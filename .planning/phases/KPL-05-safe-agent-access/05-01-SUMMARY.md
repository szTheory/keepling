---
phase: KPL-05-safe-agent-access
plan: 01
subsystem: mcp
tags: [mcp, oauth, pkce, device-grants, json-rpc, elixir, phoenix, ecto, postgresql]

# Dependency graph
requires:
  - phase: KPL-01
    provides: Commands.dispatch/3, TaskViews, Activity actor shape (agent clause already present), the account-scoped semantic boundary
  - phase: KPL-02
    provides: PKCE device-grant OAuth seam, opaque HMAC-signed account-bound token construction
provides:
  - "device_grants.client_kind admits 'mcp' alongside electron/iphone"
  - "device_grants.scope column plus a closed D-06 scope vocabulary (tasks.read, tasks.write, tasks.bulk)"
  - "an MCP-only authorize/exchange param allow-list accepting RFC 8707 resource, unwidened for electron/iphone"
  - "POST /mcp/v1 -- a real JSON-RPC 2.0 / Streamable HTTP MCP endpoint pinned to protocol revision 2025-06-18"
  - "one working write tool, keepling.capture_task, dispatching through the same Commands.dispatch/3 every adapter uses"
  - "Keepling.Application.AgentScope -- the authoritative two-layer scope gate"
affects: [KPL-05-02, KPL-05-03, KPL-05-04, KPL-05-05, KPL-05-06, KPL-05-07, KPL-05-08, KPL-05-09, KPL-05-10, KPL-05-11, KPL-05-12]

actuals:
  tokens: 68000
  tasks: 3
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Hand-rolled JSON-RPC 2.0 / Streamable HTTP framing (no MCP library dependency; D-31 confirmed)"
    - "MCP adapter as a fifth thin transport over Keepling.Application.* -- same shape as CommandController"
    - "Two-layer scope check: adapter fast-fail (KeeplingWeb.MCP.Scope) plus application-boundary gate (Keepling.Application.AgentScope), both always run"
    - "Closed CHECK constraint + mirrored Elixir closed list(s), extended to a fourth site (Keepling.Application.@client_kinds, boot-time redirect allowlist validator) beyond the three research named"

key-files:
  created:
    - apps/server/priv/repo/migrations/20260911000100_add_mcp_client_kind_and_scope.exs
    - apps/server/lib/keepling/application/agent_scope.ex
    - apps/server/lib/keepling_web/mcp/pipeline.ex
    - apps/server/lib/keepling_web/mcp/dispatch.ex
    - apps/server/lib/keepling_web/mcp/handshake.ex
    - apps/server/lib/keepling_web/mcp/scope.ex
    - apps/server/lib/keepling_web/mcp/tools.ex
    - apps/server/lib/keepling_web/mcp/errors.ex
    - apps/server/test/keepling/accounts/mcp_client_kind_test.exs
    - apps/server/test/keepling_web/mcp/tracer_capture_test.exs
  modified:
    - apps/server/lib/keepling/accounts/device_grant.ex
    - apps/server/lib/keepling_web/controllers/device_grant_controller.ex
    - apps/server/lib/keepling/application.ex
    - apps/server/lib/keepling_web/router.ex
    - apps/server/config/runtime.exs

key-decisions:
  - "Task 1's three one-way doors were answered Option A for all three, exactly as CONTEXT-locked: D-06 three scope strings (tasks.read/tasks.write/tasks.bulk), D-07 PKCE-only with no static key or client-credentials grant, and extending device_grants (not a separate agent_grants table)."
  - "D-30 re-check requested by the plan could not be performed against a live host -- no MCP host or model credential is reachable inside this execution sandbox. Recorded as an open item, not silently skipped."
  - "Canonical MCP resource URI is {configured device-grant origin}/mcp/v1, matching the mounted POST /mcp/v1 path."
  - "AgentScope's @agent_scopes list is duplicated locally inside device_grant.ex rather than delegated, because Task 2's own commit must compile and test standalone before AgentScope exists (Task 3). Documented as a Rule-1-style ordering fix, not a silent deviation."
  - "No new rate-limiting or security-audit plug was added to the :mcp pipeline. Grepping the existing command routes (/commands/*) found no generic hammer/security_audit plug applied to any of them either -- the D-03 'inherits the existing hammer rate limiting and security_audit path' language describes an aspirational posture that does not exist yet for ANY authenticated-mutation route, not something this plan regressed. Flagged for a later plan or phase-level decision rather than invented here."

