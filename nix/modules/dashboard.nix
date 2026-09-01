{
  config,
  lib,
  pkgs,
  ...
}:

let
  wazuhCfg = config.services.wazuh;
  cfg = wazuhCfg.dashboard;
  certificateCfg = wazuhCfg.certificates.autoProvision;
  effectiveRootCA =
    if cfg.certificates.rootCA != null then
      cfg.certificates.rootCA
    else
      "${certificateCfg.stateDir}/root-ca.pem";
  packages = import ../packages.nix {
    inherit pkgs;
    version = wazuhCfg.version;
  };
  dashboardTlsEnabled = cfg.certificates.certificate != null && cfg.certificates.key != null;
  dashboardConfig =
    if cfg.config != "" then
      cfg.config
    else
      lib.replaceStrings
        [
          "@SERVER_HOST@"
          "@SERVER_PORT@"
          "@INDEXER_URL@"
          "@CONFIG_DIR@"
          "@DATA_DIR@"
          "@SERVER_SSL_ENABLED@"
          "@SERVER_SSL_CONFIGURATION@"
        ]
        [
          cfg.bindAddress
          (toString cfg.port)
          cfg.indexerUrl
          cfg.configDir
          cfg.dataDir
          (if dashboardTlsEnabled then "true" else "false")
          (lib.optionalString dashboardTlsEnabled ''
            server.ssl.certificate: "${cfg.configDir}/certs/dashboard.pem"
            server.ssl.key: "${cfg.configDir}/certs/dashboard-key.pem"
          '')
        ]
        (lib.readFile ../opensearch_dashboards.yml);
  dashboardConfigFile = pkgs.writeText "opensearch_dashboards.yml" dashboardConfig;
  dashboardAppSettingsFile = pkgs.writeText "wazuh-dashboard-app-settings.json" (
    builtins.toJSON cfg.appSettings
  );
