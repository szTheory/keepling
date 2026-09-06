---
phase: KPL-04-native-iphone-daily-loop
plan: 17
subsystem: testing
tags: [ios, verification, anti-vacuity, requirements-traceability, disclosures]

requires:
  - phase: KPL-04-01
    provides: "tooling/verify-ios-phase.mjs's lane-glob runner and the first tooling/ios-lanes/*.mjs files this plan assembles into one gate"
  - phase: KPL-04-16
    provides: "the device-install plan this plan's device lane is bound to -- NOT delivered (halted at a human-action checkpoint), which is exactly what this plan's device lane and REQUIREMENTS.md updates disclose"
provides:
  - "The assembled iOS phase gate: node tooling/verify-ios-phase.mjs runs all 22 lanes, refuses zero-case/unparseable/unloadable lanes, and reports a BLOCKED (never silently skipped, never a pass) status for the one lane genuinely missing evidence"
  - "node tooling/verify-ios-phase.mjs --requirements: a machine-checked map from IOS-01..04 and the SRV-02 iPhone adapter proof to their proving lanes, ids read live from .planning/REQUIREMENTS.md"
  - "A consolidated disclosures section in docs/testing/ios-testing.md covering all eight required disclosure areas, the five edge-probe rows, and the sixteen UI-SPEC backstop considerations"
  - "An honestly updated .planning/REQUIREMENTS.md: IOS-01..03 checked with disclosure, IOS-04 explicitly UNCHECKED because its own text names a physical iPhone and zero device evidence exists"
  - "A real bug fix: the pre-existing tracer-e2e lane was scoped to the WHOLE KeeplingUITests target instead of TracerCaptureUITests, discovered only because this plan is the first time every lane ever ran together"
affects: [KPL-05, KPL-06]

actuals:
  tokens: 42000
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns:
    - "A lane can report a third status, BLOCKED, distinct from PASS/FAIL: a parse-thrown Error prefixed literally 'BLOCKED:' is recognized by the runner and labeled accordingly, but still counts as a failure for the overall exit code -- 'genuinely missing evidence' and 'a real bug' are different findings for a human to read, but neither one is ever allowed to look like success."
    - "A requirement-to-lane map is read live from the Traceability table's own Phase-N row (regex-extracted, including 'PREFIX-NN..MM' range expansion) rather than hard-coded, so a requirement added to that row later without a lane fails --requirements automatically."
    - "Assembling every previously-isolated lane into ONE run for the first time is itself a verification act -- it found a real bug (tracer-e2e's over-broad test-target scope) that seventeen prior individual '--lane X' runs, each scoped to its own plan's own work, structurally could never have surfaced."

key-files:
  created:
    - tooling/ios-lanes/device.mjs
    - tooling/ios-lanes/README.md
  modified:
    - tooling/verify-ios-phase.mjs
    - tooling/ios-lanes/tracer-e2e.mjs
    - docs/testing/ios-testing.md
    - apps/ios/README.md
    - .planning/REQUIREMENTS.md

key-decisions:
  - "The device lane is included in the normal glob-discovered lane set (not carved out as a special case) and reports BLOCKED honestly, per the orchestrator's explicit instruction: the aggregate gate must never report overall success while Plan 04-16's physical-device evidence has never been produced. This makes `node tooling/verify-ios-phase.mjs` exit non-zero right now, on purpose -- verified live, not asserted."
  - "IOS-04's checkbox was UNCHECKED rather than marked 'complete with disclosure' like MAC-03/MAC-05 in Phase 3, because its own requirement text specifically names 'a physical iPhone' and there is currently ZERO evidence of any kind on physical hardware -- disclosure language is for a partially-proven claim, not a claim with no supporting evidence at all."
  - "The requirement-to-lane map lists `device` under IOS-01, IOS-02, IOS-04, and SRV-02 (the requirements whose own text or D-22 criteria depend on physical hardware) but not IOS-03, whose accessibility/Dynamic Type/Reduce Motion claims are comprehensively proven on the Simulator with a separately disclosed (not gate-blocking) VoiceOver-speech gap."
  - "requirements.ready-ids confirmed independently that ALL FIVE of this plan's requirement IDs are still 'blocked' at the tooling layer too -- Plan 04-16 shares the identical requirements list and has no SUMMARY.md yet, so the shared-ID gate (#2388) refuses to mark any of them complete regardless of this plan's own REQUIREMENTS.md edits. No `requirements mark-complete` call was made for this plan."

