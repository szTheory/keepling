---
phase: KPL-05-safe-agent-access
plan: 10
subsystem: mcp
tags: [testing, anti-vacuity, ex-unit, mcp-protocol, tooling, elixir, phoenix, postgresql, node]

# Dependency graph
requires:
  - phase: KPL-05-01
    provides: The `mcp` device-grant client kind, the D-06 scope vocabulary, the hand-rolled MCP JSON-RPC/Streamable HTTP endpoint at POST /mcp/v1, KeeplingWeb.MCP.Pipeline's bearer authentication, KeeplingWeb.MCP.Handshake's pinned protocol revision, KeeplingWeb.MCP.Dispatch's closed @methods table
provides:
  - "tooling/verify-mcp-phase.mjs -- the Phase 5 anti-vacuity gate runner: lane discovery by glob, exUnitSummary (sums every ExUnit invocation, subtracts skips/excluded, throws on a zero-case invocation or any failure), laneVerdict's PASS/BLOCKED/FAIL discriminator where a blocked lane still fails the run, inputDigestFor-bound verdicts, REQUIREMENT_LANES plus a live --requirements mode"
  - "tooling/mcp-gate-selftest.mjs -- ten cases attacking the harness itself with synthetic fixtures built from .planning/WINDOWS.md row 65's exact undercounted bundle counts"
  - "tooling/mcp-lanes/deterministic.mjs -- the ExUnit unit/contract lane over the MCP adapter and application test suites (105 genuine cases at this plan's completion)"
  - "tooling/mcp-lanes/protocol.mjs -- a real initialize handshake over the real Streamable HTTP transport against a live, disposable Phoenix server on real PostgreSQL, asserting the pinned protocol revision exactly and the dispatch module's closed method set"
  - "tooling/mcp-lanes/README.md -- the lane-module contract every later D-25 lane in this phase is written against"
  - "pnpm verify:mcp:phase / verify:mcp:selftest package.json scripts"
affects: [KPL-05-11, KPL-05-12]

actuals:
  tokens: 12890
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "A JS lane module exports a single default({ exUnitSummary, repositoryRoot }) function returning {command,args,cwd,env,name,parse,trackedInputPaths} -- verify-mcp-phase.mjs discovers lanes by glob and calls this shape, exactly mirroring tooling/ios-lanes/*.mjs's contract"
    - "A lane whose real work is async (boot a disposable server, do real HTTP) stays inside runLane's single spawnSync contract by being its own re-invocable script: tooling/mcp-lanes/protocol.mjs both exports a lane definition (command=node, args=[itself,'--run']) and executes the async handshake when invoked with --run, guarded by the usual main-module check"
    - "Elixir 1.20.2's own ExUnit CLI formatter already nets out skipped/excluded tests from its 'Result: N/M passed' total (measured directly, not assumed) -- exUnitSummary subtracts them again anyway as a deliberate, disclosed, conservative defense-in-depth so no future formatter change can silently reintroduce a Phase-4-style leak"
    - "A real PKCE-obtained MCP bearer over a live server is obtained entirely through fetch() with manual Set-Cookie/Cookie threading and redirect:'manual' on the /oauth/authorize step, mirroring apps/web/e2e/support/backend.ts's disposable-Postgres-plus-mix-phx.server pattern in plain Node rather than TypeScript"

key-files:
  created:
    - tooling/verify-mcp-phase.mjs
    - tooling/mcp-gate-selftest.mjs
    - tooling/mcp-lanes/deterministic.mjs
    - tooling/mcp-lanes/protocol.mjs
    - tooling/mcp-lanes/README.md
  modified:
    - package.json