in
{
  options.services.wazuh.dashboard = {
    enable = lib.mkEnableOption "Wazuh dashboard";
    package = lib.mkOption {
      type = lib.types.package;
      default = packages.dashboard;
    };
    configDir = lib.mkOption {
      type = lib.types.path;
      default = "/etc/wazuh-dashboard";
      description = "Mutable Wazuh dashboard configuration directory.";
    };
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/wazuh-dashboard";
      description = "Persistent Wazuh dashboard data directory.";
    };
    indexerUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://127.0.0.1:9200";
      description = "Wazuh indexer URL.";
    };
    managerApiUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://127.0.0.1";
      description = "Wazuh manager API URL without its port.";
    };
    managerApiPort = lib.mkOption {
      type = lib.types.port;
      default = 55000;
      description = "Wazuh manager API port.";
    };
    managerApiRunAs = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use the authenticated dashboard user when calling the Wazuh API.";
    };
    appSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Non-secret Wazuh dashboard application settings merged with the runtime API host.";
    };
    requireManager = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Require the local Wazuh manager before starting the dashboard.";
    };
    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Dashboard listen address.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 5601;
    };
    config = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Complete opensearch_dashboards.yml; a local single-node config is generated when empty.";
    };
    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Environment file containing DASHBOARD_USERNAME, DASHBOARD_PASSWORD,
        API_USERNAME, and API_PASSWORD.
      '';
    };
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the dashboard port in the firewall.";
    };
    certificates = {
      rootCA = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Wazuh dashboard root CA certificate.";
      };
      certificate = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Wazuh dashboard TLS certificate.";
      };
      key = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Wazuh dashboard TLS private key.";
      };
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !cfg.enable || !cfg.requireManager || wazuhCfg.manager.enable;
          message = "services.wazuh.dashboard.requireManager requires services.wazuh.manager.enable.";
        }
        {
          assertion = !cfg.enable || !cfg.requireManager || wazuhCfg.manager.apiCredentials.enable;
          message = "A dashboard requiring the manager also requires Wazuh manager API credential provisioning.";
        }
        {
          assertion = !cfg.enable || wazuhCfg.indexer.enable;
          message = "services.wazuh.dashboard requires services.wazuh.indexer.enable.";
        }
        {
          assertion = !cfg.enable || cfg.environmentFile != null;
          message = "services.wazuh.dashboard.environmentFile is required when the dashboard is enabled.";
        }
        {
          assertion = !cfg.enable || certificateCfg.enable || cfg.certificates.rootCA != null;
          message = "The Wazuh dashboard requires the indexer root CA certificate.";
        }
        {
          assertion = !cfg.enable || (cfg.certificates.certificate == null) == (cfg.certificates.key == null);
          message = "Wazuh dashboard TLS certificate and key must be configured together.";
        }
      ];
    }
    (lib.mkIf cfg.enable {
      users.groups.wazuh-dashboard = { };
      users.users.wazuh-dashboard = {
        isSystemUser = true;
        group = "wazuh-dashboard";
        home = "/var/lib/wazuh-dashboard";
      };
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0750 wazuh-dashboard wazuh-dashboard -"
        "d ${cfg.configDir} 0750 root wazuh-dashboard -"
        "d ${cfg.configDir}/certs 0500 wazuh-dashboard wazuh-dashboard -"
      ];
      systemd.services.wazuh-dashboard-prepare = {
        description = "Prepare Wazuh dashboard runtime files";
        wantedBy = [ "multi-user.target" ];
        before = [ "wazuh-dashboard.service" ];
        requires = lib.optional certificateCfg.enable "wazuh-certificates.service";
        after = lib.optional certificateCfg.enable "wazuh-certificates.service";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          EnvironmentFile = cfg.environmentFile;
          ExecStart = pkgs.writeShellScript "wazuh-dashboard-prepare" ''
            set -eu
            : "''${DASHBOARD_USERNAME:?DASHBOARD_USERNAME must be set in the dashboard environment file}"
            : "''${DASHBOARD_PASSWORD:?DASHBOARD_PASSWORD must be set in the dashboard environment file}"
            : "''${API_USERNAME:?API_USERNAME must be set in the dashboard environment file}"
            : "''${API_PASSWORD:?API_PASSWORD must be set in the dashboard environment file}"

            install -d -m 0750 -o root -g wazuh-dashboard ${cfg.configDir}
            if [ -d ${cfg.package}/etc/wazuh-dashboard ]; then
              cp -a --no-clobber ${cfg.package}/etc/wazuh-dashboard/. ${cfg.configDir}/
            fi
            chown root:wazuh-dashboard ${cfg.configDir}
            chmod 0750 ${cfg.configDir}
            install -d -m 0750 -o wazuh-dashboard -g wazuh-dashboard ${cfg.dataDir}
            if [ -d ${cfg.package}/usr/share/wazuh-dashboard/data ]; then
              cp -a --no-clobber \
                ${cfg.package}/usr/share/wazuh-dashboard/data/. \
                ${cfg.dataDir}/
            fi
            chown -R wazuh-dashboard:wazuh-dashboard ${cfg.dataDir}
            chmod -R u+rwX,g+rX,o-rwx ${cfg.dataDir}

            install -d -m 0500 -o wazuh-dashboard -g wazuh-dashboard ${cfg.configDir}/certs
            ${lib.optionalString (cfg.certificates.rootCA != null || certificateCfg.enable) ''
              install -o wazuh-dashboard -g wazuh-dashboard -m 0400 ${effectiveRootCA} ${cfg.configDir}/certs/root-ca.pem
            ''}
            ${lib.optionalString dashboardTlsEnabled ''
              install -o wazuh-dashboard -g wazuh-dashboard -m 0400 ${cfg.certificates.certificate} ${cfg.configDir}/certs/dashboard.pem
              install -o wazuh-dashboard -g wazuh-dashboard -m 0400 ${cfg.certificates.key} ${cfg.configDir}/certs/dashboard-key.pem
            ''}
            install -o root -g wazuh-dashboard -m 0640 ${dashboardConfigFile} ${cfg.configDir}/opensearch_dashboards.yml

            export OPENSEARCH_DASHBOARDS_PATH_CONF=${cfg.configDir}
            keystore=${cfg.package}/usr/share/wazuh-dashboard/bin/opensearch-dashboards-keystore
            rm -f ${cfg.configDir}/opensearch_dashboards.keystore
            "$keystore" create --allow-root
            printf '%s\n' "$DASHBOARD_USERNAME" | \
              "$keystore" add opensearch.username --stdin --allow-root
            printf '%s\n' "$DASHBOARD_PASSWORD" | \
              "$keystore" add opensearch.password --stdin --allow-root
            chown wazuh-dashboard:wazuh-dashboard ${cfg.configDir}/opensearch_dashboards.keystore
            chmod 0600 ${cfg.configDir}/opensearch_dashboards.keystore

            install -d -m 0700 -o wazuh-dashboard -g wazuh-dashboard \
              ${cfg.dataDir}/wazuh \
              ${cfg.dataDir}/wazuh/config
            ${pkgs.jq}/bin/jq \
              --arg url ${lib.escapeShellArg cfg.managerApiUrl} \
              --argjson port ${toString cfg.managerApiPort} \
              --arg username "$API_USERNAME" \
              --arg password "$API_PASSWORD" \
              --argjson run_as ${if cfg.managerApiRunAs then "true" else "false"} \
              '. + {hosts: [{"1513629884013": {url: $url, port: $port, username: $username, password: $password, run_as: $run_as}}]}' \
              ${dashboardAppSettingsFile} \
              > ${cfg.dataDir}/wazuh/config/wazuh.yml
            chown wazuh-dashboard:wazuh-dashboard ${cfg.dataDir}/wazuh/config/wazuh.yml
            chmod 0600 ${cfg.dataDir}/wazuh/config/wazuh.yml
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
        ++ lib.optional cfg.requireManager "wazuh-manager.service"
        ++ lib.optional cfg.requireManager "wazuh-manager-api-credentials.service"
        ++ lib.optional wazuhCfg.indexer.securityBootstrap.enable "wazuh-indexer-security.service";
        after = [
          "network-online.target"
          "wazuh-dashboard-prepare.service"
          "wazuh-indexer.service"
        ]
        ++ lib.optional cfg.requireManager "wazuh-manager.service"
        ++ lib.optional cfg.requireManager "wazuh-manager-api-credentials.service"
        ++ lib.optional wazuhCfg.indexer.securityBootstrap.enable "wazuh-indexer-security.service";
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "simple";
          User = "wazuh-dashboard";
          Group = "wazuh-dashboard";
          WorkingDirectory = cfg.dataDir;
          ExecStart = "${cfg.package}/usr/share/wazuh-dashboard/bin/opensearch-dashboards";
          ExecStartPost = pkgs.writeShellScript "wazuh-dashboard-healthcheck" ''
            set -eu
            for attempt in $(seq 1 60); do
              status=$(${pkgs.curl}/bin/curl -k -s -o /dev/null -w '%{http_code}' \
                "${
                  if dashboardTlsEnabled then "https" else "http"
                }://127.0.0.1:${toString cfg.port}/api/status" || true)
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
            "OPENSEARCH_DASHBOARDS_PATH_CONF=${cfg.configDir}"
          ];
        };
      };
      networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
    })
  ];
}
