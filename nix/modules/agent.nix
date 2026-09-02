{
  config,
  lib,
  pkgs,
  wazuhPackages,
  ...
}:

let
  wazuhCfg = config.services.wazuh;
  cfg = wazuhCfg.agent;
  agentConfig =
    if cfg.config != "" then
      cfg.config
    else
      lib.replaceStrings
        [
          "@AGENT_NAME@"
          "@MANAGER_ADDRESS@"
          "@MANAGER_PORT@"
          "@ENROLLMENT_PORT@"
          "@EXTRA_CONFIG@"
        ]
        [
          cfg.agentName
          cfg.managerAddress
          (toString cfg.managerPort)
          (toString cfg.enrollmentPort)
          cfg.extraConfig
        ]
        (lib.readFile ../templates/agent-ossec.conf);
in
{
  options.services.wazuh.agent = {
    enable = lib.mkEnableOption "Wazuh agent";
    package = lib.mkOption {
      type = lib.types.package;
      default = wazuhPackages.agent;
      description = "Wazuh agent package.";
    };
    managerAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address of the Wazuh manager.";
    };
    agentName = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Name used when enrolling this Wazuh agent.";
    };
    managerPort = lib.mkOption {
      type = lib.types.port;
      default = 1514;
      description = "Wazuh manager event-collection port.";
    };
    enrollmentPort = lib.mkOption {
      type = lib.types.port;
      default = 1515;
      description = "Wazuh manager enrollment port.";
    };
    config = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Complete ossec.conf content; an enrollment config is generated when empty.";
    };
    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional XML inserted into the generated baseline agent configuration.";
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !(cfg.enable && wazuhCfg.manager.enable);
          message = "The Wazuh agent and manager cannot share the same /var/ossec runtime.";
        }
      ];
    }
    (lib.mkIf cfg.enable {
      users.groups.wazuh = { };
      users.users.wazuh = {
        isSystemUser = true;
        group = "wazuh";
        home = "/var/ossec";
        shell = "${pkgs.shadow}/bin/nologin";
      };
      systemd.tmpfiles.rules = [
        "d /var/ossec 0750 root wazuh -"
        "d /var/ossec/etc 0770 wazuh wazuh -"
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
            install -d -m 0750 -o root -g wazuh /var/ossec
            install -d -m 0770 -o wazuh -g wazuh /var/ossec/etc
            package_marker=/var/ossec/.wazuh-agent-package
            if [ ! -f "$package_marker" ] || [ "$(cat "$package_marker")" != "${cfg.package}" ]; then
              if [ -f /var/ossec/etc/client.keys ]; then
                install -m 0640 /var/ossec/etc/client.keys /run/wazuh-agent-client.keys
              fi
              cp -a --no-preserve=ownership ${cfg.package}/var/ossec/. /var/ossec/
              ${cfg.package}/var/ossec/packages_files/agent_installation_scripts/restore-permissions.sh
              if [ -f /run/wazuh-agent-client.keys ]; then
                install -o wazuh -g wazuh -m 0640 /run/wazuh-agent-client.keys /var/ossec/etc/client.keys
                rm -f /run/wazuh-agent-client.keys
              fi
            fi
            if [ -f /var/ossec/etc/client.keys ]; then
              chown wazuh:wazuh /var/ossec/etc/client.keys
              chmod 0640 /var/ossec/etc/client.keys
            fi
            install -o root -g wazuh -m 0640 /etc/wazuh/ossec.conf /var/ossec/etc/ossec.conf
            printf '%s\n' "${cfg.package}" > "$package_marker"
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
  ];
}
