---
phase: KPL-02-synchronization-and-replaceable-server
plan: 04
subsystem: compatibility
tags: [elixir, phoenix, openapi, protocol-trains, migration-matrix, rollback]

requires:
  - phase: KPL-02-synchronization-and-replaceable-server
    plan: 02
    provides: retained authenticated cursor codec, ordered feed, bootstrap, and current schema migrations
  - phase: KPL-02-synchronization-and-replaceable-server
    plan: 03
    provides: server-authoritative installation namespace and current/previous client lifecycle assumptions
  - phase: KPL-02-synchronization-and-replaceable-server
    plan: 11
    provides: generated native transport contract and public/bearer router boundaries
provides:
  - Highest-intersection integer protocol-train negotiation with stable non-retrying upgrade outcomes
  - Anonymous unversioned compatibility metadata with exact release, OCI digest, protocol, schema, platform, deadline, and recovery fields
  - Executable current/previous receipt, cursor, generated-fixture, migration, image/schema, and rollback skew matrix
affects: [sync-transport, desktop-release, ios-release, deployment-preflight, rollback, contract-ci]

actuals:
  tokens: 16610
  tasks: 3
  commits: 6

tech-stack:
  added: []
  patterns: [pure protocol policy, closed public metadata, startup compatibility validation, exact artifact eligibility, anti-vacuous skew matrix]

key-files:
  created:
    - apps/server/lib/keepling/application/compatibility.ex
    - apps/server/lib/keepling_web/controllers/compatibility_controller.ex
    - apps/server/test/keepling/application/compatibility_test.exs
    - apps/server/test/keepling_web/compatibility_controller_test.exs
    - packages/contracts/vectors/compatibility.json
    - tooling/test-compatibility.sh
  modified:
    - apps/server/config/config.exs
    - apps/server/config/runtime.exs
    - apps/server/lib/keepling/application.ex
    - apps/server/lib/keepling_web/router.ex
    - packages/contracts/openapi/keepling.yaml
    - packages/contracts/generated/keepling.ts
    - tooling/check-contracts.mjs

key-decisions:
  - "The active protocol floor comes only from server distribution state, the inclusive deprecation deadline, or a documented evidence-bearing security emergency; marketing/build versions remain metadata-only."
  - "The unversioned compatibility route accepts exactly one client min/max train range and publishes a closed release-only response without session, account, grant, cursor, or credential state."
  - "Rollback eligibility requires an exact immutable OCI digest plus both schema and protocol inclusion; a schema or protocol miss is stable and non-retrying."

patterns-established:
  - "Compatibility authority: clients supply range claims, while the server selects the highest safe read/write/sync intersection and owns recovery direction."
  - "Published support validation: production startup refuses missing digest/update metadata, malformed ranges, or a distributed previous-train window shorter than 90 days without documented emergency evidence."
  - "Skew evidence: every bounded lane records exact digest, schema, train, expected result, and positive case count before disposable migrations execute."

requirements-completed: [SRV-06]

coverage:
  - id: D1
    description: "The server deterministically selects the highest intersecting train and returns stable non-retrying client/server upgrade recovery on non-overlap."
    requirement: SRV-06
    verification:
      - kind: unit
        ref: "apps/server/test/keepling/application/compatibility_test.exs#frozen protocol train and exhaustive range-pair tests"
        status: pass
    human_judgment: false
  - id: D2
    description: "Anonymous clients receive a closed authoritative compatibility response with every D-27 field and no private account or credential state."
    requirement: SRV-06
    verification:
      - kind: integration
        ref: "apps/server/test/keepling_web/compatibility_controller_test.exs#anonymous metadata, malformed claims, mismatch recovery, and startup validation"
        status: pass
      - kind: other
        ref: "pnpm contracts:check#OpenAPI generated drift and compatibility vector validation"
        status: pass
    human_judgment: false
  - id: D3
    description: "Current/previous codecs, receipts, cursors, generated fixtures, migrations, image/schema pairs, and rollback checks remain executable with a known-bad pair rejected."
    requirement: SRV-06
    verification:
      - kind: integration
        ref: "tooling/test-compatibility.sh#9 tests, 14 migrations, 6 skew lanes, 2 codec fixtures"
        status: pass
    human_judgment: false
  - id: D4
    description: "Flagged assumption: current-dogfood-only support remains valid until the first distributed build, when current-plus-previous for at least 90 days becomes active."
    requirement: SRV-06
    verification:
      - kind: other
        ref: ".planning/phases/KPL-02-synchronization-and-replaceable-server/02-04-PLAN.md#must_haves"
        status: unknown
    human_judgment: true
    rationale: "The release boundary has not occurred; the verifier must confirm the gate is updated when the first distributed build is published."

