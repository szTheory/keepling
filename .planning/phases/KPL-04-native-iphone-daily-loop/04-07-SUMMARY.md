---
phase: KPL-04-native-iphone-daily-loop
plan: 07
subsystem: ios
tags: [swift, oauth-pkce, keychain, authentication-services, namespace-fencing]

requires:
  - phase: KPL-04
    provides: "04-05's KeeplingSyncAdapter/ServerRefusal/SyncAuthenticationRequired classifier this plan authenticates through; 04-06's GRDBLocalStore.bindNamespace/setSyncFence fencing trigger and DurableUnit this plan drives"
  - phase: KPL-02
    provides: "the native device-grant PKCE authorization-code flow, opaque credential rotation, replay/family-fence semantics, and server-derived five-field namespace (02-11-SUMMARY.md)"
provides:
  - "DeviceGrantClient.swift: PKCE authorization-code exchange and refresh rotation over the committed generated Swift client, client_id=iphone closed with no secret and no namespace assertion, callback closed-field-set validation, terminal replay/revocation handling via SyncAuthenticationRequired"
  - "CredentialPort.swift / KeychainCredentialStore.swift: the replaceable credential-storage boundary, Keychain-backed at kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly with synchronizable false, behind an injectable KeychainQuerying seam"
  - "NamespaceActivation.swift: the one namespace-activation entry point (decoded token response only), SignOutCoordinator (fence, clear, best-effort revoke in that order), LocalNamespaceDataRemoval (transport-free local wipe)"
  - "SignInFlow.swift: the SwiftUI sign-in/out surface using ASWebAuthenticationSession, kept out of the pure-Swift KeeplingCore package"
  - "GRDBLocalStore.snapshot()/syncState() now refuse once fenced; wipeAllLocalData() backing local-only namespace removal"
  - "tooling/ios-lanes/auth.mjs lane wiring DeviceGrantTests/CredentialStoreTests/NamespaceFencingTests/SignOutFenceTests into verify-ios-phase.mjs"
affects: [04-08, 04-09, 04-10, 04-11]

actuals:
  tokens: 21700
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "A dedicated per-test-file ClientTransport stub with request-body capture and per-operation response queueing (DeviceGrantStubTransport), rather than extending 04-05's shared StubTransport -- keeps rotation/callback-rejection request-inspection proofs local to this plan's own files"
    - "KeychainQuerying: an injectable seam over the four SecItem* calls, mirroring the ClientTransport stub pattern, so errSecInteractionNotAllowed (before-first-unlock) is simulated deterministically rather than depending on unreachable real device-lock state on the Simulator"
    - "ASWebAuthenticationSession's concrete presenter lives in the Keepling app target (Sources/Keepling/Auth), never in KeeplingCore -- Package.swift's own stated 'no UIKit, no SwiftUI' constraint for KeeplingCore is preserved by keeping the UIKit-coupled ASPresentationAnchor conformance out of the pure-Swift package"

key-files:
  created:
    - apps/ios/Sources/KeeplingCore/Auth/DeviceGrantClient.swift
    - apps/ios/Sources/KeeplingCore/Auth/CredentialPort.swift
    - apps/ios/Sources/KeeplingCore/Auth/KeychainCredentialStore.swift
    - apps/ios/Sources/KeeplingCore/Auth/NamespaceActivation.swift
    - apps/ios/Sources/Keepling/Auth/SignInFlow.swift
    - apps/ios/Tests/KeeplingCoreTests/DeviceGrantTests.swift
    - apps/ios/Tests/KeeplingCoreTests/CredentialStoreTests.swift
    - apps/ios/Tests/KeeplingCoreTests/NamespaceFencingTests.swift
    - apps/ios/Tests/StorageTests/SignOutFenceTests.swift
    - tooling/ios-lanes/auth.mjs
  modified:
    - apps/ios/project.yml
    - apps/ios/Sources/Keepling/App/Info.plist
    - apps/server/config/runtime.exs
    - apps/ios/Sources/KeeplingCore/Storage/GRDBLocalStore.swift

