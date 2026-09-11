---
phase: KPL-05-safe-agent-access
plan: 12
subsystem: mcp
tags: [testing, anti-vacuity, cross-adapter, srv-02, tooling, elixir, phoenix, postgresql, node]

# Dependency graph
requires:
  - phase: KPL-05-10
    provides: "tooling/verify-mcp-phase.mjs's lane-discovery/BLOCKED/exUnitSummary/REQUIREMENT_LANES gate contract this plan's lane wrapper plugs into"
  - phase: KPL-05-11
    provides: "tooling/mcp-client/{client,final-state}.mjs -- bootDisposableServer, obtainGrant, toolsCall, readFinalState -- reused unchanged as this lane's server bootstrap and evidence-reading layer"
provides:
  - "tooling/verify-cross-adapter-phase.mjs -- the D-27 cross-adapter orchestrator: one real disposable Phoenix/PostgreSQL instance, one inputDigestFor, one run identifier, four legs run in sequence, cross-leg comparison"
  - "tooling/cross-adapter/scenario-report.mjs -- the CROSS_ADAPTER_SCENARIO evidence line format, parser, and compareLegs cross-leg equality check (8 node --test cases)"
  - "tooling/cross-adapter/legs.mjs -- web-api and mcp legs (real, verified live); electron and iphone legs (real precondition checks, disclosed BLOCKED pending a live driver)"
  - "tooling/mcp-lanes/cross-adapter.mjs -- the cross-adapter lane wrapper under the 05-10 gate contract"
  - "tooling/verify-mcp-phase.mjs's REQUIREMENT_LANES SRV-02 row extended to include cross-adapter"
  - "docs/testing/cross-adapter-testing.md"
affects: []

actuals:
  tokens: 21000
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Every leg exposes capture/complete/reopen against a shared runSharedScenarioSet driver, so the 4-scenario set is enforced by code sharing rather than four independently-written copies that could quietly diverge -- the same discipline 05-11's client.mjs/scenarios.mjs pair already established, applied across adapters instead of within one."
    - "Every CROSS_ADAPTER_SCENARIO field is read back from the server's own APIs (task revision, activity feed) via the SAME account session cookie regardless of which adapter performed the mutation, never from the acting adapter's own response body -- extends the D-26 final-state-not-self-report discipline from single-lane scoring to cross-adapter comparison."
    - "GET /api/v1/tasks/:id/activity returns items NEWEST FIRST -- measured directly against a live server; the most recent activity fact is facts[0], not facts.at(-1). Documented in a code comment at the read site after being caught by a live run producing an identical-but-wrong result (task_captured reported for complete/reopen scenarios) that only comparison against a SECOND leg's identical wrongness would have hidden if left unfixed."
    - "A genuine stale-expected-revision refusal requires a LIFECYCLE command (complete/reopen), not edit/clarify: Keepling.Domain.Task.lifecycle_transition/4 refuses only when lifecycle_revision > expected_revision (a staleness check), while edit_task's conflict detection is a separate base_values three-way merge that does not consult expected_revision at all -- measured live, not assumed from source reading alone."

key-files:
  created:
    - tooling/verify-cross-adapter-phase.mjs
    - tooling/cross-adapter/scenario-report.mjs
    - tooling/cross-adapter/legs.mjs
    - tooling/mcp-lanes/cross-adapter.mjs
    - docs/testing/cross-adapter-testing.md
  modified:
    - tooling/verify-mcp-phase.mjs
    - package.json
    - .planning/REQUIREMENTS.md
    - .planning/WINDOWS.md

