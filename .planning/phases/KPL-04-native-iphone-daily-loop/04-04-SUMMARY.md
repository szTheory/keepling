---
phase: KPL-04-native-iphone-daily-loop
plan: 04
subsystem: ios
tags: [swiftui, tabviewbottomaccessory, design-tokens, xcuitest, accessibility]

requires:
  - phase: KPL-04-01
    provides: the scaffolded apps/ios Xcode project, tooling/verify-ios-phase.mjs's lane-discovery gate, and the tracer's KeeplingApp.swift/RootView.swift this plan extends with a probe-scene route
provides:
  - An executable, committed measurement of whether tabViewBottomAccessory can be genuinely absent on this Mac's pinned iOS SDK 26.5, asserting on rendered frame height and hit-testable region rather than text content
  - A single named capability constant (AccessoryHostability) that Plan 04-10 reads to decide how to render synchronization state, with a permanent regression test protecting the finding
  - A mechanical, diff-checked Swift design-token emitter (tooling/emit-swift-tokens.mjs) producing a committed GeneratedTokens.swift with runtime-resolved light/dark colors
  - A hand-written, literal-free TokenSemantics.swift accessor layer every later iPhone view will consume
  - docs/testing/ios-testing.md, the iOS lane inventory and disclosures document
affects: [04-10, 04-13, 04-16]

actuals:
  tokens: 13151
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Launch-argument-selected probe scene (KEEPLING_ACCESSORY_PROBE_MODE) hosting each SwiftUI configuration under test, read by AccessoryAbsenceProbeTests via app.launchEnvironment -- reusable whenever a future SDK-behavior question needs a same-process empirical measurement rather than an assumption"
    - "Accessibility-value bridge (AccessoryHostability.probeDescription exposed on a StaticText) for a UI test bundle (a separate process) to read an app-target enum's current case without importing the app module"
    - "Frame/hit-region marker (.frame(maxWidth: .infinity, maxHeight: .infinity) wrapped in .accessibilityIdentifier) measures what a system container actually allocates, rather than a size the view chooses -- the concrete technique this plan's own threat model existed to enforce (T-04-04-01)"
    - "Mechanical DTCG-to-Swift emitter with a --check diff mode, mirroring tooling/check-contracts.mjs and tooling/generate-ios-client.mjs's committed-generated-output precedent; the one closed lookup table it owns (typography role -> Dynamic Type text style/weight) fails loudly on an unrecognized role rather than guessing"

key-files:
  created:
    - apps/ios/Tests/KeeplingUITests/AccessoryAbsenceProbeTests.swift
    - apps/ios/Sources/Keepling/SyncRecovery/AccessoryHostability.swift
    - apps/ios/Sources/Keepling/SyncRecovery/AccessoryProbeRootView.swift
    - docs/testing/ios-testing.md
    - tooling/ios-lanes/accessory-probe.mjs
    - tooling/emit-swift-tokens.mjs
    - apps/ios/Sources/Keepling/DesignTokens/GeneratedTokens.swift
    - apps/ios/Sources/Keepling/DesignTokens/TokenSemantics.swift
    - tooling/ios-lanes/design-tokens.mjs
  modified:
    - apps/ios/Sources/Keepling/App/KeeplingApp.swift
    - package.json

key-decisions:
  - "Absence IS achievable on this Mac's pinned SDK 26.5, contrary to 04-RESEARCH.md's iOS-26.1-vintage DTS finding of 'no supported hide API' -- measured directly rather than trusting the research file's own caveat that it might have changed by execute time."
  - "Named capability is AccessoryHostability.absenceAchievable(via: .conditionalModifier, measuredSDKVersion: \"26.5\") -- simply not attaching .tabViewBottomAccessory at all when no content is warranted, rather than the isEnabled: false overload, because it needs no reliance on an undocumented suppression behavior DTS has not confirmed as an intentional API, even though isEnabled: false also measured absent on this SDK."
  - "The regression test reads the app's own declared capability via an accessibility value rather than duplicating the enum's logic in the UI test file, because a UI test bundle runs out-of-process and cannot import the app target's module -- this keeps AccessoryHostability.swift the single source of truth."
  - "Density aliases layout.target (44px) and layout.taskRowMin (52px) were already present in packages/design-tokens/tokens.json from an earlier phase, so Task 2 emitted them mechanically rather than adding them -- no change to tokens.json or css.css was needed."
  - "Swift identifiers for DTCG keys that are not legal bare identifiers (space.2xl, space.3xl) are emitted backtick-escaped (`2xl`, `3xl`) rather than renamed, keeping the emitted name mechanically traceable back to its tokens.json key."

