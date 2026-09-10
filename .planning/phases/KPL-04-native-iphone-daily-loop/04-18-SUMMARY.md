---
phase: KPL-04-native-iphone-daily-loop
plan: 18
subsystem: testing
tags: [ios, device, tailscale, transport, openapi-contract, anti-vacuity, attestation]

requires:
  - phase: KPL-04-16
    provides: "the signed-build/install/attestation/hard-kill device tooling this plan's device lane chains behind, and the device lane whose BLOCKED status this plan retires"
  - phase: KPL-04-17
    provides: "the assembled gate (tooling/verify-ios-phase.mjs), its lane-glob runner, its BLOCKED convention, and the requirement-to-lane map this plan extends and repairs"
provides:
  - "tooling/ios-device/real-stack.mjs: one definition of 'a real backend behind a recording proxy' -- real Phoenix on real PostgreSQL, a fault-injection control channel, and a real RFC 8252 PKCE device grant -- shared by the simulator lane, the device lane, and verify-real-stack-ios.mjs"
  - "server-driven-sim and server-driven-device lanes: the four server-driven scenarios of D-22 Criterion 2 driven through the REAL Swift client, on the simulator and on a physical iPhone"
  - "A credential seam on KeeplingSyncAdapter (CredentialProvider + a bearer ClientMiddleware) -- the adapter could not authenticate against a real server at all before this plan"
  - "RFC3339DateTranscoder: the adapter could not decode the server's own timestamps before this plan"
  - "Three OpenAPI contract fixes where packages/contracts/openapi/keepling.yaml disagreed with what the server actually sends"
  - "D-21 configuration attestation: the configuration a lane TESTED is now attested, not merely the one it archived"
  - "tooling/ios-device/lock-probe.mjs: a locked phone is named as its own BLOCKED reason in seconds, not surfaced as a destination timeout minutes later"
  - "IOS-04 checked -- the last unchecked requirement this phase owns"
affects: [KPL-05, KPL-06]

actuals:
  tokens: 690000
  tasks: 7
  commits: 9

tech-stack:
  added:
    - "tailscale (developer-machine tooling only; nothing in any shipping target depends on it)"
  patterns:
    - "Reach for a host the client ALREADY trusts before reaching for a test-only trust seam. `tailscale cert` issues a genuine Let's Encrypt certificate for a MagicDNS name, so the phone validates the lane's proxy through the SHIPPING transport -- default URLSessionTransport, production HTTPS guard, production ATS. The planned `#if DEBUG` lane CA was sound and would have worked; it was superseded because zero test-only trust code is strictly safer than correctly-gated test-only trust code, and because a VPN interface is excluded from Apple TN3179's definition of a local network, which removes a privilege grant that can be given by a person only and resets on every reinstall."
    - "A stub, a fake transport, or a fixture written to match a schema cannot discover that the schema disagrees with the server. Twenty-one green lanes hid six stacked defects because every one of them used one. The first time the real client met the real server, all six surfaced at once."
    - "Never spawnSync in a process that also hosts the HTTP server under test -- it blocks the event loop entirely, so every request times out and both the 'arrived' and 'refused' counters read zero, which looks exactly like a passing measurement of nothing."
    - "Attest the configuration, not just the digest. A source-content digest cannot distinguish Debug from Release, so a configuration substitution is invisible to it; BuildAttestation.configuration is compiled in from a `#if` and read back out of the running process."

key-files:
  created:
    - tooling/ios-device/real-stack.mjs
    - tooling/ios-device/tailnet.mjs
    - tooling/ios-device/lock-probe.mjs
    - tooling/ios-device/server-driven-run.mjs
    - tooling/ios-lanes/server-driven-sim.mjs
    - tooling/ios-lanes/server-driven-device.mjs
    - apps/ios/Tests/KeeplingCoreTests/ServerDrivenTests.swift
    - apps/ios/Tests/KeeplingCoreTests/TransportGuardTests.swift
    - apps/ios/Sources/KeeplingCore/Transport/RFC3339DateTranscoder.swift
  modified:
    - apps/ios/Sources/KeeplingCore/Transport/KeeplingSyncAdapter.swift
    - apps/ios/Sources/Keepling/App/BuildAttestation.swift
    - packages/contracts/openapi/keepling.yaml
    - tooling/ios-lanes/device.mjs
    - tooling/verify-ios-phase.mjs
    - tooling/verify-real-stack-ios.mjs
    - docs/testing/ios-testing.md
    - docs/testing/ios-dogfood.md
    - .planning/REQUIREMENTS.md
    - package.json

