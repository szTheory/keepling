---
phase: KPL-04-native-iphone-daily-loop
verified: 2026-09-10T00:05:00Z
status: passed
score: 23/23 must-haves verified (20 by evidence, 3 accepted by owner override)
behavior_unverified: 0
overrides_applied: 3
overrides:
  - must_have: "ROADMAP SC5 — Jon can use the supported iPhone loop daily without opening Things for those actions"
    reason: "Owner dogfood feedback, never a gate by design. No lane asserts it and none ever will. Disclosed as docs/testing/ios-testing.md row 7. Accepted AS DISCLOSED, NOT AS PROVEN."
    accepted_by: owner
    accepted_at: "2026-09-08"
  - must_have: "04-06 backstop (D-04 G7) — a write performed while the device is locked completes without an I/O or 0xdead10cc failure"
    reason: "Nothing can lock the phone under program control (devicectl has no lock verb; XCUIDevice is UI-testing-only and StorageTests is a unit bundle). Closing it would mean adding a production protectedDataWillBecomeUnavailable write hook solely to make a gate pass. Disclosed as row 2; tracked as WINDOWS.md row 63 (still open). The protection-class half IS proven on hardware. Accepted AS DISCLOSED, NOT AS PROVEN."
    accepted_by: owner
    accepted_at: "2026-09-08"
  - must_have: "04-16 backstop — the same G7 locked-write statement carried by the physical-device plan"
    reason: "Same blocker, same disclosure, same acceptance. Recorded against both plans because both declare it verification: backstop. Accepted AS DISCLOSED, NOT AS PROVEN."
    accepted_by: owner
    accepted_at: "2026-09-08"
owner_acceptance:
  decided_by: owner
  decided_at: 2026-09-08
  decision: >-
    Accepted all four remaining human-judgment items AS DISCLOSED, NOT AS PROVEN.
    This changes the phase's status, not its evidence: nothing below was
    re-measured or re-classified as verified on the strength of this decision,
    and every one of the four keeps its disclosure naming exactly what is not
    proven and why. Verified by the verifier: the block's four descriptions are
    accurate, each item retains its disclosure, and no truth's evidence changed.
  items:
    - "SC5 daily adoption -- disclosure row 7. Encoded above as an override."
    - "G7's locked-device write -- disclosure row 2, WINDOWS.md row 63 still open. Encoded above as two overrides (04-06 and 04-16 both declare it)."
    - "The Debug-configuration substitution for the device suites -- disclosed in the Summary bullet of docs/testing/ios-testing.md, in tooling/ios-lanes/device.mjs's own comment, and in IOS-04's REQUIREMENTS.md note. Not a must-have truth, so no override; recorded here."
    - "04-14's D9 discharge judgment -- disclosed at docs/testing/ios-testing.md:468 and in 04-14-SUMMARY.md. Not a must-have truth, so no override; recorded here."
re_verification:
  previous_status: human_needed
  previous_score: 20/23
  gaps_closed:
    - "Undo overclaim — corrected in ROADMAP SC1, IOS-01's REQUIREMENTS.md note, and disclosure row 9 (commit 6538542)"
    - "migration-1.sqlite fixture vacuity — fixture regenerated at version 1, all consumers open a per-run writable copy (commit 0746e34); re-verified by running the storage lane"
    - "Skipped tests counted as executed cases — parser subtracts skips and fails an all-skipped lane (commit 594d243)"
    - "Four human-judgment items — reviewed and accepted by the owner as disclosed, not as proven (commit 6496323); re-encoded here through the documented overrides mechanism"
    - "Hardware lanes ran behind ~20 minutes of simulator lanes and a bare BLOCKED: from the lock probe surfaced as an ordinary FAIL — both fixed and verified in tooling/verify-ios-phase.mjs:231-235 and tooling/ios-lanes/device.mjs:253-254 (commit f13e5ca)"
    - "The 496-case figure was presented as one gate invocation while being a composite of three; closed by running one unified gate (unified-gate-2.log) rather than by rewording alone"
  gaps_remaining: []
  regressions: []
