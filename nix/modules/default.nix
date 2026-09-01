{
  imports = [
    ./common.nix
    ./certificates.nix
    ./agent.nix
    ./manager.nix
    ./manager-api-credentials.nix
    ./filebeat.nix
    ./indexer.nix
    ./indexer-security.nix
    ./dashboard.nix
  ];
}
