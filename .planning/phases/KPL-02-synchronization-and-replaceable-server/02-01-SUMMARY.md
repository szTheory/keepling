---
phase: KPL-02-synchronization-and-replaceable-server
plan: 01
subsystem: synchronization
tags: [elixir, stream-data, offline-sync, json-schema, property-testing]

requires:
  - phase: KPL-01-one-trustworthy-task
    provides: stable semantic mutations, exact receipts, task snapshots, and persisted conflicts
provides:
  - Storage-neutral D-01 through D-06 synchronization reference reducer
  - Closed fixed-clock synchronization schema and adversarial vector corpus
  - Seed-reproducible shrinking property proof for identity, FIFO, dependencies, and revisions
affects: [desktop-offline-store, ios-offline-store, server-sync-feed, compatibility]

actuals:
  tokens: 12961
  tasks: 3
  commits: 6

tech-stack:
  added: [stream_data 1.4.0 test-only]
  patterns: [string-keyed storage-neutral reducer, conflict-domain FIFO lanes, durable dependency journal, schema-bound golden vectors]

key-files:
  created:
    - apps/server/lib/keepling/application/sync/reference_model.ex
    - apps/server/test/keepling/application/sync/reference_model_test.exs
    - apps/server/test/support/sync_scenario.ex
    - packages/contracts/schemas/sync-state-machine.schema.json
    - packages/contracts/vectors/sync.json
  modified:
    - apps/server/mix.exs
    - apps/server/mix.lock
    - tooling/check-contracts.mjs

key-decisions:
  - "Reference synchronization state uses closed JSON-compatible string-keyed maps so later clients share behavior without sharing persistence records."
  - "Ready pushes are bounded to 25 and pulls to 50 changes; overlapping resource keys preserve FIFO while disjoint lanes progress."
  - "Only accepted and already_satisfied journal outcomes satisfy durable dependencies."
  - "Immutable command bytes must contain the same mutation identity as the durable envelope and match its SHA-256 fingerprint."

patterns-established:
  - "Local acceptance: optimistic projection, immutable command bytes/fingerprint, journal, dependencies, and outbox change in one returned durable state."
  - "Exact settlement: acknowledgement identity and fingerprint both match before the outbox entry is removed."
  - "Contract anti-vacuity: schema-bound vectors require unique names, closed actions/outcomes, fixed clocks/identities, and a positive executed-case count."

requirements-completed: [SRV-04, SRV-05]

coverage:
  - id: D1
    description: "A durable local mutation survives pending pulls and settles only from an exact identity-and-fingerprint acknowledgement."
    requirement: SRV-04
    verification:
      - kind: unit
        ref: "apps/server/test/keepling/application/sync/reference_model_test.exs#tracer tests"
        status: pass
    human_judgment: false
  - id: D2
    description: "Overlapping lanes, durable dependencies, relaunch, response loss, and authentication fencing progress deterministically."
    requirement: SRV-05
    verification:
      - kind: unit
        ref: "apps/server/test/keepling/application/sync/reference_model_test.exs#scenario tests"
        status: pass
      - kind: other
        ref: "packages/contracts/vectors/sync.json#4 executed cases"
        status: pass
    human_judgment: false
  - id: D3
    description: "The closed vector and shrinking property harness is non-vacuous and rejects malformed actions and outcomes."
    requirement: SRV-04
    verification:
      - kind: other
        ref: "pnpm contracts:check"
        status: pass
      - kind: unit
        ref: "reference_model_test.exs#generated action sequences preserve identity, FIFO, dependencies, and revisions"
        status: pass
    human_judgment: false
  - id: D4
    description: "Flagged assumption: these closed vectors are the Phase 2 interpretation of the still-unclassified SRV-04/SRV-05 prose."
    requirement: SRV-04
    verification:
      - kind: other
        ref: ".planning/phases/KPL-02-synchronization-and-replaceable-server/02-01-PLAN.md#must_haves"
        status: unknown
    human_judgment: true
    rationale: "The plan explicitly requires verifier review of this interpretation against the requirement prose."

duration: 17min
completed: 2026-09-01
status: complete
---

# Phase KPL-02 Plan 01: Synchronization Reference Model Summary

**A storage-neutral offline reducer now proves exact local durability, FIFO lane scheduling, dependency blocking, pending-pull replay, and exact acknowledgement settlement with closed vectors and shrinking properties.**

## Performance

- **Duration:** 17 min
- **Started:** 2026-09-01T05:37:29Z
- **Completed:** 2026-09-01T05:53:34Z
- **Tasks:** 3
- **Files modified:** 8 implementation and proof files

## Accomplishments