findings:
  - id: published-case-count-undercounts-multi-bundle-lanes
    severity: warning
    status: fixed
    fixed_in: "214bcf8 -- xcodebuildSummary now anchors on the `<Bundle>.xctest` summary (exactly one per bundle), sums per-bundle totals, subtracts skips, and fails when any single bundle executed zero. Measured after the fix: auth 19, undo 18, sync-presentation 35, device 29; corrected totals 463 simulator and 496 overall. Tracked as WINDOWS.md row 65."
    status_note: >-
      Also corrected a claim this verification had accepted earlier: the device
      lane's count did not stay at 26 because nothing it published had been a
      skip, but because `DataProtectionTests` -- the bundle carrying G7's
      protection-class hardware evidence -- was being discarded entirely.
    file: tooling/verify-ios-phase.mjs
    summary: >-
      xcodebuildSummary takes the LAST "Executed N tests" line, which for a lane
      spanning two test bundles is the last BUNDLE's total, not the run's. Four
      lanes span two bundles, so each publishes fewer cases than it ran: auth 4
      published / 19 run (measured directly), undo 8 / 18, sync-presentation 21 /
      35, device 26 / 29. The published totals 424 simulator and 454 overall
      therefore understate actual executed cases by roughly 42. It is an
      UNDERCOUNT, so it has never produced a false PASS — a failure anywhere
      still fails the run and every published count is positive — but the number
      the gate publishes as its evidence does not cover everything the lane ran,
      which is the property D-24 rests on. This is the same defect the parser's
      own comment records fixing at the suite level, reappearing one level up at
      the bundle level. Side effect: the device lane's single XCTSkip lives in
      DataProtectionTests, whose bundle total is discarded, which is why the
      device count did not move under the skip-excluding fix.
    fix: >-
      Sum the per-bundle totals (or parse per "Test Suite '*.xctest'" block)
      instead of taking the last match. Does not require re-running the gate to
      make the fix; re-running to republish corrected numbers is at the owner's
      convenience.
deferred:
  - truth: "SRV-02 — the iPhone adapter proof completes the cross-adapter SRV-02 requirement"
    addressed_in: "Phase 5"
    evidence: "REQUIREMENTS.md traceability rows 124/125 and the closing note: 'SRV-02 is intentionally proven incrementally… It is not complete until the Phase 5 cross-adapter proof passes.' Phase 5 owns 'MCP-01..05, SRV-02 MCP adapter proof and cross-adapter completion'."
---

# Phase 4: Native iPhone Daily Loop — Verification Report

**Phase Goal:** Jon can dogfood the same trustworthy core loop through a native, platform-integrated SwiftUI iPhone client.
**Verified:** 2026-09-10T00:05:00Z (fifth pass — one unified gate run verified end to end)
**Status:** passed
**Re-verification:** Yes — five passes; final evidence is `unified-gate-2.log` at commit `fe38e05`
**Mode note:** ROADMAP marks this phase `mode: mvp`, but its goal is not in the required User Story form. MVP-mode User Flow Coverage was not applied; standard goal-backward verification was used. Process warning, not a code defect.

## Fifth Pass (2026-09-10): the unified run holds — gap closed

I read `unified-gate-2.log` rather than the summary of it. It is one
invocation, and it says what it is claimed to say:

- **24 LANE lines, zero non-PASS.** Checked by filtering for anything that is
  not `status=PASS` — nothing matched.
- **Hardware first, in the same log:** `device` PASS cases=29 (1123s),
  `server-driven-device` PASS cases=4.
- **Counts sum correctly from the log itself:** all 24 lanes → **496**;
  excluding the two hardware lanes → **463**. Both figures reproduce from the
  LANE lines, not from a narrative.
- **The build is in the same run:** `IOS_BUILD` / `IOS_BUILD_MANIFEST` lines head
  the log with digest `4bc0be13…`, the digest the device lane's attestation binds
  to, so the phone-side evidence belongs to the build this invocation installed.
- **`iOS phase gate summary: lanes=24 failed=0 blocked=0`** and
  **`iOS phase gate: PASSED`**.

