---
phase: KPL-04-native-iphone-daily-loop
plan: 15
subsystem: ios
tags: [swift, diagnostics, privacy, grdb, xctest]

requires:
  - phase: KPL-04-12
    provides: "IntentPrivacyTests' real-secret-round-trip discipline (assert against the run's own actual values, never a pattern) -- this plan extends the same discipline to the diagnostic log"
  - phase: KPL-04-10
    provides: "SyncPresentation/SyncCopy/AnnouncementDebouncer -- the authoritative presentation projection whose unrecoverable state's Inspect/Export recovery actions this plan's DiagnosticExport backs"
  - phase: KPL-04-08
    provides: "KeeplingApplication.runSyncPass and the three-state transmission machine (queued/in_flight/settled/uncertain) this plan instruments directly, and the refusal/settlement outcomes it names"
provides:
  - "DiagnosticEvent/DiagnosticLog: a closed, structurally-free-text-incapable diagnostic event type and a bounded (500-event) on-device ring, injectable for tests, defaulting to a process-wide DiagnosticLog.shared"
  - "KeeplingApplication.runSyncPass and GRDBLocalStore (bindNamespace/setSyncFence/init) now emit one diagnostic event per real transmission-state transition, settlement outcome, namespace fence, unrecoverable-store halt, and authentication-required stop"
  - "DiagnosticExport.bundle(from:): a single-parameter, store-path-incapable export producing exactly one file (the serialized log) -- the artifact the unrecoverable state's Export action hands over"
  - "DiagnosticCoverageTests/DiagnosticPrivacyTests (KeeplingCoreTests target): coverage derived from source types and driven through real production code, plus a full-exercise leak scan against the export bundle, the in-product Inspect presentation, accessibility announcements, and user-visible error copy"
  - "tooling/ios-lanes/privacy.mjs covering both new test classes in one xcodebuild invocation"
affects: [04-16, 04-17]

actuals:
  tokens: 16554
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "A privacy-critical type's freedom from free text is enforced by a source-text scan of the exact file (no `String`-typed stored property anywhere in DiagnosticEvent.swift), not by code review discipline -- the same technique this plan's own <verify> script uses, now also embedded in the type's own doc comment as a standing constraint on future edits."
    - "Diagnostic instrumentation lives at the SAME small set of call sites that already decide a transition (KeeplingApplication.runSyncPass's claim/settle/uncertain/auth branches; GRDBLocalStore's writeFence and init's migration catch) rather than a parallel notion of 'sensitive' re-derived elsewhere -- this plan's orchestrator note asked for exactly this reuse."
    - "An export function's 'cannot reach the store' guarantee lives in its own signature (DiagnosticLog as the ONLY parameter), mirroring LocalNamespaceDataRemoval.removeAll(from:)'s established technique for making server deletion unreachable from local-data removal."

key-files:
  created:
    - apps/ios/Sources/KeeplingCore/Diagnostics/DiagnosticEvent.swift
    - apps/ios/Sources/KeeplingCore/Diagnostics/DiagnosticLog.swift
    - apps/ios/Sources/KeeplingCore/Diagnostics/DiagnosticExport.swift
    - apps/ios/Tests/KeeplingCoreTests/DiagnosticCoverageTests.swift
    - apps/ios/Tests/KeeplingCoreTests/DiagnosticPrivacyTests.swift
    - tooling/ios-lanes/privacy.mjs
  modified:
    - apps/ios/Sources/KeeplingCore/Application/KeeplingApplication.swift
    - apps/ios/Sources/KeeplingCore/Storage/GRDBLocalStore.swift
    - apps/ios/Sources/KeeplingCore/Storage/LocalStorePort.swift

