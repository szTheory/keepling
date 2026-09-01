# Phase 2: Synchronization and Replaceable Server - Context

**Gathered:** 2026-09-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver and formally prove Keepling's offline synchronization contract, compatible server-evolution contract, privacy-safe operational surface, and always-on recoverable reference deployment. The server atomically persists canonical command outcomes and an ordered account-scoped change feed; storage-neutral golden vectors define behavior for later Electron and iPhone adapters; a pinned Phoenix-plus-PostgreSQL topology runs locally and on one replaceable Hetzner VM; and backup health is established only through executable disposable restore and host-replacement evidence. This phase defines cross-client semantic states and recovery actions, not final Mac/iPhone persistence adapters or screens.

</domain>

<decisions>
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

- Exact PostgreSQL table/index names, change-clock representation, cursor encoding, page sizes, retry jitter/backoff, and bounded retention mechanics consistent with the locked semantics.
- Exact resource/dependency key encoding, bootstrap endpoint shape, compatibility headers and metadata field names, and OpenAPI diff tooling.
- Exact second backup provider, scheduler, Hetzner location/machine size after measurement, DNS cutover mechanism, and whether optional provider snapshots justify their cost.
- Exact native access-token lifetime, refresh retry grace/sender constraint, Apple protection class, Electron SQLite/encryption adapter, and dormant-store retention after the platform phases produce evidence.
- Exact UI placement, iconography, layout, motion, announcement phrasing, and copy refinements within the locked semantic states, accessibility contract, and brand voice.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.** Dated snapshots are evidence, not instructions; current lifecycle documents and decision dispositions win on conflict.

### Product scope and phase authority

- `.planning/PROJECT.md` — current product truth, trust guarantee, constraints, and exclusions.
- `.planning/REQUIREMENTS.md` — Phase 2 requirements SRV-04..06, DATA-02..03, OPS-01..05, QUAL-02, and QUAL-05.
- `.planning/ROADMAP.md` — Phase 2 goal, boundary, success criteria, and no-UI hint.
- `.planning/STATE.md` — current workflow position and retained Phase 2 open decisions.
- `.planning/phases/KPL-01-one-trustworthy-task/01-CONTEXT.md` — locked mutation identity, conflict, acknowledgement, session, activity, cursor, and privacy semantics that Phase 2 extends.

### Architecture and retained decision authority

- `docs/architecture/REPOSITORY.md` — ownership boundaries, dependency direction, infrastructure limits, and shared-contract rules.
- `.planning/knowledge/DECISIONS.md` — active architecture decisions D-004 through D-010.
- `.planning/knowledge/OPEN-QUESTIONS.md` — OQ-006 through OQ-009 concerning fencing, compatibility, at-rest protection, and recovery objectives.
- `.planning/research/SUMMARY.md` — normalized research conclusions and roadmap implications.
- `.planning/knowledge/snapshots/2026-08-28-platform-and-architecture.md` — retained evidence for the sync contract, client boundaries, golden vectors, and CI layers.
- `.planning/knowledge/snapshots/2026-08-28-deployment-and-recovery.md` — retained evidence for reference topology, backup/PITR tradeoffs, recovery invariants, upgrades, and operator experience.

### Product intent and interaction character

- `.planning/knowledge/provenance/gtd-app-original-prompt.txt` — original owner intent emphasizing Things-quality calm, offline/native trust, strong automation, architecture, SRE, DX, and design quality.
- `docs/brand/BRAND-SEED.md` — current brand authority for honest state language, calm agency, operator copy, accessibility, and motion character; supersedes older brand exploration where they conflict.

### Existing contracts and boundary declarations

