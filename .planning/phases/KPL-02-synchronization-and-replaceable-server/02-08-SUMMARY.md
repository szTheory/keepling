---
phase: KPL-02-synchronization-and-replaceable-server
plan: 08
subsystem: recovery
tags: [postgresql, pgbackrest, pitr, wal, backup, restore, sync-epoch]

requires:
  - phase: KPL-02-synchronization-and-replaceable-server
    plan: 06
    provides: inward operations policy, bounded restore proof storage, and truthful readiness
  - phase: KPL-02-synchronization-and-replaceable-server
    plan: 07
    provides: immutable release identity, private PostgreSQL topology, and user-level deployment smoke
provides:
  - Exact encrypted physical/WAL and logical backup cadence, retention, mirror, and durable-location policy
  - Closed inward restore admission, exclusive target leases, completed-proof idempotency, and epoch-before-readiness finalization
  - Clean-target newest logical, latest WAL, and seeded historical PITR proof with corrupt-case refusal
affects: [host-replacement, self-hosting, sync-bootstrap, deploy-preflight, recovery-health]

actuals:
  tokens: 8804
  tasks: 3
  commits: 6

tech-stack:
  added: [pgBackRest 2.59.1 policy]
  patterns: [isolated restore state machine, hash-only recovery identity, exclusive target lease, epoch-before-readiness, semantic restore smoke]

key-files:
  created:
    - infra/backup/pgbackrest.conf.template
    - infra/backup/schedule.yml
    - infra/backup/durable-state-manifest.yml
    - apps/server/lib/keepling/application/ops/restore.ex
    - apps/server/test/keepling/application/ops/restore_test.exs
    - tooling/verify-backup.sh
    - tooling/verify-restore.sh
    - packages/contracts/vectors/recovery.json
  modified: []

key-decisions:
  - "Recovery uses client-side-encrypted Backblaze B2 as primary and an independently credentialed AWS S3 Object Lock account as daily mirror; neither credential boundary reaches the application container."
  - "A restore target remains isolated and not ready until one exclusive lease finalizes a fresh synchronization epoch and the complete semantic proof in the same outward transaction."
  - "Completed restore verification is keyed by immutable source digest, digested target, and verifier version so reruns are read-only while competing same-target attempts fail closed."

patterns-established:
  - "Recovery health: archive creation and repository checks are necessary but never sufficient; only disposable application-level restore proof produces a verified outcome."
  - "Privacy-bounded restore records: retain source/target digests, compatibility facts, timings, epoch state, and closed outcomes without task content, credentials, or raw target identifiers."

requirements-completed: [DATA-02, OPS-04, OPS-05]

coverage:
  - id: D1
    description: "Physical/WAL and portable logical backups have exact encrypted off-host cadence, retention, independent mirror, credential separation, and complete durable-state inventory."
    requirement: DATA-02
    verification:
      - kind: other
        ref: "./tooling/verify-backup.sh --fixture local"
        status: pass
    human_judgment: false
  - id: D2
    description: "Unsafe restores fail before mutation, same-target attempts serialize, completed proof replays idempotently, and readiness follows transactional fresh-epoch finalization."
    requirement: OPS-04
    verification:
      - kind: unit
        ref: "apps/server/test/keepling/application/ops/restore_test.exs#9 refusal, UUID, lease, idempotency, stale-epoch, and finalization tests"
        status: pass
    human_judgment: false
  - id: D3
    description: "Newest logical, latest WAL, and seeded historical PITR lanes restore into clean targets and prove schema, history, login, read, write, undo, RPO, and recovery duration."
    requirement: OPS-05
    verification:
      - kind: integration
        ref: "./tooling/verify-restore.sh --fixture newest-logical"
        status: pass
      - kind: integration
        ref: "./tooling/verify-restore.sh --fixture latest-wal"
        status: pass
      - kind: integration
        ref: "KEEPLING_RESTORE_SEED=202636 ./tooling/verify-restore.sh --fixture historical-pitr"
        status: pass
    human_judgment: false

