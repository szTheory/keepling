---
phase: KPL-04-native-iphone-daily-loop
plan: 16
subsystem: ios
tags: [xcodebuild, devicectl, codesigning, provisioning, attestation, xctest, phoenix, postgresql]

requires:
  - phase: KPL-04-01
    provides: "the KeeplingBuildDigest Info.plist key and the committed Signing.xcconfig / gitignored Signing.local.xcconfig split this plan's build script depends on"
  - phase: KPL-04-06
    provides: "StorageTests/DataProtectionTests' G7 assertion and its recorded simulator skip -- the skip this plan converts into a real hardware assertion plus a narrowly-named BLOCKED remainder"
  - phase: KPL-04-13
    provides: "AccessibilityAuditTests/DynamicTypeSnapshotTests -- the suites the device lane re-runs once on hardware as D-22 Criterion 4's confirmation run"
  - phase: KPL-04-17
    provides: "tooling/verify-ios-phase.mjs, its lane contract, and the BLOCKED convention this plan's device lane now reports through"
provides:
  - "tooling/ios-device/resolve-devices.mjs: hardwareUdid and devicectlIdentifier as separate named fields, cross-checked against xctrace, refusing when equal, plus a devicectl lockState passcode probe"
  - "tooling/build-ios-signed.mjs: xcodegen -> archive -> development export -> devicectl direct install, digest injected before signing, ten-field provenance manifest, and a machine refusal of any provisioning profile valid <= 30 days (D-17)"
  - "apps/ios/Sources/Keepling/App/BuildAttestation.swift: three read-back channels (console, app-container receipt, lane-gated accessibility probe) out of the RUNNING process"
  - "tooling/ios-device/attestation.mjs: the refusal gate -- exits non-zero on digest mismatch before any test runs, and names a locked phone and a CoreDevice transport flake as distinct conditions"
  - "tooling/ios-device/hard-kill.mjs: out-of-process SIGKILL through devicectl (which takes a PID, not a bundle id)"
  - "tooling/verify-real-stack-ios.mjs: real Phoenix on real PostgreSQL behind a recording forwarding proxy with server-side fault injection, plus a measured device-reachability probe"
  - "apps/ios/Tests/KeeplingUITests/DeviceCoreLoopTests.swift and DeviceRecoveryTests.swift: physical-device suites bound to the installed build"
  - "tooling/ios-lanes/device.mjs: a real device lane replacing 04-17's always-BLOCKED placeholder"
  - "docs/testing/ios-dogfood.md: the four D-22 disclosures, the G7 split, and the measured transport blocker"
affects: [04-17]

estimate_vs_actual:
  estimated_tokens: 190000
actuals:
  tokens: 88000
  tasks: 3
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Identity by ATTESTATION rather than reproducibility: an iOS artifact cannot hash stably (CMS signature timestamp + per-build nonce), so the digest is injected into Info.plist BEFORE signing and read back out of the RUNNING process on the phone -- three independent channels, any disagreement a refusal."
    - "The digest input list is `git ls-files --cached --others --exclude-standard`, not `--cached` alone: restricting to tracked files would let an added-but-uncommitted source file leave the digest unmoved, so two genuinely different builds would attest to the same value."
    - "A gitignored secret-adjacent value (the Apple Team ID) is kept out of recorded evidence by construction: the manifest is asserted not to contain it before it is written, and `git grep` confirms it appears in no tracked file."
    - "Machine evidence replaces a human's word wherever one exists: `devicectl device info lockState` answers 'is a passcode set', and the embedded profile's own creation/expiry window answers 'is this a paid membership or a seven-day personal team'."
    - "A transient-transport retry is scoped so narrowly it cannot launder a real failure: the attestation retries ONLY when no digest was read AND the output names a CoreDevice transport error. A digest that was read and did not match is never retried."

