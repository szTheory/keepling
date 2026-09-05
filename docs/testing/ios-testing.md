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
| `vector-conformance` | `node tooling/verify-ios-phase.mjs --lane vector-conformance` | `KeeplingCoreTests` (`VectorConformanceTests`) | The Swift `SyncReducer`'s agreement with the Elixir reference model and the TypeScript desktop consumer on `packages/contracts/vectors/sync.json` |
| `accessory-probe` | `node tooling/verify-ios-phase.mjs --lane accessory-probe` | `KeeplingUITests` (`AccessoryAbsenceProbeTests`) | Whether `tabViewBottomAccessory` can be made genuinely absent on this Mac's pinned SDK — measured on rendered geometry and hit-testability, never on text content, plus a permanent regression on the named achieving configuration |

Run every lane (the phase gate, always comprehensive):

```sh
node tooling/verify-ios-phase.mjs
```

Run one lane:

```sh
node tooling/verify-ios-phase.mjs --lane accessory-probe
```

## Disclosures

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
