---
phase: KPL-02-synchronization-and-replaceable-server
plan: 10
subsystem: testing
tags: [github-actions, ci, recovery, privacy, opentofu, docker, postgres]

requires:
  - phase: KPL-02-synchronization-and-replaceable-server
    plans: [03, 04, 05, 06, 07, 08, 11]
    provides: synchronization, compatibility, operations, deployment, restore, and privacy contracts
  - phase: KPL-02-synchronization-and-replaceable-server
    plan: 09
    provides: hermetic archive, bootstrap, ownership, teardown, and DNS-fence regressions without a completion claim
provides:
  - Non-vacuous timed and seeded Phase 2 local lane runner with exact input digests
  - Full-SHA-pinned parallel required CI with exact lock/runtime cache keys
  - Protected daily, weekly, and quarterly recovery workflow with bounded evidence
  - Aggregate hostile-sentinel scanning across every retained diagnostic surface
affects: [phase-2-verification, release-evidence, recovery-drills, host-replacement]

actuals:
  tokens: 8991
  tasks: 2
  commits: 3

tech-stack:
  added: []
  patterns: [committed lane commands, anti-vacuity counts, bounded timing evidence, explicit non-passing outer acceptance]

key-files:
  created:
    - tooling/test-phase-2.sh
    - tooling/check-ci-contract.mjs
    - tooling/verify-privacy.sh
    - .github/workflows/recovery-drills.yml
    - apps/server/test/keepling/ops_redaction_test.exs
  modified:
    - .github/workflows/repository-integrity.yml

key-decisions:
  - "Required CI calls the same committed Phase 2 lane commands as local verification and retains only privacy-scanned timing metadata."
  - "Plan 02-09's provider/DNS outer acceptance remains NON_PASSING; a scheduled reminder or missing credential never becomes green evidence."
  - "SEED-003 live-boundary failures run as eight hermetic CI fixtures before any rare, protected, change-triggered single live attempt."

patterns-established:
  - "Lane evidence: name, exact command, positive case count, deterministic seed, elapsed time, and digest of exact tracked inputs."
  - "Recovery evidence: protected credentials fail closed, artifacts use a bounded allow-listed schema, and deferred live gates exit nonzero."

requirements-completed: [QUAL-02, QUAL-05, SRV-04, SRV-05, SRV-06, DATA-02, OPS-01, OPS-03, OPS-04, OPS-05]
requirements-preserved-partial: [DATA-03, OPS-02]

coverage:
  - id: D1
    description: "Every local Phase 2 boundary runs through a named non-vacuous lane, while required CI fans out the same commands with pinned actions, exact cache inputs, timings, seeds, and flake ownership policy."
    requirement: QUAL-02
    verification:
      - kind: integration
        ref: "./tooling/test-phase-2.sh --run#8 executable lanes passed with positive counts; live acceptance NON_PASSING"
        status: pass
      - kind: other
        ref: "./tooling/check-ci-contract.mjs#9 lanes, full-SHA pins, exact caches, scheduled contract"
        status: pass
    human_judgment: false
  - id: D2
    description: "Producer tests and aggregate scanning reject hostile task content, credentials, provider errors, cursors, and arbitrary identifiers across ten diagnostic artifact surfaces."
    requirement: QUAL-05
    verification:
      - kind: unit
        ref: "apps/server/test/keepling/telemetry_redaction_test.exs and ops_redaction_test.exs#7 tests passed"
        status: pass
      - kind: integration
        ref: "./tooling/verify-privacy.sh --self-test#10 clean/hostile surfaces"
        status: pass
    human_judgment: false
  - id: D3
    description: "The corrected integrated restore/runtime plus authoritative and recursive DNS cutover/rollback acceptance remains deferred and explicitly non-passing."
    requirement: DATA-03
    verification:
      - kind: manual_procedural
        ref: ".planning/phases/KPL-02-synchronization-and-replaceable-server/deferred-items.md#Plan 02-09 live acceptance deferral"
        status: unknown
    human_judgment: true
    rationale: "The credentialed provider/DNS outer boundary was deliberately not run; Plan 02-09 remains incomplete until fresh evidence exists."

duration: 18min
completed: 2026-09-01
status: complete
---

# Phase KPL-02 Plan 10: Required CI and Recovery Evidence Summary

**Pinned parallel CI now executes the same non-vacuous Phase 2 lanes as local verification, scans bounded evidence for privacy leaks, and keeps deferred live host/DNS acceptance explicitly non-passing.**

## Performance