duration: 15min
completed: 2026-09-01
status: complete
---

# Phase KPL-02 Plan 04: Protocol Compatibility and Skew Matrix Summary

**Authoritative highest-train negotiation now pairs with a closed anonymous metadata endpoint and executable current/previous migration and rollback evidence.**

## Performance

- **Duration:** 15 min
- **Started:** 2026-09-01T06:56:40Z
- **Completed:** 2026-09-01T07:12:05Z
- **Tasks:** 3
- **Files modified:** 13 implementation, configuration, contract, fixture, and proof files

## Accomplishments

- Implemented pure current/dogfood, current-plus-previous, deadline, and evidence-bound emergency policy that always selects the highest common train or one stable upgrade direction.
- Exposed public `GET /compatibility` metadata with exact closed request/response contracts and application-start validation for immutable digest, protocol/schema ranges, platform builds, and the published support window.
- Added two retained codec fixtures and six exact skew lanes covering old/new clients, old/new schemas, prior images, and rollback, with a known-bad pair rejected.
- Proved all 14 migrations execute in a disposable PostgreSQL 18.6 database and kept the full 146-test server regression suite green.

## Task Commits

Each TDD task was committed as a RED test followed by its GREEN implementation:

1. **Task 1 RED: frozen protocol compatibility outcomes** - `fd5822b` (test)
2. **Task 1 GREEN: highest-intersection policy** - `6c9904c` (feat)
3. **Task 2 RED: failing public compatibility transport** - `d7d8bc1` (test)
4. **Task 2 GREEN: authoritative metadata endpoint and contracts** - `bf1b8b0` (feat)
5. **Task 3 RED: failing current/previous skew matrix** - `34c1bc7` (test)
6. **Task 3 GREEN: executable migration and rollback matrix** - `cbc3c56` (feat)

## Files Created/Modified

- `apps/server/lib/keepling/application/compatibility.ex` - Pure train negotiation, startup policy validation, metadata, and exact artifact eligibility.
- `apps/server/lib/keepling_web/controllers/compatibility_controller.ex` - Thin closed query decoder and public response adapter.
- `apps/server/lib/keepling_web/router.ex` - Anonymous unversioned compatibility route.
- `apps/server/lib/keepling/application.ex` - Fail-closed compatibility validation before supervision starts.
- `apps/server/config/config.exs` and `apps/server/config/runtime.exs` - Dogfood defaults and required production release/digest/update inputs.
- `apps/server/test/keepling/application/compatibility_test.exs` - Frozen policy, exhaustive range, retained codec, and artifact matrix tests.
- `apps/server/test/keepling_web/compatibility_controller_test.exs` - Anonymous, malformed, mismatch, privacy, and startup-validation transport proof.
- `packages/contracts/openapi/keepling.yaml` and `packages/contracts/generated/keepling.ts` - Closed compatibility operation and generated transport DTOs.
- `packages/contracts/vectors/compatibility.json` - Negotiation, retained codec/artifact fixtures, skew lanes, and known-bad rollback case.
- `tooling/check-contracts.mjs` - Compatibility anti-vacuity, exact input, and malformed-fixture validation.
- `tooling/test-compatibility.sh` - Disposable PostgreSQL migration and focused compatibility runner.