requirements-completed: [IOS-03, IOS-04]

coverage:
  - id: D1
    description: "AccessoryAbsenceProbeTests measures all three named tabViewBottomAccessory configurations plus a no-accessory baseline on iOS SDK 26.5, asserting on rendered frame height, hit-testable region, and tab-bar top edge -- never on text content"
    requirement: IOS-04
    verification:
      - kind: e2e
        ref: "apps/ios/Tests/KeeplingUITests/AccessoryAbsenceProbeTests.swift (5 test methods, all passing on iPhone 17 simulator)"
        status: pass
    human_judgment: false
  - id: D2
    description: "AccessoryHostability.swift names the single capability constant (absenceAchievable via conditionalModifier, measured SDK 26.5) that Plan 04-10 reads, with a permanent regression test protecting the measured outcome"
    requirement: IOS-04
    verification:
      - kind: e2e
        ref: "apps/ios/Tests/KeeplingUITests/AccessoryAbsenceProbeTests.swift#testNamedAchievedConfigurationStaysAbsent"
        status: pass
    human_judgment: false
  - id: D3
    description: "docs/testing/ios-testing.md records the full iOS lane inventory (6 lanes) and a per-dimension disclosure of the accessory-absence measurement, following 03-UI-SPEC.md's evidence-table convention"
    verification:
      - kind: other
        ref: "node -e (grep check confirming tabViewBottomAccessory finding and 26.5 SDK version recorded)"
        status: pass
    human_judgment: false
  - id: D4
    description: "tooling/emit-swift-tokens.mjs mechanically generates GeneratedTokens.swift from tokens.json with zero hard-coded token name or hex value; a --check flag exits non-zero on any drift"
    requirement: IOS-03
    verification:
      - kind: integration
        ref: "node tooling/emit-swift-tokens.mjs && git diff --exit-code -- apps/ios/Sources/Keepling/DesignTokens/GeneratedTokens.swift packages/design-tokens/css.css && node tooling/emit-swift-tokens.mjs --check"
        status: pass
    human_judgment: false
  - id: D5
    description: "GeneratedTokens.swift contains every approved hex value and both density aliases (44, 52); colors resolve light/dark at runtime via a dynamic UIColor provider; exactly four typography roles map to Dynamic Type text styles; TokenSemantics.swift is literal-free"
    requirement: IOS-03
    verification:
      - kind: unit
        ref: "node -e (hex-value, density-alias, and hard-coded-literal checks over GeneratedTokens.swift and TokenSemantics.swift)"
        status: pass
    human_judgment: false
  - id: D6
    description: "Both new lanes (accessory-probe, design-tokens) and the five pre-existing lanes all pass under the full node tooling/verify-ios-phase.mjs gate with positive case counts, confirming no regression from the KeeplingApp.swift probe-routing change"
    verification:
      - kind: integration
        ref: "node tooling/verify-ios-phase.mjs (7 lanes: accessory-probe cases=5, core-unit cases=9, design-tokens cases=1, storage-gates cases=9, storage cases=9, tracer-e2e cases=5, vector-conformance cases=1)"
        status: pass
    human_judgment: false

duration: ~2h
completed: 2026-09-04
status: complete
---

# Phase 4 Plan 4: Accessory Absence Measurement and Swift Design Tokens Summary

**Measured (not assumed) that `tabViewBottomAccessory` achieves genuine absence on iOS SDK 26.5 via a conditionally-applied modifier, and shipped a mechanical, diff-checked Swift token emitter with runtime-resolved light/dark colors.**

## Performance

- **Duration:** ~2 hours
- **Started:** 2026-09-04T23:00Z (approx.)
- **Completed:** 2026-09-05T01:00Z (approx.)
- **Tasks:** 2 of 2 completed
- **Files created/modified:** 11