key-files:
  created:
    - tooling/build-ios-signed.mjs
    - tooling/verify-real-stack-ios.mjs
    - tooling/ios-device/resolve-devices.mjs
    - tooling/ios-device/attestation.mjs
    - tooling/ios-device/hard-kill.mjs
    - apps/ios/Sources/Keepling/App/BuildAttestation.swift
    - apps/ios/Tests/KeeplingUITests/DeviceCoreLoopTests.swift
    - apps/ios/Tests/KeeplingUITests/DeviceRecoveryTests.swift
    - docs/testing/ios-dogfood.md
  modified:
    - apps/ios/Sources/Keepling/App/KeeplingApp.swift
    - apps/ios/Tests/StorageTests/DataProtectionTests.swift
    - tooling/ios-lanes/device.mjs
    - package.json

key-decisions:
  - "The exported artifact is a real `xcodebuild archive` + development `-exportArchive` producing a signed `.ipa`, not a zipped `.app`. `archiveSha256` then means what its name says, and the bytes installed on the phone are the bytes hashed."
  - "`build-ios-signed.mjs` runs `xcodegen generate` itself. XcodeGen enumerates sources at GENERATION time, and a project regenerated before a file was added compiles a stale file list -- measured here as `buildAttestationProbe()` 'has no member' while the file sat on disk."
  - "`build-ios-signed.mjs` refuses any provisioning profile whose validity window is <= 30 days. This converts D-17 from an instruction into a check: a free personal-team profile is 7 days and a paid one is 365, so the profile itself is the evidence of which membership signed the build."
  - "The Apple Team ID is written to NO tracked file and to NO recorded artifact. `apps/ios/Signing.local.xcconfig` is created from the committed example and stays gitignored; the generated ExportOptions.plist lives under gitignored `.artifacts/`; and the manifest is asserted not to contain the ID before being written."
  - "A byte-identical replay is asserted against the server's ACTUAL contract, not the plan's wording. `CommandStore.replay/4` returns the original receipt verbatim -- same `accepted` outcome, same revision, no second task -- which is exactly-once done properly. `already_satisfied` is this server's word for a SEMANTIC no-op, and is exercised separately by completing an already-completed task. Asserting the plan's literal `already_satisfied` for a replay would have meant failing a correct server or 'fixing' the server to match a test."
  - "Cross-ACCOUNT fencing is not constructible against this server: `accounts` carries `singleton_key TRUE` and the seed creates exactly one account. The fence the product actually has -- the SESSION fence -- is asserted for real instead (after logout, the retained credential buys neither an accepted push nor a readable row), and the substitution is disclosed rather than presented as the cross-account case."
  - "The device lane reports `BLOCKED` rather than returning a positive case count even when device cases pass, because the server-driven half of D-22 Criterion 2 is unproven. Returning green on the offline half alone would let IOS-02's server-driven half look proven forever."
  - "Widening `KeeplingSyncAdapter`'s transport guard to admit LAN/.local hosts was considered and REFUSED. Relaxing a deliberate security decision -- one with its own tests (T-04-01-03/T-04-05-04) -- so that a lane goes green is the exact false-evidence failure this phase exists to prevent."

requirements-completed: []