key-decisions:
  - "REQUIREMENT_LANES maps all six requirements (MCP-01..05, SRV-02) only to the two lanes this plan actually ships (deterministic, protocol) rather than the aspirational five-D-25-lanes-plus-cross-adapter shape the plan's Task 1 prose describes. --requirements fails on any mapped lane with no file on disk, and simulated-client/representative-model/adversarial/cross-adapter genuinely do not exist until 05-11 (Wave 6) and 05-12 (Wave 7). 05-11-PLAN.md's own files_modified list names tooling/verify-mcp-phase.mjs, confirming it is the plan that extends this map -- this plan's map is this phase's honestly-scoped Wave-3 evidence inventory, not its final claim, and a code comment says so at the map's definition site."
  - "The protocol lane's capability assertion does not require 1:1 parity between a declared capability namespace and an implemented dispatch method. 'resources' is declared in KeeplingWeb.MCP.Handshake's capabilities but has zero resources/* methods in the dispatch table -- a disclosed stub named explicitly in 05-01-SUMMARY.md's Known Stubs, not a new gap this plan introduced. Requiring parity would fail this lane on an already-disclosed, intentional gap; instead the lane asserts the capability SET is exactly the closed {resources,tools} pair Handshake declares, and separately asserts the dispatch module's own closed method list never silently drifts from this lane's expectation."
  - "exUnitSummary subtracts skipped/excluded counts from ExUnit's own 'Result:' total even though Elixir 1.20.2's own accounting (measured directly: test_counter increments only on a terminal nil/failed state, never on skipped/excluded) already excludes them. This can only ever make the published count MORE conservative -- it never inflates evidence, and a bundle that is entirely skips correctly reduces to zero and fails here rather than reporting its pre-skip declared total."
  - "The protocol lane boots its own throwaway PostgreSQL cluster and mix phx.server process (mirroring apps/web/e2e/support/backend.ts's pattern) rather than depending on a developer's already-running local database, so the lane is self-contained and safe to run repeatedly without state leakage between runs. Ports (KEEPLING_MCP_PROTOCOL_POSTGRES_PORT/KEEPLING_MCP_PROTOCOL_PHOENIX_PORT, defaults 55450/4210) and the disposable database name (keepling_mcp_protocol) are chosen to avoid colliding with every other lane's documented default port in this repository."

requirements-completed: []  # MCP-01, MCP-02, MCP-03, MCP-04, MCP-05, SRV-02 are all declared by multiple plans in this phase; none is ready to mark complete from this plan alone (this plan builds the gate, not the requirement's own behavior).

coverage:
  - id: D1
    description: "The phase gate publishes a case count that equals the number of cases actually executed: every ExUnit bundle summed, skips subtracted, no bundle silently discarded -- proven against synthetic fixtures built from .planning/WINDOWS.md row 65's exact undercounted numbers."
    requirement: "SRV-02"
    verification:
      - kind: unit
        ref: "tooling/mcp-gate-selftest.mjs#two ExUnit invocations of 19 and 18 cases sum to 37, not 18 and not 19"
        status: pass
      - kind: unit
        ref: "tooling/mcp-gate-selftest.mjs#a summary of 19 cases with 4 skipped publishes 15, never the pre-subtraction 19"
        status: pass
      - kind: unit
        ref: "tooling/mcp-gate-selftest.mjs#two summaries where one reports zero cases throws -- the lane does not pass"
        status: pass
    human_judgment: false
  - id: D2
    description: "A lane that genuinely cannot run reports BLOCKED, is visually distinct from FAIL, and still makes the run exit non-zero; a lane returning zero cases without throwing is reported failed, never passed."
    requirement: "SRV-02"
    verification:
      - kind: unit
        ref: "tooling/mcp-gate-selftest.mjs#a lane whose parse error begins with the blocked prefix is reported blocked, never passed"
        status: pass
      - kind: unit
        ref: "tooling/mcp-gate-selftest.mjs#a lane returning a case count of zero without throwing is reported failed, not passed"
        status: pass
    human_judgment: false
  - id: D3
    description: "Every phase requirement (MCP-01..05, SRV-02) maps to at least one lane whose file genuinely exists on disk, read live from .planning/REQUIREMENTS.md's Phase 5 row."
    requirement: "SRV-02"
    verification:
      - kind: integration
        ref: "node tooling/verify-mcp-phase.mjs --requirements"
        status: pass
    human_judgment: false
  - id: D4
    description: "The deterministic lane runs the real ExUnit suite over the MCP adapter and application modules and reports a genuine positive case count bound to a digest of the tracked inputs it exercised."
    requirement: "MCP-02"
    verification:
      - kind: integration
        ref: "node tooling/verify-mcp-phase.mjs --lane deterministic (cases=105)"
        status: pass
    human_judgment: false
  - id: D5
    description: "The protocol lane performs a real MCP initialize handshake over the real Streamable HTTP transport against a live server (never Phoenix.ConnTest's simulated cycle), asserting the pinned protocol revision exactly and the dispatch module's closed method set, and reports BLOCKED rather than passing when no server is reachable."
    requirement: "MCP-01"
    verification:
      - kind: integration
        ref: "node tooling/verify-mcp-phase.mjs --lane protocol (cases=2, protocol_version=2025-06-18)"
        status: pass
    human_judgment: true
    rationale: "The BLOCKED path (no server reachable) is exercised by code inspection and by every runChecked/waitForPort call site throwing the blocked() constructor, not by a dedicated test that actually starves the lane of a server -- doing so would mean deliberately breaking runtime-preflight.sh or occupying its ports mid-suite. A human or a later plan's review should confirm the BLOCKED path fires correctly the first time it is genuinely needed (e.g. if runtime-preflight.sh is ever missing in a CI image)."