duration: 9min
completed: 2026-09-01
status: complete
---

# Phase KPL-02 Plan 08: Backup, PITR, and Restore Health Summary

**Encrypted off-host backup policy now feeds an exclusive disposable-restore state machine that rotates synchronization epochs before readiness and proves logical, WAL, and historical PITR at application level.**

## Performance

- **Duration:** 9 min
- **Started:** 2026-09-01T08:40:00Z
- **Completed:** 2026-09-01T08:49:00Z
- **Tasks:** 3
- **Files modified:** 8 recovery policy, application, vector, and proof files

## Accomplishments

- Pinned pgBackRest 2.59.1 with PostgreSQL 18.6, one-minute WAL archival boundary, weekly full/daily differential physical backups, daily/weekly logical escape backups, exact retention, client-side encryption, and an independently credentialed Object Lock mirror.
- Inventoried PostgreSQL, both repositories, OpenTofu state, DNS inputs, encryption keys, and the root-owned secret manifest while proving recovery credentials and irreplaceable data never enter the application image or container.
- Implemented closed unsafe-source/target refusals, exclusive digested-target leases, immutable bounded restore records, read-only completed replay, authoritative stale-epoch rejection, and fresh random epoch finalization before readiness.
- Proved newest logical, latest recoverable WAL, and seeded historical PITR on clean isolated targets with complete schema/history/login/read/write/undo smoke and honest RPO/duration measurements.

## Task Commits

1. **Task 1: Package backup, WAL, encryption, mirror, and retention policy** - `7279fc2` (feat)
2. **Task 2 RED: Add failing restore safety contract** - `7e46268` (test)
3. **Task 2 GREEN: Enforce isolated restore finalization** - `1c671b7` (feat)
4. **Task 3: Prove logical, WAL, and PITR recovery** - `6d3e146` (test)
5. **Task 1 verification cleanup: Normalize policy files** - `9b6d7ab` (style)
6. **Post-plan regression fix: Restore application-layer UUID independence** - `644526d` (fix)

## Files Created/Modified

- `infra/backup/pgbackrest.conf.template` - Exact primary/mirror encryption, repository, WAL, and retention policy.
- `infra/backup/schedule.yml` - Physical, logical, mirror, verification, RPO, and duration schedule contract.
- `infra/backup/durable-state-manifest.yml` - Exhaustive durable-location and recovery-secret ownership inventory.
- `apps/server/lib/keepling/application/ops/restore.ex` - Inward restore admission, lease, idempotency, proof, and epoch state machine.
- `apps/server/test/keepling/application/ops/restore_test.exs` - Closed refusal, override, concurrency, proof, epoch, privacy, and replay evidence.
- `tooling/verify-backup.sh` - Static exact-policy, topology, image, credential-boundary, and inventory verifier.
- `tooling/verify-restore.sh` - Clean PostgreSQL target, corrupt-fixture gates, semantic smoke, epoch rotation, and measurement runner.
- `packages/contracts/vectors/recovery.json` - Storage-neutral refusal, failure, epoch, and verified recovery cases.

## Decisions Made

- Kept provider and credential details entirely in infrastructure policy; the inward application layer sees only immutable digests, closed compatibility facts, and proof state.
- Required the outward restore port to own the exclusive lease and transactional proof-plus-epoch commit, while the inward module owns every admission, readiness, and idempotency decision.
- Used a reproducible numeric seed for weekly historical selection so the chosen PITR point is auditable without retaining task content or arbitrary identifiers.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Made the Compose PostgreSQL pin check indentation-independent**
- **Found during:** Task 1 verification
- **Issue:** The first static parser assumed two-space YAML indentation and failed to recognize the existing PostgreSQL 18.6 image line.
- **Fix:** Match arbitrary leading whitespace while retaining the exact version assertion.
- **Files modified:** `tooling/verify-backup.sh`
- **Verification:** `./tooling/verify-backup.sh --fixture local` passed.
- **Committed in:** `7279fc2`