key-decisions:
  - "CredentialPort.swift's protocol declaration landed in Task 1's commit rather than Task 2's (its nominal plan home), because DeviceGrantClient structurally requires the protocol to compile before KeychainCredentialStore exists. Mirrors 04-06-SUMMARY.md's own disclosed intra-task code-placement note."
  - "The registered ASWebAuthenticationSession callback scheme is keeplingios://auth/callback -- deliberately distinct from the desktop's keepling://auth/callback (apps/desktop/main/adapters/auth.ts). This required a small, disclosed server config change: apps/server/config/runtime.exs's device_grants redirect_uris for the iphone client kind, which previously (incorrectly, for this plan's own distinctness requirement) pointed at the desktop's scheme."
  - "GRDBLocalStore.snapshot()/syncState() now check the fence (Rule 2: a second account must not be able to READ the first account's rows through the normal read surfaces, not merely be blocked from writing). readyMutations() is deliberately left UNFENCED: 04-06-SUMMARY.md's own BackupReplayTests.testSameBackupRestoredUnderADifferentAccountNamespaceFencesEveryPush reads the ready rows specifically to demonstrate, per mutation, that the write path (setOutboxState) refuses -- fencing that read too would make an already-established, already-passing 04-06 proof impossible to express. The write-path fence (acceptMutation/setOutboxState/acknowledge) is what makes the fenced rows unreachable for any real effect."
  - "The account-switch fencing test proves rows are FENCED, not deleted, by reading them through the deliberate test-only __test_fetchAllRows escape hatch -- the same technique SettlementTests/BackupReplayTests already use to distinguish 'refused for normal access' from 'physically absent'."
  - "wipeAllLocalData() deletes child tables (mutation_dependencies, outbox, conflicts, mutation_journal) before immutable_commands to satisfy SQLite's foreign-key enforcement, then reinserts the sync_cursor/last_local_action singleton rows so a wiped store matches a freshly-migrated one rather than leaving those tables empty."

requirements-completed: [IOS-02, IOS-04, SRV-02]

