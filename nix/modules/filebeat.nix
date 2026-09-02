{
  config,
  lib,
  pkgs,
  wazuhPackages,
  ...
}:

let
  wazuhCfg = config.services.wazuh;
  cfg = wazuhCfg.filebeat;
  certificateCfg = wazuhCfg.certificates.autoProvision;
  credentialCfg = wazuhCfg.credentials.autoProvision;
  effectiveCertificates = {
    rootCA =
      if cfg.certificates.rootCA != null then
        cfg.certificates.rootCA
      else
        "${certificateCfg.stateDir}/root-ca.pem";
    certificate =
      if cfg.certificates.certificate != null then
        cfg.certificates.certificate
      else
        "${certificateCfg.stateDir}/filebeat.pem";
    key =
      if cfg.certificates.key != null then
        cfg.certificates.key
      else
        "${certificateCfg.stateDir}/filebeat-key.pem";
  };
  filebeatConfig =
    if cfg.config != "" then
      cfg.config
    else
      lib.replaceStrings [ "@CONFIG_DIR@" "@INDEXER_URL@" ] [ cfg.configDir cfg.indexerUrl ] (
        lib.readFile ../templates/filebeat.yml
      );
  filebeatConfigFile = pkgs.writeText "wazuh-filebeat.yml" filebeatConfig;
