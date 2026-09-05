---
phase: KPL-04-native-iphone-daily-loop
plan: 10
subsystem: ios
tags: [swiftui, presentation, accessibility, sync-recovery, tabviewbottomaccessory, xcuitest]

requires:
  - phase: KPL-04-05
    provides: "SyncReachability/ServerRefusal -- the unreachable-vs-refused classifier this plan's presentation input union is designed to be driven from"
  - phase: KPL-04-08
    provides: "KeeplingApplication.runSyncPass and SyncPassScheduler.activeGracePeriod, the shared grace-period constant this plan reads rather than redeclaring"
  - phase: KPL-04-09
    provides: "RootTabView, WorkspaceFacade, TaskRow/TodayView/InboxView, TaskDetailView/ConflictResolverSection -- the presentation boundary and per-task conflict data this plan extends"
provides:
  - "SyncPresentation.swift/SyncCopy.swift/AnnouncementDebouncer.swift: one pure derive(_:now:) function over a closed 13-case input union, the exact inherited copy vocabulary with the this-Mac -> this-iPhone substitution, and a debounced-announcement path that batches routine acknowledgements"
  - "BottomAccessoryView.swift: a dumb SyncPresentationSummary/UndoAvailabilityPresentation consumer with no priority logic of its own; RootTabView omits the .tabViewBottomAccessory call site entirely when there is nothing to show"
  - "SyncRecoverySheet.swift/TaskExceptionRow.swift: the full-screen (.fullScreenCover) Sync & Recovery inspection surface and the inline per-task exception indicator, both reading the same derived summary"
  - "A persistent Sync & Recovery overflow-menu row on both tabs' toolbars, present even when everything is quiet, with an Undo mirror slot"
  - "WorkspaceFacade.syncPresentation/undoAvailability/isSyncRecoveryPresented/syncRecoveryFocusTaskId -- the one shared presentation state every surface reads and every opener shares"
  - "tooling/ios-lanes/sync-presentation.mjs covering SyncPresentationTests, AnnouncementTests, and SyncRecoveryTests in one xcodebuild invocation"
affects: [04-13, 04-14, 04-15, 04-17]

actuals:
  tokens: 195000
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "A container view's .accessibilityIdentifier overrides its children's own identifiers in SwiftUI/XCUITest rather than coexisting with them -- discovered directly via XCUIApplication.debugDescription while developing BottomAccessoryView/SyncRecoverySheet; the fix is structural: identifiers are set ONLY on leaf text/button elements, never on a wrapping Group/HStack/VStack/NavigationLink"
    - "A UI-test-only launch-environment fixture hook (KEEPLING_UITEST_SYNC_STATE/KEEPLING_UITEST_UNDO_AVAILABLE/KEEPLING_UITEST_SEED_CONFLICT) drives the app deterministically into any closed-set state without a real sync pass, mirroring KEEPLING_ACCESSORY_PROBE_MODE's established pattern; the conflict seed specifically routes through the REAL capture -> acceptMutation -> acknowledge(outcome: .conflict) path rather than synthesizing a fake WorkspaceItem"
    - ".fullScreenCover, not .sheet, for a UI-SPEC-mandated full-screen surface -- .sheet's default 'large detent' card leaves a visible top inset and rounded corners on iPhone, which is not full screen"

key-files:
  created:
    - apps/ios/Sources/KeeplingCore/Presentation/SyncPresentation.swift
    - apps/ios/Sources/KeeplingCore/Presentation/SyncCopy.swift
    - apps/ios/Sources/KeeplingCore/Presentation/AnnouncementDebouncer.swift
    - apps/ios/Sources/Keepling/SyncRecovery/BottomAccessoryView.swift
    - apps/ios/Sources/Keepling/SyncRecovery/SyncRecoverySheet.swift
    - apps/ios/Sources/Keepling/Shared/TaskExceptionRow.swift
    - apps/ios/Tests/KeeplingCoreTests/SyncPresentationTests.swift
    - apps/ios/Tests/KeeplingUITests/AnnouncementTests.swift
    - apps/ios/Tests/KeeplingUITests/SyncRecoveryTests.swift
    - tooling/ios-lanes/sync-presentation.mjs
  modified:
    - apps/ios/Sources/Keepling/App/RootTabView.swift
    - apps/ios/Sources/Keepling/App/KeeplingApp.swift
    - apps/ios/Sources/Keepling/Workspace/WorkspaceFacade.swift
    - apps/ios/Sources/Keepling/Shared/TaskRow.swift
    - apps/ios/Sources/Keepling/Today/TodayView.swift
    - apps/ios/Sources/Keepling/Inbox/InboxView.swift
    - apps/ios/project.yml