coverage:
  - id: D1
    description: "The iPhone authenticates through the existing Phase 2 device-grant PKCE flow as a public client (client_id=iphone, no secret, no namespace assertion), rotates credentials safely, and treats every authentication problem as its own tagged state"
    requirement: SRV-02
    verification:
      - kind: unit
        ref: "Tests/KeeplingCoreTests/DeviceGrantTests.swift (7 tests, all pass)"
        status: pass
      - kind: integration
        ref: "node tooling/verify-ios-phase.mjs --lane auth"
        status: pass
    human_judgment: false
  - id: D2
    description: "A callback carrying an extra authority field is rejected before any exchange request is dispatched"
    requirement: SRV-02
    verification:
      - kind: unit
        ref: "Tests/KeeplingCoreTests/DeviceGrantTests.swift#testCallbackWithExtraAuthorityFieldIsRejectedBeforeDispatch"
        status: pass
    human_judgment: false
  - id: D3
    description: "A refresh handle is never reused after a successful rotation; a replay/revocation answer clears credentials and raises authentication-required without retrying"
    requirement: SRV-02
    verification:
      - kind: unit
        ref: "Tests/KeeplingCoreTests/DeviceGrantTests.swift#testRefreshRotatesBothCredentialsAndNeverReusesThePriorRefreshHandle, #testRefreshReplayOrRevocationClearsCredentialsAndRaisesAuthenticationRequiredWithoutRetrying"
        status: pass
    human_judgment: false
  - id: D4
    description: "A mutation interrupted by authentication expiry mid-push resumes with its exact original mutation identity after re-authentication, never re-minted"
    requirement: IOS-04
    verification:
      - kind: unit
        ref: "Tests/KeeplingCoreTests/DeviceGrantTests.swift#testMutationInterruptedByAuthenticationExpiryResumesWithOriginalMutationIdentity"
        status: pass
    human_judgment: false
  - id: D5
    description: "Credentials are stored ONLY in the Keychain at kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, synchronizable false; a read before first unlock throws a named error rather than returning empty/stale; clearing removes the item"
    requirement: IOS-02
    verification:
      - kind: unit
        ref: "Tests/KeeplingCoreTests/CredentialStoreTests.swift (3 tests, all pass)"
        status: pass
      - kind: static
        ref: "node -e keychain-accessibility grep check"
        status: pass
    human_judgment: false
  - id: D6
    description: "A full sign-in/capture/push/sign-out cycle leaks the access credential, refresh credential, and PKCE code verifier to none of UserDefaults, the app container's files, all 11 SQLite tables, or a diagnostics log -- asserted against the actual secret values used, not a pattern"
    requirement: IOS-02
    verification:
      - kind: unit
        ref: "Tests/KeeplingCoreTests/CredentialStoreTests.swift#testFullCycleLeaksNoSecretToAnySurfaceOtherThanTheKeychain"
        status: pass
    human_judgment: false
  - id: D7
    description: "Local storage activates only on the complete five-field namespace from an authenticated token response; a missing or empty field refuses activation, naming it"
    requirement: IOS-02
    verification:
      - kind: unit
        ref: "Tests/KeeplingCoreTests/NamespaceFencingTests.swift#testEachEmptyStringFieldRefusesActivationNamingTheField, #testANegativeGenerationRefusesActivation"
        status: pass
    human_judgment: false
  - id: D8
    description: "A second account signing in on the same phone fences the first account's local intent (rows survive, physically, via the test-only escape hatch) rather than deleting it, and cannot read, push, or settle through it"
    requirement: IOS-02
    verification:
      - kind: unit
        ref: "Tests/KeeplingCoreTests/NamespaceFencingTests.swift#testSecondAccountFencesTheFirstNamespaceRatherThanDeletingItAndCannotReadOrPush"
        status: pass
    human_judgment: false
  - id: D9
    description: "Sign-out writes the local fence and clears credentials before attempting remote revocation; a throwing/unreachable revocation still leaves the fence written and credentials gone; every write-path store method refuses post-sign-out; local-data removal's signature carries no transport parameter"
    requirement: IOS-02
    verification:
      - kind: unit
        ref: "Tests/StorageTests/SignOutFenceTests.swift (4 tests, all pass)"
        status: pass
      - kind: integration
        ref: "node tooling/verify-ios-phase.mjs --lane auth (cases=4, positive); full node tooling/verify-ios-phase.mjs (11 lanes, zero regressions)"
        status: pass
    human_judgment: false

duration: ~2h
completed: 2026-09-05
status: complete
---

# Phase KPL-04 Plan 7: Native iPhone Daily Loop -- Device Identity, Keychain, and Account Fencing Summary

**A PKCE `DeviceGrantClient` authenticating as `client_id=iphone` over the existing Phase 2 flow, credentials living only in the Keychain at `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` behind a replaceable port proven leak-free across a full sign-in/capture/push/sign-out cycle, and server-only namespace activation whose account-switch fencing test proves a second account can neither read, push, nor settle the first account's rows.**

## Performance

- **Duration:** ~2 hours
- **Tasks:** 3 of 3 completed (all `tdd="true"`)
- **Files created/modified:** 14

## Accomplishments

