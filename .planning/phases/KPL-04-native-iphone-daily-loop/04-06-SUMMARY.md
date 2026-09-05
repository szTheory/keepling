---
phase: KPL-04-native-iphone-daily-loop
plan: 06
subsystem: ios
tags: [swift, grdb, sqlite, durability, backup, data-protection, settlement]

requires:
  - phase: KPL-04
    provides: "04-01's tracer GRDBLocalStore/acknowledge, 04-02's migration ledger and transaction-hook proof technique, 04-05's ServerRefusal/WireMappers refusal classification this plan's settlement consumes"
provides:
  - "GRDBLocalStore.acknowledge generalized to the full settlement surface (D-04 G8): identity + fingerprint verification, canonical/conflict application, projection recompute, journal terminalization, and exact outbox-row deletion in one transaction, with duplicate replay proven a no-op"
  - "DurableUnit: the db/-wal/-shm treated as one value with all-or-none move/copy/delete and backup exclusion"
  - "The real bindNamespace/setSyncFence D-03 fencing trigger (mirrors desktop), closing the gap 04-02's __test_setFence comment left open for this plan"
  - "BackupReplayTests: the D-09 adversarial fixture proving a hand-restored store cannot double-apply an accepted command or cross an account namespace fence"
  - "DataProtectionTests: G7's simulator-provable half (protection class), with the device-only half (locked-device write) honestly disclosed as a named skip"
  - "durability-posture lane and docs/testing/ios-testing.md disclosures"
affects: [04-16]

actuals:
  tokens: 18500
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "DurableUnit's transferAllOrNone: stage each existing member's copy/move, roll back every already-completed member on the first failure (move rolls back by moving back to source, not merely deleting the destination, so a rolled-back move never loses data)"
    - "SyncNamespace bindNamespace: compare-and-fence against a durably stored 'sync_namespace' key, mirroring desktop's bindNamespace exactly -- the real D-03 fencing trigger, not a test-only seam"
    - "URL.resourceValues(forKeys: [.fileProtectionKey]) as the reliable protection-class readback on iOS Simulator, where FileManager.attributesOfItem's .protectionKey reads back nil even after a successful set -- empirically confirmed this session, disclosed in docs/testing/ios-testing.md"

key-files:
  created:
    - apps/ios/Sources/KeeplingCore/Storage/DurableUnit.swift
    - apps/ios/Tests/StorageTests/SettlementTests.swift
    - apps/ios/Tests/StorageTests/DurableUnitTests.swift
    - apps/ios/Tests/StorageTests/BackupReplayTests.swift
    - apps/ios/Tests/StorageTests/DataProtectionTests.swift
    - tooling/ios-lanes/durability-posture.mjs
  modified:
    - apps/ios/Sources/KeeplingCore/Storage/GRDBLocalStore.swift
    - apps/ios/Sources/KeeplingCore/Storage/LocalStorePort.swift
    - docs/testing/ios-testing.md

key-decisions:
  - "SyncAcknowledgement (LocalStorePort.swift) gained affectedFields and an undo handle as backward-compatible defaulted parameters, rather than being left in Task 2's file scope only -- both fields are structurally required for the conflict/undo behaviors Task 1's own <behavior> list names, and LocalStorePort.swift is the one place SyncAcknowledgement can live without Storage depending on Transport."
  - "A conflict settlement touches NEITHER canonical_shadow NOR visible_projection at all (mirrors desktop's acknowledge exactly) -- it only records a conflicts row restricted to the server-named affected fields. This is a stronger, simpler guarantee of 'never blanks an unaffected field' than partially applying affected fields into the projection would have been, and it matches the one real precedent (desktop) this plan's own <read_first> pointed at."
  - "bindNamespace/setSyncFence (the real D-03/D-09 fencing trigger 04-02's own __test_setFence doc comment named as this plan's job) landed in Task 1's commit alongside GRDBLocalStore's init/backup-exclusion wiring, because both share GRDBLocalStore.swift's init/fencing sections with Task 1's acknowledge() edits -- Task 2's own commit adds no further production code to that file, only its adversarial tests and docs. Disclosed as a task-boundary blur, not a scope-creep concern (both are literal Task 2 deliverables)."
  - "DataProtectionTests reads back the store file's protection class via URL.resourceValues(.fileProtectionKey), not FileManager.attributesOfItem's .protectionKey -- empirically, the latter reads back nil on the iOS Simulator even immediately after a successful setAttributes call, while the URLResourceValues accessor reads back the real value on the same file. This is a genuine, previously-undocumented iOS Simulator characteristic discovered during this plan's execution, not assumed from RESEARCH.md's aspirational code example."
  - "The backup-replay fixture snapshots the durable unit AFTER checkpoint-truncating the WAL into the main file, rather than mid-WAL -- a deterministic, self-contained fixture that sidesteps the WAL-mode byte-drift-on-open characteristic 04-02-SUMMARY.md already disclosed, rather than re-discovering the same landmine here."

