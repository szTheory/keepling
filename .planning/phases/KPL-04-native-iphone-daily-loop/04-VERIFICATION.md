---
phase: KPL-04-native-iphone-daily-loop
verified: 2026-09-08T23:40:00Z
status: human_needed
score: 19/23 must-haves verified
behavior_unverified: 4
overrides_applied: 0
deferred:
  - truth: "SRV-02 — the iPhone adapter proof completes the cross-adapter SRV-02 requirement"
    addressed_in: "Phase 5"
    evidence: "REQUIREMENTS.md traceability row 124/125 and the closing note: 'SRV-02 is intentionally proven incrementally… It is not complete until the Phase 5 cross-adapter proof passes.' Phase 5 owns 'MCP-01..05, SRV-02 MCP adapter proof and cross-adapter completion'."
behavior_unverified_items:
  - truth: "ROADMAP SC1 — a physical iPhone supports capture, Inbox, Today, edit, complete/reopen, trash/restore, AND UNDO with native touch"
    test: "On the installed device build: capture a task, complete it, then use the named `Undo Complete` control in the bottom accessory (and the nav-bar overflow row) and confirm the task returns to its prior state; then confirm the control disappears/supersedes correctly."
    expected: "Undo is reachable and honored on hardware, exactly as `UndoPersistenceTests` proves on the simulator."
    why_human: "No lane asserts undo on hardware. `tooling/ios-lanes/device.mjs` runs only DeviceCoreLoopTests, DeviceRecoveryTests, DataProtectionTests, AccessibilityAuditTests, DynamicTypeSnapshotTests and four named SyncStateMatrixTests cases — the `undo` lane (`UndoReconciliationTests` + `UndoPersistenceTests`) is simulator-only, and `DeviceCoreLoopTests.testFullSupportedLoopOnPhysicalDevice` drives capture/edit/complete/reopen/trash/restore but never undo. This gap is NOT named in the consolidated disclosures table."
  - truth: "ROADMAP SC5 — Jon can use the supported iPhone loop daily without opening Things for those actions"
    test: "Use the installed build as the only tool for capture / Inbox / Today / complete / trash for a sustained period."
    expected: "The loop is sufficient for daily use without falling back to Things."
    why_human: "Adoption is owner dogfood feedback. Disclosed in docs/testing/ios-testing.md consolidated row 7 as 'Not automatable at all, by design' — no lane asserts it and none ever will."
  - truth: "04-06 / 04-16 backstop (D-04 G7) — a write performed while the device is locked completes without an I/O or 0xdead10cc failure"
    test: "Lock the phone with its passcode, trigger a background write, and confirm no SQLITE_IOERR / 0xdead10cc."
    expected: "The .completeUntilFirstUserAuthentication class permits the write while locked."
    why_human: "`DataProtectionTests.testBackgroundWriteWhileLockedDoesNotTakeAnIOErrorOrTerminate` throws an explicit BLOCKED XCTSkip: devicectl exposes `info lockState` (a read) but no `lock` verb, and XCUIDevice's lock control is UI-testing-only while StorageTests is a unit bundle. Tracked open as WINDOWS.md row 63. The protection-class half IS proven on hardware; only the locked-write half is open."
  - truth: "04-14 coverage entry D9 — whether each mapped OverflowAndLongTextTests case fully discharges its corresponding 04-UI-SPEC.md prose, versus being a partial proxy"
    test: "Read the eight-element / sixteen-consideration table in docs/testing/ios-testing.md against 04-UI-SPEC.md § UI Considerations."
    expected: "Each mapped test's assertions actually cover the consideration's prose."
    why_human: "Explicitly disclosed by the phase as 'a judgment call for a human reviewer… rather than asserted as fully automated'."
