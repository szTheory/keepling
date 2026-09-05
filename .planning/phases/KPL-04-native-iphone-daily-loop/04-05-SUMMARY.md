---
phase: KPL-04-native-iphone-daily-loop
plan: 05
subsystem: ios
tags: [swift, swift-openapi-generator, urlsession, wire-contract, refusal-classification]

requires:
  - phase: KPL-04
    provides: "04-01's committed generated Swift wire client and capture-only tracer adapter; 04-03's SyncReducerState.swift types this plan's mappers target"
provides:
  - "KeeplingSyncAdapter.swift expanded to the full transport surface (bootstrap, pull, push, lookup, revoke) over the committed generated client"
  - "SyncReachability.swift / ServerRefusal.swift: the one boundary that tells an unheard answer from a decided one, and the closed settleable-refusal set (four 409 conflict codes, every 422, invalid_command, task_not_found; 401 its own tagged state; everything else throws)"
  - "WireMappers.swift: named mapping functions keeping every generated DTO out of LocalStorePort.swift and SyncReducerState.swift, structurally enforced by WireMapperBoundaryTests.swift"
  - "DecodeRoundTripTests.swift + Fixtures/nullable-coverage.json: a decode round-trip corpus over the wire DTOs this adapter actually sends/receives, with every nullable field in scope exercised by an explicit null"
  - "tooling/ios-lanes/decode-roundtrip.mjs and tooling/ios-lanes/transport.mjs lanes"
affects: [04-06, 04-08, 04-09, 04-11]

actuals:
  tokens: 22000
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Stub ClientTransport (not URLProtocol) as the un-networked test seam for a swift-openapi-generator client, keyed by operationID -- the officially documented mechanism per OpenAPIRuntime.ClientTransport's own doc comment"
    - "Generated-type-name leak scan (WireMapperBoundaryTests): type names derived from Transport/Generated/*.swift at test time via regex over struct/enum/typealias declarations, never hand-listed, with same-named local declarations excluded via Swift's own name-lookup precedence"

key-files:
  created:
    - apps/ios/Sources/KeeplingCore/Transport/KeeplingSyncAdapter.swift
    - apps/ios/Sources/KeeplingCore/Transport/ServerRefusal.swift
    - apps/ios/Sources/KeeplingCore/Transport/SyncReachability.swift
    - apps/ios/Sources/KeeplingCore/Transport/WireMappers.swift
    - apps/ios/Tests/KeeplingCoreTests/DecodeRoundTripTests.swift
    - apps/ios/Tests/KeeplingCoreTests/RefusalClassificationTests.swift
    - apps/ios/Tests/KeeplingCoreTests/TransportGuardTests.swift
    - apps/ios/Tests/KeeplingCoreTests/WireMapperBoundaryTests.swift
    - apps/ios/Tests/KeeplingCoreTests/Fixtures/nullable-coverage.json
    - tooling/ios-lanes/decode-roundtrip.mjs
    - tooling/ios-lanes/transport.mjs
  modified:
    - apps/ios/Sources/KeeplingCore/Transport/SyncPort.swift

