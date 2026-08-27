# wazuh-flake

Reusable NixOS modules for running Wazuh without containers.

The flake consumes official Wazuh and Elastic release artifacts and provides
native systemd services for the agent, manager, indexer, dashboard, and the
Filebeat alert pipeline. It does not rebuild Wazuh's C++, Java, or Node.js
projects from source.

## Status

The package URLs and hashes are pinned to Wazuh 4.14.5 for x86_64-linux and
aarch64-linux. All central components are kept at the same patch version, and
the release hashes are centralized near the top of `nix/packages.nix`.

The Debian maintainer scripts are intentionally not executed. The modules
reproduce the required setup, including permissions and the manager enrollment
certificate, while preserving Wazuh's expected runtime paths under
`/var/ossec`. The manager's bundled Python runtime and vulnerability database
remain store-backed instead of being copied on every service restart.

The x86_64 NixOS VM tests cover agent and manager first boot and restart. A
separate end-to-end test boots the complete TLS-enabled central stack,
initializes OpenSearch security, authenticates with the manager API, starts the
dashboard, forwards an alert through Filebeat, verifies the resulting index,
and restarts all non-indexer services.

Certificate generation and existing state migration remain outside this
flake's scope. The module installs supplied certificates and provisions
component keystores from a runtime environment file without placing passwords
in the Nix store.

## Usage

Add the input and import the shared module:

```nix
{
  inputs.wazuh.url = "github:ruiiiijiiiiang/wazuh-flake";

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

A central host enables all four server-side services and supplies the
certificates generated for its Wazuh deployment. The same protected runtime
environment file can be shared by the manager, Filebeat, and dashboard:

```nix
let
  credentials = "/run/agenix/wazuh-credentials";
  rootCA = "/run/agenix/wazuh-root-ca";
in
{
  services.wazuh = {
    manager = {
      enable = true;
      environmentFile = credentials;
    };

    filebeat = {
      enable = true;
      environmentFile = credentials;
      certificates = {
        inherit rootCA;
        certificate = "/run/agenix/wazuh-filebeat-cert";
        key = "/run/agenix/wazuh-filebeat-key";
      };
    };

    indexer = {
      enable = true;
      certificates = {
        inherit rootCA;
        nodeCertificate = "/run/agenix/wazuh-indexer-cert";
        nodeKey = "/run/agenix/wazuh-indexer-key";
        adminCertificate = "/run/agenix/wazuh-admin-cert";
        adminKey = "/run/agenix/wazuh-admin-key";
      };
      securityBootstrap.enable = true;
    };

    dashboard = {
      enable = true;
      environmentFile = credentials;
      certificates = {
        inherit rootCA;
        certificate = "/run/agenix/wazuh-dashboard-cert";
        key = "/run/agenix/wazuh-dashboard-key";
      };
    };
  };
}
```

The environment file must contain these shell-style assignments:

```bash
INDEXER_USERNAME=admin
INDEXER_PASSWORD=replace-me
DASHBOARD_USERNAME=kibanaserver
DASHBOARD_PASSWORD=replace-me
API_USERNAME=wazuh-wui
API_PASSWORD=replace-me
```

The indexer security configuration must contain matching users and password
hashes. On a fresh installation, `securityBootstrap.enable` loads the security
configuration bundled by the official Wazuh package once and writes its marker
under `/var/lib/wazuh-indexer`. Supply credentials that match that configuration
or preserve your existing indexer state and security index.

The agent and manager cannot be enabled on the same host because both use
`/var/ossec`. Manager enrollment uses a locally generated one-year self-signed
certificate by default; set `services.wazuh.manager.certificates` to provide a
managed certificate and key instead.

Indexer and dashboard ports bind to localhost and remain closed in the firewall
by default. Use `services.wazuh.indexer.openFirewall` or
`services.wazuh.dashboard.openFirewall` only when direct network access is
required. The manager event and enrollment ports are opened when the manager is
enabled; its API remains closed unless `services.wazuh.manager.openApiPort` is
set.

Wazuh central components must use identical versions, including patch level.
Agents should not be newer than their manager.

## Validation

```console
nix flake check
nix flake check --all-systems --no-build
nix build .#checks.x86_64-linux.central-stack
```
