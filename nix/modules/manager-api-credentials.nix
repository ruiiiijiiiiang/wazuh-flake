{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.wazuh.manager;
  credentialProvisioner = pkgs.writeText "wazuh-manager-api-credentials.py" (
    builtins.readFile ../scripts/manager-api-credentials.py
  );
in
{
  options.services.wazuh.manager.apiCredentials.enable = lib.mkOption {
    type = lib.types.bool;
    default = cfg.environmentFile != null;
    defaultText = lib.literalExpression "services.wazuh.manager.environmentFile != null";
    description = ''
      Provision the reserved Wazuh API users from API_USERNAME, API_PASSWORD,
      API_ADMIN_USERNAME, and API_ADMIN_PASSWORD in the manager environment
      file.
    '';
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !cfg.enable || !cfg.apiCredentials.enable || cfg.environmentFile != null;
          message = "Wazuh manager API credential provisioning requires services.wazuh.manager.environmentFile.";
        }
      ];
    }
    (lib.mkIf (cfg.enable && cfg.apiCredentials.enable) {
      systemd.services = {
        wazuh-manager.wants = [ "wazuh-manager-api-credentials.service" ];

        wazuh-manager-api-credentials = {
          description = "Provision Wazuh manager API credentials";
          requires = [ "wazuh-manager.service" ];
          after = [ "wazuh-manager.service" ];
          before = [ "wazuh-dashboard.service" ];
          serviceConfig = {
            Type = "oneshot";
            EnvironmentFile = cfg.environmentFile;
            UMask = "0077";
            ExecStart = pkgs.writeShellScript "wazuh-manager-api-credentials" /* bash */ ''
              set -eu
              : "''${API_USERNAME:?API_USERNAME must be set in the manager environment file}"
              : "''${API_PASSWORD:?API_PASSWORD must be set in the manager environment file}"
              : "''${API_ADMIN_USERNAME:?API_ADMIN_USERNAME must be set in the manager environment file}"
              : "''${API_ADMIN_PASSWORD:?API_ADMIN_PASSWORD must be set in the manager environment file}"

              remaining=60
              database=/var/ossec/api/configuration/security/rbac.db
              while [ "$remaining" -gt 0 ] && [ ! -s "$database" ]; do
                sleep 1
                remaining=$((remaining - 1))
              done
              if [ ! -s "$database" ]; then
                echo "Wazuh API RBAC database did not become ready" >&2
                exit 1
              fi

              exec /var/ossec/framework/python/bin/python3 ${credentialProvisioner}
            '';
          };
        };
      };
    })
  ];
}
