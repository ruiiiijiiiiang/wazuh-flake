# wazuh-flake

Reusable NixOS modules for running Wazuh without containers.

The flake consumes official Wazuh Debian release artifacts and provides native
systemd services for the agent, manager, indexer, and dashboard. It does not
rebuild Wazuh's C++, Java, or Node.js projects from source.

## Status

The package URLs and hashes are pinned to Wazuh 4.14.5 for x86_64-linux and
aarch64-linux. All central components are kept at the same patch version, and
the release hashes are centralized near the top of `nix/packages.nix`.

The Debian maintainer scripts are intentionally not executed. The modules
reproduce the required setup, including permissions and the manager enrollment
certificate, while preserving Wazuh's expected runtime paths under
`/var/ossec`. The manager's bundled Python runtime and vulnerability database
remain store-backed instead of being copied on every service restart.

The agent and manager have x86_64 NixOS VM smoke tests covering first boot and
restart. The indexer and dashboard artifacts build natively and their bundled
Java and Node.js runtimes are patched for NixOS, but the complete TLS-enabled
central stack does not yet have an end-to-end VM test.

Before using the central stack in production, provide indexer and dashboard
certificates, initialize OpenSearch security, and configure alert forwarding
(normally Filebeat). Certificate generation for that stack and Filebeat setup
are intentionally not automated yet. Existing state migration is also outside
this flake's scope.

## Usage

Add the input and import the shared module:

```nix
{
  inputs.wazuh.url = "git+https://git.ruijiang.me/rui/wazuh-flake.git";

  outputs =
    { nixpkgs, wazuh, ... }:
    {
      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        modules = [
          wazuh.nixosModules.default
          ./configuration.nix
        ];
      };
    };
}
```

An agent host only needs the manager address:

```nix
services.wazuh.agent = {
  enable = true;
  managerAddress = "10.0.0.2";
};
```

A central host enables the three server components and supplies the
certificates generated for its Wazuh deployment:

```nix
services.wazuh = {
  manager.enable = true;

  indexer = {
    enable = true;
    certificates = {
      rootCA = "/run/agenix/wazuh-root-ca";
      nodeCertificate = "/run/agenix/wazuh-indexer-cert";
      nodeKey = "/run/agenix/wazuh-indexer-key";
      adminCertificate = "/run/agenix/wazuh-admin-cert";
      adminKey = "/run/agenix/wazuh-admin-key";
    };
    securityBootstrap.enable = true;
  };

  dashboard = {
    enable = true;
    certificates = {
      rootCA = "/run/agenix/wazuh-root-ca";
      certificate = "/run/agenix/wazuh-dashboard-cert";
      key = "/run/agenix/wazuh-dashboard-key";
    };
  };
};
```

The agent and manager cannot be enabled on the same host because both use
`/var/ossec`. Manager enrollment uses a locally generated one-year self-signed
certificate by default; set `services.wazuh.manager.certificates` to provide a
managed certificate and key instead.

Indexer and dashboard ports bind to localhost and remain closed in the firewall
by default. Use `services.wazuh.indexer.openFirewall` or
`services.wazuh.dashboard.openFirewall` only when direct network access is
required.

Wazuh central components must use identical versions, including patch level.
Agents should not be newer than their manager.

## Validation

```console
nix flake check
nix flake check --all-systems --no-build
```
