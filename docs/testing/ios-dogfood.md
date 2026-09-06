# iOS Dogfood (D-17/D-20/D-21/D-22)

**Nothing in this document is a checklist, a gate, or a sign-off. There is no form to fill in,
nothing to count, and nothing to certify.** Keepling's evidence comes from machines. What is asked
of a person is one thing only: use the app on the phone and say what you think.

**Attaching the iPhone is the only non-automated act in this lane.** Every case below is scripted:
the build is signed and installed by `tooling/build-ios-signed.mjs`, its identity is read back out
of the running process by `tooling/ios-device/attestation.mjs`, the no-notice kill is delivered by
`tooling/ios-device/hard-kill.mjs`, and the suites are driven by `xcodebuild test` against the
physical device. Nobody taps anything to produce a result. That is the project's zero-human-UAT
constraint, stated here so a later plan does not quietly reintroduce a manual pass.

## Just use it, and tell me what you think

Use the installed app on the phone for whatever you would normally use a task app for. If
something annoys you, feels slow, reads wrong, or makes you reach for another app instead — say
so, in whatever form is convenient. A sentence is fine. There is no required cadence, no required
duration, no active-day count, and no disposition vocabulary.

That is the whole contract.

## What binds this evidence to a build

iOS artifacts are **not byte-reproducible**: the CMS code signature carries a signing timestamp and
a per-build nonce, and `embedded.mobileprovision` is re-stamped by automatic provisioning. Two
builds of identical source therefore hash differently, always. This is a property of Apple's
signing format, not a packaging defect of the kind `tooling/verify-package-reproducibility.mjs`
correctly catches for the Mac app — do not add a reproducibility check here.

Identity is proven by **attestation** instead (D-21):

1. `tooling/build-ios-signed.mjs` computes a digest over the build's real source inputs and injects
   it into `Info.plist` as `KeeplingBuildDigest` **before signing**, so the value is covered by the
   signature it attests to.
2. `BuildAttestation.swift` emits that value out of the **running process** on the phone — on
   stdout (captured by `devicectl … --console`), into a receipt in the app's own container (copied
   back with `devicectl device copy from`), and, when the lane asks, as a hidden accessibility
   element the device suites bind their own assertions to.
3. `tooling/ios-device/attestation.mjs` compares it with `.artifacts/ios/build-manifest.json` and
   **refuses the run on mismatch, before any test executes.** A lane that ran its suite and then
   checked identity would already have spent the evidence.

`.artifacts/ios/build-manifest.json` records ten provenance fields: `gitRevision`, `xcodeVersion`,
`sdkVersion`, `signingIdentityFingerprint`, `provisioningProfileUUID`, `cfBundleVersion`,
`archiveSha256`, `appBundleAdvisorySha256`, `laneSourceDigest`, and `keeplingBuildDigest`. The
bundle hash is named **advisory** deliberately: it excludes `_CodeSignature/` and
`embedded.mobileprovision`, is useful for spotting an unexpected code change, and is not an
identity claim — nothing gates on it.

## Two identifier spaces, never one

A physical iPhone has two identifiers that look alike and are not interchangeable:

| Identifier | Spoken by | Example shape |
|---|---|---|
| Hardware UDID | `xcodebuild -destination`, `xctrace`, provisioning profiles | `00008140-XXXXXXXXXXXXXXXX` |
| CoreDevice identifier | `devicectl --device` | `455FFAE9-XXXX-XXXX-XXXX-XXXXXXXXXXXX` |

`tooling/ios-device/resolve-devices.mjs` returns them as separately named fields, cross-checks the
UDID against `xctrace`, and **fails loudly if the two are equal** — a run where the distinction was
invisible would let an interchange bug survive to the next device, where it would target the wrong
phone.

## The install path is `devicectl` direct install, and nothing else (D-19)

TestFlight and the App Store are deferred to Phase 6. Upload plus processing latency plus a 90-day
build expiry buy this phase no evidentiary value: the claim under test is "the loop runs on Jon's
actual phone", and a direct install proves exactly that, sooner. `tooling/ios-lanes/device.mjs`
asserts that no script in this lane references `altool`, `notarytool`, App Store Connect, or a
distribution export method.

## The profile must not expire (D-17)

A **free personal-team** provisioning profile expires seven days after creation and hard-stops the
installed app — the exact recurring manual step this project forbids, failing precisely when a week
away from the build Mac makes mobile capture matter most. `tooling/build-ios-signed.mjs` does not
take anyone's word for which kind signed a build: it reads the embedded profile's own creation and
expiry dates and **refuses any profile whose validity window is 30 days or shorter.**

## D-22's disclosures, stated plainly

These are the claims this lane does **not** make. They are named rather than left to be inferred
from what the lane happens to assert (T-04-16-08).

### Criterion 2 — termination

**OS-initiated jetsam under memory pressure is not induced.** It cannot be requested on demand.
Termination is proven by a signal-based hard kill (`devicectl device process terminate --kill`,
SIGKILL), which is the **stricter** no-notice case: SIGKILL cannot be caught and the app runs no
shutdown path at all, whereas a jetsam kill may follow a clean suspension. The weaker case is not
silently claimed under the stronger one's evidence.

### Criterion 3 — background wake

