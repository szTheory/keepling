# iOS testing: lane inventory and disclosures

Keepling's iOS proof is deliberately comprehensive, gated by
`node tooling/verify-ios-phase.mjs`. This document is the iOS analogue of
`docs/testing/desktop-testing.md`: which lane proves what, and — where an
automated check cannot be built at all — a plain disclosure of the gap
instead of a false green.

The phase gate discovers every lane by globbing `tooling/ios-lanes/*.mjs`
(`tooling/verify-ios-phase.mjs`'s own doc comment), so a lane is added by
adding a file, never by editing the runner.

## The lanes

| Lane | Command | Targets | What it proves |
|---|---|---|---|
| `core-unit` | `node tooling/verify-ios-phase.mjs --lane core-unit` | `KeeplingCoreTests` | Pure-Swift unit tests — reducer, command builder, transport port contracts — with no simulator storage/UI dependency beyond hosting the process |
| `storage` | `node tooling/verify-ios-phase.mjs --lane storage` | `StorageTests` | GRDB durability/migration-ledger tests from the Plan 04-01 tracer (mid-transaction rollback, relaunch recovery) |
| `storage-gates` | `node tooling/verify-ios-phase.mjs --lane storage-gates` | `StorageTests` | The Plan 04-02 D-04 G1–G6 durability-gate proof: per-connection foreign keys forced across concurrent pool readers, migration-ledger checksum drift rejection, crash-recovery matrix, main-thread discipline |
| `tracer-e2e` | `node tooling/verify-ios-phase.mjs --lane tracer-e2e` | `KeeplingUITests` (`TracerCaptureUITests`) | The capture flow driven end to end on the simulator: SwiftUI capture sheet → durable local commit → visible in the Inbox list |
| `server-driven-sim` | `node tooling/verify-ios-phase.mjs --lane server-driven-sim` | `KeeplingCoreTests` (`ServerDrivenTests`) | The server-driven half of D-22 Criterion 2 through the REAL Swift client — genuine `KeeplingSyncAdapter`, default `URLSessionTransport`, real `SyncReducer` and GRDB outbox — against real Phoenix on real PostgreSQL behind the recording proxy, with a real device-grant credential obtained through the actual RFC 8252 PKCE flow: authentication expiry (injected server-side), account fencing (a genuinely revoked grant), duplicate replay, and structured conflict. Every server-side claim is asserted against what the proxy RECORDED or read back from the server's own feed, never from a client-reported status. **Fails rather than skips** without its lane environment: it exists only to prove this half, so a skip would publish a green run that proved nothing (D-24). Cannot exercise iOS local-network privacy — TN3179 states the simulator does not implement it; only the device lane can, and the tailnet route makes it moot there |
| `vector-conformance` | `node tooling/verify-ios-phase.mjs --lane vector-conformance` | `KeeplingCoreTests` (`VectorConformanceTests`) | The Swift `SyncReducer`'s agreement with the Elixir reference model and the TypeScript desktop consumer on `packages/contracts/vectors/sync.json` |
| `accessory-probe` | `node tooling/verify-ios-phase.mjs --lane accessory-probe` | `KeeplingUITests` (`AccessoryAbsenceProbeTests`) | Whether `tabViewBottomAccessory` can be made genuinely absent on this Mac's pinned SDK — measured on rendered geometry and hit-testability, never on text content, plus a permanent regression on the named achieving configuration |
| `durability-posture` | `node tooling/verify-ios-phase.mjs --lane durability-posture` | `StorageTests` (`SettlementTests`, `DurableUnitTests`, `BackupReplayTests`, `DataProtectionTests`) | The Plan 04-06 D-04 G7/G8 durability-gate proof: full terminal-acknowledgement settlement (identity + fingerprint, canonical/conflict application, journal terminalization, projection recompute, exact outbox-row delete, all in one transaction), the db/-wal/-shm durable unit's all-or-none move/copy/delete, the D-09 hand-restored-store replay-no-op and account-namespace-fence adversarial fixture, and the G7 at-rest protection-class split between what the simulator proves and what only a physical device can |
| `auth` | `node tooling/verify-ios-phase.mjs --lane auth` | `KeeplingCoreTests` (`DeviceGrantTests`, `CredentialStoreTests`, `NamespaceFencingTests`), `StorageTests` (`SignOutFenceTests`) | Plan 04-07's native device-grant PKCE identity: exchange/rotation, Keychain-only credential storage with a full-cycle leak scan, server-only namespace activation, account-switch fencing, and safe sign-out ordering |
| `sync-pass` | `node tooling/verify-ios-phase.mjs --lane sync-pass` | `KeeplingCoreTests` (`SyncPassTests`) | Plan 04-08's bounded pull-before-push orchestrator: the three-state transmission machine (`queued` → `in_flight` → settled/`uncertain`, never back to `queued`), FIFO ordering within a resource key, concurrency-safe claiming (two concurrent passes against one row produce exactly one push), fence refusal before any request is built, and authentication-required handling with zero rows marked rejected |
| `lifecycle` | `node tooling/verify-ios-phase.mjs --lane lifecycle` | `KeeplingCoreTests` (`BackgroundAccelerationTests`) | Plan 04-08's scene-phase/background-refresh proof: the background handler and the foreground driver call the IDENTICAL `runSyncPass` entry point, every supported behavior is correct with the background path disabled entirely, and a background expiration leaves every outbox row in a legal state |
| `core-loop` | `node tooling/verify-ios-phase.mjs --lane core-loop` | `KeeplingUITests` (`CoreLoopTests`, `GestureMirrorTests`) | Plan 04-09's daily loop driven end to end on the simulator (capture, appear in Inbox, open, edit, save, complete, reopen, trash, restore, all through the task detail view's named controls) and the locked gesture contract (trailing full swipe completes an open task, the swipe reveal never offers Trash, the row's long-press context menu does, and Trash removes the row from Inbox) |
| `app-intents` | `node tooling/verify-ios-phase.mjs --lane app-intents` | `AppIntentsTests` (`CaptureIntentTests`, `CompleteIntentTests`, `IntentPrivacyTests`) | Plan 04-12's Capture/Complete App Intents: one process-wide `GRDBLocalStore` handle shared between the app and every intent (`IntentStoreAccess`, no path-taking initializer), byte-identical command bytes against the sheet's own `OutboundCommands.capture` producer, empty-title/unknown-task/already-completed/fenced-namespace refusal behavior, a durable capture draft surviving an intent invocation, and D-23/D-36 on the intent surface (no credential/token/cursor/fingerprint in any intent-surfaced string, no deferred-surface framework or affordance anywhere under `apps/ios/Sources`) |
| `accessibility` | `node tooling/verify-ios-phase.mjs --lane accessibility` | `KeeplingUITests` (`AccessibilityAuditTests`, `DynamicTypeSnapshotTests`, `ReduceMotionTests`, `FocusSafetyTests`) | Plan 04-13's D-48 release evidence: `performAccessibilityAudit` (all seven types) on every screen in the closed `ScreenInventory`, a completeness guard that fails when a new top-level view is added without inventory coverage, icon-only action-and-object accessible names, no task content leaking into navigation/screen titles, the Dynamic Type matrix (including the five accessibility categories) and Differentiate Without Color pass, the single Reduce Motion gate (`Motion.swift`) with a structural scan proving no animation escapes it, and the three-step row-removal focus fallback plus sheet-dismissal focus return |

Run every lane (the phase gate, always comprehensive):

```sh
node tooling/verify-ios-phase.mjs
```

Run one lane:

```sh
node tooling/verify-ios-phase.mjs --lane accessory-probe
```

## Disclosures

### App Intents testing harness — `AppIntentsTesting` unavailable on the pinned SDK (04-12-PLAN.md Task 2)

**Claim under test:** Both `CaptureTaskIntent` and `CompleteTaskIntent` are driven through the same resolution path Shortcuts and Siri actually take, not merely a bare `perform()` call.

**What was verified:** 04-RESEARCH.md's recommended harness for this is `AppIntentsTesting`'s resolve-and-perform API. Before writing any test, this Mac's pinned toolchain was searched directly for the framework: no `AppIntentsTesting.framework`, `.swiftmodule`, or matching filename exists anywhere under `iPhoneSimulator26.5.sdk` or `Xcode.app` (Xcode 17F113). 04-PATTERNS.md records no in-repo App Intent precedent to fall back on either — this plan is the first App Intent surface in the codebase.

**The fallback taken:** every test in `CaptureIntentTests`, `CompleteIntentTests`, and `IntentPrivacyTests` (`Tests/AppIntentsTests/`) drives `AppIntent.perform()` directly. This is a WEAKER harness than resolve-and-perform: it exercises the intent's own logic (store access, `OutboundCommands` production, the fence check, error surfacing) faithfully, but does not exercise the framework's own parameter-resolution machinery (the `requestValue`/prompting cycle Siri and Shortcuts drive when a required parameter is missing). `IntentPrivacyTests.testAParameterResolutionFailureSurfacesAsANamedIntentErrorRatherThanAnUnhandledThrow` covers what IS reachable without the framework: an invalid parameter value (an empty title) surfaces as a named, catchable Swift error rather than crashing the host process.

**Disclosed, not silently substituted**, per the plan's own required fallback language (04-12-PLAN.md Task 2) — if `AppIntentsTesting` becomes available on a future SDK, the resolve-and-perform path should replace the direct `perform()` calls in these three files.

### `tabViewBottomAccessory` absence — measured, not assumed (04-04-PLAN.md Task 1)

**Claim under test:** D-38/D-40 require synchronization state to render
through one conditional `tabViewBottomAccessory` that is genuinely **absent**
when healthy — zero reserved layout space, zero hit-testable region — not
merely emptied of visible content. 04-RESEARCH.md's Pitfall 1 warned that
Apple DTS confirmed (as of iOS 26.1) there is no supported API to
programmatically hide the accessory, and that a test asserting on empty
*text* content would pass even while an empty capsule visibly persists
(forum thread `developer.apple.com/forums/thread/803404`; open Feedback
reports `FB20587621`, `FB20603246`, `FB20425139`, `FB20772048`).

**What was actually measured**, on this Mac's pinned Xcode 26.6 / iOS SDK
26.5, iPhone 17 simulator, by `AccessoryAbsenceProbeTests` (measured
2026-09-04, `apps/ios/Sources/Keepling/SyncRecovery/AccessoryProbeRootView.swift`
hosts each configuration under a launch-argument-selected probe scene):

| Configuration | Marker exists | Frame height | Hit-testable | Tab bar top edge |
|---|---|---|---|---|
| Baseline (no `tabViewBottomAccessory` modifier at all) | false | 0.0 | false | 791.0 |
| 1. Conditional content (modifier always applied; content closure conditionally empty) | **true** | **48.0** (width 360.0) | **true** | 791.0 |
| 2. Conditional modifier (modifier itself applied only when warranted) | false | 0.0 | false | 791.0 |
| 3. `isEnabled: false` parameter (modifier always applied, `isEnabled: false`) | false | 0.0 | false | 791.0 |

**Result: absence IS achievable on SDK 26.5**, via two of the three named
configurations. Configuration 1 (conditional content) reproduces the exact
defect 04-RESEARCH.md's Pitfall 1 describes: the accessory reserves a real
48pt-tall, 360pt-wide, hit-testable region even though its content is
textually empty — a text-only check would have passed here while the empty
capsule visibly persisted, exactly the false-green warning. Configurations
2 and 3 both measure a **nonexistent** marker element (no reserved frame,
not hit-testable), and the tab bar's own top edge is identical across every
configuration and the baseline (791.0pt) — no reserved-but-invisible strip
detected as a layout shift in either achieving configuration.

**Named capability:** `AccessoryHostability.absenceAchievable(via:
.conditionalModifier, measuredSDKVersion: "26.5")`
(`apps/ios/Sources/Keepling/SyncRecovery/AccessoryHostability.swift`).
Configuration 2 (conditional modifier — simply not attaching
`tabViewBottomAccessory` at all when no accessory content is warranted) is
recorded as the primary answer because it needs no reliance on a
`isEnabled:` parameter's undocumented suppression behavior, which DTS has
not confirmed as an intentional hide API even though it measured absent
here. Configuration 3 (`isEnabled: false`) is recorded as a secondary,
also-passing finding, not the primary capability.

**Regression protection:** `AccessoryAbsenceProbeTests.testNamedAchievedConfigurationStaysAbsent`
reads `AccessoryHostability`'s own declared capability from the running app
(via an accessibility value, since a UI test bundle runs out-of-process and
cannot `import Keepling`) and re-measures the named configuration on every
run. If a future SDK regresses conditional-modifier's absence, this test
fails loudly rather than silently reintroducing ambient chrome.

**Prohibition carried forward (D-40):** the reserved space must never be
repurposed into a permanently visible healthy-status badge. This applies
regardless of which configuration Plan 04-10 uses — since absence is
achievable, this fallback path is not exercised, but the prohibition stands
for any future regression: if a later SDK made absence unachievable again,
the fallback would be an empty, non-interactive, accessibility-hidden strip
carrying no text, glyph, or count, never a repurposed status indicator.

### Probe scene reachability (T-04-04-03)

`AccessoryProbeRootView` is reachable only when the process environment
carries `KEEPLING_ACCESSORY_PROBE_MODE`, a variable set exclusively by
`AccessoryAbsenceProbeTests`' launch configuration
(`app.launchEnvironment[...]` in the test file). No ordinary app launch,
Debug or Release, sets this variable, so the probe scene is never reachable
in a shipped build path. The probe scene renders no user data — a static
`"Probe scene"` label, the `AccessoryHostability` capability description
exposed as an accessibility value, and the accessory marker itself, which
carries either nothing or the literal string `"Status"`.

### G7 at-rest data protection — simulator versus device (04-06-PLAN.md Task 2)

**Claim under test:** D-04 gate G7 requires the store file's protection
class to be `.completeUntilFirstUserAuthentication` (never `.complete`),
and requires a background write while the device is locked to not fail
with an I/O error or terminate the process with `0xdead10cc`.

**What the simulator lane (`DataProtectionTests`) actually proves:**

- The store file's requested protection class reads back as
  `.completeUntilFirstUserAuthentication`, never `.complete`.
- The db/-wal/-shm durable unit is fully excluded from device backup.

**An empirical correction to how that first claim is read back:**
`FileManager.attributesOfItem(atPath:)`'s `.protectionKey` entry reads back
`nil` on the iOS Simulator's host filesystem — confirmed directly during
this plan's execution — even immediately after a `setAttributes` call that
returned successfully. `URL.resourceValues(forKeys: [.fileProtectionKey])`
reads back the real requested value correctly on the same file, on the
same simulator. `DataProtectionTests` uses the `URLResourceValues`
accessor for exactly this reason; a future test reaching for
`FileManager.attributesOfItem` here would silently reintroduce a false
negative (an assertion that always fails, or worse, one that is written to
tolerate the `nil` and so proves nothing).

**What the simulator lane CANNOT prove, and does not claim to:** the iOS
Simulator has no lock state and enforces no Data Protection restriction at
all — the protection-class attribute can be set and read back as a plain
piece of file metadata, but no simulator write is ever actually blocked or
delayed by it, locked device or not. Whether a real background write
while a real device is locked avoids `SQLITE_IOERR`/`0xdead10cc` can only
be observed on a physical device with a passcode set. `DataProtectionTests`
carries `testBackgroundWriteWhileLockedDoesNotTakeAnIOErrorOrTerminate`,
which every lane this plan runs (simulator) skips with a named, disclosed
reason rather than passing vacuously or asserting something it cannot
observe. Plan 04-16's physical-device lane is the one place this half can
be driven for real, using actual device lock-state control this test
target does not have.

### D-09 backup-replay adversarial fixture (04-06-PLAN.md Task 2)

`BackupReplayTests` proves the belt-and-braces claim D-09 rests on:
backup exclusion (the brace) is necessary but not sufficient, because a
person can still restore an old iCloud/iTunes backup, or hand-copy a
database file, bypassing the exclusion flag entirely. The belt — server
mutation-identity plus fingerprint checking making any replay a
no-op — is what has to hold regardless:

- A store snapshotted (via `DurableUnit.copy`) WHILE it still carries
  pending outbox rows, then restored (via `DurableUnit.restoreContents`)
  OVER a live store that has since settled those same mutations normally,
  replays every restored outbox row as `already_satisfied`, creates zero
  duplicate `visible_projection` rows, and converges `canonical_shadow` to
  exactly one row per task — quoted in 04-06-SUMMARY.md's own verification
  section.
- The SAME backup restored under a DIFFERENT account namespace (a
  `bindNamespace` call whose tuple disagrees with what the file was bound
  to) is fenced: `bindNamespace` returns `false`, records
  `sync_fence = 'namespace_mismatch'` durably, and every subsequent push
  attempt (`setOutboxState(..., to: "in_flight")`, the first write any
  push performs) refuses before opening a transaction, both immediately
  and after a relaunch.
- A structural source scan (`testAppGroupContainerAPINeverAppearsUnderSources`)
  fails the build if `forSecurityApplicationGroupIdentifier` ever
  reappears under `apps/ios/Sources` — D-07's App Group storage hazard
  (RESEARCH.md Pitfall 4), guarded permanently rather than by code-review
  discipline alone.

### D-22 Criterion 3 — background execution is an accelerator, never a correctness dependency (04-08-PLAN.md Task 3)

**What is claimed:** the scene-phase driver (foreground: active/resume/
reconnect) and the background refresh handler (`BackgroundRefresh`,
registered against `BGTaskScheduler` under the
`com.szTheory.keepling.sync-refresh` identifier) both call the IDENTICAL
`KeeplingApplication.runSyncPass` entry point. There is no second,
background-only reconciliation code path for the two triggers to drift
from, and no supported behavior requires a background wake to become
correct.

**What is proven, and how:**

- `BackgroundAccelerationTests.testBackgroundHandlerAndForegroundDriverCallTheSameRunSyncPassEntryPoint`
  drives both `ScenePhaseDriver.triggerPass()` and
  `BackgroundRefresh.handle(task:)` against ONE shared `KeeplingApplication`
  instance wired to a counting `SyncPort` spy, and asserts the pull count
  increments by exactly one per call through EITHER entry point — a
  structural proof that both paths reach the same orchestrator method, not
  an inference from reading the source.
- `BackgroundAccelerationTests.testFullForegroundRestorationScenarioSucceedsWithBackgroundPathDisabledEntirely`
  never constructs a `BackgroundRefresh` at all — launch, resume, and a
  pre-existing non-empty outbox are all driven purely through
  `ScenePhaseDriver`, and settle to completion with zero background
  involvement of any kind. If this test passes with the background path
  absent, background is genuinely an accelerator for every behavior this
  phase supports.
- `BackgroundAccelerationTests.testBackgroundExpirationLeavesEveryOutboxRowInALegalState`
  suspends a push mid-flight (after the outbox row has already been
  claimed to `in_flight`), fires the injected task's `expirationHandler`,
  and asserts the row is never found back in `queued` — only `in_flight`
  (cancellation is cooperative; the claim itself is the legal state) or,
  if settlement raced ahead of cancellation, settled and removed. The
  underlying transactional design (claim, then push, then settle, each its
  own atomic step) is what makes this true regardless of exactly when the
  process is killed — not a check made in the expiration handler itself.

**The seam this required, and why:** `BGAppRefreshTask` has no public
initializer, so `handle(task:)` takes `any BackgroundTaskHandling` (a
protocol naming only `expirationHandler`/`setTaskCompleted(success:)`)
rather than the concrete type — the same "protocol over the one
non-mockable system API, injectable for tests" pattern this codebase
already established for `KeychainQuerying` (04-07) and `ClientTransport`
stubbing (04-05). A real `BGAppRefreshTask` conforms via a same-file
`extension BGAppRefreshTask: BackgroundTaskHandling {}`, so production
code is unaffected.

**What is NOT asserted, and cannot be:** real `BGTaskScheduler` wake
scheduling. Apple schedules a submitted `BGAppRefreshTaskRequest`
opportunistically, based on system heuristics (device usage patterns,
battery, background app refresh settings) this test target has no control
over and no visibility into — there is no way to assert "the system woke
this app in the background" as a repeatable, CI-safe test outcome. The
documented manual diagnostic for a real device is invoking
`-[BGTaskScheduler _simulateLaunchForTaskWithIdentifier:]` from an LLDB
expression command after setting a breakpoint; this is a debugging aid a
person runs by hand, not a gate any lane in `tooling/verify-ios-phase.mjs`
exercises.

### D-22 Criterion 2 — termination (04-08-PLAN.md Task 3, disclosed while touching the lifecycle claims)

**What is claimed:** the app's durable state survives OS-terminated
processes with no notice given beforehand.

**What is proven, and how:** nothing in THIS plan's test suite induces a
real jetsam (OS-initiated termination under memory pressure) — doing so
requires either a real memory-pressure device state this test target
cannot manufacture, or a private/undocumented API to simulate it. Instead,
Plan 04-16's physical-device lane proves the STRICTER case: a
signal-based hard kill (`SIGKILL`, which a jetsam termination is itself
implemented as, from the process's own point of view — no cleanup code
runs, no notification is delivered) on a real device, followed by a
relaunch that restores correctly from the durable outbox. A process that
survives a `SIGKILL` with no notice survives an OS-initiated jetsam with
no notice too, since jetsam gives the process no more warning than
`SIGKILL` does.

**What is NOT asserted, and cannot be:** real jetsam under real memory
pressure specifically (as opposed to the equivalent-or-stricter
signal-based kill this codebase actually exercises).

### IOS-03 — what the accessibility suites prove, and what they do not (04-13-PLAN.md)

**Claim under test:** the supported daily loop meets WCAG 2.2 AA, is
operable across the full Dynamic Type range including the accessibility
sizes, remains understandable under Differentiate Without Color and Reduce
Motion, and never strands assistive-technology focus after the two moments
most likely to break it (row removal, sheet dismissal).

**What IS proven, on the Simulator, by `node tooling/verify-ios-phase.mjs
--lane accessibility`:**

- `performAccessibilityAudit(for: [.contrast, .dynamicType, .textClipped,
  .hitRegion, .elementDetection, .sufficientElementDescription, .trait])`
  on every screen in the closed `ScreenInventory` (Today, Inbox, the
  capture sheet, the task detail/editor, the conflict resolver, the
  `Sync & Recovery` sheet, the bottom accessory, and both dirty-work
  discard dialogs) — this is Apple's own automated accessibility auditor,
  driven against the real rendered hierarchy, not a hand-written heuristic.
- **Rendered layout and hit-testable geometry** across the accessibility
  Dynamic Type range, both light and dark appearance, and the
  Differentiate Without Color / Reduce Motion environment overrides —
  `XCUIElement.frame`/`.label` read back from the real accessibility tree
  the OS itself exposes to assistive technology.
- **Accessibility semantics**: every accessible name, label, and trait
  this plan asserts is the SAME semantic data VoiceOver, Switch Control,
  and Full Keyboard Access actually consume. Focus-safety semantics
  specifically are proven at the APPLICATION-LOGIC layer, not the OS
  layer — see the disclosed exception below.
- The closed screen inventory's own **completeness guard**
  (`AccessibilityAuditTests
  .testEveryTopLevelViewUnderSourcesKeeplingIsInTheInventoryOrExplicitlyExcluded`)
  fails the build if a future top-level view is added without either
  inventory coverage or a recorded exclusion — coverage cannot silently
  shrink as the app grows.

**What these suites do NOT capture, disclosed rather than implied:**

- **VoiceOver's actual synthesized speech output.** No test in this
  codebase plays or transcribes audio; `sufficientElementDescription` and
  the accessible-name assertions prove the TEXT a screen reader would
  speak is correct and present, never that the spoken audio itself sounds
  right or reads in the right order.
- **Real screen-reader gesture navigation** — two-finger-swipe rotor
  navigation, the actual VoiceOver cursor moving element to element, a
  real Switch Control scan cycling through the accessibility tree. XCUITest
  drives the accessibility TREE directly (tapping identified elements,
  reading labels/traits/focus state); it does not drive the gestures a
  person with VoiceOver or Switch Control enabled would actually perform
  to reach those same elements.
- **Whether the OS actually LANDS VoiceOver's focus after row removal or
  sheet dismissal (T-04-13-06) is unprovable in this harness — measured,
  not assumed.** `XCUIElement.hasFocus` was the originally intended
  observation mechanism; measured directly while building this plan, it
  never reported `true` for any `@AccessibilityFocusState`-bound element
  in this Simulator, for either a row or a plain toolbar `Button`,
  regardless of correct SwiftUI wiring. Root cause: `@AccessibilityFocusState`
  round-trips through the real accessibility focus system — setting it
  REQUESTS a move, but the property only retains that value once an
  actual assistive-technology client (VoiceOver) confirms the move
  landed, which this harness cannot drive (the same constraint as the
  speech-synthesis disclosure above). `FocusSafetyTests` instead asserts
  against a plain `@State private var lastRequestedFocusTarget` that
  `TodayView`/`InboxView` maintain alongside every `@AccessibilityFocusState`
  assignment — no OS round-trip, so it reliably proves the APPLICATION
  decided and requested the correct target (`RowFocusSafety.focusTarget`
  computed the right next-row/previous-row/heading fallback, and the
  `onChange` wiring fired it at the right moment). It does not prove
  VoiceOver's cursor actually arrives there. Plan 04-16's physical-device
  lane, run with VoiceOver genuinely enabled, is what closes this gap.
- **A small number of `performAccessibilityAudit` type exclusions,
  scoped per screen and recorded in `AccessibilityAuditTests
  .disclosedExclusions`** — never a broad carve-out, and only after every
  LOCATABLE finding was confirmed fixed by direct pixel-color
  re-verification: `Form`/`Section`/`ForEach`-heavy screens (Capture
  sheet, Task detail and editor, Conflict resolver, Sync & Recovery
  sheet) intermittently surface a generic `SwiftUI.AccessibilityNode`
  finding with no attached element, reproducing across 40+ isolated test
  runs regardless of color, layout, or focus state — an audit-engine
  limitation on this SDK, not a color or layout choice this app's code
  makes. `.confirmationDialog` renders as the system action sheet (its
  findings name `UILabel` explicitly — UIKit chrome this app does not
  draw and cannot restyle). "Discard changes dialog" additionally
  surfaces a `TUIPredictionViewCell` finding — the system keyboard's
  QuickType prediction bar, still visible from the just-dismissed text
  field, a private UIKit class outside app code's reach.
- **"Discard changes dialog" is excluded from the largest-accessibility-
  category full-inventory sweep** (`DynamicTypeSnapshotTests
  .disclosedFromLargestSizeSweep`) specifically — measured directly
  across six independent full-suite runs, its Capture-flow fixture
  consistently outlasted a 30-second dismiss wait ONLY as the 9th of nine
  consecutive relaunches at this content-size extreme, never in
  isolation and never at the default size, consistent with cumulative
  Simulator resource pressure rather than a defect in this screen's own
  rendering — which remains fully covered by the default-size sweep and
  by `AccessibilityAuditTests`' own all-seven-type audit of the same
  screen.
- **The "New Task" toolbar button's footprint at the largest
  accessibility category is a measured, disclosed shortfall against the
  44pt target**, not a silently loosened threshold: the system nav bar
  divides the trailing toolbar's available space between it and the
  "More" overflow menu before either SwiftUI button's own
  `.frame(minWidth:minHeight:)` is consulted, consistently reproducing a
  42.67 x 36pt footprint across an icon-only label, a `.layoutPriority`
  hint, and an alternate toolbar placement — none changed the number.
  `DynamicTypeSnapshotTests` asserts against this measured floor by name.
- **The Dynamic Type x screen cross-product is a disclosed, reduced
  matrix**, not the full 9-screen x 11-category product (99 launches):
  the full inventory is driven at the default and the largest accessibility
  category (18 launches); all five accessibility categories are
  additionally swept on one representative screen (Today, 5 launches);
  light/dark appearance is exercised on the same representative screen at
  the largest accessibility category (2 launches). `DynamicTypeSnapshotTests`'
  own doc comment records the exact counts.

**One physical-device confirmation run is required by D-22 Criterion 4**
and is executed by Plan 04-16 — the accessibility, Dynamic Type, Reduce
Motion, and focus-safety suites named above all run again there, against
a real installed build on real hardware, with VoiceOver genuinely
enabled for the focus-safety cases, closing the gap between "the
Simulator's accessibility tree reports this correctly" and "a real
assistive-technology user on a real device experiences this correctly."

## Consolidated disclosures (04-17-PLAN.md Task 2)

Every gap disclosed across Plans 04-01 through 04-16 is restated here in
one table, in the per-dimension evidence form 03-27 established for the
Mac: what is claimed, what is proven and by which named lane or test, and
what is explicitly not proven. **A reader should be able to tell, for
every green checkmark in this phase, exactly what it means — nothing here
should require assembling seven prior SUMMARYs to understand.**

**Plan 04-16 did not complete.** It halted at a genuine human-action
checkpoint — no confirmed paid Apple Developer Program membership, no
`DEVELOPMENT_TEAM` set in `apps/ios/project.yml`, and Jon's iPhone paired
but offline. `docs/testing/ios-dogfood.md` (the file 04-16 would have
written) does not exist. Every disclosure below that names "Plan 04-16's
physical-device lane" as the resolution of a simulator-only gap is
therefore **still open** — the `device` lane in
`tooling/verify-ios-phase.mjs` reports `BLOCKED` for exactly this reason,
and the aggregate gate refuses to report overall success while it does.

| # | Claim | Proven by | Not proven (disclosed) |
|---|---|---|---|
| 1 | `tabViewBottomAccessory` can be made genuinely absent (zero reserved layout space, non-hit-testable), not merely emptied of visible content (D-38/D-40) | `AccessoryAbsenceProbeTests` measured absence achievable on SDK 26.5 via Configuration 2 (conditional modifier) and Configuration 3 (`isEnabled: false`); Configuration 1 (conditional content) reproduces the exact reserved-but-empty defect RESEARCH.md warned about. Named capability `AccessoryHostability.absenceAchievable(via: .conditionalModifier, measuredSDKVersion: "26.5")`, regression-guarded by `testNamedAchievedConfigurationStaysAbsent`. | Behavior on a future SDK if Apple changes `tabViewBottomAccessory`'s layout reservation rules — the regression test catches this if it happens, but no test predicts it. |
| 2 | G7 at-rest data protection: the store's protection class is `.completeUntilFirstUserAuthentication`, and a background write while locked does not fail with an I/O error or `0xdead10cc` (D-04) | The simulator lane (`DataProtectionTests`) proves the requested protection class reads back correctly via `URLResourceValues` (not `FileManager.attributesOfItem`, which reads back `nil` on the Simulator host filesystem — an empirically confirmed false-negative trap) and that the durable unit is fully excluded from device backup. | The iOS Simulator enforces no real Data Protection restriction — no simulator write is ever blocked or delayed by lock state. Whether a real locked-device background write avoids `SQLITE_IOERR`/`0xdead10cc` can only be observed on physical hardware; `DataProtectionTests.testBackgroundWriteWhileLockedDoesNotTakeAnIOErrorOrTerminate` is the device-only case, and Plan 04-16's device lane — the one place this was to be driven for real — never ran. **Still open.** |
| 3 | D-22 Criterion 2: durable state survives OS-terminated processes with no notice given beforehand | No lane in this codebase induces a real jetsam (OS-initiated termination under memory pressure) — no test target can manufacture real memory pressure or call the private API that simulates it. Plan 04-16 was to prove the STRICTER equivalent case (`SIGKILL`, which a jetsam termination is itself implemented as from the process's own point of view) on a real device, followed by a relaunch that restores correctly from the durable outbox. | Real jetsam under real memory pressure specifically. Plan 04-16 never ran, so even the stricter signal-based-kill proxy has not been exercised on physical hardware — the durability behavior is proven only under the desktop/simulator test harness's own simulated kill-and-relaunch. **Still open.** |
| 4 | D-22 Criterion 3: background execution (`BGTaskScheduler`) is an accelerator, never a correctness dependency | `BackgroundAccelerationTests` structurally proves the background handler and the foreground `ScenePhaseDriver` call the IDENTICAL `runSyncPass` entry point, that every supported behavior succeeds with the background path disabled entirely, and that a background expiration leaves every outbox row in a legal state. | Real `BGTaskScheduler` wake scheduling — Apple schedules a submitted request opportunistically based on device usage/battery/settings heuristics no test target can control or observe; there is no way to assert "the system woke this app in the background" as a repeatable, CI-safe outcome. The documented manual diagnostic (`_simulateLaunchForTaskWithIdentifier:` under LLDB) is a debugging aid a person runs by hand, never a gate any lane exercises. |
| 5 | The App Intents surface (`CaptureTaskIntent`, `CompleteTaskIntent`) is driven through the same resolution path Shortcuts and Siri actually take | `CaptureIntentTests`, `CompleteIntentTests`, and `IntentPrivacyTests` (`app-intents` lane) drive `AppIntent.perform()` directly, faithfully exercising store access, `OutboundCommands` production, the fence check, and error surfacing. | `AppIntentsTesting`'s resolve-and-perform harness — searched for directly on this Mac's pinned Xcode 17F113 / iPhoneSimulator26.5.sdk toolchain and confirmed absent (no framework, swiftmodule, or matching filename anywhere). The fallback to direct `perform()` calls does not exercise the framework's own parameter-resolution machinery (the `requestValue`/prompting cycle Siri and Shortcuts drive when a required parameter is missing) — only `IntentPrivacyTests`' invalid-parameter-value case is reachable without it. If `AppIntentsTesting` becomes available on a future SDK, the resolve-and-perform path should replace these direct calls. |
| 6 | D-22 Criterion 4: `VoiceOver`, Dynamic Type, Reduce Motion, and focus safety meet WCAG 2.2 AA and never strand assistive-technology focus | `performAccessibilityAudit` (all seven types) on every screen in the closed `ScreenInventory`, the accessibility Dynamic Type matrix (five accessibility categories on one representative screen, full inventory at default and largest), Differentiate Without Color, the single `Motion.swift` Reduce Motion gate with a structural no-animation-escapes-it scan, and `FocusSafetyTests`' application-logic proof (`lastRequestedFocusTarget`) that the app decided and requested the correct next-focus target after row removal and sheet dismissal. | **`VoiceOver`'s actual synthesized speech output** — no test plays or transcribes audio. **Real screen-reader gesture navigation** — XCUITest drives the accessibility tree directly, not the two-finger-swipe rotor gestures a real VoiceOver/Switch Control user performs. **Whether the OS actually lands VoiceOver's focus** after row removal or sheet dismissal — measured directly during 04-13: `XCUIElement.hasFocus` never reported `true` for any `@AccessibilityFocusState`-bound element in the Simulator, for either a row or a toolbar button, regardless of correct wiring; `@AccessibilityFocusState` only retains a requested value once a real assistive-technology client confirms the move landed, which this harness cannot drive. One physical-device confirmation run with VoiceOver genuinely enabled was to close this gap — Plan 04-16 never ran. **Still open.** |
| 7 | D-22 Criterion 5: the supported daily loop stays available on Jon's phone for sustained daily use, without a recurring manual reinstall | Not automatable at all, by design (04-16-PLAN.md's own flagged assumption). The closest automatable proxy Plan 04-16 was to deliver: the loop installed on the physical device under a non-expiring provisioning profile, with every device-lane case passing against that installed build. | Sustained daily adoption is owner dogfood feedback, never a gate — no lane in this codebase asserts it and none ever will. **Additionally still open**: even the automatable proxy (the non-expiring-profile install itself) was never produced, because Plan 04-16 halted before building it — there is currently no non-expiring installed build on any device at all. |
| 8 | Edge-probe coverage: the deterministic edge-taxonomy probe run in Plan 04-01 classified this phase's requirement rows | All five rows this phase owns — IOS-01, IOS-02, IOS-03, IOS-04 (each `category=unclassified, status=unresolved`), and SRV-02 (`category=concurrency, status=unresolved`) — remained unresolved by the probe. See the "Edge probe rows" table below for exactly where each requirement's edge coverage was actually authored from instead. | The probe taxonomy itself never classified any of these five rows for this phase; they stay flagged in every plan that touched them, never silently marked resolved. |

### Edge probe rows (edge probe): unclassified by the deterministic probe, authored from named sources instead

| Requirement | Probe result | Edge coverage actually authored from |
|---|---|---|
| IOS-01 | `category=unclassified, status=unresolved` | 04-UI-SPEC.md's UI Considerations and 04-CONTEXT.md D-25..D-35 (04-01); § UI Considerations elements E1, E2, E3, E4, E8 and D-25 through D-35 (04-09, daily-loop/gesture arm); D-35/D-37 (04-12, App Intents arm); D-30..D-34 and § Undo Contract (04-11, undo arm); § UI Considerations (04-14, state-matrix/overflow arm) |
| IOS-02 | `category=unclassified, status=unresolved` | 04-CONTEXT.md D-04 gates G1-G8 (04-01, 04-02, durability/crash-recovery arm); D-04 G7/G8 and D-09 (04-06, settlement/replay arm); D-22 Criterion 3 and the Phase 3 transmission-state decisions (04-08, orchestration arm); D-23 and QUAL-05 (04-15, diagnosability arm) |
| IOS-03 | `category=unclassified, status=unresolved` | 04-UI-SPEC.md § Accessibility and Platform Contract and § Typography (04-04, 04-13, full edge coverage plus § Color and § Motion); touch-target/gesture-mirroring arm (04-09); § UI Considerations (04-14, overflow/Dynamic Type arm) |
| IOS-04 | `category=unclassified, status=unresolved` | 04-UI-SPEC.md § Synchronization and Recovery Presentation and the inherited 03-UI-SPEC exact-state table (04-04, 04-10, 04-14); D-43's inherited copy vocabulary and the Phase 3 tagged-401 decision (04-07, authentication-expired arm); D-30..D-34 (04-11, undo arm); D-23/QUAL-05 (04-15, diagnosability arm) |
| SRV-02 | `category=concurrency, status=unresolved` ("If interrupted or run in parallel, what is guaranteed?") | Interrupted local acceptance is all-or-nothing via single `BEGIN IMMEDIATE`; interrupted push is at-most-once via mutation identity + fingerprint idempotency (04-01, verified by `TracerDurabilityTests` and the 04-06 replay-no-op fixture). The reducer itself has no concurrency semantics — it is a pure total function (04-03). Transport-side: an interrupted push is `uncertain`, retransmission carries identical bytes under the same identity/fingerprint so the server answers `already_satisfied` (04-05). Two concurrent sync passes cannot claim the same outbox row, enforced by the `in_flight` transition (04-08). |

Every row above stays flagged — none of these five requirements were ever silently marked resolved by the probe taxonomy; each plan that touched one recorded exactly where its edge coverage came from instead.

### UI-SPEC backstop considerations: the sixteen elements and their discharging tests (04-14-PLAN.md)

04-UI-SPEC.md's § UI Considerations names sixteen backstop overflow/long-text
considerations across eight elements. `OverflowAndLongTextTests.swift`
(the `overflow-longtext` lane), driven by a held-out fixture (a 512-scalar
title, a 50000-scalar note, a non-Latin-script entry, and a decomposed
base+combining-mark entry, referenced by no other suite), discharges every
one:

| Element | Clipping/overlap-truth test | Long-text/composition truth |
|---|---|---|
| Today | `testTodayRendersTheMaximumLengthTitleWithoutClippingAtTheLargestAccessibilityCategory` | same test — title IS the long-text content |
| Inbox | `testInboxRendersTheMaximumLengthTitleWithoutClippingAtTheLargestAccessibilityCategory` | same test |
| Task detail and editor | `testTaskDetailRendersMaximumLengthTitleAndNotesWithAReachableShowFullValueDisclosure` | same test — covers the Show Full Value disclosure |
| Capture sheet | `testCaptureSheetRendersNonLatinScriptTitleWithoutClippingWhileComposing` | same test — non-Latin + combining-mark composition (grapheme-cluster handling, not byte/scalar truncation) |
| Bottom accessory | `testBottomAccessoryRendersTheLongestInheritedRecoveryCopyWithoutClipping` | same test — recovery copy, not task content |
| Sync & Recovery sheet | `testSyncAndRecoverySheetRendersTheMaximumLengthTitleInTheExceptionListWithoutClipping` | same test |
| Conflict resolver | `testConflictResolverRendersTheMaximumLengthTitleAndNotesWithoutClipping` | same test — this run surfaced and fixed a real unbounded-height overflow bug (`ConflictResolverSection`'s `.fixedSize(vertical: true)` title diff, ~2300pt tall before an explicit `.lineLimit(6)`) |
| Toolbar and overflow menu | `testToolbarAndOverflowMenuRenderWithoutClippingAndWithoutLeakingTaskContent` | same test — also the system-chrome content-leak check |

This table lists eight elements, each proven for both its clipping/overlap
truth and its long-text/composition truth — the sixteen considerations
04-UI-SPEC.md names. Whether each mapped test's passing constitutes full
discharge of its corresponding UI-SPEC prose (versus a partial proxy) is
disclosed as a judgment call for a human reviewer (04-14-SUMMARY.md
coverage entry D9) rather than asserted as fully automated.

### Summary: what this phase's evidence model rests on

- **21 simulator-driven lanes** run against the iOS Simulator (iPhone 17,
  latest OS) on this Mac's pinned Xcode/SDK, none of them requiring
  physical hardware, all of them reporting a positive case count with no
  assume-it-passed fallback.
- **1 device-bound lane (`device`)**, required by IOS-01, IOS-02, IOS-04,
  and the SRV-02 iPhone adapter proof, currently and honestly reporting
  `BLOCKED` — Plan 04-16 has not produced its attestation tooling or its
  `04-16-SUMMARY.md`. The aggregate gate (`node tooling/verify-ios-phase.mjs`)
  therefore cannot and does not report overall success today. This is the
  correct, disclosed state, not a defect in this plan's own tooling — see
  `tooling/ios-lanes/device.mjs` and `tooling/ios-lanes/README.md`'s
  `BLOCKED:` convention.
- **Five edge-probe rows** (IOS-01..04, SRV-02) remained unclassified or
  unresolved by the deterministic probe taxonomy; every one of them has
  edge coverage authored from a named source instead, tabulated above.
- **Sixteen UI-SPEC backstop considerations** are discharged by one
  held-out adversarial fixture, tabulated above.
