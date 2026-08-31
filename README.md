# wazuh-flake

Reusable NixOS modules for running Wazuh without containers.

The flake consumes official Wazuh and Elastic release artifacts and provides
native systemd services for the agent, manager, indexer, dashboard, and the
Filebeat alert pipeline. It does not rebuild Wazuh's C++, Java, or Node.js
projects from source.

## Status

The package URLs and hashes are pinned to Wazuh 4.14.7 for x86_64-linux and
aarch64-linux. All central components are kept at the same patch version, and
the release hashes are centralized near the top of `nix/packages.nix`.
Wazuh 4.14.7 includes the
[vulnerability-scanner shutdown fix](https://github.com/wazuh/wazuh/pull/36011)
first released in 4.14.6; 4.14.5 is not supported by this flake because its
manager can crash while stopping a disabled or partially initialized scanner.

The Debian maintainer scripts are intentionally not executed. The modules
reproduce the required setup, including permissions and the manager enrollment
certificate, while preserving Wazuh's expected runtime paths under
`/var/ossec`. The manager's bundled Python runtime and vulnerability database
remain store-backed instead of being copied on every service restart.

The x86_64 NixOS VM tests cover agent and manager first boot and restart. A
focused manager test verifies that credentials are written to the Wazuh
keystore without being inherited by the long-running manager processes. A
manager lifecycle regression test performs five consecutive restarts and fails
on any `wazuh-modulesd` kernel segfault or coredump. Manager-only tests use a
standalone XML profile that disables vulnerability indexing; the complete-stack
test exercises the indexer-backed configuration. A
separate end-to-end test boots the complete TLS-enabled central stack,
initializes OpenSearch security, replaces both default manager API passwords,
authenticates with the provisioned credentials, starts the dashboard, forwards
an alert through Filebeat, verifies the resulting index, restarts every central
service, and verifies API and alert-pipeline recovery afterward.

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
      securityBootstrap = {
        enable = true;
        environmentFile = credentials;
      };
    };

    dashboard = {
      enable = true;
      environmentFile = credentials;
      certificates = {
        inherit rootCA;
      };
    };
  };
}
```

With no dashboard certificate and key, the dashboard serves HTTP on its
localhost bind address for a local TLS-terminating reverse proxy. Set both
`services.wazuh.dashboard.certificates.certificate` and `key` to enable HTTPS
directly on the dashboard listener.

The environment file must contain these shell-style assignments:

```bash
INDEXER_USERNAME=admin
INDEXER_PASSWORD=replace-me
DASHBOARD_USERNAME=kibanaserver
DASHBOARD_PASSWORD=replace-me
API_USERNAME=wazuh-wui
API_PASSWORD=Replace-This1!
API_ADMIN_USERNAME=wazuh
API_ADMIN_PASSWORD=Replace-Admin1!
```

`API_USERNAME` must be `wazuh-wui`, and `API_ADMIN_USERNAME` must be `wazuh`.
Both API passwords must be different, 8-64 characters long, and contain an
uppercase letter, a lowercase letter, a number, and a special character. These
requirements ensure that neither upstream reserved administrator account keeps
its default password.

The environment file can be an agenix secret such as
`config.age.secrets.wazuh-credentials.path`. Agenix decrypts it at runtime, so
the plaintext values do not enter the Nix store. A root-owned mode of `0400` is
sufficient because systemd reads the environment file for the preparation
units.

To retain a customized manager configuration declaratively, keep the XML next
to the consuming NixOS configuration and set:

```nix
services.wazuh.manager.config = builtins.readFile ./wazuh-manager-ossec.conf;
```

When this option is empty, the manager starts from the upstream package
configuration and keeps its mutable copy under `/var/ossec/etc/ossec.conf`.

The manager environment file is read only by short-lived preparation and API
credential units. The preparation unit writes the indexer username and password
to Wazuh's keystore, then exits before the manager starts. After the manager has
initialized its RBAC database, the credential unit updates the reserved
`wazuh-wui` and `wazuh` API users only when their passwords differ and
invalidates those users' existing API tokens. Neither unit passes plaintext
variables to the long-running manager daemons. Both units run as part of every
manager start, and the API credential unit also runs before a local dashboard
starts.

Manager API credential provisioning defaults to enabled whenever
`services.wazuh.manager.environmentFile` is set. It can be controlled explicitly
with `services.wazuh.manager.apiCredentials.enable`.

On a fresh installation, the security bootstrap hashes `INDEXER_PASSWORD` and
`DASHBOARD_PASSWORD` at runtime and replaces the bundled passwords for the
reserved `admin` and `kibanaserver` users before loading the security
configuration. Plaintext passwords are not written to the Nix store. The
bootstrap waits for both accounts to authenticate before writing its marker
under `/var/lib/wazuh-indexer`.

If a security index already exists but the local marker is missing, bootstrap
fails instead of overwriting it. Set
`services.wazuh.indexer.securityBootstrap.adoptExisting = true` for one
activation to verify and adopt that index without changing its contents.

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

## Production operations

### Startup and health

On an all-in-one host, systemd orders indexer preparation, indexer startup,
one-time security initialization, manager preparation, the manager, Filebeat,
and the dashboard. A normal boot does not require manually starting components
in sequence.

Use both unit state and application-level checks when validating a deployment:

```console
sudo systemctl --failed
sudo systemctl is-active \
  wazuh-indexer.service \
  wazuh-indexer-security.service \
  wazuh-manager.service \
  wazuh-filebeat.service \
  wazuh-dashboard.service