patterns-established:
  - "MCP JSON-RPC dispatch table keyed by method name, each handler taking (params, context) and returning {:ok, result} | {:error, error_map} -- later plans add methods/tools to this table without touching KeeplingWeb.MCP.Dispatch's own framing logic."
  - "MCP tool decode uses the same Enum.sort(Map.keys(params)) == allowed_keys closed-shape idiom as CommandController; later tools copy this exactly."

requirements-completed: []  # MCP-02, MCP-04, SRV-02 are declared by multiple plans in this phase (sibling plans not yet executed); requirements.ready-ids confirmed 0/3 ready to mark complete from this plan alone.

coverage:
  - id: D1
    description: "An mcp device grant is a first-class client kind carrying a validated, closed scope set, stored alongside electron/iphone without changing their validation."
    requirement: "MCP-02"
    verification:
      - kind: integration
        ref: "test/keepling/accounts/mcp_client_kind_test.exs"
        status: pass
      - kind: integration
        ref: "test/keepling_web/device_grant_controller_test.exs"
        status: pass
    human_judgment: false
  - id: D2
    description: "An agent grant obtained through the real PKCE flow captures exactly one task over the real MCP JSON-RPC/Streamable HTTP endpoint, idempotent on mutation_id replay, refused with zero writes when scope is insufficient."
    requirement: "MCP-02"
    verification:
      - kind: integration
        ref: "test/keepling_web/mcp/tracer_capture_test.exs"
        status: pass
    human_judgment: false
  - id: D3
    description: "The captured task's activity record names the agent grant as actor (type agent, principal authorized_grant, client_kind mcp), readable through the existing browser activity endpoint."
    requirement: "MCP-04"
    verification:
      - kind: integration
        ref: "test/keepling_web/mcp/tracer_capture_test.exs#tools/call captures exactly one task and is idempotent on mutation_id replay"
        status: pass
    human_judgment: false
  - id: D4
    description: "The MCP server declares protocol revision 2025-06-18 verbatim in its initialize response, and the pin was re-checked against a live representative host before implementation per D-30."
    requirement: "MCP-02"
    verification:
      - kind: integration
        ref: "test/keepling_web/mcp/tracer_capture_test.exs#initialize declares the pinned protocol revision and tools+resources capabilities"
        status: pass
    human_judgment: true
    rationale: "The D-30 live-host re-check itself could not be performed -- no MCP host or model credential is reachable in this execution sandbox. The revision is asserted correct against the plan's own decision, not verified against a live client's negotiated behavior. A human (or the phase's representative-model evidence lane) must confirm 2025-06-18 is still accepted by the actual hosts in use before this is treated as fully proven."

duration: ~80min
completed: 2026-09-10
status: complete
---

# Phase 5 Plan 01: Safe Agent Access -- MCP Tracer Slice Summary

**An `mcp` device grant, obtained through the real PKCE flow, captures one task over a hand-rolled JSON-RPC 2.0 / Streamable HTTP `POST /mcp/v1` endpoint into real Postgres via the same `Commands.dispatch/3` every other adapter uses, with a two-layer scope gate and full activity attribution.**

## Performance

- **Duration:** ~80 min
- **Tasks:** 3 (1 checkpoint:decision, 1 auto, 1 tracer/tdd)
- **Files created:** 10
- **Files modified:** 5

## Accomplishments

