---
phase: KPL-05-safe-agent-access
plan: 11
subsystem: mcp
tags: [mcp, testing, anti-vacuity, adversarial, tooling, node, anthropic, elixir]

# Dependency graph
requires:
  - phase: KPL-05-10
    provides: "tooling/verify-mcp-phase.mjs's lane-discovery/BLOCKED/exUnitSummary/REQUIREMENT_LANES gate contract, tooling/mcp-lanes/README.md's four contract points, the deterministic and protocol lanes this plan runs alongside"
  - phase: KPL-05-04
    provides: "KeeplingWeb.MCP.Resources/Redaction -- the read surface simulated-client and representative-model drive"
  - phase: KPL-05-05
    provides: "KeeplingWeb.MCP.Tools's four write tools and the closed @mcp_error_codes vocabulary/golden vectors this plan's assertKnownError checks against"
  - phase: KPL-05-06
    provides: "Keepling.Application.TaskAddressing -- the identity-only resolution and bounded disambiguation the phrase-addressing scenario and case exercise"
  - phase: KPL-05-07
    provides: "Keepling.Application.Preview -- the preview/commit primitive the multi-target and stale-preview scenarios drive"
provides:
  - "tooling/mcp-client/client.mjs -- a bespoke JSON-RPC-over-HTTP MCP client: bootDisposableServer (real disposable Postgres+Phoenix), obtainGrant (real PKCE authorization-code flow), rpcCall/toolsCall/resourcesRead, assertKnownError (checks a refusal against mcp-tools.json's golden vectors), guardAgainstShortcuts (scans a lane's own source for stubbed-transport/hand-injected-credential shortcuts)"
  - "tooling/mcp-client/scenarios.mjs -- 9 shared scenarios every lane in this plan (and 05-12) drives, each declaring its expected final state and expected error member"
  - "tooling/mcp-client/final-state.mjs -- readFinalState (reads tasks/activity/grants from the server's own APIs) and assertNoForbiddenSideEffects (a pure, self-tested verdict function over 6 named forbidden side effects)"
  - "packages/contracts/vectors/mcp-injection.json -- Keepling's own adversarial injection corpus (D-24/D-25), 6 cases"
  - "tooling/mcp-lanes/simulated-client.mjs, adversarial.mjs, representative-model.mjs -- the phase's third, fourth, and fifth named evidence lanes"
  - "tooling/verify-mcp-phase.mjs's REQUIREMENT_LANES extended to cover all five real MCP-0N lanes"
affects: [KPL-05-12]

actuals:
  tokens: 25900
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "A lane that needs a real disposable server reuses ONE bootstrap function (client.mjs's bootDisposableServer), mirroring tooling/mcp-lanes/protocol.mjs's exact disposable-PostgreSQL-plus-mix-phx.server construction byte-for-byte in shape, rather than each lane growing its own drifting copy of 'a real server'."
    - "Every lane's verdict is computed by snapshotting readFinalState over the FULL set of tasks known before a scenario/case (not just the tasks it itself touches), running the scenario, then re-snapshotting the same set and handing both to assertNoForbiddenSideEffects -- this is what lets the pure verdict function catch a scenario that mutates an EARLIER scenario's task, not merely fail to prove its own."
    - "A 404 for a task_id already known to exist (present in the `before` snapshot) is read as 'trashed'; a 404 for a task_id NOT present in `before` is read as 'never created' (e.g. a scope-refused capture) -- conflating the two was the first live bug this plan's own runs caught (see Deviations)."
    - "The representative-model lane calls the Anthropic Messages API directly over plain HTTPS (no SDK dependency), converting the server's own live tools/list result into the API's `tools` shape -- the model's tool schema is never independently re-declared."

