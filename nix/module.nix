{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.wazuh;
  packages = import ./packages.nix {
    inherit pkgs;
    version = cfg.version;
  };
  agentConfig =
    if cfg.agent.config != "" then
      cfg.agent.config
    else
      lib.replaceStrings
        [ "@MANAGER_ADDRESS@" "@MANAGER_PORT@" "@ENROLLMENT_PORT@" ]
        [ cfg.agent.managerAddress (toString cfg.agent.managerPort) (toString cfg.agent.enrollmentPort) ]
        (lib.readFile ./ossec.conf);
  filebeatConfig =
    if cfg.filebeat.config != "" then
      cfg.filebeat.config
    else
      lib.replaceStrings
        [ "@CONFIG_DIR@" "@INDEXER_URL@" ]
        [ cfg.filebeat.configDir cfg.filebeat.indexerUrl ]
        (lib.readFile ./filebeat.yml);
  filebeatConfigFile = pkgs.writeText "wazuh-filebeat.yml" filebeatConfig;
  indexerConfigFile = pkgs.writeText "wazuh-indexer.yml" cfg.indexer.config;
  dashboardConfig =
    if cfg.dashboard.config != "" then
      cfg.dashboard.config
    else
      lib.replaceStrings
        [
          "@SERVER_HOST@"
          "@SERVER_PORT@"
          "@INDEXER_URL@"
          "@CONFIG_DIR@"
          "@DATA_DIR@"
          "@SERVER_SSL_ENABLED@"
        ]
        [
          cfg.dashboard.bindAddress
          (toString cfg.dashboard.port)
          cfg.dashboard.indexerUrl
          cfg.dashboard.configDir
          cfg.dashboard.dataDir
          (
            if cfg.dashboard.certificates.certificate != null && cfg.dashboard.certificates.key != null then
              "true"
            else
              "false"
          )
        ]
        (lib.readFile ./opensearch_dashboards.yml);
  dashboardConfigFile = pkgs.writeText "opensearch_dashboards.yml" dashboardConfig;
  dashboardAppSettingsFile = pkgs.writeText "wazuh-dashboard-app-settings.json" (
    builtins.toJSON cfg.dashboard.appSettings
  );
  indexerHealthHost =
    if cfg.indexer.bindAddress == "0.0.0.0" then
      "127.0.0.1"
    else if cfg.indexer.bindAddress == "::" then
      "[::1]"
    else if lib.hasInfix ":" cfg.indexer.bindAddress then
      "[${cfg.indexer.bindAddress}]"
    else
      cfg.indexer.bindAddress;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
in
{
  options.services.wazuh = {
    version = mkOption {
      type = types.str;
      default = "4.14.5";
      description = "Wazuh version shared by all package defaults.";
    };
    agent = {
      enable = mkEnableOption "Wazuh agent";
      package = mkOption {
        type = types.package;
        default = packages.agent;
        description = "Wazuh agent package.";
      };
      managerAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Address of the Wazuh manager.";
      };
      managerPort = mkOption {
        type = types.port;
        default = 1514;
        description = "Wazuh manager event-collection port.";
      };
      enrollmentPort = mkOption {
        type = types.port;
        default = 1515;
        description = "Wazuh manager enrollment port.";
      };
      config = mkOption {
        type = types.lines;
        default = "";
        description = "Complete ossec.conf content; an enrollment config is generated when empty.";
      };
    };

    manager = {
      enable = mkEnableOption "Wazuh manager";
      package = mkOption {
        type = types.package;
        default = packages.manager;
      };
      environmentFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Optional environment file for manager integrations and credentials.";
      };
      eventPort = mkOption {
        type = types.port;
        default = 1514;
        description = "Wazuh manager event-collection port.";
      };
      enrollmentPort = mkOption {
        type = types.port;
        default = 1515;
        description = "Wazuh manager enrollment port.";
      };
      apiPort = mkOption {
        type = types.port;
        default = 55000;
        description = "Wazuh manager API port.";
      };
      openApiPort = mkOption {
        type = types.bool;
        default = false;
        description = "Open the manager API port in the firewall.";
      };
      config = mkOption {
        type = types.lines;
        default = "";
        description = "Complete ossec.conf content; the package default is used when empty.";
      };
      certificates = {
        certificate = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Optional Wazuh enrollment server certificate.";
        };
        key = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Optional Wazuh enrollment server private key.";
        };
      };
      requireIndexer = mkOption {
        type = types.bool;
        default = true;
        description = "Require the local Wazuh indexer before starting the manager.";
      };
    };

    filebeat = {
      enable = mkEnableOption "Wazuh Filebeat alert forwarding";
      package = mkOption {
        type = types.package;
        default = packages.filebeat;
        description = "Filebeat package with the Wazuh module and index template.";
      };
      configDir = mkOption {
        type = types.path;
        default = "/etc/filebeat";
        description = "Mutable Filebeat configuration directory.";
      };
      dataDir = mkOption {
        type = types.path;
        default = "/var/lib/filebeat";
        description = "Persistent Filebeat registry and data directory.";
      };
      logDir = mkOption {
        type = types.path;
        default = "/var/log/filebeat";
        description = "Filebeat log directory.";
      };
      indexerUrl = mkOption {
        type = types.str;
        default = "https://127.0.0.1:9200";
        description = "Wazuh indexer URL receiving alerts.";
      };
      config = mkOption {
        type = types.lines;
        default = "";
        description = "Complete filebeat.yml; a Wazuh alerts configuration is generated when empty.";
      };
      environmentFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Environment file containing INDEXER_USERNAME and INDEXER_PASSWORD.";
      };
      requireManager = mkOption {
        type = types.bool;
        default = true;
        description = "Require the local Wazuh manager before forwarding alerts.";
      };
      requireIndexer = mkOption {
        type = types.bool;
        default = true;
        description = "Require the local Wazuh indexer before forwarding alerts.";
      };
      certificates = {
        rootCA = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Certificate authority used to verify the Wazuh indexer.";
        };
        certificate = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Filebeat client certificate accepted by the Wazuh indexer.";
        };
        key = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Filebeat client private key.";
        };
      };
    };

    indexer = {
      enable = mkEnableOption "Wazuh indexer";
      package = mkOption {
        type = types.package;
        default = packages.indexer;
      };
      dataDir = mkOption {
        type = types.path;
        default = "/var/lib/wazuh-indexer";
        description = "Persistent Wazuh indexer data directory.";
      };
      configDir = mkOption {
        type = types.path;
        default = "/etc/wazuh-indexer";
        description = "Mutable Wazuh indexer configuration directory.";
      };
      config = mkOption {
        type = types.lines;
        default = "";
        description = "Complete opensearch.yml; the package default is used when empty.";
      };
      certificates = {
        rootCA = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Wazuh indexer root CA certificate.";
        };
        nodeCertificate = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Wazuh indexer node certificate.";
        };
        nodeKey = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Wazuh indexer node private key.";
        };
        adminCertificate = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Wazuh indexer admin certificate.";
        };
        adminKey = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Wazuh indexer admin private key.";
        };
      };
      port = mkOption {
        type = types.port;
        default = 9200;
        description = "Wazuh indexer HTTPS port.";
      };
      bindAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Wazuh indexer listen address.";
      };
      openFirewall = mkOption {
        type = types.bool;
        default = false;
        description = "Open the Wazuh indexer port in the firewall.";
      };
      securityBootstrap = {
        enable = mkEnableOption "Wazuh indexer security bootstrap";
        initializedFile = mkOption {
          type = types.path;
          default = "/var/lib/wazuh-indexer/.security-initialized";
          description = "Marker file written after securityadmin initialization.";
        };
      };
    };

    dashboard = {
      enable = mkEnableOption "Wazuh dashboard";
      package = mkOption {
        type = types.package;
        default = packages.dashboard;
      };
      configDir = mkOption {
        type = types.path;
        default = "/etc/wazuh-dashboard";
        description = "Mutable Wazuh dashboard configuration directory.";
      };
      dataDir = mkOption {
        type = types.path;
        default = "/var/lib/wazuh-dashboard";
        description = "Persistent Wazuh dashboard data directory.";
      };
      indexerUrl = mkOption {
        type = types.str;
        default = "https://127.0.0.1:9200";
        description = "Wazuh indexer URL.";
      };
      managerApiUrl = mkOption {
        type = types.str;
        default = "https://127.0.0.1";
        description = "Wazuh manager API URL without its port.";
      };
      managerApiPort = mkOption {
        type = types.port;
        default = 55000;
        description = "Wazuh manager API port.";
      };
      managerApiRunAs = mkOption {
        type = types.bool;
        default = true;
        description = "Use the authenticated dashboard user when calling the Wazuh API.";
      };
      appSettings = mkOption {
        type = types.attrs;
        default = { };
        description = "Non-secret Wazuh dashboard application settings merged with the runtime API host.";
      };
      requireManager = mkOption {
        type = types.bool;
        default = true;
        description = "Require the local Wazuh manager before starting the dashboard.";
      };
      bindAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Dashboard listen address.";
      };
      port = mkOption {
        type = types.port;
        default = 5601;
      };
      config = mkOption {
        type = types.lines;
        default = "";
        description = "Complete opensearch_dashboards.yml; a local single-node config is generated when empty.";
      };
      environmentFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Environment file containing DASHBOARD_USERNAME, DASHBOARD_PASSWORD,
          API_USERNAME, and API_PASSWORD.
        '';
      };
      openFirewall = mkOption {
        type = types.bool;
        default = false;
        description = "Open the dashboard port in the firewall.";
      };
      certificates = {
        rootCA = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Wazuh dashboard root CA certificate.";
        };
        certificate = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Wazuh dashboard TLS certificate.";
        };
        key = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Wazuh dashboard TLS private key.";
        };
      };
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.version == "4.14.5";
          message = "Wazuh ${cfg.version} is not packaged by this flake yet.";
        }
        {
          assertion = !(cfg.agent.enable && cfg.manager.enable);
          message = "The Wazuh agent and manager cannot share the same /var/ossec runtime.";
        }
        {
          assertion = !cfg.manager.enable || !cfg.manager.requireIndexer || cfg.indexer.enable;
          message = "services.wazuh.manager.requireIndexer requires services.wazuh.indexer.enable.";
        }
        {
          assertion =
            !cfg.manager.enable || !cfg.manager.requireIndexer || cfg.manager.environmentFile != null;
          message = "A manager requiring the indexer must set services.wazuh.manager.environmentFile.";
        }
        {
          assertion =
            !cfg.manager.enable
            || (cfg.manager.certificates.certificate == null) == (cfg.manager.certificates.key == null);
          message = "Wazuh manager enrollment certificate and key must be configured together.";
        }
        {
          assertion = !cfg.indexer.securityBootstrap.enable || cfg.indexer.enable;
          message = "services.wazuh.indexer.securityBootstrap requires services.wazuh.indexer.enable.";
        }
        {
          assertion = !cfg.filebeat.enable || !cfg.filebeat.requireManager || cfg.manager.enable;
          message = "services.wazuh.filebeat.requireManager requires services.wazuh.manager.enable.";
        }
        {
          assertion = !cfg.filebeat.enable || !cfg.filebeat.requireIndexer || cfg.indexer.enable;
          message = "services.wazuh.filebeat.requireIndexer requires services.wazuh.indexer.enable.";
        }
        {
          assertion = !cfg.filebeat.enable || cfg.filebeat.environmentFile != null;
          message = "services.wazuh.filebeat.environmentFile is required when Filebeat is enabled.";
        }
        {
          assertion =
            !cfg.filebeat.enable
            || (
              cfg.filebeat.certificates.rootCA != null
              && cfg.filebeat.certificates.certificate != null
              && cfg.filebeat.certificates.key != null
            );
          message = "Wazuh Filebeat requires its root CA, certificate, and key.";
        }
        {
          assertion = !cfg.dashboard.enable || !cfg.dashboard.requireManager || cfg.manager.enable;
          message = "services.wazuh.dashboard.requireManager requires services.wazuh.manager.enable.";
        }
        {
          assertion = !cfg.dashboard.enable || cfg.indexer.enable;
          message = "services.wazuh.dashboard requires services.wazuh.indexer.enable.";
        }
        {
          assertion = !cfg.dashboard.enable || cfg.dashboard.environmentFile != null;
          message = "services.wazuh.dashboard.environmentFile is required when the dashboard is enabled.";
        }
        {
          assertion = !cfg.dashboard.enable || cfg.dashboard.certificates.rootCA != null;
          message = "The Wazuh dashboard requires the indexer root CA certificate.";
        }
        {
          assertion =
            !cfg.indexer.securityBootstrap.enable
            || (
              cfg.indexer.certificates.rootCA != null
              && cfg.indexer.certificates.nodeCertificate != null
              && cfg.indexer.certificates.nodeKey != null
              && cfg.indexer.certificates.adminCertificate != null
              && cfg.indexer.certificates.adminKey != null
            );
          message = "Wazuh indexer security bootstrap requires all indexer certificates.";
        }
      ];
    }
    (mkIf cfg.agent.enable {
      users.groups.wazuh = { };
      users.users.wazuh = {
        isSystemUser = true;
        group = "wazuh";
        home = "/var/ossec";
        shell = "${pkgs.shadow}/bin/nologin";
      };
      systemd.tmpfiles.rules = [
        "d /var/ossec 0750 root wazuh -"
        "d /var/ossec/etc 0750 root wazuh -"
        "d /var/ossec/logs 0750 wazuh wazuh -"
        "d /var/ossec/queue 0750 wazuh wazuh -"
        "d /var/ossec/queue/sockets 0770 wazuh wazuh -"
        "d /var/ossec/var 0750 wazuh wazuh -"
      ];
      environment.etc."wazuh/ossec.conf".text = agentConfig;
      systemd.services.wazuh-agent = {
        description = "Wazuh agent";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [
          pkgs.coreutils
          pkgs.gawk
          pkgs.procps
        ];
        serviceConfig = {
          Type = "forking";
          ExecStartPre = pkgs.writeShellScript "wazuh-agent-prepare" ''
            set -eu
            install -d -m 0750 -o root -g wazuh /var/ossec /var/ossec/etc
            package_marker=/var/ossec/.wazuh-agent-package
            if [ ! -f "$package_marker" ] || [ "$(cat "$package_marker")" != "${cfg.agent.package}" ]; then
              if [ -f /var/ossec/etc/client.keys ]; then
                install -m 0640 /var/ossec/etc/client.keys /run/wazuh-agent-client.keys
              fi
              cp -a --no-preserve=ownership ${cfg.agent.package}/var/ossec/. /var/ossec/
              ${cfg.agent.package}/var/ossec/packages_files/agent_installation_scripts/restore-permissions.sh
              if [ -f /run/wazuh-agent-client.keys ]; then
                install -o wazuh -g wazuh -m 0640 /run/wazuh-agent-client.keys /var/ossec/etc/client.keys
                rm -f /run/wazuh-agent-client.keys
              fi
            fi
            install -o root -g wazuh -m 0640 /etc/wazuh/ossec.conf /var/ossec/etc/ossec.conf
            printf '%s\n' "${cfg.agent.package}" > "$package_marker"
            chown root:wazuh "$package_marker"
            chmod 0640 "$package_marker"
          '';
          ExecStart = "/var/ossec/bin/wazuh-control start";
          ExecStop = "/var/ossec/bin/wazuh-control stop";
          ExecReload = "/var/ossec/bin/wazuh-control restart";
          Restart = "on-failure";
          RestartSec = 5;
          TimeoutStartSec = 120;
          TimeoutStopSec = 120;
          KillMode = "control-group";
          ReadWritePaths = [ "/var/ossec" ];
        };
      };
    })

    (mkIf cfg.manager.enable {
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
      systemd.services.wazuh-manager = {
        description = "Wazuh manager";
        wantedBy = [ "multi-user.target" ];
        requires =
          lib.optional cfg.manager.requireIndexer "wazuh-indexer.service"
          ++ lib.optional cfg.indexer.securityBootstrap.enable "wazuh-indexer-security.service"
          ++ lib.optional cfg.filebeat.enable "wazuh-filebeat-prepare.service";
        after = [
          "network-online.target"
        ]
        ++ lib.optional cfg.manager.requireIndexer "wazuh-indexer.service"
        ++ lib.optional cfg.indexer.securityBootstrap.enable "wazuh-indexer-security.service"
        ++ lib.optional cfg.filebeat.enable "wazuh-filebeat-prepare.service";
        wants = [ "network-online.target" ];
        path = [
          pkgs.coreutils
          pkgs.gawk
          pkgs.procps
        ];
        serviceConfig = {
          Type = "forking";
          ExecStartPre = pkgs.writeShellScript "wazuh-manager-prepare" ''
            set -eu
            install -d -m 0750 -o root -g wazuh /var/ossec /var/ossec/etc
            package_marker=/var/ossec/.wazuh-manager-package
            if [ ! -f "$package_marker" ] || [ "$(cat "$package_marker")" != "${cfg.manager.package}" ]; then
              if [ -f /var/ossec/etc/client.keys ]; then
                install -m 0640 /var/ossec/etc/client.keys /run/wazuh-manager-client.keys
              fi
              ${pkgs.rsync}/bin/rsync -a --no-owner --no-group \
                --exclude='/framework/python' \
                --exclude='/tmp/vd_*_vd_*.tar*' \
                ${cfg.manager.package}/var/ossec/ /var/ossec/

              install -d -m 0750 -o root -g wazuh /var/ossec/framework
              if [ ! -L /var/ossec/framework/python ]; then
                rm -rf /var/ossec/framework/python
              fi
              ln -sfnT ${cfg.manager.package}/var/ossec/framework/python /var/ossec/framework/python

              install -d -m 1770 -o root -g wazuh /var/ossec/tmp
              for vulnerability_database in ${cfg.manager.package}/var/ossec/tmp/vd_*_vd_*.tar*; do
                if [ -f "$vulnerability_database" ]; then
                  ln -sfnT "$vulnerability_database" "/var/ossec/tmp/$(basename "$vulnerability_database")"
                fi
              done

              ${pkgs.gnused}/bin/sed \
                -e '\|/var/ossec/framework/python|d' \
                -e '\|/var/ossec/tmp/vd_.*_vd_.*\.tar|d' \
                ${cfg.manager.package}/var/ossec/packages_files/manager_installation_scripts/restore-permissions.sh \
                | ${pkgs.bash}/bin/bash
              if [ -f /run/wazuh-manager-client.keys ]; then
                install -o wazuh -g wazuh -m 0640 /run/wazuh-manager-client.keys /var/ossec/etc/client.keys
                rm -f /run/wazuh-manager-client.keys
              fi
            fi
            ${lib.optionalString (cfg.manager.config != "") ''
              install -o root -g wazuh -m 0640 /etc/wazuh/manager.conf /var/ossec/etc/ossec.conf
            ''}
            ${lib.optionalString (cfg.filebeat.enable && cfg.manager.config == "") ''
              sed -i \
                's#https://0.0.0.0:9200#${cfg.filebeat.indexerUrl}#g' \
                /var/ossec/etc/ossec.conf
            ''}
            ${lib.optionalString (cfg.manager.certificates.certificate != null) ''
              install -o root -g wazuh -m 0640 ${cfg.manager.certificates.certificate} /var/ossec/etc/sslmanager.cert
              install -o root -g wazuh -m 0640 ${cfg.manager.certificates.key} /var/ossec/etc/sslmanager.key
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
            ${lib.optionalString (cfg.manager.environmentFile != null) ''
              : "''${INDEXER_USERNAME:?INDEXER_USERNAME must be set in the manager environment file}"
              : "''${INDEXER_PASSWORD:?INDEXER_PASSWORD must be set in the manager environment file}"
              printf '%s\n' "$INDEXER_USERNAME" | /var/ossec/bin/wazuh-keystore -f indexer -k username
              printf '%s\n' "$INDEXER_PASSWORD" | /var/ossec/bin/wazuh-keystore -f indexer -k password
            ''}
            printf '%s\n' "${cfg.manager.package}" > "$package_marker"
            chown root:wazuh "$package_marker"
            chmod 0640 "$package_marker"
          '';
          ExecStart = "/var/ossec/bin/wazuh-control start";
          ExecStop = "/var/ossec/bin/wazuh-control stop";
          ExecReload = "/var/ossec/bin/wazuh-control restart";
          Restart = "on-failure";
          RestartSec = 5;
          TimeoutStartSec = 300;
          TimeoutStopSec = 120;
          KillMode = "control-group";
          ReadWritePaths = [ "/var/ossec" ];
          EnvironmentFile = lib.optional (cfg.manager.environmentFile != null) cfg.manager.environmentFile;
        };
      };
      environment.etc."wazuh/manager.conf".text = cfg.manager.config;
      networking.firewall.allowedTCPPorts = [
        cfg.manager.eventPort
        cfg.manager.enrollmentPort
      ]
      ++ lib.optional cfg.manager.openApiPort cfg.manager.apiPort;
    })

    (mkIf cfg.filebeat.enable {
      systemd.tmpfiles.rules = [
        "d ${cfg.filebeat.configDir} 0750 root root -"
        "d ${cfg.filebeat.configDir}/certs 0500 root root -"
        "d ${cfg.filebeat.dataDir} 0750 root root -"
        "d ${cfg.filebeat.logDir} 0750 root root -"
      ];

      systemd.services.wazuh-filebeat-prepare = {
        description = "Prepare Wazuh Filebeat runtime files";
        before = [ "wazuh-filebeat.service" ] ++ lib.optional cfg.manager.enable "wazuh-manager.service";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          EnvironmentFile = cfg.filebeat.environmentFile;
          ExecStart = pkgs.writeShellScript "wazuh-filebeat-prepare" ''
            set -eu
            : "''${INDEXER_USERNAME:?INDEXER_USERNAME must be set in the Filebeat environment file}"
            : "''${INDEXER_PASSWORD:?INDEXER_PASSWORD must be set in the Filebeat environment file}"

            install -d -m 0750 -o root -g root ${cfg.filebeat.configDir}
            install -d -m 0500 -o root -g root ${cfg.filebeat.configDir}/certs
            install -d -m 0750 -o root -g root ${cfg.filebeat.dataDir} ${cfg.filebeat.logDir}
            install -o root -g root -m 0640 ${filebeatConfigFile} ${cfg.filebeat.configDir}/filebeat.yml
            install -o root -g root -m 0644 \
              ${cfg.filebeat.package}/etc/filebeat/wazuh-template.json \
              ${cfg.filebeat.configDir}/wazuh-template.json
            install -o root -g root -m 0400 \
              ${cfg.filebeat.certificates.rootCA} \
              ${cfg.filebeat.configDir}/certs/root-ca.pem
            install -o root -g root -m 0400 \
              ${cfg.filebeat.certificates.certificate} \
              ${cfg.filebeat.configDir}/certs/filebeat.pem
            install -o root -g root -m 0400 \
              ${cfg.filebeat.certificates.key} \
              ${cfg.filebeat.configDir}/certs/filebeat-key.pem

            filebeat=${cfg.filebeat.package}/usr/share/filebeat/bin/filebeat
            rm -f ${cfg.filebeat.dataDir}/filebeat.keystore
            "$filebeat" keystore create --force \
              --path.home ${cfg.filebeat.package}/usr/share/filebeat \
              --path.config ${cfg.filebeat.configDir} \
              --path.data ${cfg.filebeat.dataDir} \
              --path.logs ${cfg.filebeat.logDir}
            printf '%s\n' "$INDEXER_USERNAME" | "$filebeat" keystore add username --stdin --force \
              --path.home ${cfg.filebeat.package}/usr/share/filebeat \
              --path.config ${cfg.filebeat.configDir} \
              --path.data ${cfg.filebeat.dataDir} \
              --path.logs ${cfg.filebeat.logDir}
            printf '%s\n' "$INDEXER_PASSWORD" | "$filebeat" keystore add password --stdin --force \
              --path.home ${cfg.filebeat.package}/usr/share/filebeat \
              --path.config ${cfg.filebeat.configDir} \
              --path.data ${cfg.filebeat.dataDir} \
              --path.logs ${cfg.filebeat.logDir}
            chmod 0600 ${cfg.filebeat.dataDir}/filebeat.keystore
          '';
        };
      };

      systemd.services.wazuh-filebeat = {
        description = "Wazuh Filebeat alert forwarding";
        wantedBy = [ "multi-user.target" ];
        requires = [
          "wazuh-filebeat-prepare.service"
        ]
        ++ lib.optional cfg.filebeat.requireManager "wazuh-manager.service"
        ++ lib.optional cfg.filebeat.requireIndexer "wazuh-indexer.service"
        ++ lib.optional cfg.indexer.securityBootstrap.enable "wazuh-indexer-security.service";
        after = [
          "network-online.target"
          "wazuh-filebeat-prepare.service"
        ]
        ++ lib.optional cfg.filebeat.requireManager "wazuh-manager.service"
        ++ lib.optional cfg.filebeat.requireIndexer "wazuh-indexer.service"
        ++ lib.optional cfg.indexer.securityBootstrap.enable "wazuh-indexer-security.service";
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${cfg.filebeat.package}/usr/share/filebeat/bin/filebeat --environment systemd --path.home ${cfg.filebeat.package}/usr/share/filebeat --path.config ${cfg.filebeat.configDir} --path.data ${cfg.filebeat.dataDir} --path.logs ${cfg.filebeat.logDir} -c filebeat.yml -e";
          Restart = "on-failure";
          RestartSec = 5;
          TimeoutStartSec = 120;
          TimeoutStopSec = 30;
          KillMode = "control-group";
          UMask = "0077";
          ReadWritePaths = [
            cfg.filebeat.dataDir
            cfg.filebeat.logDir
          ];
        };
      };
    })

    (mkIf cfg.indexer.enable {
      users.groups.wazuh-indexer = { };
      users.users.wazuh-indexer = {
        isSystemUser = true;
        group = "wazuh-indexer";
        home = cfg.indexer.dataDir;
      };
      boot.kernel.sysctl."vm.max_map_count" = 262144;
      systemd.tmpfiles.rules = [
        "d ${cfg.indexer.dataDir} 0750 wazuh-indexer wazuh-indexer -"
        "d /var/log/wazuh-indexer 0750 wazuh-indexer wazuh-indexer -"
        "d ${cfg.indexer.configDir} 0750 wazuh-indexer wazuh-indexer -"
        "d ${cfg.indexer.configDir}/certs 0500 wazuh-indexer wazuh-indexer -"
      ];
      systemd.services.wazuh-indexer-prepare = {
        description = "Prepare Wazuh indexer runtime files";
        wantedBy = [ "multi-user.target" ];
        before = [ "wazuh-indexer.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "wazuh-indexer-prepare" ''
            set -eu
            install -d -m 0750 -o wazuh-indexer -g wazuh-indexer ${cfg.indexer.configDir}
            if [ -d ${cfg.indexer.package}/etc/wazuh-indexer ]; then
              cp -a --no-clobber ${cfg.indexer.package}/etc/wazuh-indexer/. ${cfg.indexer.configDir}/
            fi
            install -d -m 0500 -o wazuh-indexer -g wazuh-indexer ${cfg.indexer.configDir}/certs
            ${lib.optionalString (cfg.indexer.certificates.rootCA != null) ''
              install -o wazuh-indexer -g wazuh-indexer -m 0400 ${cfg.indexer.certificates.rootCA} ${cfg.indexer.configDir}/certs/root-ca.pem
            ''}
            ${lib.optionalString (cfg.indexer.certificates.nodeCertificate != null) ''
              install -o wazuh-indexer -g wazuh-indexer -m 0400 ${cfg.indexer.certificates.nodeCertificate} ${cfg.indexer.configDir}/certs/indexer.pem
            ''}
            ${lib.optionalString (cfg.indexer.certificates.nodeKey != null) ''
              install -o wazuh-indexer -g wazuh-indexer -m 0400 ${cfg.indexer.certificates.nodeKey} ${cfg.indexer.configDir}/certs/indexer-key.pem
            ''}
            ${lib.optionalString (cfg.indexer.certificates.adminCertificate != null) ''
              install -o wazuh-indexer -g wazuh-indexer -m 0400 ${cfg.indexer.certificates.adminCertificate} ${cfg.indexer.configDir}/certs/admin.pem
            ''}
            ${lib.optionalString (cfg.indexer.certificates.adminKey != null) ''
              install -o wazuh-indexer -g wazuh-indexer -m 0400 ${cfg.indexer.certificates.adminKey} ${cfg.indexer.configDir}/certs/admin-key.pem
            ''}
            ${lib.optionalString (cfg.indexer.config != "") ''
              install -o wazuh-indexer -g wazuh-indexer -m 0640 ${indexerConfigFile} ${cfg.indexer.configDir}/opensearch.yml
            ''}
            chown -R wazuh-indexer:wazuh-indexer ${cfg.indexer.configDir}
            ${pkgs.findutils}/bin/find ${cfg.indexer.configDir} -type d -exec chmod 0700 {} +
            ${pkgs.findutils}/bin/find ${cfg.indexer.configDir} -type f -exec chmod 0600 {} +
            if [ ! -e ${cfg.indexer.configDir}/opensearch.keystore ]; then
              ${pkgs.util-linux}/bin/runuser -u wazuh-indexer -- \
                ${pkgs.coreutils}/bin/env \
                  OPENSEARCH_PATH_CONF=${cfg.indexer.configDir} \
                  OPENSEARCH_JAVA_HOME=${cfg.indexer.package}/usr/share/wazuh-indexer/jdk \
                  ${cfg.indexer.package}/usr/share/wazuh-indexer/bin/opensearch-keystore create
            fi
            ${pkgs.util-linux}/bin/runuser -u wazuh-indexer -- \
              ${pkgs.coreutils}/bin/env \
                OPENSEARCH_PATH_CONF=${cfg.indexer.configDir} \
                OPENSEARCH_JAVA_HOME=${cfg.indexer.package}/usr/share/wazuh-indexer/jdk \
                ${cfg.indexer.package}/usr/share/wazuh-indexer/bin/opensearch-keystore upgrade
            install -d -m 0750 -o wazuh-indexer -g wazuh-indexer ${cfg.indexer.dataDir}
          '';
        };
      };
      systemd.services.wazuh-indexer = {
        description = "Wazuh indexer";
        wantedBy = [ "multi-user.target" ];
        requires = [ "wazuh-indexer-prepare.service" ];
        after = [
          "network-online.target"
          "wazuh-indexer-prepare.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "simple";
          User = "wazuh-indexer";
          Group = "wazuh-indexer";
          WorkingDirectory = cfg.indexer.dataDir;
          ExecStart = "${cfg.indexer.package}/usr/share/wazuh-indexer/bin/opensearch -Enetwork.host=${cfg.indexer.bindAddress} -Ehttp.port=${toString cfg.indexer.port} -Epath.data=${cfg.indexer.dataDir} -Epath.logs=/var/log/wazuh-indexer";
          ExecStartPost = pkgs.writeShellScript "wazuh-indexer-healthcheck" ''
            set -eu
            for attempt in $(seq 1 60); do
              status=$(${pkgs.curl}/bin/curl -k -s -o /dev/null -w '%{http_code}' \
                "https://${indexerHealthHost}:${toString cfg.indexer.port}/" || true)
              # The security plugin returns 503 until securityadmin initializes it.
              if [ "$status" = 200 ] || [ "$status" = 401 ] || [ "$status" = 403 ] || [ "$status" = 503 ]; then
                exit 0
              fi
              sleep 2
            done
            echo "Wazuh indexer did not become ready" >&2
            exit 1
          '';
          Restart = "on-failure";
          LimitMEMLOCK = "infinity";
          LimitNOFILE = 65535;
          TimeoutStartSec = 180;
          TimeoutStopSec = 60;
          KillMode = "control-group";
          ReadWritePaths = [
            cfg.indexer.configDir
            cfg.indexer.dataDir
            "/var/log/wazuh-indexer"
          ];
          Environment = [
            "OPENSEARCH_PATH_CONF=${cfg.indexer.configDir}"
            "OPENSEARCH_JAVA_HOME=${cfg.indexer.package}/usr/share/wazuh-indexer/jdk"
          ];
        };
      };
      systemd.services.wazuh-indexer-security = mkIf cfg.indexer.securityBootstrap.enable {
        description = "Initialize Wazuh indexer security configuration";
        wantedBy = [ "multi-user.target" ];
        requires = [
          "wazuh-indexer.service"
          "wazuh-indexer-prepare.service"
        ];
        after = [ "wazuh-indexer.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Environment = "OPENSEARCH_JAVA_HOME=${cfg.indexer.package}/usr/share/wazuh-indexer/jdk";
          ExecStart = pkgs.writeShellScript "wazuh-indexer-security-bootstrap" ''
            set -eu
            if [ -e ${cfg.indexer.securityBootstrap.initializedFile} ]; then
              exit 0
            fi
            ${cfg.indexer.package}/usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
              -cd ${cfg.indexer.configDir}/opensearch-security \
              -icl -nhnv \
              -cacert ${cfg.indexer.configDir}/certs/root-ca.pem \
              -cert ${cfg.indexer.configDir}/certs/admin.pem \
              -key ${cfg.indexer.configDir}/certs/admin-key.pem
            install -D -m 0640 -o wazuh-indexer -g wazuh-indexer /dev/null ${cfg.indexer.securityBootstrap.initializedFile}
          '';
        };
      };
      networking.firewall.allowedTCPPorts = lib.optional cfg.indexer.openFirewall cfg.indexer.port;
    })

    (mkIf cfg.dashboard.enable {
      users.groups.wazuh-dashboard = { };
      users.users.wazuh-dashboard = {
        isSystemUser = true;
        group = "wazuh-dashboard";
        home = "/var/lib/wazuh-dashboard";
      };
      systemd.tmpfiles.rules = [
        "d ${cfg.dashboard.dataDir} 0750 wazuh-dashboard wazuh-dashboard -"
        "d ${cfg.dashboard.configDir} 0750 root wazuh-dashboard -"
        "d ${cfg.dashboard.configDir}/certs 0500 wazuh-dashboard wazuh-dashboard -"
      ];
      systemd.services.wazuh-dashboard-prepare = {
        description = "Prepare Wazuh dashboard runtime files";
        wantedBy = [ "multi-user.target" ];
        before = [ "wazuh-dashboard.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          EnvironmentFile = cfg.dashboard.environmentFile;
          ExecStart = pkgs.writeShellScript "wazuh-dashboard-prepare" ''
            set -eu
            : "''${DASHBOARD_USERNAME:?DASHBOARD_USERNAME must be set in the dashboard environment file}"
            : "''${DASHBOARD_PASSWORD:?DASHBOARD_PASSWORD must be set in the dashboard environment file}"
            : "''${API_USERNAME:?API_USERNAME must be set in the dashboard environment file}"
            : "''${API_PASSWORD:?API_PASSWORD must be set in the dashboard environment file}"

            install -d -m 0750 -o root -g wazuh-dashboard ${cfg.dashboard.configDir}
            if [ -d ${cfg.dashboard.package}/etc/wazuh-dashboard ]; then
              cp -a --no-clobber ${cfg.dashboard.package}/etc/wazuh-dashboard/. ${cfg.dashboard.configDir}/
            fi
            chown root:wazuh-dashboard ${cfg.dashboard.configDir}
            chmod 0750 ${cfg.dashboard.configDir}
            install -d -m 0750 -o wazuh-dashboard -g wazuh-dashboard ${cfg.dashboard.dataDir}
            if [ -d ${cfg.dashboard.package}/usr/share/wazuh-dashboard/data ]; then
              cp -a --no-clobber \
                ${cfg.dashboard.package}/usr/share/wazuh-dashboard/data/. \
                ${cfg.dashboard.dataDir}/
            fi
            chown -R wazuh-dashboard:wazuh-dashboard ${cfg.dashboard.dataDir}
            chmod -R u+rwX,g+rX,o-rwx ${cfg.dashboard.dataDir}

            install -d -m 0500 -o wazuh-dashboard -g wazuh-dashboard ${cfg.dashboard.configDir}/certs
            ${lib.optionalString (cfg.dashboard.certificates.rootCA != null) ''
              install -o wazuh-dashboard -g wazuh-dashboard -m 0400 ${cfg.dashboard.certificates.rootCA} ${cfg.dashboard.configDir}/certs/root-ca.pem
            ''}
            ${lib.optionalString (cfg.dashboard.certificates.certificate != null) ''
              install -o wazuh-dashboard -g wazuh-dashboard -m 0400 ${cfg.dashboard.certificates.certificate} ${cfg.dashboard.configDir}/certs/dashboard.pem
            ''}
            ${lib.optionalString (cfg.dashboard.certificates.key != null) ''
              install -o wazuh-dashboard -g wazuh-dashboard -m 0400 ${cfg.dashboard.certificates.key} ${cfg.dashboard.configDir}/certs/dashboard-key.pem
            ''}
            install -o root -g wazuh-dashboard -m 0640 ${dashboardConfigFile} ${cfg.dashboard.configDir}/opensearch_dashboards.yml

            export OPENSEARCH_DASHBOARDS_PATH_CONF=${cfg.dashboard.configDir}
            keystore=${cfg.dashboard.package}/usr/share/wazuh-dashboard/bin/opensearch-dashboards-keystore
            rm -f ${cfg.dashboard.configDir}/opensearch_dashboards.keystore
            "$keystore" create --allow-root
            printf '%s\n' "$DASHBOARD_USERNAME" | \
              "$keystore" add opensearch.username --stdin --allow-root
            printf '%s\n' "$DASHBOARD_PASSWORD" | \
              "$keystore" add opensearch.password --stdin --allow-root
            chown wazuh-dashboard:wazuh-dashboard ${cfg.dashboard.configDir}/opensearch_dashboards.keystore
            chmod 0600 ${cfg.dashboard.configDir}/opensearch_dashboards.keystore

            install -d -m 0700 -o wazuh-dashboard -g wazuh-dashboard \
              ${cfg.dashboard.dataDir}/wazuh \
              ${cfg.dashboard.dataDir}/wazuh/config
            ${pkgs.jq}/bin/jq \
              --arg url ${lib.escapeShellArg cfg.dashboard.managerApiUrl} \
              --argjson port ${toString cfg.dashboard.managerApiPort} \
              --arg username "$API_USERNAME" \
              --arg password "$API_PASSWORD" \
              --argjson run_as ${if cfg.dashboard.managerApiRunAs then "true" else "false"} \
              '. + {hosts: [{"1513629884013": {url: $url, port: $port, username: $username, password: $password, run_as: $run_as}}]}' \
              ${dashboardAppSettingsFile} \
              > ${cfg.dashboard.dataDir}/wazuh/config/wazuh.yml
            chown wazuh-dashboard:wazuh-dashboard ${cfg.dashboard.dataDir}/wazuh/config/wazuh.yml
            chmod 0600 ${cfg.dashboard.dataDir}/wazuh/config/wazuh.yml
          '';
        };
      };
      systemd.services.wazuh-dashboard = {
        description = "Wazuh dashboard";
        wantedBy = [ "multi-user.target" ];
        requires = [
          "wazuh-dashboard-prepare.service"
          "wazuh-indexer.service"
        ]
        ++ lib.optional cfg.dashboard.requireManager "wazuh-manager.service"
        ++ lib.optional cfg.indexer.securityBootstrap.enable "wazuh-indexer-security.service";
        after = [
          "network-online.target"
          "wazuh-dashboard-prepare.service"
          "wazuh-indexer.service"
        ]
        ++ lib.optional cfg.dashboard.requireManager "wazuh-manager.service"
        ++ lib.optional cfg.indexer.securityBootstrap.enable "wazuh-indexer-security.service";
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "simple";
          User = "wazuh-dashboard";
          Group = "wazuh-dashboard";
          WorkingDirectory = cfg.dashboard.dataDir;
          ExecStart = "${cfg.dashboard.package}/usr/share/wazuh-dashboard/bin/opensearch-dashboards";
          ExecStartPost = pkgs.writeShellScript "wazuh-dashboard-healthcheck" ''
            set -eu
            for attempt in $(seq 1 60); do
              status=$(${pkgs.curl}/bin/curl -k -s -o /dev/null -w '%{http_code}' \
                "${
                  if cfg.dashboard.certificates.certificate != null && cfg.dashboard.certificates.key != null then
                    "https"
                  else
                    "http"
                }://127.0.0.1:${toString cfg.dashboard.port}/api/status" || true)
              if [ "$status" = 200 ] || [ "$status" = 401 ] || [ "$status" = 403 ]; then
                exit 0
              fi
              sleep 2
            done
            echo "Wazuh dashboard did not become ready" >&2
            exit 1
          '';
          Restart = "on-failure";
          RestartSec = 5;
          TimeoutStartSec = 180;
          TimeoutStopSec = 30;
          KillMode = "control-group";
          Environment = [
            "OPENSEARCH_DASHBOARDS_PATH_CONF=${cfg.dashboard.configDir}"
          ];
        };
      };
      networking.firewall.allowedTCPPorts = lib.optional cfg.dashboard.openFirewall cfg.dashboard.port;
    })
  ];
}
