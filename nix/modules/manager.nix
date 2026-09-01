{
  config,
  lib,
  pkgs,
  ...
}:

let
  wazuhCfg = config.services.wazuh;
  cfg = wazuhCfg.manager;
  credentialCfg = wazuhCfg.credentials.autoProvision;
  packages = import ../packages.nix {
    inherit pkgs;
    version = wazuhCfg.version;
  };
  managerStop = pkgs.writeShellScript "wazuh-manager-stop" /* bash */ ''
    set -eu

    modulesd_pids=()
    for pid_file in /var/ossec/var/run/wazuh-modulesd-*.pid; do
      [ -e "$pid_file" ] || continue
      while IFS= read -r pid; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
          modulesd_pids+=("$pid")
        fi
      done < "$pid_file"
    done

    if [ "''${#modulesd_pids[@]}" -gt 0 ]; then
      # Wazuh 4.14.7 aborts in the inventory teardown handler when the
      # indexer integration is enabled. Avoid the faulty handler until the
      # upstream binary provides a safe shutdown path.
      kill -${if cfg.requireIndexer then "KILL" else "TERM"} "''${modulesd_pids[@]}"

      remaining=30
      while [ "$remaining" -gt 0 ]; do
        running=false
        for pid in "''${modulesd_pids[@]}"; do
          if kill -0 "$pid" 2>/dev/null; then
            running=true
            break
          fi
        done
        [ "$running" = true ] || break
        sleep 1
        remaining=$((remaining - 1))
      done
    fi

    exec /var/ossec/bin/wazuh-control stop
  '';
  managerReady = pkgs.writeShellScript "wazuh-manager-ready" /* bash */ ''
    set -eu

    log_file=/var/ossec/logs/ossec.log
    read -r log_offset fingerprint_size log_fingerprint < /run/wazuh-manager-log-state
    remaining=300

    while [ "$remaining" -gt 0 ]; do
      if [ -f "$log_file" ]; then
        current_size=$(stat -c %s "$log_file")
        if [ "$current_size" -lt "$log_offset" ]; then
          log_offset=0
        elif [ "$fingerprint_size" -gt 0 ]; then
          fingerprint_offset=$((log_offset - fingerprint_size))
          current_fingerprint=$(dd if="$log_file" bs=1 skip="$fingerprint_offset" count="$fingerprint_size" status=none | sha256sum | awk '{print $1}')
          if [ "$current_fingerprint" != "$log_fingerprint" ]; then
            log_offset=0
          fi
        fi

        if tail -c "+$((log_offset + 1))" "$log_file" \
          | grep -Fq 'InventoryHarvesterFacade module started.'; then
          exit 0
        fi
        if tail -c "+$((log_offset + 1))" "$log_file" \
          | grep -Fq 'InventoryHarvesterFacade::start:'; then
          echo "Wazuh inventory harvester failed during manager startup" >&2
          exit 1
        fi
      fi

      sleep 1
      remaining=$((remaining - 1))
    done

    echo "Timed out waiting for the Wazuh inventory harvester" >&2
    exit 1
  '';