key-decisions:
  - "The production transport guard was NOT widened, as the plan prohibited. `http://<non-loopback>` still throws .insecureBaseURL, proven by TransportGuardTests including a case that the new credential-provider initializer does not relax it. A scan confirms no serverTrust handling, URLSessionDelegate, NSAllowsArbitraryLoads, or pinning code exists anywhere under apps/ios/Sources."
  - "The stated blocker (a self-signed certificate) was the OUTERMOST of six stacked defects, not the whole gap. In order: transport reachability; the Swift client had never met a real server on ANY destination; the adapter could not authenticate at all; it could not decode the server's timestamps; it could not classify a 401 on the pull leg where 401s actually arrive; and it could not decode a sync page because of three separate contract/server mismatches. Each was invisible until the one above it was fixed."
  - "The device suites are compiled Debug and this is DISCLOSED and ATTESTED rather than worked around: a Release build strips the XCTest framework the physical-device suites host in. `attestation.mjs --expect-configuration` enforces it, and did refuse a run during this plan when the phone still held a Debug build from a prior test pass."
  - "IOS-04's four proving cases were added to the device lane at METHOD granularity, not by adding the whole SyncStateMatrixTests suite. The rest of that suite (zero/one/many shapes, draft and editor preservation) has no device dimension this requirement names, and the state-matrix lane still runs it whole on the simulator."
  - "Plan 04-16's device measurement was retroactively found UNSOUND: both its arrival counters read zero by construction because spawnSync blocked the event loop the proxy ran on. The conclusion it drew ('routing works, trust is the blocker') happened to be correct, but not because that run measured it."

patterns-established:
  - "A lane may refuse to report PASS on the strength of HOW it ran, not only whether its assertions held: server-driven-device parses the run's own transport marker and reports BLOCKED unless it reads `transport=https-publicly-trusted`, so a silent fallback to a weaker transport can never be published as success (D-24)."

requirements-completed: [IOS-04]

coverage:
  - id: D1
    description: "The four server-driven scenarios of D-22 Criterion 2 -- authentication expiry, account fencing, duplicate replay, structured conflict -- run through the real KeeplingSyncAdapter against real Phoenix on real PostgreSQL, asserted against what the recording proxy received"
    requirement: IOS-02
    verification:
      - kind: e2e
        ref: "node tooling/verify-ios-phase.mjs --lane server-driven-sim -- IOS_SERVER_DRIVEN scenarios=4 command_arrivals=6 injected=1 refusals=2; order capture-task:201 -> capture-task:201 -> capture-task:201 -> edit-task:200 -> edit-task:409 -> capture-task:401"
        status: pass
    human_judgment: false
  - id: D2
    description: "Those same four scenarios run on the physical iPhone over a transport the shipping build uses unmodified -- production URLSessionTransport, production ATS, production HTTPS guard, publicly-trusted certificate"
    requirement: IOS-04
    verification:
      - kind: e2e
        ref: "node tooling/verify-ios-phase.mjs --lane server-driven-device -- IOS_SERVER_DRIVEN scenarios=4 destination=\"platform=iOS,id=<device>\" transport=https-publicly-trusted command_arrivals=6 injected=1 refusals=2, same recorded order"
        status: pass
    human_judgment: false
  - id: D3
    description: "The production transport guard is not widened: http://<non-loopback> still throws .insecureBaseURL, and no certificate-trust override exists in any shipping target"
    verification:
      - kind: unit
        ref: "TransportGuardTests -- 6 cases including testCredentialProviderDoesNotRelaxTheGuardForANonLoopbackHTTPHost"
        status: pass
      - kind: other
        ref: "grep for serverTrust|URLSessionDelegate|didReceive challenge|NSAllowsArbitraryLoads|allowsInsecure across apps/ios/Sources and project.yml -- zero matches"
        status: pass
    human_judgment: false
  - id: D4
    description: "A scenario that cannot genuinely run reports BLOCKED with its own reason; the suite FAILS rather than XCTSkips when the lane supplies no base URL, and the device lane refuses PASS unless the run actually used the publicly-trusted transport"
    verification:
      - kind: other
        ref: "ServerDrivenTests' lane environment XCTFails rather than XCTSkips; server-driven-device.mjs parse() throws BLOCKED unless transport=https-publicly-trusted appears in the run marker"
        status: pass
    human_judgment: false
  - id: D5
    description: "The build configuration a device lane TESTED is attested, not merely the one it archived"
    requirement: IOS-04
    verification:
      - kind: e2e
        ref: "Enforced live and observed refusing: 'ATTESTATION REFUSED: the build running on iPhone 16 Pro Max was compiled as Debug but Release was expected' -- a real refusal during this plan, not a synthetic one"
        status: pass
    human_judgment: false
  - id: D6
    description: "A locked phone is named as a distinct BLOCKED reason within seconds rather than surfacing as a destination timeout minutes later"
    verification:
      - kind: e2e
        ref: "tooling/ios-device/lock-probe.mjs chained first in the device lane -- LOCK_PROBE device=<name> locked=false printed within seconds of lane start"
        status: pass
    human_judgment: false
  - id: D7
    description: "IOS-04 is checked, with both halves proven on physical hardware: the states ARRIVE and are classified correctly (server-driven-device), and the user can TELL THEM APART by exact copy and named recovery action (four SyncStateMatrixTests cases in the device lane)"
    requirement: IOS-04
    verification:
      - kind: e2e
        ref: "node tooling/verify-ios-phase.mjs --lane device -- LANE name=device status=PASS cases=26 duration_ms=1133259, bound to build digest 8bf8ad871096390c8dbbb62ea16cef0b"
        status: pass
    human_judgment: true
    rationale: "Whether adapter-level classification on hardware plus copy-level discrimination on hardware together discharge 'the user can distinguish' is a judgment call. The state->copy mapping is pure Swift with no device-specific behaviour, but 04-16 found a device-only contrast defect the simulator never reproduced, so the split is stated rather than assumed."