coverage:
  - id: D1
    description: "Both device identifier spaces are resolved separately, cross-checked, and refused if equal"
    requirement: IOS-01
    verification:
      - kind: integration
        ref: "`node tooling/ios-device/resolve-devices.mjs` -- exit 0, printed hardware_udid=<REDACTED-DEVICE-UDID>, devicectl_identifier=<REDACTED-COREDEVICE-ID>, identifiers_distinct=true, xctrace_cross_checked=true"
        status: pass
    human_judgment: false
  - id: D2
    description: "A development-signed build is produced with -allowProvisioningUpdates, carries an injected KeeplingBuildDigest, and installs on the physical iPhone by devicectl direct install"
    requirement: IOS-01
    verification:
      - kind: integration
        ref: "`node tooling/build-ios-signed.mjs` -- exit 0; IOS_BUILD_MANIFEST digest=42a2cb1b50d2d17299d8f7167086dfe0 profile_uuid=<REDACTED-PROFILE-UUID> profile_validity_days=365 identity=<REDACTED-SIGNING-IDENTITY> installed=true"
        status: pass
    human_judgment: false
  - id: D3
    description: "The provenance manifest carries all ten named fields"
    requirement: IOS-01
    verification:
      - kind: static
        ref: "the plan's own <verify> node -e field check over .artifacts/ios/build-manifest.json -- output 'provenance manifest complete', exit 0"
        status: pass
    human_judgment: false
  - id: D4
    description: "The lane reads KeeplingBuildDigest back out of the RUNNING process on the phone and refuses on mismatch"
    requirement: IOS-01
    verification:
      - kind: integration
        ref: "`node tooling/ios-device/attestation.mjs --expect-installed` -- ATTESTATION matched=true digest=8bcae5f232c177a479a17f2e366aa720 receipt_channel=agreed, exit 0"
        status: pass
      - kind: integration
        ref: "`node tooling/ios-device/attestation.mjs --expect-digest deadbeefdeadbeefdeadbeefdeadbeef` -- ATTESTATION REFUSED naming both digests, exit 1 (the deliberate-mismatch proof the plan required)"
        status: pass
    human_judgment: false
  - id: D5
    description: "A non-expiring (paid-membership) provisioning profile signed the installed build, and it lists this phone"
    requirement: IOS-01
    verification:
      - kind: integration
        ref: "build-ios-signed.mjs refuses profiles valid <= 30 days; this build's embedded profile is valid 365 days (2026-09-05 -> 2027-09-05) and its ProvisionedDevices contains <REDACTED-DEVICE-UDID>"
        status: pass
    human_judgment: false
  - id: D6
    description: "Real Phoenix on real PostgreSQL behind a recording proxy, with server-side injection, proves duplicate-replay exactly-once, semantic already_satisfied, structured conflict, authentication expiry, and the session fence -- each asserted against what the proxy recorded"
    requirement: SRV-02
    verification:
      - kind: integration
        ref: "`node tooling/verify-real-stack-ios.mjs` -- IOS_REAL_STACK_SERVER recorded_requests=13 command_arrivals=9 replay_receipt=accepted@rev1 duplicate_tasks=0 semantic_no_op=already_satisfied conflict_status=409 auth_expiry_status=401 fenced_push_status=401 fenced_read_status=401 injected=1"
        status: pass
    human_judgment: false
  - id: D7
    description: "The device suites and the hardware DataProtection assertion compile and link for the physical device against the signed build"
    requirement: IOS-01
    verification:
      - kind: integration
        ref: "`xcodebuild build-for-testing -destination platform=iOS,id=00008140-... -allowProvisioningUpdates KEEPLING_BUILD_DIGEST=42a2cb1b...` -- ** TEST BUILD SUCCEEDED **, exit 0"
        status: pass
    human_judgment: false
  - id: D8
    description: "The physical-device suites EXECUTE and pass on the phone"
    requirement: IOS-01
    verification:
      - kind: integration
        ref: "`node tooling/verify-ios-phase.mjs --lane device` -- LANE name=device status=BLOCKED cases=0: the iPhone is locked and iOS refuses to launch any app on a locked device"
        status: blocked
    human_judgment: true
    rationale: "Unlocking the phone requires the passcode, which no tool in this repository can supply and which this project's zero-human-UAT constraint cannot remove. The suites compile and link for the device (D7), the attestation gate they run behind is proven working on this exact phone (D4), and the lane's refusal names the condition precisely. A human must unlock the phone and re-run `node tooling/verify-ios-phase.mjs --lane device` for this row to move to pass."
  - id: D9
    description: "The server-driven half of D-22 Criterion 2 runs on the DEVICE (auth expiry, fencing, replay, conflict injected server-side and asserted against the proxy's recording)"
    requirement: IOS-02
    verification:
      - kind: integration
        ref: "`node tooling/verify-real-stack-ios.mjs` measures it: the app's transport guard refuses a LAN http:// base URL, and over TLS URLSession rejects the lane's self-signed certificate"
        status: blocked
    human_judgment: true
    rationale: "Needs an architectural decision this plan did not make: a DEBUG-only, launch-env-gated lane CA trusted through an injected ClientTransport, versus widening the production transport guard, versus deferring. Widening the guard is refused. Recorded in .planning/WINDOWS.md and in docs/testing/ios-dogfood.md."
  - id: D10
    description: "Gate G7's locked-device WRITE completes without an I/O failure"
    requirement: IOS-02
    verification:
      - kind: unit
        ref: "StorageTests/DataProtectionTests#testBackgroundWriteWhileLockedDoesNotTakeAnIOErrorOrTerminate -- named BLOCKED skip"
        status: blocked
    human_judgment: true
    rationale: "Nothing available can lock the phone under program control: devicectl exposes `info lockState` (a read) but no lock verb, and XCUIDevice's lock control is UI-testing-only while DataProtectionTests is a unit-test bundle. The enforceable-class half is proven on hardware, and the phone's passcodeRequired=true is machine-recorded."
  - id: D11
    description: "All four D-22 disclosures are written down by name"
    verification:
      - kind: static
        ref: "docs/testing/ios-dogfood.md sections 'Criterion 2 -- termination', 'Criterion 3 -- background wake', 'Criterion 4 -- accessibility', 'Criterion 5 -- sustained daily use'"
        status: pass
    human_judgment: false