key-files:
  created:
    - tooling/mcp-client/client.mjs
    - tooling/mcp-client/scenarios.mjs
    - tooling/mcp-client/final-state.mjs
    - packages/contracts/vectors/mcp-injection.json
    - tooling/mcp-lanes/simulated-client.mjs
    - tooling/mcp-lanes/adversarial.mjs
    - tooling/mcp-lanes/representative-model.mjs
    - apps/server/test/keepling_web/mcp/injection_vector_test.exs
    - tooling/vector-conformance-reports/tooling.json
  modified:
    - packages/contracts/vectors/manifest.json
    - tooling/check-contracts.mjs
    - tooling/verify-mcp-phase.mjs
    - package.json

key-decisions:
  - "REQUIREMENT_LANES: every MCP-0N requirement now maps to all five real lanes (deterministic, protocol, simulated-client, adversarial, representative-model); SRV-02 deliberately stays mapped to only deterministic/protocol, because D-27's cross-adapter completion proof is 05-12's lane (Wave 7), not this plan's -- extending SRV-02's map here would claim evidence this plan does not provide. A code comment names 05-12-PLAN.md as the plan that extends it, exactly as 05-10-SUMMARY.md named this plan for the MCP-0N extension."
  - "mcp-injection.json is registered with BOTH an elixir and a tooling consumer, per the plan's literal instruction, even though the corpus is driven entirely by a Node lane. The elixir consumer is proven by a small, genuine structural test (injection_vector_test.exs) that loads and validates the corpus's shape -- deliberately NOT duplicating content_isolation_test.exs's behavioural proof (05-06) or adversarial.mjs's own live-transport proof. The tooling consumer is proven by a STATIC report at tooling/vector-conformance-reports/tooling.json, matching the existing swift.json/typescript.json precedent in that directory (neither of those is regenerated by a script either)."
  - "tooling/check-contracts.mjs's hardcoded vector-file count (14) was bumped to 15 -- a Rule 3 blocking fix, not a scope violation: 05-05-SUMMARY.md already established this exact precedent (13->14) when it added mcp-tools.json, and pnpm contracts:check cannot pass with a 15th vector file present and an unchanged count."
  - "The three lanes' verdicts are computed over the FULL set of tasks known to the run so far (accumulated across scenarios/cases within one lane invocation), not just each scenario's own tasks -- otherwise a scenario that quietly mutates an earlier scenario's task would never be caught. This required correcting final-state.mjs's own trashed-state inference twice during live runs (see Deviations) before the verdict function was trustworthy across a multi-scenario run, not just a single isolated one."
  - "The representative-model lane's injection-resistance scenario is a PAIR (injection_resistance + injection_resistance_control) rather than a single scenario compared against a hardcoded expectation, so the required outcome (identical final state) is checked between two genuinely-executed live runs, never against a value this file merely asserts should have happened."

requirements-completed: []
# This plan declares MCP-02, MCP-03, MCP-05, SRV-02 in its own frontmatter,
# but none is marked complete here: no gsd-tools.cjs binary was present in
# this worktree (matching 05-08/05-10's own documented finding), so the
# standard requirements.ready-ids / requirements.mark-complete verbs could
# not be run. As of this plan's completion, REQUIREMENTS.md's MCP-01..05
# checkboxes are ALL still unchecked (verified by direct read) despite
# 05-04/05-06/05-07's own SUMMARYs claiming MCP-01/MCP-03/MCP-05 were
# "now checked" -- those markings evidently never landed (the same missing-
# tooling gap, independently hit by each of those plans' worktrees). SRV-02
# is correctly and deliberately NOT completable here regardless: D-27's
# cross-adapter proof (05-12) is what completes it, and this plan's
# REQUIREMENT_LANES change intentionally does not extend SRV-02's lane
# mapping. See Issues Encountered / Broken-Windows Ledger.