duration: ~9h
completed: 2026-09-08
status: complete
---

# Phase KPL-04 Plan 18: Closing the Device Blocker Without Weakening Anything

**The `device` lane reports PASS for the first time in this phase — 26 cases on a physical iPhone — and IOS-04 is checked, because the phone now reaches a Mac-hosted recording proxy over a host it already trusts rather than through any test-only trust code. Getting there meant finding that the stated blocker was the outermost of six stacked defects, every one of them hidden by twenty-one green lanes that had never let the real Swift client meet a real server.**

## What the blocker actually was

Plan 04-16 recorded the blocker as "the lane's certificate is self-signed." True, and not the whole gap. Fixing it revealed the next layer, six times over:

1. **Transport** — the phone could not reach the proxy at all.
2. **Authentication** — `KeeplingSyncAdapter` had no way to send a credential. It had never needed one, because no test had ever put it in front of a server that asked.
3. **Timestamps** — the adapter could not decode the server's own RFC 3339 output. `ISO8601DateFormatter` rejects fractional seconds without `.withFractionalSeconds` and is unreliable past three digits; RFC 3339 permits any number.
4. **Refusal classification** — a 401 on the pull leg (where 401s actually arrive) was thrown as `SyncPortRefused` and never classified as `.authenticationRequired`.
5. **Sync page decoding** — three separate places where `packages/contracts/openapi/keepling.yaml` disagreed with what the server sends: a snapshot schema requiring `project_id`/`tag_ids` when the server sends `project`/`tags`, a missing `Problem` variant in `MutationResult`, and an acknowledgement union carrying an undo capability handle the server does not include.
6. **Assertion bugs of my own** — JSON string comparison across key orders, the wrong outbox invariant, a session-only route dialled with a bearer token, and `UUID().uuidString` case.

Every one was invisible to the existing gate because every existing lane used a stub, a fake transport, or a fixture written to match the schema rather than the server.

## Why tailnet rather than the planned DEBUG lane CA

The plan's chosen route — a `#if DEBUG`, launch-environment-gated lane CA behind an injected `ClientTransport` — is sound and would have worked. It was superseded because a strictly better one exists:

`tailscale cert` issues a real Let's Encrypt certificate for the build Mac's MagicDNS name. The phone validates the proxy with the **shipping** trust path: default `URLSessionTransport`, production `KeeplingSyncAdapter` constructor, production HTTPS guard, production ATS. There is no test-only trust code on any configuration, so there is none to leak into a release and none to keep correctly gated forever.

It also removes a human touchpoint the plan had not accounted for. Apple TN3179 makes an outgoing TCP connection to a LAN address require the local-network privilege — enforced deep in the networking stack for every API, grantable by a person only (never by MDM, profile, or `devicectl`), and reset whenever the app is deleted. A tailnet address rides a VPN interface, which TN3179 excludes from the definition of a local network, so the privilege never applies. That matters directly to this project's zero-human-UAT constraint.

