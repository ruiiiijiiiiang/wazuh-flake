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

Certificate and credential provisioning can be delegated to the flake for
standalone central stacks. It generates a persistent local CA, service
identities, and passwords at runtime, never placing private keys or passwords
in the Nix store. Externally managed certificates and credentials remain
supported.

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

The generated agent configuration is a generic enrollment baseline. Add
host-specific monitoring policy through `extraConfig`; use `config` only when
replacing the whole generated configuration:

```nix
services.wazuh.agent.extraConfig = /* xml */ ''
  <localfile>
    <log_format>journald</log_format>
    <location>journald</location>
  </localfile>
'';
```

A central host can enable all four server-side services without supplying
certificate files or internal service credentials. It only needs a managed
dashboard-administrator password:

```nix
{
  services.wazuh = {
    certificates.autoProvision = {
      enable = true;
      indexer.subjectAltNames = [ "DNS:wazuh.example" "IP:10.0.0.10" ];
    };
    credentials.autoProvision = {
      enable = true;
      indexerPasswordFile = "/run/agenix/wazuh-dashboard-admin-password";
    };

    manager = {
      enable = true;
    };

    filebeat = {
      enable = true;
    };

    indexer = {
      enable = true;
      securityBootstrap = {
        enable = true;
      };
    };

    dashboard = {
      enable = true;
    };
  };
}
```

With no dashboard certificate and key, the dashboard serves HTTP on its
localhost bind address for a local TLS-terminating reverse proxy. Set both
`services.wazuh.dashboard.certificates.certificate` and `key` to enable HTTPS
directly on the dashboard listener.

Automatic provisioning is intended for a standalone indexer. Its state is
stored in `/var/lib/wazuh-certificates` with mode `0700`; back up this directory
to preserve the deployment's TLS identity. Changing the generated indexer
certificate SANs after first boot does not rotate it. For a multi-node cluster,
externally trusted endpoint, or coordinated certificate rotation, leave
`services.wazuh.certificates.autoProvision.enable` disabled and use the
existing per-component `certificates` options.

Automatic credential provisioning fixes the interactive dashboard username to
`admin`, reads its password from `indexerPasswordFile`, and generates the three
internal service passwords. Generated state is stored in
`/var/lib/wazuh-credentials`, owned by `root:root` with mode `0700`. The module
combines it with the dashboard administrator password in a root-only runtime
environment file consumed by the manager, indexer bootstrap, Filebeat, and
dashboard. Generated passwords are created once and never rotated implicitly.

`indexerPasswordFile` must contain exactly one non-whitespace password line;
an agenix secret is a suitable source. For a headless deployment with no human
dashboard login, set `generateIndexerPassword = true` instead. That password is
then generated and persisted alongside the internal credentials.

For externally managed credentials, leave
`services.wazuh.credentials.autoProvision.enable` disabled and configure each
component's `environmentFile`. That file must contain `INDEXER_USERNAME=admin`,
`DASHBOARD_USERNAME=kibanaserver`, `API_USERNAME=wazuh-wui`,
`API_ADMIN_USERNAME=wazuh`, and their passwords. The two API passwords must be
different and meet Wazuh's password policy.

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
| Generated certificates | `/var/lib/wazuh-certificates` | Local CA and service identities when certificate auto-provisioning is enabled |
| Generated credentials | `/var/lib/wazuh-credentials` | Component passwords when credential auto-provisioning is enabled |

Generated certificate and credential directories are deployment identity. Back
them up together, encrypted, and off-host. In interactive deployments, also
back up the externally managed `indexerPasswordFile`. Do not restore only one
of these identities or delete them while retaining the OpenSearch security
index: the saved credentials must continue to match its stored password hashes,
and the saved certificates must remain the TLS identity used by its clients.

If only manager configuration and enrollment identity need to survive, back up
`/var/ossec/etc`; alert logs do not need to be retained. Back up the rest of
`/var/ossec` when agent metadata and queue state are also required.

Indexer alert data does not need to be backed up when event retention is not a
requirement. If it is retained, use an OpenSearch snapshot or a storage
snapshot taken while the indexer is stopped; do not file-copy a live data
directory. Filebeat and dashboard state can be reconstructed from the module,
runtime credentials, and certificates.

### Recovery sequence

To restore a deployment, keep Wazuh services stopped on a fresh host and
restore the generated certificate and credential directories together with
their root ownership and modes. In interactive deployments, make the saved
dashboard administrator password available again through `indexerPasswordFile`.
Restore `/var/ossec/etc` when enrolled agents must reconnect without enrollment,
then restore an OpenSearch snapshot when alert history or the security index
must be preserved. Enable and start Wazuh only after those restores; the
provisioning services see the complete existing state and leave it unchanged.

For an intentional clean deployment, restore none of those directories and do
not restore the OpenSearch snapshot. New identities and credentials will be
generated, the security bootstrap will initialize a new index, and agents must
enroll again.

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

The manager preparation step runs on every manager start. Automatic
provisioning deliberately never rotates an existing CA, service identity, or
password; replace its persisted certificate and credential state only as a
coordinated maintenance operation. For externally managed certificates and
credentials, replace all related secret files first, then rerun the
corresponding prepare unit before restarting each service. Rerun
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