coincidental_reliance_items:
  - truth: "04-02 — the app-owned migration ledger forward-migrates a version-1 database cleanly (MigrationLedgerTests.testMigration1FixtureMigratesForwardToVersion2PreservingVersion1Row)"
    reason: fixture-only
    harden: "The committed fixture apps/ios/Tests/StorageTests/Fixtures/migration-1.sqlite now contains schema_migrations rows [1, 2, 3] — verified directly against git HEAD. FixtureFactory.ensureMigration1Fixture() returns early when the file exists, so it is never regenerated. The test therefore opens an already-fully-migrated database and asserts rows == [1,2,3] tautologically on EVERY checkout. Fix: copy fixtures to a temp directory per run (WINDOWS.md row 64) AND regenerate/recommit migration-1.sqlite at version 1 only — row 64's claim that 'only the FIRST run on a fresh checkout' is affected is now optimistic, because the mutated file was committed in 624f9f3."
human_verification:
  - test: "Drive undo on the physical iPhone (capture → complete → named Undo control)"
    expected: "Undo is reachable and honored on hardware; the control persists until superseded, with no timer"
    why_human: "The device lane runs no undo case; undo is simulator-proven only, and this gap is undisclosed in the phase's own disclosures table"
  - test: "Sustained daily dogfood of the installed loop"
    expected: "Jon does not need Things for capture / Inbox / Today / complete / trash"
    why_human: "SC5 is owner feedback by design, disclosed as never-a-gate"
  - test: "G7 locked-device write"
    expected: "A write while the phone is locked does not fail with SQLITE_IOERR / 0xdead10cc"
    why_human: "No programmatic lock control exists; closing it would mean adding production surface solely to satisfy a gate (WINDOWS.md row 63)"
  - test: "Decide on the migration-1.sqlite fixture defect"
    expected: "Either regenerate the fixture at version 1 and copy-per-run, or accept and correct WINDOWS.md row 64's severity"
    why_human: "A committed already-migrated fixture makes one green test permanently vacuous — this contradicts the phase's own D-24 anti-vacuity posture and warrants an explicit decision"
  - test: "Accept the Debug-configuration substitution for the device suites"
    expected: "Proving the Release binary on hardware stays open, or is scheduled"
    why_human: "Disclosed and attested (BuildAttestation.configuration + attestation.mjs --expect-configuration), but it is a deliberate substitution a human should sign off on"
  - test: "Read the 04-14 sixteen-consideration discharge table against 04-UI-SPEC.md prose"
    expected: "Each mapped test genuinely discharges its consideration"
    why_human: "Disclosed by the phase itself as a human judgment call (04-14-SUMMARY coverage entry D9)"
---

# Phase 4: Native iPhone Daily Loop — Verification Report

**Phase Goal:** Jon can dogfood the same trustworthy core loop through a native, platform-integrated SwiftUI iPhone client.
**Verified:** 2026-09-08T23:40:00Z
**Status:** human_needed
**Re-verification:** No — initial verification
**Mode note:** ROADMAP marks this phase `mode: mvp`, but its goal is not in the required User Story form (`As a …, I want to …, so that ….`). MVP-mode User Flow Coverage was therefore not applied; standard goal-backward verification was used instead. Recorded as a process warning, not a code defect.

## Goal Achievement

This is one of the most honestly-evidenced phases I have verified. The gate is genuinely
anti-vacuous by construction, the disclosure surface is unusually complete, and every
artifact I checked was substantive and wired — not one stub, not one debt marker. The
findings below are narrow, and two of them are things the phase's own disclosure table
does not yet name.

