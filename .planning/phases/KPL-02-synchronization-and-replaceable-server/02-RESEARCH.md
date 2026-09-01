# Phase 2: Synchronization and Replaceable Server - Research

**Researched:** 2026-09-01
**Domain:** Offline synchronization contracts, PostgreSQL change feeds, released-client compatibility, and replaceable single-host operations
**Confidence:** HIGH for in-repo architecture and locked semantics; MEDIUM for current external tooling details

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
## Implementation Decisions

### Offline queue progression and synchronization

- **D-01:** Model delivery as conflict-domain FIFO lanes. Every queued mutation declares a sorted set of resource keys it touches; mutations whose keys overlap preserve FIFO and mutual exclusion, while unrelated lanes continue. Ordinary task commands key by task; shared operations may additionally key Today-order or organization scope. Reject an account-wide stop-on-conflict queue and a maximally concurrent semantic DAG. — **Reversibility:** costly — changing lane and ordering semantics later would migrate durable desktop/iPhone outboxes and invalidate cross-runtime vectors.
- **D-02:** Represent cross-entity prerequisites with explicit durable dependency edges, including capture-before-edit and create-organization-before-assignment. Keep a durable local mutation journal after outbox deletion because descendants may still depend on terminal outcomes. Only declared successful outcomes such as `accepted` and `already_satisfied` satisfy a dependency; rejection or conflict blocks descendants until an explicit replacement or resolution.
- **D-03:** A client reports local success only after one local transaction commits the optimistic projection, immutable serialized command and fingerprint, mutation journal entry, dependency metadata, and outbox row. Immutable identity, payload, base values, and dependencies are never rewritten during retry, bootstrap, or upgrade. — **Reversibility:** one-way — weakening this boundary would contradict Keepling's core accepted-intent guarantee and every future offline client contract.
- **D-04:** Pulling never pauses merely because local mutations are pending or conflicted. Maintain separate canonical-shadow and visible optimistic representations; apply incoming canonical changes monotonically, then deterministically replay pending intents over the shadow. A local replay that is no longer valid becomes `needs_attention`; the client never silently edits the command or mints a replacement identity.
- **D-05:** After reconnect or relaunch, recover only from durable local state, pull at least one bounded sync page, then interleave bounded pulls with ready-lane pushes. Authentication expiry pauses authenticated network work while retaining exact identities and durable state.
- **D-06:** Treat an accepted, rejected, stale, `already_satisfied`, or conflict response as an exact terminal acknowledgement only when it matches the queued mutation identity and semantic fingerprint. In one local transaction, apply the returned canonical snapshot/conflict, journal the terminal result, recompute the optimistic projection, and remove the outbox row. A crash before that commit safely repeats lookup or delivery with the original identity.
- **D-07:** On the server, atomically persist the canonical snapshot/effect or terminal rejection, stable mutation receipt, task activity or persisted conflict, ordered scoped change rows, and any applicable tombstone/undo metadata. Extend the existing transaction/constraint pattern; sockets and background workers may announce post-commit hints but never establish correctness.
- **D-08:** Establish feed order with a transactionally serialized per-account change clock plus an item ordinal, not PostgreSQL sequence allocation, wall-clock time, socket arrival, or response arrival. Single-account serialization is an intentional simplicity/performance tradeoff for Keepling's personal GTD scale. — **Reversibility:** costly — feed ordering becomes a durable cursor and compatibility invariant.
- **D-09:** Keep acknowledgement order distinct from feed coverage. An acknowledgement may update an entity ahead of the saved feed cursor, but it does not advance the global cursor unless the server returns an explicit coverage cursor. Entity revision/generation checks prevent later stale acknowledgements, deltas, or tombstones from regressing state.
- **D-10:** Bind opaque sync cursors to authenticated server instance, account subject, synchronization epoch, protocol/codec version, sequence, and ordinal. Tampered, unsupported, expired, or below-low-water cursors fail with stable explicit recovery; they never produce an empty-success guess. — **Reversibility:** costly — cursor contents remain opaque, but reset and compatibility behavior is a released cross-client contract.
- **D-11:** Full bootstrap captures a high-water sync position, enumerates canonical entities by stable identity through a sync-specific keyset cursor, then consumes changes after the high-water mark. Bootstrap replaces only the canonical shadow and cursor; it preserves and replays every local immutable intent. Phase 1 view cursors are not synchronization/bootstrap cursors.
- **D-12:** Every database restore atomically installs a fresh random synchronization epoch before the application can become ready. Old clients receive an explicit cursor-reset/bootstrap path, preventing restored counters or identifiers from causing skipped history. Readiness and `doctor` verify restore finalization. — **Reversibility:** costly — omitting epoch rotation creates a known silent-data-loss class after restore.
- **D-13:** Trash remains canonical recoverable task state and continues to synchronize as a snapshot. It is not a deletion tombstone. Tombstone envelopes represent removal from a canonical collection, but Phase 2 does not add permanent task purge.
- **D-14:** Advertise feed low-water state and retain change history, tombstones, cursor codecs, and bootstrap/reset support for at least the released-client compatibility window plus documented offline grace. Pruning is allowed only when reset/bootstrap remains safe for every supported client.
- **D-15:** Golden vectors use fixed identities and clocks and cover accepted, duplicate, rejection, semantic fingerprint reuse, stale, conflict and fresh-resolution identity, acknowledgement/feed reordering, response loss before/after commit, pending-local pull, dependency blocking, multi-scope exclusion, reconnect, authentication loss, account switch, crash before local acknowledgement commit, relaunch, cursor tampering/expiry/reset, bootstrap, tombstone propagation, restore epoch rotation, dependency cycles/orphans, and telemetry redaction. Use state-machine/property suites plus targeted adversarial cases rather than a Cartesian platform matrix.

### Logout, revocation, account switching, and local protection

- **D-16:** Namespace credentials, canonical shadow, cursor, conflicts, mutation journal, drafts, and outbox by authenticated issuer/origin, stable server-instance identity, account subject, and synchronization generation. A URL, display label, account UUID, or client assertion alone cannot establish the namespace. Mismatches quarantine rather than replay.
- **D-17:** Explicit logout first stops new writes and durably fences the namespace, then attempts grant-family revocation. Offline or uncertain revocation becomes a truthful `sign_out_pending` state; the UI is locked while the credential remains confined to the privileged credential adapter only for revocation retry.
- **D-18:** Logout, session revocation, account switching, and authentication expiry preserve account-scoped projections and unacknowledged mutations in quarantine. Same-account reauthentication resumes exact lookup/replay. A different account or server opens a separate namespace and can never drain the quarantined outbox.
- **D-19:** Remote revocation stops future server access but never claims to erase unreachable offline data. Permanent authorization loss stops automatic retries, preserves quarantined intent, and offers inspect/export/remove recovery without promising future synchronization.
- **D-20:** "Remove local data from this device" is a separate destructive action. It names unsynced and conflicted counts, defaults to Cancel, and removes credentials, database/WAL/temp files, caches, indexes, and namespace metadata. Keepling claims cryptographic erasure only after a platform adapter proves every durable copy is covered.
- **D-21:** Preserve dirty unsubmitted text through an explicit Save, Discard, or Keep working decision. Already locally accepted mutations are not treated as drafts and cannot be discarded merely to complete logout without explicit destructive consent.
- **D-22:** Preserve the Phase 1 native-client grant seam: external user agent, authorization code, exact redirect binding, unpredictable state, and S256 PKCE. Native apps are public clients and never embed a shared secret, browser cookie, password, or deployment credential. Issue one separately visible/revocable grant per installation with opaque short-lived access credentials and hash-stored rotating refresh-token lineage.
- **D-23:** Phase 2's at-rest baseline is FileVault/iOS Data Protection or equivalent OS protection, least-privilege local-file permissions, and platform credential storage. Be explicit if task/outbox content is plaintext inside the application database. Defer application-database encryption, biometric app lock, and cryptographic erasure to client adapter evidence rather than adding an unproven universal vault.
- **D-24:** Golden account-lifecycle vectors cover empty and pending outboxes across logout, uncertain revocation, late acknowledgement after fencing, access expiry versus definitive grant revocation, refresh replay, same-account reauthentication, account A to B to A switching, duplicate account identifiers across servers, relaunch while quarantined, confirmed local removal, device-loss revocation, and privacy-safe diagnostics.

### Released-client compatibility and protocol evolution

- **D-25:** Before the first downloadable or TestFlight build, declare the protocol unstable and support the current dogfood train only; resets require explicit notice. Beginning with the first distributed build, support the current and immediately preceding protocol train for at least 90 days after supersession. Extend that floor when measured update lag warrants it. — **Reversibility:** one-way — once advertised to distributed clients, the compatibility window cannot be shortened without breaking a published trust promise except for a documented security emergency.
- **D-26:** Define compatibility by coarse integer protocol trains, not Mac/iPhone marketing versions. A client declares a minimum and maximum protocol range; the server selects the highest supported intersection. Do not negotiate authorization, invariants, conflict meaning, or arbitrary feature flags.
- **D-27:** Provide an unversioned compatibility response with server release and tested OCI digest, supported read/write/sync protocol ranges, database schema range, per-platform minimum builds, deprecation deadline, update location, and stable recovery codes. Client claims are input; the server is authoritative.
- **D-28:** A deprecated-but-supported client continues full safe operation with a quiet non-blocking notice. An unsupported client enters stable non-retrying `client_upgrade_required`; a newer client against an older self-hosted server enters `server_upgrade_required`. Both preserve immutable local commands and explain that pending changes remain on the device.
- **D-29:** Keep `/api/v1` and existing closed command `version: 1` semantics stable for compatible additions. A required request field, removed field, changed type, narrowed constraint, new closed-enum response case, or changed semantic meaning requires a new protocol representation or explicit downgrade adapter; generated consumers and vectors, not a schema-diff tool alone, define compatibility.
- **D-30:** Retain command/result codecs, stored-receipt decoders, cursor codecs, frozen vector schemas, and generated DTO fixtures for every supported protocol. Exact results remain replayable in the protocol representation that created them until the support and retained-receipt windows have elapsed.
- **D-31:** Evolve storage through expand, deploy compatible code, dual-read/write or migrate/backfill, validate, switch reads, age out supported clients and rollback images, then contract. No advertised supported client requires a coordinated server upgrade.
- **D-32:** Required CI fans out contract changes across current and oldest-supported generated clients, current/previous protocol simulators, golden mutation/sync/cursor/error vectors, old-client/new-server and new-client/old-server pairs, migration/restore compatibility, and previous-tested-image rollback compatibility. Avoid full combinatorial matrices.
- **D-33:** Deployment preflight rejects a target whose protocol or schema range excludes recently active supported devices unless the operator explicitly acknowledges the documented break. Security fixes may shorten compatibility only through an explicit emergency path with honest client messaging and preserved local intent.