key-decisions:
  - "The shared scenario set is 4 scenarios (capture_one_task, complete_task, reopen_task, update_stale_expected_revision), not the full 9 in tooling/mcp-client/scenarios.mjs. Two of the nine (preview_and_commit_multi_target, commit_stale_preview) exercise D-17's preview/commit primitive, which is an MCP-only wire construct in this phase -- no HTTP /commands/* endpoint, no Electron IPC command, no iPhone app action expose an equivalent two-step preview/commit surface (grep -n 'preview|bulk' apps/server/lib/keepling_web/router.ex returns nothing). This narrows what D-27 proves to MCP-02's four write verbs; MCP-05's bulk/destructive guarantee remains proven single-adapter by 05-11's adversarial/simulated-client lanes until a later plan gives every adapter its own preview/commit surface. Disclosed in a code comment at the top of legs.mjs and in docs/testing/cross-adapter-testing.md."
  - "The stale-revision scenario uses two lifecycle commands (complete, then reopen with the SAME expected_revision) rather than a single edit attempt with a bad revision. Measured live against the real server while writing this lane: edit_task's conflict detection never consults expected_revision at all (a base_values three-way merge only), and a lifecycle command's own check is lifecycle_revision > expected_revision (a staleness comparison, not equality) -- so a first-ever lifecycle command with any expected_revision passes trivially. A freshly captured task's lifecycle_revision starts at 1; complete(expected_revision=1) advances it to 2; reusing expected_revision=1 on the next lifecycle call is then genuinely stale and refused, uniformly on every one of the four shared verbs."
  - "electron and iphone legs check their real precondition (a packaged build at apps/desktop/out; the app installed on a booted simulator) and, even when the precondition is met, still report BLOCKED naming that a live driver against that artifact is not yet wired -- rather than fabricating or partially faking evidence. Building the packaged-Electron IPC driver and the iPhone recording-proxy driver is the next increment, disclosed in docs/testing/cross-adapter-testing.md and .planning/WINDOWS.md #69, not silently deferred."
  - "The plan's Task 1 acceptance criterion (a grep for KEEPLING_TEST_SYNC_MODE/.invalid guard patterns in verify-cross-adapter-phase.mjs's own source) counts 0: the shortcut-refusal guards are enforced by calling client.mjs's guardAgainstShortcuts(file) on this orchestrator's own file and on legs.mjs, not by duplicating the guard pattern strings inline. Verified functionally equivalent -- guardAgainstShortcuts is called on both files at the top of every live run and throws before any server boots if either file contains a shortcut pattern. Reported here per the criterion's own instruction to name the count."

requirements-completed: []
# SRV-02 is this plan's sole declared requirement and is deliberately NOT
# marked complete: the cross-adapter lane ran live and 2 of its 4 legs
# (electron, iphone) are disclosed BLOCKED, per the plan's own instruction
# that a blocked leg is disclosed missing evidence, never grounds for a
# completion claim. See Deviations and Known Stubs below.

coverage:
  - id: D1
    description: "One evidence format (CROSS_ADAPTER_SCENARIO) that only accepts server-observed values, with its own parser and a cross-leg comparison function proven to fail on a scenario missing from one leg and on a differing conflict shape."
    requirement: "SRV-02"
    verification:
      - kind: unit
        ref: "node --test tooling/cross-adapter/scenario-report.mjs (8/8 passing, including 'compareLegs fails when a scenario is missing from one leg' and 'compareLegs fails on a differing conflict shape between legs')"
        status: pass
    human_judgment: false
  - id: D2
    description: "The web-api and mcp legs drive the identical semantic scenario set against ONE real server instance and produce byte-identical result codes, conflict shapes, activity facts, and revisions -- proven live, not asserted."
    requirement: "SRV-02"
    verification:
      - kind: integration
        ref: "node tooling/verify-cross-adapter-phase.mjs (legs_ran=2, comparison_ok=true, run_id eaa5b67a-b1ee-4927-bcdf-7cea4fb5ad50, input_digest 74df127034c515f7)"
        status: pass
    human_judgment: false
  - id: D3
    description: "A leg that cannot run (no packaged Electron build; no live iPhone UI driver) BLOCKS the lane with a named, disclosed reason -- never a fixture, a fake, or a silent pass -- and the overall lane exits non-zero while any leg is BLOCKED."
    requirement: "SRV-02"
    verification:
      - kind: integration
        ref: "node tooling/verify-cross-adapter-phase.mjs exits 1 with CROSS_ADAPTER_PHASE_GATE: BLOCKED naming electron and iphone; node tooling/verify-mcp-phase.mjs --lane cross-adapter reports status=BLOCKED (not FAIL)"
        status: pass
    human_judgment: false
  - id: D4
    description: "SRV-02's requirement-to-lane map now includes cross-adapter, and the full six-requirement, six-lane phase gate shows no regression from 05-11's lanes."
    requirement: "SRV-02"
    verification:
      - kind: integration
        ref: "node tooling/verify-mcp-phase.mjs --requirements (all six requirement ids mapped); pnpm run verify:mcp:phase equivalent invocation (deterministic=183, protocol=2, simulated-client=9, adversarial=6, cross-adapter=BLOCKED, representative-model=BLOCKED, both honest)"
        status: pass
    human_judgment: false
  - id: D5
    description: "The electron and iphone legs' full live-driving success path -- IPC-driven scenarios against a packaged Electron build, and UI-driven scenarios against an installed iPhone simulator app -- has not been exercised in this session."
    requirement: "SRV-02"
    verification: []
    human_judgment: true
    rationale: "No packaged Electron build exists in this worktree (apps/desktop/out is absent) and building one plus wiring a live IPC driver was out of this session's practical scope. A Keepling app IS installed on the booted iOS Simulator, but this lane has no live UI/recording-proxy driver wired against it yet. Both legs' precondition-check paths (existence of the artifact) ARE proven live and correctly report BLOCKED with the missing artifact/driver named -- see D3 above -- but the SUCCESS path for either hardware leg is unexercised. A human or a later plan must run pnpm package:desktop, wire the packaged-app IPC driver (following verify-real-stack-desktop.mjs's discipline), and wire the iPhone recording-proxy driver (following verify-real-stack-ios.mjs's pattern) before SRV-02's checkbox can be restored."