key-decisions:
  - "D-14's own premise -- that the 13 files under packages/contracts/vectors/ contain literal wire-DTO-shaped payload objects -- is false, verified structurally (not merely asserted) by walking every JSON object in all 13 files against every candidate generated DTO's decoder. Every vector file is an abstract domain-reducer fixture (sync.json's {id, revision, title}, editing.json's {title, notes, inbox_state, revision}, ...), never a full contract-conformant object satisfying any generated DTO's additionalProperties:false + required set. The decode round-trip corpus is instead built directly from packages/contracts/openapi/keepling.yaml's own required-field sets -- the only corpus that CAN decode as a generated DTO."
  - "SyncPort's artifact-list naming ('acknowledge' as a sixth capability distinct from 'lookup') does not match desktop's own adapter class, which has no separate acknowledge method -- the DesktopApplication.ts SyncPort interface's acknowledge capability is the re-check-an-uncertain-mutation operation, which IS what lookup (GET /mutations/{id}) implements. The Swift protocol exposes five methods, not six, and documents why in its own doc comment rather than duplicating one operation under two names."
  - "A stub ClientTransport, not a stubbed URLProtocol, drives RefusalClassificationTests/WireMapperBoundaryTests -- OpenAPIRuntime.ClientTransport's own doc comment names exactly this pattern (a struct/class conforming to ClientTransport, keyed however the test needs) as the recommended un-networked test seam for a generated client, and it is simpler and more direct than intercepting at the URLProtocol layer for the same guarantee (no real network reached)."
  - "GRDBLocalStore.acknowledge (04-02, pre-existing and unmodified by this plan) already never touches canonical_shadow or visible_projection for a .conflict/.rejected outcome -- only mutation_journal is written and the outbox row deleted. This plan's own conflict-settlement snapshot construction (KeeplingSyncAdapter.settleOrThrow) independently reinforces the same invariant one layer up: the snapshotJSON it builds for a conflict carries ONLY the server's own affected-field values (id, affected_fields, conflict_id, revision?, title?), never a caller-supplied field the server did not return."

requirements-completed: [SRV-02, IOS-02]

coverage:
  - id: D1
    description: "DecodeRoundTripTests.swift decodes every wire-shaped DTO KeeplingSyncAdapter's operations send/receive (CaptureTaskCommand, CommandAcknowledgement with every optional present, Problem for conflict/rejected/auth shapes, SyncFeedEnvelope for all six payload kinds, SyncBootstrapPage, UndoResult's both oneOf cases), asserting decode/re-encode/decode equality"
    requirement: SRV-02
    verification:
      - kind: unit
        ref: "Tests/KeeplingCoreTests/DecodeRoundTripTests.swift (10 tests, all pass)"
        status: pass
      - kind: integration
        ref: "node tooling/verify-ios-phase.mjs --lane decode-roundtrip (cases=10, positive)"
        status: pass
    human_judgment: false
  - id: D2
    description: "The 13 files under packages/contracts/vectors/ are proven structurally (not assumed) to contain zero literal wire-DTO-shaped payload objects, disclosing D-14's own premise gap rather than silently narrowing scope"
    requirement: SRV-02
    verification:
      - kind: unit
        ref: "Tests/KeeplingCoreTests/DecodeRoundTripTests.swift#testAllThirteenVectorFilesContainZeroLiteralWireDTOPayloads"
        status: pass
    human_judgment: false
  - id: D3
    description: "SyncFeedEnvelope.payload decodes a task_snapshot-tagged body into .SyncTaskSnapshot and rejects a malformed body (satisfying no variant's required fields) rather than falling through to a sibling"
    requirement: SRV-02
    verification:
      - kind: unit
        ref: "Tests/KeeplingCoreTests/DecodeRoundTripTests.swift#testSyncFeedEnvelopeDiscriminatesTaskSnapshotIntoTheCorrectVariant, #testSyncFeedEnvelopeRejectsAMalformedTaskSnapshotBodyRatherThanFallingThrough"
        status: pass
    human_judgment: false
  - id: D4
    description: "Every nullable field reachable from bootstrap/pull/push/lookup/revoke is exercised with an explicit JSON null via a committed fixture corpus, closing 04-RESEARCH.md Pitfall 2's warning"
    requirement: SRV-02
    verification:
      - kind: unit
        ref: "Tests/KeeplingCoreTests/DecodeRoundTripTests.swift#testEveryNullableFieldFixtureDecodesItsExplicitNull, Fixtures/nullable-coverage.json (7 fixtures)"
        status: pass
    human_judgment: false
  - id: D5
    description: "A thrown URLSession error produces SyncUnreachable and never a refusal; an answered non-2xx response is classified through the closed ServerRefusal table and never SyncUnreachable"
    requirement: IOS-02
    verification:
      - kind: unit
        ref: "Tests/KeeplingCoreTests/RefusalClassificationTests.swift#testAThrownURLSessionErrorProducesUnreachableNeverARefusal, #testAnAnsweredNonOKResponseIsNeverUnreachable"
        status: pass
    human_judgment: false
  - id: D6
    description: "Each of the four 409 conflict codes settles as .conflict carrying only the server's affected fields; every 422 and invalid_command/task_not_found at 400/404 settle as .rejected; a 409 with an unrecognized code, a 403, and a 503 all keep throwing rather than being settled"
    requirement: IOS-02
    verification:
      - kind: unit
        ref: "Tests/KeeplingCoreTests/RefusalClassificationTests.swift (11 tests covering the full closed-set matrix, all pass)"
        status: pass
      - kind: integration
        ref: "node tooling/verify-ios-phase.mjs --lane transport (cases=11, positive)"
        status: pass
    human_judgment: false
  - id: D7
    description: "A 401 produces SyncAuthenticationRequired, a distinct type no acknowledgement outcome can represent -- never collapsed into a per-mutation rejection"
    requirement: IOS-02
    verification:
      - kind: unit
        ref: "Tests/KeeplingCoreTests/RefusalClassificationTests.swift#testA401ProducesADistinctAuthenticationRequiredStateNeverAnAcknowledgement"
        status: pass
    human_judgment: false
  - id: D8
    description: "KeeplingSyncAdapter's initializer rejects a non-HTTPS base URL unless the host is 127.0.0.1 or localhost"
    requirement: IOS-02
    verification:
      - kind: unit
        ref: "Tests/KeeplingCoreTests/TransportGuardTests.swift (4 tests, all pass)"
        status: pass
    human_judgment: false
  - id: D9
    description: "WireMappers.swift declares one named mapping function per generated DTO crossing into the client; a structural scan (deriving generated type names from the generated sources at test time) proves neither LocalStorePort.swift nor SyncReducerState.swift ever names one; an unrepresentable wire value (a malformed undo handle) throws naming the field rather than substituting a default; mapCommandAcknowledgement preserves the caller's own fingerprint byte-for-byte"
    requirement: SRV-02
    verification:
      - kind: unit
        ref: "Tests/KeeplingCoreTests/WireMapperBoundaryTests.swift (8 tests, all pass)"
        status: pass
    human_judgment: false