duration: ~70min
completed: 2026-09-10
status: complete
---

# Phase 5 Plan 10: The MCP Phase Gate -- Anti-Vacuity Runner, Self-Test, and Two Real Lanes Summary

**A glob-discovered, self-testing gate runner (`tooling/verify-mcp-phase.mjs`) with a
real ExUnit lane (105 cases) and a real over-the-wire PKCE-to-`initialize` protocol
handshake lane (2 cases) against a live, disposable Phoenix/PostgreSQL server -- built
distrustfully on the FIXED iOS gate structure, with its own harness attacked by ten
tests built from `.planning/WINDOWS.md` row 65's exact undercounted numbers.**

## Performance

- **Duration:** ~70 min
- **Tasks:** 3 (all `type="auto"`, Task 2 `tdd="true"`)
- **Files created:** 5
- **Files modified:** 1

## Accomplishments

- `tooling/verify-mcp-phase.mjs`: lanes discovered by `readdirSync` glob over
  `tooling/mcp-lanes/*.mjs` (never an inline list); a lane file that fails to
  `import()` ends the run with a non-zero exit; `exUnitSummary` anchors on **every**
  `Result:` line ExUnit's own CLI formatter prints and sums them, subtracting
  skipped/excluded and throwing on a zero-case invocation, an unparseable output, or
  any reported failure; `laneVerdict` is the pure PASS/BLOCKED/FAIL discriminator
  (`BLOCKED:`-prefixed parse errors are distinct from FAIL but still fail the run);
  `inputDigestFor`/`gitLsFiles` bind every verdict to a SHA-256 digest of the
  git-tracked inputs it exercised; `REQUIREMENT_LANES` plus a live `--requirements`
  mode read this phase's row straight from `.planning/REQUIREMENTS.md` and fail on
  any unmapped requirement or missing lane file; `--lane <name>` matches the iOS
  runner's flag; a fresh `RUN_ID` (`randomUUID()`) is generated once per module load
  and printed on every `LANE`/summary line.
- `tooling/mcp-gate-selftest.mjs`: ten `node --test` cases, including two built from
  `.planning/WINDOWS.md` row 65's own real numbers (19+18 -> 37 summed; 19 with 4
  skipped -> 15 published), a two-bundle run where one reports zero cases (throws), a
  non-parseable output (throws), a real failure count (throws even with no exit-status
  argument passed), a blocked lane (not passed, still fails), a zero-case lane that
  returns without throwing (failed, not passed), digest sensitivity to file contents
  plus an untracked path contributing nothing, and a per-run identifier proven to
  differ across two independent module loads.
