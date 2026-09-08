---
phase: KPL-04-native-iphone-daily-loop
verified: 2026-09-08T19:05:00Z
status: human_needed
score: 20/23 must-haves verified
behavior_unverified: 3
overrides_applied: 0
re_verification:
  previous_status: human_needed
  previous_score: 19/23
  gaps_closed:
    - "Undo overclaim — ROADMAP SC1, IOS-01's REQUIREMENTS.md note, and docs/testing/ios-testing.md now all state that undo is simulator-only, with the structural reason and what would close it (commit 6538542, disclosure row 9)"
    - "migration-1.sqlite fixture vacuity — fixture regenerated at version 1 only, all three consumers open a per-run writable copy carrying the -wal/-shm siblings (commit 0746e34); re-verified by running the storage lane and confirming byte-identical fixtures afterwards"
    - "Skipped tests counted as executed cases — xcodebuildSummary now subtracts skips and fails a lane that skipped everything (commit 594d243); published simulator total corrected 432 -> 424"
  gaps_remaining: []
  regressions: []
deferred:
  - truth: "SRV-02 — the iPhone adapter proof completes the cross-adapter SRV-02 requirement"
    addressed_in: "Phase 5"
    evidence: "REQUIREMENTS.md traceability rows 124/125 and the closing note: 'SRV-02 is intentionally proven incrementally… It is not complete until the Phase 5 cross-adapter proof passes.' Phase 5 owns 'MCP-01..05, SRV-02 MCP adapter proof and cross-adapter completion'."
behavior_unverified_items:
  - truth: "ROADMAP SC5 — Jon can use the supported iPhone loop daily without opening Things for those actions"
    test: "Use the installed build as the only tool for capture / Inbox / Today / complete / trash for a sustained period."
    expected: "The loop is sufficient for daily use without falling back to Things."
    why_human: "Adoption is owner dogfood feedback. Disclosed in docs/testing/ios-testing.md consolidated row 7 as 'Not automatable at all, by design' — no lane asserts it and none ever will."
  - truth: "04-06 / 04-16 backstop (D-04 G7) — a write performed while the device is locked completes without an I/O or 0xdead10cc failure"
    test: "Lock the phone with its passcode, trigger a background write, and confirm no SQLITE_IOERR / 0xdead10cc."
    expected: "The .completeUntilFirstUserAuthentication class permits the write while locked."
    why_human: "`DataProtectionTests.testBackgroundWriteWhileLockedDoesNotTakeAnIOErrorOrTerminate` throws an explicit BLOCKED XCTSkip: devicectl exposes `info lockState` (a read) but no `lock` verb, and XCUIDevice's lock control is UI-testing-only while StorageTests is a unit bundle. Tracked open as WINDOWS.md row 63 (still `open`). The protection-class half IS proven on hardware; only the locked-write half is open. Observed directly in this verification's storage run: 55 cases, 2 skipped — those two."
  - truth: "04-16 backstop — the same G7 locked-write statement carried by the physical-device plan"
    test: "As above, on the attached device."
    expected: "As above."
    why_human: "Same blocker; recorded against both plans because both declare it `verification: backstop`."
human_verification:
  - test: "Sustained daily dogfood of the installed loop"
    expected: "Jon does not need Things for capture / Inbox / Today / complete / trash"
    why_human: "SC5 is owner feedback by design, disclosed as never-a-gate"
  - test: "G7 locked-device write"
    expected: "A write while the phone is locked does not fail with SQLITE_IOERR / 0xdead10cc"
    why_human: "No programmatic lock control exists; closing it would mean adding production surface solely to satisfy a gate (WINDOWS.md row 63)"
  - test: "Accept the Debug-configuration substitution for the device suites"
    expected: "Proving the Release binary on hardware stays open, or is scheduled"
    why_human: "Disclosed and attested (BuildAttestation.configuration + attestation.mjs --expect-configuration), but it is a deliberate substitution a human should sign off on"
  - test: "Read the 04-14 sixteen-consideration discharge table against 04-UI-SPEC.md prose"
    expected: "Each mapped test genuinely discharges its consideration"
    why_human: "Disclosed by the phase itself as a human judgment call (04-14-SUMMARY coverage entry D9)"