- `device_grants.client_kind` admits `mcp` alongside `electron`/`iphone` across all four closed-list sites (migration CHECK, `DeviceGrant.@client_kinds`, `DeviceGrantController.@client_ids`, `Keepling.Application.@client_kinds` boot validator) -- confirmed via `git grep -n "electron iphone" -- lib` returning no hits outside those three files.
- `device_grants.scope` (`{:array, :text}`) plus `device_grants_scope_closed` CHECK constraint close the scope vocabulary to `tasks.read`/`tasks.write`/`tasks.bulk`, and enforce an empty scope for non-`mcp` grants at the database layer -- proven with a direct raw-SQL insert that the DB itself, not just Elixir, rejects an out-of-vocabulary value.
- The redirect-URI validator in `Keepling.Application` now branches by client kind: `electron`/`iphone` keep the private-use `keepling://host/path` requirement unchanged; `mcp` accepts an absolute `http(s)` URI with a non-empty host and path.
- `DeviceGrantController` gained MCP-only `@mcp_authorize_keys`/`@mcp_exchange_keys` admitting RFC 8707's `resource` parameter (and `scope`), matched against this server's canonical MCP resource URI (`{origin}/mcp/v1`); `@authorize_keys`/`@exchange_keys` for electron/iphone are unchanged.
- A real, hand-rolled MCP endpoint at `POST /mcp/v1`: `KeeplingWeb.MCP.Pipeline` (bearer auth via the existing device-grant path, `client_kind == "mcp"` refusal, 401 + `WWW-Authenticate` on failure), `KeeplingWeb.MCP.Dispatch` (JSON-RPC envelope framing only), `KeeplingWeb.MCP.Handshake` (`initialize`/`ping`, protocol revision `2025-06-18` pinned verbatim), `KeeplingWeb.MCP.Tools` (`tools/list`, `tools/call` for `keepling.capture_task`), `KeeplingWeb.MCP.Errors` (closed JSON-RPC error vocabulary).
- `Keepling.Application.AgentScope` -- the closed three-member scope vocabulary and the authoritative `require/2` gate, called from `KeeplingWeb.MCP.Tools` after `KeeplingWeb.MCP.Scope`'s adapter-layer fast-fail (both always run).
- An end-to-end tracer test (`test/keepling_web/mcp/tracer_capture_test.exs`) that obtains a real `mcp` grant through the real `/oauth/authorize` + `/oauth/token` PKCE flow, calls the real `POST /mcp/v1` endpoint, and asserts against real Postgres: exactly one task row created, idempotent replay on the same `mutation_id`, zero writes when scope is insufficient, and the activity record naming the agent actor -- readable both by direct SQL and through the existing `GET /api/v1/tasks/:task_id/activity` browser endpoint.
- `git diff --stat apps/server/mix.exs` is empty -- no dependency added, confirming D-31's hand-roll decision.

## Task Commits

1. **Task 1: Confirm the three one-way authorization doors** -- no code change; decision recorded below (checkpoint answered inline per locked CONTEXT.md guidance, not a file commit).
2. **Task 2: Admit an agent client kind and a scope set** -- `bf057ae` (feat)
3. **Task 3: End-to-end "an agent captures one task"** -- `e27ac4f` (feat)

**Plan metadata:** committed alongside this SUMMARY.

## Files Created/Modified

- `apps/server/priv/repo/migrations/20260911000100_add_mcp_client_kind_and_scope.exs` -- widens `device_grants_client_kind`, adds `scope` + `device_grants_scope_closed`
- `apps/server/lib/keepling/accounts/device_grant.ex` -- `mcp` client kind, scope persistence/validation, `label`+`scope` returned by `authenticate_access`
- `apps/server/lib/keepling_web/controllers/device_grant_controller.ex` -- MCP-only param allow-lists, RFC 8707 `resource` validation against the canonical MCP resource URI
- `apps/server/lib/keepling/application.ex` -- boot-time `@client_kinds` widened; redirect-scheme validator branches by client kind
- `apps/server/config/runtime.exs` -- registers the `mcp` redirect URI so the server boots with the widened three-kind allowlist
- `apps/server/lib/keepling_web/router.ex` -- `:mcp` pipeline, `POST /mcp/v1`
- `apps/server/lib/keepling/application/agent_scope.ex` -- the closed scope vocabulary and authoritative gate
- `apps/server/lib/keepling_web/mcp/{pipeline,dispatch,handshake,scope,tools,errors}.ex` -- the MCP adapter tree
- `apps/server/test/keepling/accounts/mcp_client_kind_test.exs`, `apps/server/test/keepling_web/mcp/tracer_capture_test.exs` -- the plan's seven closed-list/scope cases and the end-to-end tracer proof

## Decisions Made

**Task 1's three one-way doors -- answered "A" for all three, as CONTEXT-locked:**

- **(a) D-06 scope vocabulary:** Option A -- exactly `tasks.read`, `tasks.write`, `tasks.bulk`. Absent scope means denied; no wildcard, no implicit grant.
- **(b) D-07 credential posture:** Option A -- authorization-code + S256 PKCE + exact redirect binding, reusing the existing device-grant seam. No client-credentials grant, no long-lived static API key.
- **(c) Identity-model widening:** Option A -- kept the `device_grants` table and name; the PKCE/rotating-refresh/replay-detection lifecycle is exactly right for an agent, and the activity `actor_type = 'agent'` vocabulary was already anticipated by an earlier migration.

