{ pkgs }:

let
  indexerPasswordFile = pkgs.writeText "wazuh-test-indexer-password" "Native-Indexer-Test1!\n";
in
pkgs.testers.nixosTest {
  name = "wazuh-central-stack";

  nodes.central =
    { lib, ... }:
    {
      imports = [ ../nix/module.nix ];

      networking.hostName = "central";
      virtualisation = {
        cores = 4;
        diskSize = 24576;
        memorySize = 6144;
      };

      services.wazuh = {
        certificates.autoProvision.enable = true;
        credentials.autoProvision = {
          enable = true;
          inherit indexerPasswordFile;
        };

        manager = {
          enable = true;
        };

        filebeat = {
          enable = true;
        };

        indexer = {
          enable = true;
          securityBootstrap = {
            enable = true;
          };
        };

        dashboard = {
          enable = true;
        };
      };

      systemd.services.wazuh-dashboard.wantedBy = lib.mkForce [ ];
    };

  testScript = ''
    from datetime import timedelta

    service_timeout = timedelta(minutes=5)
    poll_timeout = timedelta(minutes=3)

    start_all()

    central.wait_for_unit("wazuh-indexer-security.service", timeout=service_timeout)
    central.wait_for_unit("wazuh-certificates.service", timeout=service_timeout)
    central.wait_for_unit("wazuh-credentials.service", timeout=service_timeout)
    central.succeed("test -s /var/lib/wazuh-certificates/root-ca.pem")
    central.succeed("test -s /var/lib/wazuh-certificates/indexer.pem")
    central.succeed("test -s /var/lib/wazuh-certificates/admin.pem")
    central.succeed("test -s /var/lib/wazuh-certificates/filebeat.pem")
    central.succeed("stat -c '%U:%G:%a' /var/lib/wazuh-certificates | grep -qx root:root:700")
    central.succeed("stat -c '%U:%G:%a' /var/lib/wazuh-credentials | grep -qx root:root:700")
    central.succeed("stat -c '%U:%G:%a' /var/lib/wazuh-credentials/internal.env | grep -qx root:root:600")
    central.succeed("stat -c '%U:%G:%a' /run/wazuh-credentials/credentials.env | grep -qx root:root:400")
    central.succeed(". /run/wazuh-credentials/credentials.env; test \"$INDEXER_USERNAME\" = admin; test \"$INDEXER_PASSWORD\" = Native-Indexer-Test1!; test \"$DASHBOARD_USERNAME\" = kibanaserver; test \"$API_USERNAME\" = wazuh-wui; test \"$API_ADMIN_USERNAME\" = wazuh; test \"$API_PASSWORD\" != \"$API_ADMIN_PASSWORD\"")
    central.succeed("sha256sum /var/lib/wazuh-credentials/internal.env > /tmp/wazuh-credentials.before")
    central.succeed("systemctl restart wazuh-credentials.service")
    central.succeed("sha256sum --check /tmp/wazuh-credentials.before")
    central.wait_for_unit("wazuh-manager.service", timeout=service_timeout)
    central.wait_until_succeeds(
        "test \"$(systemctl show wazuh-manager-api-credentials.service -p ActiveState --value)\" = inactive; "
        "test \"$(systemctl show wazuh-manager-api-credentials.service -p Result --value)\" = success",
        timeout=poll_timeout,
    )
    central.wait_for_unit("wazuh-filebeat.service", timeout=service_timeout)
    central.succeed(
        ". /run/wazuh-credentials/credentials.env; curl --fail --silent --cacert /var/lib/wazuh-certificates/root-ca.pem --user \"$INDEXER_USERNAME:$INDEXER_PASSWORD\" "
        "'https://127.0.0.1:9200/_cluster/health?wait_for_status=green&"
        "wait_for_no_relocating_shards=true&wait_for_no_initializing_shards=true&timeout=180s'"
    )
    central.succeed("systemctl start wazuh-dashboard.service")
    central.wait_for_unit("wazuh-dashboard.service", timeout=service_timeout)

    central.succeed(
        ". /run/wazuh-credentials/credentials.env; curl --fail --silent --cacert /var/lib/wazuh-certificates/root-ca.pem "
        "--user \"$INDEXER_USERNAME:$INDEXER_PASSWORD\" https://127.0.0.1:9200/_cluster/health"
    )
    central.succeed(
        ". /run/wazuh-credentials/credentials.env; curl --fail --silent --insecure --user \"$API_USERNAME:$API_PASSWORD\" "
        "--request POST 'https://127.0.0.1:55000/security/user/authenticate?raw=true' | grep -q ."
    )
    central.succeed(
        ". /run/wazuh-credentials/credentials.env; curl --fail --silent --insecure --user \"$API_ADMIN_USERNAME:$API_ADMIN_PASSWORD\" "
        "--request POST 'https://127.0.0.1:55000/security/user/authenticate?raw=true' | grep -q ."
    )
    central.fail(
        "curl --fail --silent --insecure --user wazuh-wui:wazuh-wui "
        "--request POST 'https://127.0.0.1:55000/security/user/authenticate?raw=true'"
    )
    central.fail(
        "curl --fail --silent --insecure --user wazuh:wazuh "
        "--request POST 'https://127.0.0.1:55000/security/user/authenticate?raw=true'"
    )
    central.succeed(
        "grep -q 'https://127.0.0.1:9200' /var/ossec/etc/ossec.conf"
    )
    central.succeed("test -s /etc/wazuh-dashboard/opensearch_dashboards.keystore")
    central.succeed("grep -qxF 'server.ssl.enabled: false' /etc/wazuh-dashboard/opensearch_dashboards.yml")
    central.succeed("! grep -q '^server.ssl.\\(certificate\\|key\\):' /etc/wazuh-dashboard/opensearch_dashboards.yml")
    central.succeed(
        ". /run/wazuh-credentials/credentials.env; ${pkgs.jq}/bin/jq "
        "--arg password \"$API_PASSWORD\" -e "
        "'.hosts[0][\"1513629884013\"] | "
        ".url == \"https://127.0.0.1\" and .password == $password' "
        "/var/lib/wazuh-dashboard/wazuh/config/wazuh.yml"
    )
    central.wait_until_succeeds(
        ". /run/wazuh-credentials/credentials.env; curl --fail --silent --user \"$INDEXER_USERNAME:$INDEXER_PASSWORD\" "
        "http://127.0.0.1:5601/api/status >/dev/null",
        timeout=poll_timeout,
    )

    central.succeed(
        "printf '%s\\n' "
        "'{\"timestamp\":\"2026-08-27T12:00:00.000+0000\",\"rule\":{\"level\":3,\"description\":\"native central stack test\",\"id\":\"100001\",\"groups\":[\"test\"]},\"agent\":{\"id\":\"000\",\"name\":\"central\"},\"manager\":{\"name\":\"central\"},\"id\":\"1756296000.1\",\"full_log\":\"native-central-stack-test\",\"decoder\":{\"name\":\"json\"},\"location\":\"nixos-test\"}' "
        ">> /var/ossec/logs/alerts/alerts.json"
    )
    central.wait_until_succeeds(
        ". /run/wazuh-credentials/credentials.env; curl --fail --silent --cacert /var/lib/wazuh-certificates/root-ca.pem --user \"$INDEXER_USERNAME:$INDEXER_PASSWORD\" "
        "'https://127.0.0.1:9200/_cat/indices/wazuh-alerts-4.x-*?h=index' | grep -q wazuh-alerts-4.x-",
        timeout=poll_timeout,
    )

    central.succeed("systemctl restart wazuh-dashboard.service")
    central.wait_for_unit("wazuh-dashboard.service", timeout=service_timeout)
    central.wait_until_succeeds(
        ". /run/wazuh-credentials/credentials.env; curl --fail --silent --user \"$INDEXER_USERNAME:$INDEXER_PASSWORD\" "
        "http://127.0.0.1:5601/api/status >/dev/null",
        timeout=poll_timeout,
    )
    central.succeed("systemctl restart wazuh-filebeat.service")
    central.wait_for_unit("wazuh-filebeat.service", timeout=service_timeout)

    central.succeed("systemctl restart wazuh-manager.service")
    central.wait_for_unit("wazuh-manager.service", timeout=service_timeout)
    central.wait_for_unit("wazuh-filebeat.service", timeout=service_timeout)
    central.wait_for_unit("wazuh-dashboard.service", timeout=service_timeout)
    central.wait_until_succeeds(
        ". /run/wazuh-credentials/credentials.env; curl --fail --silent --insecure --user \"$API_USERNAME:$API_PASSWORD\" "
        "--request POST 'https://127.0.0.1:55000/security/user/authenticate?raw=true' | grep -q .",
        timeout=poll_timeout,
    )
    central.wait_until_succeeds(
        ". /run/wazuh-credentials/credentials.env; curl --fail --silent --insecure --user \"$API_ADMIN_USERNAME:$API_ADMIN_PASSWORD\" "
        "--request POST 'https://127.0.0.1:55000/security/user/authenticate?raw=true' | grep -q .",
        timeout=poll_timeout,
    )
    central.wait_until_succeeds(
        ". /run/wazuh-credentials/credentials.env; curl --fail --silent --user \"$INDEXER_USERNAME:$INDEXER_PASSWORD\" "
        "http://127.0.0.1:5601/api/status >/dev/null",
        timeout=poll_timeout,
    )

    central.succeed("systemctl restart wazuh-indexer.service")
    central.wait_for_unit("wazuh-indexer.service", timeout=service_timeout)
    central.wait_for_unit("wazuh-indexer-security.service", timeout=service_timeout)
    central.wait_for_unit("wazuh-manager.service", timeout=service_timeout)
    central.wait_for_unit("wazuh-filebeat.service", timeout=service_timeout)
    central.wait_for_unit("wazuh-dashboard.service", timeout=service_timeout)
    central.wait_until_succeeds(
        ". /run/wazuh-credentials/credentials.env; curl --fail --silent --cacert /var/lib/wazuh-certificates/root-ca.pem --user \"$INDEXER_USERNAME:$INDEXER_PASSWORD\" "
        "'https://127.0.0.1:9200/_cluster/health?wait_for_status=green&"
        "wait_for_no_relocating_shards=true&wait_for_no_initializing_shards=true&timeout=180s' >/dev/null",
        timeout=service_timeout,
    )
    central.wait_until_succeeds(
        ". /run/wazuh-credentials/credentials.env; curl --fail --silent --insecure --user \"$API_USERNAME:$API_PASSWORD\" "
        "--request POST 'https://127.0.0.1:55000/security/user/authenticate?raw=true' | grep -q .",
        timeout=poll_timeout,
    )
    central.wait_until_succeeds(
        ". /run/wazuh-credentials/credentials.env; curl --fail --silent --insecure --user \"$API_ADMIN_USERNAME:$API_ADMIN_PASSWORD\" "
        "--request POST 'https://127.0.0.1:55000/security/user/authenticate?raw=true' | grep -q .",
        timeout=poll_timeout,
    )
    central.wait_until_succeeds(
        ". /run/wazuh-credentials/credentials.env; curl --fail --silent --user \"$INDEXER_USERNAME:$INDEXER_PASSWORD\" "
        "http://127.0.0.1:5601/api/status >/dev/null",
        timeout=poll_timeout,
    )

    central.succeed(
        "printf '%s\\n' "
        "'{\"timestamp\":\"2026-08-28T12:00:00.000+0000\",\"rule\":{\"level\":3,\"description\":\"native central stack restart test\",\"id\":\"100002\",\"groups\":[\"test\"]},\"agent\":{\"id\":\"000\",\"name\":\"central\"},\"manager\":{\"name\":\"central\"},\"id\":\"1756382400.2\",\"full_log\":\"native-central-stack-restart-test\",\"decoder\":{\"name\":\"json\"},\"location\":\"nixos-test\"}' "
        ">> /var/ossec/logs/alerts/alerts.json"
    )
    central.wait_until_succeeds(
        ". /run/wazuh-credentials/credentials.env; curl --fail --silent --cacert /var/lib/wazuh-certificates/root-ca.pem --user \"$INDEXER_USERNAME:$INDEXER_PASSWORD\" "
        "--header 'Content-Type: application/json' "
        "--data '{\"query\":{\"match_phrase\":{\"full_log\":\"native-central-stack-restart-test\"}}}' "
        "'https://127.0.0.1:9200/wazuh-alerts-4.x-*/_count' | "
        "${pkgs.jq}/bin/jq -e '.count >= 1'",
        timeout=poll_timeout,
    )

    central.succeed(
        "! journalctl --boot --dmesg --no-pager | grep -E 'wazuh-modulesd.*segfault'"
    )
    central.succeed(
        "! journalctl --boot --no-pager -t systemd-coredump | grep -F wazuh-modulesd"
    )
  '';
}
