{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.wazuh;
  packages = import ./packages.nix { inherit pkgs; };
  agentConfig =
    if cfg.agent.config != "" then
      cfg.agent.config
    else
      lib.replaceStrings
        [ "@MANAGER_ADDRESS@" "@MANAGER_PORT@" "@ENROLLMENT_PORT@" ]
        [ cfg.agent.managerAddress (toString cfg.agent.managerPort) (toString cfg.agent.enrollmentPort) ]
        (lib.readFile ./ossec.conf);
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
in
{
  options.services.wazuh = {
    agent = {
      enable = mkEnableOption "Wazuh agent";
      package = mkOption {
        type = types.package;
        default = packages.agent;
        description = "Wazuh agent package.";
      };
      managerAddress = mkOption {
        type = types.str;
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
      config = mkOption {
        type = types.lines;
        default = "";
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
      };
      settings = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
    };

    dashboard = {
      enable = mkEnableOption "Wazuh dashboard";
      package = mkOption {
        type = types.package;
        default = packages.dashboard;
      };
      port = mkOption {
        type = types.port;
        default = 5601;
      };
      settings = mkOption {
        type = types.lines;
        default = "";
      };
    };
  };

  config = lib.mkMerge [
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
      systemd.tmpfiles.rules = [ "d /var/ossec 0750 wazuh wazuh -" ];
      systemd.services.wazuh-manager = {
        description = "Wazuh manager";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network-online.target"
          "wazuh-indexer.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "forking";
          ExecStart = "${cfg.manager.package}/var/ossec/bin/wazuh-control start";
          ExecStop = "${cfg.manager.package}/var/ossec/bin/wazuh-control stop";
          ExecReload = "${cfg.manager.package}/var/ossec/bin/wazuh-control restart";
          Restart = "on-failure";
          StateDirectory = "ossec";
          ReadWritePaths = [ "/var/ossec" ];
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
      systemd.tmpfiles.rules = [ "d ${cfg.indexer.dataDir} 0750 wazuh-indexer wazuh-indexer -" ];
      environment.etc."wazuh-indexer/opensearch.yml".text =
        lib.generators.toYAML { }
          cfg.indexer.settings;
      systemd.services.wazuh-indexer = {
        description = "Wazuh indexer";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "simple";
          User = "wazuh-indexer";
          Group = "wazuh-indexer";
          WorkingDirectory = cfg.indexer.dataDir;
          ExecStart = "${cfg.indexer.package}/usr/share/wazuh-indexer/bin/opensearch";
          Restart = "on-failure";
          LimitMEMLOCK = "infinity";
          LimitNOFILE = 65535;
          Environment = [
            "OPENSEARCH_PATH_CONF=/etc/wazuh-indexer"
            "OPENSEARCH_JAVA_OPTS=-Xms1g -Xmx1g"
          ];
        };
      };
    })

    (mkIf cfg.dashboard.enable {
      users.groups.wazuh-dashboard = { };
      users.users.wazuh-dashboard = {
        isSystemUser = true;
        group = "wazuh-dashboard";
        home = "/var/lib/wazuh-dashboard";
      };
      systemd.tmpfiles.rules = [ "d /var/lib/wazuh-dashboard 0750 wazuh-dashboard wazuh-dashboard -" ];
      environment.etc."wazuh-dashboard/opensearch_dashboards.yml".text = cfg.dashboard.settings;
      systemd.services.wazuh-dashboard = {
        description = "Wazuh dashboard";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network-online.target"
          "wazuh-indexer.service"
          "wazuh-manager.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "simple";
          User = "wazuh-dashboard";
          Group = "wazuh-dashboard";
          WorkingDirectory = "/var/lib/wazuh-dashboard";
          ExecStart = "${cfg.dashboard.package}/usr/share/wazuh-dashboard/bin/opensearch-dashboards";
          Restart = "on-failure";
          Environment = [ "OPENSEARCH_DASHBOARDS_PATH_CONF=/etc/wazuh-dashboard" ];
        };
      };
      networking.firewall.allowedTCPPorts = [ cfg.dashboard.port ];
    })
  ];
}