---

# Phase 4: Native iPhone Daily Loop — Verification Report

**Phase Goal:** Jon can dogfood the same trustworthy core loop through a native, platform-integrated SwiftUI iPhone client.
**Verified:** 2026-09-08T19:05:00Z (re-verified after remediation)
**Status:** human_needed
**Re-verification:** Yes — after remediation of the two findings from the initial pass
**Mode note:** ROADMAP marks this phase `mode: mvp`, but its goal is not in the required User Story form (`As a …, I want to …, so that ….`). MVP-mode User Flow Coverage was therefore not applied; standard goal-backward verification was used instead. Recorded as a process warning, not a code defect.

## Re-verification Result

Both findings are genuinely closed. I checked the tree rather than the claims, and
re-ran what was cheap.

**Finding 1 — undo overclaim: closed by correcting the claim, and the correction is
accurate.** No device undo case was added, and I verified the stated reason is real, not
a rationalisation: `WorkspaceFacade.swift:51,65` publishes `undoAvailability` and it is
assigned only from the acknowledgement path, and the simulator suites inject availability
through `KEEPLING_UITEST_UNDO_AVAILABLE`, read at `KeeplingApp.swift:118` and set by
`UndoPersistenceTests.swift:24`, `SyncRecoveryTests.swift:23`, and
`AccessibilityAuditTests.swift:243`. A device lane with no server therefore has no undo
affordance to tap — the gap is structural, not an oversight. The claim is now accurate in
all three places it appears: `ROADMAP.md:316` carries an explicit exception on SC1,
IOS-01's note in `REQUIREMENTS.md` carries a `CORRECTED 2026-09-08` clause naming the
mechanism, and `docs/testing/ios-testing.md:428` adds disclosure row 9 stating what would
close it (running the UI device lane against the recording-proxy stack, as
`server-driven-device` already does for the adapter). **Reclassified: disclosed residual,
not a silent gap** — the same class as VoiceOver speech, real jetsam, and BGTaskScheduler
wakes, and handled the same way. It is no longer a human-verification item. What changed
is the claim, not the evidence: SC1 is now narrower than originally written, and that
narrowing is an owner amendment recorded in the contract itself.

**Finding 2 — fixture vacuity: properly fixed, and I confirmed it by running the lane.**

- Committed blob at HEAD: `SELECT version FROM schema_migrations` → **1** only (86016 bytes,
  down from the 94208-byte `[1,2,3]` file).
- No test opens a committed fixture path directly: the only references to
  `migration1FixturePath` / `corruptedChecksumFixturePath` outside `FixtureFactory.swift`
  are none; all three consumers (`MigrationLedgerTests.swift:65,160,171`,
  `DurabilityPostureTests.swift:96`) call the `…FixtureCopy()` accessors.
- `FixtureFactory.writableCopy(ofFixtureAtPath:)` copies into a per-run UUID temp directory
  and carries the `-wal`/`-shm` siblings, correctly treating the WAL database as a
  three-file durable unit.
- **Byte-identity confirmed by measurement, not assertion.** I hashed both fixtures, ran
  `xcodebuild test -only-testing:StorageTests` to completion (`** TEST SUCCEEDED **`), and
  re-hashed: `6cc5861b…` and `b6d99661…` unchanged, `git status --porcelain apps/ios/`
  empty, and the fixture still reads version `1`. `testMigration1FixtureMigratesForward…`
  passed in 0.017s having actually migrated a version-1 copy.

**Skip-counting: fixed, and the corrected numbers reconcile.** `xcodebuildSummary` now
subtracts skips and throws `'xcodebuild skipped every one of its N test(s), so this lane
proved nothing'` when a lane skipped everything. My own storage run reported
`Executed 55 tests, with 2 tests skipped` → 53 executed, exactly matching the claimed
`storage` 55 → 53 correction. The two skips are the G7 device-only cases, which is the
right answer.