duration: ~75min
completed: 2026-09-11
status: complete
---

# Phase 5 Plan 12: The Cross-Adapter Proof -- SRV-02's Evidence Format, Orchestrator, and Two of Four Live Legs Summary

**A one-server, one-run-identifier cross-adapter orchestrator with a self-tested evidence
comparator proves web/API and MCP produce byte-identical result codes, conflict shapes,
activity facts, and revisions for the same 4 shared scenarios -- while the Electron and iPhone
legs correctly, honestly report BLOCKED on their real missing prerequisites rather than SRV-02
being marked complete on partial evidence.**

## Performance

- **Duration:** ~75 min
- **Started:** 2026-09-11 (base commit 845fa24)
- **Completed:** 2026-09-11
- **Tasks:** 3 (all `type="auto"`)
- **Files created:** 5
- **Files modified:** 4

## Accomplishments

- `tooling/cross-adapter/scenario-report.mjs`: the `CROSS_ADAPTER_SCENARIO` evidence line
  format (run identifier, leg, scenario, server-observed result code, conflict shape, activity
  fact, final revision), `parseScenarioLines`, and `compareLegs` -- the cross-leg equality
  check. Proven by 8 `node --test` cases run directly against this worktree, including the two
  the plan's acceptance criteria name: a scenario missing from one leg, and a differing conflict
  shape between legs.