### Backup, restore, deployment, and operator experience

- **D-34:** Before sustained personal dogfood, target recovery-point objective of at most five minutes and full-host recovery-time objective of at most four hours. These objectives define backup cadence and acceptance evidence rather than serving as aspirational telemetry.
- **D-35:** Use a pinned and packaged-tested pgBackRest release for continuous WAL archival and physical backup/PITR, plus a daily PostgreSQL custom-format logical dump as the portable cross-version/architecture escape hatch. This one backup dependency earns its place by replacing fragile custom retention, archive checking, encryption, and restore orchestration.
- **D-36:** Use a one-minute WAL switch/archive boundary; weekly full plus daily differential physical backups; 14 days of physical/WAL recovery; daily logical dumps retained 30 days; and weekly logical generations retained 12 weeks. Surface WAL/archive lag, and block deploy preflight—not serving readiness—when the five-minute RPO is not currently met.
- **D-37:** Store client-side-encrypted recovery material off-host in a versioned/object-locked repository and mirror it daily to an independent provider/account. Keep backup/restore credentials out of the app container, separate least-privilege backup and restore credentials, and retain encryption keys plus root-owned runtime secrets in a separately recoverable encrypted secret manifest.
- **D-38:** Provider VM snapshots are optional short-lived forensic convenience, never recovery authority and never a substitute for PostgreSQL-aware backups and disposable restore verification.
- **D-39:** A backup becomes healthy only after an isolated disposable restore proves manifest/checksum, schema, representative privacy-safe task/history invariants, operator recovery/login, read, safe write, and undo. Verify the newest logical backup and latest recoverable WAL target daily, a randomized historical PITR target weekly, and a fresh OpenTofu VM quarterly. Phase 2 acceptance includes one complete host replacement and DNS rehearsal. — **Reversibility:** costly — weakening verification would invalidate DATA-02 and the project's recovery trust claim.
- **D-40:** Expose one stable operator vocabulary: `keepling ops preflight|status|doctor|backup|restore|restore-verify|deploy|upgrade|replace-host`. Support concise human output, structured JSON, stable exit/error codes, copyable remediation, `--no-color`, and noninteractive CI use.
- **D-41:** Put operational semantics in ordinary inward-facing Elixir application modules/ports. Thin source-time Mix tasks and release/CLI wrappers invoke them; do not bury recovery rules in shell scripts, Phoenix controllers, or Mix-task-only code. Provider-specific OpenTofu, Compose, Caddy, and object-store adapters remain outward infrastructure.
- **D-42:** Public liveness proves only that the process responds. Public readiness proves bounded PostgreSQL reachability, accepted schema/protocol range, finalized migrations, finalized restore epoch, and willingness to accept traffic. Backup lag degrades operator status and blocks deploy preflight but does not take an otherwise-correct server out of readiness.
- **D-43:** Operator-only status reports release revision and tested OCI digest, protocol min/max, schema current/pending, synchronization epoch status, backup age, WAL/archive lag, and last successful restore verification. Diagnostics contain no task titles, notes, prompts, credentials, tokens, raw identifiers, or unbounded high-cardinality labels.
- **D-44:** Deploy the exact tested immutable OCI digest, run explicit expand-compatible migrations, keep Caddy available, recreate the application, wait for readiness, and execute login/read/write/undo smoke. Promise an honest short interruption rather than zero downtime; return stable `503` plus `Retry-After` while offline clients retain and retry exact mutation identities.
- **D-45:** Roll back only to a previous tested image whose declared protocol and database range accepts the migrated schema. Otherwise prefer a forward fix. Treat database restore as a destructive isolated recovery event, never a casual application rollback.
- **D-46:** Restore starts on an isolated empty target, blocks production side effects, verifies before exposure, rotates the synchronization epoch, and changes DNS only after user-level proof. Refuse live/nonempty destinations, ambiguous source/target, missing WAL, unverified selections, mutable image tags, or expired compatibility ranges without an explicit recovery override.
- **D-47:** The reference deployment remains one replaceable Hetzner VM running Caddy, one Phoenix release, and PostgreSQL through a small Compose topology with private PostgreSQL networking and no irreplaceable container/build state. Do not introduce Kubernetes, Redis, a control plane, or provider-specific canonical services.
- **D-48:** Required operations evidence covers local Compose readiness, image digest promotion, graceful shutdown, migration compatibility, unavailable dependency states, privacy-safe doctor bundles, backup age/WAL lag, logical and PITR restore, historical target selection, epoch rotation, post-restore smoke, and full source-driven host replacement.

### User-visible trust states, accessibility, and product language

- **D-49:** Phase 2 locks semantic states and transitions, not platform layouts. Mutation states are `local_saved`, `checking`, `accepted`, `rejected`, `conflict`, `authentication_required`, and `quarantined`; synchronization states are `starting`, `catching_up`, `ready`, `stale_last_good`, and `retryable_failure`; compatibility states are `supported`, `deprecated_but_safe`, and `unsupported`; recovery states are `backup_unverified`, `restore_in_progress`, `restore_verified`, and `restore_failed`. — **Reversibility:** costly — these state meanings feed contracts, vectors, React/Electron, and Swift clients.
- **D-50:** Never infer global "Everything synced" from one successful lane. Copy names durable truth, location, consequence, and next action: saved locally, checking server acceptance, waiting for sign-in, one task needs a choice while others sync, client/server upgrade required, rebuilding canonical data while pending changes remain safe, or restore verified at an exact time.
- **D-51:** Routine success stays quiet. Persistent interruption is reserved for conflicts, authentication fencing, unsupported compatibility, destructive local removal, and failed recovery. Do not nag on routine retries or flood assistive technology with background-sync announcements.
- **D-52:** Require non-color state cues, keyboard-complete recovery, semantic headings and controls, stable focus by object identity, predictable focus restoration, concise nonduplicative live announcements, exact counts/timestamps, WCAG 2.2 AA contrast, Dynamic Type/zoom tolerance, Reduce Motion alternatives, and Cancel-default accessible destructive dialogs.
- **D-53:** Hide mutation identities, revisions, cursors, feed positions, token families, tombstones, protocol negotiation, PostgreSQL, containers, and restore plumbing from ordinary product copy. Offer only sanitized error code, compatibility range, last successful contact, local-versus-server status, backup/restore time, and verification result behind copyable Technical details.
- **D-54:** Preserve the current Keepling voice: plain, compact, specific, non-blaming, and operationally serious. Examples include "Saved on this Mac. Sync when you're back online," "One change needs your choice; other tasks are syncing," and "Backup restored and verified 14 minutes ago." Final platform-specific copy and presentation remain Phase 3/4 work.

### the agent's Discretion
### the agent's Discretion

- Exact PostgreSQL table/index names, change-clock representation, cursor encoding, page sizes, retry jitter/backoff, and bounded retention mechanics consistent with the locked semantics.
- Exact resource/dependency key encoding, bootstrap endpoint shape, compatibility headers and metadata field names, and OpenAPI diff tooling.
- Exact second backup provider, scheduler, Hetzner location/machine size after measurement, DNS cutover mechanism, and whether optional provider snapshots justify their cost.
- Exact native access-token lifetime, refresh retry grace/sender constraint, Apple protection class, Electron SQLite/encryption adapter, and dormant-store retention after the platform phases produce evidence.
- Exact UI placement, iconography, layout, motion, announcement phrasing, and copy refinements within the locked semantic states, accessibility contract, and brand voice.

### Deferred Ideas (OUT OF SCOPE)
## Deferred Ideas