in
{
  options.services.wazuh.filebeat = {
    enable = lib.mkEnableOption "Wazuh Filebeat alert forwarding";
    package = lib.mkOption {
      type = lib.types.package;
      default = wazuhPackages.filebeat;
      description = "Filebeat package with the Wazuh module and index template.";
    };
    configDir = lib.mkOption {
      type = lib.types.path;
      default = "/etc/filebeat";
      description = "Mutable Filebeat configuration directory.";
    };
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/filebeat";
      description = "Persistent Filebeat registry and data directory.";
    };
    logDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/log/filebeat";
      description = "Filebeat log directory.";
    };
    indexerUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://127.0.0.1:9200";
      description = "Wazuh indexer URL receiving alerts.";
    };
    config = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Complete filebeat.yml; a Wazuh alerts configuration is generated when empty.";
    };
    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Environment file containing INDEXER_USERNAME and INDEXER_PASSWORD.";
    };
    requireManager = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Require the local Wazuh manager before forwarding alerts.";
    };
    requireIndexer = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Require the local Wazuh indexer before forwarding alerts.";
    };
    certificates = {
      rootCA = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Certificate authority used to verify the Wazuh indexer.";
      };
      certificate = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Filebeat client certificate accepted by the Wazuh indexer.";
      };
      key = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Filebeat client private key.";
      };
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !cfg.enable || !cfg.requireManager || wazuhCfg.manager.enable;
          message = "services.wazuh.filebeat.requireManager requires services.wazuh.manager.enable.";
        }
        {
          assertion = !cfg.enable || !cfg.requireIndexer || wazuhCfg.indexer.enable;
          message = "services.wazuh.filebeat.requireIndexer requires services.wazuh.indexer.enable.";
        }
        {
          assertion = !cfg.enable || cfg.environmentFile != null;
          message = "services.wazuh.filebeat.environmentFile is required when Filebeat is enabled.";
        }
        {
          assertion =
            !cfg.enable
            || (
              certificateCfg.enable
              || (
                cfg.certificates.rootCA != null
                && cfg.certificates.certificate != null
                && cfg.certificates.key != null
              )
            );
          message = "Wazuh Filebeat requires its root CA, certificate, and key.";
        }
      ];
    }
    (lib.mkIf cfg.enable {
      systemd.tmpfiles.rules = [
        "d ${cfg.configDir} 0750 root root -"
        "d ${cfg.configDir}/certs 0500 root root -"
        "d ${cfg.dataDir} 0750 root root -"
        "d ${cfg.logDir} 0750 root root -"
      ];

      systemd.services.wazuh-filebeat-prepare = {
        description = "Prepare Wazuh Filebeat runtime files";
        before = [
          "wazuh-filebeat.service"
        ]
        ++ lib.optional wazuhCfg.manager.enable "wazuh-manager.service";
        requires =
          lib.optional certificateCfg.enable "wazuh-certificates.service"
          ++ lib.optional credentialCfg.enable "wazuh-credentials.service";
        after =
          lib.optional certificateCfg.enable "wazuh-certificates.service"
          ++ lib.optional credentialCfg.enable "wazuh-credentials.service";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          EnvironmentFile = cfg.environmentFile;
          ExecStart = pkgs.writeShellScript "wazuh-filebeat-prepare" ''
            set -eu
            : "''${INDEXER_USERNAME:?INDEXER_USERNAME must be set in the Filebeat environment file}"
            : "''${INDEXER_PASSWORD:?INDEXER_PASSWORD must be set in the Filebeat environment file}"

            install -d -m 0750 -o root -g root ${cfg.configDir}
            install -d -m 0500 -o root -g root ${cfg.configDir}/certs
            install -d -m 0750 -o root -g root ${cfg.dataDir} ${cfg.logDir}
            install -o root -g root -m 0640 ${filebeatConfigFile} ${cfg.configDir}/filebeat.yml
            install -o root -g root -m 0644 \
              ${cfg.package}/etc/filebeat/wazuh-template.json \
              ${cfg.configDir}/wazuh-template.json
            install -o root -g root -m 0400 \
              ${effectiveCertificates.rootCA} \
              ${cfg.configDir}/certs/root-ca.pem
            install -o root -g root -m 0400 \
              ${effectiveCertificates.certificate} \
              ${cfg.configDir}/certs/filebeat.pem
            install -o root -g root -m 0400 \
              ${effectiveCertificates.key} \
              ${cfg.configDir}/certs/filebeat-key.pem

            filebeat=${cfg.package}/usr/share/filebeat/bin/filebeat
            rm -f ${cfg.dataDir}/filebeat.keystore
            "$filebeat" keystore create --force \
              --path.home ${cfg.package}/usr/share/filebeat \
              --path.config ${cfg.configDir} \
              --path.data ${cfg.dataDir} \
              --path.logs ${cfg.logDir}
            printf '%s\n' "$INDEXER_USERNAME" | "$filebeat" keystore add username --stdin --force \
              --path.home ${cfg.package}/usr/share/filebeat \
              --path.config ${cfg.configDir} \
              --path.data ${cfg.dataDir} \
              --path.logs ${cfg.logDir}
            printf '%s\n' "$INDEXER_PASSWORD" | "$filebeat" keystore add password --stdin --force \
              --path.home ${cfg.package}/usr/share/filebeat \
              --path.config ${cfg.configDir} \
              --path.data ${cfg.dataDir} \
              --path.logs ${cfg.logDir}
            chmod 0600 ${cfg.dataDir}/filebeat.keystore
          '';
        };
      };

      systemd.services.wazuh-filebeat = {
        description = "Wazuh Filebeat alert forwarding";
        wantedBy = [ "multi-user.target" ];
        requires = [
          "wazuh-filebeat-prepare.service"
        ]
        ++ lib.optional cfg.requireManager "wazuh-manager.service"
        ++ lib.optional cfg.requireIndexer "wazuh-indexer.service"
        ++ lib.optional wazuhCfg.indexer.securityBootstrap.enable "wazuh-indexer-security.service";
        after = [
          "network-online.target"
          "wazuh-filebeat-prepare.service"
        ]
        ++ lib.optional cfg.requireManager "wazuh-manager.service"
        ++ lib.optional cfg.requireIndexer "wazuh-indexer.service"
        ++ lib.optional wazuhCfg.indexer.securityBootstrap.enable "wazuh-indexer-security.service";
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${cfg.package}/usr/share/filebeat/bin/filebeat --environment systemd --path.home ${cfg.package}/usr/share/filebeat --path.config ${cfg.configDir} --path.data ${cfg.dataDir} --path.logs ${cfg.logDir} -c filebeat.yml -e";
          Restart = "on-failure";
          RestartSec = 5;
          TimeoutStartSec = 120;
          TimeoutStopSec = 30;
          KillMode = "control-group";
          UMask = "0077";
          ReadWritePaths = [
            cfg.dataDir
            cfg.logDir
          ];
        };
      };
    })
  ];
}
