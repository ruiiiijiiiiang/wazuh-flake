{
  config,
  lib,
  pkgs,
  ...
}:

let
  wazuhCfg = config.services.wazuh;
  cfg = wazuhCfg.indexer;
  packages = import ../packages.nix {
    inherit pkgs;
    version = wazuhCfg.version;
  };
  indexerConfigFile = pkgs.writeText "wazuh-indexer.yml" cfg.config;
  indexerHealthHost =
    if cfg.bindAddress == "0.0.0.0" then
      "127.0.0.1"
    else if cfg.bindAddress == "::" then
      "[::1]"
    else if lib.hasInfix ":" cfg.bindAddress then
      "[${cfg.bindAddress}]"
    else
      cfg.bindAddress;
in
{
  options.services.wazuh.indexer = {
    enable = lib.mkEnableOption "Wazuh indexer";
    package = lib.mkOption {
      type = lib.types.package;
      default = packages.indexer;
    };
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/wazuh-indexer";
      description = "Persistent Wazuh indexer data directory.";
    };
    configDir = lib.mkOption {
      type = lib.types.path;
      default = "/etc/wazuh-indexer";
      description = "Mutable Wazuh indexer configuration directory.";
    };
    config = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Complete opensearch.yml; the package default is used when empty.";
    };
    certificates = {
      rootCA = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Wazuh indexer root CA certificate.";
      };
      nodeCertificate = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Wazuh indexer node certificate.";
      };
      nodeKey = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Wazuh indexer node private key.";
      };
      adminCertificate = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Wazuh indexer admin certificate.";
      };
      adminKey = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Wazuh indexer admin private key.";
      };
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 9200;
      description = "Wazuh indexer HTTPS port.";
    };
    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Wazuh indexer listen address.";
    };
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the Wazuh indexer port in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.wazuh-indexer = { };
    users.users.wazuh-indexer = {
      isSystemUser = true;
      group = "wazuh-indexer";
      home = cfg.dataDir;
    };
    boot.kernel.sysctl."vm.max_map_count" = 262144;
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 wazuh-indexer wazuh-indexer -"
      "d /var/log/wazuh-indexer 0750 wazuh-indexer wazuh-indexer -"
      "d ${cfg.configDir} 0750 wazuh-indexer wazuh-indexer -"
      "d ${cfg.configDir}/certs 0500 wazuh-indexer wazuh-indexer -"
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
          install -d -m 0750 -o wazuh-indexer -g wazuh-indexer ${cfg.configDir}
          if [ -d ${cfg.package}/etc/wazuh-indexer ]; then
            cp -a --no-clobber ${cfg.package}/etc/wazuh-indexer/. ${cfg.configDir}/
          fi
          install -d -m 0500 -o wazuh-indexer -g wazuh-indexer ${cfg.configDir}/certs
          ${lib.optionalString (cfg.certificates.rootCA != null) ''
            install -o wazuh-indexer -g wazuh-indexer -m 0400 ${cfg.certificates.rootCA} ${cfg.configDir}/certs/root-ca.pem
          ''}
          ${lib.optionalString (cfg.certificates.nodeCertificate != null) ''
            install -o wazuh-indexer -g wazuh-indexer -m 0400 ${cfg.certificates.nodeCertificate} ${cfg.configDir}/certs/indexer.pem
          ''}
          ${lib.optionalString (cfg.certificates.nodeKey != null) ''
            install -o wazuh-indexer -g wazuh-indexer -m 0400 ${cfg.certificates.nodeKey} ${cfg.configDir}/certs/indexer-key.pem
          ''}
          ${lib.optionalString (cfg.certificates.adminCertificate != null) ''
            install -o wazuh-indexer -g wazuh-indexer -m 0400 ${cfg.certificates.adminCertificate} ${cfg.configDir}/certs/admin.pem
          ''}
          ${lib.optionalString (cfg.certificates.adminKey != null) ''
            install -o wazuh-indexer -g wazuh-indexer -m 0400 ${cfg.certificates.adminKey} ${cfg.configDir}/certs/admin-key.pem
          ''}
          ${lib.optionalString (cfg.config != "") ''
            install -o wazuh-indexer -g wazuh-indexer -m 0640 ${indexerConfigFile} ${cfg.configDir}/opensearch.yml
          ''}
          chown -R wazuh-indexer:wazuh-indexer ${cfg.configDir}
          ${pkgs.findutils}/bin/find ${cfg.configDir} -type d -exec chmod 0700 {} +
          ${pkgs.findutils}/bin/find ${cfg.configDir} -type f -exec chmod 0600 {} +
          if [ ! -e ${cfg.configDir}/opensearch.keystore ]; then
            ${pkgs.util-linux}/bin/runuser -u wazuh-indexer -- \
              ${pkgs.coreutils}/bin/env \
                OPENSEARCH_PATH_CONF=${cfg.configDir} \
                OPENSEARCH_JAVA_HOME=${cfg.package}/usr/share/wazuh-indexer/jdk \
                ${cfg.package}/usr/share/wazuh-indexer/bin/opensearch-keystore create
          fi
          ${pkgs.util-linux}/bin/runuser -u wazuh-indexer -- \
            ${pkgs.coreutils}/bin/env \
              OPENSEARCH_PATH_CONF=${cfg.configDir} \
              OPENSEARCH_JAVA_HOME=${cfg.package}/usr/share/wazuh-indexer/jdk \
              ${cfg.package}/usr/share/wazuh-indexer/bin/opensearch-keystore upgrade
          install -d -m 0750 -o wazuh-indexer -g wazuh-indexer ${cfg.dataDir}
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
        WorkingDirectory = cfg.dataDir;
        ExecStart = "${cfg.package}/usr/share/wazuh-indexer/bin/opensearch -Enetwork.host=${cfg.bindAddress} -Ehttp.port=${toString cfg.port} -Epath.data=${cfg.dataDir} -Epath.logs=/var/log/wazuh-indexer";
        ExecStartPost = pkgs.writeShellScript "wazuh-indexer-healthcheck" ''
          set -eu
          for attempt in $(seq 1 60); do
            status=$(${pkgs.curl}/bin/curl -k -s -o /dev/null -w '%{http_code}' \
              "https://${indexerHealthHost}:${toString cfg.port}/" || true)
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
          cfg.configDir
          cfg.dataDir
          "/var/log/wazuh-indexer"
        ];
        Environment = [
          "OPENSEARCH_PATH_CONF=${cfg.configDir}"
          "OPENSEARCH_JAVA_HOME=${cfg.package}/usr/share/wazuh-indexer/jdk"
        ];
      };
    };
    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