- Application-layer encrypted client vaults, biometric app lock, proven cryptographic erasure, and remote-wipe capability; revisit in the Electron/iPhone adapter phases after packaged and physical-device evidence.
- Permanent task purge and its content/history/tombstone/backup-expiry policy; Trash remains durable canonical state.
- OIDC/federated identity, collaboration account switching, enterprise device policy, and remote administration.
- Arbitrary capability negotiation, indefinite historical API adapters, or third-party public API permanence beyond the bounded released-client contract.
- High availability, gapless/zero-downtime deployment, Kamal, Kubernetes, Redis, multi-node PostgreSQL, or a hosted control plane until measured need justifies the complexity.
- Final Mac/iPhone sync screens, icons, animation, and platform-specific layout; Phase 2 locks semantic states and vectors only.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SRV-04 | User can synchronize through an ordered, account-scoped change feed with opaque durable cursors and tombstones. | Per-account serialized clock, ordinal feed rows, authenticated cursor envelope, bootstrap high-water protocol, and monotonic entity revision rules. |
| SRV-05 | User sees a structured conflict instead of a silent overwrite when concurrent edits cannot be safely merged. | Extend the existing persisted-conflict and fresh-resolution-identity transaction seam into feed and golden-vector coverage. |
| SRV-06 | User can continue using a supported released client after a compatible server deployment without a coordinated forced upgrade. | Protocol trains, unversioned compatibility metadata, frozen codecs/vectors, expand-migrate-age-out-contract migrations, and skew CI. |
| DATA-02 | Operator can create a portable PostgreSQL backup, restore it into a disposable environment, and automatically verify schema, representative task/history consistency, login, read, and safe write/undo behavior. | pgBackRest physical/PITR plus custom-format logical escape backup; isolated restore state machine; application-level verification and epoch rotation. |
| DATA-03 | Operator can determine every durable state location and replace the application host without repairing a snowflake machine. | Durable-state manifest, source-owned Compose/OpenTofu/Caddy configuration, encrypted off-host recovery material, and full host replacement rehearsal. |
| OPS-01 | Operator can run the supported app-plus-PostgreSQL topology locally using pinned containers, explicit health checks, and no hidden durable state. | Digest-pinned Compose topology with public edge, private database network, named durable database storage, and application-defined liveness/readiness. |
| OPS-02 | Operator can provision the reference Hetzner VM, firewall, network, and bootstrap declaratively with OpenTofu/Terraform and minimal manual steps. | Pinned `hetznercloud/hcloud` provider, remote encrypted state with locking, location-based resources, firewall attachment, and bounded cloud-init. |
| OPS-03 | Operator can deploy an immutable tested image, run explicit migrations, wait for readiness, and execute a user-level smoke with honest short-interruption semantics. | Phoenix release migration/eval commands, digest promotion, Caddy-held edge, stable `503`/`Retry-After`, readiness wait, and login/read/write/undo smoke. |
| OPS-04 | Operator can use documented preflight, doctor, backup, restore, restore-verify, upgrade, and disaster-recovery commands with stable actionable errors. | One inward Elixir operations API with thin Mix/release wrappers, JSON mode, closed exit/error codes, and copyable remediation. |
| OPS-05 | Operator can inspect liveness, readiness, version, schema compatibility, backup age, last restore verification, and privacy-safe diagnostics without default-on remote telemetry. | Separate public probes and authenticated operator status, persisted restore-verification record, bounded allow-listed telemetry, and hostile-content redaction tests. |
| QUAL-02 | Contributor receives fast required CI lanes with parallelism, dependency caching, slow-test visibility, flake accountability, and cross-consumer fan-out for contract/token changes. | Required server/contract/sync/image/restore/tofu lanes, affected-input fan-out, deterministic seeds, timing artifacts, and exact-digest evidence. |
| QUAL-05 | Diagnostic logs and traces are structured, bounded, correlated, and tested not to emit task titles, notes, prompts, tokens, or arbitrary high-cardinality identifiers. | Extend the existing telemetry allow-list and hostile sentinels to sync, grants, operations, backup, restore, and diagnostic bundles. |
</phase_requirements>

The descriptions above are copied verbatim from `.planning/REQUIREMENTS.md`. [VERIFIED: .planning/REQUIREMENTS.md:23-25,58-75]

## Summary

Plan Phase 2 as two coordinated vertical systems joined by a single durable contract: (1) a server-side synchronization transaction and cross-runtime reference model, and (2) a source-reproducible operations/recovery system that proves the exact tested server can survive host loss. Do not split work into a generic “sync layer” and a later “deployment layer”: restore epoch rotation, compatibility metadata, readiness, backup health, and client bootstrap are one correctness boundary. [VERIFIED: .planning/phases/KPL-02-synchronization-and-replaceable-server/02-CONTEXT.md:18-91]

