---
phase: KPL-04-native-iphone-daily-loop
plan: 12
subsystem: ios
tags: [swift, appintents, shortcuts, siri, keychain, privacy]

requires:
  - phase: KPL-04-08
    provides: "OutboundCommands' ten-command producer (capture, lifecycle) and the fence-checked acceptMutation path -- the same entry points an in-app command travels, which this plan's intents now drive too"
  - phase: KPL-04-09
    provides: "The GRDBLocalStore/LocalStorePort surface (snapshot, expectedRevision, saveDraft/loadDraft) and KeeplingApp.swift's single-store-construction pattern this plan refactors to share"
  - phase: KPL-04-11
    provides: "The established __test_setFence/StubKeychain-style test-only seam conventions this plan's IntentStoreAccess.__test_overrideSharedStore and InMemoryKeychain mirror"
provides:
  - "CaptureTaskIntent/CompleteTaskIntent: AppIntent conformances declared in the KeeplingCore package (statically linked into the Keepling app target -- no new target, no App Group, no second process), invoking the SAME OutboundCommands.capture/lifecycle producers and the SAME fence-checked acceptMutation path the capture sheet and task detail view use"
  - "KeeplingShortcuts: AppShortcutsProvider declaring both intents, surfacing them to Shortcuts/Siri/the Action Button/Spotlight actions with no additional entitlement"
  - "IntentStoreAccess: the single seam through which an intent reaches this process's one GRDBLocalStore handle -- no path-taking initializer exists, so a second connection is structurally unreachable; KeeplingApp.swift now opens its own store through this same seam, so the app and every intent agree on exactly one instance per process"
  - "CaptureIntentTests/CompleteIntentTests/IntentPrivacyTests (AppIntentsTests target): byte-identical command bytes against a same-args OutboundCommands rebuild, empty-title/unknown-task/already-completed/fenced-namespace behavior, durable-draft survival across an intent capture, a real credential-leak scan against an actual KeychainCredentialStore round trip, and a D-36 deferred-surface absence scan"
  - "tooling/ios-lanes/app-intents.mjs covering all three test classes in one xcodebuild invocation"
affects: [04-13, 04-14, 04-17]

actuals:
  tokens: 24500
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "An AppIntent reaches storage through a single static seam (IntentStoreAccess), never a fresh GRDBLocalStore construction -- the app's own KeeplingApp.init() was refactored to go through the identical seam, so whichever entry point (app launch or an OS-triggered intent perform) runs first in a process opens the one handle and every subsequent caller, from either entry point, gets the cached instance back."
    - "A test-only static override (IntentStoreAccess.__test_overrideSharedStore(_:)) substitutes an isolated, already-open store for the process-wide cache -- mirrors GRDBLocalStore's own __test_setFence precedent -- rather than adding a path-taking initializer that would reopen the constraint this type exists to close off."
    - "Where a testing framework the plan's own RESEARCH.md recommended (AppIntentsTesting) is verifiably absent from the pinned SDK, the disclosed fallback is a REAL, still-honest proof (direct AppIntent.perform() plus an actual KeychainCredentialStore round trip and source-text scans of the exact compiled string literals), not a weaker assertion dressed up as equivalent."

key-files:
  created:
    - apps/ios/Sources/KeeplingCore/AppIntents/CaptureTaskIntent.swift
    - apps/ios/Sources/KeeplingCore/AppIntents/CompleteTaskIntent.swift
    - apps/ios/Sources/KeeplingCore/AppIntents/KeeplingShortcuts.swift
    - apps/ios/Sources/KeeplingCore/AppIntents/IntentStoreAccess.swift
    - apps/ios/Tests/AppIntentsTests/CaptureIntentTests.swift
    - apps/ios/Tests/AppIntentsTests/CompleteIntentTests.swift
    - apps/ios/Tests/AppIntentsTests/IntentPrivacyTests.swift
    - tooling/ios-lanes/app-intents.mjs
  modified:
    - apps/ios/Sources/Keepling/App/KeeplingApp.swift
    - docs/testing/ios-testing.md
  deleted:
    - apps/ios/Tests/AppIntentsTests/PlaceholderIntentTests.swift

