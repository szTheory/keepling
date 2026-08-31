---
phase: KPL-01-one-trustworthy-task
plan: 03
subsystem: server-runtime-and-testing
tags: [phoenix, exunit, ecto-sandbox, postgresql, concurrency, architecture-tests]

requires:
  - phase: KPL-01-02
    provides: Standalone Phoenix/Ecto core, exact lockfile, Repo supervision, and runtime configuration
provides:
  - Runnable route-empty Phoenix Endpoint with JSON errors, bounded telemetry, and explicit no-op seeds
  - SQL Sandbox DataCase and Endpoint ConnCase support for later server slices
  - Independent PostgreSQL connection/barrier helpers and deterministic clock/identity fixtures
  - Executable inward-dependency guard for domain and semantic application sources
affects: [KPL-01-05, server-http-adapters, server-concurrency-tests, architecture-enforcement]

actuals:
  tokens: 4348
  tasks: 2
  commits: 5

tech-stack:
  added: []
  patterns: [route-empty Phoenix adapter, unboxed SQL Sandbox concurrency, reusable process barrier, immutable deterministic clock, AST dependency guard]

key-files:
  created:
    - apps/server/lib/keepling_web.ex
    - apps/server/lib/keepling_web/endpoint.ex
    - apps/server/lib/keepling_web/router.ex
    - apps/server/lib/keepling_web/telemetry.ex
    - apps/server/test/support/concurrency_case.ex
    - apps/server/test/support/clock.ex
    - apps/server/test/architecture_test.exs
  modified:
    - apps/server/lib/keepling/application.ex

key-decisions:
  - "The OTP composition root starts Repo first and Endpoint last, retaining generated DNSCluster and Phoenix.PubSub support without placing transport imports in semantic application/domain roots."
  - "Concurrency tests use per-process unboxed SQL Sandbox checkouts, PostgreSQL backend PIDs, and an explicit reusable barrier so races cannot silently collapse into sequential calls."
  - "The deterministic test clock is immutable and explicitly threads time and preselected identities through command scenarios."

patterns-established:
  - "Phoenix adapter boundary: the initial /api scope is route-empty; later controllers must invoke inward semantic commands rather than database or raw-patch shortcuts."
  - "Concurrency evidence: each competitor owns a distinct real PostgreSQL backend and waits on a shared barrier before performing the raced operation."
  - "Architecture evidence: scan semantic domain/application AST module references against forbidden transport, persistence, generated-client, UI, MCP, and client-storage families."

requirements-completed: [QUAL-01, SRV-02]

coverage:
  - id: D1
    description: "Phoenix Endpoint, web namespace, route-empty router, bounded telemetry, JSON errors, and safe seeds compile as an outward adapter."
    requirement: SRV-02
    verification:
      - kind: integration
        ref: "./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix compile --warnings-as-errors && mix phx.routes'"
        status: pass
    human_judgment: false
  - id: D2
    description: "Two independently checked-out PostgreSQL connections pause and release on one deterministic barrier."
    requirement: QUAL-01
    verification:
      - kind: integration
        ref: "apps/server/test/architecture_test.exs#independent database connections pause and release at one barrier"
        status: pass
    human_judgment: false
  - id: D3
    description: "Domain and semantic application sources reject dependencies on Phoenix, persistence, generated clients, UI, MCP, and client storage."
    requirement: SRV-02
    verification:
      - kind: unit
        ref: "apps/server/test/architecture_test.exs#domain and semantic application sources have no outward dependencies"
        status: pass
      - kind: unit
        ref: "apps/server/test/architecture_test.exs#the dependency guard rejects every prohibited boundary family"
        status: pass
    human_judgment: false
  - id: D4
    description: "Endpoint requests use ConnCase while database tests retain explicit SQL Sandbox ownership."
    requirement: QUAL-01
    verification:
      - kind: integration
        ref: "./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test'"
        status: pass
    human_judgment: false

duration: 8min
completed: 2026-08-30
status: complete
---

# Phase KPL-01 Plan 03: Phoenix Runtime and Deterministic Test Boundary Summary

**Route-empty Phoenix 1.8 runtime with bounded telemetry, SQL Sandbox cases, real independent-connection barriers, deterministic time/IDs, and executable inward-dependency enforcement**

## Performance

- **Duration:** 8 min
- **Started:** 2026-08-31T01:22:07Z
- **Completed:** 2026-08-31T01:30:04Z
- **Tasks:** 2
- **Files modified:** 15

## Accomplishments

- Completed the supervised Phoenix runtime with Repo first, Endpoint last, route-empty `/api` plumbing, a closed JSON error shape, low-cardinality telemetry, and seeds that cannot create an account.
- Added generated-style DataCase and ConnCase support plus deterministic clock/identity fixtures for later semantic command tests.
- Proved with PostgreSQL 18.6 that two concurrent test processes receive distinct backend connections and remain blocked until both reach the same explicit barrier.
- Enforced D-02 with an AST-level architecture guard that detects forbidden outward module families and scans only the semantic domain/application roots, excluding the OTP composition root.

## Task Commits

Each task was committed atomically; Task 2 followed RED/GREEN TDD gates:

1. **Task 1: Materialize the runnable Phoenix web runtime** - `96a71ed` (feat)
2. **Task 2 RED: Add failing deterministic boundary tests** - `ca7123c` (test)
3. **Task 2 GREEN: Add deterministic server test support** - `9c8866b` (feat)
4. **Task 2 formatting correction** - `c26a2ff` (style)

## Files Created/Modified

