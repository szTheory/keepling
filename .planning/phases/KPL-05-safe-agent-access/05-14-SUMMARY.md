---
phase: KPL-05-safe-agent-access
plan: 14
subsystem: auth
tags: [mcp, device-grants, authorization, scope, least-privilege, phoenix]

requires:
  - phase: KPL-05-safe-agent-access
    provides: "the MCP adapter, its device-grant credential class, AgentScope, and 05-13's client_kind half of the same boundary"
provides:
  - "current_scope carried on every surface a device grant authenticates, not only under KeeplingWeb.MCP.Pipeline"
  - "A default-deny agent authority table on :client_authenticated and :client_mutation, enforced through Keepling.Application.AgentScope"
  - "AgentScope's first call site outside lib/keepling_web/mcp/ — its 'application-boundary' moduledoc is now true of the application"
  - "Five server boundary tests and six adversarial-lane scope over-delivery cases, both mutation-tested"
affects: [KPL-05 re-verification, MCP-02, MCP-01, D-09, SRV-02, any future route placed behind :client_authenticated or the shared command surface]

actuals:
  tokens: 8700
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Authority = client_kind x scope: both factors default-deny, or the boundary is half a product"
    - "The deny decision executed by the application module (AgentScope), not by an adapter branch"
    - "Route allow-list mirroring the published tool set, so agent authority is a property of the credential rather than of the adapter"

key-files:
  created:
    - apps/server/test/keepling_web/agent_authorization_test.exs
  modified:
    - apps/server/lib/keepling_web/auth.ex
    - tooling/mcp-lanes/adversarial.mjs

key-decisions:
  - "Option B (carry current_scope and enforce it), not option A (refuse mcp on :client_authenticated) — a consumer of A's no-consumer claim WAS found, and the plan's own key_links require a link from auth.ex to agent_scope.ex that A cannot produce."
  - "The gate keys on agent client kinds only, so browser sessions and electron/iphone grants are byte-identically unaffected — a first-party grant carries no scope at all, so a blanket scope requirement would have broken every native client."
  - "Scope alone is not sufficient: the route table is an allow-list mirroring the closed MCP tool set, because trash/restore/undo are reachable by an agent only through the previewed, revision-bound tasks.bulk two-step."
  - "403 insufficient_scope, not 401: the credential authenticated; what it lacks is authority. Same code the MCP surface already returns for the same refusal."
  - "The auth.ex carve-out comment claiming 'scope-checked and bounded' is corrected in place rather than deleted."

patterns-established:
  - "Default-deny route authority: an unmapped route asks for no scope and is refused, so a route added later does not silently inherit agent reach."
  - "Mutation-test each half separately: one mutation proves the scope comparison has teeth, a second proves the allow-list does — a single mutation that trips the first case proves nothing about the second."

requirements-completed: []

duration: 45min
completed: 2026-09-11
status: complete
---

# Phase KPL-05 Plan 14: Agent Scope Boundary Gap Closure — Summary

**An MCP agent credential scoped `tasks.read` could capture and trash tasks through the shared `/api/v1/commands/*` surface while the same token was refused `insufficient_scope` at `/mcp/v1`; the scope is now carried on every surface a grant authenticates and enforced through the application's own scope gate, with the agent's HTTP authority bounded to exactly the closed tool set it can already reach.**

## Performance

- **Duration:** ~25 min of execution, plus ~20 min of gate, model-lane and phase-1 runs
- **Tasks:** 3 of 3
- **Files:** 2 modified, 1 created (751 insertions, 8 deletions)

## Task 1 — the shape, and why

**Chosen: option B (carry `current_scope` and enforce it), not option A (refuse `mcp` on `:client_authenticated`/`:client_mutation`).**

I was asked to confirm A's no-consumer finding myself rather than inherit it. **I searched and I found one.** What I searched:

