---
phase: KPL-05-safe-agent-access
plan: 08
subsystem: mcp
tags: [mcp, activity, undo, recovery, privacy, elixir, postgresql]

# Dependency graph
requires:
  - phase: KPL-05-01
    provides: The MCP agent context wired through KeeplingWeb.MCP.Dispatch/Tools (actor_type "agent", actor_label, actor_principal "authorized_grant", client_kind "mcp"), and the already-admitted actor/client_kind CHECK-constraint vocabulary this plan proves against.
provides:
  - "Agent actions attributed in the one existing activity history (type=agent, principal=authorized_grant, label truncated to the actor CHECK's 200-char bound at write time)"
  - "A storage-level, test-enforced privacy assertion (information_schema.columns allow-list) proving no reasoning/prompt/rationale/conversation column exists on the tables this phase writes to"
  - "Proof that Keepling.Application.Undo and its CommandStore compensation path already treat an agent-authored activity fact exactly as a human-authored one -- no actor-discriminating clause anywhere"
  - "A full agent undo round-trip proof: recovery_state available/not_available by command-type support, expiry on the same Undo.valid_for_seconds() bound, and an expired handle reporting expired rather than failing opaquely"
  - "docs/architecture/AGENT-RECOVERY.md -- the honest scope statement of the undo claim, including a source-verified correction of WINDOWS.md row 59"
affects: [KPL-05-09, KPL-05-10, KPL-05-12]

