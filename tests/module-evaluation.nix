{ pkgs }:

pkgs.testers.nixosTest {
  name = "wazuh-module-evaluation";

  nodes = {
    agent =
      { ... }:
      {
        imports = [ ../nix/module.nix ];

        services.wazuh.agent = {
          enable = true;
          managerAddress = "192.0.2.10";
        };
      };

    manager =
      { ... }:
      {
        imports = [ ../nix/module.nix ];

        virtualisation.diskSize = 4096;
        virtualisation.memorySize = 2048;
        services.wazuh.manager = {
          enable = true;
          requireIndexer = false;
        };
      };
  };

  testScript = ''
    start_all()
    agent.wait_for_unit("wazuh-agent.service")
    agent.succeed("test -e /etc/wazuh/ossec.conf")
    agent.succeed("grep -q 192.0.2.10 /etc/wazuh/ossec.conf")
    agent.succeed("test -s /var/ossec/.wazuh-agent-package")
    agent.succeed("systemctl show wazuh-agent.service -p Type --value | grep -qx forking")
    agent.succeed("systemctl restart wazuh-agent.service")
    agent.wait_for_unit("wazuh-agent.service")

    manager.wait_for_unit("wazuh-manager.service")
    manager.succeed("systemctl show wazuh-manager.service -p Type --value | grep -qx forking")
    manager.succeed("find /var/ossec/var/run -maxdepth 1 -type f -name 'wazuh-apid-*.pid' -not -empty | grep -q .")
    manager.succeed("test -s /var/ossec/.wazuh-manager-package")
    manager.succeed("test -L /var/ossec/framework/python")
    manager.succeed("find /var/ossec/tmp -maxdepth 1 -type l -name 'vd_*_vd_*.tar.xz' | grep -q .")
    manager.succeed("test -s /var/ossec/etc/sslmanager.cert")
    manager.succeed("test -s /var/ossec/etc/sslmanager.key")
    manager.succeed("systemctl restart wazuh-manager.service")
    manager.wait_for_unit("wazuh-manager.service")
    manager.succeed("find /var/ossec/var/run -maxdepth 1 -type f -name 'wazuh-apid-*.pid' -not -empty | grep -q .")
  '';
}