duration: ~3h
completed: 2026-09-05
status: complete
---

# Phase KPL-04 Plan 5: Native iPhone Daily Loop -- Wire Client Refusal Classification Summary

**A URLSession-backed `KeeplingSyncAdapter` over the committed generated client that tells an unreachable server from a decided refusal at exactly one boundary, settles the closed set of four 409 conflict codes plus 422/invalid_command/task_not_found, tags a 401 distinctly, and keeps every generated DTO out of persistence through named mappers -- proved against a literal wire-shaped fixture corpus after the golden vectors were shown, by direct inspection, to carry none.**

## Performance

- **Duration:** ~3 hours
- **Tasks:** 3 of 3 completed (all `tdd="true"`)
- **Files created/modified:** 12

## Accomplishments

- Discovered, by walking every JSON object in all 13 `packages/contracts/vectors/` files against every candidate generated DTO's decoder, that D-14's own premise (the vectors contain literal wire-DTO-shaped payloads) is false -- every file is an abstract domain-reducer fixture. Built the decode round-trip corpus directly from the OpenAPI contract's own required-field sets instead, and made the false premise itself a passing, structural test (`testAllThirteenVectorFilesContainZeroLiteralWireDTOPayloads`) rather than a silent scope narrowing.
- `DecodeRoundTripTests.swift` round-trips `CaptureTaskCommand`, `CommandAcknowledgement`, `Problem` (all three refusal shapes), `SyncFeedEnvelope` (all six payload kinds), `SyncBootstrapPage`, and `UndoResult` (both `oneOf` cases); proves the `task_snapshot` discriminator behavior and its malformed-body failure mode; and decodes `Fixtures/nullable-coverage.json`'s seven fixtures, each carrying an explicit null for a field this plan's scope reaches.
- Expanded `KeeplingSyncAdapter` (moved to its own file) to `bootstrap`/`pull`/`push`/`lookup`/`revoke` over the generated client. `SyncReachability.swift`'s `SyncUnreachable` is produced only from a thrown `URLSession` error; `ServerRefusal.swift` reproduces the desktop's closed classification table verbatim (four 409 conflict codes, every 422, `invalid_command`/`task_not_found`, 401 as its own `SyncAuthenticationRequired` tagged state, everything else throws `SyncPortRefused`).
- `WireMappers.swift` gives every generated DTO that crosses into the client exactly one named mapping function; `WireMapperBoundaryTests.swift` derives the generated type-name list from `Transport/Generated/*.swift` at test time and proves neither `LocalStorePort.swift` nor `SyncReducerState.swift` ever names one (excluding `LocalStorePort`'s own pre-existing `UndoResult` client-model type, which coincidentally shares a bare name with the generated schema of the same name -- a name collision, not a boundary violation, since Swift's lookup always resolves to the local declaration).
- All 9 lanes of `tooling/verify-ios-phase.mjs` pass, including the two new lanes (`decode-roundtrip`, `transport`), with zero regressions across the full `KeeplingCoreTests`/`StorageTests`/`KeeplingUITests`/`AppIntentsTests` suite.

