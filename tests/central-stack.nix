{ pkgs }:

let
  certificates =
    pkgs.runCommand "wazuh-central-test-certificates" { nativeBuildInputs = [ pkgs.openssl ]; }
      ''
        set -eu
        mkdir -p "$out"

        openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 2 \
          -subj "/C=US/L=California/O=Wazuh/OU=Wazuh/CN=Wazuh root CA" \
          -keyout "$out/root-ca-key.pem" \
          -out "$out/root-ca.pem"

        make_certificate() {
          name="$1"
          common_name="$2"
          subject_alt_name="$3"
          extended_key_usage="$4"
          openssl req -newkey rsa:2048 -nodes -sha256 \
            -subj "/C=US/L=California/O=Wazuh/OU=Wazuh/CN=$common_name" \
            -keyout "$out/$name-key.pem" \
            -out "$out/$name.csr"
          {
            if [ -n "$subject_alt_name" ]; then
              printf 'subjectAltName=%s\n' "$subject_alt_name"
            fi
            printf 'extendedKeyUsage=%s\n' "$extended_key_usage"
          } > "$out/$name.ext"
          openssl x509 -req -sha256 -days 2 \
            -in "$out/$name.csr" \
            -CA "$out/root-ca.pem" \
            -CAkey "$out/root-ca-key.pem" \
            -CAcreateserial \
            -extfile "$out/$name.ext" \
            -out "$out/$name.pem"
          rm "$out/$name.csr" "$out/$name.ext"
        }

        make_certificate node-1 node-1 \
          "IP:127.0.0.1,DNS:localhost,DNS:node-1" "serverAuth,clientAuth"
        make_certificate admin admin "" "clientAuth"
        make_certificate filebeat wazuh-server "" "clientAuth"
        make_certificate dashboard wazuh-dashboard \
          "IP:127.0.0.1,DNS:localhost,DNS:wazuh-dashboard" "serverAuth"
      '';

  credentials = pkgs.writeText "wazuh-central-test-credentials" ''
    INDEXER_USERNAME=admin
    INDEXER_PASSWORD=admin
    DASHBOARD_USERNAME=kibanaserver
    DASHBOARD_PASSWORD=kibanaserver
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
          securityBootstrap.enable = true;
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
        "curl --fail --silent --cacert ${certificates}/root-ca.pem --user admin:admin "
        "'https://127.0.0.1:9200/_cluster/health?wait_for_status=green&"
        "wait_for_no_relocating_shards=true&wait_for_no_initializing_shards=true&timeout=180s'"
    )
    central.succeed("systemctl start wazuh-dashboard.service")
    central.wait_for_unit("wazuh-dashboard.service", timeout=service_timeout)

    central.succeed(
        "curl --fail --silent --cacert ${certificates}/root-ca.pem "
        "--user admin:admin https://127.0.0.1:9200/_cluster/health"
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
        "curl --fail --silent --insecure --user admin:admin "
        "https://127.0.0.1:5601/api/status >/dev/null",
        timeout=poll_timeout,
    )

    central.succeed(
        "printf '%s\\n' "
        "'{\"timestamp\":\"2026-08-27T12:00:00.000+0000\",\"rule\":{\"level\":3,\"description\":\"native central stack test\",\"id\":\"100001\",\"groups\":[\"test\"]},\"agent\":{\"id\":\"000\",\"name\":\"central\"},\"manager\":{\"name\":\"central\"},\"id\":\"1756296000.1\",\"full_log\":\"native-central-stack-test\",\"decoder\":{\"name\":\"json\"},\"location\":\"nixos-test\"}' "
        ">> /var/ossec/logs/alerts/alerts.json"
    )
    central.wait_until_succeeds(
        "curl --fail --silent --cacert ${certificates}/root-ca.pem --user admin:admin "
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