patterns-established:
  - "BLOCKED lane status convention (tooling/ios-lanes/README.md): a lane whose parse() throws an Error message starting literally 'BLOCKED:' is labeled distinctly from FAIL in gate output, but is never a pass and never omitted -- future lanes bound to unavailable hardware/credentials/prior-plan evidence should use this convention rather than inventing their own skip mechanism."

requirements-completed: []

coverage:
  - id: D1
    description: "One command (node tooling/verify-ios-phase.mjs) runs every one of 22 lanes and prints one LANE line per lane with name, status, case count, duration, and a git-ls-files-derived input digest; a lane reporting zero or unparseable output is a failure, never a silent skip"
    requirement: IOS-01
    verification:
      - kind: e2e
        ref: "node tooling/verify-ios-phase.mjs -- 21 lanes freshly re-run live in this session, all PASS with positive case counts; 1 lane (device) correctly BLOCKED"
        status: pass
    human_judgment: false
  - id: D2
    description: "A lane reporting zero cases, an unparseable result, or a nonexistent test target fails the gate -- proven by two deliberate breaks during this plan's own execution, not merely asserted"
    verification:
      - kind: other
        ref: "Deliberate break 1: a synthetic zero-case lane (`command: 'true'`, `parse: () => 0`) -- gate reported status=FAIL, exit 1. Deliberate break 2: an xcodebuild -only-testing target naming a nonexistent test class -- xcodebuild itself reported 'Executed 0 tests', gate reported status=FAIL, exit 1."
        status: pass
    human_judgment: false
  - id: D3
    description: "node tooling/verify-ios-phase.mjs --requirements maps IOS-01, IOS-02, IOS-03, IOS-04, and SRV-02 (read live from .planning/REQUIREMENTS.md's Phase 4 Traceability row) to existing lane files, and fails on any unmapped requirement or any mapped-but-missing lane"
    requirement: SRV-02
    verification:
      - kind: other
        ref: "node tooling/verify-ios-phase.mjs --requirements -- printed all 5 requirement/lane mappings and exited 0"
        status: pass
    human_judgment: false
  - id: D4
    description: "The gate refuses to report success while the physical-device lane's evidence is missing -- the device lane always runs, always reports BLOCKED (not PASS, not a silent skip) until Plan 04-16 produces its attestation tooling and SUMMARY"
    requirement: IOS-04
    verification:
      - kind: other
        ref: "node tooling/verify-ios-phase.mjs --lane device -- printed LANE name=device status=BLOCKED and a specific missing-evidence message, exited 1"
        status: pass
    human_judgment: false
  - id: D5
    description: "A real, pre-existing bug (tracer-e2e's -only-testing argument named the whole KeeplingUITests target instead of TracerCaptureUITests, silently duplicating every other lane's coverage under its own name) was found and fixed as a direct consequence of assembling every lane into one run for the first time"
    verification:
      - kind: e2e
        ref: "tooling/ios-lanes/tracer-e2e.mjs -- before: exceeded a 150s timeout without finishing; after: node tooling/verify-ios-phase.mjs --lane tracer-e2e completed in 15240ms, cases=1"
        status: pass
    human_judgment: false
  - id: D6
    description: "Every disclosed gap across Plans 04-01 through 04-16 is consolidated into one section of docs/testing/ios-testing.md: the eight required disclosure rows, the five unclassified/unresolved edge-probe rows with their authored-from sources, and the sixteen UI-SPEC backstop considerations mapped to their discharging tests"
    verification:
      - kind: other
        ref: "node -e regex check for all eight required disclosure terms (tabViewBottomAccessory, completeUntilFirstUserAuthentication, jetsam, BGTaskScheduler, VoiceOver, Criterion 5, edge probe, backstop) -- 'all disclosures consolidated'"
        status: pass
    human_judgment: false
  - id: D7
    description: ".planning/REQUIREMENTS.md reflects the gate's actual result: IOS-01..03 checked with disclosure, IOS-04 explicitly unchecked (its text names a physical iPhone, and none exists), the Phase 4 Traceability row and the SRV-02 iPhone-adapter-proof note both restate that SRV-02 completes only at the Phase 5 cross-adapter proof"
    verification:
      - kind: other
        ref: "node -e check for IOS-01..04 row presence and 'SRV-02 iPhone adapter proof' text -- 'requirement ledger updated'"
        status: pass
    human_judgment: true
    rationale: "Whether IOS-01..03's disclosed Simulator-only proof is 'enough' to keep those three checked (vs. unchecking all four like IOS-04) is a judgment call this SUMMARY makes explicit and documents the reasoning for, but a human reviewer should confirm it reads as honest rather than as rounding up."
  - id: D8
    description: "apps/ios/README.md documents the project layout, the generate-then-build workflow, both committed-generated-output rules (wire client and design tokens), the no-pnpm rule, the full 22-lane inventory, and a pointer to the consolidated disclosures"
    verification:
      - kind: other
        ref: "Manual read-through of apps/ios/README.md's new sections against the plan's acceptance criteria"
        status: pass
    human_judgment: false