requirements-completed: [IOS-02]

coverage:
  - id: D1
    description: "GRDBLocalStore.acknowledge verifies mutation identity and fingerprint, applies canonical/conflict state, terminalizes the journal, recomputes the visible projection's title, retains undo availability, and deletes the exact outbox row -- all inside one transaction, proven via the same afterNextTransaction hook acceptMutation already used"
    requirement: IOS-02
    verification:
      - kind: unit
        ref: "Tests/StorageTests/SettlementTests.swift (8 tests, all pass)"
        status: pass
      - kind: integration
        ref: "node tooling/verify-ios-phase.mjs --lane durability-posture (cases=3, positive)"
        status: pass
    human_judgment: false
  - id: D2
    description: "A fingerprint mismatch refuses and mutates zero rows across all eight settlement-relevant tables (full snapshot comparison); a replay of an already-terminal acknowledgement is a no-op success asserted the same way; an unknown mutation identity with no matching journal outcome throws a named error"
    requirement: IOS-02
    verification:
      - kind: unit
        ref: "Tests/StorageTests/SettlementTests.swift#testFingerprintMismatchRefusesAndMutatesNothing, #testUnknownOutboxButMatchingJournalOutcomeIsANoOpSuccess, #testUnknownMutationIdentityWithNoJournalEntryAtAllThrowsNamedError"
        status: pass
    human_judgment: false
  - id: D3
    description: "A conflict settlement records a conflicts row restricted to exactly the server-named affected fields and leaves a locally-edited, unaffected field byte-identical; a rejected settlement deletes the outbox row and applies zero canonical state"
    requirement: IOS-02
    verification:
      - kind: unit
        ref: "Tests/StorageTests/SettlementTests.swift#testConflictSettlementRecordsOnlyAffectedFieldsAndLeavesUntouchedFieldByteIdentical, #testRejectedSettlementDeletesOutboxAndAppliesNoCanonicalState"
        status: pass
    human_judgment: false
  - id: D4
    description: "DurableUnit's move/copy/delete each act on all three existing db/-wal/-shm members or roll back to leave none touched, proven by forcing a mid-operation failure on a named member; excludeFromBackup marks every existing member and is read back via isFullyExcludedFromBackup"
    requirement: IOS-02
    verification:
      - kind: unit
        ref: "Tests/StorageTests/DurableUnitTests.swift (5 tests, all pass)"
        status: pass
    human_judgment: false
  - id: D5
    description: "A store snapshotted while it still carries pending outbox rows, then restored over a live store that has since settled those same mutations normally, replays every restored outbox row as already_satisfied with zero duplicate visible_projection rows and canonical_shadow converging to exactly one row per task"
    requirement: IOS-02
    verification:
      - kind: unit
        ref: "Tests/StorageTests/BackupReplayTests.swift#testRestoredStoreReplaysEveryOutboxRowAsAlreadySatisfiedWithNoDuplicateOrCanonicalMutation"
        status: pass
    human_judgment: false
  - id: D6
    description: "The same backup restored under a different account namespace (via the real bindNamespace trigger) is fenced: bindNamespace returns false, records sync_fence='namespace_mismatch' durably, and every push attempt refuses before opening a transaction, both immediately and after a relaunch"
    requirement: IOS-02
    verification:
      - kind: unit
        ref: "Tests/StorageTests/BackupReplayTests.swift#testSameBackupRestoredUnderADifferentAccountNamespaceFencesEveryPush"
        status: pass
    human_judgment: false
  - id: D7
    description: "No file under apps/ios/Sources contains forSecurityApplicationGroupIdentifier, asserted by both a structural test and the plan's own git-ls-files verification command"
    requirement: IOS-02
    verification:
      - kind: unit
        ref: "Tests/StorageTests/BackupReplayTests.swift#testAppGroupContainerAPINeverAppearsUnderSources"
        status: pass
      - kind: other
        ref: "git ls-files -z 'apps/ios/Sources/*.swift' | xargs -0 grep -l forSecurityApplicationGroupIdentifier | wc -l -> 0"
        status: pass
    human_judgment: false
  - id: D8
    description: "The store file's requested protection class reads back as .completeUntilFirstUserAuthentication and explicitly not .complete; the durable unit reads back as fully excluded from backup"
    requirement: IOS-02
    verification:
      - kind: unit
        ref: "Tests/StorageTests/DataProtectionTests.swift#testStoreFileRequestsCompleteUntilFirstUserAuthenticationProtection, #testDurableUnitReportsFullyExcludedFromBackupOnceOpened"
        status: pass
    human_judgment: false
  - id: D9
    description: "The locked-device background-write half of G7 (no SQLITE_IOERR/0xdead10cc while locked) is disclosed as unobservable on the simulator, via a named XCTSkip rather than a false pass"
    requirement: IOS-02
    verification:
      - kind: manual_procedural
        ref: "Tests/StorageTests/DataProtectionTests.swift#testBackgroundWriteWhileLockedDoesNotTakeAnIOErrorOrTerminate (XCTSkip, named reason)"
        status: unknown
    human_judgment: true
    rationale: "This half of G7 can only be genuinely observed on a physical device with a passcode set and real lock-state control this session's tooling does not have. Plan 04-16's device lane is the one place it can be driven for real; a human/that plan must confirm this disclosure is an acceptable interim posture rather than a silently deferred gate."