- `tooling/verify-cross-adapter-phase.mjs`: boots exactly ONE real, disposable Phoenix/
  PostgreSQL instance (reusing 05-11's `bootDisposableServer`), computes ONE `inputDigestFor`
  over the server source tree, mints ONE run identifier, and runs all four legs against that
  single instance, ranking the precondition-gated legs (electron, iphone) first so an
  unavailable packaged build or simulator is discovered in seconds. `--dry-run` lists all four
  legs without booting anything.
- `tooling/cross-adapter/legs.mjs`: a single `runSharedScenarioSet` driver runs
  capture/complete/reopen/stale-revision against any adapter exposing those three methods, then
  reads final task state and activity back from the server's own APIs (never the acting
  adapter's own response) for the evidence line. **`web-api`** drives `/api/v1/commands/*`
  directly with the disposable server's own browser session, CSRF token, and Origin header --
  verified live. **`mcp`** drives `tooling/mcp-client/client.mjs`'s real PKCE-obtained grant --
  verified live. **`electron`**/**`iphone`** check their real precondition (packaged build at
  `apps/desktop/out`; app installed on a booted simulator) and report `BLOCKED` naming exactly
  what is missing when unmet, or that a live driver is not yet wired when the precondition IS
  met -- never a fixture or a fabricated result.
- `tooling/mcp-lanes/cross-adapter.mjs`: wraps the orchestrator as a lane under the 05-10 gate
  contract, parsing `CROSS_ADAPTER_SUMMARY`/`CROSS_ADAPTER_PHASE_GATE` lines into
  `PASS`/`BLOCKED`/`FAIL` per the same discriminator every other lane uses.
- `tooling/verify-mcp-phase.mjs`: `REQUIREMENT_LANES`'s `SRV-02` row now includes
  `cross-adapter` alongside `deterministic`/`protocol`.
- `docs/testing/cross-adapter-testing.md`: how to run the lane, what each leg needs and how long
  it takes, what a BLOCKED leg means, why this is a phase-gate cadence, and the deliberate
  4-scenario scope narrowing from the plan's aspirational 9.
- **Verified live against this worktree's real PostgreSQL/Phoenix**, run identifier
  `eaa5b67a-b1ee-4927-bcdf-7cea4fb5ad50`, input digest `74df127034c515f7`:

  | Lane / leg | Status | Cases / scenarios | Notes |
  |---|---|---|---|
  | `deterministic` | PASS | 183 | no regression from 05-11 |
  | `protocol` | PASS | 2 | no regression from 05-11 |
  | `simulated-client` | PASS | 9 | no regression from 05-11 |
  | `adversarial` | PASS | 6 | no regression from 05-11 |
  | `representative-model` | BLOCKED | 0 | honest -- `ANTHROPIC_API_KEY` unreachable in this isolated worktree session, per the environment note; not new to this plan |
  | `cross-adapter` (this plan) | BLOCKED | 0 (lane-level; see legs below) | disclosed -- 2 of 4 legs blocked |
  | `cross-adapter` leg `web-api` | PASS | 4/4 scenarios | fully real, live |
  | `cross-adapter` leg `mcp` | PASS | 4/4 scenarios | fully real, live |
  | `cross-adapter` leg `electron` | BLOCKED | 0/4 | no packaged build at `apps/desktop/out` in this worktree |
  | `cross-adapter` leg `iphone` | BLOCKED | 0/4 | Keepling IS installed on the booted simulator, but no live UI driver is wired against it yet |

  `compareLegs(web-api, mcp)` reported `comparison_ok=true` -- every one of the 4 scenarios'
  `result_code`, `conflict_shape`, `activity_fact`, and `final_revision` matched exactly between
  the two legs that ran.

## Task Commits

1. **Task 1: One server instance, one evidence format, one run identifier** -- `0290a07` (feat)
2. **Task 2: The four legs, each producing its own fresh evidence** -- `305d887` (feat)
3. **Task 3: Restore SRV-02, and cite the run that earned it** -- `0788ca0` (docs; SRV-02 stays
   unchecked because 2 legs were blocked -- see Deviations)

**Plan metadata:** committed alongside this SUMMARY.

## Files Created/Modified

- `tooling/verify-cross-adapter-phase.mjs` -- the orchestrator
- `tooling/cross-adapter/scenario-report.mjs` -- evidence format, parser, comparator
- `tooling/cross-adapter/legs.mjs` -- the four leg drivers
- `tooling/mcp-lanes/cross-adapter.mjs` -- the lane wrapper
- `docs/testing/cross-adapter-testing.md` -- how to run it, what a BLOCKED leg means
- `tooling/verify-mcp-phase.mjs` -- `REQUIREMENT_LANES` extended
- `package.json` -- `verify:cross-adapter` added
- `.planning/REQUIREMENTS.md` -- SRV-02 entry and Phase 5 traceability row updated with this
  run's citation (checkbox stays unchecked)
- `.planning/WINDOWS.md` -- entry #69 recording the two blocked legs

## Decisions Made

See `key-decisions` in frontmatter for the full rationale on: the deliberate 4-scenario
narrowing from the plan's aspirational 9-scenario set (D-17 preview/commit has no non-MCP wire
equivalent today), the two-lifecycle-command construction of the stale-revision scenario
(measured live: `edit_task` never checks `expected_revision`, and a lifecycle command's own
check is a staleness comparison, not equality), the electron/iphone legs' real-but-still-BLOCKED
precondition design, and the Task 1 acceptance grep's honestly-reported zero count.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `readFinalState`'s comparator bug: `allLines` held unparsed strings, not
objects**
- **Found during:** Task 2, first live run comparing web-api and mcp legs
- **Issue:** `verify-cross-adapter-phase.mjs` pushed `formatScenarioLine`'s STRING output
  directly into `allLines`, then passed that array of strings to `compareLegs`, which expects
  parsed objects with `.scenario`/`.leg` fields. Every comparison silently read `undefined` for
  every field, producing a spurious "scenario undefined missing from leg(s): mcp,web-api"
  violation on every run regardless of actual leg agreement.
- **Fix:** Changed to `allLines.push(...parseScenarioLines(lines.join('\n')))`, so the array
  always holds parsed comparator objects.
- **Files modified:** `tooling/verify-cross-adapter-phase.mjs`
- **Verification:** Subsequent live runs correctly reported `comparison_ok=true` once the
  underlying scenario data genuinely agreed.
- **Committed in:** `305d887` (caught and fixed before any commit)

**2. [Rule 1 - Bug] Activity feed ordering: `.at(-1)` read the OLDEST fact, not the newest**
- **Found during:** Task 2, first live run -- `complete_task` and `reopen_task` scenarios both
  reported `activity_fact=task_captured`, which is wrong (should be `task_completed`/
  `task_reopened`).
- **Issue:** `GET /api/v1/tasks/:id/activity` returns items NEWEST FIRST (confirmed by a direct
  probe against a live server: after capture+complete, index 0 was `task_completed`, index 1 was
  `task_captured`). `lastActivityType` used `facts.at(-1)`, reading the OLDEST fact.
- **Fix:** Renamed to `mostRecentActivityType`, reads `facts[0]`, with a code comment recording
  the measured ordering.
- **Files modified:** `tooling/cross-adapter/legs.mjs`
- **Verification:** Live run then correctly reported `activity_fact=task_captured` /
  `task_completed` / `task_reopened` / `task_completed` (the fourth scenario's last successful
  action) for each of the four scenarios, matching between `web-api` and `mcp`.
- **Committed in:** `305d887` (caught and fixed before any commit)

**3. [Rule 1 - Bug] `update_stale_expected_revision`'s original design (edit_task, bad
expected_revision) never produced a conflict**
- **Found during:** Task 2, live runs -- both `web-api` (edit_task with a mismatched
  `expected_revision` but correct `base_values`) and an earlier `mcp` attempt (`complete_task`
  with `expected_revision=999`) were ACCEPTED, not refused.
- **Issue:** `apps/server/lib/keepling/domain/task.ex` showed `edit_task`'s conflict detection
  (`merge_fields`) is a `base_values` three-way merge that never consults `expected_revision` at
  all; and `lifecycle_transition/4`'s check is `lifecycle_revision > expected_revision` (a
  staleness comparison), not equality -- so an inflated `expected_revision=999` on a first-ever
  lifecycle command trivially passes (0 or 1 is never `>` 999).
- **Fix:** The scenario now performs two lifecycle commands on the same task:
  `complete(expected_revision=1)` (accepted, advances `lifecycle_revision` to 2), then
  `reopen(expected_revision=1)` (now genuinely stale, `2 > 1`, refused as
  `task_lifecycle_conflict`). This construction is uniform across all four shared command verbs
  and was verified live to produce identical refusals on both `web-api` and `mcp`.
- **Files modified:** `tooling/cross-adapter/legs.mjs`
- **Verification:** Live runs on both legs report `result_code=refused:task_lifecycle_conflict`,
  `conflict_shape=task_lifecycle_conflict`, matching exactly.
- **Committed in:** `305d887` (caught and fixed before any commit; three iterations were needed
  to find a construction that produces a genuine, uniform refusal)

**4. [Rule 3 - Blocking] `web-api` leg's mutation requests were refused with 403 until CSRF and
Origin were added**
- **Found during:** Task 2, first live run of the `web-api` leg
- **Issue:** `KeeplingWeb.Auth.authenticate_client`'s browser path requires a matching `Origin`
  header (`require_trusted_origin`) AND a session-bound CSRF token (`protect_from_forgery`) for
  every mutation -- neither of which the initial `postCommand` implementation sent, producing a
  uniform 403 on every scenario.
- **Fix:** Added `fetchCsrfToken` (reads `GET /api/v1/session`'s `csrf_token`, the same endpoint
  the real web client uses) and an `x-csrf-token` header alongside the already-present `Origin`
  header on every mutation POST.
- **Files modified:** `tooling/cross-adapter/legs.mjs`
- **Verification:** Live `web-api` leg run then reported `PASS` on all four scenarios.
- **Committed in:** `305d887` (caught and fixed before any commit)

**5. [Rule 3 - Blocking] `bootDisposableServer` leaked a `postgres` process across failed runs**
- **Found during:** Task 2, iterative testing -- a second invocation failed with `database
  "keepling_cross_adapter" already exists` because an earlier failed run's `postgres` process
  (spawned before `bootDisposableServer`'s own `try/finally` scope begins) was never terminated.
- **Issue:** This is a latent gap in 05-11's `tooling/mcp-client/client.mjs` (out of this plan's
  declared `files_modified`), not something this plan introduces -- `bootDisposableServer`'s
  cleanup only covers the `login()` call onward, not the earlier `initdb`/`postgres`/`createdb`/
  `migrate` steps.
- **Fix:** Worked around locally during testing (`lsof -ti:PORT | xargs kill -9` between runs);
  did NOT modify `client.mjs`, which is out of this plan's declared scope and shared by every
  other lane in this phase.
- **Files modified:** none (workaround only, no production code change)
- **Verification:** N/A -- documented here and in Broken-Windows Ledger below for a future plan
  with `client.mjs` in its declared scope.
- **Committed in:** N/A (no code change)

---

**Total deviations:** 5 (4 bugs caught and fixed before any commit; 1 documented, un-fixed
latent gap in a dependency out of this plan's declared scope). **Impact on plan:** All four
fixes were necessary for the `web-api`/`mcp` legs to produce genuine, comparable evidence rather
than a spuriously-passing or spuriously-failing comparison. No scope creep -- every fix stayed
within `tooling/cross-adapter/legs.mjs` and `tooling/verify-cross-adapter-phase.mjs`, the files
this plan already owns.

## Known Stubs

- **`electron` and `iphone` legs have no live driver wired**, disclosed at the top of
  `tooling/cross-adapter/legs.mjs`, in `docs/testing/cross-adapter-testing.md`, and in
  `.planning/WINDOWS.md` #69. Both legs' PRECONDITION CHECKS are real and live (packaged-build
  existence; installed-app existence on a booted simulator) and correctly report `BLOCKED` --
  the gap is specifically the live scenario-driving code against each artifact, which is the
  next increment for a future plan.
- **The `preview_and_commit_multi_target`/`commit_stale_preview` scenarios from
  `tooling/mcp-client/scenarios.mjs`'s full 9-scenario set are not part of this lane's shared
  set.** D-17's preview/commit primitive has no non-MCP wire equivalent in this phase (no HTTP
  endpoint, no Electron IPC command, no iPhone app action) -- see `key-decisions` above.
  MCP-05's bulk/destructive guarantee remains proven single-adapter by 05-11's
  `adversarial`/`simulated-client` lanes.

## Broken-Windows Ledger

Recorded via `gsd_run windows append` (entry #69, `unrun-verify`): the cross-adapter lane's
`electron` and `iphone` legs are BLOCKED -- no packaged Electron build in this worktree, and no
live UI driver wired against the installed simulator app. web-api and mcp legs pass identically.
SRV-02 stays unchecked pending both legs.

Additionally, not filed as a separate WINDOWS.md row (out of this plan's declared file scope,
`client.mjs` is a 05-11 artifact): `tooling/mcp-client/client.mjs`'s `bootDisposableServer`
leaks its spawned `postgres`/`phx.server` processes on any failure BEFORE the `login()` call
(the `initdb`/`createdb`/`migrate` steps are outside its `try/finally` scope). Worked around
locally during this plan's testing; a future plan touching `client.mjs` should widen the
`try/finally` to cover the full bootstrap sequence.

## Issues Encountered

- `gsd-tools.cjs`/`gsd_run` WAS available in this worktree (unlike 05-08/05-10/05-11's
  documented gap for the same reason) -- `.planning/WINDOWS.md` append and this SUMMARY's
  frontmatter tooling worked normally.
- This worktree had no `apps/server/deps`/`_build` installed at spawn time (matching every prior
  plan in this phase's own finding). `mix deps.get` was run as a standard, non-destructive
  fresh-worktree setup step.
- Three iterations were needed to construct a stale-revision scenario that genuinely refuses on
  every adapter (see Deviations #3) -- the domain's actual conflict semantics (a staleness
  comparison for lifecycle commands, a base_values merge with no revision check at all for
  edit/clarify commands) were more nuanced than the plan's own `tooling/mcp-client/scenarios.mjs`
  precedent (which used `update_task`'s MCP-specific pre-dispatch revision check, unavailable on
  the HTTP `edit_task` path) suggested.

## User Setup Required

**To exercise the electron and iphone legs' currently-BLOCKED paths, a human or a later plan
must:**
1. Run `pnpm package:desktop` to produce a packaged build at `apps/desktop/out/`, then wire a
   live IPC driver against it (following `tooling/verify-real-stack-desktop.mjs`'s discipline).
2. Wire a live UI/recording-proxy driver for the `iphone` leg against the already-installed
   simulator app (following `tooling/verify-real-stack-ios.mjs`'s pattern, or the Phase 4
   physical-device tailnet setup in `docs/testing/ios-testing.md` for the device variant).

Neither step is automatable from this session -- packaging is a multi-minute build step, and
writing a correct, tested live driver against either platform's real UI/IPC surface is
substantial new code this plan's scope did not include (see Known Stubs).

## Next Phase Readiness

- SRV-02 is the last open requirement of Phase 5 and of the milestone (per this plan's own
  objective). It remains open, honestly: 2 of 4 adapters (web-api, mcp) are proven identical by
  a real, live, self-tested cross-adapter lane; 2 (electron, iphone) are disclosed BLOCKED on a
  live driver, not a design gap.
- The evidence format (`scenario-report.mjs`), the shared scenario driver
  (`runSharedScenarioSet` in `legs.mjs`), and the orchestrator's server-bootstrap/digest/run-id
  contract are all reusable, tested extension points for whichever future plan wires the
  electron and iphone drivers -- no module boundary this plan introduced needs to change to add
  them.
- `tooling/verify-mcp-phase.mjs`'s full six-lane, six-requirement gate shows zero regression from
  05-10/05-11's own evidence: `deterministic=183`, `protocol=2`, `simulated-client=9`,
  `adversarial=6` all still pass; `representative-model` is still honestly `BLOCKED` for the same
  isolated-worktree credential reason 05-11 documented, unrelated to this plan's changes.

---
*Phase: KPL-05-safe-agent-access*
*Completed: 2026-09-11*

## Self-Check: PASSED

- `tooling/verify-cross-adapter-phase.mjs` -- FOUND on disk
- `tooling/cross-adapter/scenario-report.mjs` -- FOUND on disk
- `tooling/cross-adapter/legs.mjs` -- FOUND on disk
- `tooling/mcp-lanes/cross-adapter.mjs` -- FOUND on disk
- `docs/testing/cross-adapter-testing.md` -- FOUND on disk
- Commits `0290a07`, `305d887`, `0788ca0` all found in `git log --oneline --all`
- `node --test tooling/cross-adapter/scenario-report.mjs`: 8/8 passing
- `node tooling/verify-cross-adapter-phase.mjs --dry-run`: lists 4 legs, run_id, exits 0
- `node tooling/verify-cross-adapter-phase.mjs`: legs_ran=2 legs_blocked=2 comparison_ok=true,
  exits 1 solely because of the two disclosed BLOCKED legs
- `node tooling/verify-mcp-phase.mjs --lane cross-adapter`: status=BLOCKED (not FAIL)
- `node tooling/verify-mcp-phase.mjs --requirements`: passes, all six requirement ids mapped
  (SRV-02 now includes cross-adapter)
- Full 6-lane `verify-mcp-phase.mjs` run: deterministic=183, protocol=2, simulated-client=9,
  adversarial=6, cross-adapter=BLOCKED, representative-model=BLOCKED -- no regression from 05-11
- `grep -c '^- \[x\] \*\*SRV-02\*\*' .planning/REQUIREMENTS.md` reports 0 -- box correctly stays
  unchecked
- No stray `postgres`/`beam.smp` processes or open listeners on this lane's ports after the
  final run (checked via `lsof`)