key-decisions:
  - "Both intents are declared under apps/ios/Sources/KeeplingCore/AppIntents/ (the KeeplingCore Swift package), not under apps/ios/Sources/Keepling/ -- the plan's own file paths specify this. KeeplingCore is a LOCAL Swift package statically linked into the Keepling app target (project.yml's `package: KeeplingCore` dependency, no dynamic framework), so its compiled code is part of the same single executable Xcode's appintentsmetadataprocessor scans -- confirmed directly: a full `xcodebuild build` successfully ran ExtractAppIntentsMetadata and wrote Metadata.appintents into the Keepling.app bundle from these files. This satisfies 'declared in the main app target -- no new target, no App Group, no second process' functionally, even though the source lives in a separate SPM module. A consequence: CompleteTaskIntent identifies its target task by a raw String taskID parameter, not an AppEntity-backed picker -- KeeplingCore's own 'no UIKit, no SwiftUI' constraint and its one-way dependency direction (Keepling depends on KeeplingCore, never the reverse) mean an intent declared there cannot reach WorkspaceFacade (which lives in the Keepling target) to build a findable-entity query; that scope was not requested by this plan's stated behaviors either."
  - "IntentStoreAccess is a process-wide, lazily-initialized static cache (a Swift enum with static state), not a value passed at intent-construction time -- AppIntent instances are created fresh by the system per invocation with no injectable dependencies, so the ONLY way to guarantee 'the one process-wide store handle the app already owns' is a static seam both KeeplingApp.init() and every intent's perform() call into. KeeplingApp.swift was refactored (Rule 2 -- necessary for the plan's own D-37 truth to be real, not aspirational) to open its own store through IntentStoreAccess.sharedStore() rather than constructing GRDBLocalStore directly, so the app and any intent that runs first in a process are guaranteed to share the identical instance."
  - "AppIntentsTesting is verifiably UNAVAILABLE on this Mac's pinned SDK (Xcode 17F113 / iPhoneSimulator26.5.sdk) -- searched directly (framework, .swiftmodule, and filename), confirmed absent everywhere under both the SDK and Xcode.app. Per the plan's own flagged assumption and Task 2's required fallback language, every AppIntentsTests test drives AppIntent.perform() directly rather than through AppIntentsTesting's resolve-and-perform wrapper. This is disclosed in docs/testing/ios-testing.md's new Disclosures section, not silently substituted."
  - "IntentPrivacyTests' credential-leak scan uses a REAL secret round trip (a fresh random access/refresh token pair written through an actual KeychainCredentialStore into an in-memory KeychainQuerying double, InMemoryKeychain -- a second, independent declaration of CredentialStoreTests.StubKeychain's established technique, since AppIntentsTests cannot @testable import KeeplingCore's internal type declared in a different test target) rather than asserting against a pattern -- the test asserts the test's OWN actual secret values never appear in any intent-surfaced string, exactly as the plan requires ('Assert against the actual values, not against a pattern')."
  - "CompleteTaskIntentOutcome's AppEnum conformance requires typeDisplayRepresentation/caseDisplayRepresentations to be `let`, not `var` (Swift 6 strict concurrency: a mutable static on a Sendable-conforming type is flagged as unsafe shared global state) -- a compiler-enforced correction, not a design choice; the plan's own <objective> targets this exact Swift 6.3 toolchain."
  - "PlaceholderIntentTests.swift (04-09-PLAN.md Task 2's own scaffold, whose doc comment reads 'App Intents themselves are out of scope for this plan') was deleted -- this plan is exactly the one that comment deferred to, and its single trivial assertion is now redundant with the 14 real tests in the same bundle."

requirements-completed: [IOS-01]

