---
phase: KPL-02-synchronization-and-replaceable-server
plan: 05
subsystem: synchronization
tags: [elixir, phoenix, sync-transport, openapi, telemetry, privacy]

requires:
  - phase: KPL-02-synchronization-and-replaceable-server
    plan: 02
    provides: atomic ordered feed, authenticated cursors, bootstrap, restore epoch, and tombstones
  - phase: KPL-02-synchronization-and-replaceable-server
    plan: 03
    provides: separately revocable installation grants and synchronization-generation fencing
  - phase: KPL-02-synchronization-and-replaceable-server
    plan: 04
    provides: authoritative protocol-train compatibility policy
  - phase: KPL-02-synchronization-and-replaceable-server
    plan: 11
    provides: bearer-authenticated server-derived installation namespace
provides:
  - Bearer-authenticated bounded feed pull and canonical bootstrap HTTP routes
  - Closed generated synchronization envelopes, positions, tombstones, and reset problems
  - Exact cross-runtime mutation, synchronization, compatibility, and recovery trust states
  - Allow-listed sync diagnostics and hostile-sentinel redaction vectors
affects: [desktop-sync, ios-sync, operator-diagnostics, compatibility, accessibility]

actuals:
  tokens: 15059
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns: [thin bearer sync adapter, server-derived cursor namespace, bounded diagnostic metadata, closed trust-state vectors]

key-files:
  created:
    - apps/server/lib/keepling_web/controllers/sync_controller.ex
    - apps/server/priv/repo/migrations/20260901000300_initialize_sync_epoch.exs
    - apps/server/test/keepling_web/sync_controller_test.exs
    - packages/contracts/vectors/redaction.json
  modified:
    - apps/server/lib/keepling/application/sync.ex
    - apps/server/lib/keepling/adapters/postgres/sync_feed.ex
    - apps/server/lib/keepling_web/router.ex
    - apps/server/lib/keepling_web/telemetry.ex
    - apps/server/test/keepling/telemetry_redaction_test.exs
    - packages/contracts/openapi/keepling.yaml
    - packages/contracts/generated/keepling.ts
    - tooling/check-contracts.mjs

key-decisions:
  - "Sync transport accepts namespace authority only from the authenticated DeviceGrant assign, then enriches it with the finalized database restore epoch and authoritative current protocol train."
  - "Feed coverage advances only to the last returned ordered envelope; acknowledgements remain separate from global coverage and an empty page preserves the submitted cursor."
  - "Synchronization diagnostics expose exactly operation and outcome from closed bounded vocabularies; content, credentials, cursors, identifiers, and provider bodies never become metadata."
  - "D-49 trust states are generated wire vocabulary while D-50 through D-54 presentation and privacy requirements remain executable storage-neutral vectors for later platform clients."

patterns-established:
  - "Authenticated sync adapter: bearer pipeline derives authority, application Sync decides pull/bootstrap semantics, and PostgreSQL remains behind the declared port."
  - "Explicit reset: tamper, namespace, protocol, codec, restore epoch, expiry, and low-water conditions produce stable non-empty Problem Details with one recovery action."
  - "Privacy-safe observability: a span wrapper classifies terminal sync results without inspecting or serializing result bodies or exceptions."

requirements-completed: [SRV-04, SRV-05, QUAL-05]