key-decisions:
  - "The closed SyncPresentationInput union carries 13 cases (healthy plus 12 named states), not the 12 the plan's own prose lists -- healthy alone cannot satisfy the D-43 copy test requiring the literal string 'Saved on this iPhone', which is the Mac table's separate 'Local acceptance' row. Added .localAcceptance as its own case rather than overloading .healthy with visible copy, which would violate D-38's 'healthy is silent' rule."
  - "Undo-versus-exception accessory arbitration (Claude's Discretion, 04-UI-SPEC.md Navigation/Gesture Contract): exception-first. An actionable exception always wins the accessory slot; an available undo is never hidden entirely -- it remains reachable in the overflow menu's Undo mirror row."
  - "Bottom-trailing thumb-zone arbitration (Claude's Discretion, same section): resolved exactly as the UI-SPEC's own stated resolution -- capture stays reachable via the nav-bar toolbar action at all times, independent of accessory state; RootTabView never lets the accessory gate or clip it."
  - "Per-task exception data is scoped to what WorkspaceFacade already models (active conflict only, from 04-09). Rejected/uncertain per-task presentation is a disclosed later-plan gap, not silently dropped -- TaskExceptionRow/SyncRecoverySheet both consume the shared SyncPresentationSummary vocabulary so no structural change is needed once that data exists."
  - "UndoAvailabilityPresentation is intentionally minimal: only the presentation-priority arbitration point the accessory needs (a label plus availability). The full semantic-undo feature (persistent until superseded, compensating server action, separate from UndoManager, D-30/D-33/D-34) is NOT built by this plan -- the overflow menu's Undo button is a labeled no-op placeholder."
  - "Real production wiring from KeeplingApplication.runSyncPass outcomes into WorkspaceFacade.updateSyncPresentation is not built. KeeplingApplication.runSyncPass returns a coarse SyncPassOutcome (completed/fenced/authenticationRequired) with no per-error propagation path today, and building that reactive bridge (offline detection, updating/grace timing, per-error mapping) is itself a multi-plan effort tracked implicitly by this phase's later plans. WorkspaceFacade.syncPresentation defaults to healthy and is fully wired for a caller to drive; UI-test-only fixture hooks exercise every state deterministically in the interim."

requirements-completed: [IOS-04]