duration: ~3h10m
completed: 2026-09-05
status: complete
---

# Phase KPL-04 Plan 17: Assembled Anti-Vacuous iOS Phase Gate Summary

**One command (`node tooling/verify-ios-phase.mjs`) now runs all 22 iOS lanes together for the first time ever, machine-checks every phase requirement against a named lane, and honestly reports the physical-device lane as BLOCKED rather than pretending success — a stance that also surfaced and fixed a real bug (tracer-e2e was silently running the entire UI test target) that no prior isolated `--lane` run could have found.**

## Performance

- **Duration:** ~3h10m (most of it spent live-verifying all 22 lanes individually and in combination, not writing code)
- **Started:** 2026-09-05T~19:52Z (approx)
- **Completed:** 2026-09-06T~01:10Z UTC
- **Tasks:** 2 of 2 completed
- **Files modified:** 7 (2 created, 5 modified)

## Accomplishments

- `tooling/verify-ios-phase.mjs` gained a `REQUIREMENT_LANES` map and a `--requirements` flag that reads this phase's requirement ids live from `.planning/REQUIREMENTS.md`'s Traceability table (with `PREFIX-NN..MM` range expansion) and fails if any requirement has no mapped lane or maps to a lane file that doesn't exist. Verified: all 5 requirements (IOS-01..04, SRV-02) map cleanly to existing lanes.
- Added a `BLOCKED` lane status: a lane whose `parse()` throws an `Error` prefixed literally `BLOCKED:` is labeled distinctly from an ordinary `FAIL` in gate output — "genuinely missing evidence" reads differently from "a real bug" — but still fails the overall run. The gate can never report green while required evidence is missing.
- `tooling/ios-lanes/device.mjs`: the one lane bound to physical hardware. Plan 04-16 halted at a genuine human-action checkpoint (no confirmed paid Apple Developer Program membership, no `DEVELOPMENT_TEAM`, iPhone offline) and never produced its attestation tooling or SUMMARY. This lane always runs and always reports `BLOCKED` right now — verified live: `node tooling/verify-ios-phase.mjs --lane device` prints the exact missing-evidence reason and exits 1.
- **Proved the anti-vacuity contract is real, not asserted**, with two deliberate breaks during this plan's own execution: a synthetic zero-case lane failed the gate, and an `xcodebuild -only-testing` target naming a nonexistent test class also failed the gate (xcodebuild itself reported "Executed 0 tests").
- **Found and fixed a real, pre-existing bug** in `tooling/ios-lanes/tracer-e2e.mjs`: its `-only-testing` argument named the *whole* `KeeplingUITests` target instead of `TracerCaptureUITests` specifically — silently re-running every other UI-test lane's classes under this lane's name, several minutes slower than intended, on every gate invocation. This was discoverable only because this plan is the first time all 22 lanes have ever run together in one pass; every prior plan verified only its own `--lane <name>` in isolation. Fixed to match what `docs/testing/ios-testing.md` already documented this lane as proving.
- **Live-verified all 22 lanes individually in this session** (not merely trusted from prior SUMMARYs): 21 lanes PASS with positive case counts, 1 lane (`device`) correctly `BLOCKED`. See the lane-by-lane table below.
- Consolidated every disclosed gap from Plans 04-01 through 04-16 into one section of `docs/testing/ios-testing.md`: the eight required disclosure rows (tabViewBottomAccessory absence, G7 data protection, D-22 Criteria 2/3/4/5, the App Intents harness fallback, edge-probe rows), the five unclassified/unresolved edge-probe rows with exactly where each requirement's edge coverage was authored from instead, and the sixteen UI-SPEC backstop overflow/long-text considerations mapped to their discharging tests.
- Updated `.planning/REQUIREMENTS.md` **honestly against what the gate actually proves**: IOS-01, IOS-02, IOS-03 checked with disclosure (comprehensive Simulator proof; physical-device confirmation still pending); **IOS-04 explicitly UNCHECKED** — its own text names "a physical iPhone" and there is currently zero evidence of any kind on physical hardware. The Phase 4 Traceability row and the SRV-02 iPhone-adapter-proof note both restate that SRV-02 completes only at the Phase 5 cross-adapter proof, matching the Phase 3 Electron-row precedent.
- Finished `apps/ios/README.md`: project layout, the generate-then-build workflow, the design-tokens committed-generated-output rule (alongside the pre-existing wire-client rule), the full 22-lane inventory, and a pointer to the consolidated disclosures.
- `tooling/ios-lanes/README.md` documents the lane export contract, the throw-rather-than-return-zero rule, and the new `BLOCKED:` convention.

