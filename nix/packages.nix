{
  pkgs,
  version ? "4.14.7",
}:

let
  inherit (pkgs) lib;

  # Wazuh's official package repository uses amd64/arm64 for Debian packages.
  debArch = if pkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "amd64";
  filebeatVersion = "7.10.2";
  filebeatModuleVersion = "0.4";

  hashes = {
    "4.14.7" = {
      common = {
        filebeatModule = "b0683f1d5d7c5d076ea3a565b0aa7ca92e6483f8a14e8b96799e6ee632da2284";
        filebeatTemplate = "c6e30822c67c10f7e777cb51926e261d8b2c3a941c4ffcf83325f700c1c8802f";
      };
      amd64 = {
        agent = "5276281b62e887065ecc14d4463cea529cf418529538c8edd6769c9ec550213f";
        manager = "1edd93f49ea1d89edcb7c17eeec750e99f685bc9f88d3c71f7972267c9442de0";
        indexer = "5657623a3607c9f0c3d64100b03972dd037110744bc6448382a0e0af57b95570";
        dashboard = "83f472d9e5f59b28b1abb6260c466e77b99ae427ce8c5f76203d847f2f598b6f";
        filebeat = "f759a13e5407bba184d9f0235ab88409a0d77d821e64adb3dcc0ba8e397f0201";
      };
      arm64 = {
        agent = "e5a6c90414caa9bb20ed56c3aa0f20ab7c36534632e91e968ede51e8b340da74";
        manager = "a53e85a0a89b850fdcc2b0249f723ca1f8284cee9b2a44446a1cd4a9767e8611";
        indexer = "d3d43a6a3357807eeb10e6fc6abc55910777cc5163cd4b1559df9d439b4deee5";
        dashboard = "4ef75c90167182b282ac09fed3473e394313ab1326b0072c617d69e67c4be21a";
        filebeat = "93860759c538813cfe34f88a4e4047fba45fead287a7d11fea8957c1d816cfd9";
      };
    };
  };
  componentHashes =
    hashes.${version} or (throw "Unsupported Wazuh version ${version}; add its artifact hashes first.");

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
