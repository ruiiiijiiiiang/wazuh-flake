{
  config,
  lib,
  ...
}:

let
  cfg = config.services.wazuh;
in
{
  options.services.wazuh.version = lib.mkOption {
    type = lib.types.str;
    default = "4.14.5";
    description = "Wazuh version shared by all package defaults.";
  };

  config.assertions = [
    {
      assertion = cfg.version == "4.14.5";
      message = "Wazuh ${cfg.version} is not packaged by this flake yet.";
    }
  ];
}