**Device-lane counts are pending a re-run.** The phone is away, so `device` and
`server-driven-device` could not be re-run. Their last recorded results (`device` PASS
cases=26, `server-driven-device` PASS cases=4, inside `lanes=24 failed=0 blocked=0`) were
produced under the *old* count that included skipped tests. `device` runs
`DataProtectionTests`, which carries the two G7 skips, so its published figure will very
likely drop when re-run. Those numbers should be treated as stale-but-not-invalid: the
PASS/FAIL verdicts stand, the case counts do not. This report deliberately does not
restate 26/4/462 as current.

## Goal Achievement

Nothing about the phase goal is in doubt. The iPhone client is real, wired end to end,
and the evidence model is unusually rigorous — the gate refuses to report green on a
missing lane, a zero count, a lane that skipped its way to a healthy-looking total, a
stale build digest, a substituted build configuration, a locked phone, or a proxy that
recorded nothing. Both remediations made the evidence stricter rather than merely
re-describing it.

### Observable Truths

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | **SC1** — a physical iPhone supports capture, Inbox, Today, edit, complete/reopen, trash/restore, and undo | ✓ VERIFIED (scope amended, disclosed) | `DeviceCoreLoopTests.testFullSupportedLoopOnPhysicalDevice` drives capture → edit → Save & Move Out of Inbox → complete → reopen → trash → restore on hardware, plus `testTrashViaContextMenuOnPhysicalDevice` and `testPlanForTodayAndFindItOnTheTodayTabOnPhysicalDevice`. Undo is simulator-only for a structural reason verified in code (availability is minted by a server acknowledgement); SC1 now carries an explicit exception, IOS-01's note is corrected, and disclosure row 9 names what would close it. |
| 2 | **SC2** — offline mutation, termination, relaunch, expired auth, account fencing, duplicate replay, structured conflict preserve intent and account isolation | ✓ VERIFIED | `DeviceRecoveryTests` (4 hardware cases) + the `server-driven-device` lane driving the real Swift client against real Phoenix on real PostgreSQL behind the recording proxy. `ServerDrivenTests` asserts from `proxy.records`, and `XCTFail`s (never `XCTSkip`s) when no base URL is supplied (`ServerDrivenTests.swift:69`). |
| 3 | **SC3** — background execution is only an acceleration | ✓ VERIFIED | `BackgroundAccelerationTests` proves the BG handler and `ScenePhaseDriver` call the identical `runSyncPass` entry point and that full restoration succeeds with the background path disabled entirely; confirmed on hardware by `DeviceRecoveryTests.testBackgroundAndForegroundRestoresCorrectnessOnPhysicalDevice`. |
| 4 | **SC4** — Dynamic Type, VoiceOver semantics, touch targets, Reduce Motion | ✓ VERIFIED (disclosed harness limit) | Seven-type `performAccessibilityAudit` over the closed `ScreenInventory`, the Dynamic Type matrix, DWC, the single `Motion.swift` gate, `FocusSafetyTests`; hardware confirmation run found a real device-only contrast defect (fixed in `TaskListEmptyState`). VoiceOver speech and rotor gestures are permanently outside any lane — disclosed row 6. |
| 5 | **SC5** — Jon uses the iPhone loop daily without opening Things | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Owner dogfood feedback. Automatable proxy delivered (non-expiring profile, `build-ios-signed.mjs` install, all device cases green against the installed build). Disclosed row 7 as never-a-gate. |
| 6 | **04-01** — tracer capture, normalized contract, no pnpm membership | ✓ VERIFIED | No `apps/ios/package.json`; zero real `nullable:` sites in `keepling.yaml` (all three grep hits are comments); `discriminator:` at line 1967 with an honest recorded rationale where a conformant one was impossible. `pnpm contracts:check` green; `generate-ios-client --check` reports the committed client current (9 files). |
| 7 | **04-02** — 11 STRICT tables, G1–G6, ledger halts on drift, never repairs | ✓ VERIFIED | Previously flagged fixture-only; **now genuinely proven.** The committed fixture is version 1, every consumer opens a per-run copy, and I ran the lane: 53 executed cases, 0 failures, fixtures byte-identical afterwards, tree clean. `testCorruptedChecksumFixtureThrowsChecksumDriftAndLeavesFileByteIdentical` remains unusually self-aware (asserts ledger rows, per-table row counts and `integrity_check` rather than naive byte equality). |
| 8 | **04-03** — a third independent Swift reducer agrees with the Elixir and TypeScript references | ✓ VERIFIED (documented deviation) | Vectors resolved from the source tree via a `#filePath` walk. Manifest gate green: "13 vector files, 15 consumer entries proven executed". Deviation from the literal "all 13 files": only `sync.json` lists `swift`, justified in the committed `manifest.json` `_comment` and machine-checked. Override suggestion below. |
| 9 | **04-04** — accessory absence measured, not assumed; tokens generated | ✓ VERIFIED | `AccessoryHostability.swift:58` commits the measured capability and it is consumed at `RootTabView.swift:46,74`. `emit-swift-tokens --check` reports the committed output current. |
| 10 | **04-05** — decode round-trip, unreachable vs refused, hand-written mappers, HTTPS guard | ✓ VERIFIED | `KeeplingSyncAdapter.swift:83` throws `.insecureBaseURL` unless https or loopback, evaluated before credentials are consulted. |
| 11 | **04-06** — terminal settlement (G8), durable unit, backup-replay no-op | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED (G7 locked-write half) | Settlement, durable unit and replay-no-op all proven. The `verification: backstop` locked-write statement has no evidence and cannot get any without a lock verb — observed as one of the two skips in my storage run. |
| 12 | **04-07** — device-grant PKCE, Keychain-only credentials, server-only namespace activation | ✓ VERIFIED | `KeychainCredentialStore.swift:89,96` sets `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` on both add and update queries. |
| 13 | **04-08** — bounded sync pass, outbound commands, background as acceleration | ✓ VERIFIED | `ScenePhaseDriver.swift:77` and `BackgroundRefresh.swift` both route to `KeeplingApplication.runSyncPass`. |
| 14 | **04-09** — two-tab loop, locked gesture contract, durable capture draft | ✓ VERIFIED | `TaskRow.swift:159` — trailing full swipe carries only Complete/Reopen; Trash only in `.contextMenu` (line 180) and detail. Repository-wide grep for `refreshable`, `onMove`, `EditButton`: **zero** hits. |
| 15 | **04-10** — one authoritative sync presentation, conditional accessory, debounced announcements | ✓ VERIFIED | All five artifacts substantive; the accessory's healthy rendering reads `currentAccessoryHostability` at the one named site. |
| 16 | **04-11** — named, timerless undo as a compensating semantic action | ✓ VERIFIED | Zero `Timer`/`asyncAfter`/`Task.sleep` in the undo path; repository-wide grep for `toast`/`snackbar`: zero. Simulator-proven; hardware coverage disclosed under truth 1. |
| 17 | **04-12** — App Intents in the main target sharing one store handle | ✓ VERIFIED | `CaptureTaskIntent.swift:41,60` — one in-process handle via `IntentStoreAccess`, no App Group. |
| 18 | **04-13** — accessibility as release evidence | ✓ VERIFIED | See truth 4. |
| 19 | **04-14** — twelve-state matrix, held-out overflow/long-text suite | ✓ VERIFIED | `SyncStateMatrixTests` (291 lines), `OverflowAndLongTextTests` (379 lines), `StateInjection`, `Fixtures/long-text.json`. The D9 discharge judgment is routed to human. |
| 20 | **04-15** — diagnostics reconstruct a bad day without carrying content | ✓ VERIFIED | `DiagnosticEvent.swift` is structurally content-free: `UUID`-typed identity, closed enums, no `String`-typed stored property. |
| 21 | **04-16** — physical-device evidence lane bound by read-back attestation | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED (same G7 backstop) | Signing, attestation, device resolution and both device suites all substantive; device suites `XCTSkip` only on `targetEnvironment(simulator)`. The plan's own `verification: backstop` G7 statement is unproven for the same reason as truth 11. |
| 22 | **04-17** — the assembled anti-vacuous gate and machine-checked requirement map | ✓ VERIFIED | `--requirements` re-run clean: 5/5 mapped. 24 lane files matching `lanes=24`. **Strengthened since the initial pass:** the summary parser now subtracts skips and hard-fails a lane that skipped everything, so a published case count means what it says. |
| 23 | **04-18** — server-driven scenarios on the real phone over a publicly-trusted tailnet host | ✓ VERIFIED | No `URLSessionDelegate`, `serverTrust`, or ATS exception anywhere in `apps/ios/Sources` — no test-only trust code on any configuration. Transport guard byte-for-byte unchanged. `attestation.mjs --expect-configuration` refuses a configuration mismatch; `lock-probe.mjs` names a locked phone as its own BLOCKED reason; no `uninstall` verb anywhere in the device tooling. |

