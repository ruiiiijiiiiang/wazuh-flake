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
          "@SERVER_SSL_ENABLED@"
        ]
        [
          cfg.dashboard.bindAddress
          (toString cfg.dashboard.port)
          cfg.dashboard.indexerUrl
          cfg.dashboard.configDir
          (
            if cfg.dashboard.certificates.certificate != null && cfg.dashboard.certificates.key != null then
              "true"
            else
              "false"
          )
        ]
        (lib.readFile ./opensearch_dashboards.yml);
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
      requireIndexer = mkOption {
        type = types.bool;
        default = true;
        description = "Require the local Wazuh indexer before starting the manager.";
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
        default = "https://127.0.0.1:55000";
        description = "Wazuh manager API URL.";
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
        description = "Optional environment file for dashboard credentials and integrations.";
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
          assertion = !cfg.manager.requireIndexer || cfg.indexer.enable;
          message = "services.wazuh.manager.requireIndexer requires services.wazuh.indexer.enable.";
        }
        {
          assertion = !cfg.indexer.securityBootstrap.enable || cfg.indexer.enable;
          message = "services.wazuh.indexer.securityBootstrap requires services.wazuh.indexer.enable.";
        }
        {
          assertion = !cfg.dashboard.requireManager || cfg.manager.enable;
          message = "services.wazuh.dashboard.requireManager requires services.wazuh.manager.enable.";
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
        "d /var/ossec/var 0750 wazuh wazuh -"
      ];
      environment.etc."wazuh/ossec.conf".text = agentConfig;
      systemd.services.wazuh-agent = {
        description = "Wazuh agent";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "forking";
          ExecStartPre = pkgs.writeShellScript "wazuh-agent-prepare" ''
            set -eu
            install -d -m 0750 -o root -g wazuh /var/ossec /var/ossec/etc
            if [ -f /var/ossec/etc/client.keys ]; then
              install -m 0640 /var/ossec/etc/client.keys /tmp/wazuh-client.keys
            fi
            cp -a --no-preserve=ownership ${cfg.agent.package}/var/ossec/. /var/ossec/
            if [ -f /tmp/wazuh-client.keys ]; then
              install -o wazuh -g wazuh -m 0640 /tmp/wazuh-client.keys /var/ossec/etc/client.keys
              rm -f /tmp/wazuh-client.keys
            fi
            install -o root -g wazuh -m 0640 /etc/wazuh/ossec.conf /var/ossec/etc/ossec.conf
            chown -R root:wazuh /var/ossec
            chown -R wazuh:wazuh /var/ossec/logs /var/ossec/queue /var/ossec/var
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
      networking.firewall.allowedTCPPorts = [
        cfg.agent.managerPort
        cfg.agent.enrollmentPort
      ];
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
        "d /var/ossec/var 0750 wazuh wazuh -"
      ];
      systemd.services.wazuh-manager = {
        description = "Wazuh manager";
        wantedBy = [ "multi-user.target" ];
        requires =
          lib.optional cfg.manager.requireIndexer "wazuh-indexer.service"
          ++ lib.optional cfg.indexer.securityBootstrap.enable "wazuh-indexer-security.service";
        after = [
          "network-online.target"
        ]
        ++ lib.optional cfg.manager.requireIndexer "wazuh-indexer.service"
        ++ lib.optional cfg.indexer.securityBootstrap.enable "wazuh-indexer-security.service";
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "forking";
          ExecStartPre = pkgs.writeShellScript "wazuh-manager-prepare" ''
            set -eu
            install -d -m 0750 -o root -g wazuh /var/ossec /var/ossec/etc
            if [ -f /var/ossec/etc/client.keys ]; then
              install -m 0640 /var/ossec/etc/client.keys /tmp/wazuh-manager-client.keys
            fi
            cp -a --no-preserve=ownership ${cfg.manager.package}/var/ossec/. /var/ossec/
            if [ -f /tmp/wazuh-manager-client.keys ]; then
              install -o wazuh -g wazuh -m 0640 /tmp/wazuh-manager-client.keys /var/ossec/etc/client.keys
              rm -f /tmp/wazuh-manager-client.keys
            fi
            ${lib.optionalString (cfg.manager.config != "") ''
              install -o root -g wazuh -m 0640 /etc/wazuh/manager.conf /var/ossec/etc/ossec.conf
            ''}
            chown -R root:wazuh /var/ossec
            chown -R wazuh:wazuh /var/ossec/logs /var/ossec/queue /var/ossec/var
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
        "d ${cfg.indexer.configDir} 0750 root wazuh-indexer -"
        "d ${cfg.indexer.configDir}/certs 0500 wazuh-indexer wazuh-indexer -"
      ];
      environment.etc = lib.mkIf (cfg.indexer.config != "") {
        "wazuh-indexer/opensearch.yml".text = cfg.indexer.config;
      };
      systemd.services.wazuh-indexer-prepare = {
        description = "Prepare Wazuh indexer runtime files";
        wantedBy = [ "multi-user.target" ];
        before = [ "wazuh-indexer.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "wazuh-indexer-prepare" ''
            set -eu
            install -d -m 0750 -o root -g wazuh-indexer ${cfg.indexer.configDir}
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
              install -o root -g wazuh-indexer -m 0640 /etc/wazuh-indexer/opensearch.yml ${cfg.indexer.configDir}/opensearch.yml
            ''}
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
          ExecStart = "${cfg.indexer.package}/usr/share/wazuh-indexer/bin/opensearch";
          ExecStartPost = pkgs.writeShellScript "wazuh-indexer-healthcheck" ''
            set -eu
            for attempt in $(seq 1 60); do
              status=$(${pkgs.curl}/bin/curl -k -s -o /dev/null -w '%{http_code}' \
                "https://127.0.0.1:${toString cfg.indexer.port}/" || true)
              if [ "$status" = 200 ] || [ "$status" = 401 ] || [ "$status" = 403 ]; then
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
          Environment = [
            "OPENSEARCH_PATH_CONF=${cfg.indexer.configDir}"
            "OPENSEARCH_JAVA_HOME=${cfg.indexer.package}/usr/share/wazuh-indexer/jdk"
            "OPENSEARCH_JAVA_OPTS=-Xms1g -Xmx1g"
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
      networking.firewall.allowedTCPPorts = [ cfg.indexer.port ];
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
      environment.etc = {
        "wazuh-dashboard/opensearch_dashboards.yml".text = dashboardConfig;
      };
      systemd.services.wazuh-dashboard-prepare = {
        description = "Prepare Wazuh dashboard runtime files";
        wantedBy = [ "multi-user.target" ];
        before = [ "wazuh-dashboard.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "wazuh-dashboard-prepare" ''
            set -eu
            install -d -m 0750 -o root -g wazuh-dashboard ${cfg.dashboard.configDir}
            if [ -d ${cfg.dashboard.package}/etc/wazuh-dashboard ]; then
              cp -a --no-clobber ${cfg.dashboard.package}/etc/wazuh-dashboard/. ${cfg.dashboard.configDir}/
            fi
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
            install -o root -g wazuh-dashboard -m 0640 /etc/wazuh-dashboard/opensearch_dashboards.yml ${cfg.dashboard.configDir}/opensearch_dashboards.yml
            install -d -m 0750 -o wazuh-dashboard -g wazuh-dashboard ${cfg.dashboard.dataDir}
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
            "WAZUH_API_URL=${cfg.dashboard.managerApiUrl}"
          ];
          EnvironmentFile = lib.optional (
            cfg.dashboard.environmentFile != null
          ) cfg.dashboard.environmentFile;
        };
      };
      networking.firewall.allowedTCPPorts = lib.optional cfg.dashboard.openFirewall cfg.dashboard.port;
    })
  ];
}