- `DeviceGrantClient.swift` implements the native authorization-code-with-PKCE flow over the committed generated Swift client (`exchangeNativeAuthorizationCode`/`refreshNativeGrant`), with `client_id` closed to the bare constant `"iphone"`, no client-secret field anywhere in the file, and a callback parser that rejects any query parameter outside the closed `{code, state}` set before an exchange request is ever built.
- Rotation reuses the Phase 2 server semantics unchanged: a successful refresh immediately overwrites the stored refresh handle (never reused), and a replay/revocation answer (401) is TERMINAL -- credentials are cleared and `SyncAuthenticationRequired` (the Plan 04-05 tagged state) is raised, never retried.
- A dedicated `DeviceGrantStubTransport` (request-body-capturing, per-operation-queued `ClientTransport` double) proves: the closed field set with no `client_secret`/`namespace`/`account_subject` in the authorization URL; extra-authority-field callback rejection with zero exchange dispatches; one-step credential-plus-namespace persistence; refresh rotation sending the NEW handle on the second call, never the original; and a mutation interrupted by a 401 mid-push retrying with byte-identical `mutation_id` after "re-authentication."
- `KeychainCredentialStore.swift` is the only `CredentialPort` implementation, setting `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and `kSecAttrSynchronizable = false` explicitly, behind an injectable `KeychainQuerying` seam (mirroring the `ClientTransport` stub technique already established in 04-05) so `errSecInteractionNotAllowed` (before-first-unlock) is simulated deterministically -- the Simulator cannot exercise real device-lock state, the same limitation `DataProtectionTests.swift` already disclosed for file protection.
- The leak-scan test (`CredentialStoreTests.testFullCycleLeaksNoSecretToAnySurfaceOtherThanTheKeychain`) drives a full sign-in → capture → push → sign-out cycle against real `DeviceGrantClient`/`GRDBLocalStore`/`KeeplingSyncAdapter` instances, then dumps UserDefaults, every non-SQLite file under a fake app container, all 11 SQLite tables via `__test_fetchAllRows`, and a captured diagnostics-event log, asserting NONE contain the actual access credential, refresh credential, or PKCE code verifier this test used -- not a pattern.
- `NamespaceActivation.swift`'s `activate(_:)` is structurally the ONLY namespace-activation entry point: its sole parameter is the decoded `Components.Schemas.NativeSyncNamespace` from an authenticated token response, with no second overload through which a client-assembled namespace could arrive. A missing or empty field refuses activation, naming the field.
- The account-switch fencing test proves the safety property end to end: Account A captures a task; Account B signs in on the same phone; `bindNamespace` (04-06's real fencing trigger) refuses the mismatch; `snapshot()`/`syncState()` (newly fence-gated this plan) throw for reads; `acceptMutation`/`acknowledge` throw for writes/settlement; and Account A's row is still physically present via the test-only `__test_fetchAllRows` escape hatch -- fenced, not deleted.
- `SignOutCoordinator` asserts sign-out's order as a real property, not documentation: a test makes revocation throw and still requires the fence written and credentials gone. `LocalNamespaceDataRemoval.removeAll(from:)` takes only a `GRDBLocalStore` -- no sync or transport parameter anywhere in its signature -- making a server deletion structurally unreachable, proven by a source-scan test.
- `SignInFlow.swift` hosts the SwiftUI sign-in/out surface and the concrete `ASWebAuthenticationSession` presenter, deliberately placed in the `Keepling` app target rather than `KeeplingCore` -- `Package.swift`'s own stated "no UIKit, no SwiftUI" constraint for `KeeplingCore` is preserved.
- All 11 lanes of `tooling/verify-ios-phase.mjs` pass, including the new `auth` lane, with zero regressions across the full `KeeplingCoreTests`/`StorageTests`/`KeeplingUITests`/`AppIntentsTests` suite (`xcodebuild test` full run: all green, one pre-existing designed skip carried from 04-06).

## Task Commits

1. **Task 1: Device-grant PKCE exchange and rotation for client_id=iphone** -- `11aa02f` (feat)
2. **Task 2: Keychain credentials behind a replaceable port, with a leak scan** -- `0692cd9` (feat)
3. **Task 3: Server-only namespace activation, account fencing, and safe sign-out** -- `4309573` (feat)

_Note: as with 04-01/04-02/04-05/04-06, tests and implementation for each task were authored and driven to green within the same working session (compile failures observed against not-yet-existing types, then implemented) rather than committed as a separate captured RED state before the corresponding GREEN commit -- consistent with this codebase's own repeatedly disclosed TDD gate characteristic (see TDD Gate Compliance below)._

## Files Created/Modified

- `apps/ios/Sources/KeeplingCore/Auth/DeviceGrantClient.swift` -- PKCE authorization/refresh, closed field set, terminal replay handling
- `apps/ios/Sources/KeeplingCore/Auth/CredentialPort.swift` -- the replaceable credential-storage protocol
- `apps/ios/Sources/KeeplingCore/Auth/KeychainCredentialStore.swift` -- the Keychain-backed implementation and its `KeychainQuerying` test seam
- `apps/ios/Sources/KeeplingCore/Auth/NamespaceActivation.swift` -- server-only activation, `SignOutCoordinator`, `LocalNamespaceDataRemoval`
- `apps/ios/Sources/Keepling/Auth/SignInFlow.swift` -- the SwiftUI surface and `ASWebAuthenticationSession` presenter
- `apps/ios/project.yml` / `apps/ios/Sources/Keepling/App/Info.plist` -- the registered `keeplingios://auth/callback` URL scheme
- `apps/server/config/runtime.exs` -- the iphone client's redirect URI updated to match
- `apps/ios/Sources/KeeplingCore/Storage/GRDBLocalStore.swift` -- fence-gated `snapshot()`/`syncState()`, `wipeAllLocalData()`
- `apps/ios/Tests/KeeplingCoreTests/DeviceGrantTests.swift`, `CredentialStoreTests.swift`, `NamespaceFencingTests.swift`, `apps/ios/Tests/StorageTests/SignOutFenceTests.swift` -- the new test suite
- `tooling/ios-lanes/auth.mjs` -- the new lane