duration: 165min
completed: 2026-09-06
status: complete
---

# Phase KPL-04 Plan 16: Keepling on Jon's Actual Phone Summary

**A paid-membership, development-signed build of Keepling is installed on Jon's physical iPhone 16 Pro Max under a 365-day provisioning profile, carrying a source digest injected before signing that `tooling/ios-device/attestation.mjs` reads back out of the running process and refuses on mismatch — proven both ways on that exact phone — while the real Phoenix/PostgreSQL recording-proxy lane proves exactly-once replay, semantic `already_satisfied`, a real 409 conflict, server-injected authentication expiry, and a real session fence against what the server actually received; the physical-device UI suites compile and link for the device but have not executed, because the phone is locked and iOS refuses to launch any app on a locked device, and the server-driven half of Criterion 2 is measurably blocked by the app's own transport guard.**

## Performance

- **Duration:** ~165 min
- **Tasks:** 3 of 3 (Task 1 checkpoint satisfied and evidenced; Tasks 2 and 3 executed)
- **Files created/modified:** 13 (9 created, 4 modified)
- **Commits:** `cc292b7`, `94a3ad0`

## Task 1 — the human-action checkpoint, evidenced rather than assumed

Both prerequisites were confirmed by machine, not by anyone's word.

| Fact | Evidence |
|---|---|
| A physical iPhone is attached and trusted | `xcrun devicectl list devices` — "<REDACTED-DEVICE-NAME>", iPhone 16 Pro Max (iPhone17,2), iOS **26.6.1**, state `available (paired)` |
| **CoreDevice identifier** | `<REDACTED-COREDEVICE-ID>` |
| **Hardware UDID** | `<REDACTED-DEVICE-UDID>` (`xcrun xctrace list devices`, cross-checked by `resolve-devices.mjs`) |
| A valid Apple Development identity exists | `security find-identity -v -p codesigning` — 3 valid identities; the one that signed this build is **`<REDACTED-SIGNING-IDENTITY>`** — "Apple Development: <REDACTED-DEVELOPER-NAME> (<REDACTED-TEAM-ID>)" |
| A development team is configured for the Keepling scheme | `xcodebuild -showBuildSettings` reports a `DEVELOPMENT_TEAM` (the value itself is deliberately not recorded anywhere in the repository) |
| **The device has a passcode set** | `xcrun devicectl device info lockState` — **`passcodeRequired: true`**, `unlockedSinceBoot: true`. This is machine evidence, not a human assurance, and it is what makes G7's protection class enforceable rather than nominal. |
| **The membership is paid, not a personal team** | The embedded profile's own window: created 2026-09-05, expires 2027-09-05 — **365 days**. A free personal-team profile is 7. `build-ios-signed.mjs` refuses anything ≤ 30 days. |
| Profile UUID | `<REDACTED-PROFILE-UUID>`, `TeamIdentifier` present, `ProvisionedDevices` contains `<REDACTED-DEVICE-UDID>` |