- `apps/server/lib/keepling/application.ex` - Repo-first OTP composition with telemetry, DNS discovery, PubSub, Endpoint, and runtime config-change propagation.
- `apps/server/lib/keepling_web.ex` - Thin JSON-only Phoenix transport macros and verified-route configuration.
- `apps/server/lib/keepling_web/endpoint.ex` - Endpoint plugs with host-only signed session defaults and production Secure cookie behavior.
- `apps/server/lib/keepling_web/router.ex` - Route-empty JSON `/api` pipeline ready for the authenticated tracer.
- `apps/server/lib/keepling_web/telemetry.ex` - Endpoint, route-template, Repo timing, and VM metrics without task content, raw tokens, or arbitrary domain identifiers.
- `apps/server/lib/keepling_web/controllers/error_json.ex` - Closed `%{errors: %{detail: ...}}` transport error renderer.
- `apps/server/priv/repo/seeds.exs` - Explicit no-op seed entry documenting operator-owned account setup.
- `apps/server/priv/repo/migrations/.formatter.exs` - Generator marker that retains the empty migration boundary in Git and lets Mix migration aliases run.
- `apps/server/test/test_helper.exs` - ExUnit bootstrap and manual SQL Sandbox mode.
- `apps/server/test/support/data_case.ex` - Per-test SQL Sandbox owner lifecycle and changeset error helper.
- `apps/server/test/support/conn_case.ex` - Phoenix ConnTest setup coupled to DataCase ownership.
- `apps/server/test/support/concurrency_case.ex` - Unboxed independent connection checkout, backend identity, and reusable deterministic barrier.
- `apps/server/test/support/clock.ex` - Immutable injected time and identity sequence.
- `apps/server/test/architecture_test.exs` - Dependency guard self-test, real connection/barrier proof, and deterministic clock proof.
- `apps/server/test/keepling_web/controllers/error_json_test.exs` - Generated JSON error behavior through ConnCase.

## Decisions Made

- Kept `Keepling.Application` as the outward OTP composition root while architecture enforcement targets `lib/keepling/domain/**` and `lib/keepling/application/**`, preserving the plan's required Endpoint supervision without weakening D-02 for business rules.
- Retained generated `DNSCluster` and `Phoenix.PubSub` children because they are approved baseline runtime dependencies; no feature route, socket, or public account-creation path was added.
- Used `Ecto.Adapters.SQL.Sandbox.unboxed_run/2` in separate task processes and queried `pg_backend_pid()` so the test proves physical connection independence rather than assuming it.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Retained the empty migration boundary in Git**
- **Found during:** Task 2 RED verification
- **Issue:** The existing `mix test` alias runs migrations, but Plan 01-02 had not retained `priv/repo/migrations/`; Mix stopped before reaching the intended failing tests because Git cannot track an empty directory.
- **Fix:** Added the exact Phoenix-generator `priv/repo/migrations/.formatter.exs` marker.
- **Files modified:** `apps/server/priv/repo/migrations/.formatter.exs`
- **Verification:** The next RED run reached the missing concurrency/clock interfaces, and all later `mix test` runs executed normally.
- **Committed in:** `9c8866b`

**2. [Rule 1 - Bug] Corrected architecture-test formatting**
- **Found during:** Plan-level closure verification
- **Issue:** `mix format --check-formatted` required a blank line between two assertion groups in the committed RED test.
- **Fix:** Added the formatter-required blank line and reran the complete closure gate.
- **Files modified:** `apps/server/test/architecture_test.exs`
- **Verification:** Formatting, compile, targeted architecture tests, full ExUnit, repository integrity, and security scans all passed.
- **Committed in:** `c26a2ff`

---

**Total deviations:** 2 auto-fixed (1 Rule 3 blocking issue, 1 Rule 1 bug)
**Impact on plan:** The migration marker restores the generator inventory needed by the planned test alias, and the formatting fix satisfies the repository gate. Neither changes product behavior or dependency direction.

## Issues Encountered

- Context7 MCP and CLI lookup were unavailable, so implementation used the installed approved Phoenix 1.8.13 generator outputs and exact Ecto SQL 3.14 source documentation, followed by executable verification.
- A disposable loopback PostgreSQL 18.6 cluster supplied real independent connections for the TDD cycle and was stopped after the full suite passed.

## TDD Gate Compliance

- RED commit `ca7123c` recorded 2/4 passing and two failures caused specifically by absent `Keepling.ConcurrencyCase` and `Keepling.TestClock` public interfaces.
- GREEN commit `9c8866b` implemented the minimum support required; the targeted suite then passed 4/4 and the combined suite passed 6/6.
- No refactor commit was needed; the only post-GREEN change was the formatter correction in `c26a2ff`.

## Known Stubs

None - the empty router and no-op seeds are intentional security boundaries for Plans 01-05 and 01-06, not incomplete claims; no placeholder, TODO, skipped test, or unrun verification remains.

## User Setup Required

None - verification used an executor-owned disposable PostgreSQL 18.6 instance and left no running service.

## Next Phase Readiness

- Plan 01-05 can add its authenticated HTTP tracer to a runnable Endpoint and reuse ConnCase, DataCase, deterministic clock/IDs, and real concurrency barriers immediately.
- D-02 now has executable evidence before feature modules appear, and no high-severity test-isolation, dependency-direction, or telemetry-disclosure mitigation remains open.

## Self-Check: PASSED

- All 15 implementation/test artifacts and this summary exist on disk.
- Task and deviation commits `96a71ed`, `ca7123c`, `9c8866b`, and `c26a2ff` exist in Git history.
- Required `actuals`, coverage, requirements, TDD compliance, and `status: complete` metadata are present.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-30*
