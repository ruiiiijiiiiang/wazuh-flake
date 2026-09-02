{ pkgs, ... }:

{
  _module.args.wazuhPackages = import ../packages.nix { inherit pkgs; };

  imports = [
    ./common.nix
    ./certificates.nix
    ./credentials.nix
    ./agent.nix
    ./manager.nix
    ./manager-api-credentials.nix
    ./filebeat.nix
    ./indexer.nix
    ./indexer-security.nix
    ./dashboard.nix
  ];
}