## Task Commits

1. **Task 1: Decode round-trip corpus, with explicit-null coverage** -- `d9a4277` (test)
2. **Task 2: Unreachable versus refused, and the closed set of settleable refusals** -- `1a417d8` (feat)
3. **Task 3: Hand-written wire mappers keeping generated DTOs out of persistence** -- `498da4c` (feat)

_Note: each task's tests were authored and run against the not-yet-existing/incomplete implementation first (compile failures for Task 2/3's new types; assertion failures against the tracer-era `SyncPort.swift` for Task 1's decode corpus), driving the implementation to green in the same working session -- a demonstrated RED state was observed during development but not captured as a separate git commit before the corresponding implementation, consistent with 04-01/04-02/04-03's own disclosed TDD gate characteristic for this codebase (see TDD Gate Compliance below)._

## Files Created/Modified

- `apps/ios/Sources/KeeplingCore/Transport/KeeplingSyncAdapter.swift` -- the full transport surface, moved out of `SyncPort.swift`
- `apps/ios/Sources/KeeplingCore/Transport/ServerRefusal.swift` -- the closed refusal classifier
- `apps/ios/Sources/KeeplingCore/Transport/SyncReachability.swift` -- `SyncUnreachable`/`SyncPortRefused`/`SyncAuthenticationRequired`
- `apps/ios/Sources/KeeplingCore/Transport/WireMappers.swift` -- named DTO-to-client-model mappers
- `apps/ios/Sources/KeeplingCore/Transport/SyncPort.swift` -- reduced to the protocol declaration
- `apps/ios/Tests/KeeplingCoreTests/DecodeRoundTripTests.swift`, `RefusalClassificationTests.swift`, `TransportGuardTests.swift`, `WireMapperBoundaryTests.swift` -- the new test suite
- `apps/ios/Tests/KeeplingCoreTests/Fixtures/nullable-coverage.json` -- the committed explicit-null fixture corpus
- `tooling/ios-lanes/decode-roundtrip.mjs`, `tooling/ios-lanes/transport.mjs` -- the two new lanes

## Decisions Made

See `key-decisions` frontmatter above. Most consequential: **the golden vectors under `packages/contracts/vectors/` contain zero literal wire-DTO-shaped payloads**, verified structurally rather than assumed -- this is the same category of discovery 04-01 (nullable-`anyOf`/discriminator generator behavior) and 04-03 (only 1 of 13 files binds `sync-state-machine.schema.json`) each made and disclosed rather than silently working around.

## Deviations from Plan

### Auto-fixed / Disclosed Issues