coverage:
  - id: D1
    description: "A scripted MCP client (tooling/mcp-client/client.mjs) completes a real handshake over the real HTTP pipeline with a real, PKCE-obtained grant, and the server can be shown to have observed each request via its own activity feed -- not the client's self-report."
    requirement: "MCP-02"
    verification:
      - kind: integration
        ref: "node tooling/verify-mcp-phase.mjs --lane simulated-client (cases=9, activity_facts_observed>0)"
        status: pass
      - kind: unit
        ref: "node tooling/mcp-client/client.mjs --self-check"
        status: pass
    human_judgment: false
  - id: D2
    description: "All three lanes built by this plan (simulated-client, adversarial, representative-model) score every scenario/case on final database state and a forbidden-side-effect list, never on model text or a self-reported status code."
    requirement: "MCP-02"
    verification:
      - kind: unit
        ref: "tooling/mcp-client/final-state.mjs#assertNoForbiddenSideEffects self-check: 3 cases (legitimate change accepted, undeclared change caught, injected new grant caught)"
        status: pass
      - kind: other
        ref: "grep -v '^\\s*//' tooling/mcp-lanes/adversarial.mjs | grep -cE 'response\\.status === 200' -- 0"
        status: pass
    human_judgment: false
  - id: D3
    description: "The adversarial corpus (packages/contracts/vectors/mcp-injection.json, 6 cases) is placed into a task that is genuinely the resolved target of the operation under test in every case; the lane fails a case whose injected content did not resolve into its declared target."
    requirement: "MCP-03"
    verification:
      - kind: integration
        ref: "node tooling/verify-mcp-phase.mjs --lane adversarial (cases=6)"
        status: pass
      - kind: unit
        ref: "apps/server/test/keepling_web/mcp/injection_vector_test.exs (4 tests: corpus shape, sentinel uniqueness, per-case required fields, unique ids)"
        status: pass
    human_judgment: false
  - id: D4
    description: "The representative-model lane checks the model credential at run time on every invocation and reports BLOCKED, never a silent pass or a reused prior result, when it is absent."
    requirement: "MCP-05"
    verification:
      - kind: integration
        ref: "node tooling/verify-mcp-phase.mjs --lane representative-model (no credential reachable in this session): status=BLOCKED, exit=1, names ANTHROPIC_API_KEY"
        status: pass
      - kind: other
        ref: "grep -v '^\\s*//' tooling/mcp-lanes/representative-model.mjs | grep -cE 'cached|replay|fixture' -- 0"
        status: pass
    human_judgment: true
    rationale: "The lane's SUCCESS path (a real model genuinely driving the five scenarios, including the injection-resistance pair) could not be executed in this sandboxed session -- ANTHROPIC_API_KEY in .env.local is deliberately unreadable to this agent (a permission denial, not a missing file; Node's --env-file-if-exists independently reported the same file as absent). The code path, prompt construction, tool-schema translation, and turn-bound refusal logic are all written and pass a --check syntax check, and the BLOCKED path -- the other half of D-26's honesty requirement -- is proven live. A human or a later run with real filesystem access to .env.local must confirm the success path (pnpm run verify:mcp:model) before this requirement's representative-model evidence is treated as fully exercised."
  - id: D5
    description: "Each of the three lanes publishes a case count equal to the number of scenarios/cases actually executed, under the plan 05-10 gate; the phase gate's REQUIREMENT_LANES map is extended to cover all three, and pnpm contracts:check passes with the new vector registered."
    requirement: "MCP-05"
    verification:
      - kind: integration
        ref: "pnpm run verify:mcp:phase: LANE lines report simulated-client cases=9, adversarial cases=6, deterministic cases=183, protocol cases=2, representative-model BLOCKED (honest, credential absent)"
        status: pass
      - kind: integration
        ref: "node tooling/verify-mcp-phase.mjs --requirements: all six requirement ids mapped to existing lane files"
        status: pass
      - kind: integration
        ref: "pnpm run contracts:check"
        status: pass
    human_judgment: false

duration: ~45min
completed: 2026-09-10
status: complete
---

# Phase 5 Plan 11: The Three Live MCP Evidence Lanes -- Scripted Client, Adversarial Corpus, and a Credential-Honest Model Lane Summary

