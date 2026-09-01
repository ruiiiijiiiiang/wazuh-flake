{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.wazuh.certificates.autoProvision;
  indexerSan = lib.concatStringsSep "," cfg.indexer.subjectAltNames;
in
{
  options.services.wazuh.certificates.autoProvision = {
    enable = lib.mkEnableOption "automatic Wazuh certificate provisioning";
    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/wazuh-certificates";
      description = ''
        Persistent, root-owned directory containing the generated CA and
        service private keys. This directory must be backed up to preserve
        the deployment's TLS identity.
      '';
    };
    indexer.subjectAltNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "IP:127.0.0.1"
        "DNS:localhost"
        "DNS:node-1"
      ];
      description = "Subject alternative names for the generated Wazuh indexer certificate.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.indexer.subjectAltNames != [ ];
        message = "services.wazuh.certificates.autoProvision.indexer.subjectAltNames must not be empty.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 root root -"
    ];

    systemd.services.wazuh-certificates = {
      description = "Provision local Wazuh TLS certificates";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0077";
        ExecStart = pkgs.writeShellScript "wazuh-certificate-provision" ''
          set -eu
          state_dir=${lib.escapeShellArg (toString cfg.stateDir)}
          openssl=${pkgs.openssl}/bin/openssl
          umask 077
          install -d -m 0700 -o root -g root "$state_dir"

          ensure_complete_pair() {
            certificate="$1"
            key="$2"
            if { [ -e "$certificate" ] && [ ! -e "$key" ]; } \
              || { [ ! -e "$certificate" ] && [ -e "$key" ]; }; then
              echo "Refusing to replace partial certificate state: $certificate / $key" >&2
              exit 1
            fi
          }

          ensure_complete_pair "$state_dir/root-ca.pem" "$state_dir/root-ca-key.pem"
          if [ ! -e "$state_dir/root-ca.pem" ]; then
            "$openssl" req -x509 -newkey rsa:3072 -nodes -sha256 -days 3650 \
              -subj "/C=US/L=California/O=Wazuh/OU=Wazuh/CN=Wazuh local root CA" \
              -keyout "$state_dir/root-ca-key.pem" \
              -out "$state_dir/root-ca.pem"
          fi

          make_certificate() {
            name="$1"
            common_name="$2"
            subject_alt_name="$3"
            extended_key_usage="$4"
            certificate="$state_dir/$name.pem"
            key="$state_dir/$name-key.pem"
            csr="$state_dir/$name.csr"
            extension="$state_dir/$name.ext"

            ensure_complete_pair "$certificate" "$key"
            if [ -e "$certificate" ]; then
              return
            fi

            "$openssl" req -newkey rsa:3072 -nodes -sha256 \
              -subj "/C=US/L=California/O=Wazuh/OU=Wazuh/CN=$common_name" \
              -keyout "$key" \
              -out "$csr"
            {
              if [ -n "$subject_alt_name" ]; then
                printf 'subjectAltName=%s\n' "$subject_alt_name"
              fi
              printf 'extendedKeyUsage=%s\n' "$extended_key_usage"
            } > "$extension"
            "$openssl" x509 -req -sha256 -days 825 \
              -in "$csr" \
              -CA "$state_dir/root-ca.pem" \
              -CAkey "$state_dir/root-ca-key.pem" \
              -CAcreateserial \
              -extfile "$extension" \
              -out "$certificate"
            rm -f "$csr" "$extension"
          }

          make_certificate indexer node-1 ${lib.escapeShellArg indexerSan} "serverAuth,clientAuth"
          make_certificate admin admin "" "clientAuth"
          make_certificate filebeat wazuh-server "" "clientAuth"

          chown root:root "$state_dir"/*
          chmod 0600 "$state_dir"/*
        '';
      };
    };
  };
}