**Score:** 20/23 truths verified (3 present, behavior-unverified — SC5 and the one G7
backstop statement carried by two plans)

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|---|---|---|
| 1 | SRV-02's iPhone adapter proof completing the cross-adapter requirement | Phase 5 | REQUIREMENTS.md traceability; the iPhone-side transport/reducer/orchestration proof itself IS delivered here (`transport`, `vector-conformance`, `sync-pass`, `server-driven-sim`, `server-driven-device` lanes). |

### Required Artifacts

All 90 artifacts named across the 18 plans' `must_haves.artifacts` exist, are substantive,
and are wired. Zero MISSING, zero STUB, zero ORPHANED — unchanged from the initial pass,
plus one new artifact (`FixtureFactory.writableCopy` and the two copy accessors) verified
as part of the remediation.

### Key Link Verification

| From | To | Via | Status |
|---|---|---|---|
| `CaptureSheet` | `GRDBLocalStore` | `CaptureCommand` → single `dbPool.write { }` → only then `local_saved` | ✓ WIRED |
| outbox row | settlement | identity + fingerprint → canonical/conflict → journal terminalization → exact row delete in one transaction | ✓ WIRED |
| `keepling.yaml` | `Transport/Generated/*.swift` | `generate-ios-client.mjs --check`: current (9 files) | ✓ WIRED |
| `tokens.json` | `GeneratedTokens.swift` | `emit-swift-tokens.mjs --check`: current | ✓ WIRED |
| committed fixture | test | `FixtureFactory.writableCopy` per-run temp copy carrying `-wal`/`-shm` | ✓ WIRED |
| `acknowledge(_:)` | `UndoControl` | `WorkspaceFacade.undoAvailability` — server-minted, which is exactly why the device lane cannot reach it | ✓ WIRED |
| build digest | running process on phone | `build-ios-signed.mjs` → Info.plist → `BuildAttestation` → `attestation.mjs` refuses on digest **or** configuration mismatch | ✓ WIRED |
| recording proxy | assertions | `ServerDrivenTests` reads `proxy.records`; lane parser refuses zero arrivals / injections / refusals | ✓ WIRED |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Committed migration fixture is a version-1 database | `sqlite3 <git HEAD blob> "SELECT version FROM schema_migrations"` | **1** (86016 bytes) | ✓ PASS |
| Storage lane runs clean and leaves fixtures untouched | `xcodebuild test -only-testing:StorageTests`, hashing fixtures before and after | `** TEST SUCCEEDED **`; `Executed 55 tests, with 2 tests skipped`; both SHA-1s unchanged; `git status` clean | ✓ PASS |
| Forward-migration test genuinely migrates | same run | `testMigration1FixtureMigratesForwardToVersion2PreservingVersion1Row` passed in 0.017s against a version-1 copy | ✓ PASS |
| Skip-excluding count matches the claim | same run | 55 − 2 = 53, exactly the claimed `storage` 55 → 53 | ✓ PASS |
| Requirement→lane map holds | `node tooling/verify-ios-phase.mjs --requirements` | 5 requirements, all mapped; exit 0 | ✓ PASS |
| Committed Swift tokens current | `node tooling/emit-swift-tokens.mjs --check` | current | ✓ PASS |
| Committed Swift client current | `node tooling/generate-ios-client.mjs --check` | current (9 files) | ✓ PASS |
| Contract + vector manifest gate | `pnpm contracts:check` | green; 13 vector files, 15 consumer entries proven executed | ✓ PASS |
| Full gate under the corrected count | not run (device lanes need the phone, which is away) | last recorded `lanes=24 failed=0 blocked=0`, but device counts predate the skip fix | ? SKIP |

