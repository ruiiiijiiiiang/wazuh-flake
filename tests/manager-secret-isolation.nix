{ pkgs }:

pkgs.testers.nixosTest {
  name = "wazuh-manager-secret-isolation";

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
              indexer_password="manager-$(cat /etc/machine-id)"
              api_password="Native-Api1!$(cat /etc/machine-id)"
              api_admin_password="Native-Admin1!$(cat /etc/machine-id)"
              printf 'INDEXER_USERNAME=admin\nINDEXER_PASSWORD=%s\nAPI_USERNAME=wazuh-wui\nAPI_PASSWORD=%s\nAPI_ADMIN_USERNAME=wazuh\nAPI_ADMIN_PASSWORD=%s\n' \
                "$indexer_password" "$api_password" "$api_admin_password" \
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
    manager.wait_until_succeeds(
        "test \"$(systemctl show wazuh-manager-api-credentials.service -p ActiveState --value)\" = inactive; "
        "test \"$(systemctl show wazuh-manager-api-credentials.service -p Result --value)\" = success"
    )

    manager.succeed(
        "api_password=Native-Api1!$(cat /etc/machine-id); "
        "curl --fail --silent --insecure --user \"wazuh-wui:$api_password\" "
        "--request POST 'https://127.0.0.1:55000/security/user/authenticate?raw=true' | grep -q ."
    )
    manager.succeed(
        "api_admin_password=Native-Admin1!$(cat /etc/machine-id); "
        "curl --fail --silent --insecure --user \"wazuh:$api_admin_password\" "
        "--request POST 'https://127.0.0.1:55000/security/user/authenticate?raw=true' | grep -q ."
    )
    manager.fail(
        "curl --fail --silent --insecure --user wazuh-wui:wazuh-wui "
        "--request POST 'https://127.0.0.1:55000/security/user/authenticate?raw=true'"
    )
    manager.fail(
        "curl --fail --silent --insecure --user wazuh:wazuh "
        "--request POST 'https://127.0.0.1:55000/security/user/authenticate?raw=true'"
    )

    manager.succeed(
        "test -z \"$(systemctl show wazuh-manager.service -p EnvironmentFiles --value)\""
    )
    manager.succeed(
        "systemctl show wazuh-manager-prepare.service -p EnvironmentFiles --value "
        "| grep -qF /run/wazuh-test/manager.env"
    )
    manager.succeed(
        "systemctl show wazuh-manager-api-credentials.service -p EnvironmentFiles --value "
        "| grep -qF /run/wazuh-test/manager.env"
    )
    manager.succeed(
        "test -z \"$(systemctl show wazuh-manager.service -p ExecStartPre --value)\""
    )
    manager.succeed("find /var/ossec/queue/keystore -type f -not -empty | grep -q .")
    manager.succeed(
        "for pid in $(cat /sys/fs/cgroup/system.slice/wazuh-manager.service/cgroup.procs); do "
        "! tr '\\0' '\\n' < /proc/$pid/environ "
        "| grep -Eq '^(INDEXER_USERNAME|INDEXER_PASSWORD|API_USERNAME|API_PASSWORD|API_ADMIN_USERNAME|API_ADMIN_PASSWORD)=' || exit 1; "
        "done"
    )

    first_api_invocation = manager.succeed(
        "systemctl show wazuh-manager-api-credentials.service -p InvocationID --value"
    ).strip()
    first_invocation = manager.succeed(
        "systemctl show wazuh-manager-prepare.service -p InvocationID --value"
    ).strip()
    manager.succeed("systemctl restart wazuh-manager.service")
    manager.wait_for_unit("wazuh-manager.service")
    second_invocation = manager.succeed(
        "systemctl show wazuh-manager-prepare.service -p InvocationID --value"
    ).strip()
    assert first_invocation != second_invocation
    manager.wait_until_succeeds(
        "test \"$(systemctl show wazuh-manager-api-credentials.service -p InvocationID --value)\" "
        f"!= {first_api_invocation}; "
        "test \"$(systemctl show wazuh-manager-api-credentials.service -p ActiveState --value)\" = inactive; "
        "test \"$(systemctl show wazuh-manager-api-credentials.service -p Result --value)\" = success"
    )

    manager.succeed(
        "for pid in $(cat /sys/fs/cgroup/system.slice/wazuh-manager.service/cgroup.procs); do "
        "! tr '\\0' '\\n' < /proc/$pid/environ "
        "| grep -Eq '^(INDEXER_USERNAME|INDEXER_PASSWORD|API_USERNAME|API_PASSWORD|API_ADMIN_USERNAME|API_ADMIN_PASSWORD)=' || exit 1; "
        "done"
    )

    manager.succeed(
        "api_password=Native-Api1!$(cat /etc/machine-id); "
        "curl --fail --silent --insecure --user \"wazuh-wui:$api_password\" "
        "--request POST 'https://127.0.0.1:55000/security/user/authenticate?raw=true' | grep -q ."
    )
    manager.succeed(
        "api_admin_password=Native-Admin1!$(cat /etc/machine-id); "
        "curl --fail --silent --insecure --user \"wazuh:$api_admin_password\" "
        "--request POST 'https://127.0.0.1:55000/security/user/authenticate?raw=true' | grep -q ."
    )

    manager.succeed(
        "indexer_password=manager-$(cat /etc/machine-id); "
        "api_password=Rotated-Api1!$(cat /etc/machine-id); "
        "api_admin_password=Rotated-Admin1!$(cat /etc/machine-id); "
        "printf 'INDEXER_USERNAME=admin\\nINDEXER_PASSWORD=%s\\nAPI_USERNAME=wazuh-wui\\nAPI_PASSWORD=%s\\nAPI_ADMIN_USERNAME=wazuh\\nAPI_ADMIN_PASSWORD=%s\\n' "
        "\"$indexer_password\" \"$api_password\" \"$api_admin_password\" > /run/wazuh-test/manager.env; "
        "systemctl start wazuh-manager-api-credentials.service"
    )
    manager.succeed(
        "api_password=Rotated-Api1!$(cat /etc/machine-id); "
        "curl --fail --silent --insecure --user \"wazuh-wui:$api_password\" "
        "--request POST 'https://127.0.0.1:55000/security/user/authenticate?raw=true' | grep -q ."
    )
    manager.succeed(
        "api_admin_password=Rotated-Admin1!$(cat /etc/machine-id); "
        "curl --fail --silent --insecure --user \"wazuh:$api_admin_password\" "
        "--request POST 'https://127.0.0.1:55000/security/user/authenticate?raw=true' | grep -q ."
    )
    manager.fail(
        "api_password=Native-Api1!$(cat /etc/machine-id); "
        "curl --fail --silent --insecure --user \"wazuh-wui:$api_password\" "
        "--request POST 'https://127.0.0.1:55000/security/user/authenticate?raw=true'"
    )
    manager.fail(
        "api_admin_password=Native-Admin1!$(cat /etc/machine-id); "
        "curl --fail --silent --insecure --user \"wazuh:$api_admin_password\" "
        "--request POST 'https://127.0.0.1:55000/security/user/authenticate?raw=true'"
    )
  '';
}