The docs sentence now claims one invocation and rests on that log. **Keep the
history note** — a surface whose purpose is that a reader can tell what each
green check means is exactly where a corrected claim should show its work; it
reads as rigour, not clutter.

Worth recording: the run before this one reported `lanes=24 failed=2 blocked=2`
with **both** hardware lanes saying BLOCKED on a real lock. That is the
`server-driven-device` lock probe I reviewed last pass doing its job on a genuine
auto-lock rather than a synthetic one — the fix is now proven by use, not just by
inspection.

**Gap closed. Status: passed.**

## Fourth Pass (2026-09-09): count fix verified, one claim did not hold

**The parser fix is correct.** `xcodebuildSummary` now anchors on
`Test Suite '<Bundle>.xctest' passed|failed at ...` followed by its `Executed`
line — exactly one per bundle, so summing counts each bundle once without
triple-counting the per-suite and "Selected tests" lines. It sums, subtracts
skips, and throws when any single bundle executed zero, so a healthy bundle
cannot stand in for one that ran nothing. The measured results match this
report's derivation exactly: `auth` 19 (which I had measured myself last pass),
`undo` 18, `sync-presentation` 35, `device` 29 — the +3 being
`DataProtectionTests`, the discarded bundle. WINDOWS.md row 65 records it as
fixed with the G7 consequence stated. Finding closed.

**The two lane fixes are real.** `server-driven-device.mjs:57,69` chains the lock
probe and propagates a bare `BLOCKED:` verbatim; `device.mjs:274` matches
`deviceprep Code=-3` / "Unlock … to Continue" / "because the device is locked"
and reports BLOCKED instead of publishing a lost-connection message as a test
failure.

**What does not hold: "the full gate passes … 496 executed cases."** No
invocation ever produced that. Reading the logs rather than the summary:

| Invocation | Result | Contribution |
|---|---|---|
| `final-gate-3.log` | **`iOS phase gate: FAILED`** — `device` BLOCKED, `server-driven-device` FAIL (the phone locked) | the 22 simulator lanes, 463 cases |
| `hw-lanes-3.log` run A | `lanes=1 failed=0 blocked=0`, PASS | `device` 29 |
| `hw-lanes-3.log` run B | `lanes=1 failed=0 blocked=0`, PASS | `server-driven-device` 4 |

463 + 29 + 4 = 496, and I verified that arithmetic against the LANE lines. Every
one of the 24 lanes does have a PASS with a positive case count at current lane
sources — the substance is fine. But `docs/testing/ios-testing.md` presents this
as the output of one command reporting `lanes=24 failed=0 blocked=0`, and the
only invocation that ever reported that was `final-gate-2` at 454 cases under the
buggy parser and superseded lane code. This is the same species of composite-
presented-as-single-run claim as the undo overclaim I flagged in pass one, on the
surface whose stated purpose is that a reader "should be able to tell, for every
green checkmark, exactly what it means".

**So I have not advanced `verified:`.** You asked me to tell you rather than
re-stamp, and re-stamping is exactly the act that would certify these records.
Two closures are equally acceptable to me:

1. **Run one unified gate.** You offered, the phone is available, and
   hardware-first ordering plus the new mid-run lock detection exist precisely to
   make that survivable. Then the sentence becomes literally true and I re-stamp
   on the log.
2. **Correct the wording** to describe the composite — 22 simulator lanes green
   inside a run the gate reported FAILED, plus two single-lane hardware runs. This
   phase has good precedent for correcting a claim rather than manufacturing
   evidence, and it costs minutes rather than an hour.

I have no preference between them. What I will not do is stamp a claim the logs
contradict.

## What I Checked In Earlier Passes

**1. Owner acceptance — the block is accurate, and no evidence moved.** I read all
four descriptions against the tree. Each is correct: SC5 keeps disclosure row 7; G7's
locked write keeps row 2 and WINDOWS.md row 63 is still `open` (not quietly flipped to
fixed); the Debug substitution is disclosed in three places (the ios-testing.md Summary
bullet, `device.mjs`'s own comment, and IOS-04's REQUIREMENTS.md note); D9 is disclosed
at `ios-testing.md:468`. Nothing was re-classified as verified — the truth table below
carries the same evidence it did before, and the three overrides are labelled
`PASSED (override)` rather than `VERIFIED`.