## Decisions Made

- Derived support from coarse integer trains only; platform marketing builds cannot influence authorization, invariants, conflicts, or protocol selection.
- Treated the deprecation deadline as inclusive, so the previous train remains safe through the exact advertised instant.
- Allowed early support-window contraction only when an effective emergency record carries evidence, an HTTPS notice, and an explicit local-intent preservation claim.
- Made exact tested digest, schema range, and protocol range jointly authoritative for rollback rather than accepting a mutable tag or schema-only check.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] Enforced compatibility validity before application startup**
- **Found during:** Task 2 (authoritative compatibility metadata)
- **Issue:** A request-time-only check would allow a server with a missing tested digest or malformed advertised ranges to start and serve other traffic.
- **Fix:** Added closed configuration validation to `Keepling.Application.start/2` and environment-owned production release/digest/update inputs.
- **Files modified:** `apps/server/lib/keepling/application.ex`, `apps/server/config/config.exs`, `apps/server/config/runtime.exs`, `apps/server/lib/keepling/application/compatibility.ex`
- **Verification:** Focused startup-validation tests and the 146-test full server suite passed.
- **Committed in:** `bf1b8b0`

**2. [Rule 2 - Missing critical functionality] Added compatibility contract anti-vacuity checks**
- **Found during:** Task 3 (current/previous compatibility matrix)
- **Issue:** The existing contract gate validated synchronization vectors but would not reject a zero-case compatibility lane, malformed exact digest, or missing retained codec fixture.
- **Fix:** Added closed compatibility vector validation, a deliberately malformed zero-case probe, and exact per-lane digest/schema/train evidence.
- **Files modified:** `tooling/check-contracts.mjs`
- **Verification:** `pnpm contracts:check` reported 6 negotiation cases, 2 codec fixtures, and 6 nonzero skew lanes.
- **Committed in:** `cbc3c56`

**3. [Rule 1 - Bug] Corrected the disposable matrix migration-count probe**
- **Found during:** Task 3 GREEN verification
- **Issue:** `psql` rejected Ecto's `ecto://` URL, and the runtime-preflight banner shared captured stdout with the numeric count.
- **Fix:** Used the runner's exact host/port/user/database inputs and selected the final numeric output line.
- **Files modified:** `tooling/test-compatibility.sh`
- **Verification:** The complete runner passed and reported 14 executable migrations.
- **Committed in:** `cbc3c56`

---

**Total deviations:** 3 auto-fixed (2 Rule 2, 1 Rule 1)
**Impact on plan:** The fixes make startup and matrix evidence fail closed without adding a dependency, service, or new canonical state.

## Issues Encountered

- The compatibility runner required two evidence-parsing corrections after its semantic tests were already green; the final full rerun passed from contract validation through disposable migration count.

## Known Stubs

None. The scan found no TODO/FIXME/placeholder path, skipped test, or hardcoded empty value flowing to a user surface.

## User Setup Required

Production releases must supply `KEEPLING_SERVER_RELEASE`, `KEEPLING_TESTED_OCI_DIGEST`, and `KEEPLING_UPDATE_LOCATION`; startup rejects missing or malformed values. No external service or credential is required for this plan's local evidence.

## Next Phase Readiness

- Plan 02-05 can attach authenticated synchronization transport to one authoritative train/recovery contract.
- Deployment preflight and rollback plans can consume exact digest/schema/protocol eligibility without duplicating policy in shell.
- Before the first downloadable Electron or TestFlight build, the dogfood policy must be changed to distributed current-plus-previous support with an advertised deadline of at least 90 days.

---
*Phase: KPL-02-synchronization-and-replaceable-server*
*Completed: 2026-09-01*

## Self-Check: PASSED

- All six created implementation, transport, test, vector, and runner artifacts plus this summary exist on disk.
- All six RED/GREEN task commits are present in Git history.
- Coverage metadata parsed successfully: three deliverables are backed by passing automation and the explicit first-distributed-build assumption remains routed to human verification.
