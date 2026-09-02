{ pkgs }:

pkgs.testers.nixosTest {
  name = "wazuh-manager-restart-stress";

  nodes.manager =
    { ... }:
    {
      imports = [ ../nix/modules ];

      virtualisation = {
        diskSize = 4096;
        memorySize = 2048;
      };

      services.wazuh.manager = {
        enable = true;
        requireIndexer = false;
        config = builtins.readFile ./fixtures/manager-standalone-ossec.conf;
      };

      systemd.services.wazuh-manager.serviceConfig.ExecStartPre =
        pkgs.writeShellScript "truncate-wazuh-manager-log"
          /* bash */ ''
            : > /var/ossec/logs/ossec.log
          '';
    };

  testScript = ''
    start_all()
    manager.wait_for_unit("wazuh-manager.service")

    for attempt in range(5):
        with subtest(f"manager restart {attempt + 1}"):
            manager.succeed("systemctl restart wazuh-manager.service")
            manager.wait_for_unit("wazuh-manager.service")
            manager.succeed("systemctl is-active --quiet wazuh-manager.service")
            manager.succeed(
                "find /var/ossec/var/run -maxdepth 1 -type f "
                "-name 'wazuh-apid-*.pid' -not -empty | grep -q ."
            )
            manager.succeed(
                "! journalctl --boot --dmesg --no-pager "
                "| grep -E 'wazuh-modulesd.*segfault'"
            )
            manager.succeed(
                "! journalctl --boot --no-pager -t systemd-coredump "
                "| grep -F wazuh-modulesd"
            )
  '';
}
