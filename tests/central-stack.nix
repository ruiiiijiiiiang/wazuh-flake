{ pkgs }:

let
  certificates = import ./certificates.nix { inherit pkgs; };

  credentials = pkgs.writeText "wazuh-central-test-credentials" ''
    INDEXER_USERNAME=admin
    INDEXER_PASSWORD=native-indexer-test
    DASHBOARD_USERNAME=kibanaserver
    DASHBOARD_PASSWORD=native-dashboard-test
    API_USERNAME=wazuh-wui
    API_PASSWORD=wazuh-wui
  '';
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
        diskSize = 16384;
        memorySize = 6144;
      };

      services.wazuh = {
        manager = {
          enable = true;
          environmentFile = credentials;
        };

        filebeat = {
          enable = true;
          environmentFile = credentials;
          certificates = {
            rootCA = "${certificates}/root-ca.pem";
            certificate = "${certificates}/filebeat.pem";
            key = "${certificates}/filebeat-key.pem";
          };
        };

        indexer = {
          enable = true;
          certificates = {
            rootCA = "${certificates}/root-ca.pem";
            nodeCertificate = "${certificates}/node-1.pem";
            nodeKey = "${certificates}/node-1-key.pem";
            adminCertificate = "${certificates}/admin.pem";
            adminKey = "${certificates}/admin-key.pem";
          };
          securityBootstrap = {
            enable = true;
            environmentFile = credentials;
          };
        };

        dashboard = {
          enable = true;
          environmentFile = credentials;
          certificates = {
            rootCA = "${certificates}/root-ca.pem";
            certificate = "${certificates}/dashboard.pem";
            key = "${certificates}/dashboard-key.pem";
          };
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
    central.wait_for_unit("wazuh-manager.service", timeout=service_timeout)
    central.wait_for_unit("wazuh-filebeat.service", timeout=service_timeout)
    central.succeed(
        "curl --fail --silent --cacert ${certificates}/root-ca.pem --user admin:native-indexer-test "
        "'https://127.0.0.1:9200/_cluster/health?wait_for_status=green&"
        "wait_for_no_relocating_shards=true&wait_for_no_initializing_shards=true&timeout=180s'"
    )
    central.succeed("systemctl start wazuh-dashboard.service")
    central.wait_for_unit("wazuh-dashboard.service", timeout=service_timeout)

    central.succeed(
        "curl --fail --silent --cacert ${certificates}/root-ca.pem "
        "--user admin:native-indexer-test https://127.0.0.1:9200/_cluster/health"
    )
    central.succeed(
        "curl --fail --silent --insecure --user wazuh-wui:wazuh-wui "
        "--request POST 'https://127.0.0.1:55000/security/user/authenticate?raw=true' | grep -q ."
    )
    central.succeed(
        "grep -q 'https://127.0.0.1:9200' /var/ossec/etc/ossec.conf"
    )
    central.succeed("test -s /etc/wazuh-dashboard/opensearch_dashboards.keystore")
    central.succeed(
        "${pkgs.jq}/bin/jq -e "
        "'.hosts[0][\"1513629884013\"].url == \"https://127.0.0.1\"' "
        "/var/lib/wazuh-dashboard/wazuh/config/wazuh.yml"
    )
    central.wait_until_succeeds(
        "curl --fail --silent --insecure --user admin:native-indexer-test "
        "https://127.0.0.1:5601/api/status >/dev/null",
        timeout=poll_timeout,
    )

    central.succeed(
        "printf '%s\\n' "
        "'{\"timestamp\":\"2026-08-27T12:00:00.000+0000\",\"rule\":{\"level\":3,\"description\":\"native central stack test\",\"id\":\"100001\",\"groups\":[\"test\"]},\"agent\":{\"id\":\"000\",\"name\":\"central\"},\"manager\":{\"name\":\"central\"},\"id\":\"1756296000.1\",\"full_log\":\"native-central-stack-test\",\"decoder\":{\"name\":\"json\"},\"location\":\"nixos-test\"}' "
        ">> /var/ossec/logs/alerts/alerts.json"
    )
    central.wait_until_succeeds(
        "curl --fail --silent --cacert ${certificates}/root-ca.pem --user admin:native-indexer-test "
        "'https://127.0.0.1:9200/_cat/indices/wazuh-alerts-4.x-*?h=index' | grep -q wazuh-alerts-4.x-",
        timeout=poll_timeout,
    )

    central.succeed("systemctl restart wazuh-manager.service")
    central.wait_for_unit("wazuh-manager.service", timeout=service_timeout)
    central.succeed("systemctl restart wazuh-filebeat.service")
    central.wait_for_unit("wazuh-filebeat.service", timeout=service_timeout)
    central.succeed("systemctl restart wazuh-dashboard.service")
    central.wait_for_unit("wazuh-dashboard.service", timeout=service_timeout)
  '';
}