## Accomplishments

- Built `AccessoryAbsenceProbeTests`, a real XCUITest measurement of three named `tabViewBottomAccessory` configurations plus a no-accessory baseline, asserting on rendered frame height and hit-testable region rather than text content — the exact false-green 04-RESEARCH.md's Pitfall 1 warned against.
- **Discovered the accessory absence question resolves favorably on SDK 26.5**: contrary to the Apple DTS finding cited in RESEARCH.md (no supported hide API as of iOS 26.1), both omitting the modifier conditionally and applying it with `isEnabled: false` measured a genuinely nonexistent, zero-frame, non-hittable accessory element. Only the "always-applied modifier with conditionally-empty content" configuration reproduced the defect (48pt reserved height, 360pt wide, hit-testable, even with empty text).
- Named the single capability constant `AccessoryHostability.absenceAchievable(via: .conditionalModifier, measuredSDKVersion: "26.5")` that Plan 04-10 will read, with a permanent regression test that reads the app's own declared capability via an accessibility value (since a UI test bundle cannot `import` the app module) and re-measures it on every run.
- Wrote `docs/testing/ios-testing.md`, the iOS analogue of `docs/testing/desktop-testing.md`: a 6-lane inventory table plus a disclosures section recording the full measured numbers per configuration.
- Built `tooling/emit-swift-tokens.mjs`, a mechanical emitter with a `--check` diff mode producing `GeneratedTokens.swift` from `packages/design-tokens/tokens.json` — zero hard-coded token names or hex values, colors resolved light/dark at runtime via a dynamic `UIColor` provider (not baked in at launch), and exactly four typography roles mapped to Dynamic Type text styles.
- Wrote `TokenSemantics.swift`, the hand-written, literal-free semantic accessor layer every later iPhone view (Plans 04-09 through 04-14) will consume instead of `GeneratedTokens` directly or a raw literal.
- Confirmed the full 7-lane `tooling/verify-ios-phase.mjs` gate passes with no regression from the `KeeplingApp.swift` probe-routing change.

## Task Commits

Each task was committed atomically:

1. **Task 1: Measure whether the bottom accessory can be genuinely absent, and commit the answer** — `66a7578` (feat)
2. **Task 2: Swift design-token emitter with committed, diff-checked output** — `86be3aa` (feat)

## Files Created/Modified

- `apps/ios/Tests/KeeplingUITests/AccessoryAbsenceProbeTests.swift` — the 5-test measurement suite
- `apps/ios/Sources/Keepling/SyncRecovery/AccessoryHostability.swift` — the single named capability constant
- `apps/ios/Sources/Keepling/SyncRecovery/AccessoryProbeRootView.swift` — the launch-argument-selected probe scene hosting all three configurations plus baseline
- `apps/ios/Sources/Keepling/App/KeeplingApp.swift` — routes to the probe scene only when `KEEPLING_ACCESSORY_PROBE_MODE` is set
- `docs/testing/ios-testing.md` — lane inventory and the accessory-absence disclosure
- `tooling/ios-lanes/accessory-probe.mjs` — the phase-gate lane definition
- `tooling/emit-swift-tokens.mjs` — the mechanical DTCG-to-Swift emitter
- `apps/ios/Sources/Keepling/DesignTokens/GeneratedTokens.swift` — committed generated output
- `apps/ios/Sources/Keepling/DesignTokens/TokenSemantics.swift` — hand-written literal-free accessor layer
- `tooling/ios-lanes/design-tokens.mjs` — the phase-gate lane definition
- `package.json` — added `tokens:swift` script

## Decisions Made