## Live lane-by-lane verification (this session, `node tooling/verify-ios-phase.mjs --lane <name>`)

| Lane | Status | Cases | Duration |
|---|---|---|---|
| design-tokens | PASS | 1 | 23ms |
| core-unit | PASS | 3 | 5.1s |
| decode-roundtrip | PASS | 10 | 3.3s |
| privacy | PASS | 13 | 3.3s |
| vector-conformance | PASS | 1 | 3.2s |
| transport | PASS | 11 | 3.2s |
| storage | PASS | 3 | 2.8s |
| storage-gates | PASS | 3 | 2.9s |
| auth | PASS | 4 | 4.0s |
| lifecycle | PASS | 3 | 4.4s |
| durability-posture | PASS | 3 | 2.6s |
| sync-pass | PASS | 9 | 3.3s |
| sync-presentation | PASS | 14 | 107.0s |
| undo | PASS | 10 | 69.2s |
| tracer-e2e | PASS | 1 | 15.2s (after Rule 1 fix; previously exceeded 150s unfinished) |
| app-intents | PASS | 5 | 3.4s |
| accessory-probe | PASS | 5 | 55.0s |
| core-loop | PASS | 2 | 123.6s |
| overflow-longtext | PASS | 8 | 210.5s |
| state-matrix | PASS | 11 | 201.4s |
| accessibility | PASS | 7 | 1096.6s (~18.3 min — the heaviest lane: 4 XCUITest classes, full ScreenInventory audit) |
| device | **BLOCKED** | 0 | 7ms — disclosed missing physical-device evidence, by design |

21/22 lanes PASS with positive case counts; 1/22 (`device`) correctly `BLOCKED`. **`node tooling/verify-ios-phase.mjs` (no arguments, all lanes together) therefore currently exits non-zero — on purpose.** This is the honest state the whole plan exists to produce: the aggregate command cannot and does not report overall success while Plan 04-16's physical-device evidence has never been produced.

## Task Commits

1. **Task 1: The assembled anti-vacuous phase gate with a machine-checked requirement map** - `ad6c9be` (feat)
2. **Task 2: One consolidated disclosures section and the updated requirement ledger** - `b8b5a78` (docs)
3. **Rule 1 deviation: fix tracer-e2e's over-broad test-target scope** - `f5eb862` (fix)

## Files Created/Modified

- `tooling/verify-ios-phase.mjs` - assembled `--requirements` flag, `REQUIREMENT_LANES` map, `BLOCKED` lane status
- `tooling/ios-lanes/device.mjs` - the physical-device lane, honestly `BLOCKED` pending Plan 04-16
- `tooling/ios-lanes/README.md` - lane export contract, throw-not-zero rule, `BLOCKED:` convention
- `tooling/ios-lanes/tracer-e2e.mjs` - Rule 1 fix: scoped to `TracerCaptureUITests` only
- `docs/testing/ios-testing.md` - consolidated disclosures section (8 required rows, 5 edge-probe rows, 16 backstop considerations)
- `apps/ios/README.md` - project layout, generate-then-build workflow, design-tokens rule, lane inventory, disclosures pointer
- `.planning/REQUIREMENTS.md` - IOS-01..03 checked with disclosure, IOS-04 unchecked, Phase 4 Traceability row updated