The gitignored `apps/ios/Signing.local.xcconfig` was created from the committed example in this
worktree. `git check-ignore` confirms it is ignored, and `git grep` confirms the Team ID appears in
**no tracked file**.

## Task 2 — signed build, two identifier spaces, read-back attestation

- **`resolve-devices.mjs`** returns `hardwareUdid` and `devicectlIdentifier` as separate named
  fields, cross-checks the UDID against `xctrace` (whose identifier space `xcodebuild -destination`
  shares), refuses if the two are ever equal, refuses if more than one iPhone is paired without an
  explicit `KEEPLING_IOS_DEVICE`, and reports the `lockState` passcode probe.
- **`build-ios-signed.mjs`** runs `xcodegen generate` → `xcodebuild archive -allowProvisioningUpdates`
  with `KEEPLING_BUILD_DIGEST=<digest>` → development `-exportArchive` → `devicectl device install
  app`. It writes all ten provenance fields plus the device and profile details, and it refuses to
  write a manifest containing the Team ID.
- **`BuildAttestation.swift`** emits the digest on stdout (with an explicit `fflush`, because a line
  left in a pipe buffer would be indistinguishable from a build with no digest), writes a receipt
  into the app's own container, and renders a lane-gated hidden accessibility element.
- **`attestation.mjs`** launched the app on the phone, read `digest=8bcae5f232c177a479a17f2e366aa720`
  back off the console, corroborated it against the container receipt (`receipt_channel=agreed`),
  and — run against `--expect-digest deadbeef…` — **refused with exit 1**. Both directions proven on
  this exact device.
- **`verify-real-stack-ios.mjs`** starts the shared backend harness (real PostgreSQL 18.6, real
  migrations, real seed, real Phoenix on Elixir 1.20.2/OTP 29.0.5) behind a recording forwarding
  proxy, and passes its server half green.

## Task 3 — the device evidence lane

- `DeviceCoreLoopTests` (full loop, context-menu trash, plan-for-today, foreground resume) and
  `DeviceRecoveryTests` (hard-kill durability, exactly-once relaunch projection, durable
  capture-draft survival, background/foreground correctness) both bind every case to the installed
  build through the attestation probe and refuse to run on a simulator.
- `DataProtectionTests` gained a hardware-only case asserting the protection class where iOS
  actually enforces it, and its remaining skip now states precisely what is missing and why.
- `tooling/ios-lanes/device.mjs` replaces 04-17's always-BLOCKED placeholder with a real lane:
  attestation refusal first, then out-of-process SIGKILL, then the device suites plus the
  Criterion 4 accessibility confirmation run — with the same digest injected so the reinstall stays
  bound.
- `docs/testing/ios-dogfood.md` states all four D-22 disclosures by name, splits G7 honestly, and
  says explicitly that attaching the device is the only non-automated act in this lane.

## Gate results

| Gate | Result |
|---|---|
| `node tooling/ios-device/resolve-devices.mjs` | **PASS** — both identifiers distinct, xctrace cross-checked |
| `node tooling/build-ios-signed.mjs` | **PASS** — signed, exported, installed; 365-day profile |
| provenance-manifest field check | **PASS** — `provenance manifest complete` |
| `attestation.mjs --expect-installed` | **PASS** — matched, both channels agreed |
| `attestation.mjs --expect-digest <wrong>` | **PASS (refused, exit 1)** — the D-21 refusal proven |
| `node tooling/verify-real-stack-ios.mjs` (server half) | **PASS** — 13 recorded requests, 9 command arrivals, exactly-once replay, `already_satisfied`, 409, 401, session fence |
| `xcodebuild build-for-testing` (device, signed) | **PASS** — `** TEST BUILD SUCCEEDED **` |
| `node tooling/verify-ios-phase.mjs --lane device` | **BLOCKED** — the iPhone is locked |
| `verify-real-stack-ios.mjs` device probe | **BLOCKED** — the iPhone is locked |
| G7 locked-device write | **BLOCKED** — no programmatic lock control exists |
| Server-driven half of D-22 Criterion 2 on device | **BLOCKED** — the app's own transport guard |