actuals:
  tokens: 7965
  tasks: 3
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Write-time label truncation as a defense-in-depth backstop over an already-bounded upstream input (activity_actor/1's agent clause), matching the project's closed-vocabulary-plus-CHECK-constraint discipline."
    - "information_schema.columns enumeration against an explicit allow-list as the mechanism that makes a storage-level privacy guarantee structural rather than convention -- a future migration adding a free-text column fails this test before it ships."

key-files:
  created:
    - apps/server/test/keepling/application/agent_history_test.exs
    - docs/architecture/AGENT-RECOVERY.md
  modified:
    - apps/server/lib/keepling/adapters/postgres/command_store.ex
    - apps/server/test/keepling/application/activity_test.exs
    - apps/server/test/keepling/application/undo_test.exs
    - packages/contracts/vectors/activity.json
    - packages/contracts/vectors/undo.json

key-decisions:
  - "Task 1's storage-level privacy checkpoint answered Option A exactly as CONTEXT.md's D-21 already locked it: no column can hold model reasoning/prompt/rationale/conversation content; enforced by a schema-level information_schema.columns enumeration test with an explicit allow-list, not a read-time redaction filter. No alternative was proposed; the checkpoint exists to put the confirmation on record before the one-way door (D-21) is walked through, matching the same-phase precedent set by 05-01's and 05-02's Task 1 checkpoints."
  - "No migration was needed for the actor/client_kind vocabulary -- confirmed by reading the CHECK constraint in 20260830000500_expand_task_activity.exs (already admits actor_type='agent'/actor_principal='authorized_grant' and client_kind='mcp') rather than assuming, and by git diff --stat over priv/repo/migrations returning empty."
  - "Undo required zero code changes to remove actor discrimination, because none existed: Keepling.Application.Undo.compensation/2 takes a command and an activity fact, never an actor, and CommandStore's issue_undo/5 and apply_undo_delivery/4 read only command-type and revision fields. The mechanism was already correct; this plan's job was to prove it, which agent_history_test.exs's round-trip test does."
  - "Corrected .planning/WINDOWS.md row 59 against current source rather than repeating its filed-time claim: apps/desktop/main/application/DesktopApplication.ts's undoLastLocalAction (per its own 'O-45: undo, made to RECONCILE' header) now retains the server-issued handle and enqueues a real outbound command through the same durable-outbox mechanism every other desktop command uses (closed by KPL-03-23, confirmed via git log -S on the exact enqueue call). The row's literal 'enqueues NO outbound command' claim is stale. This plan documents the finding in AGENT-RECOVERY.md but does not edit the ledger row itself -- out of this plan's files_modified scope, and the ledger's counts/format are tool-managed (gsd-tools windows fixed/waive), which was not available in this execution environment."
  - "The plan's literal four refusal causes for the zero-activity-fact test (\"insufficient scope, ambiguous match, stale revision, stale preview\") assumed capabilities (ambiguity resolution, preview/commit) that do not exist in the codebase yet -- they belong to sibling plans (MCP-03, MCP-05) not yet executed at this plan's Wave 2 position (depends_on: [05-01] only). Substituted two real, currently-reachable refusal causes in their place: invalid_command (a malformed MCP tool call, refused by the closed-key schema decoder) and task_not_found (a real command-level refusal against a nonexistent target), alongside the two literally-named causes that do exist today: insufficient_scope (MCP tool boundary) and stale revision (a genuine lifecycle_conflict via reopen_task after an intervening complete_task). All four are proven to write zero activity facts."

patterns-established:
  - "A storage-level privacy guarantee is proven by enumerating information_schema.columns against an explicit allow-list inside the application-level test suite, not by a read-time filter -- the same discipline this phase's D-21 threat mitigation (T-05-40) requires, reusable by any future phase making an equivalent no-such-column claim."

requirements-completed: []  # MCP-04 is declared by four plans in this phase (05-01, 05-08, 05-09, 05-10); 05-09/05-10 have not yet executed, so requirements.ready-ids would report 0/4 ready from this plan alone (no gsd-tools binary was available in this worktree to run the check, but the same reasoning 05-01's summary applied holds unchanged).

coverage:
  - id: D1
    description: "Every accepted agent write tool call produces exactly one activity fact, typed agent/authorized_grant/mcp, interleaved with human facts in one ordered stream, with an oversized grant label truncated at write time rather than rejected."
    requirement: "MCP-04"
    verification:
      - kind: integration
        ref: "test/keepling/application/agent_history_test.exs#an accepted agent write produces exactly one activity fact naming the grant"
        status: pass
      - kind: integration
        ref: "test/keepling/application/agent_history_test.exs#an oversized grant label is truncated at write time rather than raising"
        status: pass
      - kind: integration
        ref: "test/keepling/application/activity_test.exs#the activity feed interleaves agent and human facts in one ordered stream"
        status: pass
    human_judgment: false
  - id: D2
    description: "A refused agent tool call -- across four distinct, currently-reachable causes -- writes zero activity facts. No second, agent-only history surface exists anywhere in the system."
    requirement: "MCP-04"
    verification:
      - kind: integration
        ref: "test/keepling/application/agent_history_test.exs#refused agent calls write zero activity facts, across four named causes"
        status: pass
      - kind: other
        ref: "git grep -rn 'agent_activity|agent_audit' -- apps/server/lib (returns nothing)"
        status: pass
    human_judgment: false
  - id: D3
    description: "No column, struct field, or serialized blob in the tables this phase writes to (task_activities, undo_handles) can hold model reasoning, prompt text, tool-call rationale, or conversation content -- a storage-level guarantee, not a read-time filter."
    requirement: "MCP-04"
    verification:
      - kind: integration
        ref: "test/keepling/application/agent_history_test.exs#storage-level privacy: no reasoning/prompt/rationale/conversation column exists"
        status: pass
    human_judgment: false
  - id: D4
    description: "An agent action exposes the same GTD-07 undo handle a human action exposes: a supported command type is recorded available with a working handle, an unsupported one is recorded not_available, and undoing an agent action through the server reverses it -- field values proven at three points (before, after the action, after the undo) -- with the undo itself recorded as a correctly-attributed activity fact."
    requirement: "MCP-04"
    verification:
      - kind: integration
        ref: "test/keepling/application/agent_history_test.exs#an agent action of a supported command type is recorded available, and undoing it through the server reverses it"
        status: pass
      - kind: integration
        ref: "test/keepling/application/agent_history_test.exs#an agent action of an unsupported command type records not_available"
        status: pass
      - kind: integration
        ref: "test/keepling/application/agent_history_test.exs#the undo handle expires on the same bound as a human action, and an expired handle reports expired rather than failing opaquely"
        status: pass
    human_judgment: false
  - id: D5
    description: "The limits of the undo claim across adapters are written down rather than assumed, including a source-verified correction of a stale defect-ledger entry."
    requirement: "MCP-04"
    verification: []
    human_judgment: true
    rationale: "docs/architecture/AGENT-RECOVERY.md is a prose scope document, not something an automated test can grade for honesty or completeness. A human (or the phase's later cross-adapter proof, 05-12) should confirm the desktop-leg claim boundary this document draws is the right one before 05-12 builds on it."

duration: ~55min
completed: 2026-09-10
status: complete
---

# Phase 5 Plan 08: Agent Attribution, Undo, and Honest Recovery Scope Summary

**Agent tool calls now appear in the same activity history a human's do -- typed, attributed to the authorized grant, storage-level-proven free of any reasoning/prompt/rationale column -- and an agent action carries and honors the same server-issued undo handle a human action does, with the desktop-undo scope claim corrected against current source rather than a stale defect-ledger row.**

## Performance

- **Duration:** ~55 min
- **Started:** 2026-09-10T21:38:00Z (approx.)
- **Completed:** 2026-09-10T22:33:00Z (approx.)
- **Tasks:** 3 (1 checkpoint:decision, 2 auto/tdd)
- **Files modified:** 7 (2 created, 5 modified)

## Accomplishments

- `Keepling.Adapters.Postgres.CommandStore`'s `activity_actor/1` agent clause now truncates an
  oversized device-grant label to the actor CHECK constraint's 200-character bound at write time,
  a defense-in-depth backstop on top of the already-bounded grant-issuance input.
- `apps/server/test/keepling/application/agent_history_test.exs` (new, 468 lines): agent writes
  attribute correctly; an oversized label is truncated not rejected; four distinct refusal causes
  write zero activity facts; and an `information_schema.columns` enumeration against an explicit
  allow-list proves no reasoning/prompt/rationale/conversation column exists on `task_activities`
  or `undo_handles` (T-05-40, D-21) -- plus a full agent undo round-trip (recovery_state
  available/not_available by command-type support, expiry parity with `Undo.valid_for_seconds()`,
  and an expired handle reporting `expired` rather than failing opaquely).
- `apps/server/test/keepling/application/activity_test.exs` gained an interleaving test proving
  the existing activity feed returns agent and human facts in one ordered, correctly-attributed
  stream -- there is no second history to reconcile.
- `packages/contracts/vectors/activity.json` and `undo.json` each gained an agent case, asserted
  by their existing consumer tests.
- `docs/architecture/AGENT-RECOVERY.md` (new): states the server-side undo guarantee for agent
  actions, and corrects `.planning/WINDOWS.md` row 59 against current desktop source -- the
  desktop client's local undo affordance now enqueues a real outbound command (closed by
  KPL-03-23's O-45 fix), so the row's "enqueues NO outbound command" claim is stale as of this
  reading.
- No migration was added (verified via `git diff --stat` over `priv/repo/migrations`) -- the
  actor/client_kind vocabulary for `agent`/`mcp` was already admitted by an earlier migration, as
  the plan anticipated.
- No parallel agent-audit surface exists (`git grep -rn 'agent_activity|agent_audit' -- apps/server/lib`
  returns nothing) -- every agent fact goes through the same `Commands.dispatch/3` ->
  `CommandStore.execute/3` path a human action uses.
- Full `mix test` suite: 223/223 passing (0 failures). `pnpm contracts:check` passes.

## Task Commits

1. **Task 1: Confirm the storage-level privacy guarantee** -- no code change; decision recorded
   below (checkpoint answered inline per locked `05-CONTEXT.md` D-21 guidance, matching this
   phase's own 05-01/05-02 precedent for their Task 1 checkpoints).
2. **Task 2: Agent attribution end to end, and a storage-level privacy assertion** -- `d655cad`
   (feat)
3. **Task 3: The agent undo handle, and an honest statement of what it covers** -- `c180c01`
   (feat)

**Plan metadata:** committed alongside this SUMMARY.

## Files Created/Modified

- `apps/server/lib/keepling/adapters/postgres/command_store.ex` -- write-time actor-label
  truncation for the agent clause of `activity_actor/1`
- `apps/server/test/keepling/application/agent_history_test.exs` -- the plan's full proof surface:
  attribution, refusal-writes-nothing, storage-level privacy, and undo round-trip
- `apps/server/test/keepling/application/activity_test.exs` -- interleaving test, vector
  assertions extended for the new `actors` key
- `apps/server/test/keepling/application/undo_test.exs` -- extended to consume `undo.json`'s new
  `agent_case`
- `packages/contracts/vectors/activity.json` -- new `actors` key (user/agent shapes, label bound)
- `packages/contracts/vectors/undo.json` -- new `agent_case` key
- `docs/architecture/AGENT-RECOVERY.md` -- the undo scope document, naming window 59

## Decisions Made

See `key-decisions` in frontmatter for the full rationale on: Task 1's storage-level privacy
checkpoint (Option A, CONTEXT-locked), the confirmed no-migration-needed finding, why Undo
required zero code changes (it already carried no actor-discriminating clause), the WINDOWS.md
row 59 correction against current source, and the substitution of two real refusal causes
(`invalid_command`, `task_not_found`) for two not-yet-buildable ones (`ambiguous_match`,
`stale_preview`) named literally in the plan text.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Test correctness] Fixed an invalid stale-revision test setup that violated a real DB constraint**
- **Found during:** Task 2, first test run of the four-refusal-causes test
- **Issue:** The initial test attempted `complete_task` with `expected_revision: 0` against a
  freshly-captured task expecting a `409` conflict. `lifecycle_revision` starts at `0` for a new
  task (not `1`), so `expected_revision: 0` was actually current, not stale -- the call succeeded
  (`200`), failing the test's own assertion.
- **Fix:** Restructured the "stale revision" case to complete the task first (advancing
  `lifecycle_revision` to `2`), then attempt `reopen_task` with `expected_revision: 1` -- a
  genuinely stale value that also satisfies `persisted_conflicts_revisions_positive`'s
  `expected_revision >= 1` CHECK constraint (an initial attempt at `expected_revision: 0` for the
  conflict itself violated that constraint and surfaced as `{:error, :infrastructure_failure}`,
  a second self-correction within the same fix cycle).
- **Files modified:** `apps/server/test/keepling/application/agent_history_test.exs`
- **Verification:** `mix test test/keepling/application/agent_history_test.exs` (21/21 passing)
- **Committed in:** `d655cad` (Task 2 commit)

**2. [Rule 1 - Scope substitution, documented] Two of the plan's four named refusal causes do not exist in the codebase yet**
- **Found during:** Task 2, before writing the refusal-causes test
- **Issue:** The plan's behavior text names "insufficient scope, ambiguous match, stale revision,
  stale preview" as the four refusal causes to prove write zero activity facts. `ambiguous_match`
  (MCP-03) and `stale_preview` (MCP-05) are not implemented anywhere in the codebase at this
  plan's Wave 2 position (`depends_on: [05-01]` only) -- they are sibling plans' scope, not yet
  executed.
- **Fix:** Substituted `invalid_command` (a malformed MCP tool call refused by the closed-key
  schema decoder) and `task_not_found` (a real command-level refusal against a nonexistent
  target) -- two refusal causes that are real and reachable today. All four causes actually
  tested (`insufficient_scope`, `invalid_command`, `task_not_found`, stale revision via
  `reopen_task`) are proven to write zero activity facts.
- **Files modified:** `apps/server/test/keepling/application/agent_history_test.exs`
- **Verification:** `mix test test/keepling/application/agent_history_test.exs` (21/21 passing)
- **Committed in:** `d655cad` (Task 2 commit)

---

**Total deviations:** 2 (1 test-correctness fix, 1 documented scope substitution). **Impact on
plan:** Both were necessary to produce a real, passing proof of the plan's actual claims; no
production-code scope creep -- the substitution affects only which refusal causes the test
exercises, not what the plan's `must_haves` require.

## Known Stubs

None specific to this plan. `KeeplingWeb.MCP.Tools` still implements only `keepling.capture_task`
of MCP-02's four verbs, and `resources/*` remains unimplemented -- both are carried-forward,
unchanged gaps from 05-01/05-02, out of this plan's scope (this plan touched
`application/activity.ex`'s consuming layer, `command_store.ex`, and `application/undo.ex`'s
proof, not the MCP tool surface).