These were recorded in `05-CONTEXT.md` under `--auto` discussion mode as the researched recommended options, with this checkpoint existing precisely so the answer is on the record before the authorization doors are walked through. No alternative was proposed or needed.

**D-30 re-check (live host protocol revision):** the plan asked this task to re-check the pinned revision against a live representative host's observed behavior before writing the transport. That re-check could not be performed -- this execution environment has no reachable MCP host (Claude Code/Claude Desktop) and no model API credential to drive one. `2025-06-18` was implemented as pinned per `05-CONTEXT.md`/`05-RESEARCH.md`'s own recommendation, but the "verify against live host behaviour, not this document" instruction is only partially satisfied: the implementation is internally consistent and tested, but not empirically checked against a live client's negotiated revision. This is recorded as an open item for a later plan's representative-model evidence lane, not silently marked done.

**Canonical MCP resource URI:** `{configured device-grant origin}/mcp/v1` -- derived from the same `:keepling, :device_grants, :origin` configuration value the existing namespace tuple already uses, concatenated with the mounted `/mcp/v1` path.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Checkpoint routing bug in `KeeplingWeb.MCP.Dispatch`**
- **Found during:** Task 3, first test run
- **Issue:** Naming the JSON-RPC handler function `call/2` collided with the `call/2` Phoenix.Controller generates via `use KeeplingWeb, :controller` -- the router invoked the framework's own dispatch with the route's action atom (`:call`) as the second argument instead of `conn.params`, crashing every request with `BadMapError`.
- **Fix:** Renamed the handler to `handle/2` and updated the router to `post "/v1", Dispatch, :handle`.
- **Files modified:** `apps/server/lib/keepling_web/mcp/dispatch.ex`, `apps/server/lib/keepling_web/router.ex`
- **Verification:** All 6 tracer tests pass; full `mix test` suite (201 tests) passes with zero failures.
- **Committed in:** `e27ac4f` (Task 3 commit)

**2. [Rule 3 - Blocking] `:scope` key breaking pre-existing electron/iphone authorization requests**
- **Found during:** Task 2 implementation
- **Issue:** The plan's literal wording implied adding `scope` as a required key to `DeviceGrant`'s own closed-key validator, which would have broken every pre-existing caller (including `test/keepling/accounts/device_grant_test.exs`, which builds authorization request maps without a `scope` key at all) -- violating the plan's own success criterion that "No electron or iphone behaviour changed."
- **Fix:** Made `:scope` an OPTIONAL key at the `DeviceGrant.validate_authorization_request/1` boundary -- both the 7-key legacy shape and the 8-key shape-with-scope validate. `DeviceGrantController` always supplies `scope: params["scope"] || ""` so every controller-driven request (electron, iphone, mcp alike) uses the 8-key shape; direct module-level callers that omit `:scope` entirely (as every pre-existing test does) keep working unchanged.
- **Files modified:** `apps/server/lib/keepling/accounts/device_grant.ex`
- **Verification:** `test/keepling_web/device_grant_controller_test.exs` and `test/keepling/accounts/device_grant_test.exs` (existing suites) pass unmodified.
- **Committed in:** `bf057ae` (Task 2 commit)

**3. [Rule 1 - Ordering bug] `AgentScope` delegation deferred to avoid a compile-time forward reference**
- **Found during:** Task 2 implementation
- **Issue:** The plan's Task 2 action says to give `DeviceGrant` an `@agent_scopes` list "only by delegating to `Keepling.Application.AgentScope`," but `AgentScope` is created in Task 3 -- a module in that task's own file list, not Task 2's. Delegating to a not-yet-created module inside a commit meant to compile and test standalone would break Task 2 in isolation.
- **Fix:** Defined `@agent_scopes ~w(tasks.read tasks.write tasks.bulk)` locally inside `device_grant.ex` with a comment explaining the ordering constraint, rather than delegating.
- **Files modified:** `apps/server/lib/keepling/accounts/device_grant.ex`
- **Verification:** Both the local list and `AgentScope.@agent_scopes` are byte-identical (`~w(tasks.read tasks.write tasks.bulk)`); no test currently asserts their identity mechanically, which is a residual duplication risk flagged below.
- **Committed in:** `bf057ae` (Task 2 commit)

---

