{ pkgs }:

pkgs.testers.nixosTest {
  name = "wazuh-manager-secret-isolation";

  nodes.manager =
    { ... }:
    {
      imports = [ ../nix/module.nix ];

      virtualisation = {
        diskSize = 4096;
        memorySize = 2048;
      };

      services.wazuh.manager = {
        enable = true;
        requireIndexer = false;
        config = builtins.readFile ./manager-standalone-ossec.conf;
        environmentFile = "/run/wazuh-test/manager.env";
      };

      systemd.services = {
        wazuh-manager-test-credentials = {
          description = "Create runtime-only Wazuh manager test credentials";
          requiredBy = [ "wazuh-manager-prepare.service" ];
          before = [ "wazuh-manager-prepare.service" ];
          serviceConfig = {
            Type = "oneshot";
            UMask = "0077";
            ExecStart = pkgs.writeShellScript "wazuh-manager-test-credentials" ''
              set -eu
              install -d -m 0700 /run/wazuh-test
              password="manager-$(cat /etc/machine-id)"
              printf 'INDEXER_USERNAME=admin\nINDEXER_PASSWORD=%s\n' "$password" \
                > /run/wazuh-test/manager.env
            '';
          };
        };
        wazuh-manager-prepare.after = [ "wazuh-manager-test-credentials.service" ];
      };
    };

  testScript = ''
    start_all()
    manager.wait_for_unit("wazuh-manager.service")

    manager.succeed(
        "test -z \"$(systemctl show wazuh-manager.service -p EnvironmentFiles --value)\""
    )
    manager.succeed(
        "systemctl show wazuh-manager-prepare.service -p EnvironmentFiles --value "
        "| grep -qF /run/wazuh-test/manager.env"
    )
    manager.succeed(
        "test -z \"$(systemctl show wazuh-manager.service -p ExecStartPre --value)\""
    )
    manager.succeed("find /var/ossec/queue/keystore -type f -not -empty | grep -q .")
    manager.succeed(
        "for pid in $(cat /sys/fs/cgroup/system.slice/wazuh-manager.service/cgroup.procs); do "
        "! tr '\\0' '\\n' < /proc/$pid/environ "
        "| grep -Eq '^(INDEXER_USERNAME|INDEXER_PASSWORD)=' || exit 1; "
        "done"
    )

    first_invocation = manager.succeed(
        "systemctl show wazuh-manager-prepare.service -p InvocationID --value"
    ).strip()
    manager.succeed("systemctl restart wazuh-manager.service")
    manager.wait_for_unit("wazuh-manager.service")
    second_invocation = manager.succeed(
        "systemctl show wazuh-manager-prepare.service -p InvocationID --value"
    ).strip()
    assert first_invocation != second_invocation

    manager.succeed(
        "for pid in $(cat /sys/fs/cgroup/system.slice/wazuh-manager.service/cgroup.procs); do "
        "! tr '\\0' '\\n' < /proc/$pid/environ "
        "| grep -Eq '^(INDEXER_USERNAME|INDEXER_PASSWORD)=' || exit 1; "
        "done"
    )
  '';
}