**Real `BGTaskScheduler` wake scheduling is not asserted.** Apple schedules background refresh
opportunistically, on its own judgement of usage and power state, and there is no supported way to
assert that a wake was scheduled or that it fired. The claim proved here is the different, weaker,
checkable one: **correctness does not require a background wake.** Foreground launch, resume, and
reconnect each restore correct state on their own.

### Criterion 4 — accessibility

**VoiceOver speech output and real screen-reader gesture navigation are not captured.** What is
captured is accessibility semantics (labels, traits, values, identifiers), the accessibility
audit's own findings, and rendered layout across Dynamic Type sizes. The device confirmation run
executes the Plan 04-13 suites once on hardware; it confirms rather than replaces the simulator
`accessibility` lane.

### Criterion 5 — sustained daily use

**Not automatable, and not a gate.** The closest automatable proxy is delivered instead: the
supported loop is installed on the physical device under a **non-expiring** profile, and every
action in it passes this lane bound to the shipped build. **Sustained daily adoption is owner
dogfood feedback, not a gate.** Nobody signs off on it and nothing counts it.

## Currently BLOCKED, with the reason measured rather than asserted

The **server-driven half of Criterion 2** — authentication expiry, account fencing, duplicate
replay, and structured conflict, injected *server-side* through the recording proxy and asserted
against what the proxy recorded the server receiving — **does not run.** It is reported `BLOCKED`
by `tooling/ios-lanes/device.mjs` and by `tooling/verify-real-stack-ios.mjs`, never passed and
never silently omitted.

Why, measured by `tooling/verify-real-stack-ios.mjs` on each run:

- `KeeplingSyncAdapter`'s constructor refuses any non-HTTPS base URL whose host is not `127.0.0.1`
  or `localhost` (T-04-01-03/T-04-05-04, mirroring `apps/desktop/main/adapters/sync.ts`). On the
  Mac that costs nothing — the desktop app and Phoenix share a loopback. **A physical phone does
  not**, and can only reach the build Mac at a LAN address.
- Over `http://<lan-ip>:<port>` the app constructs no adapter at all, so **nothing leaves the
  phone** — the lane records zero arrivals at the proxy.
- Over `https://<lan-ip>:<port>` the phone **genuinely connects** — the lane's TLS listener records
  the connection attempt — and URLSession then rejects the lane's self-signed certificate. That
  distinction is the point: **routing from the phone to this Mac works; the blocker is certificate
  trust, not networking.**

Closing it requires a decision Plan 04-16 did not make:

1. a `#if DEBUG`, launch-environment-gated lane CA trusted through an injected `ClientTransport`
   (keeps HTTPS, keeps production behaviour unchanged, adds a test-only transport seam);
2. widening the production transport guard to admit LAN or `.local` hosts;
3. deferring the server-driven device scenarios to a later plan.

**Option 2 is refused here.** Relaxing a deliberate security guard — one with its own tests — so
that a lane goes green is precisely the false-evidence failure this phase exists to prevent.

## What the machines cover

| Layer | Owner |
|---|---|
| Every simulator lane (core loop, storage, sync, accessibility, tokens, undo, auth, transport…) | `node tooling/verify-ios-phase.mjs` |
| Requirement-to-lane map | `node tooling/verify-ios-phase.mjs --requirements` |
| Signed device build, provenance manifest, install | `node tooling/build-ios-signed.mjs` |
| Read-back attestation, refusal on mismatch | `node tooling/ios-device/attestation.mjs --expect-installed` |
| Two-identifier resolution, passcode/lock-state probe | `node tooling/ios-device/resolve-devices.mjs` |
| Out-of-process SIGKILL | `node tooling/ios-device/hard-kill.mjs --require-running` |
| Physical-device suites + device accessibility confirmation | `node tooling/verify-ios-phase.mjs --lane device` |
| Real Phoenix on real PostgreSQL behind the recording proxy | `node tooling/verify-real-stack-ios.mjs` |

## Gate G7 (D-04), split honestly

| Half | Status |
|---|---|
| The store file's protection class reads back as `.completeUntilFirstUserAuthentication`, and never `.complete`, **on real hardware where iOS actually enforces Data Protection** | **Proven** — `StorageTests/DataProtectionTests.testStoreProtectionClassOnPhysicalDeviceIsEnforceable`, run through the `device` lane |
| The attached phone genuinely has a passcode, so the class above is enforceable rather than nominal | **Proven** — `devicectl device info lockState` reports `passcodeRequired: true`, recorded by `resolve-devices.mjs` |
| A write performed **while the device is locked** completes without an I/O failure or `0xdead10cc` | **BLOCKED** — see below |

The locked-write half is blocked for a specific, checkable reason: **nothing available can lock the
phone under program control.** `devicectl` exposes `info lockState` (a *read*) plus install, launch,
terminate, signal, reboot and orientation — there is no `lock` verb. `XCUIDevice`'s lock control
lives in the UI-testing framework, which the `StorageTests` unit-test bundle does not link. Driving
it from the UI-test target instead would require a new app-side
`protectedDataWillBecomeUnavailable` write hook — new production surface added solely to make a
gate pass, which is not a trade this project makes. The skip is recorded in
`DataProtectionTests.testBackgroundWriteWhileLockedDoesNotTakeAnIOErrorOrTerminate` with that
reason, never as a bare `XCTSkip`.
