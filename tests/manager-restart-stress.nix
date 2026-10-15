{ pkgs }:

pkgs.testers.nixosTest {
  name = "wazuh-manager-restart-stress";

  nodes.manager =
    { config, ... }:
    {
      imports = [ ../nix/modules ];

      environment.etc."wazuh-test-package".text = "${config.services.wazuh.manager.package}\n";
      environment.systemPackages = [ pkgs.diffutils ];

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

    with subtest("repair an old matching package marker with stale same-size files"):
        manager.succeed("systemctl stop wazuh-manager.service")
        manager.succeed("sha256sum /var/ossec/etc/sslmanager.cert /var/ossec/etc/sslmanager.key > /tmp/enrollment.before")
        manager.succeed("printf '%s\\n' '001 preserved any 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' > /var/ossec/etc/client.keys")
        manager.succeed("sha256sum /var/ossec/etc/client.keys > /tmp/client-keys.before")
        manager.succeed(
            "printf '\\n# retained local option\\n' >> /var/ossec/etc/local_internal_options.conf; "
            "printf '\\n<!-- retained local rule -->\\n' >> /var/ossec/etc/rules/local_rules.xml; "
            "sha256sum /var/ossec/etc/local_internal_options.conf /var/ossec/etc/rules/local_rules.xml > /tmp/local-config.before"
        )
        manager.succeed(
            "cp -p /var/ossec/bin/wazuh-control /tmp/wazuh-control.expected; "
            "printf '#' | dd of=/var/ossec/bin/wazuh-control bs=1 seek=1 conv=notrunc; "
            "touch -r /tmp/wazuh-control.expected /var/ossec/bin/wazuh-control; "
            "test \"$(stat -c '%s:%Y' /var/ossec/bin/wazuh-control)\" = \"$(stat -c '%s:%Y' /tmp/wazuh-control.expected)\"; "
            "cmp /etc/wazuh-test-package /var/ossec/.wazuh-manager-package; "
            "rm /var/ossec/.wazuh-manager-copy-version"
        )
        manager.fail("cmp /tmp/wazuh-control.expected /var/ossec/bin/wazuh-control")
        manager.succeed("systemctl start wazuh-manager.service")
        manager.wait_for_unit("wazuh-manager.service")
        manager.succeed("cmp /tmp/wazuh-control.expected /var/ossec/bin/wazuh-control")
        manager.succeed("sha256sum --check /tmp/client-keys.before /tmp/enrollment.before /tmp/local-config.before")
        manager.succeed("grep -qx 1 /var/ossec/.wazuh-manager-copy-version")

    with subtest("refresh a changed package marker with same-size stale files"):
        manager.succeed("systemctl stop wazuh-manager.service")
        manager.succeed(
            "printf '#' | dd of=/var/ossec/bin/wazuh-control bs=1 seek=1 conv=notrunc; "
            "touch -r /tmp/wazuh-control.expected /var/ossec/bin/wazuh-control; "
            "printf 'previous-package\\n' > /var/ossec/.wazuh-manager-package"
        )
        manager.succeed("systemctl start wazuh-manager.service")
        manager.wait_for_unit("wazuh-manager.service")
        manager.succeed("cmp /tmp/wazuh-control.expected /var/ossec/bin/wazuh-control")
        manager.succeed("sha256sum --check /tmp/client-keys.before /tmp/enrollment.before /tmp/local-config.before")

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