```

The application checks should confirm all of the following:

- `GET https://127.0.0.1:9200/_cluster/health` authenticates with the indexer
  credentials and reports at least yellow health (green for the default
  single-node configuration).
- `POST https://127.0.0.1:55000/security/user/authenticate?raw=true`
  authenticates with the Wazuh API credentials.
- `GET http://127.0.0.1:5601/api/status` returns successfully with an
  authorized indexer account. Use HTTPS instead when dashboard TLS is enabled.
- A fresh record appended by the manager appears in a
  `wazuh-alerts-4.x-*` index. Unit health alone does not prove this Filebeat
  path.

The integrated VM test allocates four vCPUs, 6 GiB of memory, and a 24 GiB
disk. That is a test fixture, not a production sizing recommendation. Monitor
indexer heap pressure and disk use and size the host for its actual agent and
retention load.

Wazuh 4.14.7's `wazuh-modulesd` aborts in its inventory teardown path when the
indexer integration is enabled. For that configuration, this module kills only
`wazuh-modulesd` before asking `wazuh-control` to stop the remaining daemons;
standalone managers keep the normal graceful stop path. The central-stack test
guards against the resulting segfault and core dump. Reassess and remove this
workaround when upgrading Wazuh after the same test demonstrates that upstream
shutdown is safe.

### Persistent state and backups

The default mutable paths are:

| Component | Paths | Purpose |
| --- | --- | --- |
| Manager | `/var/ossec` | Configuration, enrollment identity, agent state, queues, and logs |
| Indexer | `/var/lib/wazuh-indexer`, `/etc/wazuh-indexer` | OpenSearch data and prepared runtime configuration |
| Filebeat | `/var/lib/filebeat`, `/etc/filebeat` | Registry, keystore, and prepared runtime configuration |
| Dashboard | `/var/lib/wazuh-dashboard`, `/etc/wazuh-dashboard` | Plugin data, keystore, and prepared runtime configuration |

Keep the Nix configuration and the external certificate and secret sources as
the authoritative configuration backup. If only configuration and enrollment
identity need to survive, back up `/var/ossec/etc`; alert logs do not need to
be retained. Back up the rest of `/var/ossec` when agent metadata and queue
state are also required.

Indexer alert data does not need to be backed up when event retention is not a
requirement. If it is retained, use an OpenSearch snapshot or a storage
snapshot taken while the indexer is stopped; do not file-copy a live data
directory. Filebeat and dashboard state can be reconstructed from the module,
runtime credentials, and certificates.

### Credential and certificate rotation

The security bootstrap only sets the initial `admin` and `kibanaserver`
passwords. After initialization, rotate those accounts through the OpenSearch
Security API or Wazuh's password tooling, then update the runtime environment
file. Changing that file alone does not update passwords stored in the
security index.

Preparation units for Filebeat and the dashboard remain active after their
first successful run. Explicitly rerun them after changing credentials or
certificates:

```console
sudo systemctl restart wazuh-manager.service
sudo systemctl restart wazuh-manager-api-credentials.service
sudo systemctl restart wazuh-filebeat-prepare.service
sudo systemctl restart wazuh-filebeat.service
sudo systemctl restart wazuh-dashboard-prepare.service
sudo systemctl restart wazuh-dashboard.service
```

The manager preparation step runs on every manager start. For certificate
rotation, replace all related secret files first, then rerun the corresponding
prepare unit before restarting each service. Rerun
`wazuh-indexer-prepare.service` before restarting the indexer. Rotate a root CA
and all certificates issued by it as one coordinated maintenance operation.

### Upgrades and rollback

Treat a Wazuh update as an atomic central-stack change:

1. Update the shared Wazuh version and every architecture-specific release
   hash in `nix/packages.nix`. Update Filebeat inputs only when Wazuh's release
   requires it.
2. Build all packages and run the security-bootstrap, manager lifecycle, secret
   isolation, and central-stack tests.
3. Take the required manager backup and, when alert retention matters, an
   indexer snapshot.
4. Deploy the indexer, manager, Filebeat, and dashboard from the same flake
   revision. Upgrade agents afterward and never make them newer than the
   manager.
5. Verify unit state, all three authenticated APIs, and delivery of a new alert.

A NixOS generation rollback restores packages and unit definitions, but it
does not roll mutable state back. Do not start an older indexer against data
that a newer release has migrated unless upstream explicitly supports that
downgrade. Restore the matching indexer snapshot or roll forward instead.

## Validation

```console
nix flake check
nix flake check --all-systems --no-build
nix build .#agent .#manager .#indexer .#dashboard .#filebeat --no-link
nix build .#checks.x86_64-linux.manager-secret-isolation
nix build .#checks.x86_64-linux.manager-restart-stress
nix build .#checks.x86_64-linux.security-bootstrap
nix build .#checks.x86_64-linux.central-stack
```