### Requirements Coverage

| Requirement | Source Plans | Status | Evidence |
|---|---|---|---|
| IOS-01 | 04-01, 04-08, 04-09, 04-11, 04-12, 04-14, 04-16, 04-17 | ✓ SATISFIED (undo hardware gap disclosed) | Lanes `core-loop`, `undo`, `tracer-e2e`, `device`; the claim now matches the evidence everywhere it appears. |
| IOS-02 | 04-01, 04-02, 04-06, 04-07, 04-08, 04-15, 04-16, 04-17, 04-18 | ✓ SATISFIED | Lanes `storage`, `storage-gates`, `sync-pass`, `durability-posture`, `server-driven-sim`, `server-driven-device`, `device`. Storage evidence is stronger than at the initial pass. |
| IOS-03 | 04-04, 04-09, 04-13, 04-14, 04-16, 04-17 | ✓ SATISFIED (VoiceOver-speech gap disclosed) | Lanes `accessibility`, `state-matrix`, `design-tokens`; hardware confirmation run. |
| IOS-04 | 04-04, 04-07, 04-10, 04-11, 04-14, 04-15, 04-16, 04-17, 04-18 | ✓ SATISFIED (Debug-config disclosure) | Lanes `sync-presentation`, `auth`, `state-matrix`, `server-driven-device`, `device`. |
| SRV-02 | 04-01, 04-03, 04-05, 04-08, 04-17, 04-18 | ⏸ DEFERRED (iPhone-adapter half satisfied) | Completes at the Phase 5 cross-adapter proof. |

