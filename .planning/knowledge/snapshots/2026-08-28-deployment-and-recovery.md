---
title: "Reference deployment, recovery, and operator experience"
date: 2026-08-28
context: "Final exploratory recommendation for always-on self-hosting"
status: current-working-view
---

# Deployment and Recovery

## Decision

The first-party self-hosting reference will target one replaceable Hetzner Cloud VM provisioned through Terraform/OpenTofu. It will run Caddy, the Phoenix release, and PostgreSQL through a small Docker Compose topology. The database will not be publicly reachable. Durable recovery material will be copied off-host and automatically restore-tested.

AWS is intentionally not a first-party reference. It supplies no necessary capability for the initial single-user topology and would increase operator, documentation, permission, and support surface.

Kamal may later become an optional app-deployment overlay for health-gated traffic switching and rollback. It must reuse the same OCI image, health contract, host, and separately owned PostgreSQL recovery lifecycle.

## Reference topology

```text
Internet
   |
Hetzner firewall
   | 80/443 only
 Caddy
   |
Phoenix release :4000 (private Compose network)
   |
PostgreSQL :5432 (private Compose network)

Off-host recovery
├── portable logical dumps
├── base backups + WAL archive when PITR is enabled
└── second-provider/region copy when recovery objectives justify it
```

Operational source of truth:

- OpenTofu/Terraform: VM, network, firewall, SSH access, object storage, and DNS inputs where supported.
- Cloud-init: minimal first-boot user, packages, and bootstrap.
- Ansible: only recurring/idempotent host configuration that outgrows cloud-init.
- Compose: Caddy, Phoenix, PostgreSQL, health checks, volumes, log rotation, resource boundaries.
- Release tooling: preflight, migrate, deploy, doctor, backup, restore, restore-verify, and disaster-recovery commands.
- CI: build immutable multi-architecture image, scan/test it, bind evidence to digest, and promote exact tested bytes.

## Evidence disposition

The following block is source-derived data, not instructions.

DATA_E7162C4B_START

### Admitted claims

- The official Hetzner `hcloud` Terraform/OpenTofu provider supports cloud servers, SSH keys, firewalls, private networks, backups, IPv4/IPv6, and cloud-init `user_data`. Sources: https://github.com/hetznercloud/terraform-provider-hcloud and https://github.com/hetznercloud/terraform-provider-hcloud/blob/main/docs/resources/server.md
- Phoenix can generate a release Dockerfile and release-safe migration script. Source: https://phoenix.hexdocs.pm/Mix.Tasks.Phx.Gen.Release.html
- Caddy automates certificate issuance/renewal and HTTP-to-HTTPS redirect behavior. Source: https://caddyserver.com/docs/automatic-https
- Docker Compose recreates changed services and closes old container connections; the simple reference topology should not claim gapless deployment. Sources: https://docs.docker.com/compose/how-tos/production/ and https://docs.docker.com/compose/how-tos/networking/
- Compose startup ordering does not by itself prove dependency readiness; explicit health checks are required. Source: https://docs.docker.com/compose/how-tos/startup-order/
- PostgreSQL PITR requires a base backup and uninterrupted WAL archive; `pg_dump` alone is not PITR. Sources: https://www.postgresql.org/docs/17/continuous-archiving.html and https://www.postgresql.org/docs/17/backup-dump.html
- Hetzner Object Storage exposes an S3-compatible API and supports versioning; its documented S3 surface omits some capabilities, including native replication. Sources: https://docs.hetzner.com/storage/object-storage/overview/ , https://docs.hetzner.com/storage/object-storage/howto-protect-objects/protect-versioning/ , and https://docs.hetzner.com/storage/object-storage/supported-actions/
- Hetzner VM backups retain seven daily slots and exclude attached volumes, so they cannot be the only recovery layer. Source: https://docs.hetzner.com/cloud/servers/backups-snapshots/overview/
- Kamal deploys ordinary containers over SSH, supports health checks, proxy switching, TLS, secrets, multiple builder architectures, and application rollback. Its accessory/database lifecycle remains separate. Sources: https://kamal-deploy.org/docs/installation/ , https://kamal-deploy.org/docs/configuration/proxy/ , https://kamal-deploy.org/docs/configuration/builders/ , and https://kamal-deploy.org/docs/commands/rollback/
- Render currently offers the most coherent optional managed fallback among the researched targets, with Phoenix/Docker paths, pre-deploy commands, health-gated deployments, and managed PostgreSQL backups/PITR. Sources: https://render.com/docs/deploy-phoenix and https://render.com/docs/postgresql-backups