- `tooling/mcp-lanes/deterministic.mjs`: `mix test` over
  `test/keepling_web/mcp test/keepling/application test/keepling/accounts/device_grant_test.exs`
  through `tooling/runtime-preflight.sh --exec`, parsed by `exUnitSummary`. Verified
  live against this worktree's real PostgreSQL: **105 genuine cases**, input digest
  bound to the MCP adapter, application-layer tests, `agent_scope.ex`, and
  `device_grant.ex` (plus the not-yet-landed `search.ex`/`preview.ex`, which correctly
  contribute only their names to the digest today).
- `tooling/mcp-lanes/protocol.mjs`: boots its own disposable PostgreSQL cluster and
  `mix phx.server` process, creates a real account fixture via a real Argon2 hash,
  logs in over real HTTP, walks the full real PKCE authorization-code flow
  (`/oauth/authorize` -> `/oauth/token`) to obtain a genuine `mcp` bearer, then POSTs a
  real `initialize` JSON-RPC request to `/mcp/v1` and asserts `protocolVersion` equals
  `2025-06-18` **exactly** plus the declared `{resources,tools}` capability set is the
  exact closed pair `KeeplingWeb.MCP.Handshake` declares, cross-checked against
  `KeeplingWeb.MCP.Dispatch`'s own `@methods` source (read statically, not trusted from
  the live response alone) for silent drift. Verified live end to end: **2 cases**,
  clean process shutdown confirmed (no leaked `postgres`/`beam.smp` processes, no
  lingering listeners on the lane's ports after the run).
- `tooling/mcp-lanes/README.md`: states all four contract points from the plan's
  action text (parse must throw on unparseable output; a lane that cannot run throws
  `BLOCKED:` and never passes; a lane's published count is genuinely-executed cases
  only; a lane's verdict carries a tracked-input digest) plus a table of this phase's
  planned lanes and which plan owns each.
- `pnpm verify:mcp:selftest` (self-test alone) and `pnpm verify:mcp:phase`
  (self-test, then both real lanes) both verified passing live, end to end, against
  this worktree's real runtime -- not merely reviewed for shape.

## Task Commits

1. **Task 1: The gate runner, copied from the fixed iOS structure** -- `1825334`
   (feat)
2. **Task 2: Try to fool the counter -- a test of the harness itself** -- `bad8a12`
   (test, TDD: the self-test itself was iterated against the real digest/summary
   functions until every case genuinely held)
3. **Task 3: The deterministic and protocol lanes** -- `6ceb25e` (feat)

**Plan metadata:** committed alongside this SUMMARY.

## Files Created/Modified

- `tooling/verify-mcp-phase.mjs` -- the gate runner
- `tooling/mcp-gate-selftest.mjs` -- tests of the harness itself
- `tooling/mcp-lanes/deterministic.mjs` -- the ExUnit lane
- `tooling/mcp-lanes/protocol.mjs` -- the real-transport handshake lane
- `tooling/mcp-lanes/README.md` -- the lane-module contract
- `package.json` -- `verify:mcp:phase`, `verify:mcp:selftest`

## Decisions Made

See `key-decisions` in frontmatter for the full rationale on: `REQUIREMENT_LANES`'s
honestly Wave-3-scoped mapping (only `deterministic`/`protocol`, with 05-11 named as
the plan that extends it), the protocol lane's capability-set assertion deliberately
not requiring capability/method parity (so it does not fail on 05-01's already
disclosed `resources` stub), the deliberate double-subtraction of skips/excluded in
`exUnitSummary` (conservative-only, never inflates evidence), and the protocol lane's
self-contained disposable-Postgres/disposable-Phoenix construction.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `sh -c` string interpolation silently dropped Ecto's `$1`/`$2`/`$3` SQL parameters**
- **Found during:** Task 3, first live run of `protocol.mjs`'s account-fixture step
- **Issue:** The account-creation Elixir script was originally embedded directly into
  a `sh -c "cd apps/server && mix run -e \"...\""` string. Ecto's positional SQL
  parameters (`$1`, `$2`, `$3`) inside that DOUBLE-QUOTED shell string were expanded
  by `sh` as empty shell positional parameters before Elixir ever saw them, producing
  a malformed `INSERT INTO accounts (...) VALUES (, TRUE, , 'Etc/UTC', , )` and a
  syntax error.
- **Fix:** Pass the Elixir script through a shell VARIABLE REFERENCE
  (`"$KEEPLING_LANE_ACCOUNT_SCRIPT"`) set via the spawned process's environment
  instead of interpolating it directly into the command string. A variable reference
  is expanded once, wholesale, with no rescan of its value for further `$`-sequences.
- **Files modified:** `tooling/mcp-lanes/protocol.mjs` (caught and fixed before any
  commit -- no broken version was ever committed)
- **Verification:** `node tooling/mcp-lanes/protocol.mjs --run` completed the full
  PKCE-to-`initialize` flow end to end against a real disposable server
- **Committed in:** `6ceb25e` (Task 3 commit; the fix was already in place before the
  first commit touching this file)

**2. [Rule 1 - Scope interpretation, documented] `REQUIREMENT_LANES` scoped to this plan's two real lanes, not the plan text's full five-lane-plus-cross-adapter description**
- **Found during:** Task 1, before writing `REQUIREMENT_LANES`
- **Issue:** Task 1's action text says to map all six requirements "to the five D-25
  lanes plus the cross-adapter lane," but this plan (Wave 3) ships only
  `deterministic` and `protocol`; `simulated-client`, `representative-model`,
  `adversarial`, and `cross-adapter` do not exist as files until 05-11 (Wave 6) and
  05-12 (Wave 7). Both Task 1's own `<verify>` and the plan-level `<verification>`
  block require `--requirements` to PASS at this plan's completion, and
  `--requirements` fails on any mapped lane with no file on disk -- so mapping to
  not-yet-existing lane names would make this plan's own required verification fail.
- **Fix:** `REQUIREMENT_LANES` maps every requirement only to `deterministic` and
  `protocol` for now, with an explicit code comment naming 05-11-PLAN.md (confirmed by
  reading its `files_modified` list, which names `tooling/verify-mcp-phase.mjs`) as
  the plan that extends this map to the full shape as it adds the remaining lane
  files.
- **Files modified:** `tooling/verify-mcp-phase.mjs`
- **Verification:** `node tooling/verify-mcp-phase.mjs --requirements` passes and
  lists all six requirement identifiers
- **Committed in:** `1825334` (Task 1 commit)

---

**Total deviations:** 2 (1 bug caught and fixed before any commit, 1 documented scope
interpretation resolving a genuine tension between the plan's aspirational Task 1
prose and its own immediate `<verify>` requirement). **Impact on plan:** Neither
affects the plan's `must_haves` -- all six truths and all five prohibitions hold, each
proven by a self-test case or by a live `--requirements`/lane run, not by inspection
alone.

## Known Stubs

None introduced by this plan. `tooling/mcp-lanes/protocol.mjs`'s capability assertion
explicitly does NOT require the `resources` capability to have a matching
`resources/*` dispatch method -- that gap is 05-01's own disclosed stub (see
05-01-SUMMARY.md's Known Stubs), not something this plan introduces or silently
accepts without naming it in a code comment at the assertion site.

## Broken-Windows Ledger

No `gsd-tools.cjs` binary was present in this worktree (matching 05-08's own finding
for the same reason), so `.planning/WINDOWS.md` could not be updated via
`gsd_run windows append`. Recorded here instead for a future pass with tooling access:

- deviation: `tooling/verify-mcp-phase.mjs` -- `REQUIREMENT_LANES` currently maps all
  six requirements only to `deterministic`/`protocol` (this plan's two real lanes),
  not the full five-D-25-lanes-plus-cross-adapter shape the plan's own Task 1 prose
  describes; 05-11-PLAN.md is the plan that extends it (see Deviations #2 above)
- deviation: `tooling/mcp-lanes/protocol.mjs` -- an `sh -c` string-interpolation bug
  that silently dropped Ecto's `$1`/`$2`/`$3` SQL parameters was found and fixed
  before any commit (see Deviations #1 above); recorded for visibility, not because
  any broken version ever shipped

## Issues Encountered

- No `gsd-tools.cjs` binary was present in this worktree, matching the pattern
  05-08-SUMMARY.md already recorded for the same reason. `.planning/WINDOWS.md` could
  not be updated via the standard verb; the two findings above are recorded in this
  SUMMARY's Broken-Windows Ledger section instead.
- This worktree had no `apps/server/deps` or `apps/server/_build` installed at spawn
  time (matching 05-08's own finding). `mix deps.get` (via `runtime-preflight.sh`) was
  run to make verification possible -- a standard, non-destructive setup step for a
  fresh worktree, not a deviation from the plan.

## User Setup Required

None -- no external service configuration required. `tooling/mcp-lanes/protocol.mjs`
provisions its own throwaway PostgreSQL cluster and Phoenix server per run; no
developer machine state is required or assumed beyond `tooling/runtime-preflight.sh`'s
already-pinned Elixir/OTP/PostgreSQL toolchain.

## Next Phase Readiness

- The Phase 5 gate this phase's later claims will rest on now exists, is
  self-testing, and has proven itself against real evidence (not stubs or fakes) for
  two of the eventual six D-25-plus-cross-adapter lanes.
- `tooling/mcp-lanes/README.md`'s contract and `verify-mcp-phase.mjs`'s exported
  `exUnitSummary`/`laneVerdict`/`inputDigestFor` surface are the extension points
  05-11 (`simulated-client`, `representative-model`, `adversarial`) and 05-12
  (`cross-adapter`) build on without altering any module boundary this plan
  introduced.
- 05-11-PLAN.md must also extend `REQUIREMENT_LANES` in `tooling/verify-mcp-phase.mjs`
  as it lands its three lanes (already confirmed reachable: its own
  `files_modified` names that file) -- this plan's map is disclosed as a Wave-3
  snapshot, not this phase's final claim, in both the source comment and this
  SUMMARY's Deviations section.
- MCP-01..05 and SRV-02 remain unchecked in `REQUIREMENTS.md`, correctly: this plan
  builds gate infrastructure, not the requirement's own behavior, and multiple
  sibling plans in this phase also declare each of these ids.

---
*Phase: KPL-05-safe-agent-access*
*Completed: 2026-09-10*

## Self-Check: PASSED

- `tooling/verify-mcp-phase.mjs` -- FOUND on disk
- `tooling/mcp-gate-selftest.mjs` -- FOUND on disk
- `tooling/mcp-lanes/deterministic.mjs` -- FOUND on disk
- `tooling/mcp-lanes/protocol.mjs` -- FOUND on disk
- `tooling/mcp-lanes/README.md` -- FOUND on disk
- Commits `1825334`, `bad8a12`, `6ceb25e` all found in `git log --oneline --all`
- `pnpm run verify:mcp:selftest`: 10/10 passing
- `pnpm run verify:mcp:phase`: self-test then both lanes, exits 0 (protocol cases=2,
  deterministic cases=105)
- `node tooling/verify-mcp-phase.mjs --requirements`: passes, lists MCP-01, MCP-02,
  MCP-03, MCP-04, MCP-05, SRV-02
- No stray `postgres`/`beam.smp` processes or open listeners left behind after
  `protocol.mjs`'s live run (checked via `ps aux` and `lsof`)
