{
  description = "Native NixOS modules for the Wazuh agent and central components";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      packagesFor = system: import ./nix/packages.nix { pkgs = import nixpkgs { inherit system; }; };
    in
    {
      packages = forAllSystems packagesFor;

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = [ pkgs.nixfmt ];
          };
        }
      );

      nixosModules = {
        default = import ./nix/module.nix;
        wazuh = import ./nix/module.nix;
        agent = import ./nix/module.nix;
        manager = import ./nix/module.nix;
        indexer = import ./nix/module.nix;
        dashboard = import ./nix/module.nix;
        filebeat = import ./nix/module.nix;
      };

      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        packagesFor system
        // {
          module-evaluation = import ./tests/module-evaluation.nix { inherit pkgs; };
          manager-restart-stress = import ./tests/manager-restart-stress.nix { inherit pkgs; };
          manager-secret-isolation = import ./tests/manager-secret-isolation.nix { inherit pkgs; };
          security-bootstrap = import ./tests/security-bootstrap.nix { inherit pkgs; };
          central-stack = import ./tests/central-stack.nix { inherit pkgs; };
        }
      );

      formatter = forAllSystems (system: (import nixpkgs { inherit system; }).nixfmt);
    };
}