**On the encoding: `status: passed` is right, but `owner_acceptance:` alone was not.**
The file said `passed` while still carrying a populated `human_verification` block,
`behavior_unverified: 3`, and `overrides_applied: 0` — three fields asserting unresolved
human items under a status that means there are none. The documented mechanism for
exactly this situation is `overrides:`, which turns an accepted must-have into
`PASSED (override)` and counts it toward the score. I have re-encoded the three items
that map to must-have truths as overrides (`overrides_applied: 3`, `behavior_unverified: 0`,
`human_verification` removed), kept your `owner_acceptance` block because it records the
*character* of the decision better than an override `reason` field does, and left the
other two items (Debug substitution, D9) recorded there only — neither is a must-have
truth, so neither needs an override. The score is now 23/23 with the split stated
explicitly: 20 by evidence, 3 by owner override. Nothing reads as proven that is not.

**2. Both tooling fixes are real.** `verify-ios-phase.mjs:231-235` ranks
`device.mjs` and `server-driven-device.mjs` to 0 and everything else to 1, sorting
alphabetically within each group — hardware first, deterministic order preserved. The
gate log confirms it: `device` and `server-driven-device` are the first two LANE lines.
`device.mjs:253-254` now matches a bare `^BLOCKED:` (multiline) and throws it verbatim
when no `ATTESTATION REFUSED` is present, so the lock probe's own reason reaches the
gate's `status=BLOCKED` label instead of being buried in stderr behind a generic FAIL.

**3. The gate log is genuine and internally consistent.** 24 LANE lines, all
`status=PASS`, `iOS phase gate: PASSED`. Hardware lanes first with plausible durations
(`device` 1748s, `server-driven-device` 68s). The simulator lanes sum to exactly 424 and
the two device lanes to 30, giving 454 — the arithmetic checks out. `storage cases=53`
matches the 55 − 2 I measured myself last pass.

**4. You were right that the device counts did not drop — but not for the stated
reason, and chasing that turned up a new finding.** See below.

## New Finding: the published case count undercounts multi-bundle lanes

⚠️ **WARNING — not a blocker, not a false PASS, but it touches the number this phase
treats as its evidence.**