| Search | Result |
|---|---|
| Every JS/TS/Swift file referencing `/api/v1` that also mentions `Bearer`/`accessToken`/`access_token` (cross-product grep over `tooling/`, `apps/`, `packages/`, excluding `node_modules`) | `tooling/ios-device/*` and `apps/desktop/main/adapters/sync.ts` send **first-party** (`iphone`/`electron`) grants. `tooling/cross-adapter/legs.mjs`'s `mcpAdapter` only calls `toolsCall` → `/mcp/v1`. `tooling/mcp-client/final-state.mjs` reads through the owner's session. `tooling/mcp-lanes/adversarial.mjs`'s only `/api/v1` bearer use is the over-delivery probe that **asserts refusal**. |
| `apps/web/e2e/agent-access.spec.ts` (the only web e2e that mints an `mcp` grant) | Its bearer goes to `/mcp/v1` and nowhere else (`mcpCall` at line 127). Not a consumer. |
| All Elixir call sites of `AgentScope` | All 12 inside `lib/keepling_web/mcp/` — confirming the adapter-locality window #72 names. |
| Elixir tests creating an `mcp`-kind grant and issuing HTTP requests | **`test/keepling/application/projects_test.exs:86`** — "GET /api/v1/search returns byte-identical rows across a browser session, a device-grant bearer, and an **mcp bearer**", with a `tasks.read`-scoped `mcp` grant asserting **200 and byte-identity**. Its moduledoc states the surfaces "every credential class in `:client_authenticated` reaches identically (D-09)". |

That last one is a caller that sends an `mcp`-kind bearer to `/api/v1` and depends on a 200. It is a **test**, not a product client, and I am flagging that distinction rather than hiding behind it — but it is not incidental: it is the HTTP-level evidence for D-09/SRV-02's "same invariants across adapters" claim, written deliberately. Option A would have required inverting that assertion, i.e. **destroying evidence for SRV-02 in order to close MCP-02**. Under option B it passes untouched, because a `tasks.read` grant asking for a read is exactly what its grant covers.

Two further reasons B is right rather than merely acceptable:

1. **The plan's own `must_haves.key_links`** requires a link `auth.ex → agent_scope.ex` via "the application-boundary scope gate stops being reachable only from `lib/keepling_web/mcp/`". Option A produces no such link — it refuses `mcp` and leaves `AgentScope` exactly as adapter-local as window #72 found it. Only B makes `AgentScope`'s own moduledoc true.
2. **MCP-02's clause is "least-privilege scopes", not "no privileges".** A blanket class denial satisfies the letter of truth 1 by removing the surface, and leaves the scope machinery still untested outside one adapter.

**Which of truth 1's two branches is true, stated plainly:** an agent credential *can* reach the shared `/api/v1` surface, and *cannot* reach it beyond the authority its grant carries. It is bounded twice — by scope, and by a route allow-list.

### What was built

- `authenticate_device_grant/1` now assigns `:current_scope` from the loaded grant on **every** surface it authenticates. This is the root defect: the scope was not merely unchecked, it was absent from the conn, so no route outside `/mcp/v1` could have checked it.
- `authorize_agent/1` runs on both `:client_authenticated` and `:client_mutation`, for agent client kinds only, and delegates the decision to `Keepling.Application.AgentScope.require/2` — its first call site outside `lib/keepling_web/mcp/`.
- The authority table is **default-deny** and names exactly what the closed tool set already reaches: `tasks.read` for `/api/v1/search`, `/api/v1/projects`, `/api/v1/projects/:id/tasks`; `tasks.write` for `/api/v1/mutations/:id` (D-49 moves the receipt with the write) and for the six commands `keepling.capture_task`, `keepling.update_task` (which decodes into `edit_task`, `edit_task_dates`, `assign_task_organizations`), `keepling.complete_task` and `keepling.reopen_task` reach. The other thirteen command routes are refused.
- **Why the thirteen, and why scope alone is not enough:** `trash-task`, `restore-task` and `undo-task` are the closed D-19 destructive vocabulary. An agent reaches them only through `preview_bulk_change` + `commit_bulk_change` — gated by `tasks.bulk` **and** by a signed token binding exact targets and expected revisions (D-17, D-18). A scope-only check would have handed a `tasks.bulk` grant a one-step, unpreviewed, drift-unchecked trash over HTTP: a route around the safeguard the bulk path exists to impose. The remaining ten are outside the tool set the phase deliberately published.
- **`auth.ex:147`:** the sentence claiming that surface is "scope-checked and bounded" is corrected **in place**, with the correction naming what was true (bounded), what was false (scope-checked), and why it was structurally impossible. It is recorded rather than deleted because an inherited, plausible, unverified claim is exactly how the next reader concludes a boundary is already covered.
- **The owner is untouched.** The gate keys on `client_kind == "mcp"`. A browser session has no `current_client_kind` at all; `electron`/`iphone` grants carry no scope at all — so had this been written as a blanket scope requirement, every native client would now be 403. Pinned by test, not by prose.