key-decisions:
  - "DiagnosticEvent's operation identity is a closed enum over UUID (DiagnosticOperationIdentity: .mutation(UUID) | .none), never a String -- a mutation's own identity in this codebase is always minted as UUID().uuidString, so nothing is lost by storing the parsed value, and this is what lets the whole file pass a literal zero-String-field scan."
  - "The diagnostic log's bound is 500 events, chosen and reasoned about in DiagnosticLog.swift's own doc comment (not only here): a bad day's worth of activity across one or a few sync passes is at most a few hundred transitions, and 500 small value-type events is a trivial, bounded footprint (T-04-15-06)."
  - "A settlement (in_flight -> settled) is ONE diagnostic event whose errorClass names the outcome (settled_accepted/settled_already_satisfied/settled_rejected/settled_stale/settled_conflict), not a separate event per outcome kind -- this satisfies both 'every transmission transition' and 'every settlement outcome, including the duplicate-replay no-op' as the same real call site (GRDBLocalStore.acknowledge succeeding), rather than inventing a second notion of the same fact."
  - "StoreUnrecoverable.integrityCheckFailed has no real production call site today (GRDBLocalStore.integrityCheckResults()/foreignKeyCheckViolations() return raw PRAGMA output with no caller converting a bad result into this case) -- a pre-existing gap this plan did not introduce and was not authorized to close. DiagnosticCoverageTests proves the MAPPING function's exhaustive coverage of this case directly rather than silently presenting it as an end-to-end production drive; disclosed here and in the test's own doc comment."
  - "migrationMidApplyFailure cannot be forced through the real GRDBLocalStore.init (its own migration list is fixed, valid production SQL) -- driven instead at MigrationLedger.apply (the SAME function GRDBLocalStore.init calls) with a synthetic broken migration, then fed through the SAME GRDBLocalStore.errorClass(for:) mapping function production code uses. Disclosed as the one StoreUnrecoverable case this file cannot drive end-to-end through init itself."
  - "DiagnosticExport.bundle(from:) returns an in-memory DiagnosticExportBundle (filename -> Data), never writes to disk itself -- keeping the function's signature literally one parameter (the log) with no second parameter through which any other path could arrive; a future Export action writes the returned bytes to wherever it chooses."
  - "The 'system unified log' surface named in the plan's <behavior> is proven absent, not scanned per-value: a direct grep confirmed apps/ios/Sources contains zero os_log/Logger call sites, so DiagnosticPrivacyTests asserts that absence structurally and fails loudly the moment a future change adds one (at which point that call site must join the per-value leak scan)."

requirements-completed: [IOS-04, IOS-02]

coverage:
  - id: D1
    description: "DiagnosticEvent carries only an operation identity, a closed transition enum, a closed error-class enum, and a timestamp -- no String-typed stored property anywhere in the file"
    requirement: IOS-04
    verification:
      - kind: static
        ref: "node -e regex scan for `(let|var) x: String` over DiagnosticEvent.swift (this plan's own <verify> script) -- reproduced, output 'diagnostic event carries no free text'"
        status: pass
    human_judgment: false
  - id: D2
    description: "Every one of the three transmission transitions, every settlement outcome (including the duplicate-replay no-op), every namespace fence, every unrecoverable-store halt, and every authentication-required stop emits exactly one diagnostic event, driven through real production code and derived from source types rather than a hand-written list"
    requirement: IOS-04
    verification:
      - kind: unit
        ref: "Tests/KeeplingCoreTests/DiagnosticCoverageTests.swift (13 tests, all pass) -- lane: node tooling/verify-ios-phase.mjs --lane privacy"
        status: pass
    human_judgment: false
  - id: D3
    description: "The diagnostic log is an explicitly bounded ring (500 events), with the bound and its reasoning recorded"
    requirement: IOS-02
    verification:
      - kind: unit
        ref: "DiagnosticLog.defaultBound, tested indirectly via DiagnosticCoverageTests' bounded-capacity DiagnosticLog(bound:) instances; reasoning recorded in DiagnosticLog.swift's own doc comment and this SUMMARY's key-decisions"
        status: pass
    human_judgment: false
  - id: D4
    description: "DiagnosticExport.bundle(from:) takes the log as its only input, references no store path/durable-unit/SQLite type, and produces a bundle enumerated to contain exactly one file"
    requirement: IOS-04
    verification:
      - kind: static
        ref: "node -e regex scan for DurableUnit|storeURL|databasePath|sqlite over DiagnosticExport.swift (this plan's own <verify> script) -- reproduced, output 'export is log-only by construction'"
        status: pass
      - kind: unit
        ref: "Tests/KeeplingCoreTests/DiagnosticPrivacyTests.swift -- bundle.files.count == 1 and bundle.files.keys == [DiagnosticExport.logFileName]"
        status: pass
    human_judgment: false
  - id: D5
    description: "A full exercise (sign in, capture, edit, complete with a real undo handle, undo, a second task's conflict, a namespace fence, sign out, and an unrecoverable halt) using distinctive per-run values produces no leak of those exact values into the export bundle, the in-product Inspect presentation, accessibility announcements, or user-visible error copy"
    requirement: IOS-02
    verification:
      - kind: unit
        ref: "Tests/KeeplingCoreTests/DiagnosticPrivacyTests.swift#testFullExerciseLeaksNoActualTaskContentCredentialCursorFingerprintOrHandleToAnyDiagnosticAdjacentSurface"
        status: pass
    human_judgment: false
  - id: D6
    description: "The system unified log surface is covered by the same leak-scan discipline"
    verification:
      - kind: unit
        ref: "Tests/KeeplingCoreTests/DiagnosticPrivacyTests.swift#testNoProductionSourceUnderSourcesWritesToTheSystemUnifiedLog"
        status: pass
    human_judgment: true
    rationale: "This codebase writes nothing to the OS unified log anywhere under Sources today, so there is no per-value surface to scan -- the test proves that absence structurally rather than scanning real bytes. A human should confirm this remains the right substitute if/when a future plan adds real os_log/Logger usage (at which point it must join the per-value scan in D5's test, not merely pass this absence check)."