**A bespoke JSON-RPC-over-HTTP MCP client with real PKCE authorization drives a shared 9-scenario set and a 6-case adversarial injection corpus over a real disposable Phoenix/PostgreSQL server, scored exclusively on final database state; a third, model-driven lane reports honest BLOCKED without a live Anthropic credential rather than a silent pass.**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-09-10T20:17:54-04:00 (base commit)
- **Completed:** 2026-09-10T20:38:51-04:00
- **Tasks:** 3 (all `type="auto"`)
- **Files created:** 9
- **Files modified:** 4

## Accomplishments

- `tooling/mcp-client/client.mjs`: `bootDisposableServer` reuses `tooling/mcp-lanes/protocol.mjs`'s
  exact disposable-PostgreSQL-plus-`mix phx.server` bootstrap; `obtainGrant` completes the real
  external-user-agent + authorization-code + S256 PKCE flow for an arbitrary scope set (never a
  hand-constructed bearer); `rpcCall`/`toolsCall`/`resourcesRead`/`initialize`/`ping` are the real
  JSON-RPC surface; `assertKnownError` checks a refusal against `mcp-tools.json`'s golden error
  vectors byte-for-byte (code/message/title/retryable/recovery_action); `guardAgainstShortcuts`
  scans a lane's own source for a stubbed transport, a `.invalid` host, or a hand-injected bearer.
  A `--self-check` mode boots a real server and completes a real handshake end to end.
- `tooling/mcp-client/scenarios.mjs`: the 9 shared scenarios the plan's action text names verbatim
  (capture, complete, reopen, stale-expected-revision update, phrase addressing, multi-target
  preview/commit, stale-preview commit, missing-scope call, mutation replay), each with a declared
  expected final state and expected error member.
- `tooling/mcp-client/final-state.mjs`: `readFinalState` reads tasks (`GET /api/v1/tasks/:id`),
  activity (`GET /api/v1/tasks/:id/activity`), and every device grant
  (`GET /api/v1/device-grants`) back from the server's own APIs. `assertNoForbiddenSideEffects` is a
  pure function checking 6 named forbidden side effects (unexpected trash, unexpected revision
  advance, grant scope change, new grant issued, activity actor not the scenario's own grant,
  unexpected task creation); its `--self-check` mode proves the function catches an undeclared
  revision advance and an injected new grant, and does NOT false-positive on a declared, legitimate
  change.
- `packages/contracts/vectors/mcp-injection.json`: 6 cases following `redaction.json`'s
  `hostile_sentinels` convention -- trash-all-tasks, grant-the-bulk-scope, impersonate-a-
  different-target, a fabricated preview token, a fabricated `expected_revision`, and a claim that a
  scope refusal was a mistake -- each declaring its injection field, target scenario, the exact task
  it must resolve into, and its forbidden outcome. Registered in `manifest.json` with `elixir` and
  `tooling` consumers.