## What was found wrong in prior work

- **04-16's device measurement was unsound.** `spawnSync` blocked the event loop the proxy ran on, so every request timed out and both the "arrived" and "refused" counters read zero *by construction*. The conclusion it drew was right; the run did not measure it. Proven in isolation: `SYNCHRONOUS_READING hits=0` / `AFTER_EVENT_LOOP_RUNS hits=1`. The same flaw existed in `verify-real-stack-ios.mjs` and was fixed there too.
- **The gate under-reported every multi-suite lane's case count** — `xcodebuildSummary` took the first "Executed N tests" line rather than the last.
- **The attested build was not the tested build.** The scheme's `ArchiveAction` is Release and its `TestAction` is Debug; a source-content digest cannot tell them apart. Now attested from a compiled-in `#if` and enforced.
- **`--requirements` had failed for the whole phase** with "requirement D-22 has no mapped lane." D-22 is a *decision* id appearing in the traceability row's prose, and the parser harvested every `LETTERS-DIGITS` token from the entire row — the gate's own wording could break the gate. It now reads the id column. All five requirements map.
- **The two server-driven lanes could not run in the same gate.** `server-driven-sim` failed reproducibly inside the full gate while passing standalone, with an error naming nothing about the cause: *"Failed to install or launch the test runner ... Launchd job spawn failed"*. Both destinations shared one derived-data tree, so `Build/Products` accumulated an `.xctestrun` per platform and the runner took the first by name -- `iphoneos` sorts before `iphonesimulator`, so once the device lane had run, the simulator lane launched the **device-built** app on the simulator. Fixed per-platform, and the selection now refuses an ambiguous match rather than picking one. This defect was reachable only by running every lane together; neither lane could ever have found it alone.
- **A device failure could not be read after the fact.** A `DynamicTypeSnapshotTests` hit-region case failed once in a full gate (and passed on every other device run, before and after). Diagnosing it was impossible: the lane printed only a tail, which showed the *last* suite's log, and the `.xcresult` had already been overwritten by the next run. The device lane now writes the whole log to `.artifacts/ios/device-last-run.log` and names the failing tests inline.

## Evidence

| Lane | Result |
|---|---|
| `server-driven-sim` | PASS — scenarios=4, command_arrivals=6, injected=1, refusals=2 |
| `server-driven-device` | PASS — same four, `transport=https-publicly-trusted`, on the physical iPhone |
| `device` | PASS, cases=26 (was BLOCKED for the entire phase) |
| `--requirements` | 5 requirements, all mapped (was FAILED) |
| full gate | **24 lanes, 496 executed cases, 0 failed, 0 blocked -- PASSED** (463 simulator, 29 `device`, 4 `server-driven-device`), after two separate defects in how cases were counted were found and fixed |

Recorded command order, identical on both destinations, read from what the proxy received rather than from client belief:

```
capture-task:201 -> capture-task:201 -> capture-task:201 -> edit-task:200 -> edit-task:409 -> capture-task:401
```

## Disclosed residuals

- **The device suites compile Debug.** A Release build strips the XCTest framework the physical-device suites host in. Stated and attested rather than silent; proving the Release binary on hardware remains open.
- **The locked-write half of G7 stays BLOCKED.** Nothing available can lock the phone under program control — `devicectl` has no `lock` verb, and `XCUIDevice`'s lock control lives in the UI-testing framework the `StorageTests` bundle does not link. Closing it would mean adding a production `protectedDataWillBecomeUnavailable` write hook solely to make a gate pass.
- **Real jetsam, real `BGTaskScheduler` wakes, VoiceOver speech and real gesture navigation** remain outside what any lane will assert, for the reasons already tabulated in `docs/testing/ios-testing.md`.

## User Setup Required

None going forward. Tailscale is installed on both machines and HTTPS certificates are enabled for the tailnet; the lane issues and reuses certificates on its own. The tailnet hostname is treated as PII and redacted from every printed line.

## Next Phase Readiness

Phase 5's cross-adapter proof now has a real precedent to follow: `tooling/ios-device/real-stack.mjs` is a destination-agnostic definition of "the real backend behind a recording proxy," and the same server-driven scenarios can be pointed at the desktop adapter without rebuilding the harness.

## Self-Check: PASSED
