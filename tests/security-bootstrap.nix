{ pkgs }:

let
  certificates = import ./certificates.nix { inherit pkgs; };
  environmentFile = "/run/wazuh-test/indexer.env";
in
pkgs.testers.nixosTest {
  name = "wazuh-security-bootstrap";

  nodes.secure =
    { lib, ... }:
    {
      imports = [ ../nix/modules ];

      networking.hostName = "secure";
      virtualisation = {
        cores = 2;
        diskSize = 8192;
        memorySize = 4096;
      };

      services.wazuh.indexer = {
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
          inherit environmentFile;
        };
      };

      systemd.services.wazuh-test-indexer-credentials = {
        description = "Generate runtime-only Wazuh indexer test credentials";
        requiredBy = [ "wazuh-indexer-security.service" ];
        before = [ "wazuh-indexer-security.service" ];
        path = [ pkgs.coreutils ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          UMask = "0077";
        };
        script = ''
          seed=$(sha256sum /etc/machine-id | cut -c1-24)
          install -d -m 0700 /run/wazuh-test
          {
            printf 'INDEXER_USERNAME=admin\n'
            printf 'INDEXER_PASSWORD=indexer-%s\n' "$seed"
            printf 'DASHBOARD_USERNAME=kibanaserver\n'
            printf 'DASHBOARD_PASSWORD=dashboard-%s\n' "$seed"
          } > ${environmentFile}
          chmod 0600 ${environmentFile}
        '';
      };

      specialisation.adopt.configuration.services.wazuh.indexer.securityBootstrap = {
        adoptExisting = lib.mkForce true;
        environmentFile = lib.mkForce null;
      };
    };

  testScript = ''
    from datetime import timedelta

    service_timeout = timedelta(minutes=5)

    start_all()
    secure.wait_for_unit("wazuh-indexer-security.service", timeout=service_timeout)

    secure.succeed(
        ". ${environmentFile}; "
        "curl --fail --silent --cacert ${certificates}/root-ca.pem "
        "--user \"$INDEXER_USERNAME:$INDEXER_PASSWORD\" "
        "https://127.0.0.1:9200/_cluster/health"
    )
    secure.succeed(
        ". ${environmentFile}; "
        "curl --fail --silent --cacert ${certificates}/root-ca.pem "
        "--user \"$DASHBOARD_USERNAME:$DASHBOARD_PASSWORD\" "
        "https://127.0.0.1:9200/_plugins/_security/authinfo"
    )
    secure.fail(
        "curl --fail --silent --cacert ${certificates}/root-ca.pem "
        "--user admin:admin https://127.0.0.1:9200/_cluster/health"
    )
    secure.fail(
        "curl --fail --silent --cacert ${certificates}/root-ca.pem "
        "--user kibanaserver:kibanaserver "
        "https://127.0.0.1:9200/_plugins/_security/authinfo"
    )
    secure.succeed("test -e /var/lib/wazuh-indexer/.security-initialized")
    secure.succeed("test ! -e /run/wazuh-indexer-security/opensearch-security")
    secure.succeed(
        ". ${environmentFile}; "
        "! systemctl cat wazuh-indexer-security.service | grep -F \"$INDEXER_PASSWORD\""
    )

    secure.succeed(
        "marker_time=$(stat -c %Y /var/lib/wazuh-indexer/.security-initialized); "
        "sleep 1; systemctl restart wazuh-indexer-security.service; "
        "test \"$(stat -c %Y /var/lib/wazuh-indexer/.security-initialized)\" = \"$marker_time\""
    )

    secure.succeed(
        "rm /var/lib/wazuh-indexer/.security-initialized; "
        "printf 'INDEXER_USERNAME=admin\\n' > ${environmentFile}; "
        "chmod 0600 ${environmentFile}"
    )
    secure.fail("systemctl restart wazuh-indexer-security.service")
    secure.succeed("test ! -e /var/lib/wazuh-indexer/.security-initialized")
    secure.succeed(
        "journalctl -u wazuh-indexer-security.service --no-pager "
        "| grep -q 'security index already exists'"
    )

    secure.succeed("systemctl restart wazuh-test-indexer-credentials.service")
    secure.succeed(
        "/run/current-system/specialisation/adopt/bin/switch-to-configuration test"
    )
    secure.succeed("systemctl reset-failed wazuh-indexer-security.service")
    secure.succeed("systemctl restart wazuh-indexer-security.service")
    secure.succeed("test -e /var/lib/wazuh-indexer/.security-initialized")
    secure.succeed(
        ". ${environmentFile}; "
        "curl --fail --silent --cacert ${certificates}/root-ca.pem "
        "--user \"$INDEXER_USERNAME:$INDEXER_PASSWORD\" "
        "https://127.0.0.1:9200/_cluster/health"
    )
  '';
}