## BLOCKED gates, named

### 1. The device UI suites did not execute — the iPhone is locked

`xcrun devicectl device process launch` fails with
`FBSOpenApplicationErrorDomain error 7 (Locked)` — *"Unable to launch com.szTheory.keepling because
the device was not, or could not be, unlocked."* iOS will not launch any app on a locked device.
Unlocking requires the passcode, which no tool here can supply.

This is **not** a build defect and **not** an attestation mismatch. The install succeeded; the
suites compile and link for the device; the attestation gate is proven working on this phone. What
is missing is one unlocked screen. `attestation.mjs` and `verify-real-stack-ios.mjs` both now detect
this condition specifically rather than reporting the misleading downstream symptom.

**To clear it:** unlock the phone, then `node tooling/verify-ios-phase.mjs --lane device`.

Note for the record: `devicectl device info lockState` reports only `passcodeRequired` and
`unlockedSinceBoot` — it does **not** report the current lock state — which is why this is detected
from the launch refusal itself.

### 2. The server-driven half of D-22 Criterion 2 — measured, not assumed

`KeeplingSyncAdapter`'s constructor refuses any non-HTTPS base URL whose host is not `127.0.0.1` or
`localhost` (T-04-01-03/T-04-05-04). On the Mac that costs nothing; a physical phone can only reach
the build Mac at a LAN address. `verify-real-stack-ios.mjs` probes both paths on every run: over
plain HTTP nothing leaves the phone, and over TLS the phone **genuinely connects** (the lane's TLS
listener records the attempt) before URLSession rejects the self-signed certificate — so **routing
works and the blocker is certificate trust, not networking.**

Closing it needs a decision this plan did not make: (a) a `#if DEBUG`, launch-env-gated lane CA
trusted through an injected `ClientTransport`; (b) widening the production transport guard; or
(c) deferring. **(b) is refused** — relaxing a deliberate security guard so a lane goes green is the
false-evidence failure this phase exists to prevent.

### 3. G7's locked-device write

`devicectl` has no lock verb (only `info lockState`, a read); `XCUIDevice`'s lock control is
UI-testing-only and `DataProtectionTests` is a unit-test bundle. Driving it from the UI-test target
would require a new app-side `protectedDataWillBecomeUnavailable` write hook — new production
surface added solely to pass a gate. The **enforceable-class** half of G7 runs on hardware, and
`passcodeRequired: true` is machine-recorded.

## D-22 Criterion 5, stated plainly

Criterion 5 is **not automatable and is not a gate.** The closest automatable proxy is delivered:
the supported loop is installed on the physical device under a **non-expiring (365-day) profile**,
bound to the shipped build by read-back attestation. **Sustained daily adoption is owner dogfood
feedback, not a gate** — nobody signs off on it and nothing counts it.

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 3 — Blocking] `build-ios-signed.mjs` now runs `xcodegen generate` itself**
- **Found during:** Task 2. `BuildAttestation.swift` was on disk but absent from the compile list, so `buildAttestationProbe()` "had no member" — a stale generated project, not a Swift error.
- **Fix:** the build script regenerates the project first, which also picks up a newly created `Signing.local.xcconfig`.
- **Commit:** `cc292b7`

**2. [Rule 1 — Bug] The digest input list uses `--cached --others --exclude-standard`**
- **Issue:** `git ls-files` over tracked files alone would leave the digest unmoved by an added-but-uncommitted source file, so two genuinely different builds would attest to the same value.
- **Commit:** `cc292b7`

