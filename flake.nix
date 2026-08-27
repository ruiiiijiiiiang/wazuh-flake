{
  description = "Native NixOS modules for the Wazuh agent and central components";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    inputs@{ self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        import ./nix/packages.nix { inherit pkgs; }
      );

      nixosModules = {
        default = import ./nix/module.nix;
        wazuh = import ./nix/module.nix;
        agent = import ./nix/module.nix;
        manager = import ./nix/module.nix;
        indexer = import ./nix/module.nix;
        dashboard = import ./nix/module.nix;
      };

      formatter = forAllSystems (system: (import nixpkgs { inherit system; }).nixfmt-rfc-style);
    };
}