**Commit:** `c040649`

## Task 2 — proof at the boundary

`apps/server/test/keepling_web/agent_authorization_test.exs`, 5 cases, all passing. Every refusal asserts **exactly 403** and the exact problem body, never "not 200" — a deleted route answers 404 and would hollow the file out silently.

| Case | Asserts |
|---|---|
| `tasks.read` cannot capture | 403 + `SELECT count(*) FROM tasks WHERE title = canary` is 0. Controls: a `tasks.write` grant captures through the same route in the same second, and so does the owner's session. |
| No agent grant can trash | `read`, `write` **and `bulk`** all 403; after each refusal the task is read back **by its owner** as still present. Control: the owner trashes it (200) and then reads 404 — the refusals are about the credential, not a broken route. |
| `tasks.write`-only (and an unscoped grant) cannot read | 403 on `/api/v1/search`, `/api/v1/projects`, `/api/v1/projects/:id/tasks`; refusal bodies proven not to contain the canary title or the project id. Control: a `tasks.read` grant gets **byte-identical** bodies to the owner's session on all three — D-09's one shared query is still one query. |
| Commands outside the tool set | `plan-for-today` and `create-organization` refused for `read` and `write` alike; `SELECT count(*) FROM organizations` is 0. |
| Nothing else moved | `electron` and `iphone` grants still capture and still list projects; the owner still reaches every command the agent was just refused on, and still searches. |

**Mutation-tested:** emptying `@agent_client_kinds` turns **4 of the 5 red**. The fifth is the control that must stay green, and does.

**Commit:** `4d7ea21`

## Task 3 — scope over-delivery cases in the adversarial lane

Six cases added alongside 05-13's four kind cases, following their structure (exactly-403 assertions, scored on final state read back through the **owner's** session, plus controls). Lane went 10 → 16 cases.

Two of the six — `write_grant_trashes_unpreviewed` and `bulk_grant_trashes_unpreviewed` — are refused by the **route allow-list** rather than by the scope comparison, and they exist precisely because `write` carries `tasks.write` and `bulk` carries `tasks.bulk`: if `trash-task` were ever admitted to the agent command set, the scope check alone would wave both through.

### The mutations, and their exact failure text

Both were made, observed, and restored immediately; `git status` confirms `auth.ex` matches its committed state.

**Mutation 1 — `@agent_client_kinds ~w(mcp)` → `~w()`** (re-opens the hole wholesale). Lane exit code **1**, stdout carried no `ADVERSARIAL` evidence line at all:

```
Error: scope_over_delivery case "read_grant_captures": POST /api/v1/commands/capture-task answered 201 for an mcp grant scoped tasks.read; expected 403
```

**Mutation 2 — `trash-task` added to `@agent_writable_commands`** (re-opens only the allow-list half, which mutation 1 could not distinguish). Lane exit code **1**:

```
Error: scope_over_delivery case "write_grant_trashes_unpreviewed": POST /api/v1/commands/trash-task answered 200 for an mcp grant scoped tasks.write; expected 403
```

Both messages name the route and the credential's scope. One mutation would have been insufficient evidence here: it trips the first case and says nothing about whether the allow-list half has teeth.