### Observable Truths

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | **SC1** — a physical iPhone supports capture, Inbox, Today, edit, complete/reopen, trash/restore, **and undo** | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `DeviceCoreLoopTests.testFullSupportedLoopOnPhysicalDevice` drives capture → edit → Save & Move Out of Inbox → complete → reopen → trash → restore on hardware, plus `testTrashViaContextMenuOnPhysicalDevice` and `testPlanForTodayAndFindItOnTheTodayTabOnPhysicalDevice`. **Undo is absent from the device lane**: `tooling/ios-lanes/device.mjs:192-223` enumerates its `-only-testing` set and includes no undo suite; `UndoPersistenceTests`/`UndoReconciliationTests` are simulator-only (`tooling/ios-lanes/undo.mjs:17-18`). Undocumented in the consolidated disclosures table. |
| 2 | **SC2** — offline mutation, termination, relaunch, expired auth, account fencing, duplicate replay, structured conflict preserve intent and account isolation | ✓ VERIFIED | `DeviceRecoveryTests` (4 hardware cases: offline mutation survives SIGKILL+relaunch, no duplication, unsent draft survives, background/foreground restores) + `server-driven-device` lane driving the real Swift client against real Phoenix on real PostgreSQL behind the recording proxy. `ServerDrivenTests` asserts from `proxy.records`, and `XCTFail`s (never `XCTSkip`s) when no base URL is supplied (`ServerDrivenTests.swift:69`). |
| 3 | **SC3** — background execution is only an acceleration; foreground launch/resume/reconnect restores correctness | ✓ VERIFIED | `BackgroundAccelerationTests` proves the BG handler and `ScenePhaseDriver` call the identical `runSyncPass` entry point, that the full restoration scenario succeeds with the background path disabled entirely, and that expiration leaves every outbox row legal. Confirmed on hardware by `DeviceRecoveryTests.testBackgroundAndForegroundRestoresCorrectnessOnPhysicalDevice` and `DeviceCoreLoopTests.testForegroundResumeRestoresStateWithoutABackgroundWake`. |
| 4 | **SC4** — Dynamic Type, VoiceOver semantics, touch targets, Reduce Motion pass the supported flows | ✓ VERIFIED (with disclosed harness limit) | `AccessibilityAuditTests` (all seven audit types over the closed `ScreenInventory`), `DynamicTypeSnapshotTests`, `ReduceMotionTests`, `FocusSafetyTests`, plus a hardware confirmation run in the `device` lane that found a real device-only contrast defect (`.borderedProminent` automatic foreground, fixed in `TaskListEmptyState`). VoiceOver's synthesized speech and real rotor gestures are permanently outside any lane — disclosed (row 6). |
| 5 | **SC5** — Jon uses the iPhone loop daily without opening Things | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Owner dogfood feedback. Automatable proxy delivered (non-expiring profile, `build-ios-signed.mjs` install, all device cases green against the installed build). Disclosed row 7 as never-a-gate. |
| 6 | **04-01** — tracer capture, normalized contract, no pnpm membership | ✓ VERIFIED | `apps/ios/package.json` absent; `pnpm-workspace.yaml` globs `apps/*` but iOS carries no manifest so it is not a member. Zero real `nullable:` sites in `keepling.yaml` (all three grep hits are comments); `discriminator:` present at line 1967 with an honest recorded rationale where a conformant discriminator was impossible. `pnpm contracts:check` green. `node tooling/generate-ios-client.mjs --check` → "committed Swift client is current (9 files)". |
| 7 | **04-02** — 11 STRICT tables, G1–G6, ledger halts on drift, never repairs | ✓ VERIFIED (coincidental-reliance) | `MigrationLedger.swift`, `StoreUnrecoverable.swift`, `DurabilityPostureTests`, `CrashRecoveryTests`, `SourceDisciplineTests` all substantive. `testCorruptedChecksumFixtureThrowsChecksumDriftAndLeavesFileByteIdentical` is unusually self-aware (asserts ledger rows, per-table row counts and `integrity_check` rather than naive byte equality) and the fixture genuinely still carries the zeroed checksum. **But** the forward-migration case is fixture-only and now vacuous — see `coincidental_reliance_items`. |
| 8 | **04-03** — a third independent Swift reducer agrees with the Elixir and TypeScript references | ✓ VERIFIED (documented deviation) | `SyncReducer.swift` + `VectorConformanceTests.swift` resolve vectors from the source tree via a `#filePath` repository-root walk. The manifest gate ran green: "13 vector files, 15 consumer entries proven executed". **Deviation:** the must-have says "every case in all 13 golden vector files"; only `sync.json` lists `swift` as a consumer. The narrowing is justified in a committed artifact (`manifest.json`'s `_comment`: only `sync.json` binds `sync-state-machine.schema.json`) and machine-checked. See the override suggestion below. |
| 9 | **04-04** — accessory absence measured, not assumed; tokens generated | ✓ VERIFIED | `AccessoryHostability.swift:58` commits `.absenceAchievable(via: .conditionalModifier, measuredSDKVersion: "26.5")` from `AccessoryAbsenceProbeTests`, and it is genuinely consumed at `RootTabView.swift:46,74`. `node tooling/emit-swift-tokens.mjs --check` → "committed Swift token output is current". |
| 10 | **04-05** — decode round-trip over every vector payload; unreachable vs refused; hand-written mappers; HTTPS guard | ✓ VERIFIED | `KeeplingSyncAdapter.swift:83` throws `ConfigurationError.insecureBaseURL` unless scheme is https or host is `127.0.0.1`/`localhost` — unchanged and evaluated before credentials are consulted. `WireMappers.swift`, `ServerRefusal.swift`, `DecodeRoundTripTests.swift`, `TransportGuardTests.swift` all present and substantive. |
| 11 | **04-06** — terminal settlement (G8), durable unit, backup-replay no-op | ✓ VERIFIED (G7 locked-write half open) | `DurableUnit.swift`, `SettlementTests.swift`, `BackupReplayTests.swift` present. `DataProtectionTests` proves the requested class via `URLResourceValues` and full backup exclusion; the hardware case proves the class is enforceable with a passcode actually set. The locked-**write** backstop has no evidence — routed to human. |
| 12 | **04-07** — device-grant PKCE, Keychain-only credentials, server-only namespace activation, fencing | ✓ VERIFIED | `KeychainCredentialStore.swift:89,96` sets `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` on both add and update queries. `NamespaceActivation.swift`, `NamespaceFencingTests.swift`, `DeviceGrantTests.swift`, `CredentialStoreTests.swift` present. |
| 13 | **04-08** — bounded sync pass, outbound commands for the full loop, background as acceleration | ✓ VERIFIED | `ScenePhaseDriver.swift:77` and `BackgroundRefresh.swift` both route to `KeeplingApplication.runSyncPass` — the same entry point, asserted structurally by `BackgroundAccelerationTests`. |
| 14 | **04-09** — two-tab loop, locked gesture contract, durable capture draft | ✓ VERIFIED | `TaskRow.swift:159` — trailing swipe with `allowsFullSwipe: true` carries **only** Complete/Reopen; Trash appears only in `.contextMenu` (line 180) and the detail view. Repository-wide grep for `refreshable`, `onMove`, `EditButton` returns **zero** hits — no pull-to-refresh, no drag-to-reorder. |
| 15 | **04-10** — one authoritative sync presentation, conditional accessory, debounced announcements | ✓ VERIFIED | `SyncPresentation.swift`, `SyncCopy.swift`, `BottomAccessoryView.swift`, `SyncRecoverySheet.swift`, `TaskExceptionRow.swift` present; the accessory's healthy rendering reads `currentAccessoryHostability` at the one named site. |
| 16 | **04-11** — named, timerless undo as a compensating semantic action | ✓ VERIFIED | `UndoAvailability.swift`, `CompensatingCommands.swift`, `UndoControl.swift`, `UndoReconciliationTests.swift` present. Zero `Timer` / `asyncAfter` / `Task.sleep` in the undo path; repository-wide grep for `toast`/`snackbar` returns zero. *(Hardware coverage gap tracked under truth 1.)* |
| 17 | **04-12** — App Intents in the main target sharing one store handle | ✓ VERIFIED | `CaptureTaskIntent.swift:41` obtains `IntentStoreAccess.sharedStore()` and line 60 routes through `performOffMain` — one in-process handle, no App Group. |
| 18 | **04-13** — accessibility as release evidence | ✓ VERIFIED | See truth 4. `Motion.swift` is the single Reduce Motion gate; `ScreenInventory.swift` is the closed list driving the audit, Dynamic Type and DWC suites. |
| 19 | **04-14** — twelve-state matrix, held-out overflow/long-text suite | ✓ VERIFIED | `SyncStateMatrixTests.swift` (291 lines), `OverflowAndLongTextTests.swift` (379 lines), `StateInjection.swift`, `Fixtures/long-text.json` present; the sixteen-consideration discharge table is tabulated in `docs/testing/ios-testing.md`. The D9 discharge judgment is routed to human. |
| 20 | **04-15** — diagnostics reconstruct a bad day without carrying content | ✓ VERIFIED | `DiagnosticEvent.swift` is structurally content-free: identity is `UUID`-typed (never a title), transitions and error classes are closed `String`-raw-value enums, and the file carries no `String`-typed stored property. `DiagnosticPrivacyTests` (308 lines) + `DiagnosticCoverageTests` present. |
| 21 | **04-16** — physical-device evidence lane bound by read-back attestation | ✓ VERIFIED (Debug substitution disclosed) | `build-ios-signed.mjs`, `attestation.mjs`, `BuildAttestation.swift`, `resolve-devices.mjs` all substantive. Device suites `XCTSkip` **only** on `targetEnvironment(simulator)` — they cannot produce a device claim from simulator evidence. |
| 22 | **04-17** — the assembled anti-vacuous gate and machine-checked requirement map | ✓ VERIFIED | `node tooling/verify-ios-phase.mjs --requirements` ran clean here: all 5 requirements map to existing lanes. 24 lane files under `tooling/ios-lanes/` (25 entries minus README) matching the claimed `lanes=24`. The runner has no assume-it-passed fallback; a parse failure, a zero count, or a `BLOCKED` all keep the exit code non-zero. |
| 23 | **04-18** — server-driven scenarios on the real phone over a publicly-trusted tailnet host | ✓ VERIFIED | Repository-wide grep finds **no** `URLSessionDelegate`, `serverTrust`, `didReceive challenge`, or ATS arbitrary-loads exception anywhere in `apps/ios/Sources` — no test-only trust code on any configuration, exactly as the prohibition requires. The transport guard is byte-for-byte the original three conditions. `attestation.mjs --expect-configuration` refuses a configuration mismatch; `lock-probe.mjs` names a locked phone as its own BLOCKED reason. No `uninstall` verb anywhere in `tooling/ios-device` or `tooling/ios-lanes`. |

**Score:** 19/23 truths verified (4 present, behavior-unverified)

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|---|---|---|
| 1 | SRV-02's iPhone adapter proof completing the cross-adapter requirement | Phase 5 | REQUIREMENTS.md traceability: "SRV-02's iPhone adapter proof is unchanged and still completes only at the Phase 5 cross-adapter proof"; Phase 5 owns "SRV-02 MCP adapter proof and cross-adapter completion". The iPhone-side transport/reducer/orchestration proof itself IS delivered here (`transport`, `vector-conformance`, `sync-pass`, `server-driven-sim`, `server-driven-device` lanes). |

### Required Artifacts

All 90 artifacts named across the 18 plans' `must_haves.artifacts` exist, are substantive
(smallest is `TaskExceptionRow.swift` at 30 lines; the fixture `long-text.json` at 10 lines
is data), and are wired. Zero MISSING, zero STUB, zero ORPHANED. Spot-checked wiring:

| Artifact | Wired to | Status |
|---|---|---|
| `AccessoryHostability.swift` | `RootTabView.swift:46,74`, `AccessoryProbeRootView.swift:56` | ✓ WIRED |
| `ScenePhaseDriver.swift` / `BackgroundRefresh.swift` | `KeeplingApplication.runSyncPass` (identical entry point) | ✓ WIRED |
| `IntentStoreAccess.swift` | `CaptureTaskIntent.swift:41,60` | ✓ WIRED |
| `GeneratedTokens.swift` | `TokenSemantics` accessors used across every view | ✓ WIRED |
| `manifest.json` | `tooling/check-contracts.mjs` cross-consumer gate (ran green) | ✓ WIRED |
| `real-stack.mjs` | `server-driven-sim.mjs` / `server-driven-device.mjs` marker-line parsers | ✓ WIRED |

### Key Link Verification

| From | To | Via | Status |
|---|---|---|---|
| `CaptureSheet` | `GRDBLocalStore` | `CaptureCommand` → single `dbPool.write { }` (16 write sites, all transactional) → only then `local_saved` | ✓ WIRED |
| outbox row | settlement | acknowledgement identity + fingerprint → canonical/conflict → journal terminalization → exact row delete in one transaction | ✓ WIRED |
| `keepling.yaml` | `Transport/Generated/*.swift` | `generate-ios-client.mjs --check` reports the committed client current (9 files) | ✓ WIRED |
| `tokens.json` | `GeneratedTokens.swift` | `emit-swift-tokens.mjs --check` reports the committed output current | ✓ WIRED |
| build digest | running process on phone | `build-ios-signed.mjs` → Info.plist → `BuildAttestation` console line → `attestation.mjs` refuses on mismatch (digest **and** configuration) | ✓ WIRED |
| recording proxy | assertions | `ServerDrivenTests` reads `proxy.records`, never client belief; lane parser refuses zero arrivals / zero injections / zero refusals | ✓ WIRED |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|---|---|---|---|---|
| `TodayView` / `InboxView` | task rows | `WorkspaceFacade` snapshot ← `GRDBLocalStore` projection | yes | ✓ FLOWING |
| `BottomAccessoryView` | sync summary | `SyncPresentation.derive` (pure, injected clock) ← `KeeplingApplication` state | yes | ✓ FLOWING |
| `SyncStateMatrixTests` | twelve states | `StateInjection` launch environment (deterministic, test-only) | test input by design | ✓ FLOWING |

### Behavioral Spot-Checks

Per instruction, the full ~65-minute device gate was **not** re-run. Host-only checks:

| Behavior | Command | Result | Status |
|---|---|---|---|
| Requirement→lane map holds | `node tooling/verify-ios-phase.mjs --requirements` | 5 requirements, all mapped to existing lanes; exit 0 | ✓ PASS |
| Committed Swift tokens current | `node tooling/emit-swift-tokens.mjs --check` | "committed Swift token output is current" | ✓ PASS |
| Committed Swift client current | `node tooling/generate-ios-client.mjs --check` | "committed Swift client is current (9 files)" | ✓ PASS |
| Contract + vector manifest gate | `pnpm contracts:check` | green; "13 vector files, 15 consumer entries proven executed" | ✓ PASS |
| Lane count matches claim | `ls tooling/ios-lanes/` | 24 lane files + README = the claimed `lanes=24` | ✓ PASS |
| migration-1 fixture is a version-1 database | `sqlite3 <git HEAD blob> "SELECT version FROM schema_migrations"` | **1, 2, 3** | ✗ FAIL |
| Full gate `lanes=24 failed=0 blocked=0` | not run (65 min, phone away) | documented in `docs/testing/ios-testing.md` + `04-18-SUMMARY.md`, committed as `9340068` | ? SKIP |

### Requirements Coverage

| Requirement | Source Plans | Status | Evidence |
|---|---|---|---|
| IOS-01 | 04-01, 04-08, 04-09, 04-11, 04-12, 04-14, 04-16, 04-17 | ✓ SATISFIED (undo device-coverage gap) | Lanes `core-loop`, `undo`, `tracer-e2e`, `device`; hardware loop drives capture→edit→complete→reopen→trash→restore. Undo hardware-unproven (truth 1). |
| IOS-02 | 04-01, 04-02, 04-06, 04-07, 04-08, 04-15, 04-16, 04-17, 04-18 | ✓ SATISFIED | Lanes `storage`, `storage-gates`, `sync-pass`, `durability-posture`, `server-driven-sim`, `server-driven-device`, `device`. |
| IOS-03 | 04-04, 04-09, 04-13, 04-14, 04-16, 04-17 | ✓ SATISFIED (VoiceOver-speech gap disclosed) | Lanes `accessibility`, `state-matrix`, `design-tokens`; hardware confirmation run. |
| IOS-04 | 04-04, 04-07, 04-10, 04-11, 04-14, 04-15, 04-16, 04-17, 04-18 | ✓ SATISFIED (Debug-config disclosure) | Lanes `sync-presentation`, `auth`, `state-matrix`, `server-driven-device`, `device`; four named `SyncStateMatrixTests` cases run on hardware. |
| SRV-02 | 04-01, 04-03, 04-05, 04-08, 04-17, 04-18 | ⏸ DEFERRED (iPhone-adapter half satisfied) | Lanes `transport`, `vector-conformance`, `sync-pass`, `server-driven-*`; completes at the Phase 5 cross-adapter proof. |

No ORPHANED requirements: REQUIREMENTS.md maps exactly IOS-01..04 + SRV-02 to Phase 4, and every one appears in at least one plan's `requirements` frontmatter.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| — | — | `TBD` / `FIXME` / `XXX` | — | **Zero** across `apps/ios/Sources`, `apps/ios/Tests`, `tooling/ios-*`, and both testing docs |
| — | — | `TODO` / `HACK` / `PLACEHOLDER` | — | **Zero** (the three `placeholder` hits in `CaptureSheet.swift` are SwiftUI `TextField` placeholder-color commentary, not stubs) |
| `apps/ios/Tests/StorageTests/Fixtures/migration-1.sqlite` | — | vacuous-green fixture | ⚠️ Warning | Committed already fully migrated (rows 1,2,3), so `testMigration1FixtureMigratesForwardToVersion2PreservingVersion1Row` is tautological on every checkout |
| `tooling/ios-lanes/device.mjs` | 192–223 | undisclosed coverage gap | ⚠️ Warning | No undo suite on hardware, while SC1 and IOS-01's roadmap note both say "the full loop … undo" was driven on device |
| `apps/ios/Tests/KeeplingCoreTests/SyncPassTests.swift` | 310 | env-gated `XCTSkip` | ℹ️ Info | `testRealStackSettlesAPushedCapture` always skips in the `sync-pass` lane (which sets no `KEEPLING_TEST_SERVER_URL`), and Xcode's "Executed N tests" total counts skipped cases — so a lane's published case count can slightly overstate executed assertions. The real-server claim is not lost: `server-driven-sim`/`-device` cover it with far stronger, proxy-read assertions. |

### Gaps Summary

Nothing blocks the phase goal. The iPhone client is real, wired end to end, and the
evidence model is unusually rigorous — the gate refuses to report green on a missing
lane, a zero count, a stale build digest, a substituted build configuration, a locked
phone, or a proxy that recorded nothing.

Four items need a human decision:

1. **Undo is not proven on hardware, and that is not disclosed.** SC1 names undo among
   what a physical iPhone supports, and IOS-01's roadmap note says the device run "drove
   the full loop". `tooling/ios-lanes/device.mjs` names its suites explicitly and none of
   them touch undo. Either add a device undo case (cheap — the control is a plain button
   in the accessory and overflow menu) or add a row to the consolidated disclosures table.
   This is the one claim in the phase that currently reads as slightly more than it means.

2. **`migration-1.sqlite` is committed already-migrated.** WINDOWS.md row 64 describes the
   in-place fixture mutation but concludes "only the FIRST run on a fresh checkout tests a
   pre-migration database". That is now optimistic: the mutated 94208-byte file was
   committed in `624f9f3`, and `FixtureFactory.ensureMigration1Fixture()` never regenerates
   an existing file — so *no* run on *any* checkout tests forward migration from version 1
   any more. Row 64's severity should be corrected even if the fix is deferred.

3. **G7's locked-device write** remains open for a genuinely checkable reason (no
   programmatic lock control), tracked as WINDOWS.md row 63. The compounding half is
   closed — the phone now has a passcode and the protection class is proven enforceable
   on hardware.