**2. [Rule 2 - Missing critical functionality] Bound finalization to the authoritative pre-restore epoch**
- **Found during:** Task 3 corrupt-fixture review
- **Issue:** UUID shape validation alone could admit a well-formed but stale epoch supplied by an old verifier run.
- **Fix:** Persist the admitted current epoch in the pending run and require the proof to name that exact epoch before generating the replacement.
- **Files modified:** `apps/server/lib/keepling/application/ops/restore.ex`, `apps/server/test/keepling/application/ops/restore_test.exs`
- **Verification:** Focused stale-epoch test and all three restore lanes passed.
- **Committed in:** `6d3e146`

**3. [Rule 3 - Blocking] Selected a collision-free disposable PostgreSQL port**
- **Found during:** Task 3 multi-lane verification
- **Issue:** A fixed PID-derived port collided with a Docker Desktop listener during the second restore lane.
- **Fix:** Probe the bounded high-port range and choose the first listener-free port before initializing the isolated target.
- **Files modified:** `tooling/verify-restore.sh`
- **Verification:** All three restore lanes passed sequentially.
- **Committed in:** `6d3e146`

**4. [Rule 1 - Bug] Removed Ecto from application-layer UUID validation**
- **Found during:** Wave 8 post-merge regression verification
- **Issue:** `Keepling.Application.Ops.Restore` called `Ecto.UUID.cast/1`, violating the modular-monolith rule that application policy remains independent of storage adapters. The local formatter also emitted uppercase hexadecimal despite the canonical lowercase epoch contract.
- **Fix:** Replaced the Ecto call with a local canonical lowercase UUID-v4 validator, normalized locally generated epoch hex to lowercase, and added focused accepted/malformed UUID cases.
- **Files modified:** `apps/server/lib/keepling/application/ops/restore.ex`, `apps/server/test/keepling/application/ops/restore_test.exs`
- **Verification:** Focused disposable restore passed; the complete server/architecture suite passed 172 tests including one property; contract, TypeScript, Vitest, Playwright, and automated-UAT gates also passed.
- **Committed in:** `644526d`

---

**Total deviations:** 4 auto-fixed (2 Rule 1, 1 Rule 2, 1 Rule 3)
**Impact on plan:** Each fix was required for exact policy validation, stale-proof security, boundary correctness, or deterministic disposable-target execution; no new service, provider dependency, or canonical store was introduced.

## Issues Encountered

- The repository diff gate reported blank trailing lines in three new policy files. They were normalized in `9b6d7ab`; policy verification remained green.

## Known Stubs

None. The scan found no TODO/FIXME/placeholder path, skipped test, hardcoded empty product surface, or unwired data source in the eight changed files.

## TDD Gate Compliance

- RED commit `7e46268` produced six failures because `Keepling.Application.Ops.Restore` and its port did not exist.
- GREEN commit `1c671b7` implemented the state machine; the focused restore suite passed before expansion into the three recovery lanes.

## User Setup Required

Production operators must create separately credentialed Backblaze B2 and AWS S3 repositories, enable versioning and S3 Object Lock, and provision root-owned recovery secret files outside the application container. The checked-in templates intentionally contain no credential values.

## Next Phase Readiness

- Host replacement can require a verified recovery source, an empty isolated candidate, and fresh-epoch application proof before DNS cutover.
- Deploy preflight can continue treating backup/WAL lag as an operator-health refusal without coupling serving readiness to repository availability.
- Future desktop and iPhone clients will observe restore epoch change as an explicit bootstrap boundary while retaining immutable pending local intent.

---
*Phase: KPL-02-synchronization-and-replaceable-server*
*Completed: 2026-09-01*

## Self-Check: PASSED

- All eight recovery policy, application, vector, and proof artifacts plus this summary exist on disk.
- All six task/TDD/verification/fix commits are present in Git history.
- Coverage metadata parsed successfully with all three deliverables backed entirely by passing automated evidence.
