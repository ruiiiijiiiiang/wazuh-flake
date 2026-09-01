{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.wazuh.indexer;
  certificateCfg = config.services.wazuh.certificates.autoProvision;
  bootstrapCfg = cfg.securityBootstrap;
  indexerHealthHost =
    if cfg.bindAddress == "0.0.0.0" then
      "127.0.0.1"
    else if cfg.bindAddress == "::" then
      "[::1]"
    else if lib.hasInfix ":" cfg.bindAddress then
      "[${cfg.bindAddress}]"
    else
      cfg.bindAddress;
in
{
  options.services.wazuh.indexer.securityBootstrap = {
    enable = lib.mkEnableOption "Wazuh indexer security bootstrap";
    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Runtime environment file containing INDEXER_USERNAME,
        INDEXER_PASSWORD, DASHBOARD_USERNAME, and DASHBOARD_PASSWORD.
      '';
    };
    adoptExisting = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Adopt an existing OpenSearch security index by writing the local
        initialization marker without replacing the index contents.
      '';
    };
    initializedFile = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/wazuh-indexer/.security-initialized";
      description = "Marker file written after securityadmin initialization.";
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !bootstrapCfg.enable || cfg.enable;
          message = "services.wazuh.indexer.securityBootstrap requires services.wazuh.indexer.enable.";
        }
        {
          assertion =
            !bootstrapCfg.enable || bootstrapCfg.adoptExisting || bootstrapCfg.environmentFile != null;
          message = ''
            services.wazuh.indexer.securityBootstrap.environmentFile is
            required when initializing a new security index.
          '';
        }
        {
          assertion =
            !bootstrapCfg.enable
            || (
              certificateCfg.enable
              || (
                cfg.certificates.rootCA != null
                && cfg.certificates.nodeCertificate != null
                && cfg.certificates.nodeKey != null
                && cfg.certificates.adminCertificate != null
                && cfg.certificates.adminKey != null
              )
            );
          message = "Wazuh indexer security bootstrap requires all indexer certificates.";
        }
      ];
    }
    (lib.mkIf (cfg.enable && bootstrapCfg.enable) {
      systemd.services.wazuh-indexer-security = {
        description = "Initialize Wazuh indexer security configuration";
        wantedBy = [ "multi-user.target" ];
        requires = [
          "wazuh-indexer.service"
          "wazuh-indexer-prepare.service"
        ];
        after = [ "wazuh-indexer.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          EnvironmentFile = lib.optional (bootstrapCfg.environmentFile != null) bootstrapCfg.environmentFile;
          Environment = "OPENSEARCH_JAVA_HOME=${cfg.package}/usr/share/wazuh-indexer/jdk";
          RuntimeDirectory = "wazuh-indexer-security";
          RuntimeDirectoryMode = "0700";
          UMask = "0077";
          ExecStart = pkgs.writeShellScript "wazuh-indexer-security-bootstrap" ''
            set -eu
            if [ -e ${bootstrapCfg.initializedFile} ]; then
              exit 0
            fi

            runtime_dir=/run/wazuh-indexer-security
            security_config="$runtime_dir/opensearch-security"
            security_index_response="$runtime_dir/security-index-response"
            cleanup() {
              rm -rf "$security_config"
              rm -f "$security_index_response"
            }
            trap cleanup EXIT
            rm -rf "$security_config"
            rm -f "$security_index_response"

            security_index_status=$(
              ${pkgs.curl}/bin/curl \
                --silent \
                --show-error \
                --cacert ${cfg.configDir}/certs/root-ca.pem \
                --cert ${cfg.configDir}/certs/admin.pem \
                --key ${cfg.configDir}/certs/admin-key.pem \
                --output "$security_index_response" \
                --write-out '%{http_code}' \
                "https://${indexerHealthHost}:${toString cfg.port}/_cat/indices/.opendistro_security?h=index" \
                || true
            )

            security_index_exists=false
            if [ "$security_index_status" = 200 ] \
              && grep -qxF .opendistro_security "$security_index_response"; then
              security_index_exists=true
            elif [ "$security_index_status" != 200 ] \
              && [ "$security_index_status" != 404 ] \
              && [ "$security_index_status" != 503 ]; then
              echo "Unable to determine whether the OpenSearch security index exists (HTTP $security_index_status)" >&2
              exit 1
            fi

            ${lib.optionalString bootstrapCfg.adoptExisting ''
              if [ "$security_index_exists" != true ]; then
                echo "Cannot adopt an existing OpenSearch security index because none was found" >&2
                exit 1
              fi
              install -D -m 0640 -o wazuh-indexer -g wazuh-indexer /dev/null ${bootstrapCfg.initializedFile}
              exit 0
            ''}

            if [ "$security_index_exists" = true ]; then
              echo "The OpenSearch security index already exists but the local initialization marker is missing" >&2
              echo "Set services.wazuh.indexer.securityBootstrap.adoptExisting = true to adopt it without overwriting it" >&2
              exit 1
            fi

            : "''${INDEXER_USERNAME:?INDEXER_USERNAME must be set in the security bootstrap environment file}"
            : "''${INDEXER_PASSWORD:?INDEXER_PASSWORD must be set in the security bootstrap environment file}"
            : "''${DASHBOARD_USERNAME:?DASHBOARD_USERNAME must be set in the security bootstrap environment file}"
            : "''${DASHBOARD_PASSWORD:?DASHBOARD_PASSWORD must be set in the security bootstrap environment file}"
            if [ "$INDEXER_USERNAME" != admin ]; then
              echo "INDEXER_USERNAME must be admin for the bundled Wazuh security roles" >&2
              exit 1
            fi
            if [ "$DASHBOARD_USERNAME" != kibanaserver ]; then
              echo "DASHBOARD_USERNAME must be kibanaserver for the bundled Wazuh security roles" >&2
              exit 1
            fi

            cp -a ${cfg.configDir}/opensearch-security "$security_config"
            chmod -R u+rwX,go-rwx "$security_config"

            hash_tool=${cfg.package}/usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh
            INDEXER_PASSWORD_HASH=$("$hash_tool" -env INDEXER_PASSWORD)
            DASHBOARD_PASSWORD_HASH=$("$hash_tool" -env DASHBOARD_PASSWORD)
            export INDEXER_PASSWORD_HASH DASHBOARD_PASSWORD_HASH

            ${pkgs.yq-go}/bin/yq --exit-status \
              '.admin.hash and .kibanaserver.hash' \
              "$security_config/internal_users.yml" >/dev/null
            ${pkgs.yq-go}/bin/yq --inplace \
              '.admin.hash = strenv(INDEXER_PASSWORD_HASH) | .kibanaserver.hash = strenv(DASHBOARD_PASSWORD_HASH)' \
              "$security_config/internal_users.yml"

            ${cfg.package}/usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
              -cd "$security_config" \
              -icl -nhnv \
              -cacert ${cfg.configDir}/certs/root-ca.pem \
              -cert ${cfg.configDir}/certs/admin.pem \
              -key ${cfg.configDir}/certs/admin-key.pem

            security_ready=false
            for attempt in $(seq 1 60); do
              if ${pkgs.curl}/bin/curl \
                --fail \
                --silent \
                --cacert ${cfg.configDir}/certs/root-ca.pem \
                --user "$INDEXER_USERNAME:$INDEXER_PASSWORD" \
                "https://${indexerHealthHost}:${toString cfg.port}/_cluster/health" \
                >/dev/null \
                && ${pkgs.curl}/bin/curl \
                  --fail \
                  --silent \
                  --cacert ${cfg.configDir}/certs/root-ca.pem \
                  --user "$DASHBOARD_USERNAME:$DASHBOARD_PASSWORD" \
                  "https://${indexerHealthHost}:${toString cfg.port}/_plugins/_security/authinfo" \
                  >/dev/null; then
                security_ready=true
                break
              fi
              sleep 1
            done
            if [ "$security_ready" != true ]; then
              echo "OpenSearch security configuration was loaded but did not become ready" >&2
              exit 1
            fi

            install -D -m 0640 -o wazuh-indexer -g wazuh-indexer /dev/null ${bootstrapCfg.initializedFile}
          '';
        };
      };
    })
  ];
}