coverage:
  - id: D1
    description: "One pure SyncPresentation.derive(_:now:) function over a closed 13-case input union, sharing SyncPassScheduler.activeGracePeriod, with the exact inherited Mac copy vocabulary (this-Mac -> this-iPhone substitution) and no backend vocabulary or global-completeness claim anywhere in derived copy"
    requirement: IOS-04
    verification:
      - kind: unit
        ref: "Tests/KeeplingCoreTests/SyncPresentationTests.swift (14 tests, all pass)"
        status: pass
      - kind: integration
        ref: "node tooling/verify-ios-phase.mjs --lane sync-presentation"
        status: pass
    human_judgment: false
  - id: D2
    description: "An uncertain-acceptance input derives its own named state, never healthy and never a rejection; every StoreUnrecoverable case derives the unrecoverable state with Inspect/Export/confirmed-removal actions"
    requirement: IOS-04
    verification:
      - kind: unit
        ref: "Tests/KeeplingCoreTests/SyncPresentationTests.swift#testUncertainDerivesItsOwnNamedStateNeverHealthyNorRejected, #testEveryStoreUnrecoverableCaseDerivesUnrecoverableWithInspectExportAndRemoveActions"
        status: pass
    human_judgment: false
  - id: D3
    description: "AnnouncementDebouncer emits exactly one announcement per meaningful transition, .high priority reserved for actionable exceptions, and batches routine local-acceptance transitions into one bounded summary rather than announcing each"
    requirement: IOS-04
    verification:
      - kind: unit
        ref: "Tests/KeeplingUITests/AnnouncementTests.swift (8 tests, all pass)"
        status: pass
    human_judgment: false
  - id: D4
    description: "The bottom accessory is genuinely absent when healthy (call site omitted, zero frame/hit region measured against the AccessoryAbsenceProbeTests baseline), and computes no priority order of its own -- it renders exactly the actionable exception when both an exception and an available undo are present, and holds transient work only past the grace period"
    requirement: IOS-04
    verification:
      - kind: automated_ui
        ref: "Tests/KeeplingUITests/SyncRecoveryTests.swift#testHealthyAccessoryExposesNoTextGlyphOrCount, #testHealthyAccessoryDoesNotShiftTheTabBarsTopEdgeRelativeToNoAccessoryAtAll, #testAnExceptionAndAnAvailableUndoTogetherRenderOnlyTheExceptionInTheAccessory, #testAvailableUndoAloneRendersTheUndoControlInTheAccessory, #testTransientWorkRendersOnlyPastTheGracePeriod, #testEveryActionableExceptionStateRendersAccessoryTextAndARecoveryAction"
        status: pass
      - kind: static
        ref: "node source-scan: BottomAccessoryView.swift consumes AccessoryHostability and contains no re-derived actionable/undo/transient ordering"
        status: pass
    human_judgment: false
  - id: D5
    description: "A persistent Sync & Recovery overflow-menu row exists on both tabs in every state including fully healthy; the sheet presents full screen; the no-exceptions state renders the exact heading and coarse last-contact copy with no completeness claim; no navigation bar carries a synchronization status glyph"
    requirement: IOS-04
    verification:
      - kind: automated_ui
        ref: "Tests/KeeplingUITests/SyncRecoveryTests.swift#testOverflowMenuOffersSyncRecoveryRowEvenWhenHealthy, #testOverflowMenuIsPresentOnBothTabs, #testSyncRecoverySheetShowsNoChangesEmptyStateWhenNothingNeedsAttention, #testSyncRecoverySheetPresentsFullScreen, #testNoNavigationBarContainsASynchronizationStatusGlyph"
        status: pass
      - kind: static
        ref: "node source-scan: SyncRecoverySheet.swift contains the exact 'Sync & Recovery' / 'No Changes Need Your Attention' / 'Last successful contact' copy and never 'Everything synced'"
        status: pass
    human_judgment: false
  - id: D6
    description: "A per-task exception (conflict) renders inline beside its own row, and a seeded real conflict's deep link opens the sheet at that entry while the sheet's own entry navigates to the task's detail"
    requirement: IOS-04
    verification:
      - kind: automated_ui
        ref: "Tests/KeeplingUITests/SyncRecoveryTests.swift#testASeededConflictAppearsInlineAndInTheSyncRecoverySheetWithWorkingDeepLinks"
        status: pass
    human_judgment: false
  - id: D7
    description: "Capture stays reachable via the nav-bar toolbar action regardless of accessory state -- the accessory never gates or clips it"
    requirement: IOS-04
    verification:
      - kind: automated_ui
        ref: "Tests/KeeplingUITests/SyncRecoveryTests.swift#testCaptureToolbarActionStaysReachableWhileAnExceptionOccupiesTheAccessory"
        status: pass
    human_judgment: false
  - id: D8
    description: "Production wiring of live synchronization state into the presentation projection (KeeplingApplication.runSyncPass -> WorkspaceFacade.updateSyncPresentation, offline detection, updating-timer scheduling) and the full semantic-undo feature behind UndoAvailabilityPresentation"
    verification: []
    human_judgment: true
    rationale: "Not built by this plan (see key-decisions). The projection, its priority order, every consuming view, and the presentation-only arbitration point are complete and independently tested against UI-test fixture hooks; connecting them to the real runSyncPass/undo lifecycle is left to a later plan and needs a human/owner to confirm scope before it is scheduled."
duration: ~2h30m
completed: 2026-09-05
status: complete
---

# Phase KPL-04 Plan 10: Native iPhone Daily Loop -- Synchronization Presentation Summary

**One authoritative `SyncPresentation.derive(_:now:)` projection with the exact inherited Mac copy vocabulary drives a genuinely-absent-when-healthy bottom accessory, a full-screen `Sync & Recovery` sheet reachable from a persistent overflow-menu row on both tabs, and inline per-task conflict indicators -- with a debounced announcement path that batches routine acknowledgements instead of narrating each one.**

## Performance

- **Duration:** ~2h30m
- **Tasks:** 3 of 3 completed (all `tdd="true"`)
- **Files created/modified:** 17

## Accomplishments