**3. [Rule 1 — Bug] The recording proxy forwards `Host` unchanged**
- **Issue:** rewriting `Host` to the upstream address broke the server's `require_trusted_origin` check (it compares `Origin` to `scheme://<host header>`), producing a blanket 403.
- **Commit:** `cc292b7`

**4. [Rule 1 — Bug] Lane failures no longer leak PostgreSQL and Phoenix**
- **Issue:** an assertion that called `process.exit` skipped shutdown; the next run then failed on a held port with a message about the wrong problem.
- **Fix:** assertions throw and route through one shutdown path; a held-port preflight refuses to attach to a server the lane did not start.
- **Commit:** `cc292b7`

**5. [Rule 2 — Missing critical] `-destination-timeout 300` on the device test invocation**
- **Issue:** a wirelessly-paired iPhone is not instantly "available" to xcodebuild even with a live CoreDevice tunnel; the default wait expired and the run died with "Timed out waiting for all destinations", which reads like an absent phone.
- **Commit:** `94a3ad0`

**6. [Rule 2 — Missing critical] `KEEPLING_BUILD_DIGEST` passed to `xcodebuild test`**
- **Issue:** `xcodebuild test` rebuilds and reinstalls the app; without the injection the reinstalled build would carry the fallback digest and the suites' binding assertion would fail as a phantom mismatch.
- **Commit:** `94a3ad0`

**7. [Rule 2 — Missing critical] Locked-phone and transport-flake detection**
- **Issue:** a locked phone surfaced as "the running process never reported a build digest", which sends a reader hunting for a build bug; a CoreDevice tunnel drop failed the whole run.
- **Fix:** both conditions are named specifically. The retry is scoped so it can never launder a real mismatch.
- **Commit:** `94a3ad0`

**8. [Rule 3 — Blocking] `mix deps.get` / `mix compile` in this fresh worktree**
- Lockfile-pinned dependencies only; no new package was introduced.

### Contract corrections (plan expectation vs. measured reality)

**9. Duplicate replay does not settle `already_satisfied`.** The plan's acceptance criterion
expected that word. `CommandStore.replay/4` returns the **original receipt verbatim** for a
byte-identical replay — same `accepted` outcome, same revision, no second task — which *is*
exactly-once. `already_satisfied` is this server's word for a **semantic** no-op. Both shapes are
now asserted, each against what it actually means, plus a read-back of the server's inbox proving
`duplicate_tasks=0`. Asserting the plan's literal wording would have meant failing a correct server
or changing the server to match a test.

**10. Cross-account fencing is not constructible.** `accounts` carries `singleton_key TRUE` and the
seed creates exactly one account — the deployment is architecturally single-account. The **session
fence** is asserted for real instead (after logout the retained credential yields
`fenced_push_status=401` and `fenced_read_status=401`), and the substitution is disclosed rather
than dressed up as the cross-account case.

### Files touched beyond the plan's list

- `apps/ios/Sources/Keepling/App/KeeplingApp.swift` — one modifier applied at the app root so the
  attestation channels exist. `RootTabView` and every other view file are untouched.
- `tooling/ios-device/hard-kill.mjs` — a new file: `devicectl terminate` takes a PID, not a bundle
  id, so the PID lookup (JSON, the only interface Apple supports for scripts) needed a home other
  than a shell pipeline inside the lane.

## Known Stubs

None. Every skip in this plan is a named `BLOCKED` with its reason, not a placeholder.

## Requirements

`requirements-completed` is deliberately **empty**. IOS-01, IOS-02, IOS-03, IOS-04 and SRV-02 each
depend on device-executed evidence that has not run (BLOCKED #1) or on the server-driven device half
(BLOCKED #2). Marking any of them complete on the strength of a compiled-but-unexecuted suite would
be exactly the false citation this project's anti-vacuity contract forbids.

## Self-Check: PASSED

All ten files claimed above exist on disk, and both commits (`cc292b7`, `94a3ad0`) exist in
`git log`.