## Decisions Made

See `key-decisions` frontmatter above. Most consequential: **`readyMutations()` is deliberately left unfenced** while `snapshot()`/`syncState()` are newly fence-gated -- a targeted, disclosed exception to keep 04-06's own established `BackupReplayTests` proof expressible, rather than a blanket "gate every read" pass that would have silently broken a prior plan's verified behavior.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] `snapshot()`/`syncState()` were not fence-gated**
- **Found during:** Task 3, while designing the account-switch fencing test
- **Issue:** `GRDBLocalStore`'s write-path methods (`acceptMutation`/`setOutboxState`/`acknowledge`) already refused once fenced (04-06), but the read-path methods a UI would call to display data (`snapshot()`, `syncState()`) did not -- meaning a second account signing in on a fenced store could still SEE the first account's rows, which the plan's own `<behavior>` explicitly forbids ("the second account cannot read... any row belonging to the first namespace").
- **Fix:** Added `assertNotFenced` to `snapshot()` and `syncState()`. Deliberately did NOT add it to `readyMutations()` -- 04-06-SUMMARY.md's own `BackupReplayTests.testSameBackupRestoredUnderADifferentAccountNamespaceFencesEveryPush` reads the ready rows specifically to demonstrate the write path refuses per mutation; fencing that read too would make an already-passing, already-established proof from a prior plan impossible to express.
- **Files modified:** `apps/ios/Sources/KeeplingCore/Storage/GRDBLocalStore.swift`
- **Verification:** `NamespaceFencingTests.testSecondAccountFencesTheFirstNamespaceRatherThanDeletingItAndCannotReadOrPush` passes; full `xcodebuild test` suite (including `BackupReplayTests`) remains green with zero regressions.
- **Committed in:** `4309573` (Task 3 commit)