4. **The Debug-configuration substitution** for the device suites and the **04-14 D9
   discharge judgment** are both disclosed and attested rather than silent; they want an
   explicit human acceptance, not a fix.

### Suggested Override

Plan 04-03's must-have says the Swift reducer agrees "on every case in all 13 golden
vector files", but only `sync.json` binds the sync state machine — the other 12 bind
Elixir-owned domain shapes. The narrowing is committed, reasoned, and machine-checked in
`packages/contracts/vectors/manifest.json`. To accept it formally, add to this file's
frontmatter:

```yaml
overrides:
  - must_have: "A third independent implementation of the synchronization reducer, written in Swift, agrees with the Elixir reference model and the TypeScript desktop consumer on every case in all 13 golden vector files (SRV-02, D-10)."
    reason: "Only sync.json binds sync-state-machine.schema.json; the other 12 files bind Elixir-owned domain shapes with no Swift consumer. Recorded in packages/contracts/vectors/manifest.json's _comment and enforced by check-contracts.mjs's cross-consumer gate (13 files, 15 consumer entries proven executed)."
    accepted_by: "jon"
    accepted_at: "2026-09-08T00:00:00Z"
```

---

_Verified: 2026-09-08T23:40:00Z_
_Verifier: Claude (gsd-verifier)_