No ORPHANED requirements.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| — | — | `TBD` / `FIXME` / `XXX` | — | **Zero** across `apps/ios/Sources`, `apps/ios/Tests`, `tooling/ios-*`, and both testing docs |
| — | — | `TODO` / `HACK` / `PLACEHOLDER` | — | **Zero** |
| — | — | vacuous-green fixture | ✅ RESOLVED | Fixed at the root and re-verified by running the lane |
| — | — | undisclosed undo coverage gap | ✅ RESOLVED | Claim corrected in all three surfaces; disclosure row 9 added |
| — | — | skipped cases counted as executed | ✅ RESOLVED | Parser subtracts skips and hard-fails an all-skipped lane |

### Human Verification Required

These four are the only genuine human-judgment items left, and I say that plainly: every
other residual in this phase is either proven, disclosed with its mechanism named, or
deferred to Phase 5.

1. **SC5 — sustained daily dogfood.** Owner feedback by design; no lane will ever assert it.
2. **G7's locked-device write.** No programmatic lock control exists. Closing it would mean
   adding a production `protectedDataWillBecomeUnavailable` write hook solely to satisfy a
   gate — a decision, not a task. WINDOWS.md row 63 remains correctly `open`.
3. **The Debug-configuration substitution** for the device suites — disclosed and attested,
   but a deliberate substitution that wants explicit sign-off. Proving the Release binary
   on hardware stays open.
4. **04-14's D9 judgment** — whether each mapped `OverflowAndLongTextTests` case fully
   discharges its 04-UI-SPEC.md consideration, which the phase itself flags as a human
   read rather than an automated claim.

One operational note that is not a judgment item: **the `device` and `server-driven-device`
case counts need a re-run** under the skip-excluding parser before they are quoted again.
Their PASS verdicts stand; their numbers are stale.

### Suggested Override

Plan 04-03's must-have says the Swift reducer agrees "on every case in all 13 golden
vector files", but only `sync.json` binds the sync state machine. The narrowing is
committed, reasoned, and machine-checked. To accept it formally:

```yaml
overrides:
  - must_have: "A third independent implementation of the synchronization reducer, written in Swift, agrees with the Elixir reference model and the TypeScript desktop consumer on every case in all 13 golden vector files (SRV-02, D-10)."
    reason: "Only sync.json binds sync-state-machine.schema.json; the other 12 files bind Elixir-owned domain shapes with no Swift consumer. Recorded in packages/contracts/vectors/manifest.json's _comment and enforced by check-contracts.mjs's cross-consumer gate (13 files, 15 consumer entries proven executed)."
    accepted_by: "jon"
    accepted_at: "2026-09-08T00:00:00Z"
```

---

_Verified: 2026-09-08T19:05:00Z_
_Verifier: Claude (gsd-verifier)_