- `apps/server/README.md` — server ownership of canonical persistence, synchronization adapters, migrations, and inward dependency direction.
- `infra/README.md` — Phase 2 infrastructure ownership and portable-contract-before-provider rule.
- `packages/README.md` — shared package limits for contracts, golden vectors, generated transport, tokens, and proven presentation seams.
- `packages/contracts/openapi/keepling.yaml` — current closed v1 command/result, session, conflict, cursor, and Problem Details contract to evolve compatibly.
- `packages/contracts/vectors/conflicts.json` — existing semantic merge/conflict vectors.
- `packages/contracts/vectors/lifecycle.json` — existing lifecycle idempotency and conflict vectors.
- `packages/contracts/vectors/trash-restore.json` — existing exact-revision Trash/restore vectors; Trash must not be reinterpreted as a tombstone.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `apps/server/lib/keepling/adapters/postgres/command_store.ex`: already centralizes account-scoped transactions, row locks, durable receipts, replay, persisted conflicts, activity, acknowledgements, and semantic fingerprints; Phase 2 extends this seam rather than creating a parallel sync write path.
- `apps/server/priv/repo/migrations/20260830000100_create_core_task_command_tables.exs`: existing compound account/mutation keys, receipt completeness constraint, task revisions, and activity foreign keys provide the transactional spine.
- `apps/server/priv/repo/migrations/20260830000800_add_persisted_conflicts.exs`: existing immutable original-conflict linkage and fresh resolution identity support lane quarantine and sync conflict vectors.
- `apps/server/lib/keepling/accounts.ex` and `apps/server/lib/keepling/accounts/session.ex`: tracked revocable sessions and a future native authorization-code seam provide the base for device grants and account fencing.
- `apps/server/lib/keepling/accounts/security_audit.ex`: existing latched audit-persistence health establishes a pattern for bounded operator health without leaking identifiers.
- `apps/server/lib/keepling_web/telemetry.ex` and `apps/server/test/keepling/telemetry_redaction_test.exs`: allow-listed low-cardinality metrics and hostile-content tests are reusable for sync and operations telemetry.
- `tooling/runtime-preflight.sh`, `tooling/run-local-stack.sh`, and `tooling/check-contracts.mjs`: deterministic runtime, stack, and contract checks can be extended behind the stable operations vocabulary.

### Established Patterns

- Domain/application rules remain independent of Phoenix, Ecto schemas, infrastructure, generated DTOs, and client persistence.
- Closed semantic commands, expected revisions, fingerprinted account-scoped mutation receipts, stable Problem Details, and exact acknowledgement already exist and remain authoritative.
- User-visible activity, mutation receipts, persisted conflicts, synchronization feed, security audit, and diagnostic telemetry are deliberately separate representations.
- Generated TypeScript transport is derived from checked-in OpenAPI; storage-neutral JSON vectors carry semantic truth across runtimes.
- Runtime configuration fails closed with named missing keys without printing secrets; production uses PostgreSQL as the only canonical state.

### Integration Points

- Add ordered change-feed persistence and retrieval beside the existing PostgreSQL command transaction, with application ports independent of Phoenix transport.
- Add sync/bootstrap/compatibility/health schemas to checked-in contracts and generate consumers through existing tooling.
- Add storage-neutral sync, account-lifecycle, compatibility, restore-epoch, and redaction vectors under `packages/contracts/vectors/`.
- Extend the current account/session boundary for installation grants and revocation semantics without making clients share browser cookies.
- Build portable image, Compose, Caddy, backup, restore, OpenTofu/Hetzner, and stable operator wrappers under `infra/` and `tooling/`, subordinate to app health and recovery contracts.
- Extend required CI fan-out from the current server/contracts/web lanes to compatibility, deployment, backup, and restore evidence.

</code_context>

<specifics>
## Specific Ideas

- A conflict on Task A pauses Task A descendants while Task B continues; a Today move or organization assignment declares every shared scope it touches.
- Pull continues during conflict so current canonical values may advance; resolution always uses a fresh mutation identity against the latest revision and may honestly conflict again.
- Cursor reset and bootstrap are normal recovery states, not exceptional data loss. A database restore always changes the synchronization epoch before readiness.
- The compatibility promise is intentionally bounded like an explicit skew policy, while protocol range negotiation separates wire compatibility from Mac/iPhone marketing versions.
- The one excellent self-host path emphasizes stable operator commands, exact tested image digests, honest short interruption, disposable restore evidence, and source-driven host replacement rather than nominal platform breadth.
- Product copy distinguishes saved locally, checking, server-accepted, conflicted, waiting for sign-in, quarantined, unsupported, and restore-verified states without exposing backend machinery.

</specifics>

<deferred>
## Deferred Ideas

- Application-layer encrypted client vaults, biometric app lock, proven cryptographic erasure, and remote-wipe capability; revisit in the Electron/iPhone adapter phases after packaged and physical-device evidence.
- Permanent task purge and its content/history/tombstone/backup-expiry policy; Trash remains durable canonical state.
- OIDC/federated identity, collaboration account switching, enterprise device policy, and remote administration.
- Arbitrary capability negotiation, indefinite historical API adapters, or third-party public API permanence beyond the bounded released-client contract.
- High availability, gapless/zero-downtime deployment, Kamal, Kubernetes, Redis, multi-node PostgreSQL, or a hosted control plane until measured need justifies the complexity.
- Final Mac/iPhone sync screens, icons, animation, and platform-specific layout; Phase 2 locks semantic states and vectors only.

</deferred>

---

*Phase: 2-Synchronization and Replaceable Server*
*Context gathered: 2026-09-01*