duration: 65min
completed: 2026-09-05
status: complete
---

# Phase KPL-04 Plan 15: On-Device Diagnostics — Reconstructable Without Being a Surveillance Record Summary

**A closed, structurally free-text-incapable `DiagnosticEvent`/`DiagnosticLog` pair records every real transmission-state transition, settlement outcome, namespace fence, unrecoverable halt, and authentication-required stop directly from `KeeplingApplication.runSyncPass` and `GRDBLocalStore`, and a single-parameter `DiagnosticExport` proves — against a full exercise using distinctive per-run values, never a pattern — that none of it, nor the accessory export bundle, ever carries a task title, note, credential, cursor, fingerprint, or undo handle.**

## Performance

- **Duration:** 65 min
- **Tasks:** 2 of 2 completed
- **Files created/modified:** 9 (6 created, 3 modified)

## Accomplishments

- `DiagnosticEvent.swift` declares an operation identity (`.mutation(UUID)` / `.none`), a closed `DiagnosticTransition` enum, a closed `DiagnosticErrorClass` enum, and a `Date` timestamp — no `String`-typed stored property anywhere in the file, verified by a literal source-text scan (this plan's own `<verify>` script).
- `DiagnosticLog.swift` is a bounded (500-event), thread-safe on-device ring, injectable for tests and defaulting to a process-wide `DiagnosticLog.shared` — the bound and its reasoning are recorded in the type's own doc comment.
- `KeeplingApplication.runSyncPass` now emits a real diagnostic event at every transition it already decides: `queued_to_in_flight` on a successful claim, `in_flight_to_settled` (naming the settlement outcome, including the duplicate-replay no-op) on a successful acknowledge, `in_flight_to_uncertain` on a transport failure or unclassified refusal, and `authentication_required` on both the pull-side and push-side auth stop.
- `GRDBLocalStore` emits `namespace_fence` on a real `bindNamespace` mismatch and on `SignOutCoordinator`'s sign-out fence (both routed through the one `writeFence` write path), and `unrecoverable_halt` when `init` catches a real `StoreUnrecoverable` thrown during migration.
- `DiagnosticCoverageTests` (13 tests) derives coverage from source types — `DiagnosticTransition.allCases` and the now-`CaseIterable` `SyncAcknowledgement.Outcome` — and drives each through real production code, including two `StoreUnrecoverable` cases (`checksumDrift`, `aheadOfLedger`) via a genuine corrupted-store reopen.
- `DiagnosticExport.bundle(from:)` takes a `DiagnosticLog` as its only parameter and returns an in-memory bundle containing exactly one file (`diagnostic-log.json`) — structurally incapable of referencing a store path, durable unit, or SQLite type, verified by the plan's own source-text scan.
- `DiagnosticPrivacyTests` (2 tests) drives a full exercise — sign in, capture, edit, complete (with a real server-issued undo handle), undo, a second task's conflict, a namespace fence, sign out, and an unrecoverable halt, all with distinctive per-run random values — then scans the export bundle, the in-product Inspect presentation, accessibility announcements (`AnnouncementDebouncer`), and every user-visible error/copy string for those exact values, and proves structurally that this codebase writes nothing to the OS unified log anywhere under `Sources`.
- `tooling/ios-lanes/privacy.mjs` runs both new test classes (15 tests total) in one `xcodebuild` invocation; `node tooling/verify-ios-phase.mjs --lane privacy` PASSes.
- Regression-checked against `sync-pass`, `app-intents`, `durability-posture`, `auth`, `storage-gates`, `lifecycle`, and `core-loop` (all pass) since this plan touched `KeeplingApplication.swift`, `GRDBLocalStore.swift`, and `LocalStorePort.swift` — files those lanes also exercise.

## Task Commits

1. **Task 1: A closed diagnostic event vocabulary with proven transition coverage** — `c2020b1` (feat)
2. **Task 2: Export for the Inspect and Export recovery actions, and a leak scan against real values** — `b6eb077` (feat)

## Files Created/Modified

- `apps/ios/Sources/KeeplingCore/Diagnostics/DiagnosticEvent.swift` — the closed, free-text-incapable event type
- `apps/ios/Sources/KeeplingCore/Diagnostics/DiagnosticLog.swift` — the bounded on-device ring
- `apps/ios/Sources/KeeplingCore/Diagnostics/DiagnosticExport.swift` — the log-only export bundle producer
- `apps/ios/Sources/KeeplingCore/Application/KeeplingApplication.swift` — real transition/settlement/auth instrumentation
- `apps/ios/Sources/KeeplingCore/Storage/GRDBLocalStore.swift` — real fence/unrecoverable-halt instrumentation, `errorClass(for:)`/`errorClass(forFenceReason:)` mappings
- `apps/ios/Sources/KeeplingCore/Storage/LocalStorePort.swift` — `SyncAcknowledgement.Outcome` gained `CaseIterable`
- `apps/ios/Tests/KeeplingCoreTests/DiagnosticCoverageTests.swift`, `DiagnosticPrivacyTests.swift` — the new test suite (15 tests)
- `tooling/ios-lanes/privacy.mjs` — the new lane

## Scanned Surfaces (Task 2's required disclosure)

Per the plan's own instruction to "record in the SUMMARY the exact list of surfaces scanned":

1. **Export bundle** — `DiagnosticExport.bundle(from:)`'s own file contents.
2. **In-product Inspect presentation** — the same events rendered through only `DiagnosticEvent`'s closed fields (transition, error class, timestamp) — proven structurally incapable of user content by `DiagnosticEvent`'s own type, not merely by today's absence of a renderer.
3. **Accessibility announcement strings** — `AnnouncementDebouncer` fed a representative transition sequence (`.localAcceptance`, `.conflict`, `.unrecoverable`).
4. **User-visible error/copy messages** — `GRDBLocalStore.StoreError`, `CompensatingCommands.UndoRefusalReason.copy`, and `SyncCopy`'s unrecoverable/rejected/conflict strings.
5. **The OS unified system log** — proven structurally absent as a surface (no `os_log`/`Logger` call site anywhere under `apps/ios/Sources`), rather than scanned per-value; see the disclosed `human_judgment` coverage entry above.

Scanned against the run's own actual values: capture title, edit notes, draft title, second-task title, access credential, refresh credential, sync cursor, server-issued undo handle, and two mutation fingerprints.

## Decisions Made

See `key-decisions` frontmatter above. Most consequential: instrumentation lives at the same call sites that already decide a transition (no parallel "sensitive" concept invented), and `integrityCheckFailed`/`migrationMidApplyFailure` are disclosed as the two `StoreUnrecoverable` cases this file cannot drive fully end-to-end through the real `GRDBLocalStore.init` (a pre-existing gap and a fixed-migration-list constraint respectively, neither introduced nor closeable by this plan's authorized scope).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] `KeeplingApplication`/`GRDBLocalStore` needed a `diagnostics: DiagnosticLog` parameter to emit anything real**
- **Found during:** Task 1, while designing how a diagnostic event could be produced by a REAL transition rather than only by a hand-written test fixture
- **Issue:** The plan's own `files_modified` list names only `Diagnostics/*` and the two new test files — but `DiagnosticCoverageTests`' own acceptance criterion ("drive each one" through the transitions) is unsatisfiable without instrumenting the actual decision points, and doing so without touching `KeeplingApplication.swift`/`GRDBLocalStore.swift` would make the whole coverage claim fictional (events existing only in test fixtures, never in the real sync pass or fence path)
- **Fix:** Added an optional `diagnostics: DiagnosticLog = .shared` parameter to both types' initializers (default preserves every existing call site's signature with zero behavior change), and recorded one event at each real decision point those types already make
- **Files modified:** `KeeplingApplication.swift`, `GRDBLocalStore.swift`
- **Verification:** `DiagnosticCoverageTests` (13 tests) and `DiagnosticPrivacyTests` (2 tests) all pass; regression lanes `sync-pass`, `app-intents`, `durability-posture`, `auth`, `storage-gates`, `lifecycle`, `core-loop` all pass with zero regressions
- **Committed in:** `c2020b1` (Task 1 commit)

**2. [Rule 2 - Missing critical functionality] `SyncAcknowledgement.Outcome` needed `CaseIterable` for coverage to be genuinely source-derived**
- **Found during:** Task 1, writing `DiagnosticCoverageTests`
- **Issue:** The plan requires deriving the settlement-outcome set "from the source types at test time" rather than a hand-written list; `SyncAcknowledgement.Outcome` (the real, existing settlement-outcome type) lacked `CaseIterable`
- **Fix:** Added `CaseIterable` conformance — a trivial, behavior-preserving addition
- **Files modified:** `LocalStorePort.swift`
- **Verification:** `DiagnosticCoverageTests.testInFlightToSettledEmitsExactlyOneEventNamingEachSettlementOutcome` iterates `SyncAcknowledgement.Outcome.allCases`
- **Committed in:** `c2020b1` (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 2 — necessary for the plan's own stated coverage claim to be genuinely, not aspirationally, true). **Impact on plan:** Both were required for "every meaningful transition leaves a trace" to be a checkable claim against REAL production code rather than only against test fixtures. No scope creep beyond what the plan's own acceptance criteria demanded.

## Issues Encountered

None beyond the deviations documented above.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- The diagnostic vocabulary, log, export, and privacy discipline are complete and independently tested (15 tests across two classes, all passing), ready for a future plan to wire `DiagnosticExport`/the Inspect presentation into an actual SwiftUI surface behind the unrecoverable state's Inspect/Export buttons (not built by this plan — `SyncPresentation.swift`'s recovery-action labels already exist from 04-10; this plan supplies the data source they will read from).
- `StoreUnrecoverable.integrityCheckFailed` still has no real production call site (`GRDBLocalStore.integrityCheckResults()`/`foreignKeyCheckViolations()` return raw results with no caller converting them into a thrown halt) — a pre-existing gap, disclosed again here, not this plan's authorized scope to close.
- No blockers.

## Known Stubs

None. Both `DiagnosticExport` and the instrumentation are production-correct, not placeholders — proven through 15 passing tests including a real end-to-end leak scan.

## Threat Flags

None new. This plan's own `<threat_model>` register (T-04-15-01 through T-04-15-07) is fully mitigated or explicitly transferred:
- T-04-15-01/02 (task content/credential leak into diagnostics) — mitigated by `DiagnosticEvent`'s structural free-text incapability and `DiagnosticPrivacyTests`' real-value scan.
- T-04-15-03 (export bundle carrying the store) — mitigated by `DiagnosticExport`'s single-parameter signature and source-text scan.
- T-04-15-04 (spoken announcement leak) — mitigated; announcements are included in the leak scan.
- T-04-15-05 (a silent transition) — mitigated by `DiagnosticCoverageTests`' source-derived coverage.
- T-04-15-06 (unbounded log growth) — mitigated by the explicit 500-event bound.
- T-04-15-07 (generic PII/retention policy) — unchanged; transferred to `/gsd-secure-phase` per the plan's own disposition.

## Self-Check: PASSED

- `[ -f apps/ios/Sources/KeeplingCore/Diagnostics/DiagnosticEvent.swift ]` — FOUND
- `[ -f apps/ios/Sources/KeeplingCore/Diagnostics/DiagnosticLog.swift ]` — FOUND
- `[ -f apps/ios/Sources/KeeplingCore/Diagnostics/DiagnosticExport.swift ]` — FOUND
- `[ -f apps/ios/Tests/KeeplingCoreTests/DiagnosticCoverageTests.swift ]` — FOUND
- `[ -f apps/ios/Tests/KeeplingCoreTests/DiagnosticPrivacyTests.swift ]` — FOUND
- `[ -f tooling/ios-lanes/privacy.mjs ]` — FOUND
- `git log --oneline --all --grep="04-15"` returns 2 commits — FOUND (`c2020b1`, `b6eb077`)
- Re-ran plan-level `<verification>`:
  - `node tooling/verify-ios-phase.mjs --lane privacy` — PASS (cases=13 reported by the parser's first-match convention; 15/15 tests across both classes independently confirmed passing via direct `xcodebuild test`)
  - `node -e` free-text scan over `DiagnosticEvent.swift` — PASS, reproduced in this session
  - `node -e` log-only-by-construction scan over `DiagnosticExport.swift` — PASS, reproduced in this session
  - Export bundle enumeration (`bundle.files.count == 1`) — PASS, asserted directly in `DiagnosticPrivacyTests`
  - Regression check against `sync-pass`, `app-intents`, `durability-posture`, `auth`, `storage-gates`, `lifecycle`, and `core-loop` lanes — all PASS, zero regressions from the `KeeplingApplication.swift`/`GRDBLocalStore.swift`/`LocalStorePort.swift` changes

---
*Phase: KPL-04-native-iphone-daily-loop*
*Plan: 15*
*Completed: 2026-09-05*