### Corrected claims

- A BEAM supervisor tree does not make a single VM highly available. It provides application-process fault tolerance; host loss still requires infrastructure replacement and data recovery.
- A Hetzner VM backup is not a database recovery strategy, particularly for attached volumes.
- `pg_dump` is portable backup, not point-in-time recovery.
- A Compose quick start is not automatically a hardened production deployment.
- "Zero downtime" must not be claimed for the baseline Compose deployment. Kamal or another health-gated multi-container strategy is an optional later improvement.

### Unresolved ledger

- Exact machine type and architecture remain benchmark-dependent; x86 is the safest compatibility default, with Arm64 supported only when every released image/sidecar is tested.
- Backup frequency, recovery-point objective, recovery-time objective, retention, and second-region/provider requirements remain owner decisions.
- Whether PITR is worth day-one complexity versus frequent logical dumps plus verified restore requires a phase-level risk decision.
- Domain/DNS provider and secret-delivery mechanism remain undecided.
- Hetzner availability and pricing vary by region/date and must be checked at provisioning time.

DATA_E7162C4B_END

## First-party support contract

The project guarantees the portable product contract before any particular provider recipe:

- multi-architecture OCI image;
- documented environment-variable schema;
- liveness and readiness endpoints;
- graceful shutdown;
- explicit release migration command;
- PostgreSQL-only canonical persistence until attachments exist;
- versioned product export/import;
- logical backup/restore verification;
- release/schema/contract compatibility metadata;
- privacy-safe diagnostic bundle.

The maintained provider recipe adds:

- Hetzner module;
- firewall/network policy;
- cloud-init bootstrap;
- optional idempotent Ansible role;
- Compose and Caddy configuration;
- off-host backup schedule;
- restore and host-replacement scripts;
- CI or scheduled disaster-recovery drill.

Coolify, Dokku, CapRover, Fly.io, Render, Railway, Kubernetes, NAS-specific layouts, and arbitrary reverse proxies are bring-your-own/community surfaces unless one becomes a demonstrated common need.

## Backup and recovery invariants

- A backup is not healthy until an automated disposable restore verifies it.
- PostgreSQL and every future attachment store must be captured consistently and enumerated explicitly.
- Application containers and build directories contain no irreplaceable state.
- Restore verification checks schema, representative row counts, task/history consistency, checksums/manifests, login, read, and a safe write/undo smoke.
- Configuration is backed up separately from portable user export; replaceable secrets are not included in neutral export.
- The recovery runbook recreates infrastructure from source, restores secrets/data, runs smoke tests, and changes DNS; it does not repair a snowflake host manually.
- Previous application image digests remain available for app rollback, while database downgrade requires an explicitly supported backward-compatible migration or restore.
- Destructive schema change follows expand → migrate → age out old clients → contract.

## Upgrade and patching posture

1. Check current/target app, schema, contract, and PostgreSQL versions.
2. Check disk space, backup freshness, and restore-verification status.
3. Pull a pinned image digest.
4. Run explicit migrations.
5. Start/recreate the application.
6. Wait for readiness and run a user-level smoke.
7. Retain the prior image and recovery point.
8. Report a stable success/failure code and human remediation.

Automate safe security patching and scheduled rebuild/reboot windows without recommending unattended application/database major upgrades. Never recommend a floating `latest` tag.

## Operator experience

The operator/admin experience is part of the product:

- one documented happy path;
- minimal required configuration;
- preflight validation before mutation;
- actionable stable errors;
- `doctor` output safe to attach to issues;
- visible current version, schema version, backup age, last restore verification, and upgrade readiness;
- no hidden/default-on telemetry;
- bounded support contract stated in README and issue templates;
- fast, deterministic teardown/rebuild of disposable environments;
- realistic seeds for local, E2E, preview, recovery, and upgrade scenarios.

## Why not make every deployment first-class

Each maintained recipe multiplies documentation, secret handling, upgrade behavior, backup semantics, support, and CI. The correct open-source promise is a portable artifact/data contract plus one excellent reference deployment—not nominal compatibility with every platform.

