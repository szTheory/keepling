# Phase 2: Synchronization and Replaceable Server - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-01
**Phase:** 2-Synchronization and Replaceable Server
**Areas discussed:** Offline queue progression, Logout and account fencing, Released-client compatibility, Backup and replacement objectives

---

## Offline Queue Progression

| Option | Description | Selected |
|--------|-------------|----------|
| Global strict FIFO with stop-on-problem | Preserve one total local order and stop the entire account on the first conflict/rejection. Simple, but unrelated work suffers head-of-line blocking. | |
| Conflict-domain lanes with explicit dependencies and concurrent pull | Preserve FIFO across each task/shared scope, declare cross-entity dependencies, quarantine only affected descendants, and continue pulling and unrelated delivery. | ✓ |
| Maximally concurrent semantic DAG | Let clients bypass earlier work when command-specific commutativity appears safe. Highest concurrency, but duplicates domain rules and expands the cross-runtime failure state. | |

**User's choice:** Asked the agent to research every option through distributed-systems, Elixir/Phoenix/Ecto, product, security, SRE, DX, UX, accessibility, and adversarial lenses, synthesize a one-shot recommendation, then approved the complete recommendation package.

**Notes:** The adversarial pass added a durable terminal mutation journal, sorted multi-scope keys, acknowledgement/feed-order separation, sync-specific bootstrap, restore epoch rotation, and explicit retention/low-water behavior. Relevant lessons included CouchDB checkpoints/deletion propagation, Dropbox cursor reset, and Linear's restore/cursor incident, without adopting hidden conflict winners or CRDT complexity.

---

## Logout and Account Fencing

| Option | Description | Selected |
|--------|-------------|----------|
| Eager wipe after successful synchronization | Minimize retained local data, but make offline logout impossible or force explicit loss of unsynced intent. | |
| Account-scoped quarantine with platform protection | Fence and retain each account/server namespace, preserve exact pending intent for same-account recovery, and make destructive local removal separate. | ✓ |
| Per-account encrypted vault with cryptographic erasure | Add custom database encryption and key deletion now. Stronger potential at-rest protection, but high key-loss, packaging, WAL/temp-file, and recovery risk before client adapter proof. | |

**User's choice:** Approved the researched account-scoped quarantine recommendation as part of the complete package.

**Notes:** Logout, revocation, account switching, local removal, and remote device loss remain distinct. The recommendation uses native authorization code plus PKCE, separate installation grants, platform credential storage, and honest limits: revocation is not remote wipe, and application-database encryption is not claimed without adapter evidence.

---

## Released-Client Compatibility

| Option | Description | Selected |
|--------|-------------|----------|
| Fixed released-client window | Support a fixed number of releases. Bounded and testable, but release cadence can distort the actual user promise. | |
| Time-based window | Promise support for a calendar duration. Clear to users, but may accumulate many variants during rapid development. | |
| Capability and protocol/schema-range negotiation | Negotiate coarse supported protocol intersection separately from app versions. Flexible, but unsafe if allowed to become arbitrary feature flags. | ✓, under bounded policy |
| Indefinite additive compatibility | Preserve old integrations forever. Least immediately disruptive, but creates unbounded solo-maintainer, security, and CI burden. | |

**User's choice:** Approved a hybrid: pre-distribution current-only dogfood, then current plus previous coarse protocol train for at least 90 days after supersession, with server-selected range negotiation and explicit upgrade states.

**Notes:** Compatibility does not negotiate authorization or invariants. Stored receipts, cursor codecs, vectors, and generated clients stay usable for the advertised window. CI covers oldest/current consumers and both old-client/new-server directions. Storage follows expand, migrate, age out, contract.

---

## Backup and Replacement Objectives

| Option | Description | Selected |
|--------|-------------|----------|
| Day-one logical dumps only | Portable and simple, but recovery-point loss is bounded only by dump cadence and operator mistakes lack point-in-time recovery. | |
| Logical backup plus continuous WAL/PITR | Add minute-scale recovery points plus a portable dump. Strong recovery with a bounded earned dependency and more operational policy. | |
| Provider VM backups/snapshots | Convenient whole-host fallback, but not database-aware, independently verified, or a separate failure domain. | supplemental only |
| Tiered recovery contract | Combine continuous WAL/PITR, physical backups, portable logical dumps, off-host independence, executable restore proof, and host replacement. | ✓ |

**User's choice:** Approved the tiered recovery contract with RPO at most five minutes and full-host RTO at most four hours before sustained dogfood.

**Notes:** The recommendation selects pinned pgBackRest plus daily custom-format logical dumps; client-side-encrypted off-host copies; independent daily mirroring; daily/weekly/quarterly verification tiers; stable `keepling ops` vocabulary; separate liveness/readiness/operator status; exact tested OCI promotion; honest short interruption; and mandatory restore epoch rotation before readiness. Provider snapshots are optional forensic convenience only.

---

## Cross-Cutting UX, Accessibility, and Brand

| Option | Description | Selected |
|--------|-------------|----------|
| Expose implementation status directly | Surface cursor, queue, database, and deployment machinery. Precise for engineers but violates the daily user's job and brand. | |
| Shared semantic trust vocabulary with platform-owned presentation | Lock durable state meanings and recovery actions while Mac/iPhone/web own native layouts and interaction. | ✓ |
| One identical cross-platform synchronization UI | Maximizes visual consistency but creates lowest-common-denominator platform behavior and prematurely scopes screens into a no-UI phase. | |

**User's choice:** Approved semantic-state and microcopy contracts without adding Phase 2 screen implementation.

**Notes:** Routine success stays quiet; interruption is reserved for user action. Copy states location, consequence, and recovery without backend jargon. Accessibility requirements include non-color cues, keyboard-complete recovery, stable focus, concise announcements, exact counts/timestamps, WCAG 2.2 AA, Dynamic Type/zoom, and Reduce Motion.

## the agent's Discretion

- Internal PostgreSQL schema/index naming, cursor encoding, page bounds, retry jitter, and dependency-key representation.
- Exact compatibility endpoint/header names and schema-diff tooling.
- Second backup provider, scheduler, Hetzner machine/location, DNS cutover, and optional snapshot cost decision.
- Exact native credential lifetimes/protection classes and client-local persistence/encryption adapters after platform spikes.
- Final platform-specific copy, layout, icons, and motion within the locked trust-state contract.

## Deferred Ideas

- Custom encrypted client vaults, biometric app lock, cryptographic erasure, and remote wipe until Electron/iPhone evidence.
- Permanent task purge and backup-expiry semantics; Trash remains canonical state.
- OIDC/federated identity, collaboration, enterprise device policy, and remote administration.
- Indefinite protocol compatibility or arbitrary capability negotiation.
- High availability, zero-downtime topology, Kubernetes, Redis, multi-node PostgreSQL, and hosted control-plane work.
- Final Mac/iPhone synchronization screens and presentation.