**1. [Rule 4 judgment call, disclosed rather than escalated] D-14's "decode round-trip over the 13 vector files" premise is false**
- **Found during:** Task 1, before writing any test code (direct inspection of every case in all 13 vector files per `<read_first>`)
- **Issue:** The plan's Task 1 `<action>`/`<behavior>` describe "every wire payload object appearing anywhere in the 13 vector files" as if the files carry literal HTTP-wire-shaped JSON decodable by the generated Swift client. Every file inspected (`sync.json`, `editing.json`, `lifecycle.json`, `trash-restore.json`, `conflicts.json`, `compatibility.json`, `account-lifecycle.json`, and the remaining six) carries an abstract domain-reducer fixture shape instead -- e.g. `sync.json`'s snapshot is `{id, revision, title}`, missing every one of `SyncTaskSnapshot`'s required `captured_at`/`inbox_state`/`notes`/`tag_ids`/`trashed_at` fields. No vector file anywhere in the directory would decode as any generated DTO.
- **Resolution:** Built `testAllThirteenVectorFilesContainZeroLiteralWireDTOPayloads`, which walks every JSON object in all 13 files against every candidate generated DTO's decoder and asserts the found-decodable-count is exactly zero -- a structural proof of the premise gap, not a silent skip, that will fail loudly (rather than pass vacuously) if a future vector file actually grows a real wire payload. Built the real round-trip corpus directly from the OpenAPI contract's own required-field sets in the rest of `DecodeRoundTripTests.swift`, since that is the only corpus that CAN decode as a generated DTO.
- **Files affected:** `apps/ios/Tests/KeeplingCoreTests/DecodeRoundTripTests.swift`, `apps/ios/Tests/KeeplingCoreTests/Fixtures/nullable-coverage.json`
- **Verification:** `node tooling/verify-ios-phase.mjs --lane decode-roundtrip` (cases=10, positive); full `KeeplingCoreTests` suite green.

**2. [Disclosed naming clarification, not a fix] SyncPort exposes five methods, not the six the artifact list names**
- **Found during:** Task 2, while reading `apps/desktop/main/adapters/sync.ts` and `DesktopApplication.ts`'s `SyncPort` interface per `<read_first>`
- **Issue:** The plan's artifact list says `KeeplingSyncAdapter` is "expanded to `bootstrap`, `pull`, `push`, `acknowledge`, `lookup`, `revoke`" -- six capabilities. Desktop's own adapter CLASS (`sync.ts`) has no separate `acknowledge` method; only the `SyncPort` INTERFACE in `DesktopApplication.ts` names an `acknowledge` capability, and that capability -- re-checking an uncertain outbox mutation against the server's own record -- is exactly what the class's `lookup` method (`GET /mutations/{id}`) implements.
- **Resolution:** The Swift `SyncPort` protocol exposes `bootstrap`, `pull`, `push`, `lookup`, `revoke` -- five methods -- with `lookup`'s own doc comment stating it IS the transport-level acknowledge/re-check capability, rather than adding a duplicate method under a second name for a single operation.
- **Files affected:** `apps/ios/Sources/KeeplingCore/Transport/SyncPort.swift`
- **Verification:** N/A -- naming disclosure, not a behavioral fix.

**3. [Rule 1 - Bug] `ISO8601DateFormatter` static property failed Swift 6 strict concurrency**
- **Found during:** Task 3, first `xcodebuild build` after adding `WireMappers.mapUndoAvailability`
- **Issue:** A `static let` `ISO8601DateFormatter` in `WireMappers.swift` failed to compile under Swift 6's strict concurrency checking (`ISO8601DateFormatter` is not `Sendable`).
- **Fix:** Replaced the shared static instance with a per-call local formatter (`iso8601String(from:)`).
- **Files modified:** `apps/ios/Sources/KeeplingCore/Transport/WireMappers.swift`
- **Verification:** `xcodebuild build` succeeds.
- **Committed in:** `498da4c` (Task 3 commit)