- `SyncPresentation.swift` is a pure function over a closed 13-case input union (healthy plus 12 named states) with an injected clock, sharing `SyncPassScheduler.activeGracePeriod` rather than redeclaring a second grace period. Every derived copy string is proven free of `this Mac`, `Everything synced`, and backend vocabulary (outbox/cursor/SQLite/fingerprint/bootstrap/transport) by a test that enumerates the full closed input set.
- `SyncCopy.swift` carries the exact 03-UI-SPEC state-language table with the `this Mac` -> `this iPhone` substitution, including the compound `Sync when you're back online` form.
- `AnnouncementDebouncer.swift` emits exactly one announcement per meaningful state transition, reserves `.high` priority for actionable exceptions, and batches consecutive routine local-acceptance transitions into a single bounded summary (`"3 changes saved on this iPhone"`) flushed on the next real transition -- proven never to leak task titles.
- `BottomAccessoryView.swift` is a dumb consumer of `SyncPresentationSummary`/`UndoAvailabilityPresentation`: it computes no priority order of its own (verified both by XCUITest and a source-scan check for re-derived ordering logic). `RootTabView` omits the `.tabViewBottomAccessory` call site entirely whenever there is nothing to show and `AccessoryHostability` measured absence as achievable (04-04's `conditionalModifier` finding) -- proven with the same zero-frame/zero-hit-region technique `AccessoryAbsenceProbeTests` established, and proven never to shift the tab bar's top edge relative to a build with no accessory code at all.
- `SyncRecoverySheet.swift` presents full screen via `.fullScreenCover` (not `.sheet`, which leaves a visible top inset on iPhone), lists only per-task exceptions bounded, and renders the exact `No Changes Need Your Attention` / `Last successful contact` copy when nothing needs attention -- never a global-completeness claim.
- `TaskExceptionRow.swift` replaces the ad hoc "Needs your attention" string `TaskRow` previously hardcoded, now deriving from the same `SyncPresentation.derive` call every other surface uses.
- A persistent `Sync & Recovery` overflow-menu row was added to both `TodayView`/`InboxView` toolbars (`.topBarTrailing`, not `.secondaryAction` -- the latter collapses into a system "More" button whose own identifier is unreachable), present in every state including fully healthy, carrying an Undo mirror row when `WorkspaceFacade.undoAvailability` is set.
- `WorkspaceFacade` gained `syncPresentation`/`undoAvailability`/`isSyncRecoveryPresented`/`syncRecoveryFocusTaskId` as the one shared presentation-state surface every opener (accessory action, either tab's overflow menu, a per-task exception's deep link) reads and writes identically.
- A UI-test-only conflict-seeding hook (`KEEPLING_UITEST_SEED_CONFLICT`) drives one task through the REAL `OutboundCommands.capture` -> `GRDBLocalStore.acceptMutation` -> `GRDBLocalStore.acknowledge(outcome: .conflict)` path (the same production code `KeeplingApplication.runSyncPass` exercises), so `testASeededConflictAppearsInlineAndInTheSyncRecoverySheetWithWorkingDeepLinks` proves the inline exception row, the sheet's listing, and both deep-link directions against real data rather than a synthesized fixture.
- `tooling/ios-lanes/sync-presentation.mjs` runs `SyncPresentationTests`, `AnnouncementTests`, and `SyncRecoveryTests` (34 test methods total) in one `xcodebuild` invocation, following the established multi-`-only-testing` pattern (`auth.mjs`, `durability-posture.mjs`, `transport.mjs`).

## Task Commits

1. **Task 1: One authoritative presentation projection with the inherited copy vocabulary** -- `0e40104` (feat)
2. **Task 2: The conditional bottom accessory and its strict priority order** -- `b926d3c` (feat)
3. **Task 3: Sync and Recovery sheet, inline per-task exceptions, and the overflow-menu path** -- `e351cf1` (feat)

_Note: as with every prior plan in this phase, each task's tests and implementation were authored together and driven to green within one continuous working session rather than committed as a separate captured RED state before the corresponding GREEN commit. See TDD Gate Compliance below._

## Files Created/Modified

- `apps/ios/Sources/KeeplingCore/Presentation/SyncPresentation.swift` -- the one derivation function, closed input union, summary type
- `apps/ios/Sources/KeeplingCore/Presentation/SyncCopy.swift` -- the exact inherited copy vocabulary
- `apps/ios/Sources/KeeplingCore/Presentation/AnnouncementDebouncer.swift` -- debounced, batched accessibility announcements
- `apps/ios/Sources/Keepling/SyncRecovery/BottomAccessoryView.swift` -- the conditional accessory content
- `apps/ios/Sources/Keepling/SyncRecovery/SyncRecoverySheet.swift` -- the full-screen inspection sheet
- `apps/ios/Sources/Keepling/Shared/TaskExceptionRow.swift` -- the inline per-task exception indicator
- `apps/ios/Sources/Keepling/App/RootTabView.swift` -- accessory attach/omit decision, full-screen cover wiring
- `apps/ios/Sources/Keepling/App/KeeplingApp.swift` -- UI-test fixture hooks (sync state, undo, conflict seeding)
- `apps/ios/Sources/Keepling/Workspace/WorkspaceFacade.swift` -- the shared presentation-state surface
- `apps/ios/Sources/Keepling/Shared/TaskRow.swift`, `Today/TodayView.swift`, `Inbox/InboxView.swift` -- inline exception wiring, overflow menu
- `apps/ios/project.yml` -- `KeeplingUITests` gains a direct `package: KeeplingCore` dependency
- `apps/ios/Tests/KeeplingCoreTests/SyncPresentationTests.swift`, `Tests/KeeplingUITests/AnnouncementTests.swift`, `Tests/KeeplingUITests/SyncRecoveryTests.swift` -- the new test suite
- `tooling/ios-lanes/sync-presentation.mjs` -- the new lane

## Decisions Made

See `key-decisions` frontmatter above. Most consequential: the 13-case (not 12) input union, the exception-first accessory priority resolving both Claude's-Discretion arbitration questions, and the explicit disclosure that real `runSyncPass` -> presentation wiring is not yet built.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `KeeplingUITests` could not import `KeeplingCore` to compile `AnnouncementTests.swift`**
- **Found during:** Task 1
- **Issue:** The plan places `AnnouncementTests.swift` (a plain `XCTestCase`, no `XCUIApplication`) in `Tests/KeeplingUITests/`, but that target only depends on `target: Keepling` (a UI-test host-app link), which does not expose `KeeplingCore`'s compiled module for `import`/`@testable import` at compile time -- build failed with `unable to resolve module dependency: 'GRDBSQLite'`.
- **Fix:** Added `package: KeeplingCore` as a second dependency on the `KeeplingUITests` target in `project.yml`, mirroring the existing unit-test targets' pattern.
- **Files modified:** `apps/ios/project.yml`
- **Verification:** `xcodebuild test -only-testing:KeeplingUITests/AnnouncementTests` -- 8/8 pass
- **Committed in:** `0e40104` (Task 1 commit)

**2. [Rule 1 - Bug] A container's `.accessibilityIdentifier` overrides its children's own identifiers**
- **Found during:** Task 2, then rediscovered independently in Task 3
- **Issue:** `BottomAccessoryView.swift`'s outer `Group`/`HStack` and `SyncRecoverySheet.swift`'s `VStack`/`NavigationLink` each carried their own `.accessibilityIdentifier` alongside leaf `Text`/`Button` elements that ALSO carried identifiers -- `XCUIApplication.debugDescription` showed every leaf collapsed to the CONTAINER's identifier, making the leaf identifiers unqueryable and causing 5 (Task 2) then 3 (Task 3) XCUITest failures.
- **Fix:** Removed every container-level `.accessibilityIdentifier`; identifiers now live ONLY on leaf text/button elements, with an explicit code comment recording the constraint so it is not rediscovered by a future plan.
- **Files modified:** `apps/ios/Sources/Keepling/SyncRecovery/BottomAccessoryView.swift`, `apps/ios/Sources/Keepling/SyncRecovery/SyncRecoverySheet.swift`
- **Verification:** Full `SyncRecoveryTests` suite (13 tests) passes
- **Committed in:** `b926d3c`, `e351cf1`

**3. [Rule 2 - Missing Critical] `.sheet` does not satisfy the UI-SPEC's "full-screen `Sync & Recovery` sheet" requirement**
- **Found during:** Task 3
- **Issue:** SwiftUI's default `.sheet` on iPhone renders an inset "large detent" card with a visible top gap and rounded corners, not a genuinely full-screen surface, contradicting 04-UI-SPEC.md's explicit "full-screen `Sync & Recovery` sheet" language (point 4 of the Synchronization and Recovery Presentation hierarchy).
- **Fix:** Presented via `.fullScreenCover` instead.
- **Files modified:** `apps/ios/Sources/Keepling/App/RootTabView.swift`
- **Verification:** `testSyncRecoverySheetPresentsFullScreen` passes
- **Committed in:** `e351cf1`

**4. [Rule 3 - Blocking] `.secondaryAction` toolbar placement collapsed the Menu into an unqueryable system "More" button**
- **Found during:** Task 3
- **Issue:** `ToolbarItem(placement: .secondaryAction)` wrapping the overflow `Menu` rendered as a system-provided `OverflowBarButtonItem` ("More") in the accessibility tree, and my `.accessibilityIdentifier("overflow-menu")` on the `Menu` itself never propagated to that system button -- `app.buttons["overflow-menu"]` never matched.
- **Fix:** Changed placement to `.topBarTrailing`, which renders the `Menu` directly (no system overflow wrapper) and honors the identifier.
- **Files modified:** `apps/ios/Sources/Keepling/Today/TodayView.swift`, `apps/ios/Sources/Keepling/Inbox/InboxView.swift`
- **Verification:** `testOverflowMenuOffersSyncRecoveryRowEvenWhenHealthy`, `testOverflowMenuIsPresentOnBothTabs` pass
- **Committed in:** `e351cf1`

---

**Total deviations:** 4 auto-fixed (2 blocking, 1 bug, 1 missing-critical)
**Impact on plan:** All four were necessary for the plan's own stated behaviors to compile or pass verification. No scope creep -- the accessibility-identifier and toolbar-placement fixes are structural discoveries recorded in code comments so they are not rediscovered by a later plan; the `.fullScreenCover` fix is required by the UI-SPEC's own explicit wording.

## Known Stubs

- **`WorkspaceFacade.syncPresentation`/`undoAvailability` default to healthy/`nil` with no production wiring from `KeeplingApplication.runSyncPass`.** `apps/ios/Sources/Keepling/Workspace/WorkspaceFacade.swift`. Reason: `runSyncPass` returns only a coarse `SyncPassOutcome` (`completed`/`fenced`/`authenticationRequired`) today, with no per-error/offline/updating-timer propagation path built yet; bridging that reactively is itself a multi-concern effort left to a later plan. UI-test-only launch-environment hooks (`KEEPLING_UITEST_SYNC_STATE`/`KEEPLING_UITEST_UNDO_AVAILABLE`) drive every closed-set state deterministically for `SyncRecoveryTests` in the interim.
- **Per-task exception modeling covers only active conflict.** `apps/ios/Sources/Keepling/SyncRecovery/SyncRecoverySheet.swift`, `TaskExceptionRow.swift`. Reason: `WorkspaceItem` (04-09) has no rejected/uncertain per-task field yet. Both views read the shared `SyncPresentationSummary` vocabulary, so no structural change is needed once that data exists -- only a new `WorkspaceItem` field and a filter update.
- **The overflow menu's Undo mirror button is a labeled no-op.** `apps/ios/Sources/Keepling/Today/TodayView.swift`, `apps/ios/Sources/Keepling/Inbox/InboxView.swift`. Reason: this plan builds only the presentation-priority arbitration point (`UndoAvailabilityPresentation`) the accessory needs between an exception and an available undo; the full semantic-undo feature (persistent until superseded, compensating server action, D-30/D-33/D-34) is a separate, not-yet-executed plan's scope.

These are not blockers to this plan's own goal (IOS-04's trust requirement: every surface derives from one projection, healthy is silent, exceptions are distinguishable with named recovery actions) -- they are the disclosed boundary of what this plan intentionally did not build.

## Issues Encountered

None beyond the deviations documented above.

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness

- The presentation projection, accessory, sheet, and inline exception surfaces are complete, independently tested (34 test methods across three classes, all passing), and ready for a later plan to wire to live `runSyncPass` state and the full Undo feature.
- Regression-checked against `core-loop`, `accessory-probe`, and `lifecycle` lanes (all pass) since this plan touched `RootTabView.swift`, `WorkspaceFacade.swift`, `TaskRow.swift`, `TodayView.swift`, `InboxView.swift`, and `KeeplingApp.swift` -- files those lanes also exercise.
- `.planning/WINDOWS.md` append for the three Known Stubs above failed with a pre-existing ledger count mismatch (`frontmatter open/waived/fixed/total=1/49/6/56` vs. computed `6/49/6/61`) unrelated to this plan's changes; the stubs are recorded here instead. A future session should reconcile `WINDOWS.md`'s frontmatter counts against its entries before the next append.

---
*Phase: KPL-04-native-iphone-daily-loop*
*Completed: 2026-09-05*