coverage:
  - id: D1
    description: "Current-train native installations can pull bounded ordered pages and bootstrap canonical state through the server-derived bearer namespace."
    requirement: SRV-04
    verification:
      - kind: integration
        ref: "apps/server/test/keepling_web/sync_controller_test.exs#authenticated installation pulls bounded changes and bootstraps canonical state"
        status: pass
      - kind: other
        ref: "pnpm contracts:check#generated SyncFeedPage and SyncBootstrapPage"
        status: pass
    human_judgment: false
  - id: D2
    description: "Tampered, cross-generation, and cross-server cursors fail with explicit reset or quarantine problems instead of empty success."
    requirement: SRV-05
    verification:
      - kind: integration
        ref: "apps/server/test/keepling_web/sync_controller_test.exs#closed input and namespace fencing cases"
        status: pass
      - kind: integration
        ref: "mix test synchronization scope#24 passed including 1 property"
        status: pass
    human_judgment: false
  - id: D3
    description: "Exact D-49 trust states and D-50 through D-54 recovery/accessibility facts are closed generated contracts with unknown-state rejection."
    requirement: QUAL-05
    verification:
      - kind: unit
        ref: "apps/server/test/keepling/telemetry_redaction_test.exs#redaction vectors lock trust states recovery facts and accessible presentation"
        status: pass
      - kind: other
        ref: "pnpm contracts:check#19 trust facts and malformed unknown state rejected"
        status: pass
    human_judgment: false
  - id: D4
    description: "Sync success, reset, unavailable, and exception diagnostics contain only bounded operation and outcome metadata and no hostile sentinels."
    requirement: QUAL-05
    verification:
      - kind: unit
        ref: "apps/server/test/keepling/telemetry_redaction_test.exs#sync success reset and exception diagnostics expose only bounded state facts"
        status: pass
      - kind: integration
        ref: "apps/server full suite#152 passed including 1 property"
        status: pass
    human_judgment: false

duration: 13min
completed: 2026-09-01
status: complete
---

# Phase KPL-02 Plan 05: Authenticated Sync Transport and Trust States Summary

**Bearer-derived sync pull/bootstrap now expose bounded ordered state with explicit cursor recovery, while generated trust states and allow-listed diagnostics preserve privacy across success and failure paths.**

## Performance

- **Duration:** 13 min
- **Started:** 2026-09-01T07:17:16Z
- **Completed:** 2026-09-01T07:30:00Z
- **Tasks:** 2
- **Files modified:** 12 implementation, migration, contract, vector, and proof files

## Accomplishments

- Added authenticated `GET /api/v1/sync` and `GET /api/v1/sync/bootstrap` routes with strict limits, closed queries, signed coverage/bootstrap cursors, and explicit recovery problems.
- Bound every pull/bootstrap to issuer, origin, server instance, account subject, installation generation, finalized restore epoch, and current protocol train without accepting client namespace claims.
- Added closed generated feed/bootstrap DTOs and exact mutation, synchronization, compatibility, and recovery trust-state enums.
- Added 19 complete durable-location/consequence/next-action facts, accessibility requirements, hostile diagnostic sentinels, and allow-listed sync telemetry.
- Kept the full 152-test server suite green and regenerated the TypeScript contract without drift.

## Task Commits

Each TDD task was committed as a RED test followed by its GREEN implementation:

1. **Task 1 RED: failing authenticated sync transport proof** - `8440699` (test)
2. **Task 1 GREEN: bounded pull/bootstrap transport and generated DTOs** - `f9c94aa` (feat)
3. **Task 2 RED: failing trust-state and redaction proof** - `43d68f1` (test)
4. **Task 2 GREEN: closed trust states and privacy-safe diagnostics** - `0f1fc23` (feat)

## Files Created/Modified

- `apps/server/lib/keepling_web/controllers/sync_controller.ex` - Thin bearer-authenticated pull/bootstrap adapter and stable Problem Details mapping.
- `apps/server/lib/keepling/application/sync.ex` - Bounded pull orchestration, cursor decode/encode, and coverage semantics.
- `apps/server/lib/keepling/adapters/postgres/sync_feed.ex` - Finalized epoch context, low-water state, and limit-plus-one page detection.
- `apps/server/priv/repo/migrations/20260901000300_initialize_sync_epoch.exs` - One finalized random epoch for fresh database installs.
- `apps/server/lib/keepling_web/telemetry.ex` - Closed sync span classification and bounded metric dimensions.
- `apps/server/test/keepling_web/sync_controller_test.exs` - Authenticated transport, invalid input, fencing, bootstrap, and denial proofs.
- `apps/server/test/keepling/telemetry_redaction_test.exs` - Success/reset/exception diagnostic and cross-runtime trust-vector proofs.
- `packages/contracts/openapi/keepling.yaml` and `packages/contracts/generated/keepling.ts` - Closed sync transport and trust-state wire DTOs.
- `packages/contracts/vectors/redaction.json` - D-49 through D-54 semantic, accessibility, technical-detail, and hostile-sentinel truth.
- `tooling/check-contracts.mjs` - Exact state-set, exhaustive fact, malformed-state, and sentinel anti-vacuity checks.

