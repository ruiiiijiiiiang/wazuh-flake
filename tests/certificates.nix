{ pkgs }:

pkgs.runCommand "wazuh-test-certificates" { nativeBuildInputs = [ pkgs.openssl ]; } ''
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
''
