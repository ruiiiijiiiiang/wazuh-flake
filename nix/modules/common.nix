{ lib, ... }:

let
  release = import ../release.nix;
in
{
  options.services.wazuh.version = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    default = release.version;
    description = "Wazuh version packaged by this flake.";
  };
}