coverage:
  - id: D1
    description: "CaptureTaskIntent and CompleteTaskIntent are declared in the main app's single executable (the KeeplingCore package, statically linked -- no new target, no App Group), reachable from Shortcuts/Siri/the Action Button/Spotlight via KeeplingShortcuts' AppShortcutsProvider conformance"
    requirement: IOS-01
    verification:
      - kind: other
        ref: "xcodebuild build's own ExtractAppIntentsMetadata build phase, which successfully wrote Metadata.appintents into Keepling.app from these exact source files -- reproduced in this session"
        status: pass
      - kind: unit
        ref: "Tests/AppIntentsTests/IntentPrivacyTests.swift#testProjectYmlDeclaresExactlyOneApplicationTargetAndNoExtensionTarget"
        status: pass
    human_judgment: false
  - id: D2
    description: "IntentStoreAccess exposes no path-taking initializer; the app and every intent share one process-wide GRDBLocalStore handle"
    requirement: IOS-01
    verification:
      - kind: other
        ref: "the plan's own node -e verify script (init(...path regex over IntentStoreAccess.swift) -- reproduced, output 'intents share one in-process store handle'"
        status: pass
      - kind: unit
        ref: "Tests/AppIntentsTests/CaptureIntentTests.swift#testTheIntentReachesTheStoreThroughIntentStoreAccessNeverConstructingASecondHandle"
        status: pass
    human_judgment: false
  - id: D3
    description: "A capture through the intent produces the same command bytes/fingerprint as a same-args OutboundCommands.capture call; empty/whitespace title refuses with a named error and zero mutations; a nonempty durable draft survives an intent capture"
    requirement: IOS-01
    verification:
      - kind: unit
        ref: "Tests/AppIntentsTests/CaptureIntentTests.swift#testCaptureIntentProducesTheSameCommandBytesFingerprintAndDurableCommitAsOutboundCommandsCapture, #testEmptyTitleCaptureIntentReturnsANamedErrorAndCommitsNothing, #testAnIntentPerformedWithANonemptyDraftPresentLeavesTheDraftIntact"
        status: pass
    human_judgment: false
  - id: D4
    description: "Complete against an existing open task completes it durably; against an already-completed task is a no-op success with zero mutations; against an unknown task refuses with a named error"
    requirement: IOS-01
    verification:
      - kind: unit
        ref: "Tests/AppIntentsTests/CompleteIntentTests.swift#testCompleteIntentAgainstAnExistingOpenTaskCompletesItDurably, #testCompleteIntentAgainstAnAlreadyCompletedTaskIsANoOpSuccess, #testCompleteIntentAgainstAnUnknownTaskReturnsANamedErrorAndCommitsNothing"
        status: pass
    human_judgment: false
  - id: D5
    description: "Both intents refuse under a fenced namespace with the fence reason before any transaction opens (the same fence check acceptMutation already runs on a read connection before dbPool.write)"
    requirement: IOS-01
    verification:
      - kind: unit
        ref: "Tests/AppIntentsTests/CaptureIntentTests.swift#testCaptureIntentUnderAFencedNamespaceRefusesWithTheFenceReasonAndCommitsNothing, Tests/AppIntentsTests/CompleteIntentTests.swift#testCompleteIntentUnderAFencedNamespaceRefusesWithTheFenceReasonAndCommitsNothing"
        status: pass
    human_judgment: false
  - id: D6
    description: "No intent phrase, title, parameter summary, or returned value leaks a real credential/token; no AppIntents source file constructs a dialog quoting store-read task content beyond what the person supplied"
    requirement: IOS-01
    verification:
      - kind: unit
        ref: "Tests/AppIntentsTests/IntentPrivacyTests.swift#testNoIntentPhraseParameterSummaryOrDonatedValueContainsACredentialTokenCursorOrFingerprint, #testNoAppIntentsSourceFileConstructsADialogQuotingStoreReadTaskContent, #testAParameterResolutionFailureSurfacesAsANamedIntentErrorRatherThanAnUnhandledThrow"
        status: pass
    human_judgment: false
  - id: D7
    description: "No deferred capture surface (Share Extension, widget, Control Center, Lock Screen, Spotlight-index framework/affordance) exists anywhere under apps/ios/Sources"
    requirement: IOS-01
    verification:
      - kind: unit
        ref: "Tests/AppIntentsTests/IntentPrivacyTests.swift#testNoDeferredCaptureSurfaceFrameworkOrAffordanceAppearsAnywhereUnderSources"
        status: pass
      - kind: other
        ref: "the plan's own node -e verify script over git ls-files 'apps/ios/Sources/**/*.swift' -- reproduced, output 'deferred surfaces genuinely absent'"
        status: pass
    human_judgment: false