## Broken-Windows Ledger

- deviation: `apps/server/test/keepling/application/agent_history_test.exs` -- initial stale-revision
  test setup violated `persisted_conflicts_revisions_positive` and `lifecycle_revision` semantics,
  corrected within Task 2 before commit (see Deviations #1)
- deviation: `apps/server/test/keepling/application/agent_history_test.exs` -- two of the plan's
  four named refusal causes (`ambiguous_match`, `stale_preview`) do not exist yet; substituted
  with `invalid_command`/`task_not_found` (see Deviations #2)
- unmet-truth (observation, not a new ledger row edited by this plan): `.planning/WINDOWS.md` row
  59's "enqueues NO outbound command" claim is stale against current
  `apps/desktop/main/application/DesktopApplication.ts`/`apps/desktop/store-worker/local-store.ts`
  source (see `docs/architecture/AGENT-RECOVERY.md`'s "desktop client's local undo affordance"
  section). This plan did not edit the ledger row (out of `files_modified` scope, no `gsd-tools`
  binary available in this worktree to run `windows fixed`/`windows waive`); flagged here so a
  future pass with tooling access can reconcile it.

## Issues Encountered

- No `gsd-tools.cjs` binary was present in this worktree, so `.planning/WINDOWS.md` could not be
  updated via the standard `gsd_run windows append`/`fixed` verbs. The row 59 finding is recorded
  in `docs/architecture/AGENT-RECOVERY.md` and in this SUMMARY's Broken-Windows Ledger section
  instead, for a future pass with tooling access to reconcile mechanically.
- This worktree had no `apps/server/deps`, `apps/server/_build`, or root `node_modules` installed
  at spawn time. `mix deps.get` (via `runtime-preflight.sh`) and `pnpm install --frozen-lockfile`
  (lockfile-respecting, no `package.json`/lockfile changes) were run to make verification
  possible; both are standard, non-destructive setup steps for a fresh worktree, not deviations
  from the plan.

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness

- MCP-04's agent-attribution, privacy, and undo-parity claims are now proven for the
  server-reached path (server + web client) by a real, passing test suite -- not just designed.
- `docs/architecture/AGENT-RECOVERY.md` gives 05-12's cross-adapter proof an accurate,
  source-verified starting claim about the desktop undo leg (real, but independently unproven for
  an agent-authored fact specifically) rather than the stale "known defective" assumption
  `WINDOWS.md` row 59 would otherwise imply.
- MCP-04 remains unchecked in `REQUIREMENTS.md` -- correctly, since 05-09 and 05-10 also declare
  it and have not yet executed (this plan does not update `REQUIREMENTS.md`/`STATE.md`/
  `ROADMAP.md`; the orchestrator owns those writes after all Wave 2 worktree agents complete).
- `.planning/WINDOWS.md` row 59 still reads its original, now-stale text; a future pass with
  `gsd-tools` access should mark it `fixed` per this plan's finding (see Broken-Windows Ledger).

---
*Phase: KPL-05-safe-agent-access*
*Completed: 2026-09-10*

## Self-Check: PASSED

- `apps/server/lib/keepling/adapters/postgres/command_store.ex` -- FOUND on disk
- `apps/server/test/keepling/application/agent_history_test.exs` -- FOUND on disk
- `docs/architecture/AGENT-RECOVERY.md` -- FOUND on disk
- Commit `d655cad` (Task 2) -- FOUND in `git log --oneline --all`
- Commit `c180c01` (Task 3) -- FOUND in `git log --oneline --all`
- `mix test` (full suite): 223 passed, 0 failures
- `pnpm contracts:check`: passed
- `git diff --stat apps/server/priv/repo/migrations`: empty (no migration added)
- `git grep -rn 'agent_activity|agent_audit' -- apps/server/lib`: no matches
- `git ls-files --error-unmatch docs/architecture/AGENT-RECOVERY.md`: tracked