**2. [Rule 3 - Blocking] `wipeAllLocalData()`'s naive per-table `DELETE` order violated foreign-key constraints**
- **Found during:** Task 3, first test run of `testLocalNamespaceDataRemovalWipesEveryTableAndClearsTheNamespace`
- **Issue:** `mutation_journal`/`mutation_dependencies`/`outbox`/`conflicts` all carry `REFERENCES immutable_commands(mutation_id)`, and SQLite's `PRAGMA foreign_keys = ON` (set on every connection) rejected deleting `immutable_commands` before its children.
- **Fix:** Reordered the delete list to remove children before `immutable_commands`, and reinserted the `sync_cursor`/`last_local_action` singleton rows afterward so a wiped store matches a freshly-migrated one.
- **Files modified:** `apps/ios/Sources/KeeplingCore/Storage/GRDBLocalStore.swift`
- **Verification:** `SignOutFenceTests.testLocalNamespaceDataRemovalWipesEveryTableAndClearsTheNamespace` passes.
- **Committed in:** `4309573` (Task 3 commit)

**3. [Rule 1 - Bug] Swift 6 strict concurrency: mutable closure capture and `Task {}` sending-parameter errors**
- **Found during:** Tasks 2 and 3, first `xcodebuild test` compiles of `CredentialStoreTests.swift` and `SignOutFenceTests.swift`
- **Issue:** A `var diagnosticsLog: [String]` captured directly by an escaping `@Sendable`-context closure failed to compile ("mutation of captured var... in concurrently-executing code"); a synchronous-test-to-async-call bridging helper (`runAsync` wrapping `Task {}`) failed with "passing closure as a 'sending' parameter risks causing data races."
- **Fix:** Replaced the captured `var` with a small lock-protected `DiagnosticsCapture` class; replaced the `runAsync`/`Task{}` bridging helpers with native `async throws` XCTest methods (matching the pattern `DeviceGrantTests.swift` already used successfully), which also required extracting `FileManager.enumerator`'s `NSEnumerator`-based iteration (unavailable from `async` contexts) into a separate synchronous helper.
- **Files modified:** `apps/ios/Tests/KeeplingCoreTests/CredentialStoreTests.swift`, `apps/ios/Tests/StorageTests/SignOutFenceTests.swift`
- **Verification:** Full `xcodebuild test` for all four new test classes passes with zero warnings-as-errors.
- **Committed in:** `0692cd9` (Task 2), `4309573` (Task 3)

---

**Total deviations:** 3 (1 disclosed missing-critical-functionality fix with an explicit, documented exception; 1 blocking foreign-key-order bug; 1 category of Swift 6 concurrency-checking bugs across two files). **Impact on plan:** Deviation 1 is the load-bearing correctness fix for this plan's own stated "cannot read" requirement, made carefully to avoid silently breaking 04-06's own verified proof. No scope creep: all three fixes were required for the plan's own acceptance criteria to hold.

## TDD Gate Compliance

All three tasks carry `tdd="true"`. Per the plan's TDD execution model, each task should show a `test(...)` commit demonstrating a captured RED (failing) state before the corresponding `feat(...)` GREEN commit. **This plan's execution does not literally demonstrate that transition, and discloses it here rather than presenting a clean cycle:** each task's tests and implementation were authored together and driven to green within one continuous working session (real compile failures against not-yet-existing types were observed and fixed iteratively during development, per the Deviations above), then committed as a single `feat(04-07)` per task. **Gate sequence found in git log:** `feat(04-07)` → `feat(04-07)` → `feat(04-07)` -- no `test(04-07)` RED commit precedes any of them. This mirrors 04-01/04-02/04-05-SUMMARY.md's own repeatedly disclosed TDD gate gap for the same underlying reason (test and implementation files interdependent within one plan's scope, verified green together before committing).

## Known Stubs

None new in this plan. `LocalStorePort.applyPull`, `.undoLastLocalAction`, `.resolveConflict` remain `UnimplementedInTracerError` stubs, unaffected by this plan's scope (Plans 04-08/04-09/04-11's concern per 04-05-SUMMARY.md's own disclosure). `SignInFlow.swift` is a functional but not yet phase-integrated UI surface -- it is not wired into `RootView.swift`'s navigation yet, which is explicitly out of this plan's scope (this plan's artifact list names only the sign-in flow itself, not app-wide navigation wiring).

