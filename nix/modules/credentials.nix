{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.wazuh.credentials.autoProvision;
  environmentFile = "/run/wazuh-credentials/credentials.env";
in
{
  options.services.wazuh.credentials.autoProvision = {
    enable = lib.mkEnableOption "automatic Wazuh credential provisioning";
    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/wazuh-credentials";
      description = ''
        Persistent, root-owned directory containing the generated Wazuh
        component credentials. This directory must be backed up with the
        Wazuh deployment state.
      '';
    };
    indexerPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Root-readable file containing the one-line Wazuh dashboard administrator
        password. The username is always admin. Use an externally managed secret
        for interactive dashboard access.
      '';
    };
    generateIndexerPassword = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Generate and persist the Wazuh dashboard administrator password instead
        of reading indexerPasswordFile. Intended for headless deployments.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.indexerPasswordFile != null || cfg.generateIndexerPassword;
        message = ''
          Wazuh automatic credential provisioning requires
          services.wazuh.credentials.autoProvision.indexerPasswordFile unless
          generateIndexerPassword is enabled.
        '';
      }
      {
        assertion = cfg.indexerPasswordFile == null || !cfg.generateIndexerPassword;
        message = ''
          Wazuh automatic credential provisioning accepts either
          indexerPasswordFile or generateIndexerPassword, not both.
        '';
      }
    ];

    services.wazuh = {
      manager.environmentFile = lib.mkDefault environmentFile;
      filebeat.environmentFile = lib.mkDefault environmentFile;
      indexer.securityBootstrap.environmentFile = lib.mkDefault environmentFile;
      dashboard.environmentFile = lib.mkDefault environmentFile;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 root root -"
    ];

    systemd.services.wazuh-credentials = {
      description = "Provision local Wazuh credentials";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "wazuh-credentials";
        RuntimeDirectoryMode = "0700";
        UMask = "0077";
        ExecStart = pkgs.writeShellScript "wazuh-credential-provision" /* bash */ ''
          set -eu
          state_dir=${lib.escapeShellArg (toString cfg.stateDir)}
          internal_credentials_file="$state_dir/internal.env"
          generated_indexer_password_file="$state_dir/indexer-password"
          state_marker="$state_dir/.initialized"
          runtime_credentials_file=/run/wazuh-credentials/credentials.env
          coreutils=${pkgs.coreutils}
          grep=${pkgs.gnugrep}/bin/grep
          umask 077
          install -d -m 0700 -o root -g root "$state_dir"

          if { [ -e "$state_marker" ] && [ ! -e "$internal_credentials_file" ]; } \
            || { [ ! -e "$state_marker" ] && [ -e "$internal_credentials_file" ]; }; then
            echo "Refusing to replace incomplete Wazuh credential state in $state_dir" >&2
            exit 1
          fi

          ${lib.optionalString (cfg.indexerPasswordFile != null) ''
            indexer_password="$("$coreutils/bin/cat" ${lib.escapeShellArg (toString cfg.indexerPasswordFile)})"
            if [ -z "$indexer_password" ] || printf '%s' "$indexer_password" | "$grep" -q '[[:space:]]'; then
              echo "Wazuh indexer password must be a single non-whitespace line" >&2
              exit 1
            fi
          ''}

          required_variables='DASHBOARD_USERNAME DASHBOARD_PASSWORD API_USERNAME API_PASSWORD API_ADMIN_USERNAME API_ADMIN_PASSWORD'
          if [ -e "$internal_credentials_file" ]; then
            for variable in $required_variables; do
              if ! "$grep" -q "^$variable=." "$internal_credentials_file"; then
                echo "Refusing to replace incomplete Wazuh credential state: $internal_credentials_file" >&2
                exit 1
              fi
            done
            if [ "$("$coreutils/bin/stat" -c '%U:%G:%a' "$internal_credentials_file")" != root:root:600 ]; then
              echo "Refusing to use insecure Wazuh credential state: $internal_credentials_file" >&2
              exit 1
            fi
          else
            generate_password() {
              random="$($coreutils/bin/tr -dc 'A-Za-z0-9' < /dev/urandom | $coreutils/bin/head -c 24)"
              printf '%sAa1!\n' "$random"
            }

            dashboard_password="$(generate_password)"
            api_password="$(generate_password)"
            api_admin_password="$(generate_password)"
            while [ "$api_password" = "$api_admin_password" ]; do
              api_admin_password="$(generate_password)"
            done

            temporary_file="$state_dir/.internal.env.$$"
            cleanup() {
              rm -f "$temporary_file"
            }
            trap cleanup EXIT
            {
              printf 'DASHBOARD_USERNAME=kibanaserver\n'
              printf 'DASHBOARD_PASSWORD=%s\n' "$dashboard_password"
              printf 'API_USERNAME=wazuh-wui\n'
              printf 'API_PASSWORD=%s\n' "$api_password"
              printf 'API_ADMIN_USERNAME=wazuh\n'
              printf 'API_ADMIN_PASSWORD=%s\n' "$api_admin_password"
            } > "$temporary_file"
            chown root:root "$temporary_file"
            chmod 0600 "$temporary_file"
            mv "$temporary_file" "$internal_credentials_file"
            trap - EXIT
          fi

          ${lib.optionalString cfg.generateIndexerPassword ''
            if [ -e "$generated_indexer_password_file" ]; then
              if [ "$("$coreutils/bin/stat" -c '%U:%G:%a' "$generated_indexer_password_file")" != root:root:600 ]; then
                echo "Refusing to use insecure generated indexer password state" >&2
                exit 1
              fi
            elif [ -e "$state_marker" ]; then
              echo "Refusing to replace incomplete generated indexer password state" >&2
              exit 1
            else
              "$coreutils/bin/tr" -dc 'A-Za-z0-9' < /dev/urandom | "$coreutils/bin/head" -c 24 > "$generated_indexer_password_file"
              printf 'Aa1!\n' >> "$generated_indexer_password_file"
              chown root:root "$generated_indexer_password_file"
              chmod 0600 "$generated_indexer_password_file"
            fi
            indexer_password="$("$coreutils/bin/cat" "$generated_indexer_password_file")"
          ''}
          if [ -z "$indexer_password" ] || printf '%s' "$indexer_password" | "$grep" -q '[[:space:]]'; then
            echo "Wazuh indexer password must be a single non-whitespace line" >&2
            exit 1
          fi

          {
            printf 'INDEXER_USERNAME=admin\n'
            printf 'INDEXER_PASSWORD=%s\n' "$indexer_password"
            "$coreutils/bin/cat" "$internal_credentials_file"
          } > "$runtime_credentials_file"
          chown root:root "$runtime_credentials_file"
          chmod 0400 "$runtime_credentials_file"
          if [ ! -e "$state_marker" ]; then
            install -m 0600 -o root -g root /dev/null "$state_marker"
          fi
        '';
      };
    };
  };
}
