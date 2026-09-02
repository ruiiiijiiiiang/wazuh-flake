{ pkgs }:

pkgs.testers.nixosTest {
  name = "wazuh-module-evaluation";

  nodes = {
    agent =
      { ... }:
      {
        imports = [ ../nix/modules ];

        services.wazuh.agent = {
          enable = true;
          managerAddress = "192.168.1.2";
          extraConfig = /* xml */ ''
            <localfile>
              <log_format>syslog</log_format>
              <location>/var/log/test-agent.log</location>
            </localfile>
          '';
        };
      };

    manager =
      { ... }:
      {
        imports = [ ../nix/modules ];

        virtualisation.diskSize = 4096;
        virtualisation.memorySize = 2048;
        services.wazuh.manager = {
          enable = true;
          requireIndexer = false;
          config = builtins.readFile ./fixtures/manager-standalone-ossec.conf;
        };
      };
  };

  testScript = ''
    start_all()

    manager.wait_for_unit("wazuh-manager.service")
    manager.succeed("systemctl show wazuh-manager.service -p Type --value | grep -qx forking")
    manager.succeed("find /var/ossec/var/run -maxdepth 1 -type f -name 'wazuh-apid-*.pid' -not -empty | grep -q .")
    manager.succeed("test -s /var/ossec/.wazuh-manager-package")
    manager.succeed("test -L /var/ossec/framework/python")
    manager.succeed("find /var/ossec/tmp -maxdepth 1 -type l -name 'vd_*_vd_*.tar.xz' | grep -q .")
    manager.succeed("test -s /var/ossec/etc/sslmanager.cert")
    manager.succeed("test -s /var/ossec/etc/sslmanager.key")

    agent.succeed("systemctl restart wazuh-agent.service")
    agent.wait_for_unit("wazuh-agent.service")
    agent.succeed("test -e /etc/wazuh/ossec.conf")
    agent.succeed("grep -q 192.168.1.2 /etc/wazuh/ossec.conf")
    agent.succeed("grep -q /var/log/test-agent.log /etc/wazuh/ossec.conf")
    agent.succeed("test -s /var/ossec/.wazuh-agent-package")
    agent.succeed("systemctl show wazuh-agent.service -p Type --value | grep -qx forking")
    manager.wait_until_succeeds(
        "/var/ossec/bin/agent_control -l | grep -E 'Name: agent, IP: any, Active$'",
        timeout=180,
    )
    agent.succeed("test -s /var/ossec/etc/client.keys")
    agent.succeed("stat -c '%U:%G:%a' /var/ossec/etc | grep -qx wazuh:wazuh:770")
    agent.succeed("stat -c '%U:%G:%a' /var/ossec/etc/client.keys | grep -qx wazuh:wazuh:640")
    agent.succeed("sha256sum /var/ossec/etc/client.keys > /tmp/client-key.before")

    agent.succeed("systemctl restart wazuh-agent.service")
    agent.wait_for_unit("wazuh-agent.service")
    agent.succeed("stat -c '%U:%G:%a' /var/ossec/etc | grep -qx wazuh:wazuh:770")
    manager.wait_until_succeeds(
        "/var/ossec/bin/agent_control -l | grep -E 'Name: agent, IP: any, Active$'",
        timeout=120,
    )

    agent.succeed("systemctl stop wazuh-agent.service")
    manager.succeed(
        "agent_id=$(/var/ossec/bin/agent_control -l "
        "| grep 'Name: agent,' | cut -d, -f1 | cut -d: -f2 | tr -d ' '); "
        "test -n \"$agent_id\"; "
        "/var/ossec/bin/manage_agents -r \"$agent_id\""
    )
    agent.succeed("systemctl start wazuh-agent.service")
    agent.wait_for_unit("wazuh-agent.service")
    manager.wait_until_succeeds(
        "/var/ossec/bin/agent_control -l | grep -E 'Name: agent, IP: any, Active$'",
        timeout=180,
    )
    agent.succeed("! sha256sum --check /tmp/client-key.before >/dev/null 2>&1")

    manager.succeed("systemctl restart wazuh-manager.service")
    manager.wait_for_unit("wazuh-manager.service")
    manager.succeed("find /var/ossec/var/run -maxdepth 1 -type f -name 'wazuh-apid-*.pid' -not -empty | grep -q .")
  '';
}