Your note that the device counts stayed at 26 and 4 did not fit: `device` runs
`DataProtectionTests`, which contains one unconditional `XCTSkip` (G7's locked write),
so a skip-excluding parser should have moved it. I went looking, and the mechanism is
this: `xcodebuildSummary` takes the **last** `Executed N tests` line, and for a lane
spanning two test bundles that line is the last *bundle's* total, not the run's.

I measured it rather than inferred it. Running the `auth` lane's exact `-only-testing`
set directly:

```
Test Suite 'KeeplingCoreTests.xctest' passed …
	 Executed 15 tests, with 0 failures …
Test Suite 'StorageTests.xctest' passed …
	 Executed 4 tests, with 0 failures …
```

The lane ran 19 cases. The gate publishes `auth cases=4` — the last bundle only.

Four lanes span two bundles, and each undercounts:

| Lane | Bundles | Published | Actually run | Basis |
|---|---|---|---|---|
| `auth` | KeeplingCoreTests + StorageTests | 4 | **19** | measured directly this pass |
| `undo` | KeeplingCoreTests + KeeplingUITests | 8 | 18 | 10 + 8 declared methods |
| `sync-presentation` | KeeplingCoreTests + KeeplingUITests | 21 | 35 | 14 + 8 + 13 declared |
| `device` | KeeplingUITests + StorageTests | 26 | 29 | 30 declared − 1 XCTSkip |

So the published `424 simulator / 454 total` understates actual executed cases by about
42. Two consequences worth stating plainly:

- **The device count did not move because the skip is in the discarded bundle.** The one
  XCTSkip lives in `DataProtectionTests`, whose total is thrown away. "Nothing those lanes
  published had been a skip" is true, but only because the bundle containing the skip was
  never in the published number at all. `DataProtectionTests` on hardware — the evidence
  for G7's protection-class half — contributes zero to `device cases=26`.
- **The tests still ran and still passed.** `** TEST FAILED **` anywhere fails the lane
  regardless of which summary line is parsed, so no PASS in this phase is false and no
  truth below is weakened. This is an evidence-*reporting* defect, not an evidence defect.

It is the same bug the parser's own comment documents fixing at the suite level ("Take the
LAST such line, not the first… the case count is the number this gate publishes as its
evidence, and D-24's anti-vacuity contract rests on that number meaning what it says"),
reappearing one level up. The fix is to sum per-bundle totals rather than take the last
match. I have **not** changed the status over it: nothing is unproven that was proven, and
the phase goal is unaffected. But given how seriously this phase takes published counts, it
deserves a WINDOWS.md entry and a follow-up, and `ios-testing.md`'s 454/424 figures should
be corrected when it is fixed.

## Goal Achievement

The phase goal is achieved. The iPhone client is real, wired end to end, and dogfoodable
on hardware. Across three verification passes the evidence model has only got stricter:
the fixture vacuity was fixed at the root, skipped cases stopped being published as
executed, the undo overclaim was corrected rather than papered over, and a locked phone
now reports BLOCKED instead of a misleading FAIL. Every one of those was a real fix, and
I confirmed each by reading the tree or running something.

### Observable Truths

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | **SC1** — physical iPhone supports capture, Inbox, Today, edit, complete/reopen, trash/restore, and undo | ✓ VERIFIED (scope amended, disclosed) | `DeviceCoreLoopTests` drives everything but undo on hardware. Undo is simulator-only for a structural reason verified in code (`WorkspaceFacade.swift:51,65` — availability is minted by a server acknowledgement); SC1 carries an explicit exception, IOS-01's note is corrected, disclosure row 9 names what would close it. |
| 2 | **SC2** — offline mutation, termination, relaunch, expired auth, fencing, replay, conflict | ✓ VERIFIED | `DeviceRecoveryTests` (4 hardware cases) + `server-driven-device` PASS cases=4 against real Phoenix on real PostgreSQL behind the recording proxy, asserting from `proxy.records`. |
| 3 | **SC3** — background execution is only an acceleration | ✓ VERIFIED | `BackgroundAccelerationTests` proves the identical `runSyncPass` entry point and full restoration with the background path disabled; confirmed on hardware. |
| 4 | **SC4** — Dynamic Type, VoiceOver semantics, touch targets, Reduce Motion | ✓ VERIFIED (disclosed harness limit) | Seven-type audits over the closed `ScreenInventory`, Dynamic Type matrix, DWC, single `Motion.swift` gate, `FocusSafetyTests`; hardware confirmation run found a real device-only contrast defect. Row 6 discloses what no lane can assert. |
| 5 | **SC5** — Jon uses the loop daily without opening Things | ✓ PASSED (override) | Owner-accepted as disclosed, not proven. Row 7: not automatable by design. |
| 6 | **04-01** — tracer capture, normalized contract, no pnpm membership | ✓ VERIFIED | No `apps/ios/package.json`; zero real `nullable:` sites; `contracts:check` green; committed Swift client current (9 files). |
| 7 | **04-02** — 11 STRICT tables, G1–G6, ledger halts on drift, never repairs | ✓ VERIFIED | Fixture vacuity fixed at the root and re-verified by running the lane: 53 executed, 0 failures, fixtures byte-identical afterwards, tree clean, fixture still at version 1. |
| 8 | **04-03** — a third independent Swift reducer agrees with the references | ✓ VERIFIED (documented deviation) | Manifest gate green: 13 files, 15 consumer entries proven executed. Only `sync.json` lists `swift`, justified in the committed manifest. Override suggestion below. |
| 9 | **04-04** — accessory absence measured; tokens generated | ✓ VERIFIED | Measured capability consumed at `RootTabView.swift:46,74`; `emit-swift-tokens --check` current. |
| 10 | **04-05** — decode round-trip, unreachable vs refused, hand-written mappers, HTTPS guard | ✓ VERIFIED | `KeeplingSyncAdapter.swift:83` unchanged, evaluated before credentials. |
| 11 | **04-06** — terminal settlement (G8), durable unit, backup-replay no-op | ✓ VERIFIED / ✓ PASSED (override) for the G7 backstop | Settlement, durable unit and replay-no-op proven. The `verification: backstop` locked-write statement is owner-accepted as disclosed; WINDOWS.md row 63 correctly remains `open`. |
| 12 | **04-07** — device-grant PKCE, Keychain-only credentials, server-only namespace activation | ✓ VERIFIED | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` on both add and update queries. |
| 13 | **04-08** — bounded sync pass, outbound commands, background as acceleration | ✓ VERIFIED | `ScenePhaseDriver.swift:77` and `BackgroundRefresh.swift` both route to `runSyncPass`. |
| 14 | **04-09** — two-tab loop, locked gesture contract, durable capture draft | ✓ VERIFIED | Trailing full swipe carries only Complete/Reopen; Trash only in the context menu and detail. Zero `refreshable`/`onMove`/`EditButton` anywhere. |
| 15 | **04-10** — one authoritative sync presentation, conditional accessory, debounced announcements | ✓ VERIFIED | All five artifacts substantive; healthy rendering reads `currentAccessoryHostability` at the one named site. |
| 16 | **04-11** — named, timerless undo as a compensating semantic action | ✓ VERIFIED | Zero `Timer`/`asyncAfter`/`Task.sleep` in the undo path; zero `toast`/`snackbar`. Hardware coverage disclosed under truth 1. |
| 17 | **04-12** — App Intents in the main target sharing one store handle | ✓ VERIFIED | One in-process handle via `IntentStoreAccess`; no App Group. |
| 18 | **04-13** — accessibility as release evidence | ✓ VERIFIED | See truth 4. |
| 19 | **04-14** — twelve-state matrix, held-out overflow/long-text suite | ✓ VERIFIED | Both suites substantive; the D9 discharge judgment is owner-accepted as a disclosed judgment call. |
| 20 | **04-15** — diagnostics reconstruct a bad day without carrying content | ✓ VERIFIED | `DiagnosticEvent.swift` structurally content-free: `UUID` identity, closed enums, no `String`-typed stored property. |
| 21 | **04-16** — physical-device evidence lane bound by read-back attestation | ✓ VERIFIED / ✓ PASSED (override) for the G7 backstop | Signing, attestation, device resolution, both device suites substantive; device suites skip only on simulator. Debug substitution disclosed and attested. |
| 22 | **04-17** — the assembled anti-vacuous gate and machine-checked requirement map | ✓ VERIFIED (one reporting defect, see Findings) | `--requirements` clean: 5/5 mapped. 24 lanes, all PASS. Strengthened twice since pass one (skip exclusion; hardware-first ordering and BLOCKED propagation). The multi-bundle undercount is a defect in what the gate *publishes*, not in what it *enforces*. |
| 23 | **04-18** — server-driven scenarios on the real phone over a publicly-trusted tailnet host | ✓ VERIFIED | No `URLSessionDelegate`, `serverTrust`, or ATS exception anywhere in `apps/ios/Sources`. Transport guard byte-for-byte unchanged. `--expect-configuration` refuses a configuration mismatch; no `uninstall` verb in the device tooling. |

**Score:** 23/23 — 20 verified by evidence, 3 accepted by owner override

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|---|---|---|
| 1 | SRV-02's iPhone adapter proof completing the cross-adapter requirement | Phase 5 | The iPhone-side transport/reducer/orchestration proof IS delivered here; REQUIREMENTS.md completes SRV-02 at the Phase 5 cross-adapter proof. |

### Gate Evidence (read from the logs, not re-run)

Current evidence, at the fixed parser and current lane sources:

| Lane group | Status | Executed cases | Source |
|---|---|---|---|
| `device` | PASS | 29 | hardware, first lane in the run |
| `server-driven-device` | PASS | 4 | hardware |
| 22 simulator lanes | all PASS | 463 | same run |
| **Total** | | **496** | `lanes=24 failed=0 blocked=0`, `iOS phase gate: PASSED` |

All of it from `unified-gate-2.log`, one invocation of
`node tooling/build-ios-signed.mjs && node tooling/verify-ios-phase.mjs`, with the
build and install recorded in the same log (digest `4bc0be13…`). The earlier
`final-gate-2` (454 cases, buggy parser) and the three-run composite it briefly
rested on are both superseded.

### Requirements Coverage

| Requirement | Status | Evidence |
|---|---|---|
| IOS-01 | ✓ SATISFIED (undo hardware gap disclosed) | `core-loop`, `undo`, `tracer-e2e`, `device` all PASS; the claim now matches the evidence everywhere it appears. |
| IOS-02 | ✓ SATISFIED | `storage`, `storage-gates`, `sync-pass`, `durability-posture`, `server-driven-sim`, `server-driven-device`, `device` all PASS. |
| IOS-03 | ✓ SATISFIED (VoiceOver-speech gap disclosed) | `accessibility`, `state-matrix`, `design-tokens` all PASS; hardware confirmation run. |
| IOS-04 | ✓ SATISFIED (Debug-config disclosure, owner-accepted) | `sync-presentation`, `auth`, `state-matrix`, `server-driven-device`, `device` all PASS. |
| SRV-02 | ⏸ DEFERRED (iPhone-adapter half satisfied) | Completes at the Phase 5 cross-adapter proof. |

No ORPHANED requirements.

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|---|---|---|---|
| — | `TBD` / `FIXME` / `XXX` / `TODO` / `HACK` / `PLACEHOLDER` | — | **Zero** across `apps/ios/Sources`, `apps/ios/Tests`, `tooling/ios-*`, and both testing docs |
| `tooling/verify-ios-phase.mjs` | published count undercounts multi-bundle lanes | ⚠️ Warning | See Findings — reporting defect, no false PASS |
| `docs/testing/ios-testing.md` | disclosure rows ordered 7, 9, 8 | ℹ️ Info | Cosmetic; row 9 was appended before row 8 |
| — | vacuous-green fixture | ✅ RESOLVED | Fixed at the root and re-verified by running the lane |
| — | undisclosed undo coverage gap | ✅ RESOLVED | Claim corrected in all three surfaces; row 9 added |
| — | skipped cases counted as executed | ✅ RESOLVED | Parser subtracts skips and hard-fails an all-skipped lane |
| — | hardware lanes behind 20 min of simulator lanes; bare `BLOCKED:` shown as FAIL | ✅ RESOLVED | Ordering rank + multiline bare-BLOCKED match, both verified in source and in the log |

### Human Verification Required

None outstanding. The four items that were open at the previous pass have been reviewed
and accepted by the owner as disclosed rather than proven, and each retains its
disclosure naming exactly what is not proven and why. One WARNING-level finding
(the published-count undercount) is recorded above for a follow-up decision; it does not
require human testing and does not gate the phase.

### Suggested Override (unchanged)

Plan 04-03's must-have says the Swift reducer agrees "on every case in all 13 golden
vector files", but only `sync.json` binds the sync state machine:

```yaml
overrides:
  - must_have: "A third independent implementation of the synchronization reducer, written in Swift, agrees with the Elixir reference model and the TypeScript desktop consumer on every case in all 13 golden vector files (SRV-02, D-10)."
    reason: "Only sync.json binds sync-state-machine.schema.json; the other 12 bind Elixir-owned domain shapes with no Swift consumer. Recorded in packages/contracts/vectors/manifest.json's _comment and enforced by check-contracts.mjs's cross-consumer gate."
    accepted_by: "jon"
    accepted_at: "2026-09-08T00:00:00Z"
```

---

_Verified: 2026-09-08T21:20:00Z_
_Verifier: Claude (gsd-verifier)_