**Commit:** `bae0e23`

## Verification Evidence

### MCP phase gate

`KEEPLING_E2E_POSTGRES_PORT=55442 pnpm run verify:mcp:phase`, run `3fe22e32-4620-4ae0-aa1a-998a66e7a443`.

| Lane | Status | Cases | Notes |
|------|--------|-------|-------|
| deterministic | PASS | 183 | unchanged |
| protocol | PASS | 2 | unchanged (decorative constant, pre-existing) |
| simulated-client | PASS | 9 | unchanged |
| adversarial | PASS | **16** | was 10; 6 injection + 4 kind over-delivery + **6 scope over-delivery** |
| representative-model | PASS | 6 | live model, run `f99708ee-83d2-4ffd-a177-e618cd38cfd0`, 49.8s. Reported BLOCKED inside the isolated worktree because `.env.local` is gitignored and therefore invisible here — **an artifact of isolation, not a product fact**. Re-run with the main checkout's credential file supplied via `--env-file-if-exists`; a credential was present. Its value was never read, echoed, copied, logged or written anywhere. |
| cross-adapter | BLOCKED | 0 | `electron`/`iphone` legs on unwired drivers (window #69) — expected, out of scope, unchanged by this plan. `web-api` and `mcp` legs PASS 4 each, `comparison_ok=true`. |

**`lanes=6 failed=0 blocked=2`.** Gate exit is non-zero solely because of the two disclosed BLOCKED lanes, one of which is an isolation artifact.

### Phase-1 gate

`KEEPLING_E2E_POSTGRES_PORT=55442 pnpm test:phase-1` → **exit 0**.

| Lane | Result |
|---|---|
| repository integrity | passed |
| server compile (`--warnings-as-errors`) | passed |
| server ExUnit | **324 passed** (1 property, 323 tests) — was 319; +5 from this plan |
| production routes | no test-only control exposed |
| contracts | OpenAPI agrees, no generation drift; 15 vector files, 18 consumer entries |
| web typecheck | passed |
| web units | 169 passed (16 files) |
| web e2e | 26 passed |
| automated UAT coverage | 3/3 checkpoints mapped |

The OpenAPI contract needed no change: no route was added or moved, and the repository's existing convention does not enumerate auth-problem responses per route (`origin_not_allowed`, the other 403 on this surface, is likewise undocumented). `contracts:check` passes including the drift check.

## Deviations from Plan

**1. [Rule 2 — Missing critical functionality] Scope alone would have left a one-step unpreviewed destructive path**

- **Found during:** Task 1, reading `Keepling.Application.Preview`'s `@destructive_commands ~w(trash_task restore_task undo_task)a`.
- **Issue:** The plan's truths are satisfied by a scope check alone, but a `tasks.write` grant would then still POST `/api/v1/commands/trash-task`, and a `tasks.bulk` grant would reach the whole destructive vocabulary in **one step** — bypassing the preview token that binds exact targets and expected revisions (D-17, D-18). The bulk path's entire safety story is that two-step; an HTTP route around it is not a smaller version of the hole, it is the same hole.
- **Fix:** The authority table is an allow-list mirroring the published tool set, so thirteen command routes are refused for any agent whatever its scope. Covered by two server cases and two lane cases, and mutation-tested separately (mutation 2 above).
- **Files:** `apps/server/lib/keepling_web/auth.ex`
- **Commit:** `c040649`

**2. [Housekeeping] Test file named `agent_authorization_test.exs`, not `command_controller_test.exs`**

- **Issue:** The plan's `files_modified` named `test/keepling_web/command_controller_test.exs` (which does not exist) and `test/keepling_web/auth_test.exs`. The boundary spans `CommandController`, `SearchController`, `ProjectController` and the owner's session, and `auth_test.exs` is `KeeplingWeb.AuthLifecycleTest` — a login-lifecycle file whose every case signs in, and window #71's login budget makes it the wrong place to add sign-in-adjacent cases.
- **Fix:** One new file covering the boundary as a single property. Its sessions are minted through `Accounts.create_session/2` rather than `POST /api/v1/login`, so **no login budget is consumed**.
- **Files:** `apps/server/test/keepling_web/agent_authorization_test.exs`

---

**Total deviations:** 2 (1 × Rule 2, 1 × housekeeping). Neither changes scope; the first closes a gap the plan's truths did not name but its objective did.

## Known Stubs

None. No stub, skipped test, or unrun `<verify>` was introduced.

## Threat Flags

None. No new network endpoint, auth path, file-access pattern or schema change was introduced — this plan narrows an existing trust boundary.

## MCP-02 evidence position

**Recommendation: MCP-02's "least-privilege scopes" clause is now checkable on the evidence that falsified it, but this plan does not check it, and I did not check it. The box stays unchecked and WINDOWS #72 stays `open` for re-verification to close after its own probe.**

The verifier's objection to MCP-02 was never that scopes did not exist — `AgentScope` and the closed `tasks.read`/`tasks.write`/`tasks.bulk` vocabulary have been enforced at `/mcp/v1` since 05-02. It was that **least-privilege was a property of one adapter, not of the credential**: the same `tasks.read` bearer that `/mcp/v1` refused `insufficient_scope` got 201 from `/api/v1/commands/capture-task` and 200 from `/api/v1/commands/trash-task`, and the mirror held for `tasks.write` on the read surface. That falsifier is closed, and closed on evidence of the same kind that produced it:

- Both probe directions are now server tests that fail if either reopens (5 cases, 4 of 5 mutation-proven red).
- Both are lane cases in the phase's own gate, scored on final state through the owner's session, mutation-proven red **twice** — once for the scope comparison, once for the allow-list.
- `apps/server/lib/keepling_web/auth.ex` is already in the adversarial lane's `trackedInputPaths` (added by 05-13), so a change to the boundary changes the lane's input digest and cannot report a stale verdict.

**What I am explicitly NOT claiming.** 05-13's summary made a structurally identical recommendation about MCP-01, and re-verification then found the escalation had been *narrowed*, not closed, because the credential's other authority factor was never examined. Applying that lesson to my own claim, the honest statement of residual risk is:

1. **The authority table is route-shaped, and routes are strings.** A command route renamed or re-mounted under a different path prefix falls through to `:no_agent_authority` and is refused — safe by default — but a *new* read route added to `:client_authenticated` is likewise refused, which is correct but will look like a regression to whoever adds it. The failure mode is a broken feature, not a silent widening.
2. **This closes HTTP reach. It does not re-audit `/mcp/v1` itself.** The two-layer `Scope` + `AgentScope` gate there is unchanged and was not re-probed by me.
3. **`/api/v1/mutations/:id` is mapped to `tasks.write`** on a D-49 reading (the receipt travels with the write). That is a judgement, not a probe result. No consumer exercises it today.
4. **The `resource` audience (RFC 8707) is still checked only by `KeeplingWeb.MCP.Pipeline`.** An `mcp` grant's stored audience is the MCP resource URI, so presenting it at `/api/v1` is arguably an audience violation independent of scope. I did not add that check — it would break `projects_test.exs:86`'s deliberate D-09 assertion, and it is a design question about whether the shared surface is a distinct RFC 8707 resource. **Flagging it for re-verification rather than deciding it here.**

Re-verification should probe with real PKCE grants as it did before, not read this file.

## Self-Check: PASSED

- `apps/server/lib/keepling_web/auth.ex` — FOUND
- `apps/server/test/keepling_web/agent_authorization_test.exs` — FOUND
- `tooling/mcp-lanes/adversarial.mjs` — FOUND
- `.planning/phases/KPL-05-safe-agent-access/05-14-SUMMARY.md` — FOUND
- commit `c040649` — FOUND
- commit `4d7ea21` — FOUND
- commit `bae0e23` — FOUND
- `git status` clean apart from this summary; `auth.ex` matches its committed state after both mutations were restored.