in
{
  options.services.wazuh.manager = {
    enable = lib.mkEnableOption "Wazuh manager";
    package = lib.mkOption {
      type = lib.types.package;
      default = packages.manager;
    };
    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional environment file for manager integrations and credentials.";
    };
    eventPort = lib.mkOption {
      type = lib.types.port;
      default = 1514;
      description = "Wazuh manager event-collection port.";
    };
    enrollmentPort = lib.mkOption {
      type = lib.types.port;
      default = 1515;
      description = "Wazuh manager enrollment port.";
    };
    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 55000;
      description = "Wazuh manager API port.";
    };
    openApiPort = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the manager API port in the firewall.";
    };
    config = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Complete ossec.conf content; the package default is used when empty.";
    };
    certificates = {
      certificate = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Optional Wazuh enrollment server certificate.";
      };
      key = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Optional Wazuh enrollment server private key.";
      };
    };
    requireIndexer = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Require the local Wazuh indexer before starting the manager.";
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !cfg.enable || !cfg.requireIndexer || wazuhCfg.indexer.enable;
          message = "services.wazuh.manager.requireIndexer requires services.wazuh.indexer.enable.";
        }
        {
          assertion = !cfg.enable || !cfg.requireIndexer || cfg.environmentFile != null;
          message = "A manager requiring the indexer must set services.wazuh.manager.environmentFile.";
        }
        {
          assertion = !cfg.enable || (cfg.certificates.certificate == null) == (cfg.certificates.key == null);
          message = "Wazuh manager enrollment certificate and key must be configured together.";
        }
      ];
    }
    (lib.mkIf cfg.enable {
      users.groups.wazuh = { };
      users.users.wazuh = {
        isSystemUser = true;
        group = "wazuh";
        home = "/var/ossec";
      };
      systemd.tmpfiles.rules = [
        "d /var/ossec 0750 root wazuh -"
        "d /var/ossec/etc 0750 root wazuh -"
        "d /var/ossec/logs 0750 wazuh wazuh -"
        "d /var/ossec/queue 0750 wazuh wazuh -"
        "d /var/ossec/queue/sockets 0770 wazuh wazuh -"
        "d /var/ossec/var 0750 wazuh wazuh -"
      ];
      systemd.services.wazuh-manager-prepare = {
        description = "Prepare Wazuh manager runtime files and credentials";
        before = [ "wazuh-manager.service" ];
        requires = lib.optional credentialCfg.enable "wazuh-credentials.service";
        after = lib.optional credentialCfg.enable "wazuh-credentials.service";
        path = [
          pkgs.coreutils
          pkgs.gawk
          pkgs.procps
        ];
        serviceConfig = {
          Type = "oneshot";
          EnvironmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
          UMask = "0077";
          ExecStart = pkgs.writeShellScript "wazuh-manager-prepare" ''
            set -eu
            install -d -m 0750 -o root -g wazuh /var/ossec /var/ossec/etc
            package_marker=/var/ossec/.wazuh-manager-package
            if [ ! -f "$package_marker" ] || [ "$(cat "$package_marker")" != "${cfg.package}" ]; then
              if [ -f /var/ossec/etc/client.keys ]; then
                install -m 0640 /var/ossec/etc/client.keys /run/wazuh-manager-client.keys
              fi
              ${pkgs.rsync}/bin/rsync -a --no-owner --no-group \
                --exclude='/framework/python' \
                --exclude='/tmp/vd_*_vd_*.tar*' \
                ${cfg.package}/var/ossec/ /var/ossec/

              install -d -m 0750 -o root -g wazuh /var/ossec/framework
              if [ ! -L /var/ossec/framework/python ]; then
                rm -rf /var/ossec/framework/python
              fi
              ln -sfnT ${cfg.package}/var/ossec/framework/python /var/ossec/framework/python

              install -d -m 1770 -o root -g wazuh /var/ossec/tmp
              for vulnerability_database in ${cfg.package}/var/ossec/tmp/vd_*_vd_*.tar*; do
                if [ -f "$vulnerability_database" ]; then
                  ln -sfnT "$vulnerability_database" "/var/ossec/tmp/$(basename "$vulnerability_database")"
                fi
              done

              ${pkgs.gnused}/bin/sed \
                -e '\|/var/ossec/framework/python|d' \
                -e '\|/var/ossec/tmp/vd_.*_vd_.*\.tar|d' \
                ${cfg.package}/var/ossec/packages_files/manager_installation_scripts/restore-permissions.sh \
                | ${pkgs.bash}/bin/bash
              if [ -f /run/wazuh-manager-client.keys ]; then
                install -o wazuh -g wazuh -m 0640 /run/wazuh-manager-client.keys /var/ossec/etc/client.keys
                rm -f /run/wazuh-manager-client.keys
              fi
            fi
            ${lib.optionalString (cfg.config != "") ''
              install -o root -g wazuh -m 0640 /etc/wazuh/manager.conf /var/ossec/etc/ossec.conf
            ''}
            ${lib.optionalString (wazuhCfg.filebeat.enable && cfg.config == "") ''
              sed -i \
                's#https://0.0.0.0:9200#${wazuhCfg.filebeat.indexerUrl}#g' \
                /var/ossec/etc/ossec.conf
            ''}
            ${lib.optionalString (cfg.certificates.certificate != null) ''
              install -o root -g wazuh -m 0640 ${cfg.certificates.certificate} /var/ossec/etc/sslmanager.cert
              install -o root -g wazuh -m 0640 ${cfg.certificates.key} /var/ossec/etc/sslmanager.key
            ''}
            if [ ! -f /var/ossec/etc/sslmanager.cert ] || [ ! -f /var/ossec/etc/sslmanager.key ]; then
              rm -f /var/ossec/etc/sslmanager.cert /var/ossec/etc/sslmanager.key
              /var/ossec/bin/wazuh-authd \
                -C 365 \
                -B 2048 \
                -K /var/ossec/etc/sslmanager.key \
                -X /var/ossec/etc/sslmanager.cert \
                -S "/C=US/ST=California/CN=wazuh/"
              chown root:wazuh /var/ossec/etc/sslmanager.cert /var/ossec/etc/sslmanager.key
              chmod 0640 /var/ossec/etc/sslmanager.cert /var/ossec/etc/sslmanager.key
            fi
            ${lib.optionalString (cfg.environmentFile != null) ''
              : "''${INDEXER_USERNAME:?INDEXER_USERNAME must be set in the manager environment file}"
              : "''${INDEXER_PASSWORD:?INDEXER_PASSWORD must be set in the manager environment file}"
              printf '%s\n' "$INDEXER_USERNAME" | /var/ossec/bin/wazuh-keystore -f indexer -k username
              printf '%s\n' "$INDEXER_PASSWORD" | /var/ossec/bin/wazuh-keystore -f indexer -k password
            ''}
            printf '%s\n' "${cfg.package}" > "$package_marker"
            chown root:wazuh "$package_marker"
            chmod 0640 "$package_marker"
            log_file=/var/ossec/logs/ossec.log
            log_offset=0
            fingerprint_size=0
            log_fingerprint=-
            if [ -f "$log_file" ]; then
              log_offset=$(stat -c %s "$log_file")
              if [ "$log_offset" -gt 0 ]; then
                fingerprint_size=$((log_offset < 4096 ? log_offset : 4096))
                fingerprint_offset=$((log_offset - fingerprint_size))
                log_fingerprint=$(dd if="$log_file" bs=1 skip="$fingerprint_offset" count="$fingerprint_size" status=none | sha256sum | awk '{print $1}')
              fi
            fi
            printf '%s %s %s\n' "$log_offset" "$fingerprint_size" "$log_fingerprint" > /run/wazuh-manager-log-state
            chmod 0600 /run/wazuh-manager-log-state
          '';
        };
      };
      systemd.services.wazuh-manager = {
        description = "Wazuh manager";
        wantedBy = [ "multi-user.target" ];
        requires = [
          "wazuh-manager-prepare.service"
        ]
        ++ lib.optional cfg.requireIndexer "wazuh-indexer.service"
        ++ lib.optional wazuhCfg.indexer.securityBootstrap.enable "wazuh-indexer-security.service"
        ++ lib.optional wazuhCfg.filebeat.enable "wazuh-filebeat-prepare.service";
        after = [
          "network-online.target"
          "wazuh-manager-prepare.service"
        ]
        ++ lib.optional cfg.requireIndexer "wazuh-indexer.service"
        ++ lib.optional wazuhCfg.indexer.securityBootstrap.enable "wazuh-indexer-security.service"
        ++ lib.optional wazuhCfg.filebeat.enable "wazuh-filebeat-prepare.service";
        wants = [ "network-online.target" ];
        path = [
          pkgs.coreutils
          pkgs.gawk
          pkgs.gnugrep
          pkgs.procps
        ];
        serviceConfig = {
          Type = "forking";
          ExecStart = "/var/ossec/bin/wazuh-control start";
          ExecStop = managerStop;
          ExecReload = "/var/ossec/bin/wazuh-control restart";
          Restart = "on-failure";
          RestartSec = 5;
          TimeoutStartSec = 420;
          TimeoutStopSec = 120;
          KillMode = "control-group";
          ReadWritePaths = [ "/var/ossec" ];
        }
        // lib.optionalAttrs cfg.requireIndexer {
          ExecStartPost = managerReady;
        };
      };
      environment.etc."wazuh/manager.conf".text = cfg.config;
      networking.firewall.allowedTCPPorts = [
        cfg.eventPort
        cfg.enrollmentPort
      ]
      ++ lib.optional cfg.openApiPort cfg.apiPort;
    })
  ];
}