The existing PostgreSQL adapter already executes semantic commands inside `Repo.transact/1`; its module contract says, verbatim, “Accepted task, activity, and terminal acknowledgement commit together.” Extend this same first-delivery transaction to reserve the per-account feed position and insert all change envelopes. Do not introduce a second asynchronous outbox, a socket-owned cursor, or an independently committed feed writer. [VERIFIED: apps/server/lib/keepling/adapters/postgres/command_store.ex:1-31] PostgreSQL row locks block competing writers/lockers on the same row until transaction end, and PostgreSQL detects deadlocks by aborting a participant, so every transaction must acquire shared scopes in one canonical sorted order. [CITED: https://www.postgresql.org/docs/18/explicit-locking.html]

For operations, use the exact locked stack: Phoenix release + PostgreSQL 18.6 + Caddy + Compose on one replaceable Hetzner VM, provisioned with OpenTofu and protected by pgBackRest 2.59.1 plus logical dumps. The important unit of evidence is not “backup command exited zero” but “an isolated restore reached a fresh epoch, became ready, and passed user-level login/read/write/undo proof.” pgBackRest's `check` and `verify` cover repository/archive integrity, while Keepling must own the application-level restore proof. [CITED: https://pgbackrest.org/user-guide.html] [VERIFIED: tooling/runtime-versions.env:1-4]

**Primary recommendation:** Build the phase in dependency order: frozen sync/reference-model vectors → atomic PostgreSQL feed/cursor/bootstrap → compatibility and account lifecycle → inward operations API/probes → release image/Compose → backup and disposable restore → Hetzner replacement rehearsal → required CI/privacy evidence.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Local lane/dependency/replay reference model | Client contract package | API / Backend | Phase 2 defines storage-neutral semantics; later Electron/Swift adapters implement durable stores independently. |
| Command acceptance, receipt, conflict, feed append | API / Backend | Database / Storage | Application commands own meaning; one PostgreSQL transaction owns atomic persistence and ordering. |
| Feed cursor and bootstrap enumeration | API / Backend | Database / Storage | The server authenticates scope/epoch/protocol; PostgreSQL provides stable high-water and keyset reads. |
| Client compatibility negotiation | API / Backend | Client | Server metadata is authoritative; clients preserve local intent and map stable recovery states. |
| Liveness/readiness/status | API / Backend | CDN / Static edge | Phoenix determines semantic readiness; Caddy exposes only the intended public surface. |
| OCI release and short-interruption deploy | Infrastructure | API / Backend | Infrastructure promotes a tested digest; application supplies migrations, readiness, and smoke operations. |
| PostgreSQL backup/PITR/logical escape | Database / Storage | Infrastructure | PostgreSQL/pgBackRest own physical consistency; infrastructure schedules, encrypts, stores, and restores. |
| Restore verification and epoch rotation | API / Backend | Database / Storage | Application semantics determine representative consistency and epoch finalization inside restored canonical data. |
| Hetzner host replacement | Infrastructure | CDN / Static edge | OpenTofu creates the host/firewall/network; Caddy/DNS expose only after proof. |
| Diagnostics and privacy tests | API / Backend | Infrastructure | Producers must emit bounded allow-listed facts; bundles aggregate without raw domain content. |

This allocation follows the repository rule “Server domain → nothing outward,” while adapters and infrastructure depend inward on application/domain contracts. [VERIFIED: docs/architecture/REPOSITORY.md:36-44]

## Project Constraints (from AGENTS.md)

- Preserve the modular-monolith inward dependency direction; server domain/application rules must not depend on Phoenix transport, MCP, generated clients, UI, client persistence, Compose, OpenTofu, or provider APIs. [VERIFIED: AGENTS.md:9-10,84-86]
- PostgreSQL remains the sole canonical data service; do not introduce Redis, Elasticsearch, Kubernetes, a control plane, or provider-specific canonical storage. [VERIFIED: AGENTS.md:10-16,100]
- UI/API/MCP must invoke the same semantic application commands; no adapter may bypass invariants with raw patches or direct database access. [VERIFIED: AGENTS.md:85-86]
- Ecto schemas, wire DTOs, desktop SQLite rows, and Swift persistence objects remain separate representations; share OpenAPI, JSON Schemas, and storage-neutral vectors rather than persistence types. [VERIFIED: AGENTS.md:87-88]
- A future offline client reports success only after its projection and durable outbox commit atomically; retries preserve exact identity until exact acknowledgement. [VERIFIED: AGENTS.md:13,88]
- Never expose PostgreSQL publicly or place irreplaceable state in application containers/build directories. [VERIFIED: AGENTS.md:18,89]
- Diagnostics must exclude raw titles, notes, prompts, credentials, tokens, and arbitrary identifiers; self-hosters receive no default-on remote telemetry. [VERIFIED: AGENTS.md:20,90]
- Completion, safety, restore health, compatibility, and release readiness require fresh executable evidence at the relevant boundary. [VERIFIED: AGENTS.md:22,91]
- Use native tools first: Mix, pnpm workspaces, OpenTofu, and Compose; no Nx, Turborepo, umbrella, or universal build graph without measured need. [VERIFIED: docs/architecture/REPOSITORY.md:67-69]
- Infrastructure belongs under root `infra/`; contracts and golden vectors belong under `packages/contracts/`; no nested Git or nested `.planning/`. [VERIFIED: AGENTS.md:76-83] [VERIFIED: docs/architecture/REPOSITORY.md:7-27]
- This research found no project-local skills under `.codex/skills/` or `.agents/skills/`; no additional project skill convention applies. [VERIFIED: AGENTS.md:67-69]

## Standard Stack

### Core

| Library / Tool | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| Elixir / OTP | `1.20.2` / `29.0.5` | Domain, sync application ports, operator commands, release runtime | Repository-pinned current runtime; keeps operational semantics inside the existing modular monolith. [VERIFIED: tooling/runtime-versions.env:1-3] |
| Phoenix / Ecto SQL / Postgrex | `1.8.13` / `3.14.0` / `0.22.4` | HTTP adapters, transaction orchestration, PostgreSQL driver | Existing locked application stack; Phoenix release commands support migrations without Mix. [VERIFIED: apps/server/mix.exs:42-54] [VERIFIED: apps/server/mix.lock:10,23,29] [CITED: https://phoenix.hexdocs.pm/releases.html] |
| PostgreSQL | `18.6` | Canonical snapshots, receipts, feed clock/rows, conflicts, epochs, restore-verification state | Repository-pinned sole canonical store; row locking and continuous archive/PITR are first-party capabilities. [VERIFIED: tooling/runtime-versions.env:4] [CITED: https://www.postgresql.org/docs/18/backup.html] |
| pgBackRest | `2.59.1` | Physical full/differential backup, async WAL archive, retention, repository encryption, PITR | Locked backup dependency; current stable on 2026-09-01 and official docs require exact local/remote version match. [CITED: https://pgbackrest.org/] [CITED: https://pgbackrest.org/user-guide.html] |
| OpenTofu | `1.12.6` target | Declarative Hetzner host/network/firewall provisioning and state | Current stable release on 2026-09-01; provider locking/checksums and remote-state handling are documented first-party. [CITED: https://github.com/opentofu/opentofu/releases] [CITED: https://opentofu.org/docs/language/state/backends/] |
| `hetznercloud/hcloud` provider | `1.68.0` | Hetzner server, location, firewall, network, SSH key, cloud-init | Current signed official provider release; use `location`, not removed `datacenter`. [CITED: https://github.com/hetznercloud/terraform-provider-hcloud/releases] |
| Docker Engine / Compose | Engine `29.5.2`; Compose `5.1.3` development baseline | Local/reference topology, health dependencies, networks, graceful stop | Present locally and official Compose semantics cover health checks, internal networks, and stop grace. [VERIFIED: environment probe 2026-09-01] [CITED: https://docs.docker.com/reference/compose-file/services/] |
| Caddy | `2.11.4` target | TLS edge and reverse proxy kept available across short app interruptions | Current official release on 2026-09-01; native reverse-proxy health checks and automatic HTTPS avoid bespoke edge code. [CITED: https://github.com/caddyserver/caddy/releases] [CITED: https://caddyserver.com/docs/caddyfile/directives/reverse_proxy] |

### Supporting

| Library / Tool | Version | Purpose | When to Use |
|----------------|---------|---------|-------------|
| StreamData | `1.4.0` test-only | Generators, shrinking, reproducible state-machine/property checks | Use for long lane/dependency/reordering/cursor sequences; keep targeted adversarial fixtures alongside it. [VERIFIED: Hex registry via `mix hex.info stream_data`, 2026-09-01] [CITED: https://stream-data.hexdocs.pm/ExUnitProperties.html] |
| `pg_dump` / `pg_restore` | PostgreSQL `18.6` runtime tools | Daily custom-format portable logical escape backup | Use in addition to, never instead of, pgBackRest PITR. Custom archives are portable across architectures and selectively restorable. [CITED: https://www.postgresql.org/docs/18/app-pgdump.html] |
| Checked-in OpenAPI + JSON vectors | repository-owned | Wire compatibility, generated consumers, cross-runtime truth | Extend existing contract drift tooling and vector readers; never import Ecto shapes into clients. [VERIFIED: docs/architecture/REPOSITORY.md:45-49] |
| GitHub Actions | pinned actions by commit before merge | Required parallel CI, caches, exact-digest evidence, scheduled recovery drills | Extend the existing required repository-integrity workflow into independent fast and slow lanes. [VERIFIED: .github/workflows/repository-integrity.yml:1-18] |

### Alternatives Considered

Locked decisions remove most alternatives from scope. Do not plan Redis streams, logical decoding, CRDTs, Kafka, Kubernetes, Kamal, or managed PostgreSQL. The strongest case for each is higher concurrency/availability or simpler provider operations, but none is required for one person's GTD scale and each adds a second correctness/operations surface contrary to the phase boundary. [VERIFIED: .planning/REQUIREMENTS.md:98-110] [VERIFIED: .planning/phases/KPL-02-synchronization-and-replaceable-server/02-CONTEXT.md:18-74,181-186]

**Installation / pinning:**

```bash
# Test-only Hex dependency; verify and commit mix.lock.
mix deps.get

# Infrastructure providers; commit .terraform.lock.hcl with target-platform checksums.
tofu init
tofu providers lock -platform=darwin_arm64 -platform=linux_amd64

# OCI services are referenced by immutable manifest digest in Compose/deploy inputs.
docker compose pull
```

OpenTofu documents that the provider lock command records official checksums for selected platforms; it does not establish provider trust by itself, so provenance review remains required. [CITED: https://opentofu.org/docs/cli/commands/providers/lock/]

## Package Legitimacy Audit

The GSD legitimacy seam accepts only npm, PyPI, and crates ecosystems; this phase introduces no package from those ecosystems. A probe against Hex returned the seam's explicit supported-ecosystem error, so no false `OK` verdict is claimed. [VERIFIED: local `package-legitimacy check --ecosystem hex stream_data` probe, 2026-09-01]

| Dependency | Registry / Authority | Publish evidence | Source Repo | Verdict | Disposition |
|------------|----------------------|------------------|-------------|---------|-------------|
| `stream_data` | Hex + official HexDocs | `1.4.0`, 2026-07-14; 37M+ all-time downloads at probe | `github.com/whatyouhide/stream_data` | Gate unsupported; official registry/docs verified | Approved test-only; pin lockfile |
| pgBackRest | pgbackrest.org / PGDG packages | `2.59.1`, 2026-08-17 | `github.com/pgbackrest/pgbackrest` | Official project verified | Approved; pin exact release/package |
| `hetznercloud/hcloud` | OpenTofu registry + official GitHub | `1.68.0`, 2026-07-28 | `github.com/hetznercloud/terraform-provider-hcloud` | Signed official release verified | Approved; pin constraint + lock checksums |
| Caddy | Official GitHub / OCI source | `2.11.4`, 2026-06-03 | `github.com/caddyserver/caddy` | Official release verified | Approved; pin OCI digest |
| PostgreSQL OCI image | Docker Official Image | tag `18.6` present 2026-09-01 | `github.com/docker-library/postgres` | Official image verified | Approved; pin multi-arch manifest digest |

**Packages removed due to SLOP verdict:** none.  
**Packages flagged as suspicious:** none.  
**Planner checkpoint:** record exact OCI manifest digests, base OS variants, package repository keys, and target architectures only after the packaged image/restore matrix passes; a version tag alone is not immutable evidence.

## Architecture Patterns

### System Architecture Diagram

```text
Later offline client reference model
  durable namespace + journal + shadow + outbox
         | bounded pull                       | ready-lane push / exact lookup
         v                                    v
  GET sync page/bootstrap              POST semantic command
         |                                    |
         +----------------> Phoenix adapters -+
                               |
                    inward application ports
                               |
          +--------------------+----------------------+
          | command decision + account/scope locks    |
          | receipt + snapshot/conflict/activity      |
          | reserve (account sequence, item ordinal)  |
          | append change/tombstone envelopes         |
          +--------------------+----------------------+
                               | one PostgreSQL transaction
                               v
                        PostgreSQL 18.6
                               |
           +-------------------+---------------------+
           | pgBackRest full/diff + async WAL        |
           | custom-format logical dump              |
           +-------------------+---------------------+
                               | encrypted off-host repositories
                               v
                   isolated disposable restore
                               |
                rotate sync epoch before readiness
                               |
        manifest/schema/invariants/login/read/write/undo proof
                               |
                   verified candidate host
                               |
                   DNS cutover after evidence

Internet -> Hetzner firewall (80/443) -> Caddy -> Phoenix
                                              -> private Compose DB network -> PostgreSQL
OpenTofu -> host + firewall + network + cloud-init; never canonical product state
```

### Recommended Project Structure

```text
apps/server/
├── lib/keepling/application/sync/       # pure contracts and ports; planned new boundary
├── lib/keepling/application/ops/        # status/preflight/restore verification semantics
├── lib/keepling/adapters/postgres/      # feed, cursor state, epochs, ops persistence
├── lib/keepling_web/controllers/        # thin sync/compatibility/probe adapters
├── lib/keepling/release.ex              # migration/release-safe command entry
└── test/keepling/{application,adapters,web}/
packages/contracts/
├── openapi/keepling.yaml
├── schemas/                              # storage-neutral sync/vector schemas
└── vectors/{sync,account-lifecycle,compatibility,recovery,redaction}/
infra/
├── images/server/                        # release Dockerfile and image metadata
├── compose/                              # portable local/reference topology
├── caddy/                                # edge configuration
├── backup/                               # pgBackRest/logical schedules and config templates
└── tofu/hetzner/                         # provider-specific replaceable-host recipe
tooling/
├── keepling-ops                          # thin stable wrapper
├── test-phase-2.sh                       # consolidated local lane runner
└── verify-{contracts,image,restore,privacy}.*
```

These are recommended new paths, not claims that the files already exist. They preserve the repository's declared ownership: Phase 2 creates `infra` implementation and sync vectors; infrastructure depends on portable image/health/migration/backup contracts. [VERIFIED: docs/architecture/REPOSITORY.md:24-27,36-44]

### Pattern 1: One Atomic Acceptance + Feed Transaction

**What:** Under one `Repo.transact/1`, arbitrate the account-scoped receipt, lock the account clock and any sorted shared scopes, decide/apply the command, persist terminal result/conflict/activity/undo metadata, reserve one sequence and deterministic ordinals, append every affected envelope, then commit. Only after commit may a socket or notifier publish a hint. [VERIFIED: apps/server/lib/keepling/adapters/postgres/command_store.ex:19-31,1655-1772] [CITED: https://www.postgresql.org/docs/18/explicit-locking.html]

**Planner consequence:** Change-feed writes must be added at the same helper level as snapshot/activity/receipt finalization, not in the controller or an `after_commit` task. A transaction that produces multiple envelopes shares one sequence and assigns ordinal by a documented stable sort. Lock resource keys in bytewise sorted order and add a real two-backend deadlock/convergence test using the existing barrier helper. The helper states verbatim: “Call it from separate tasks and synchronize those tasks with a barrier so a concurrency test cannot accidentally become sequential.” [VERIFIED: apps/server/test/support/concurrency_case.ex:1-49]

### Pattern 2: Authenticated Cursor Envelope + Explicit Reset

**What:** Encode the locked fields—server instance, account subject, sync epoch, protocol/codec train, sequence, ordinal—inside an authenticated opaque token. Decode into a closed result: valid position, unsupported codec/protocol, wrong namespace, tampered, expired, or below low-water. Never convert a decode/reset condition into an empty page. [VERIFIED: .planning/phases/KPL-02-synchronization-and-replaceable-server/02-CONTEXT.md:25-31]

**Planner consequence:** Keep cursor signing/verification as an application service with injected keyring/time; Phoenix only maps stable results. Maintain decoder fixtures for every supported train. Treat the cursor as authority over feed position only, not over authorization: authenticated account/server namespace must independently match.

### Pattern 3: High-Water Bootstrap Without Losing Local Intent

**What:** In one bounded server read transaction, capture the account's current high-water feed position, then keyset-page canonical entities by stable identity as of the bootstrap contract; after enumeration, consume feed entries strictly after the captured position. Client reference reducers replace only canonical shadow/cursor, then replay immutable pending intents. [VERIFIED: .planning/phases/KPL-02-synchronization-and-replaceable-server/02-CONTEXT.md:28-29]

**Planner consequence:** Bootstrap has its own cursor/schema and must not reuse Phase 1 view cursors. Vectors must force changes during bootstrap to prove neither gaps nor double application. The reference model should make canonical shadow, visible optimistic state, journal, dependencies, and outbox separate typed values.

### Pattern 4: Protocol Train + Expand/Migrate/Age-Out/Contract

**What:** Server publishes unversioned authoritative compatibility metadata, selects the highest overlapping integer protocol train, retains codecs/results/cursors for supported trains, and rejects non-overlap with stable non-retrying recovery. Storage evolves through additive schema, compatible code, backfill/validation, read switch, compatibility aging, then contraction. [VERIFIED: .planning/phases/KPL-02-synchronization-and-replaceable-server/02-CONTEXT.md:48-56]

**Planner consequence:** Separate contract schemas/fixtures by protocol train; do not mutate a frozen vector in place. Every migration plan needs old-image/new-schema and new-image/old-schema probes plus a declared rollback range. Compatibility metadata and image labels must bind the exact OCI digest tested.

### Pattern 5: Restore as an Isolated State Machine

**What:** Restore operates only on a newly created empty target with production side effects disabled. It selects an explicit source/target, restores, verifies repository/manifests, runs migrations only if compatible, rotates the sync epoch transactionally, starts the candidate, then performs semantic smoke. DNS changes only after proof. [VERIFIED: .planning/phases/KPL-02-synchronization-and-replaceable-server/02-CONTEXT.md:60-74]

**Planner consequence:** Persist a closed restore-verification record containing source backup identity digest, target recovery point, verifier version, started/finished instants, schema/protocol/digest result, and success/failure code—never representative task content. Readiness checks epoch finalization, not merely PostgreSQL connectivity.

### Pattern 6: Inward Operations API, Thin Runtime Wrappers

**What:** Ordinary Elixir application modules own preflight, status, doctor, backup selection, restore safety checks, verification, deploy compatibility, and stable result codes. Mix tasks and release `eval` wrappers only parse/format/exit. Phoenix documents the same approach for release migrations and custom commands without Mix. [CITED: https://phoenix.hexdocs.pm/releases.html]

**Planner consequence:** Give every operation one structured result used by human text and JSON renderers. Avoid parsing human output in CI. Separate read-only inspection from destructive execution; restore and host replacement require explicit validated target identity and refuse live/nonempty destinations by default.

### Anti-Patterns to Avoid

- **Async feed append after commit:** can acknowledge a mutation that no client can subsequently pull. Append inside the canonical transaction.
- **Sequence/default nextval as feed order:** allocation order is not commit order and locked D-08 explicitly forbids it. Use the per-account locked clock.
- **Advancing cursor from an acknowledgement:** acknowledgement freshness and global feed coverage are distinct. Advance only with explicit coverage or pulled page position.
- **Deleting receipts/change history on a short timer:** breaks exact replay and supported-client reset. Retention must be bounded by support window + offline grace + safe bootstrap.
- **Treating Trash as a tombstone:** Trash remains a synchronized canonical snapshot; tombstones remove an item from a collection.
- **Using Docker health as application readiness:** container start/process response does not prove schema/protocol/restore epoch acceptance.
- **Putting backup credentials in the app container:** backup and restore credentials are separate least-privilege host/scheduler secrets.
- **Using provider snapshots as recovery authority:** they do not replace PostgreSQL-consistent backup and verified restore.
- **Restoring over production:** restore is isolated and destructive; cut over only after proof.
- **Embedding operational rules in shell:** shell is a thin transport wrapper; safety decisions live in tested Elixir modules/ports.
- **Logging IDs for correlation:** use bounded per-operation correlation classes or ephemeral opaque run handles that are not raw arbitrary identifiers; test the complete serialized bundle.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Physical backup, WAL archive, PITR, retention | Custom `archive_command` upload scripts and homegrown retention | pgBackRest `2.59.1` | Official tooling already covers async archive, full/differential backup, encryption, checks, verification, retention, and PITR selection. [CITED: https://pgbackrest.org/user-guide.html] |
| Portable logical backup | Ad hoc CSV/table dumps | PostgreSQL `pg_dump -Fc` + `pg_restore` | Custom format is architecture-portable, compressed, inspectable, and selectively restorable. [CITED: https://www.postgresql.org/docs/18/app-pgdump.html] |
| TLS certificate lifecycle | Bespoke ACME client/cert cron | Caddy automatic HTTPS | Keeps edge ownership small and inspectable. [CITED: https://caddyserver.com/docs/automatic-https] |
| Provider API automation | Curl scripts against Hetzner APIs | OpenTofu + official `hetznercloud/hcloud` provider | Declarative plan/state enables replacement and review; official provider owns API evolution. [CITED: https://github.com/hetznercloud/terraform-provider-hcloud] |
| Property generator and shrinking | Random loops with irreproducible failures | StreamData + fixed adversarial vectors | StreamData integrates with ExUnit seed reproduction and shrinking; vectors preserve exact cross-runtime cases. [CITED: https://stream-data.hexdocs.pm/ExUnitProperties.html] |
| Transaction coordinator | OTP process or queue coordinating database writes | PostgreSQL transaction + row constraints/locks through `Repo.transact/1` | Database commit is the only boundary shared by snapshot, receipt, conflict, activity, and feed state. [VERIFIED: apps/server/lib/keepling/adapters/postgres/command_store.ex:19-31] |
| Feed ordering | Timestamp, sequence, UUID order, or socket arrival | Locked per-account clock row + ordinal | This is the locked durable-cursor invariant; alternatives can expose gaps/reordering. [VERIFIED: .planning/phases/KPL-02-synchronization-and-replaceable-server/02-CONTEXT.md:24-31] |
| Protocol negotiation | Arbitrary feature flags | Coarse integer train intersection and frozen codecs | Keeps compatibility auditable and avoids negotiating domain invariants. [VERIFIED: .planning/phases/KPL-02-synchronization-and-replaceable-server/02-CONTEXT.md:48-56] |
| Backup-health claim | Parsing successful backup output | Disposable restore plus Keepling semantic verifier | Repository validity does not prove application login/read/write/undo or restored epoch correctness. [VERIFIED: .planning/phases/KPL-02-synchronization-and-replaceable-server/02-CONTEXT.md:65-74] |
| Remote telemetry control plane | Hosted dashboard dependency | Structured local Logger/Telemetry + operator status/doctor bundle | Self-hosting requires no default-on remote telemetry and bounded private diagnostics. [VERIFIED: AGENTS.md:20,90] |

**Key insight:** The deceptively hard parts—commit ordering, WAL continuity, PITR selection, certificate renewal, state locking, and shrinking failing randomized sequences—already have authoritative platform solutions. Keepling's owned code should encode its unique semantic contract and executable proof, not reimplement infrastructure primitives.

## Common Pitfalls

### Pitfall 1: Feed Order Does Not Match Commit Visibility

**What goes wrong:** A client observes cursor position N+1 but the transaction assigned N commits later, or a sequence value is lost on rollback.  
**Why it happens:** PostgreSQL sequence allocation and wall clocks are not commit-order serializers.  
**How to avoid:** Lock one account-clock row first, increment it inside the acceptance transaction, assign deterministic ordinals to all envelopes, and commit feed rows with the receipt/effect. [CITED: https://www.postgresql.org/docs/18/explicit-locking.html]  
**Warning signs:** gaps that later fill, cursor-dependent flakes, or queries ordered only by `inserted_at`/global `id`.

### Pitfall 2: Lock Inversion Across Shared Scopes

**What goes wrong:** task, Today-order, and organization commands deadlock under real concurrent database connections.  
**Why it happens:** transactions acquire overlapping resource rows in different orders. PostgreSQL resolves a deadlock by aborting one transaction; which participant loses is not stable. [CITED: https://www.postgresql.org/docs/18/explicit-locking.html]  
**How to avoid:** derive a sorted, canonical resource-key set before entering persistence and acquire account clock + resource locks in one documented order. Retry only infrastructure aborts with the exact original mutation identity.  
**Warning signs:** tests use one sandbox connection, `deadlock_detected`, or different command types have independent lock helpers.

### Pitfall 3: Acknowledgement Incorrectly Advances Feed Coverage

**What goes wrong:** an acknowledgement snapshot is newer than the saved cursor, then a later pulled older envelope regresses it or entries are skipped.  
**How to avoid:** keep entity revision/generation monotonic, store feed cursor separately, and advance coverage only from pulled pages or an explicit coverage cursor. [VERIFIED: .planning/phases/KPL-02-synchronization-and-replaceable-server/02-CONTEXT.md:23-28]  
**Warning signs:** one `last_synced_at` field, cursor updates in command-response handlers, or snapshot replacement without revision checks.

### Pitfall 4: Bootstrap Races Create Gaps

**What goes wrong:** changes during multi-page enumeration are absent from both snapshot and subsequent feed.  
**How to avoid:** capture high-water first, enumerate stable identities with a bootstrap-specific keyset contract, then consume strictly after high-water; include a forced mid-bootstrap mutation vector. [VERIFIED: .planning/phases/KPL-02-synchronization-and-replaceable-server/02-CONTEXT.md:27-30]  
**Warning signs:** enumeration begins before high-water capture, offset pagination, or reuse of stale view cursors.

### Pitfall 5: Restore Reuses the Old Epoch

**What goes wrong:** a client with a cursor beyond the restored database's history receives empty success and silently misses restored changes.  
**How to avoid:** install a new random epoch in the restored database before readiness and return explicit reset/bootstrap for old cursors. [VERIFIED: .planning/phases/KPL-02-synchronization-and-replaceable-server/02-CONTEXT.md:29]  
**Warning signs:** readiness only checks SQL connectivity/migration version or epoch generation occurs after serving begins.

### Pitfall 6: Backup Success Is Confused With Recovery Health

**What goes wrong:** archives exist but keys, manifests, WAL, schema, or application behavior fail during an emergency.  
**How to avoid:** run daily newest logical/latest-WAL restore, weekly randomized historical PITR, and quarterly fresh-host replacement; persist exact proof and alert on age. pgBackRest `check` validates archive configuration and forces WAL archival, but Keepling still must exercise login/read/write/undo. [CITED: https://pgbackrest.org/user-guide.html]  
**Warning signs:** dashboards report only backup age/size, no last restore target/digest, or restore requires undocumented manual repair.

### Pitfall 7: WAL Archive Failure Fills the Database Disk

**What goes wrong:** PostgreSQL retains unarchived WAL until archival recovers, exhausting disk.  
**Why it happens:** PostgreSQL will not recycle segments that have not archived successfully. [CITED: https://www.postgresql.org/docs/18/wal-configuration.html]  
**How to avoid:** monitor oldest unarchived WAL/queue depth/archive lag and free space; make deploy preflight fail outside the RPO without failing serving readiness.  
**Warning signs:** growing `pg_wal`, failing `archive_command`, or status reports only last completed backup.

### Pitfall 8: Release Commands Accidentally Start Production Side Effects

**What goes wrong:** restore verification or migrations boot the full endpoint/schedulers against an isolated target.  
**How to avoid:** use release `eval` with `Application.ensure_loaded/1` for pure commands or a minimal application mode for database-dependent operations. Phoenix explicitly documents this distinction. [CITED: https://phoenix.hexdocs.pm/releases.html]  
**Warning signs:** Mix required in production, every ops command starts Endpoint, or background jobs can send notifications during restore.

### Pitfall 9: Mutable Tags Break Tested-Artifact Evidence

**What goes wrong:** deployment pulls different bytes under the same tag after CI.  
**How to avoid:** promote the tested OCI manifest digest, expose it in compatibility/status, retain prior tested digests, and reject mutable deploy inputs. [VERIFIED: .planning/phases/KPL-02-synchronization-and-replaceable-server/02-CONTEXT.md:69-74]  
**Warning signs:** `latest`, tag-only Compose files, or production rebuild jobs.

### Pitfall 10: Diagnostics Leak Through Secondary Surfaces

**What goes wrong:** titles/tokens/IDs are absent from primary logs but appear in exception inspection, HTTP query strings, pgBackRest logs, OpenTofu plans, diagnostic bundles, or metric labels.  
**How to avoid:** allow-list every production event and bundle field; use hostile sentinel values across success and failure paths; scan serialized logs, metrics, traces, JSON output, CLI stderr, and bundles. The existing test already requires telemetry metadata keys to be exactly `[:flow, :outcome]` and rejects hostile password/token/title/identifier sentinels. [VERIFIED: apps/server/test/keepling/telemetry_redaction_test.exs:44-158]  
**Warning signs:** generic `inspect(params)`, raw URL logging, dynamic metric tags, or arbitrary provider error bodies copied into user diagnostics.

## Code Examples

These examples show implementation shape. New module/table/field names are recommendations under the agent's discretion, not existing in-repo values.

### Atomic Acceptance Skeleton

```elixir
# Source pattern: existing CommandStore Repo.transact/1 plus PostgreSQL row locking.
Repo.transact(fn repo ->
  receipt = reserve_or_replay_receipt(repo, command, fingerprint)

  case receipt do
    {:replay, stored_result} ->
      {:ok, stored_result}

    :first_delivery ->
      scopes = command |> resource_keys() |> Enum.sort()
      lock_account_clock(repo, account_id)
      lock_resource_scopes(repo, account_id, scopes)

      result = decide_and_persist_effect(repo, command, context)
      position = reserve_change_position(repo, account_id)
      append_sorted_envelopes(repo, position, result)
      finalize_receipt(repo, command, result)
      {:ok, attach_coverage_position(result, position)}
  end
end)
```

The repository's current fixed transaction pattern uses `Repo.transact(fn repo -> ... end)` and returns infrastructure failure outside the transaction. [VERIFIED: apps/server/lib/keepling/adapters/postgres/command_store.ex:19-31] The recommended helper names above do not yet exist.

### Release-Safe Operational Command

```elixir
# Source: Phoenix release guide pattern, adapted to Keepling's inward operations API.
defmodule Keepling.Release do
  @app :keepling

  def migrate do
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, :up, all: true)
        end)
    end
  end
end
```

Phoenix generates the same `Ecto.Migrator.with_repo/2` release pattern because production releases do not include Mix. [CITED: https://phoenix.hexdocs.pm/releases.html]

### Property Test With Reproducible Seed

```elixir
# Source: StreamData ExUnitProperties documentation.
use ExUnitProperties

property "reference reducer never loses an immutable accepted-local intent" do
  check all steps <- list_of(sync_step_generator(), max_length: 80) do
    final = Enum.reduce(steps, reference_initial_state(), &reference_step/2)
    assert every_local_success_is_journaled_or_terminal?(final)
    assert cursor_is_monotonic?(final)
  end
end
```

StreamData takes its default seed from ExUnit, so a failing CI sequence can be replayed with ExUnit's seed; it also shrinks failing generated values. [CITED: https://stream-data.hexdocs.pm/ExUnitProperties.html]

### Compose Readiness Dependency Shape

```yaml
# Source pattern: Docker Compose service health/dependency documentation.
services:
  db:
    image: postgres@sha256:<tested-manifest>
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U keepling"]
    networks: [database]

  app:
    image: keepling-server@sha256:<tested-manifest>
    depends_on:
      db:
        condition: service_healthy
    stop_grace_period: 30s
    networks: [edge, database]

  caddy:
    image: caddy@sha256:<tested-manifest>
    networks: [edge]

networks:
  edge: {}
  database:
    internal: true
```

Compose documents `healthcheck`, `condition: service_healthy`, `stop_grace_period`, and isolated explicit networks. [CITED: https://docs.docker.com/reference/compose-file/services/] [CITED: https://docs.docker.com/reference/compose-file/networks/]

## State of the Art

| Old / Insufficient Approach | Current Approach for Phase 2 | Evidence / Impact |
|-----------------------------|------------------------------|-------------------|
| Eager online-only command response | Durable receipt plus ordered pull feed and exact lookup | Existing receipt replay remains; feed becomes the canonical cross-device discovery path. [VERIFIED: apps/server/lib/keepling/adapters/postgres/command_store.ex:1729-1772] |
| One global serial queue | Overlap-aware FIFO resource lanes | Conflicts isolate dependent scopes while unrelated tasks continue. [VERIFIED: .planning/phases/KPL-02-synchronization-and-replaceable-server/02-CONTEXT.md:18-23] |
| Last-write-wins / timestamp order | Server revisions, persisted conflicts, per-account feed clock | Prevents silent overwrite and clock-skew dependence. [VERIFIED: .planning/phases/KPL-02-synchronization-and-replaceable-server/02-CONTEXT.md:23-32] |
| “Backup completed” | Repository checks + disposable semantic restore + fresh host replacement | Recovery health becomes executable and time-stamped. [VERIFIED: .planning/phases/KPL-02-synchronization-and-replaceable-server/02-CONTEXT.md:60-74] |
| `pg_dump` as complete recovery | pgBackRest physical/WAL PITR + `pg_dump -Fc` portability layer | PITR and cross-version/architecture escape hatch serve different failure modes. [CITED: https://www.postgresql.org/docs/18/backup.html] |
| Repair-in-place VM | OpenTofu-created replacement host from source | Proves there is no snowflake state and keeps provider details outside product code. [CITED: https://github.com/hetznercloud/terraform-provider-hcloud] |
| Mutable image tags | Tested OCI manifest digest promotion | Binds running artifact to CI evidence. [VERIFIED: .planning/phases/KPL-02-synchronization-and-replaceable-server/02-CONTEXT.md:69-74] |
| Current client only | Current + previous protocol train after first distribution, frozen codecs/vectors | Compatible deploys do not require coordinated upgrades. [VERIFIED: .planning/phases/KPL-02-synchronization-and-replaceable-server/02-CONTEXT.md:48-56] |

**Deprecated/outdated for this phase:** provider `datacenter` attributes were removed in current `hcloud`; use `location`. [CITED: https://github.com/hetznercloud/terraform-provider-hcloud/releases] Floating `latest` tags, offset bootstrap pagination, PostgreSQL sequence-based feed positions, app-owned certificate scripts, provider snapshots as recovery authority, and Mix-only production commands are prohibited by the locked decisions or current official guidance.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The target stable OpenTofu version should be `1.12.6`; the local machine currently has `1.9.0`. [ASSUMED] | Standard Stack / Environment | A version upgrade could alter state/plan behavior; prove `tofu init/validate/plan/test` before apply. |
| A2 | `Caddy 2.11.4` and `hcloud 1.68.0` should be the initial tested pins because they were current signed releases on the research date. [ASSUMED] | Standard Stack | Image/provider compatibility or a security advisory may require a different exact pin at implementation time. |
| A3 | StreamData `1.4.0` is worth one test-only dependency for shrinking long sync state-machine sequences. [ASSUMED] | Supporting Stack | The API may not fit the desired model; a small spike must prove useful shrinking and runtime before lock-in. |
| A4 | A dedicated S3-compatible state/backup repository with locking/versioning/object lock can be selected without adding a canonical product service. [ASSUMED] | Operations | Exact providers differ in lock and object-lock semantics; planning needs an explicit verified provider selection. |
| A5 | One amd64 Hetzner VM is the first reference architecture. [ASSUMED] | Environment / Deployment | Cost/performance or multi-arch image constraints may favor arm64; benchmark and restore-test before locking. |
| A6 | A one-minute `archive_timeout` plus pgBackRest async archive will meet the five-minute RPO under measured network conditions. [ASSUMED] | Backup | Object-store/network lag may exceed RPO; acceptance must measure archive visibility and recoverable target, not configuration. |

## Open Questions (RESOLVED)

1. **Which two off-host repositories satisfy versioning/object-lock, client-side encryption, independent-account mirroring, and recovery credentials?**
   - What we know: D-37 locks the required properties; pgBackRest supports S3-compatible repositories and multiple repositories. [CITED: https://pgbackrest.org/user-guide.html]
   - RESOLVED: Plan 02-08 Task 1 selects Backblaze B2 as the encrypted primary repository and AWS S3 with Object Lock in an independent account as the mirror, with lifecycle/retention configuration tracked under `infra/backup/`; Plan 02-09 Task 2 remains the honest credential checkpoint, and Plan 02-08 Task 3 plus Plan 02-09 Task 3 require real cross-provider restore evidence before acceptance.

2. **What are the initial feed page size, offline grace, and low-water pruning batch?**
   - What we know: retention must exceed the released-client window plus documented offline grace and safe bootstrap must always remain available.
   - RESOLVED: Plan 02-02 Task 2 freezes an initial 200-envelope pull page, 30-day offline grace beyond the active compatibility window, and 1,000-row pruning batch; destructive pruning remains disabled until low-water/status measurements and reset/bootstrap vectors pass.

3. **What exact native refresh lifetime and sender constraint should Phase 2 implement before native adapters exist?**
   - What we know: public-client authorization code + exact redirect + state + S256 PKCE and rotating hash-stored refresh lineage are locked.
   - RESOLVED: Plan 02-03 Task 2 freezes 15-minute access credentials, 30-day refresh inactivity, and 90-day absolute refresh-family lifetime. Phase 2 requires exact redirect/state/S256 PKCE and rotation/replay fencing but makes no device-bound sender-constraint claim before native-adapter evidence, consistent with D-23.

4. **Which DNS provider and cutover mechanism will support the host-replacement rehearsal?**
   - What we know: DNS changes only after candidate verification; OpenTofu should own supported provider inputs where practical.
   - RESOLVED: Plan 02-09 Tasks 2-3 select the Cloudflare DNS v4 API outward adapter at `infra/dns/cloudflare.sh`; the blocking checkpoint supplies only file/env references, and the runner must read the authoritative record, retain its value and TTL, stage the update, verify authoritative and recursive propagation, and exercise rollback before the old host can be retired.

5. **What exact Hetzner location/type meets restore and sustained workload needs?**
   - What we know: location/type are explicitly discretionary and current `hcloud` uses `location`, not `datacenter`. [CITED: https://github.com/hetznercloud/terraform-provider-hcloud/releases]
   - RESOLVED: Plan 02-09 Task 2 supplies the authority needed for measurement; Plan 02-09 Task 3 records the pre-mutation selection in `infra/tofu/hetzner/selection.json` after testing current availability and representative storage/restore throughput for `nbg1` x86 candidates, and refuses apply until that selection satisfies the four-hour restore objective. No live sizing claim is made before the checkpoint runs.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback / Action |
|------------|-------------|-----------|---------|-------------------|
| Repository runtime preflight | server tests/build | ✓ | Elixir `1.20.2`, OTP `29.0.5`, PostgreSQL `18.6` | Use `./tooling/runtime-preflight.sh --exec -- ...`; direct `mix` is not correctly selected in nested app cwd. [VERIFIED: tooling/runtime-versions.env:1-4] |
| Docker Engine | Compose/image tests | ✓ | client/server `29.5.2` | — |
| Docker Compose | local/reference topology | ✓ | `v5.1.3` | — |
| OpenTofu | Hetzner provisioning | ✓, below recommended target | `1.9.0` | Upgrade/pin `1.12.6` in Wave 0 and prove state migration; do not apply production with mixed versions. [ASSUMED] |
| PostgreSQL CLI on default PATH | backup commands | ✓, wrong default | `14.17` | Always use repository preflight's absolute PostgreSQL 18.6 toolchain. [VERIFIED: tooling/runtime-preflight.sh and environment probe 2026-09-01] |
| pgBackRest | physical/PITR | ✗ | — | Blocking for physical backup/restore; install exact `2.59.1` in packaged topology and restore worker. |
| Caddy | edge/rehearsal | ✗ locally | — | Use digest-pinned container; no host binary required. |
| Hetzner API credential | live provisioning | ✗ (`HCLOUD_TOKEN` unset) | — | Blocking only for live VM/replacement rehearsal; local `tofu validate/test` can proceed without it. |
| Backup repository/cipher credentials | encrypted off-host backup | ✗ | — | Blocking for real backup acceptance; use generated ephemeral local fixtures for non-production tests. |
| DNS credential | cutover rehearsal | ✗ | — | Blocking for automated DNS cutover; documented manual cutover is fallback only if explicitly chosen. |
| `jq`, `curl`, `openssl` | ops wrappers/probes/key generation | ✓ | `jq 1.7.1`; system curl; OpenSSL present | — |

**Missing dependencies with no acceptance fallback:** Hetzner credential for OPS-02/live replacement, real encrypted backup repositories and keys for DATA-02, pgBackRest 2.59.1 in the packaged runtime, and DNS authority for a complete DNS rehearsal.  
**Missing dependencies with development fallback:** Caddy host binary (use container), live object store (local emulator for contract tests only), live Hetzner resources (provider schema/unit tests until credentialed acceptance).

## Validation Architecture

Nyquist validation is enabled and security enforcement is enabled at ASVS level 1. The verbatim configuration values are `"nyquist_validation": true`, `"security_enforcement": true`, and `"security_asvs_level": 1`. [VERIFIED: .planning/config.json:20-49]

### Test Framework

| Property | Value |
|----------|-------|
| Server framework | ExUnit through repository-pinned Elixir `1.20.2`; real PostgreSQL 18.6 via existing disposable-cluster runner. [VERIFIED: tooling/test-phase-1.sh:20-80] |
| Property framework | StreamData `1.4.0` test-only — Wave 0 dependency/spike. [ASSUMED] |
| Contract framework | Existing OpenAPI generation drift + JSON vector readers; extend `tooling/check-contracts.mjs`. [VERIFIED: tooling/test-phase-1.sh:75-79] |
| Infrastructure framework | `docker compose config`, container health/smoke, `tofu fmt/validate/test/plan`, Caddy config validation, pgBackRest check/verify/restore. |
| Quick run command | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling/application/sync test/keepling/adapters/postgres/sync_feed_test.exs'` (planned paths) |
| Full suite command | `./tooling/test-phase-2.sh --run` (Wave 0 extension of existing consolidated runner) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| SRV-04 | Atomic ordered feed, cursors, tombstones, bootstrap/reset | property + PostgreSQL integration + API contract | `mix test test/keepling/application/sync test/keepling/adapters/postgres/sync_feed_test.exs` | ❌ Wave 0 |
| SRV-05 | Persisted structured conflicts replay and continue unrelated lanes | existing integration + new reference model vectors | `mix test test/keepling/adapters/postgres/conflict_test.exs test/keepling/application/sync` | ⚠️ conflict file exists; sync gaps Wave 0 |
| SRV-06 | current/previous train skew, frozen codecs, migration compatibility | contract matrix + migration | `pnpm contracts:check && ./tooling/test-compatibility.sh` | ❌ Wave 0 |
| DATA-02 | logical/latest-WAL/historical PITR disposable restores pass semantic smoke | restore integration | `./tooling/verify-restore.sh --fixture newest-logical && ./tooling/verify-restore.sh --fixture latest-wal` | ❌ Wave 0 |
| DATA-03 | durable-state inventory and source-driven host replacement | infrastructure E2E | `./tooling/verify-host-replacement.sh --dry-run` plus credentialed acceptance | ❌ Wave 0 |
| OPS-01 | pinned local Compose topology/health/private DB/no hidden state | container integration | `docker compose config && ./tooling/verify-compose.sh` | ❌ Wave 0 |
| OPS-02 | OpenTofu creates VM/firewall/network/bootstrap | tofu unit/plan + live acceptance | `tofu -chdir=infra/tofu/hetzner test && tofu -chdir=infra/tofu/hetzner plan` | ❌ Wave 0 |
| OPS-03 | exact digest migrate/readiness/smoke/503 interruption | image/deploy integration | `./tooling/verify-deploy.sh --local` | ❌ Wave 0 |
| OPS-04 | stable ops verbs, JSON, exit codes, refusal cases | ExUnit + CLI black-box | `mix test test/keepling/application/ops && ./tooling/test-ops-cli.sh` | ❌ Wave 0 |
| OPS-05 | liveness/readiness/status and local diagnostics | controller + packaged integration | `mix test test/keepling_web/health_test.exs test/keepling/application/ops/status_test.exs` | ❌ Wave 0 |
| QUAL-02 | parallel required lanes, cache/fan-out/timing/flake evidence | CI self-test | `./tooling/check-ci-contract.mjs` | ❌ Wave 0 |
| QUAL-05 | hostile content absent from all diagnostics/bundles | redaction integration + artifact scan | `mix test test/keepling/telemetry_redaction_test.exs test/keepling/ops_redaction_test.exs` | ⚠️ base test exists; Phase 2 gaps Wave 0 |

### Sampling Rate

- **Per task commit:** narrow ExUnit/contract/tofu/compose command under 30 seconds where possible.
- **Per wave merge:** `./tooling/test-phase-2.sh --run` with disposable PostgreSQL and local Compose.
- **Nightly/scheduled:** logical restore + latest recoverable WAL; collect duration and exact target evidence.
- **Weekly:** randomized historical PITR target.
- **Quarterly / phase acceptance:** fresh OpenTofu VM, full host replacement, and DNS rehearsal.
- **Phase gate:** full suite green plus credentialed restore and host-replacement evidence before `$gsd-verify-work`.

### Wave 0 Gaps

- [ ] Add StreamData `1.4.0` test-only and prove shrinking/replay on a small reference reducer before broad adoption. [ASSUMED]
- [ ] Define storage-neutral JSON Schemas for sync state-machine actions/results and anti-vacuity validation.
- [ ] Add reference reducer property harness and golden vector runner shared by Elixir now and TypeScript/Swift later.
- [ ] Add `test/support/sync_scenario.ex`, failure-injection clock/identity/network scripts, and real two-connection concurrency fixtures.
- [ ] Extend the disposable PostgreSQL runner to expose physical data/config paths required by pgBackRest without weakening isolation.
- [ ] Add local S3-compatible test repository fixture or provider abstraction; it is test infrastructure, not canonical state.
- [ ] Add image build/scan/smoke and immutable digest capture.
- [ ] Add Compose, Caddy, pgBackRest, OpenTofu validation commands and a consolidated Phase 2 runner.
- [ ] Add previous-image/schema fixtures and frozen prior protocol simulator.
- [ ] Add hostile diagnostic bundle fixture that scans stdout/stderr/logs/metrics/traces/JSON/manifests.

## Security Domain

### Applicable ASVS Categories

OWASP ASVS `5.0.0` is current stable and provides a basis for verifying technical security controls; the project config requires level 1 enforcement. [CITED: https://owasp.org/www-project-application-security-verification-standard/] [VERIFIED: .planning/config.json:47-49]

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| Authentication | yes | External user agent + exact redirect + unpredictable state + S256 PKCE; short-lived opaque access credentials; hash-stored rotating refresh lineage; definitive revocation/account fencing. |
| Session Management | yes | Namespace by issuer/origin + stable server instance + account subject + generation; retain quarantined state; reject late/fenced acknowledgement. |
| Access Control | yes | Account-scoped commands/feed/bootstrap/status; server independently validates cursor namespace; operator-only status and destructive ops authorization. |
| Input Validation | yes | Closed OpenAPI schemas, bounded page sizes, authenticated cursor decode, strict protocol intersection, explicit source/target validation, refusal of live/nonempty restore destinations. |
| Cryptography | yes | Platform crypto for HMAC/AEAD cursor envelope and random epochs/tokens; TLS via Caddy; pgBackRest client-side repository encryption; no custom primitives. |
| Secure Communication | yes | Public 80/443 edge only, private database network, no PostgreSQL exposure, short-interruption `503` with bounded retry guidance. |
| Logging / Error Handling | yes | Allow-listed bounded metadata, stable codes, no raw content/token/identifier/provider-body leakage, no default-on remote telemetry. |
| Data Protection | yes | Separate least-privilege backup/restore credentials, encrypted off-host/object-locked recovery, recoverable key manifest, OpenTofu state treated as sensitive. |
| Configuration | yes | Digest/provider/checksum pins, runtime fail-closed secrets, explicit schema/protocol/epoch readiness, no test controls in production. |

### Known Threat Patterns for the Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Tampered/cross-account cursor | Spoofing / Tampering | Authenticated envelope plus independent authenticated namespace comparison; stable reset/error, never empty success. |
| Refresh-token replay after rotation | Spoofing | Atomic lineage rotation/reuse detection, family revocation, fenced local namespace, exact lifecycle vectors. |
| Duplicate mutation with changed payload | Tampering | Account-scoped mutation receipt and constant-time semantic fingerprint compare; current code returns stable `mutation_identity_reused`. [VERIFIED: apps/server/lib/keepling/adapters/postgres/command_store.ex:1741-1772] |
| Forged feed order / skipped history | Tampering | PostgreSQL constraints + locked per-account clock + epoch-bound cursors + low-water reset. |
| Restore into live target | Tampering / Denial of Service | Refuse nonempty/live target; side effects disabled; explicit source/target; proof before DNS. |
| Backup theft | Information Disclosure | Client-side pgBackRest encryption, object lock/versioning, separate keys/credentials, independent mirror. [CITED: https://pgbackrest.org/user-guide.html] |
| OpenTofu state leakage | Information Disclosure | Remote encrypted state, locking/versioning, environment-supplied credentials, never output secrets; state remains sensitive. [CITED: https://opentofu.org/docs/language/state/sensitive-data/] |
| Diagnostic content/high-cardinality leak | Information Disclosure / Denial of Service | Closed event schemas, bounded dimensions, hostile sentinel artifact scans, no raw IDs/content. |
| Archive lag exhausts disk | Denial of Service | Monitor archive queue/lag/free space; separate serving readiness from deploy preflight; explicit operator remediation. [CITED: https://www.postgresql.org/docs/18/wal-configuration.html] |
| Mutable image/provider substitution | Tampering | OCI digest, `.terraform.lock.hcl` signed checksums, exact tested metadata, preflight rejection. [CITED: https://opentofu.org/docs/cli/commands/providers/lock/] |
| Operator action repudiation | Repudiation | Stable operation/run type, exact artifact/source/target digests, timestamps, result code, and verifier version without raw user identifiers. |

## Sources

### Primary (HIGH confidence for source authority; seam classifies verified WebSearch as MEDIUM)

- [PostgreSQL 18 explicit locking](https://www.postgresql.org/docs/18/explicit-locking.html) — row locks, deadlocks, canonical lock-order implications.
- [PostgreSQL 18 backup and restore](https://www.postgresql.org/docs/18/backup.html) — logical, file-system, continuous archive/PITR distinctions.
- [PostgreSQL 18 pg_dump](https://www.postgresql.org/docs/18/app-pgdump.html) — custom-format portability and restore behavior.
- [PostgreSQL 18 WAL configuration](https://www.postgresql.org/docs/18/wal-configuration.html) — archive failure retention/disk risk.
- [Phoenix 1.8.13 releases](https://phoenix.hexdocs.pm/releases.html) — release-safe migrations/custom commands without Mix.
- [Ecto.Multi 3.14](https://ecto.hexdocs.pm/Ecto.Multi.html) — transaction grouping and `Repo.transact` guidance.
- [pgBackRest 2.59.1 user guide](https://pgbackrest.org/user-guide.html) — archive, backup, encryption, retention, check, restore, PITR, version matching.
- [Docker Compose services](https://docs.docker.com/reference/compose-file/services/) and [networks](https://docs.docker.com/reference/compose-file/networks/) — health, dependency readiness, graceful stop, isolation.
- [Caddy reverse_proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy) and [automatic HTTPS](https://caddyserver.com/docs/automatic-https) — edge behavior.
- [OpenTofu state backends](https://opentofu.org/docs/language/state/backends/), [provider lock](https://opentofu.org/docs/cli/commands/providers/lock/), and [sensitive state](https://opentofu.org/docs/language/state/sensitive-data/) — state security/locking/checksums.
- [Hetzner hcloud provider](https://github.com/hetznercloud/terraform-provider-hcloud) and [releases](https://github.com/hetznercloud/terraform-provider-hcloud/releases) — official provider features/version/deprecations.
- [StreamData 1.4 ExUnitProperties](https://stream-data.hexdocs.pm/ExUnitProperties.html) — reproducible property tests and shrinking.
- [OWASP ASVS](https://owasp.org/www-project-application-security-verification-standard/) — current stable verification standard.

### In-Repository Primary Evidence

- `02-CONTEXT.md` — locked Phase 2 semantics, discretion, deferred scope, reusable seams.
- `apps/server/lib/keepling/adapters/postgres/command_store.ex` — current transaction/receipt/conflict/acknowledgement seam.
- `apps/server/priv/repo/migrations/20260830000100_create_core_task_command_tables.exs` and `...000800_add_persisted_conflicts.exs` — current compound keys, constraints, FKs, persisted conflict representation.
- `apps/server/test/support/concurrency_case.ex` — independent PostgreSQL backend/barrier concurrency proof.
- `apps/server/test/keepling/telemetry_redaction_test.exs` — allow-list and hostile-content redaction baseline.
- `tooling/runtime-versions.env`, `tooling/test-phase-1.sh`, `.github/workflows/repository-integrity.yml` — runtime/test/CI baseline.

### Secondary (MEDIUM confidence)

- `.planning/knowledge/snapshots/2026-08-28-platform-and-architecture.md` — retained evidence synthesis for sync/client boundaries.
- `.planning/knowledge/snapshots/2026-08-28-deployment-and-recovery.md` — retained evidence synthesis for topology and recovery; current context supersedes its unresolved RPO/PITR choices.
- Current release pages for Caddy, OpenTofu, hcloud, pgBackRest — version facts valid only until the stated research validity date.

### Tertiary (LOW confidence)

- None used as authority. Items that remain choices or require live-provider measurement are marked `[ASSUMED]` in the Assumptions Log.

## Metadata

**Confidence breakdown:**
- Standard stack: **HIGH** for repository runtimes and locked technology choices; **MEDIUM** for external current release pins because the research seam classifies verified WebSearch as MEDIUM.
- Architecture: **HIGH** because it extends opened source-of-truth files and locked Phase 2 decisions.
- Synchronization pitfalls: **HIGH/MEDIUM** from current PostgreSQL docs plus existing transaction/concurrency code.
- Operations/recovery: **MEDIUM-HIGH** from official pgBackRest/PostgreSQL/Phoenix/Compose/OpenTofu/Caddy docs; live provider proof remains outstanding.
- Security: **MEDIUM-HIGH** from locked threat semantics, existing redaction tests, and OWASP ASVS; exact provider/key-management implementation awaits selection.

**Research date:** 2026-09-01  
**Valid until:** 2026-09-08 for external release pins/provider behavior; 2026-10-01 for stable PostgreSQL/Phoenix/architecture guidance.  
**Graph context:** skipped because `.planning/config.json` has verbatim `"graphify": { "enabled": false }`. [VERIFIED: .planning/config.json:94-99]  
**Runtime State Inventory:** omitted because this is a feature/greenfield infrastructure phase, not a rename/refactor/migration of an existing deployed runtime.