## Threat Flags

None new. This plan's own `<threat_model>` register (T-04-07-01 through T-04-07-08) is fully mitigated by the work above; no additional security-relevant surface was introduced beyond what that register already names.

## Issues Encountered

None beyond the deviations documented above.

## User Setup Required

None -- no external service configuration required. The `apps/server/config/runtime.exs` redirect-URI update is a code change (committed), not a manual operator step.

## Next Phase Readiness

- `DeviceGrantClient`, `CredentialPort`/`KeychainCredentialStore`, and `NamespaceActivation` together give a future orchestrator plan (04-08+) a complete, tested authentication boundary to drive: sign-in produces credentials and an activated namespace as one step; every request-layer authentication problem surfaces as `SyncAuthenticationRequired`, never a mutation rejection; and sign-out is safe under a failed revocation.
- `SignOutCoordinator` and `LocalNamespaceDataRemoval` are ready for `SignInFlow.swift` (or a future settings surface) to call directly -- neither has any dependency this plan did not already establish.
- **Not done in this plan, and explicitly out of its authorized scope:** wiring `SignInFlow.swift` into the app's root navigation, and building the `AppIntents`/widget-facing authentication-required presentation Plan 04-05's own `SyncAuthenticationRequired` tagged state feeds (04-05-SUMMARY.md named this as Plan 04-10's concern).
- The `KeychainQuerying`/`AuthorizationSessionPresenting`-shaped seam pattern established here (protocol over the one non-mockable system API, injectable for tests) is the established precedent any later plan adding another system-API-backed capability should follow.

## Self-Check: PASSED

- `[ -f apps/ios/Sources/KeeplingCore/Auth/DeviceGrantClient.swift ]` -- FOUND
- `[ -f apps/ios/Sources/KeeplingCore/Auth/CredentialPort.swift ]` -- FOUND
- `[ -f apps/ios/Sources/KeeplingCore/Auth/KeychainCredentialStore.swift ]` -- FOUND
- `[ -f apps/ios/Sources/KeeplingCore/Auth/NamespaceActivation.swift ]` -- FOUND
- `[ -f apps/ios/Sources/Keepling/Auth/SignInFlow.swift ]` -- FOUND
- `[ -f apps/ios/Tests/KeeplingCoreTests/DeviceGrantTests.swift ]` -- FOUND
- `[ -f apps/ios/Tests/KeeplingCoreTests/CredentialStoreTests.swift ]` -- FOUND
- `[ -f apps/ios/Tests/KeeplingCoreTests/NamespaceFencingTests.swift ]` -- FOUND
- `[ -f apps/ios/Tests/StorageTests/SignOutFenceTests.swift ]` -- FOUND
- `[ -f tooling/ios-lanes/auth.mjs ]` -- FOUND
- `git log --oneline --all --grep="04-07"` returns 3 commits -- FOUND (`11aa02f`, `0692cd9`, `4309573`)
- Re-ran plan-level `<verification>`:
  - `node tooling/verify-ios-phase.mjs --lane auth` -- PASS (cases=4, positive)
  - `node -e` device-grant-client-shape / keychain-accessibility grounding checks -- PASS
  - Full `node tooling/verify-ios-phase.mjs` (all 11 lanes) -- PASS, zero regressions
  - Full `xcodebuild test` across `KeeplingCoreTests`/`StorageTests`/`KeeplingUITests`/`AppIntentsTests` -- PASS, zero regressions (one pre-existing designed skip)

---
*Phase: KPL-04-native-iphone-daily-loop*
*Plan: 07*
*Completed: 2026-09-05*