- Implemented the D-01 through D-06 pure reference reducer with separate canonical shadow, visible projection, journal, dependency graph, and outbox values.
- Proved exact fingerprint/identity settlement, unrelated-lane progress, failed-dependency blocking, bounded pull/push scheduling, relaunch, and authentication fencing.
- Added four fixed-clock storage-neutral vectors plus a closed schema/contract gate that rejects malformed fixtures and reports the executed count.
- Pinned test-only StreamData 1.4.0 and added reproducible, shrinking long-sequence invariant checks.

## Task Commits

Each TDD task was committed as a RED test followed by its GREEN implementation:

1. **Task 1 RED: failing durable sync tracer** - `43891d9` (test)
2. **Task 1 GREEN: exact tracer reducer** - `937730d` (feat)
3. **Task 2 RED: failing lane and recovery scenarios** - `cf44b09` (test)
4. **Task 2 GREEN: FIFO and dependency progression** - `754bd00` (feat)
5. **Task 3 RED: failing generated properties** - `ac62a9f` (test)
6. **Task 3 GREEN: shrinking contract proof** - `0705252` (feat)

## Files Created/Modified

- `apps/server/lib/keepling/application/sync/reference_model.ex` - Pure synchronization state reducer and scheduler.
- `apps/server/test/keepling/application/sync/reference_model_test.exs` - Tracer, adversarial, and generated property coverage.
- `apps/server/test/support/sync_scenario.ex` - JSON-vector runner shared by deterministic scenarios.
- `packages/contracts/schemas/sync-state-machine.schema.json` - Closed Draft 2020-12 state-machine contract.
- `packages/contracts/vectors/sync.json` - Fixed-clock cross-runtime synchronization scenarios.
- `tooling/check-contracts.mjs` - Schema-bound anti-vacuity and malformed-fixture checks.
- `apps/server/mix.exs` and `apps/server/mix.lock` - Exact test-only StreamData dependency.

## Decisions Made

- Kept the reference model independent of Phoenix, Ecto, generated DTOs, and client persistence by using JSON-compatible maps only.
- Made resource-key overlap and explicit durable dependencies the only scheduling authorities; no account-wide stop or semantic DAG optimizer was introduced.
- Kept acknowledgement freshness separate from pull coverage: settlement never advances the saved cursor.
- Used the current ExUnit seed through StreamData so failures reproduce with the emitted seed and shrink to a smaller action sequence.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected an invalid Elixir string-literal typespec**
- **Found during:** Task 1 GREEN compilation
- **Issue:** Elixir rejected a literal `"local_saved"` return type in the function spec.
- **Fix:** Used `String.t()` while retaining the closed runtime return value.
- **Files modified:** `apps/server/lib/keepling/application/sync/reference_model.ex`
- **Verification:** Focused tracer compilation and tests passed.
- **Committed in:** `937730d`

**2. [Rule 2 - Missing critical functionality] Bound durable command bytes to mutation identity**
- **Found during:** Task 2 threat-mitigation review
- **Issue:** A matching fingerprint alone did not prove that serialized command bytes carried the same mutation identity as the durable envelope.
- **Fix:** Decode the closed command bytes at local acceptance and require the embedded identity to equal the outer mutation identity.
- **Files modified:** `apps/server/lib/keepling/application/sync/reference_model.ex`, `packages/contracts/vectors/sync.json`, `tooling/check-contracts.mjs`
- **Verification:** Scenario, property, and contract gates all passed.
- **Committed in:** `754bd00`, `0705252`

---

**Total deviations:** 2 auto-fixed (1 Rule 1, 1 Rule 2)
**Impact on plan:** Both changes were required for compilation or the declared untrusted-command trust boundary; no architectural scope changed.

## Issues Encountered

- Disposable PostgreSQL initially used a macOS temporary socket path longer than PostgreSQL's Unix-socket limit. Subsequent verification used a short explicit `/tmp/kpl0201.*` root.
- Hex reported an expired optional authentication session but fetched the public, research-approved StreamData package successfully; no authentication gate blocked execution.
- Dependency resolution surfaced pre-existing `hackney 1.25.0` advisories. They are recorded in `deferred-items.md`; the unrelated dependency path was not changed in this plan.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Server-feed and client-store plans can implement against one executable D-01 through D-06 truth without importing this reducer's in-memory representation.
- Phase verification must review the plan's explicitly flagged SRV-04/SRV-05 interpretation against the requirement prose.
- The pre-existing Hackney advisory remains a separate dependency-review item.

---
*Phase: KPL-02-synchronization-and-replaceable-server*
*Completed: 2026-09-01*

## Self-Check: PASSED

- All five created implementation/proof artifacts and this summary exist on disk.
- All six RED/GREEN task commits are present in Git history.