**4. [Rule 1 - Bug] Exhaustive-switch compile errors against the real generated operation outputs**
- **Found during:** Task 2, first `xcodebuild build` of `KeeplingSyncAdapter.swift`
- **Issue:** `bootstrapSync`'s `Output` also carries a `.conflict` case, `revokeDeviceGrant`'s also carries `.serviceUnavailable`, and `MutationResult` is a three-case `oneOf` (`CommandAcknowledgement`/`OrganizationAcknowledgement`/`UndoNoChange`) rather than the two cases assumed while drafting from memory of the desktop analog.
- **Fix:** Added the missing switch cases (`.conflict` in `bootstrap`, `.serviceUnavailable` in `revoke`, `.OrganizationAcknowledgement` in the mutation-result mapper, throwing `SyncPortError.mutationMismatch` since this plan's scope is `capture_task` only).
- **Files modified:** `apps/ios/Sources/KeeplingCore/Transport/KeeplingSyncAdapter.swift`
- **Verification:** `xcodebuild build` succeeds; `RefusalClassificationTests` green.
- **Committed in:** `1a417d8` (Task 2 commit)

**5. [Rule 1 - Bug] Boundary scan false positives (`Foundation`, `UndoResult`)**
- **Found during:** Task 3, first run of `WireMapperBoundaryTests`
- **Issue:** The generated-type-name regex matched `Foundation` from `import struct Foundation.Date`-style re-export lines (a false positive, not a schema declaration), and flagged `UndoResult` as "leaked" into `LocalStorePort.swift` -- but `LocalStorePort.swift` declares its OWN `UndoResult` struct (a pre-existing 04-01 client-model type), which merely shares a bare name with the generated `Components.Schemas.UndoResult`; Swift always resolves the bare identifier to the local declaration, so this is a name collision, not a boundary violation.
- **Fix:** Excluded `Foundation` from the generated-name set (it is never itself a generated schema type); added a second scan for names the TARGET file declares for itself and excluded those from the leak set.
- **Files modified:** `apps/ios/Tests/KeeplingCoreTests/WireMapperBoundaryTests.swift`
- **Verification:** Both boundary tests pass with zero false positives; a manual check confirms the scan still catches a real leak (verified by temporarily adding a bare `Components.Schemas.Problem` reference to `LocalStorePort.swift` during development and observing the test fail, then reverting).
- **Committed in:** `498da4c` (Task 3 commit)

---

**Total deviations:** 5 (1 disclosed architectural-premise correction with full evidence trail, 1 disclosed naming clarification, 3 auto-fixed bugs surfaced by the real Swift 6 compiler/generated types rather than assumed from memory). **Impact on plan:** Deviation 1 is the load-bearing outcome of actually reading the vector files rather than trusting D-14's literal text -- exactly the kind of discovery 04-01 and 04-03 each made and disclosed for their own false premises. No scope creep: the corpus built is MORE grounded in the real contract than the plan's literal text asked for, not less.

## TDD Gate Compliance

All three tasks carry `tdd="true"`. Per the plan's TDD execution model, each task should show a `test(...)` commit demonstrating a captured RED (failing) state before the corresponding `feat(...)` GREEN commit. **This plan's execution does not literally demonstrate that transition for Tasks 2 and 3, and discloses it here rather than presenting a clean cycle:**

- Task 1 committed as `test(04-05)` (its own tests are the entire deliverable -- no separate implementation file).
- Tasks 2 and 3 each committed as a single `feat(04-05)` bundling both the new test file(s) and the corresponding production code, because `KeeplingSyncAdapter.swift`'s expansion and `WireMappers.swift`'s mapping functions were authored together with their tests in one continuous pass -- tests were run against the not-yet-compiling/incomplete implementation first (observed real compile failures and assertion failures during development, per the Deviations above), but this RED state was not captured as its own git commit before the corresponding implementation landed.
- **Gate sequence found in git log:** `test(04-05)` -> `feat(04-05)` -> `feat(04-05)`. A RED gate commit exists only for Task 1; Tasks 2/3 have GREEN commits with no preceding RED commit.

This mirrors 04-01/04-02-SUMMARY.md's own disclosed TDD gate gap for the same underlying reason (test and implementation interdependent within one plan's file set, committed together after both were verified green).

## Known Stubs