See `key-decisions` frontmatter above. The most consequential: the accessory-absence question's answer is the **opposite** of what 04-RESEARCH.md's own DTS citation would suggest at first read — RESEARCH.md itself flagged this as "valid only until approximately 2026-09-11" and explicitly required a same-session measurement rather than trusting the finding, which is exactly what this task did and exactly why the answer differs.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] DTCG spacing keys `2xl`/`3xl` are not legal bare Swift identifiers**
- **Found during:** Task 2, first emitter run
- **Issue:** `packages/design-tokens/tokens.json`'s `space.2xl` and `space.3xl` keys, emitted naively as `public static let 2xl: CGFloat = 48`, produced a Swift syntax error (identifiers cannot start with a digit).
- **Fix:** Added a `swiftIdentifier()` helper that backtick-escapes any token key that is not a legal bare Swift identifier (`` `2xl` ``, `` `3xl` ``), keeping the emitted name mechanically traceable to its `tokens.json` key rather than renaming it away (e.g. to `xxl`).
- **Files modified:** `tooling/emit-swift-tokens.mjs`
- **Verification:** `node tooling/emit-swift-tokens.mjs` produces valid Swift; `node tooling/verify-ios-phase.mjs --lane core-unit` and `--lane tracer-e2e` both compile and pass the app/test targets referencing `GeneratedTokens.Space`.
- **Committed in:** `86be3aa` (part of Task 2 commit; the identifier bug was fixed before the commit, not as a separate correction commit)

---

**Total deviations:** 1 auto-fixed (1 bug). **Impact on plan:** Necessary correctness fix for the emitter to produce compilable Swift; no scope creep — density aliases `layout.target`/`layout.taskRowMin` were already present in `tokens.json` from an earlier phase, so no `tokens.json`/`css.css` addition was needed at all (the plan's own contingency for that case never triggered).

## Issues Encountered

None beyond the deviation documented above.

## User Setup Required

None — no external service configuration required. This plan runs entirely against the local Xcode toolchain and simulator already confirmed present in `04-RESEARCH.md`'s Environment Availability table.

## Next Phase Readiness

- Plan 04-10 (the Today/Inbox `TabView` shell and synchronization presentation) has a single named capability constant to read (`AccessoryHostability.currentAccessoryHostability`) rather than needing to re-derive or assume `tabViewBottomAccessory` behavior.
- Plans 04-09 through 04-14 have a complete, literal-free `TokenSemantics` accessor layer for every color, spacing, layout, and typography need this phase's UI-SPEC declares.
- **Note for the next planner:** the accessory-absence finding is favorable (absence IS achievable), which means D-40's disclosed-fallback path (the "empty, non-interactive, accessibility-hidden strip" for the not-achievable case) is not currently exercised in the shipped app — it remains specified in `docs/testing/ios-testing.md` and `AccessoryHostability.swift`'s own doc comments should a future SDK regress the finding, caught by the permanent regression test.
- No blockers.

## Self-Check: PASSED

- `[ -f apps/ios/Tests/KeeplingUITests/AccessoryAbsenceProbeTests.swift ]` — FOUND
- `[ -f apps/ios/Sources/Keepling/SyncRecovery/AccessoryHostability.swift ]` — FOUND
- `[ -f apps/ios/Sources/Keepling/SyncRecovery/AccessoryProbeRootView.swift ]` — FOUND
- `[ -f docs/testing/ios-testing.md ]` — FOUND
- `[ -f tooling/ios-lanes/accessory-probe.mjs ]` — FOUND
- `[ -f tooling/emit-swift-tokens.mjs ]` — FOUND
- `[ -f apps/ios/Sources/Keepling/DesignTokens/GeneratedTokens.swift ]` — FOUND
- `[ -f apps/ios/Sources/Keepling/DesignTokens/TokenSemantics.swift ]` — FOUND
- `[ -f tooling/ios-lanes/design-tokens.mjs ]` — FOUND
- `git log --oneline --all --grep="04-04"` returns 2 commits — FOUND
- Re-ran plan-level `<verification>`:
  - `node tooling/verify-ios-phase.mjs --lane accessory-probe` — PASS (cases=5)
  - `node tooling/verify-ios-phase.mjs --lane design-tokens` — PASS (cases=1)
  - `node tooling/emit-swift-tokens.mjs && git diff --exit-code -- apps/ios/Sources/Keepling/DesignTokens/GeneratedTokens.swift packages/design-tokens/css.css && node tooling/emit-swift-tokens.mjs --check` — PASS
  - Full `node tooling/verify-ios-phase.mjs` (7 lanes) — PASS

---
*Phase: KPL-04-native-iphone-daily-loop*
*Plan: 04*
*Completed: 2026-09-04*