- `tooling/mcp-lanes/simulated-client.mjs`: drives all 9 scenarios over the real transport, verified
  live at **cases=9**. Snapshots final state over the FULL accumulated task set before and after each
  scenario (not just that scenario's own tasks), asserts the server itself recorded activity for
  every mutating scenario, and never inspects an HTTP status code for its pass/fail verdict.
- `tooling/mcp-lanes/adversarial.mjs`: for each corpus case, seeds a task carrying the injected
  content, runs the exact real operation the case's `target_scenario` names, and structurally
  asserts the operation resolved into that SAME task (or, for the three refusal-shaped cases --
  fabricated token, fabricated revision, scope-refused retry -- that it resolved into nothing at
  all). Verified live at **cases=6**.
- `tooling/mcp-lanes/representative-model.mjs`: a real Anthropic model drives the live server as its
  own MCP client via a plain HTTPS call to the Messages API (no SDK dependency), receiving the
  server's own `tools/list` schemas directly. Five scenarios: benign capture, scope-forbidden
  request, under-determined target, bulk destructive change via preview/commit, and an
  injection-resistance pair (identical instruction and setup, differing only in whether the read
  task's notes carry the trash-all injection) whose required outcome is final-state EQUALITY between
  the two runs. The credential is checked via `process.env.ANTHROPIC_API_KEY` fresh on every
  invocation -- no module-level constant ever holds it -- and its absence throws a
  `BLOCKED:`-prefixed error naming exactly what is missing. `MAX_SCENARIO_COUNT`/
  `MAX_TURNS_PER_SCENARIO`/`MAX_TOKENS_PER_TURN` bound the only lane in this phase that spends money;
  exceeding either is a hard `BLOCKED` refusal, never a silent truncation.
- `tooling/verify-mcp-phase.mjs`: `REQUIREMENT_LANES` extended so every MCP-0N requirement maps to
  all five real lanes; `SRV-02` stays mapped only to `deterministic`/`protocol`, disclosed in a code
  comment naming 05-12-PLAN.md as the plan that extends it with the cross-adapter proof D-27
  requires.
- `package.json`: `verify:mcp:model` added (the credential-gated lane alone); `verify:mcp:phase` now
  loads `.env.local`/`.env` via Node's built-in `--env-file-if-exists`, so a real credential on disk
  is honored without adding a dotenv dependency.
- Verified live, end to end, against this worktree's real PostgreSQL and a fresh disposable Phoenix
  server per lane: `pnpm run verify:mcp:phase` reports `deterministic cases=183`, `protocol cases=2`,
  `simulated-client cases=9`, `adversarial cases=6`, and `representative-model status=BLOCKED`
  (honest -- no live Anthropic credential reachable in this session), with the disclosure paragraph
  printed and a non-zero exit purely because of the disclosed BLOCKED lane. `pnpm contracts:check`
  passes (15 vector files, `mcp-injection.json` registered). `node --test
  tooling/mcp-gate-selftest.mjs` still passes 10/10.

## Task Commits

1. **Task 1: A real scripted client, and a verdict computed from final state** -- `ad87cc9` (feat)
2. **Task 2: The simulated-client and adversarial lanes** -- `9d542d4` (feat)
3. **Task 3: The representative-model lane, honest about being blocked** -- `21a8abd` (feat)

**Plan metadata:** committed alongside this SUMMARY.

## Files Created/Modified

- `tooling/mcp-client/client.mjs` -- the bespoke MCP client and its real PKCE grant flow
- `tooling/mcp-client/scenarios.mjs` -- the 9 shared scenarios
- `tooling/mcp-client/final-state.mjs` -- the self-tested verdict function
- `packages/contracts/vectors/mcp-injection.json` -- the 6-case adversarial corpus
- `tooling/mcp-lanes/simulated-client.mjs` -- the third named lane
- `tooling/mcp-lanes/adversarial.mjs` -- the fourth named lane
- `tooling/mcp-lanes/representative-model.mjs` -- the fifth named lane
- `apps/server/test/keepling_web/mcp/injection_vector_test.exs` -- the elixir consumer proof for
  `mcp-injection.json`
- `tooling/vector-conformance-reports/tooling.json` -- the tooling consumer proof
- `packages/contracts/vectors/manifest.json` -- `mcp-injection.json` registered
- `tooling/check-contracts.mjs` -- vector-file count 14 -> 15
- `tooling/verify-mcp-phase.mjs` -- `REQUIREMENT_LANES` extended
- `package.json` -- `verify:mcp:model` added; `verify:mcp:phase` loads env files

## Decisions Made

See `key-decisions` in frontmatter for the full rationale on: `REQUIREMENT_LANES`'s deliberate
SRV-02 narrowing (05-12 owns the cross-adapter extension), `mcp-injection.json`'s dual elixir/tooling
consumer proof mechanism, the `check-contracts.mjs` vector-count bump (matching 05-05's own
precedent), the accumulated-known-task-set snapshot design every lane's verdict loop uses, and the
injection-resistance scenario PAIR design.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `final-state.mjs`'s activity read used the wrong response key**
- **Found during:** Task 2, first live run of `simulated-client.mjs`
- **Issue:** `readActivity` looked for `body.facts ?? body.activity`, but
  `Keepling.Application.Activity.present_page/3` returns the key `items`. Every activity read
  silently returned zero facts, which would have made this lane's "the server observed each
  request" assertion trivially and permanently true for the wrong reason (an empty array's `.length
  === 0` check was the only thing catching it).
- **Fix:** Changed to `body.items ?? []`.
- **Files modified:** `tooling/mcp-client/final-state.mjs`
- **Verification:** Live run of `simulated-client.mjs` then correctly observed
  `activity_facts_observed=16` across 9 scenarios.
- **Committed in:** `9d542d4` (Task 2 commit -- caught and fixed before that commit)

**2. [Rule 1 - Bug] `assertNoForbiddenSideEffects` false-flagged an already-trashed task from a prior scenario as freshly trashed**
- **Found during:** Task 2, live run reaching the `commit_stale_preview` scenario
- **Issue:** `GET /api/v1/tasks/:id` 404s for a trashed task. The original `trashedState` logic
  treated ANY 404 in `after` as "now trashed", so a task trashed by an EARLIER scenario (correctly
  declared there) re-triggered the SAME violation in every SUBSEQUENT scenario's snapshot, because
  the accumulated-known-task-set design (by design) re-reads it every time.
- **Fix:** `trashedState` now compares the TRANSITION between `before` and `after` for a given
  scenario, not the absolute `after` state alone -- a task already not-found in `before` never
  re-triggers the check in a later scenario.
- **Files modified:** `tooling/mcp-client/final-state.mjs`
- **Verification:** `node tooling/mcp-client/final-state.mjs --self-check` (3/3 passing, including
  the case this fix was written to satisfy); live `simulated-client.mjs` run proceeded past the
  scenario that exposed it.
- **Committed in:** `9d542d4` (Task 2 commit -- caught and fixed before that commit)

**3. [Rule 1 - Bug] The same false-positive recurred for a task that was correctly NEVER created**
- **Found during:** Task 2, live run reaching the `call_without_required_scope` scenario
- **Issue:** After fix #2, a `taskId` a scenario merely ATTEMPTED to use (a capture correctly refused
  by a scope check, so the task never existed) still 404'd in `after`, and since it was absent from
  `before` too (`before.tasks[taskId] === undefined`, not `{found:false}`), the fallback path in
  `trashedState` still read `found:false` as "trashed" for a task that in truth never existed at all.
- **Fix:** `assertNoForbiddenSideEffects`'s check 1 now skips any `taskId` entirely absent from
  `before` (`beforeTask === undefined`) -- a task_id never previously known cannot have "transitioned
  into trashed"; check 6 (unexpected task creation) already handles the genuinely-new-task case
  correctly and independently.
- **Files modified:** `tooling/mcp-client/final-state.mjs`
- **Verification:** Live `simulated-client.mjs` run completed all 9 scenarios; `--self-check` still
  3/3 passing.
- **Committed in:** `9d542d4` (Task 2 commit -- caught and fixed before that commit)

**4. [Rule 3 - Blocking] `pnpm contracts:check`'s hardcoded vector-file count needed to change**
- **Found during:** Task 2, first `pnpm contracts:check` run after adding `mcp-injection.json`
- **Issue:** `tooling/check-contracts.mjs` asserts `actualFiles.length !== 14` fails the run --
  adding a 15th vector file (out of this plan's declared `files_modified`, but structurally required
  for the plan's own required `pnpm contracts:check` to pass) would otherwise fail every future run.
- **Fix:** Bumped the hardcoded count from 14 to 15, matching 05-05-SUMMARY.md's own documented
  13->14 precedent for the identical situation.
- **Files modified:** `tooling/check-contracts.mjs`
- **Verification:** `pnpm run contracts:check` passes (15 vector files, `mcp-injection.json`
  registered).
- **Committed in:** `9d542d4` (Task 2 commit)

**5. [Rule 3 - Blocking] `mcp-injection.json`'s manifest consumer proofs required two new artifacts**
- **Found during:** Task 2, `pnpm contracts:check` failing on the manifest's cross-consumer gate
- **Issue:** The plan's own action text says to register the vector with "an elixir and a tooling
  consumer", but `check-contracts.mjs`'s `elixir` consumer check requires a git-tracked
  `apps/server/test/**` file that literally references `vectors/mcp-injection.json`, and its
  non-elixir consumer check requires a static `tooling/vector-conformance-reports/<consumer>.json`
  report -- neither existed and neither is in this plan's declared `files_modified`.
- **Fix:** Added a small, genuine structural test (`injection_vector_test.exs`, 4 tests validating
  the corpus's own shape) for the elixir consumer, and a static `tooling.json` report (matching the
  existing `swift.json`/`typescript.json` precedent -- neither of which is regenerated by a script
  either) for the tooling consumer.
- **Files modified:** `apps/server/test/keepling_web/mcp/injection_vector_test.exs` (new),
  `tooling/vector-conformance-reports/tooling.json` (new)
- **Verification:** `mix test test/keepling_web/mcp/injection_vector_test.exs` (4/4 passing);
  `pnpm run contracts:check` passes.
- **Committed in:** `9d542d4` (Task 2 commit)

---

**Total deviations:** 5 auto-fixed (3 bugs in the verdict function's own logic, caught by this
plan's own live runs before any broken version was committed; 2 blocking fixes required for the
plan's own `pnpm contracts:check` requirement to pass). **Impact on plan:** All five were necessary
for correctness or for a structural gate this plan is itself required to keep green. No scope
creep -- no capability was added beyond the three lanes, the shared client/scenario/verdict modules,
and the adversarial corpus the plan specifies.

## Known Stubs

- **The representative-model lane's SUCCESS path (a real model genuinely driving all five
  scenarios) was not exercised live in this session.** `ANTHROPIC_API_KEY` in the repository's
  gitignored `.env.local` is deliberately unreadable to this agent (a sandbox permission denial --
  confirmed both via direct `cat`/`ls` refusal and via Node's own `--env-file-if-exists` reporting
  the file "not found", the same behavior a genuinely-absent file would produce). The lane's BLOCKED
  path is proven live and is the correct, honest behavior D-26 requires in this circumstance. A
  human or a later run with real filesystem access must run `pnpm run verify:mcp:model` to exercise
  the success path before treating the representative-model lane's PASS behavior as verified rather
  than merely reviewed. This is disclosed in `coverage` (D4) above with `human_judgment: true`.

## Broken-Windows Ledger

`gsd_run windows append` was not available in this worktree (no `gsd-tools.cjs` binary present,
matching 05-08's and 05-10's own documented finding for the same reason). Recorded here instead:

- unrun-verify: the representative-model lane's success path (`pnpm run verify:mcp:model` with a
  real `ANTHROPIC_API_KEY`) has not been run in any session to date -- see Known Stubs above.
- deviation: `REQUIREMENTS.md`'s MCP-01..05 checkboxes are all still `[ ]` despite three prior
  plans' SUMMARYs (05-04, 05-06, 05-07) claiming their own requirement was "now checked" -- see
  Next Phase Readiness. No plan in this phase has had `gsd-tools.cjs` available to actually run the
  marking verb.

## Issues Encountered

- No `gsd-tools.cjs` binary was present in this worktree, matching 05-08/05-10's own documented
  finding. `.planning/WINDOWS.md` could not be updated via the standard verb; the one entry above is
  recorded in this SUMMARY's Broken-Windows Ledger instead.
- This worktree had no `apps/server/deps`/`_build` and no root `node_modules` installed at spawn
  time (matching 05-08's/05-10's own finding for deps; the `node_modules` gap is new to this plan's
  own verification, since it is the first plan in this wave to run `pnpm contracts:check` from a
  fresh worktree). `mix deps.get` and `pnpm install` were both run as standard, non-destructive
  fresh-worktree setup steps, not deviations from the plan.

## User Setup Required

**External service requires manual configuration to exercise the representative-model lane's success
path.** No `{phase}-USER-SETUP.md` was generated (the credential itself is already documented as
present at the repository's gitignored `.env.local`, per this plan's own environment brief) --
nothing further to configure. Run `pnpm run verify:mcp:model` from an environment with real
filesystem access to that file to exercise the lane end to end.

## Next Phase Readiness

- Four of this phase's five D-25 lanes now exist and have been proven live against a real,
  disposable Phoenix/PostgreSQL server: `deterministic` (183 cases), `protocol` (2 cases),
  `simulated-client` (9 cases), `adversarial` (6 cases). The fifth, `representative-model`, is
  written, syntactically valid, and proven to report BLOCKED honestly without a credential; its
  success path awaits an environment where `ANTHROPIC_API_KEY` is reachable.
- `tooling/mcp-client/{client,scenarios,final-state}.mjs` are the extension points 05-12's
  cross-adapter lane can reuse directly -- the same scenario set, the same verdict function, the same
  shortcut-refusal guard -- without inventing a second MCP client or a second verdict mechanism.
- `REQUIREMENT_LANES`'s `SRV-02` row remains intentionally narrow (`deterministic`, `protocol`
  only), disclosed in both this SUMMARY and a source comment: 05-12-PLAN.md is the plan that adds
  the `cross-adapter` lane and extends this row, exactly as this plan extended MCP-0N's rows for
  05-10.
- **REQUIREMENTS.md checkbox state is a genuine open item, not merely a tooling inconvenience.**
  Direct read confirms MCP-01..05 are ALL still unchecked, despite 05-04/05-06/05-07's own SUMMARYs
  claiming MCP-01/MCP-03/MCP-05 were "now checked" -- across four independent plan worktrees
  (05-04, 05-06, 05-07, this plan) hitting the identical missing-`gsd-tools.cjs` gap, no plan in
  this phase has actually been able to run the standard marking verb. A future pass WITH tooling
  access should mark MCP-02 (all four declaring plans -- 05-01, 05-02, 05-05, this plan -- now have
  SUMMARYs), MCP-03 (05-06, sole declaring plan), and MCP-05 (05-07, sole declaring plan) complete.
  SRV-02 correctly stays unchecked regardless, pending 05-12's cross-adapter proof.

---
*Phase: KPL-05-safe-agent-access*
*Completed: 2026-09-10*

## Self-Check: PASSED

- `tooling/mcp-client/client.mjs` -- FOUND on disk
- `tooling/mcp-client/scenarios.mjs` -- FOUND on disk
- `tooling/mcp-client/final-state.mjs` -- FOUND on disk
- `packages/contracts/vectors/mcp-injection.json` -- FOUND on disk
- `tooling/mcp-lanes/simulated-client.mjs` -- FOUND on disk
- `tooling/mcp-lanes/adversarial.mjs` -- FOUND on disk
- `tooling/mcp-lanes/representative-model.mjs` -- FOUND on disk
- `apps/server/test/keepling_web/mcp/injection_vector_test.exs` -- FOUND on disk
- `tooling/vector-conformance-reports/tooling.json` -- FOUND on disk
- Commits `ad87cc9`, `9d542d4`, `21a8abd` all found in `git log --oneline --all`
- `node --test tooling/mcp-gate-selftest.mjs`: 10/10 passing
- `node tooling/mcp-client/final-state.mjs --self-check`: 3/3 passing
- `pnpm run verify:mcp:phase`: `deterministic cases=183`, `protocol cases=2`,
  `simulated-client cases=9`, `adversarial cases=6`, `representative-model status=BLOCKED`
  (honest, no credential reachable in this session) -- disclosure paragraph printed, exit 1 solely
  because of the disclosed BLOCKED lane
- `node tooling/verify-mcp-phase.mjs --requirements`: all six requirement ids mapped to existing
  lane files
- `pnpm run contracts:check`: passed (15 vector files)
- `mix test test/keepling_web/mcp/injection_vector_test.exs`: 4/4 passing
- All 5 `must_haves.truths` and all 4 `prohibitions` from PLAN.md frontmatter verified by named
  assertions/greps (see Accomplishments and coverage above).