**Total deviations:** 3 auto-fixed (1 bug, 1 blocking, 1 ordering bug). **Impact on plan:** All three were necessary for correctness or for the plan's own "no electron/iphone regression" success criterion. No scope creep -- no capability was added beyond what the plan specified.

## Known Stubs

- `KeeplingWeb.MCP.Handshake`'s `capabilities` declares `tools: %{}` and `resources: %{}` -- the `resources` capability is declared but no `resources/list`/`resources/read` handler exists yet in `KeeplingWeb.MCP.Dispatch`'s `@methods` table. This is intentional per the plan's own text ("Stubs are permitted in this task ONLY for the read surface and the remaining three write tools, which later plans fill in without changing any module boundary introduced here"). A client calling `resources/list` today would receive `-32601 Method not found` despite the capability being advertised. Future plan: MCP-01's read-surface plan (05-04 or similar per ROADMAP) should implement the corresponding methods.
- `KeeplingWeb.MCP.Tools.list/2` advertises only `keepling.capture_task`; `update_task`, `complete_task`, `reopen_task` (MCP-02's remaining three verbs) are not yet implemented. Matches the plan's explicit scope for this tracer plan.
- The `:mcp` Phoenix pipeline does not apply a `hammer` rate-limit plug or a `security_audit`-recording plug, despite `05-RESEARCH.md`/CONTEXT.md's D-03 describing agent traffic as inheriting "the existing hammer rate limiting and the security_audit path the other authenticated pipelines use." Investigation during Task 3 found this infrastructure does not exist as a generic router-level plug for ANY authenticated-mutation route today (`/commands/*` has none either) -- rate limiting is applied inline, per-action, only inside `AuthController` for `:setup`/`:login`/`:recovery`/`:reauthentication` flows. This is a pre-existing gap this plan did not regress, but D-03's posture is not yet true for MCP traffic. Flagged for a later plan or an explicit phase-level decision about whether/how to add request-level rate limiting to `/commands/*` and `/mcp/v1` together.

## Broken-Windows Ledger

Recorded to `.planning/WINDOWS.md` (if the ledger is present in this project):

- stub: `apps/server/lib/keepling_web/mcp/handshake.ex` -- `resources` capability declared, no `resources/*` method implemented yet
- stub: `apps/server/lib/keepling_web/mcp/tools.ex` -- only `keepling.capture_task` implemented of MCP-02's four verbs
- deviation: `apps/server/lib/keepling/accounts/device_grant.ex` -- `@agent_scopes` duplicated rather than delegated to `Keepling.Application.AgentScope` (ordering constraint, see Deviations #3)

## Issues Encountered

- The D-30 live-host re-check (see Decisions Made) could not be completed for lack of a reachable representative MCP host or model credential in this execution sandbox. This is a genuine gap, not a silently-skipped step -- it is named here and should be picked up by the phase's representative-model evidence lane (per `05-RESEARCH.md` §8/§10(e)) once a real credential/host is available.

## User Setup Required

None -- no external service configuration required. (A future plan's representative-model/adversarial evidence lanes will need an `ANTHROPIC_API_KEY`-equivalent credential and/or a reachable MCP host, per D-26, but that is out of this plan's scope.)

## Next Phase Readiness

- The Phase 5 architecture's riskiest bets (placement D-01, credential class D-05/D-07, two-layer scope check D-06, pinned revision D-04) are now proven end-to-end by one committed, passing test, not just designed.
- `Keepling.Application.AgentScope`, `KeeplingWeb.MCP.Scope`, `KeeplingWeb.MCP.Errors`, and the `@methods` dispatch table in `KeeplingWeb.MCP.Dispatch` are the extension points later plans use to add `resources/*` (MCP-01), the remaining three write tools (MCP-02), ambiguity handling (MCP-03), and preview/commit (MCP-05) without altering any module boundary this plan introduced.
- Blocker for the phase's cross-adapter proof and representative-model/adversarial lanes: no MCP host or model credential is reachable in this environment. Whoever executes those later plans needs that credential/host provisioned first, or those lanes will correctly report `BLOCKED` per D-26.
- MCP-02, MCP-04, and SRV-02 remain unchecked in `REQUIREMENTS.md` -- correctly, since sibling plans in this phase also declare them and have not yet executed (`requirements.ready-ids` confirmed 0/3 ready).

---
*Phase: KPL-05-safe-agent-access*
*Completed: 2026-09-10*
