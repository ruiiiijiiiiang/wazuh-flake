{ pkgs }:

let
  inherit (pkgs) lib;
  release = import ./release.nix;
  inherit (release) version;

  # Wazuh's official package repository uses amd64/arm64 for Debian packages.
  debArch = if pkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "amd64";
  filebeatVersion = "7.10.2";
  filebeatModuleVersion = "0.4";

  componentHashes = release.hashes;

  fetchWazuhDeb =
    {
      name,
      fileName,
      sha256,
    }:
    pkgs.fetchurl {
      url = "https://packages.wazuh.com/4.x/apt/pool/main/w/${name}/${fileName}";
      inherit sha256;
    };

  fetchElasticDeb =
    {
      fileName,
      sha256,
    }:
    pkgs.fetchurl {
      url = "https://artifacts.elastic.co/downloads/beats/filebeat/${fileName}";
      inherit sha256;
    };

  unpackDeb =
    {
      pname,
      src,
      packageVersion ? version,
      patchNativeBinaries ? false,
      autoPatchelfIgnoreMissingDeps ? [ ],
      extraBuildInputs ? [ ],
      postUnpack ? "",
    }:
    pkgs.stdenvNoCC.mkDerivation {
      inherit pname src autoPatchelfIgnoreMissingDeps;
      version = packageVersion;
      nativeBuildInputs = [ pkgs.dpkg ] ++ lib.optional patchNativeBinaries pkgs.autoPatchelfHook;
      buildInputs =
        lib.optionals patchNativeBinaries [
          pkgs.glibc
          pkgs.elfutils.out
          pkgs.libgcc
          pkgs.openssl
          pkgs.zlib
        ]
        ++ extraBuildInputs;
      unpackPhase = ''
        dpkg-deb -x "$src" source
        ${postUnpack}
      '';
      installPhase = ''
        chmod -R u+rwX,go+rX source
        mkdir -p "$out"
        # Keep the package's /etc and /usr layout intact.  The native modules
        # select which mutable paths are exposed at runtime.
        cp -a source/. "$out/"
      '';
      dontStrip = true;
      passthru = {
        version = packageVersion;
        sourceArtifact = src;
      };
    };

  agent = unpackDeb {
    pname = "wazuh-agent";
    src = fetchWazuhDeb {
      name = "wazuh-agent";
      fileName = "wazuh-agent_${version}-1_${debArch}.deb";
      sha256 = componentHashes.${debArch}.agent;
    };
    patchNativeBinaries = true;
  };

  manager = unpackDeb {
    pname = "wazuh-manager";
    src = fetchWazuhDeb {
      name = "wazuh-manager";
      fileName = "wazuh-manager_${version}-1_${debArch}.deb";
      sha256 = componentHashes.${debArch}.manager;
    };
    patchNativeBinaries = true;
    # These belong to optional modules in Wazuh's bundled Python runtime. The
    # manager daemons and API do not require them, and several target obsolete
    # Debian SONAMEs that are intentionally absent from current nixpkgs.
    autoPatchelfIgnoreMissingDeps = [
      "libX11.so.6"
      "libcrypt.so.1"
      "libgdbm.so.4"
      "libgdbm_compat.so.4"
      "libncursesw.so.5"
      "libnsl.so.2"
      "libpanelw.so.5"
      "libreadline.so.6"
      "libtcl8.5.so"
      "libtinfo.so.5"
      "libtirpc.so.1"
      "libtirpc.so.3"
      "libtk8.5.so"
      "libuuid.so.1"
    ];
  };

  indexer = unpackDeb {
    pname = "wazuh-indexer";
    src = fetchWazuhDeb {
      name = "wazuh-indexer";
      fileName = "wazuh-indexer_${version}-1_${debArch}.deb";
      sha256 = componentHashes.${debArch}.indexer;
    };
    patchNativeBinaries = true;
    # OpenSearch runs headless; these libraries are referenced only by the
    # bundled JDK's desktop, splash-screen, and Java Sound modules.
    autoPatchelfIgnoreMissingDeps = [
      "libX11.so.6"
      "libXext.so.6"
      "libXi.so.6"
      "libXrender.so.1"
      "libXtst.so.6"
      "libasound.so.2"
    ];
  };

  dashboard = unpackDeb {
    pname = "wazuh-dashboard";
    src = fetchWazuhDeb {
      name = "wazuh-dashboard";
      fileName = "wazuh-dashboard_${version}-1_${debArch}.deb";
      sha256 = componentHashes.${debArch}.dashboard;
    };
    patchNativeBinaries = true;
    extraBuildInputs = [ pkgs.stdenv.cc.cc.lib ];
  };

  filebeatModule = pkgs.fetchurl {
    url = "https://packages.wazuh.com/4.x/filebeat/wazuh-filebeat-${filebeatModuleVersion}.tar.gz";
    sha256 = componentHashes.common.filebeatModule;
  };

  filebeatTemplate = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/wazuh/wazuh/v${version}/extensions/elasticsearch/7.x/wazuh-template.json";
    sha256 = componentHashes.common.filebeatTemplate;
  };

  filebeat = unpackDeb {
    pname = "wazuh-filebeat";
    packageVersion = filebeatVersion;
    src = fetchElasticDeb {
      fileName = "filebeat-oss-${filebeatVersion}-${debArch}.deb";
      sha256 = componentHashes.${debArch}.filebeat;
    };
    patchNativeBinaries = true;
    postUnpack = ''
      tar -xzf ${filebeatModule} -C source/usr/share/filebeat/module
      install -m 0644 ${filebeatTemplate} source/etc/filebeat/wazuh-template.json
    '';
  };
in
{
  inherit
    agent
    manager
    indexer
    dashboard
    filebeat
    ;
}