## Decisions Made

See `key-decisions` frontmatter above. Most consequential: (1) the device lane runs in the normal discovered set and reports `BLOCKED` rather than being special-cased out of the gate, so the aggregate command is honestly non-green right now; (2) IOS-04 was unchecked rather than "checked with disclosure" because its own text names physical hardware and none exists at all — a stronger stance than the Phase 3 MAC-03/MAC-05 disclosure pattern, reserved for claims with partial (not zero) evidence; (3) `requirements.ready-ids` independently confirmed all five requirement IDs stay blocked at the tooling layer too, because sibling Plan 04-16 shares the same requirements list and has no SUMMARY yet — no `requirements mark-complete` call was made.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] tracer-e2e lane scoped to the whole KeeplingUITests target instead of TracerCaptureUITests**
- **Found during:** Task 1's own required "prove the gate is not vacuous" step, while live-verifying every lane for this SUMMARY (the first time all 22 lanes had ever run together)
- **Issue:** `tooling/ios-lanes/tracer-e2e.mjs`'s `-only-testing` argument named `KeeplingUITests` (the entire target) rather than `KeeplingUITests/TracerCaptureUITests`, meaning every gate invocation silently re-ran every other UI-test lane's classes under the `tracer-e2e` name too — several minutes slower than intended, and a direct mismatch against what `docs/testing/ios-testing.md`'s own lane table already documented this lane as proving
- **Fix:** Narrowed the `-only-testing` argument to `KeeplingUITests/TracerCaptureUITests`
- **Files modified:** `tooling/ios-lanes/tracer-e2e.mjs`
- **Verification:** Before: the lane exceeded a 150-second timeout without finishing. After: `node tooling/verify-ios-phase.mjs --lane tracer-e2e` completes in 15,240ms with `cases=1`
- **Committed in:** `f5eb862`

---

**Total deviations:** 1 auto-fixed (Rule 1 - bug)
**Impact on plan:** Necessary for the gate's own stated purpose (efficient, non-duplicative "one command"). No scope creep — the fix restores the lane to its already-documented, narrower intent.

## Known Stubs

None. The `device` lane's `BLOCKED` status is not a stub — it is the plan's own designed, disclosed behavior for a physical-device dependency that does not yet have evidence, per the orchestrator's explicit instruction that the aggregate gate must never report overall success while that evidence is missing. It is not a placeholder awaiting future wiring; it is a correct, honest FAIL/BLOCKED result that will become a real `PASS` only once Plan 04-16 (or a re-attempt of it) produces genuine device evidence.

## Issues Encountered

- Running all 22 lanes together for the very first time (the whole point of this plan) took roughly 30 minutes of wall-clock xcodebuild/Simulator time across the session, dominated by the `accessibility` lane (~18.3 minutes for its 4 XCUITest classes covering the full `ScreenInventory` audit). This is disclosed as the true cost of "one command that cannot lie" — it runs everything, for real, every time.

## User Setup Required

None - no external service configuration required by this plan. (Plan 04-16's user_setup — an active Apple Developer Program membership and a trusted online physical iPhone — remains outstanding and is what the `device` lane's `BLOCKED` status names explicitly.)

## Next Phase Readiness

- The assembled gate, its requirement map, and the consolidated disclosures are all in place and independently, freshly verified in this session — Phase 4's evidence model is now legible in one command and one document.
- **Not ready for a clean phase close-out claim while `device` reports `BLOCKED`.** The honest next step is either (a) re-attempt Plan 04-16 once a paid Apple Developer Program membership is confirmed and Jon's iPhone is online and trusted, or (b) explicitly accept the phase with this disclosed gap and carry it forward — a decision for Jon, not something this plan resolves on its own.
- `pnpm contracts:check` (13 vector files, 15 consumer entries) and the Elixir reference-model suite (9 tests, 1 property, run against a disposable PostgreSQL instance per this session's own setup/teardown) both verified green independently of the iOS gate.

---
*Phase: KPL-04-native-iphone-daily-loop*
*Completed: 2026-09-05*