## Decisions Made

- Kept cursor signing material derived from the endpoint secret but owned the decode/recovery decision in the inward synchronization application module.
- Used the finalized database epoch as restore authority; a missing/unfinalized epoch returns retryable service unavailability rather than manufacturing state in a request.
- Returned `has_more` from a limit-plus-one PostgreSQL read while exposing at most 200 feed envelopes or 100 bootstrap entities.
- Kept product copy out of the server transport; vectors lock state meaning and accessibility requirements while Phase 3/4 retain platform layout and final-copy ownership.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] Added the application pull seam and bounded page continuation**
- **Found during:** Task 1 GREEN implementation
- **Issue:** The prior application boundary implemented bootstrap and cursor codecs but exposed no inward pull operation or reliable `has_more` result for the HTTP adapter.
- **Fix:** Added application-owned pull orchestration and limit-plus-one persistence paging while retaining acknowledgement/feed-coverage separation.
- **Files modified:** `apps/server/lib/keepling/application/sync.ex`, `apps/server/lib/keepling/adapters/postgres/sync_feed.ex`
- **Verification:** 24 focused synchronization tests passed, including one property.
- **Committed in:** `f9c94aa`

**2. [Rule 2 - Missing critical functionality] Initialized the singleton synchronization epoch for fresh installs**
- **Found during:** Task 1 authenticated context construction
- **Issue:** The existing migration created `sync_epochs` but inserted no finalized epoch, so a fresh server could not safely issue a cursor or bootstrap response.
- **Fix:** Added an idempotent data migration that installs one random finalized epoch without overwriting an existing restored epoch.
- **Files modified:** `apps/server/priv/repo/migrations/20260901000300_initialize_sync_epoch.exs`
- **Verification:** Fresh disposable migrations and the full 152-test server suite passed.
- **Committed in:** `f9c94aa`

**3. [Rule 2 - Missing critical functionality] Made trust-state vectors an enforced contract**
- **Found during:** Task 2 GREEN implementation
- **Issue:** Merely checking in `redaction.json` would not reject unknown enum drift, missing state facts, or hostile sentinels copied into diagnostic examples.
- **Fix:** Extended the contract gate with exact state sets, 19 unique exhaustive facts, sentinel scans, and a deliberately malformed unknown-state fixture.
- **Files modified:** `tooling/check-contracts.mjs`
- **Verification:** `pnpm contracts:check` validated 19 facts and rejected the malformed state.
- **Committed in:** `0f1fc23`

---

**Total deviations:** 3 auto-fixed Rule 2 issues.
**Impact on plan:** All additions were required to make the planned transport safe and executable; no new dependency, service, canonical data store, or outward domain dependency was introduced.

## Issues Encountered

- The plan's literal focused Mix command lacked the repository-required test database environment. Verification used the same runtime-preflight command against an owned disposable PostgreSQL 18.6 database with all migrations applied.
- The full suite emitted expected bounded error logs from its database-timeout and degraded-security-audit test cases; all 152 tests passed.

## Known Stubs

None. The scan found no TODO/FIXME/placeholder path, skipped test, or hardcoded empty value flowing to a product surface.

## User Setup Required

None - no external service or credential is required for this plan.

## Next Phase Readiness

- Desktop and iPhone clients can generate against stable pull/bootstrap envelopes and exact D-49 trust-state vocabulary without importing server persistence rows.
- Plan 02-06 can reuse the allow-listed diagnostic pattern and recovery-state facts for operator health/status surfaces.
- Restore work can rotate the database epoch and rely on old cursors receiving `sync_restore_epoch_changed` with bootstrap recovery.

---
*Phase: KPL-02-synchronization-and-replaceable-server*
*Completed: 2026-09-01*

## Self-Check: PASSED

- All four created implementation, migration, proof, and vector artifacts plus this summary exist on disk.
- All four RED/GREEN task commits are present in Git history.
- Coverage metadata declares all three plan requirements and four deliverables backed by passing automation.