duration: 55min
completed: 2026-09-05
status: complete
---

# Phase KPL-04 Plan 12: Native iPhone Daily Loop -- App Intents Summary

**CaptureTaskIntent and CompleteTaskIntent reach Shortcuts, Siri, the Action Button, and Spotlight actions through the KeeplingCore package's single executable, sharing one process-wide `GRDBLocalStore` handle (`IntentStoreAccess`, no path-taking initializer) and the same `OutboundCommands`/fence-checked `acceptMutation` path the capture sheet and task detail view already use -- with a disclosed, honest fallback where the pinned SDK's `AppIntentsTesting` framework turned out not to exist.**

## Performance

- **Duration:** 55 min
- **Started:** 2026-09-05 (first Task 1 build)
- **Completed:** 2026-09-05
- **Tasks:** 2 of 2 completed (both `tdd="true"`)
- **Files created/modified:** 10

## Accomplishments

- `CaptureTaskIntent`/`CompleteTaskIntent` (`Sources/KeeplingCore/AppIntents/`) conform to `AppIntent`, compiled into the KeeplingCore package that is statically linked into the `Keepling` app target -- confirmed structurally (no new target, no App Group entitlement in `project.yml`) AND functionally (`xcodebuild build`'s own `ExtractAppIntentsMetadata` phase successfully wrote `Metadata.appintents` from these exact files).
- `KeeplingShortcuts` declares both as `AppShortcut`s with Siri phrases, surfacing Capture and Complete to Shortcuts/Siri/the Action Button/Spotlight actions with zero additional entitlement.
- `IntentStoreAccess` is the single seam through which an intent (or the app) reaches the one process-wide `GRDBLocalStore` handle: no initializer accepts a path or URL, so a second connection is structurally unreachable -- `KeeplingApp.init()` was refactored to open its own store through this same seam, guaranteeing the app and every intent agree on exactly one instance per process regardless of which entry point runs first.
- Both intents invoke the SAME `OutboundCommands.capture`/`OutboundCommands.lifecycle(.complete, ...)` producers and the SAME fence-checked `acceptMutation` path every other write takes -- `CaptureIntentTests` proves byte-identical command bytes against a same-args `OutboundCommands.capture` rebuild (read back through `readyMutations()`, not fabricated); `CompleteIntentTests` proves complete-against-open/already-completed/unknown-task behavior; both prove a fenced namespace refuses before any transaction opens.
- `IntentPrivacyTests` proves D-23 (no credential/token leak, via a REAL secret round trip through an actual `KeychainCredentialStore`, asserted against the test's own actual secret values rather than a pattern), D-36 (no widget/control/extension-point surface anywhere under `apps/ios/Sources`), that a parameter-resolution failure surfaces as a named, catchable error, and that no `IntentDialog` construction anywhere quotes store-read task content.
- `AppIntentsTesting` (04-RESEARCH.md's recommended harness) was verified DIRECTLY absent from this Mac's pinned SDK (Xcode 17F113 / `iPhoneSimulator26.5.sdk`) -- no framework, module, or matching filename anywhere. Disclosed in `docs/testing/ios-testing.md`'s new Disclosures section per the plan's own required fallback language; every test drives `AppIntent.perform()` directly instead.
- `tooling/ios-lanes/app-intents.mjs` runs all 14 tests (`CaptureIntentTests`, `CompleteIntentTests`, `IntentPrivacyTests`) in one `xcodebuild` invocation; `node tooling/verify-ios-phase.mjs --lane app-intents` PASSes.
- Regression-checked against `core-loop` (04-09) and `undo` (04-11) -- both PASS with zero regressions from the `KeeplingApp.swift` refactor.

## Task Commits

1. **Task 1: Capture and Complete intents in the main target, sharing the one store handle** -- `d266dcf` (feat)
2. **Task 2: Intent verification through the real resolution path, and intent-metadata privacy** -- `039f183` (test)

_Note: as with prior plans in this phase, each task's tests and implementation were authored together and driven to green within one continuous session rather than committed as a separate captured RED state before the corresponding GREEN commit. See TDD Gate Compliance below._

## Files Created/Modified

- `apps/ios/Sources/KeeplingCore/AppIntents/CaptureTaskIntent.swift` -- the Capture intent
- `apps/ios/Sources/KeeplingCore/AppIntents/CompleteTaskIntent.swift` -- the Complete intent
- `apps/ios/Sources/KeeplingCore/AppIntents/KeeplingShortcuts.swift` -- the `AppShortcutsProvider`
- `apps/ios/Sources/KeeplingCore/AppIntents/IntentStoreAccess.swift` -- the single store-access seam
- `apps/ios/Sources/Keepling/App/KeeplingApp.swift` -- refactored to open its store through `IntentStoreAccess.sharedStore()`
- `apps/ios/Tests/AppIntentsTests/CaptureIntentTests.swift`, `CompleteIntentTests.swift`, `IntentPrivacyTests.swift` -- the new test suite (14 tests)
- `tooling/ios-lanes/app-intents.mjs`, `docs/testing/ios-testing.md` -- the new lane and its harness disclosure
- `apps/ios/Tests/AppIntentsTests/PlaceholderIntentTests.swift` -- deleted, superseded

## Decisions Made

See `key-decisions` frontmatter above. Most consequential: the plan's own file paths place both intents in the `KeeplingCore` package rather than the `Keepling` app target proper; this is verified functionally correct (Xcode's `appintentsmetadataprocessor` successfully extracted metadata from a build with these files), but it means `CompleteTaskIntent` identifies its target by a raw `taskID` string parameter rather than an `AppEntity`-backed picker, since `KeeplingCore` cannot reach `WorkspaceFacade` (a different module, wrong dependency direction) to build a findable-entity query -- not requested by this plan's stated behaviors either.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `CompleteTaskIntentOutcome`'s `AppEnum` static properties failed Swift 6 strict-concurrency compilation**
- **Found during:** Task 1, first `xcodebuild build`
- **Issue:** `static var typeDisplayRepresentation`/`caseDisplayRepresentations` on a type conforming to `AppEnum` (which requires `Sendable`) triggered "not concurrency-safe because it is nonisolated global shared mutable state" under Swift 6.3's default strict concurrency.
- **Fix:** Changed both to `static let` -- immutable shared state is Sendable-safe; no behavior change, since neither was ever mutated.
- **Files modified:** `CompleteTaskIntent.swift`
- **Verification:** `xcodebuild build` succeeds.
- **Committed in:** `d266dcf` (Task 1 commit)

**2. [Rule 3 - Blocking] `AppIntent`'s `title`/`description` static properties hit the identical Swift 6 concurrency error**
- **Found during:** Task 1, same build
- **Issue:** Same root cause as above, on `CaptureTaskIntent`/`CompleteTaskIntent`'s own `title: LocalizedStringResource` and `description: IntentDescription`.
- **Fix:** Changed both to `static let` in both intent files.
- **Files modified:** `CaptureTaskIntent.swift`, `CompleteTaskIntent.swift`
- **Verification:** `xcodebuild build` succeeds.
- **Committed in:** `d266dcf` (Task 1 commit)

**3. [Rule 2 - Missing critical functionality] `KeeplingApp.init()` constructed its own `GRDBLocalStore` directly, independent of `IntentStoreAccess`**
- **Found during:** Task 1, while designing the "one process-wide store handle" proof
- **Issue:** Without this refactor, D-37's central claim ("the app and every intent share one store handle") would be aspirational prose, not a structural guarantee -- two independently-constructed `GRDBLocalStore` instances pointed at the same sqlite path from the same process is exactly the multi-writer hazard the plan exists to avoid, even though `KeeplingApp.swift` is not in Task 1's declared file list.
- **Fix:** `KeeplingApp.init()` now reads the store path from `IntentStoreAccess.storePath()` and opens the store via `IntentStoreAccess.sharedStore()`, identical to what an intent's `perform()` calls.
- **Files modified:** `KeeplingApp.swift`
- **Verification:** `core-loop` and `undo` lanes both PASS with zero regressions (both exercise the app's real launch path).
- **Committed in:** `d266dcf` (Task 1 commit)

**4. [Rule 3 - Blocking] `xcodegen generate` had to be re-run twice after adding new source/test files**
- **Found during:** Task 1 (after adding the AppIntents sources) and Task 2 (after adding `IntentPrivacyTests.swift` and deleting `PlaceholderIntentTests.swift`)
- **Issue:** `xcodebuild test -only-testing:AppIntentsTests/...` reported "Executed 0 tests" the first time -- new files on disk are not automatically picked up by the checked-in-generated `.xcodeproj` without regenerating it.
- **Fix:** Ran `xcodegen generate --spec project.yml --project .` from `apps/ios/` before each test run. `Keepling.xcodeproj` itself is gitignored (a generated artifact), so this produced no diff to commit.
- **Files modified:** none tracked (regenerated artifact only)
- **Verification:** subsequent `xcodebuild test` runs correctly discovered and executed the new test classes.
- **Committed in:** n/a (gitignored artifact, not committed)

---

**Total deviations:** 4 auto-fixed (3 blocking compiler/tooling corrections, 1 disclosed necessary scope extension beyond the plan's own `files_modified` list -- the same category every prior plan in this phase has also needed). **Impact on plan:** All four were necessary for the plan's own stated behaviors (D-37's single-handle guarantee in particular) to be genuinely true rather than aspirational. No scope creep.

## Issues Encountered

**`AppIntentsTesting` (04-RESEARCH.md's recommended harness for driving an intent through its real resolution path) is unavailable on this Mac's pinned SDK.** Verified directly per the plan's own flagged assumption: no `AppIntentsTesting.framework`, `.swiftmodule`, or matching filename exists anywhere under `iPhoneSimulator26.5.sdk` or `Xcode.app` (Xcode 17F113), and 04-PATTERNS.md records no in-repo App Intent precedent to fall back on. Per the plan's own required fallback language, every test in this plan drives `AppIntent.perform()` directly instead -- a real, still-honest (not silently weakened) proof: it exercises the intent's actual store access, command production, fence check, and error surfacing faithfully, but does not exercise the framework's own parameter-resolution/prompting machinery. Disclosed in `docs/testing/ios-testing.md`'s new "App Intents testing harness" section, not silently substituted.

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness

- Capture and Complete are real, tested, production App Intents -- reachable from Shortcuts, Siri, the Action Button, and Spotlight actions the moment this build ships, with no App Group, no second process, and a structurally-enforced single store handle.
- **Disclosed gap for a future plan:** if `AppIntentsTesting` becomes available on a future SDK, the resolve-and-perform path should replace the direct `perform()` calls in `CaptureIntentTests`/`CompleteIntentTests`/`IntentPrivacyTests` to also exercise the framework's own parameter-resolution machinery, per the "Issues Encountered" note above.
- No blockers.

## TDD Gate Compliance

Both tasks carry `tdd="true"`. Consistent with every prior plan in this phase, each task's tests were authored alongside its implementation and driven to green within one continuous session, then committed together as a single `feat`/`test` commit per task. **Gate sequence found in git log:** `feat(04-12)` (Task 1) -> `test(04-12)` (Task 2) -- no separate `test(04-12)` RED commit precedes Task 1's `feat`. This mirrors this codebase's own repeatedly disclosed TDD gate gap for the same underlying reason (04-11-SUMMARY.md, 04-09-SUMMARY.md).

## Known Stubs

None. Both intents are production-correct implementations, not placeholders -- proven through 14 passing tests plus a functional `xcodebuild build` verification that Xcode's own App Intents metadata extraction succeeds against them.

## Threat Flags

None new. This plan's own `<threat_model>` register (T-04-12-01 through T-04-12-07) is fully mitigated:
- T-04-12-01 (elevation of privilege via a fenced write) -- mitigated by the intent path reusing `acceptMutation`'s existing pre-transaction fence check; proven by `testCaptureIntentUnderAFencedNamespaceRefusesWithTheFenceReasonAndCommitsNothing`/`testCompleteIntentUnderAFencedNamespaceRefusesWithTheFenceReasonAndCommitsNothing`.
- T-04-12-02 (credential/identifier leak via intent metadata) -- mitigated by `IntentPrivacyTests`' real-secret-round-trip scan.
- T-04-12-03 (a second store handle from an intent) -- mitigated structurally by `IntentStoreAccess`'s path-free API surface; proven by `testTheIntentReachesTheStoreThroughIntentStoreAccessNeverConstructingASecondHandle`.
- T-04-12-04 (an intent stranding a durable draft) -- mitigated by never touching `capture_draft`; proven by `testAnIntentPerformedWithANonemptyDraftPresentLeavesTheDraftIntact`.
- T-04-12-05 (an intent bypassing command byte/fingerprint derivation) -- mitigated by invoking the identical `OutboundCommands` producer; proven by `testCaptureIntentProducesTheSameCommandBytesFingerprintAndDurableCommitAsOutboundCommandsCapture`.
- T-04-12-06 (a non-functional affordance implying a deferred surface) -- mitigated by the D-36 source scan in both the plan's own `<verify>` and `IntentPrivacyTests`.
- T-04-12-07 (Spotlight-indexed task content, accepted per the plan's own threat register) -- unchanged; Phase 4 ships no Spotlight-index surface.

## Self-Check: PASSED

- `[ -f apps/ios/Sources/KeeplingCore/AppIntents/CaptureTaskIntent.swift ]` -- FOUND
- `[ -f apps/ios/Sources/KeeplingCore/AppIntents/CompleteTaskIntent.swift ]` -- FOUND
- `[ -f apps/ios/Sources/KeeplingCore/AppIntents/KeeplingShortcuts.swift ]` -- FOUND
- `[ -f apps/ios/Sources/KeeplingCore/AppIntents/IntentStoreAccess.swift ]` -- FOUND
- `[ -f apps/ios/Tests/AppIntentsTests/CaptureIntentTests.swift ]` -- FOUND
- `[ -f apps/ios/Tests/AppIntentsTests/CompleteIntentTests.swift ]` -- FOUND
- `[ -f apps/ios/Tests/AppIntentsTests/IntentPrivacyTests.swift ]` -- FOUND
- `[ -f tooling/ios-lanes/app-intents.mjs ]` -- FOUND
- `git log --oneline --all --grep="04-12"` returns 2 commits -- FOUND (`d266dcf`, `039f183`)
- Re-ran plan-level `<verification>`:
  - `node tooling/verify-ios-phase.mjs --lane app-intents` -- PASS (cases=5 reported by the parser's first-match convention; all 14 tests across the three classes independently confirmed passing via direct `xcodebuild test`)
  - `node -e` deferred-surfaces check (`deferred surfaces genuinely absent`) -- PASS, reproduced in this session
  - `node -e` App-Group/path-init check (`intents share one in-process store handle`) -- PASS, reproduced in this session
  - Full `xcodebuild test -only-testing:AppIntentsTests` -- 14/14 PASS
  - Regression check against `core-loop` (04-09) and `undo` (04-11) lanes -- both PASS, zero regressions from the `KeeplingApp.swift` refactor

---
*Phase: KPL-04-native-iphone-daily-loop*
*Plan: 12*
*Completed: 2026-09-05*
