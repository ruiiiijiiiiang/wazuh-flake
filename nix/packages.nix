{
  pkgs,
  version ? "4.14.5",
}:

let
  inherit (pkgs) lib;

  # Wazuh's official package repository uses amd64/arm64 for Debian packages.
  debArch = if pkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "amd64";

  hashes = {
    "4.14.5" = {
      amd64 = {
        agent = "78d22932d6556974f67bd4884341609681dc632ea744dbd7255d704a5fd5d70d";
        manager = "2f9010e6c32009fdc7f3af748ec6139659db80837d769e7a46e1f99b684fd29b";
        indexer = "e2ecb7bcb4c5726ffdcc5885d666eed341ff254f08c270d858ef5a3e91d8ad53";
        dashboard = "c978861c8d160517104030c9f887e3ede7f6e9de4b117b794063bd8a2f7759af";
      };
      arm64 = {
        agent = "5e9eee2bf8be136317ea14f4d97ce3c595a7be1bc553b4af64563bda28e2fe32";
        manager = "273e086542bd3efc3f35a0d5eb69531341a9d4e387038f90b36ce7b8d3bcaa80";
        indexer = "dbb600d6c1a220928ca843fa56091eadee5798815c34bd5f6be3a41c7ecb061b";
        dashboard = "edf9f837c9f43265421f31c9d21e8129b81ae850ade1e5c74eb126c4d0cefc0e";
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

  unpackDeb =
    {
      pname,
      src,
      patchNativeBinaries ? false,
    }:
    pkgs.stdenvNoCC.mkDerivation {
      inherit pname version src;
      nativeBuildInputs = [ pkgs.dpkg ] ++ lib.optional patchNativeBinaries pkgs.autoPatchelfHook;
      buildInputs = lib.optionals patchNativeBinaries [
        pkgs.glibc
        pkgs.libgcc
        pkgs.openssl
        pkgs.zlib
      ];
      unpackPhase = "dpkg-deb -x $src source";
      installPhase = ''
        mkdir -p "$out"
        # Keep the package's /etc and /usr layout intact.  The native modules
        # select which mutable paths are exposed at runtime.
        cp -a source/. "$out/"
      '';
      dontStrip = true;
      passthru = {
        inherit version;
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
  };

  indexer = unpackDeb {
    pname = "wazuh-indexer";
    src = fetchWazuhDeb {
      name = "wazuh-indexer";
      fileName = "wazuh-indexer_${version}-1_${debArch}.deb";
      sha256 = componentHashes.${debArch}.indexer;
    };
  };

  dashboard = unpackDeb {
    pname = "wazuh-dashboard";
    src = fetchWazuhDeb {
      name = "wazuh-dashboard";
      fileName = "wazuh-dashboard_${version}-1_${debArch}.deb";
      sha256 = componentHashes.${debArch}.dashboard;
    };
  };
in
{
  inherit
    agent
    manager
    indexer
    dashboard
    ;
}