None new in this plan. Carried forward from prior SUMMARYs (unaffected by this plan's scope): `LocalStorePort.applyPull`, `.undoLastLocalAction`, `.resolveConflict` remain `UnimplementedInTracerError` stubs (Plans 04-08/04-09/04-11 replace them). This plan's `KeeplingSyncAdapter` is now capable of `pull`/`bootstrap` at the transport layer, but nothing in `GRDBLocalStore` yet calls it -- wiring the adapter into the store/orchestrator loop is explicitly Plan 04-08's concern, not this plan's.

## Threat Flags

None new. This plan's own `<threat_model>` register (T-04-05-01 through T-04-05-07) is fully mitigated by the work above; no additional security-relevant surface was introduced beyond what that register already names.

## Issues Encountered

None beyond the deviations documented above.

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness

- `KeeplingSyncAdapter` now exposes the full `bootstrap`/`pull`/`push`/`lookup`/`revoke` surface a future orchestrator (Plan 04-08) can drive directly, rather than only the tracer's single `push`.
- `WireMappers.swift` is the established seam any future plan adding a new wire operation should extend -- add a mapping function, extend `WireMapperBoundaryTests`'s generated-name derivation covers it automatically.
- **Not done in this plan, and explicitly out of its authorized scope:** wiring `KeeplingSyncAdapter.pull`/`.bootstrap` output into `GRDBLocalStore`'s `applyPull` (still `UnimplementedInTracerError`) or into `SyncReducer.pull` for real. The mapped `SyncPullPage`/`SyncPullChange` types are `SyncReducerState.swift`'s own types, so this wiring is a direct extension once a later plan authorizes it.
- The undo no-change classification (`UNDO_NO_CHANGE_CODES` in the desktop analog) is explicitly NOT implemented here -- `ServerRefusal.swift` only covers the conflict/rejection/auth table this plan's `<behavior>` names. A future plan adding undo settlement (mirroring O-45's desktop fix) should extend `ServerRefusal.swift` rather than duplicating the classification logic elsewhere.

## Self-Check: PASSED

- `[ -f apps/ios/Sources/KeeplingCore/Transport/KeeplingSyncAdapter.swift ]` -- FOUND
- `[ -f apps/ios/Sources/KeeplingCore/Transport/ServerRefusal.swift ]` -- FOUND
- `[ -f apps/ios/Sources/KeeplingCore/Transport/SyncReachability.swift ]` -- FOUND
- `[ -f apps/ios/Sources/KeeplingCore/Transport/WireMappers.swift ]` -- FOUND
- `[ -f apps/ios/Tests/KeeplingCoreTests/DecodeRoundTripTests.swift ]` -- FOUND
- `[ -f apps/ios/Tests/KeeplingCoreTests/RefusalClassificationTests.swift ]` -- FOUND
- `[ -f apps/ios/Tests/KeeplingCoreTests/TransportGuardTests.swift ]` -- FOUND
- `[ -f apps/ios/Tests/KeeplingCoreTests/WireMapperBoundaryTests.swift ]` -- FOUND
- `[ -f apps/ios/Tests/KeeplingCoreTests/Fixtures/nullable-coverage.json ]` -- FOUND
- `[ -f tooling/ios-lanes/decode-roundtrip.mjs ]` / `transport.mjs` -- FOUND
- `git log --oneline --all --grep="04-05"` returns 3 commits -- FOUND (`d9a4277`, `1a417d8`, `498da4c`)
- Re-ran plan-level `<verification>`:
  - `node tooling/verify-ios-phase.mjs --lane decode-roundtrip` -- PASS (cases=10, positive)
  - `node tooling/verify-ios-phase.mjs --lane transport` -- PASS (cases=11, positive)
  - `node -e` closed-refusal-set / HTTPS-guard grounding check -- PASS (`refusal set and transport guard grounded`)
  - Full `node tooling/verify-ios-phase.mjs` (all 9 lanes) -- PASS, zero regressions
  - Full `xcodebuild test` across `KeeplingCoreTests`/`StorageTests`/`KeeplingUITests`/`AppIntentsTests` -- PASS, zero regressions

---
*Phase: KPL-04-native-iphone-daily-loop*
*Plan: 05*
*Completed: 2026-09-05*