- **Duration:** 18 min
- **Started:** 2026-09-02T02:57:18Z
- **Completed:** 2026-09-02T03:15:03Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Added a nine-lane Phase 2 contract: eight executable local lanes report positive counts, exact commands, seeds, timings, and tracked-input digests; the credentialed host/DNS lane reports `NON_PASSING` and exits nonzero when selected.
- Added full-SHA-pinned parallel required CI with exact runtime/lock cache keys, privacy-scanned bounded timing artifacts, and no blind retry or ignored-failure path.
- Added protected daily logical/latest-WAL, weekly seeded historical PITR, and quarterly outer-acceptance reminder jobs that fail closed on missing credentials and never turn Plan 02-09's deferral into success.
- Converted SEED-003 into eight required hermetic provider/bootstrap/archive/engine/teardown/DNS-fence fixtures, keeping rare live work outside ordinary PR CI and the debugging loop.

## Task Commits

1. **Task 1 RED: failing Phase 2 CI contract** - `5d2196b` (test)
2. **Task 1 GREEN: non-vacuous local and privacy evidence** - `3776ffe` (feat)
3. **Task 2: required and scheduled workflow fan-out** - `231a1a5` (feat)

## Files Created/Modified

- `tooling/test-phase-2.sh` - Consolidated list, full run, per-lane CI entry points, metadata, anti-vacuity, and explicit deferred marker.
- `tooling/check-ci-contract.mjs` - Lane, fan-out, cache, pin, cadence, artifact, retry, credential, and deferral contract.
- `tooling/verify-privacy.sh` - Recursive hostile-sentinel scanner with ten-surface clean/hostile self-test.
- `apps/server/test/keepling/ops_redaction_test.exs` - Closed operator-envelope reflection and scanner-surface proof.
- `.github/workflows/repository-integrity.yml` - Parallel required lane jobs using committed commands and bounded timing artifacts.
- `.github/workflows/recovery-drills.yml` - Protected recovery cadence with fail-closed credentials and non-passing outer acceptance.

## Decisions Made

- Required workflows invoke `test-phase-2.sh --lane` so local and CI semantics cannot drift into separately maintained command lists.
- The quarterly host-replacement job is an accountable protected reminder, not a false green rehearsal: it writes bounded `NON_PASSING` evidence and exits 1 until a reviewed change trigger and fresh Plan 02-09 outer acceptance exist.
- Every new provider/bootstrap/image/restore/DNS failure class must first become a hermetic fixture; live attempts remain single-shot, change-triggered, teardown-proven, and unreachable from ordinary PR CI.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected the synchronization lane's tracked vector input**
- **Found during:** Task 2 full Phase 2 verification
- **Issue:** The new digest manifest referenced nonexistent `sync-state-machine.json`, so the full runner failed before the seeded sync lane could start.
- **Fix:** Bound the lane to the existing canonical `packages/contracts/vectors/sync.json` artifact.
- **Files modified:** `tooling/test-phase-2.sh`
- **Verification:** The restarted full runner passed 20 sync/property cases and every remaining local lane.
- **Committed in:** `231a1a5`

---

**Total deviations:** 1 auto-fixed (1 Rule 1)
**Impact on plan:** The fix corrected evidence identity without changing lane semantics or scope.

## Issues Encountered

- The sandbox blocked the first disposable PostgreSQL shared-memory/socket attempt. The same focused suite ran with the approved local test permission and passed 7 tests; this was an execution-environment restriction, not a product failure.

## Deferred Acceptance

- Plan 02-09 remains incomplete and has no summary.
- DATA-03 and OPS-02 remain unchecked/partial. No state or requirement update in this plan may complete them.
- The corrected restore/runtime semantic chain followed by authoritative and recursive DNS cutover, propagation, rollback, and rollback propagation remains unproven.
- Scheduled, skipped, missing-credential, hermetic, or deferred outcomes are not counted as passing outer-boundary evidence.

## Known Stubs

None. The explicit `NON_PASSING` host/DNS lane is a deliberate acceptance gate tied to Plan 02-09, not a passing implementation stub.

## User Setup Required

GitHub environments `recovery-protected` and `recovery-live` must be configured before scheduled credentialed drills can run. Missing protected credentials intentionally fail and retain only a bounded non-passing marker.

## Next Phase Readiness

- QUAL-02 and QUAL-05 have fresh executable local and workflow-contract evidence.
- Phase 2 cannot complete verification while Plan 02-09 remains incomplete; DATA-03 and OPS-02 retain their partial status.
- A future reviewed provider/bootstrap/recovery/DNS change may authorize exactly one protected outer attempt after all hermetic lanes are green.

---
*Phase: KPL-02-synchronization-and-replaceable-server*
*Completed: 2026-09-01*

## Self-Check: PASSED

- Summary exists at the canonical Plan 02-10 path.
- Task commits `5d2196b`, `3776ffe`, and `231a1a5` exist in repository history.
- Plan 02-09 remains incomplete with no summary; DATA-03 and OPS-02 remain explicitly partial.
