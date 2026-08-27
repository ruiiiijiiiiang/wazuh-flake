# wazuh-flake

Reusable NixOS modules for running Wazuh without containers.

The flake consumes official Wazuh Debian release artifacts and provides native
systemd services for the agent, manager, indexer, and dashboard. It does not
rebuild Wazuh's C++, Java, or Node.js projects from source.

## Status

The package URLs and hashes are pinned to Wazuh 4.14.5 and are kept in
lockstep across all central components. Update them together when upgrading.

The Debian maintainer scripts are intentionally not executed. NixOS modules
must reproduce only the required setup declaratively; the package layer keeps
the complete `/etc`, `/usr`, and `/var` payload so those files remain available
to the native services.

The module still needs production hardening around TLS/certificate generation,
indexer security-admin initialization, migration of existing container state,
and complete declarative manager/dashboard configuration.

## Usage

```nix
inputs.wazuh-flake.url = "path:/path/to/wazuh-flake";

imports = [ inputs.wazuh-flake.nixosModules.default ];

services.wazuh = {
  version = "4.14.5";

  agent = {
    enable = true;
    managerAddress = "10.0.0.2";
  };

  manager.enable = true;
  indexer.enable = true;
  dashboard.enable = true;
};
```

Wazuh central components must use identical versions, including patch level.
Agents should not be newer than their manager.