duration: ~2h
completed: 2026-09-05
status: complete
---

# Phase KPL-04 Plan 6: Native iPhone Daily Loop -- Durability Gates Closeout Summary

**GRDBLocalStore.acknowledge generalized to the full terminal-settlement surface (identity + fingerprint verification, canonical/conflict application, projection recompute, journal terminalization, exact outbox delete, all in one transaction), a `DurableUnit` type treating db/-wal/-shm as one all-or-none value excluded from backup, the real `bindNamespace` account-fencing trigger, and a hand-restored-store adversarial fixture proving zero duplicate tasks and zero canonical divergence on replay.**

## Performance

- **Duration:** ~2 hours
- **Started:** 2026-09-05
- **Completed:** 2026-09-05
- **Tasks:** 2 of 2 completed (both `tdd="true"`)
- **Files created/modified:** 9

## Accomplishments

- Generalized `GRDBLocalStore.acknowledge` from the tracer's capture-only settlement to the full `<behavior>` surface mirroring desktop's `acknowledge` method line for line: identity + fingerprint lookup, canonical/undo application only on `accepted`/`already_satisfied`, a conflict row restricted to exactly the server-named affected fields (never touching `canonical_shadow`/`visible_projection` at all on conflict/rejection), journal terminalization, and exact outbox-row deletion -- all structurally proven as one transaction via the same `afterNextTransaction` hook `acceptMutation` already established.
- Extended `SyncAcknowledgement` (`LocalStorePort.swift`) with `affectedFields` and an `undo` handle, both backward-compatible defaults, so a conflict settlement and undo retention have somewhere to carry their data without `Storage` depending on `Transport`.
- Built `DurableUnit.swift`: the db/-wal/-shm treated as one value with all-or-none `move`/`copy`/`delete` (staged, with rollback that moves already-transferred members back rather than merely deleting a partial destination) and backup exclusion applied after migrations run.
- Added the real `bindNamespace`/`setSyncFence` D-03 fencing trigger `04-02-SUMMARY.md`'s own `__test_setFence` doc comment had explicitly deferred to this plan -- a restored store whose bound namespace disagrees with the account signing in now fences itself for writes, durably, rather than silently pushing a previous account's outbox.
- `BackupReplayTests.swift`: the D-09 adversarial fixture. A store snapshotted while carrying pending outbox rows, restored over a live store that had since settled those same mutations normally, replays every restored row as `already_satisfied` with **zero duplicate `visible_projection` rows** (task count unchanged across the restore) and **`canonical_shadow` converging to exactly 2 rows for 2 tasks** (zero divergent/duplicate canonical mutation). The same backup restored under a different account namespace is fenced -- `bindNamespace` returns `false`, records `sync_fence = 'namespace_mismatch'` durably, and every push attempt refuses before opening a transaction, confirmed both immediately and after a relaunch.
- `DataProtectionTests.swift` asserts the store file's requested protection class via `URL.resourceValues(.fileProtectionKey)` -- empirically discovered during this plan's execution that `FileManager.attributesOfItem`'s `.protectionKey` reads back `nil` on the iOS Simulator even immediately after a successful `setAttributes` call, while the `URLResourceValues` accessor reads back the real value on the identical file. The locked-device write half of G7 is disclosed as a named `XCTSkip`, not a false pass.
- Added the `durability-posture` lane; `node tooling/verify-ios-phase.mjs --lane durability-posture` passes with `cases=3`. Full `node tooling/verify-ios-phase.mjs` passes across all 10 lanes (two pre-existing UI-test lanes -- `accessory-probe`, `tracer-e2e` -- transiently failed only when run concurrently with another simulator process during this session; both pass cleanly in isolation and are unrelated to this plan's storage-only changes).

## Task Commits

1. **Task 1: Terminal settlement in one transaction, duplicate replay a no-op (G8)** -- `89a9f61` (test)
2. **Task 2: Durable unit, backup exclusion, restored-store replay fixture (G7, D-09)** -- `0e55222` (test)

_Note: both tasks carry `tdd="true"`. Each commit bundles its own test file(s) with the corresponding production changes in `GRDBLocalStore.swift`/`DurableUnit.swift`/`LocalStorePort.swift` -- tests were written and run against the pre-existing/incomplete implementation first (compile failures for the new `SyncAcknowledgement` fields and `DurableUnit` type; assertion failures against the tracer-era `acknowledge` for the settlement behaviors), driving the implementation to green in the same working session, consistent with every prior 04-* plan's disclosed TDD gate characteristic for this codebase (see TDD Gate Compliance below)._

## Files Created/Modified

- `apps/ios/Sources/KeeplingCore/Storage/GRDBLocalStore.swift` -- full settlement, backup exclusion via `DurableUnit`, `bindNamespace`/`setSyncFence`
- `apps/ios/Sources/KeeplingCore/Storage/LocalStorePort.swift` -- `SyncAcknowledgement.affectedFields`/`.undo`, `SyncNamespace`
- `apps/ios/Sources/KeeplingCore/Storage/DurableUnit.swift` -- the db/-wal/-shm all-or-none value type
- `apps/ios/Tests/StorageTests/SettlementTests.swift` -- 8 tests covering all 7 `<behavior>` cases plus the transaction-hook proof
- `apps/ios/Tests/StorageTests/DurableUnitTests.swift` -- 5 tests proving all-or-none move/copy/delete and backup exclusion
- `apps/ios/Tests/StorageTests/BackupReplayTests.swift` -- the D-09/D-07 adversarial fixture
- `apps/ios/Tests/StorageTests/DataProtectionTests.swift` -- G7 simulator/device split
- `tooling/ios-lanes/durability-posture.mjs` -- the new named lane
- `docs/testing/ios-testing.md` -- lane row, G7 simulator-vs-device disclosure, D-09 fixture disclosure

## Decisions Made

See `key-decisions` frontmatter above. Most consequential: a conflict settlement touches **neither** `canonical_shadow` **nor** `visible_projection` at all -- mirroring desktop's `acknowledge` exactly rather than attempting a partial field-level apply, which is both simpler and a strictly stronger "never blanks an unaffected field" guarantee.

## Deviations from Plan

### Auto-fixed / Disclosed Issues

**1. [Rule 3 - Blocking] `SyncAcknowledgement` needed `affectedFields`/`undo` fields not in Task 1's declared `<files>`**
- **Found during:** Task 1, before writing `SettlementTests.swift`
- **Issue:** Task 1's `<files>` names only `GRDBLocalStore.swift` and `SettlementTests.swift`, but the conflict and undo-retention `<behavior>` cases have nowhere to carry their data -- `SyncAcknowledgement` (declared in `LocalStorePort.swift`) had no `affectedFields` or `undo` field at all.
- **Fix:** Extended `SyncAcknowledgement` with both fields as backward-compatible defaulted parameters (`affectedFields: [String] = []`, `undo: UndoAvailabilityHandle? = nil`), so every existing call site (the tracer's own settlement tests) is unaffected.
- **Files modified:** `apps/ios/Sources/KeeplingCore/Storage/LocalStorePort.swift`
- **Verification:** Full `KeeplingCoreTests`/`StorageTests` suite green with zero regressions.
- **Committed in:** `89a9f61` (Task 1 commit)

**2. [Rule 3 - Blocking] The real D-03/D-09 fencing trigger (`bindNamespace`) did not exist**
- **Found during:** Task 2, before writing `BackupReplayTests.swift`'s different-namespace case
- **Issue:** `04-02-SUMMARY.md`'s own `GRDBLocalStore.__test_setFence` doc comment explicitly named this plan ("Plan 04-06's real fencing trigger") as the one that would add the production account-namespace comparison. Without it, "the same backup restored under a different account namespace is fenced" could only be simulated via the test-only seam, not proven as a real, reachable production code path.
- **Fix:** Added `bindNamespace(_:) -> Bool` and `setSyncFence(reason:)`, mirroring desktop's `bindNamespace` exactly: compares a namespace tuple against the durably stored `sync_namespace` value, fencing on mismatch.
- **Files modified:** `apps/ios/Sources/KeeplingCore/Storage/GRDBLocalStore.swift`, `apps/ios/Sources/KeeplingCore/Storage/LocalStorePort.swift` (new `SyncNamespace` type)
- **Verification:** `BackupReplayTests.swift#testSameBackupRestoredUnderADifferentAccountNamespaceFencesEveryPush` passes.
- **Committed in:** `89a9f61` (landed alongside Task 1's edits to the same file's init/fencing sections; Task 2's own commit adds no further production code to `GRDBLocalStore.swift`)

**3. [Rule 2 - Missing Critical] `acknowledge` recomputed only `sync_status`, not the projection's title**
- **Found during:** Task 1, while implementing the "recomputes the projection" behavior
- **Issue:** The tracer-era `acknowledge` only set `visible_projection.sync_status = 'synced'` on a successful outcome; it never updated `title` from the canonical snapshot, meaning an `already_satisfied` replay settling bytes accepted in an earlier process would not converge the visible title to what the server actually holds.
- **Fix:** Added `Self.stringField("title", inJSON:)` to pull the canonical title out of `snapshotJSON` and update `visible_projection.title` alongside `sync_status` when present, falling back to the sync-status-only update when absent (never throws on a missing field).
- **Files modified:** `apps/ios/Sources/KeeplingCore/Storage/GRDBLocalStore.swift`
- **Verification:** `SettlementTests.swift#testSuccessfulSettlementAppliesCanonicalTerminalizesRecomputesAndDeletesInOneTransaction`.
- **Committed in:** `89a9f61` (Task 1 commit)

**4. [Rule 1 - Bug] `DurableUnit.move`'s naive rollback would have deleted data, not preserved it**
- **Found during:** Task 2, while designing `DurableUnitTests.swift`'s forced-failure assertions
- **Issue:** A first-pass `transferAllOrNone` implementation rolled back every completed member the same way for both `copy` and `move` (deleting the destination). For `move`, that is wrong: the source is already gone by the time a later member fails, so "rolling back" by deleting the destination would lose the member's data entirely rather than restoring it.
- **Fix:** `transferAllOrNone` takes a separate `rollback` closure per operation -- `copy`'s rollback deletes the (redundant) destination copy; `move`'s rollback moves the already-transferred member back to its original source path.
- **Files modified:** `apps/ios/Sources/KeeplingCore/Storage/DurableUnit.swift`
- **Verification:** `DurableUnitTests.swift#testMoveActsOnAllThreeExistingMembersOrThrowsWithoutActingOnAny` asserts every member is back at the SOURCE path after a forced failure, not merely absent from the destination.
- **Committed in:** `89a9f61` (Task 1 commit, landed with `DurableUnit.swift`'s creation)

---

**Total deviations:** 4 (2 blocking additions the plan's own `<behavior>` text required, 1 missing-critical recompute fix, 1 bug in a first-pass rollback design caught before it shipped). **Impact on plan:** All four are load-bearing for the stated G8/G7/D-09 outcomes this plan exists to close -- no scope creep beyond what Task 1/2's own `<behavior>`/`<action>` text already committed to.

## TDD Gate Compliance

Both tasks carry `tdd="true"`. Per the plan's TDD execution model, each task should show a `test(...)` commit demonstrating a captured RED (failing) state before a `feat(...)` GREEN commit. **This plan's execution does not literally demonstrate that transition, and discloses it here rather than presenting a clean cycle:**

- Both commits (`89a9f61`, `0e55222`) are `test(04-06): ...` commits, each bundling both the new test file(s) AND the corresponding production changes, because `GRDBLocalStore.swift`'s settlement rewrite and `DurableUnit.swift`'s creation are structurally interdependent with the tests exercising them.
- Tests WERE run against pre-existing/incomplete implementation first during development (compile failures for the new `SyncAcknowledgement` fields, `DurableUnit` type, and `bindNamespace`; assertion failures against the tracer-era `acknowledge` for every new settlement behavior), but this RED state was not captured as its own git commit before the corresponding implementation.
- **Gate sequence found in git log:** `test(04-06)` -> `test(04-06)`. No `feat(04-06)` commit exists as a separate GREEN gate.

This mirrors every prior 04-* plan's own disclosed TDD gate gap for the identical underlying reason (test and implementation interdependent within one plan's file set, committed together after both were verified green).

## Known Stubs

None new in this plan. The device-only half of G7 (`testBackgroundWriteWhileLockedDoesNotTakeAnIOErrorOrTerminate`) is not a stub -- it is a disclosed, named `XCTSkip` pending Plan 04-16's physical-device lane (see `flagged_assumptions` in `04-06-PLAN.md` and the D9 coverage entry above), not silently passing or silently omitted.

## Threat Flags

None new. This plan's own `<threat_model>` register (T-04-06-01 through T-04-06-07) is fully mitigated by the work above; no additional security-relevant surface was introduced beyond what that register already names.

## Issues Encountered

- **Simulator UI-test flakiness under concurrency:** Two UI-test lanes (`accessory-probe`, `tracer-e2e`) transiently failed when this session ran two full `verify-ios-phase.mjs` invocations concurrently against the same simulator instance. Both pass cleanly and consistently when run in isolation or sequentially; neither lane touches any file this plan modified. Recorded here as an environmental characteristic of concurrent simulator test runs, not a defect in this plan's work.
- **`FileManager.attributesOfItem`'s `.protectionKey` reads back `nil` on iOS Simulator:** documented above and in `docs/testing/ios-testing.md` -- a genuine, previously-undisclosed simulator characteristic discovered while writing `DataProtectionTests.swift`, resolved by reading back via `URL.resourceValues(.fileProtectionKey)` instead.

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness

- D-04 gates G1 through G8 (except G7's device-only half, explicitly deferred to Plan 04-16) now each have a named, passing test that fails if the property is removed.
- D-09's belt-and-braces posture is proven end to end: backup exclusion (the brace, via `DurableUnit`) plus the replay-no-op/account-fence proof (the belt, via settlement + `bindNamespace`) both hold, and the adversarial fixture is the artifact that makes either posture safe regardless of which one a restore path bypasses.
- `bindNamespace`/`setSyncFence` are now real, callable production methods -- a future sign-out/account-switch flow (if planned) should call `setSyncFence` directly rather than reaching for the test-only `__test_setFence`, and a future sign-in flow should call `bindNamespace` with the real session's namespace tuple.
- **Blocker/concern for the next planner:** Plan 04-16's physical-device lane must implement `testBackgroundWriteWhileLockedDoesNotTakeAnIOErrorOrTerminate`'s real locked-device write assertion -- this plan's `XCTSkip` is an honest placeholder, not a completed proof, and G7 is not fully closed until that device-lane evidence exists.
- No caller in production code (only tests) yet calls `bindNamespace`/`acknowledge`'s new `affectedFields`/`undo` parameters with real wire-derived values -- wiring `KeeplingSyncAdapter`'s `ServerRefusal.conflict` case into a `SyncAcknowledgement` with real `affectedFields`, and wiring a real sign-in flow's namespace tuple into `bindNamespace`, remain for whichever plan builds the sync orchestrator loop (04-08 per 04-05-SUMMARY.md's own "Next Phase Readiness").

## Self-Check: PASSED

- `[ -f apps/ios/Sources/KeeplingCore/Storage/DurableUnit.swift ]` -- FOUND
- `[ -f apps/ios/Tests/StorageTests/SettlementTests.swift ]` -- FOUND
- `[ -f apps/ios/Tests/StorageTests/DurableUnitTests.swift ]` -- FOUND
- `[ -f apps/ios/Tests/StorageTests/BackupReplayTests.swift ]` -- FOUND
- `[ -f apps/ios/Tests/StorageTests/DataProtectionTests.swift ]` -- FOUND
- `[ -f tooling/ios-lanes/durability-posture.mjs ]` -- FOUND
- `git log --oneline --all --grep="04-06"` returns 2 commits -- FOUND (`89a9f61`, `0e55222`)
- Re-ran plan-level `<verification>`:
  - `node tooling/verify-ios-phase.mjs --lane durability-posture` -- PASS (cases=3, positive)
  - `git ls-files -z 'apps/ios/Sources/*.swift' | xargs -0 grep -l forSecurityApplicationGroupIdentifier | wc -l` -- `0` -- PASS
  - Full `node tooling/verify-ios-phase.mjs` (10 lanes) -- 8/10 PASS on the first concurrent run (`accessory-probe`, `tracer-e2e` transient UI flakes under simulator concurrency); both re-ran and passed cleanly in isolation; all storage-related lanes (`durability-posture`, `storage`, `storage-gates`, `core-unit`, `decode-roundtrip`, `transport`, `vector-conformance`, `design-tokens`) passed on every run
  - Full `xcodebuild test` across `StorageTests` (`SettlementTests` 8, `DurableUnitTests` 5, `BackupReplayTests` 3, `DataProtectionTests` 3, plus all pre-existing suites) -- PASS, zero regressions

---
*Phase: KPL-04-native-iphone-daily-loop*
*Plan: 06*
*Completed: 2026-09-05*
