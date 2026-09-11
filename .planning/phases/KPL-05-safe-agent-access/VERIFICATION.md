---
phase: KPL-05-safe-agent-access
verified: 2026-09-11T02:40:00Z
status: gaps_found
score: 4/5 success criteria verified
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 4/5
  previous_revision: 382419d
  this_revision: 70f9cef
  gaps_closed:
    - >-
      The client_kind escalation is CLOSED and independently re-probed. An mcp grant now receives
      exactly 401 device_authentication_required on GET /api/v1/sync, GET /api/v1/sync/bootstrap,
      GET /api/v1/device-grants and DELETE /api/v1/device-grants/:installation_id.
    - >-
      Grant administration settled without weakening either side. The new owner-session routes
      refuse an agent bearer (401 authentication_required, a DIFFERENT problem code, so the two
      credential classes are visibly distinct), and the bearer-only route keeps its
      "ignores browser cookies" assertion verbatim.
    - >-
      tooling/mcp-client/final-state.mjs no longer consumes the defect; readGrants() reads
      /api/v1/account/device-grants with the owner's session. The prior
      coincidental_reliance_items entry is resolved and removed.
    - >-
      The adversarial lane gained a real over-delivery probe (4 cases, 10 total) with a canary
      title, a final-state read-back through the owner's session, exact-401 assertions, and a
      control call proving the credential is not merely broken. It is not vacuous.
    - >-
      WINDOWS #66 carries the causality correction; #66 and #70 are marked fixed.
  gaps_remaining:
    - >-
      The escalation was NARROWED, not closed. The same agent credential still reaches the shared
      command surface with NO scope check. Proven by probe at 70f9cef, not inferred.
  regressions: []
gaps:
  - truth: >-
      SC1 — Representative MCP hosts can read bounded Inbox, Today, Upcoming, project, task, and
      search resources using least-privilege authorization.
    status: failed
    reason: >-
      The credential is still not least-privilege. 05-13 closed the client_kind half of the
      boundary; the scope half does not exist. `:client_authenticated` / `:client_mutation` admit
      an mcp grant and NEVER read its scope — `authenticate_device_grant/1` does not even assign
      `:current_scope`, so scope is structurally unavailable to those controllers. Probed live at
      70f9cef against a disposable server booted by this phase's own tooling: a grant scoped
      ["tasks.read"] ONLY captured a task through POST /api/v1/commands/capture-task (201,
      persisted, read back through the owner's session) and then trashed it through POST
      /api/v1/commands/trash-task (200; the owner's read returns 404 task_not_found and the task
      appears in /api/v1/trash) — while the SAME credential attempting the SAME operations at
      /mcp/v1 was refused `insufficient_scope` in the same run. The mirror also holds: a grant
      scoped ["tasks.write"] ONLY read GET /api/v1/search and GET /api/v1/projects with 200.
      The agent credential therefore reaches all 19 /api/v1/commands/* endpoints, roughly 15 of
      which the MCP tool set deliberately does not expose at all (trash, restore, undo,
      resolve-conflict, plan-for-today, move-today, and the five organization commands). The
      scope tag a user consents to at /oauth/authorize is decorative outside /mcp/v1.
    artifacts:
      - path: "apps/server/lib/keepling_web/router.ex"
        issue: >-
          Lines 197-241: /api/v1/mutations/:id, /projects, /projects/:organization_id/tasks,
          /api/v1/search and all 19 /api/v1/commands/* sit behind :client_authenticated /
          :client_mutation, which admit an mcp grant unconditionally.
      - path: "apps/server/lib/keepling_web/auth.ex"
        issue: >-
          authenticate_device_grant/1 (lines 178-191) assigns current_client_kind but never
          current_scope. authenticate_client/2 (line 94) calls it directly, deliberately bypassing
          authenticate_first_party_device_grant/1. The scope an agent was granted cannot be
          checked downstream because it was never carried.
      - path: "apps/server/lib/keepling_web/controllers/command_controller.ex"
        issue: >-
          No scope check on any of the 19 commands. The MCP tool layer's two-layer gate
          (KeeplingWeb.MCP.Scope + Keepling.Application.AgentScope) has no counterpart here.
      - path: "apps/server/lib/keepling/application/agent_scope.ex"
        issue: >-
          Its moduledoc calls itself "the authoritative, application-boundary scope gate" and says
          "a bug in the adapter alone cannot widen what an agent grant may do". Every one of its 8
          call sites is inside lib/keepling_web/mcp/. It is an MCP-adapter gate wearing an
          application-boundary label.
      - path: "apps/server/lib/keepling_web/auth.ex"
        issue: >-
          Lines 143-151 justify the :client_authenticated carve-out as D-09 and as
          "scope-checked and bounded". Bounded is true (cursor + limit). Scope-checked is false.
          D-09 (05-CONTEXT.md:102) says search must be a shared APPLICATION-LEVEL query rather
          than an MCP-only code path — a statement about the query layer, which
          KeeplingWeb.MCP.Resources already satisfies by calling Keepling.Application.Search
          in-process. D-09 does not authorize admitting an agent bearer to the HTTP route.
      - path: "tooling/mcp-lanes/adversarial.mjs"
        issue: >-
          OVER_DELIVERY_ROUTES (line 225) names only the four client_kind routes. No lane probes
          scope over-delivery, so the gate is green while a read-only grant writes.
      - path: "packages/contracts/openapi/keepling.yaml"
        issue: >-
          /commands/trash-task and its siblings advertise `security: DeviceBearer` with no scope
          requirement, so the published contract states the over-delivery as intended behaviour.
    missing:
      - >-
        A scope gate on the shared command surface — either carry the grant's scope through
        authenticate_device_grant/1 and require tasks.write (and tasks.bulk where the MCP tool set
        requires it) in CommandController, or refuse mcp grants on :client_authenticated /
        :client_mutation outright.
      - >-
        A decision on the ~15 commands the MCP tool set withholds but the credential reaches. If
        withholding them from agents was deliberate, the HTTP route must enforce it; if it was
        not, say so.
      - >-
        A scope over-delivery case set in the adversarial lane, mutation-tested the way 05-13
        mutation-tested the client_kind cases: a tasks.read grant must be refused on
        /api/v1/commands/*, and a tasks.write grant must be refused on the reads it was not
        granted, with a control call proving the credential still works where it should.
      - >-
        Correction of auth.ex's "scope-checked" justification and of AgentScope's
        "application-boundary" moduledoc, or the code change that makes both true.
deferred:
  - truth: >-
      SRV-02 — User receives the same domain invariants through web, desktop, iPhone, API, and
      MCP entry points.
    addressed_in: "Unowned — window #69 driver wiring; not claimed by Phase 6"
    evidence: >-
      REQUIREMENTS.md:128 states SRV-02 completes at the Phase 5 cross-adapter proof. That lane
      exists and ran (web-api and mcp legs PASS, comparison_ok=true); electron and iphone legs
      are BLOCKED on unwired drivers, not missing artifacts. Unchanged by 05-13.
coincidental_reliance_items: []
---

# Phase KPL-05: Safe Agent Access — Re-Verification Report

**Phase Goal:** External AI tools can use Keepling meaningfully without bypassing its
authorization, domain rules, or recovery model.
**Verified:** 2026-09-11 (main checkout, `70f9cef`, read-only)
**Status:** gaps_found
**Re-verification:** Yes — after 05-13 gap closure. Previous: gaps_found 4/5 at `382419d`.

## Verdict

**NOT MET.**

05-13 did what it was asked to do, and did it well. I re-probed all four routes myself against a
disposable server booted from this phase's own tooling: `/api/v1/sync`, `/api/v1/sync/bootstrap`,
`GET /api/v1/device-grants` and `DELETE /api/v1/device-grants/:installation_id` each answer exactly
401 to an mcp grant, and the new owner-session routes correctly refuse that same bearer with a
*different* problem code. The allow-list is the right shape, the placement on the pipeline rather
than per route is the right call, the second route rather than a pipeline swap weakens no existing
assertion, the harness no longer eats the defect it was supposed to catch, and the new
over-delivery cases have a canary, a final-state read-back and a control — they are not vacuous.
Nothing was weakened to make a test pass; the e2e assertion that changed is strictly stronger than
the unsatisfiable substring match it replaced.

What sinks the phase is that the fix closed one half of a two-part boundary and the SUMMARY's own
caveat #1 names the other half without weighing how much it carries. A credential's authority is
`client_kind × scope`. 05-13 made `client_kind` a default-deny allow-list. `scope` is not checked
anywhere outside `/mcp/v1` — it is not merely unchecked, it is not even *carried*:
`authenticate_device_grant/1` assigns `current_client_kind` and never assigns `current_scope`, so
no controller on the shared surface could check it if it wanted to.

The consequence is not theoretical and is not a narrowing of an already-narrow finding. In one
probe run, a grant scoped `["tasks.read"]` and nothing else:

- created a task through `POST /api/v1/commands/capture-task` → **201**, persisted, read back
  through the owner's session;
- **trashed** it through `POST /api/v1/commands/trash-task` → **200**; the owner's own read then
  returns `404 task_not_found` and the task appears in `/api/v1/trash`;
- was refused `insufficient_scope` at `/mcp/v1` for the identical operations, in the same run,
  with the same token.

`keepling.capture_task` and `keepling.complete_task` refuse this credential by design. The HTTP
twin of the same command accepts it. And `trash` is not even *exposed* as an MCP tool — it is one
of roughly fifteen commands the phase's tool set deliberately withholds from agents and the
credential reaches anyway.

The goal sentence names three things. Domain rules hold (the shared surface is the same
`Commands.dispatch/3`, revision-gated, closed-schema, identity-addressed). The recovery model
holds, and is *better* than it was — Trash is durable and restorable, the action is attributed to
`mcp` in the one history, and an agent can no longer revoke the owner's iPhone. Authorization does
not hold. A read-only agent writes and destroys. That is the same test that failed last time,
applied to the half of the boundary that did not get fixed.

## Rulings on the two caveats 05-13 asked a re-verifier to weigh

**Caveat 1 — "closed the client_kind boundary but NOT scope." This is the finding, not a footnote.**
05-13 frames it as a scoping choice ("the escalation was kind-shaped, not scope-shaped"). The
escalation was kind-shaped *as discovered*, because the four routes I probed last time happened to
be on the kind-gated pipeline. The underlying defect was always that an agent credential is treated
as a first-party credential once authenticated, and the scope half is the larger surface: 19
command endpoints and 4 read endpoints versus 4. I do not accept the framing, and I record that I
missed this half myself at `382419d` — it is pre-existing, not introduced by 05-13, and my previous
CHECK of MCP-02 was wrong.

**The `:client_authenticated` carve-out is NOT defensible as written.** Three separate reasons:

1. *Its stated justification is factually false.* auth.ex:147 says that surface is "scope-checked
   and bounded". Bounded is true. Scope-checked is false, and cannot be true, because the scope is
   not carried into the conn.
2. *D-09 does not say what it is cited for.* 05-CONTEXT.md:102 requires search and the project view
   to be shared application-level queries rather than MCP-only code paths, so that MCP has no
   capability the other adapters lack. `KeeplingWeb.MCP.Resources` satisfies that by calling
   `Keepling.Application.Search` / `Projects` / `TaskViews` **in-process**. D-09 is a statement
   about the query layer. It says nothing about which credential classes the HTTP route admits.
   The carve-out is an unexamined inheritance from D-49, a decision written before an agent
   credential class existed.
3. *Its stated cost is not real.* The SUMMARY says extending the refusal "would have broken
   /api/v1/search, /api/v1/projects and the shared command surface for the MCP adapter". I looked
   for the consumer and there is none. `mcp/resources.ex` and `mcp/tools.ex` call the application
   modules directly — neither makes an HTTP request. The harness does not need it either:
   `final-state.mjs` uses the owner's session for every read, and the cross-adapter `web-api` leg
   posts commands with the owner's session cookie and CSRF token, not an agent bearer. I did not
   find one code path, product or test, that requires an mcp grant on `:client_authenticated`.
   The carve-out appears to cost nothing to remove.

**Caveat 2 — "no live model was asked to attempt the escalation." Correctly disclosed, and it does
not change any verdict here.** A model-driven escalation attempt would be weaker evidence than what
exists, not stronger: the over-delivery cases drive the credential directly, which is the worst
case (a hostile host, not a well-behaved one being talked into misbehaving), and they are scored on
final state. The right complaint about the model lane is not that it did not attempt the
escalation; it is that neither it nor any other lane probes scope over-delivery *at all*, by any
driver. Fix the coverage, not the driver.

## Ruling on window #71 (the test-suite login budget)

**Acceptable as a stop-gap; masks nothing in production; the window must stay open.** I confirmed
the 50→400 change lives in `apps/server/config/test.exs` under `config :keepling,
:rate_limit_policy`, and that the production defaults are `@default_policies` inside
`lib/keepling/accounts/rate_limit.ex`, reached through `Application.get_env(:rate_limit_policy,
%{})` — which in `:prod` finds no override. No production abuse policy moved.

It is nonetheless a deferral, not a fix, and #71 says so honestly. The real defect is that
`auth_controller.ex:59` collapses `:rate_limited` into the same 401 `authentication_failed` a wrong
password gets. That collapse is *correct for a caller* — an attacker must not learn whether they
are throttled or wrong — and *wrong for a test log*, where it made four unrelated MCP tests fail on
a credential that was never wrong and let an executor report the suite green. Raising the cap buys
headroom (roughly 8x rather than 1.06x); it does not make the failure mode legible. #71's own two
suggestions (assert the login count against the cap, or emit a distinguishable error in `:test`)
are the right fixes. Leaving it open is the correct disposition.

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Bounded Inbox/Today/Upcoming/project/task/search reads using **least-privilege authorization** | ✗ FAILED | The read SURFACE is sound and the unbounded-sync falsifier is closed (re-probed: 401 on both sync routes). The CREDENTIAL is still not least-privilege: a `tasks.read`-only grant writes and trashes via `/api/v1/commands/*`; a `tasks.write`-only grant reads `/api/v1/search` and `/api/v1/projects`. Both probed live at `70f9cef`. See Gap 1. |
| 2 | Capture/update/complete/reopen exactly one task through closed schemas and stable, model-correctable errors | ✓ VERIFIED | Unchanged from `382419d` and unaffected by 05-13. `tools.ex` closed key sets, `mutation_id` idempotency, `expected_revision` gate, `errors.ex` closed vocabulary; 14 tool tests; live model refused an out-of-scope write at `/mcp/v1` (I re-observed that refusal directly in my own probe). SC2's text carries no least-privilege clause — that clause lives in MCP-02, which I am withdrawing. |
| 3 | Ambiguous matches mutate nothing; bulk/high-impact changes require a bound exact preview and explicit commit; stale previews fail atomically | ✓ VERIFIED (disclosed weakness) | `addressing.ex` is identity-only on both the MCP and the shared command surface, so no name-matching write path exists to be ambiguous with; `ambiguity_test.exs` 9 cases; `preview_commit_test.exs` 11 cases. **Disclosure:** preview/commit is a property of the MCP tool surface, not of the credential. There is no bulk endpoint on the shared command surface — every command is single-target, revision-gated, individually logged and individually recoverable — so going around the pair costs an agent N separate audited calls rather than one unbound mutation. Not enough to fail SC3; recorded so it is not read as a clean pass. |
| 4 | History shows typed actions, identities/revisions, result, actor, recovery, without private chain of thought | ✓ VERIFIED (strengthened) | `agent-access.spec.ts` now passes to completion (26/26) rather than dying at line 250, so step 5 ran for the first time in the phase. Attribution survives the shared surface: `command_controller.ex:594` takes `client_kind` from `current_client_kind`, which `authenticate_device_grant/1` assigns from the grant — so even the commands an agent reaches by over-delivery are recorded as `mcp`, not as `web`. `content_isolation_test.exs` 8 cases. |
| 5 | Deterministic, protocol, simulated-client, representative-model, adversarial suites score final state and forbidden side effects | ✓ VERIFIED (improved) | All five PASS. The prior coincidental-reliance defect is genuinely closed — `final-state.mjs:80` reads `/api/v1/account/device-grants` with `Cookie: sessionCookie`; the `deviceGrantAccessToken` parameter is gone from the module and from all six call sites. The adversarial lane went 6→10 cases with a real over-delivery probe. **Coverage note, not a failure:** every lane still probes only `client_kind` over-delivery. No lane probes scope over-delivery, which is why the gate is green while Gap 1 is live. |

**Score:** 4/5 truths verified (0 present, behavior-unverified)

Same numeral as `382419d`, and that is not a coincidence or a stall: SC1 fails on the same sentence
("least-privilege authorization") for the same class of reason (the agent credential is
over-privileged relative to the surface the phase built), on the other half of the same boundary.
No criterion regressed; no new defect was introduced by 05-13.

### Requirements Coverage

| Requirement | Recommendation | Change | Evidence |
|-------------|----------------|--------|----------|
| **MCP-01** — bounded, paginated Inbox/Today/Upcoming/project/task/search reads without direct database access | ✓ **CHECK** | **↑ was DO NOT CHECK** | The exact falsifier I raised is closed and I re-probed it myself: `GET /api/v1/sync/bootstrap` → 401 for an mcp grant, no account content in the body. Every read surface an agent can now reach is bounded and cursor-paginated (`/mcp/v1` resources: default 20 / max 50 + `Redaction.page/2`; `/api/v1/search` and `/api/v1/projects`: `{items, next_cursor}`), and none is raw database access. MCP-01's own text is satisfied. **Deliberate discrepancy:** SC1 FAILS while MCP-01 CHECKS because SC1's sentence adds "using least-privilege authorization" and MCP-01's does not. The scope weakness is real and is charged to MCP-02 below, not hidden. |
| **MCP-02** — capture/update/complete/reopen through closed semantic schemas, **least-privilege scopes**, idempotency, expected revisions, stable errors | ✗ **DO NOT CHECK** | **↓ was CHECK — I withdraw my previous recommendation** | Four of the five clauses hold and I do not dispute them. "Least-privilege scopes" is falsified by probe: a grant scoped `["tasks.read"]` captured a task (201) and trashed it (200) through `/api/v1/commands/*` while the same token was refused `insufficient_scope` at `/mcp/v1` in the same run; a grant scoped `["tasks.write"]` read `/api/v1/search` and `/api/v1/projects` (200). At `382419d` I checked MCP-02 with a disclosed thin spot — "least-privilege holds for task writes, but the credential is over-privileged outside the task surface". That disclosure was too generous: the over-privilege is *on* the task surface, via its HTTP twin. |
| **MCP-03** — ambiguous agent requests return candidate objects and perform no mutation | ✓ **CHECK** | unchanged | Unaffected by 05-13 and by Gap 1. Addressing is identity-only on both surfaces, so the shared command endpoints add no ambiguous write path. `ambiguity_test.exs` 9 cases; the live-model `under_determined_target` scenario is scored by before/after DB diff. Strongest of the five. |
| **MCP-04** — user sees which agent action occurred, affected identities/revisions, and an undo path, without private chain of thought | ✓ **CHECK** | unchanged, evidence strengthened | `agent-access.spec.ts` 26/26 passing to completion means steps 3-5 are all browser-observed against the real stack, not just steps 1-4. Attribution holds on the over-delivered surface too (`client_kind` derives from the grant), so Gap 1 does not produce invisible agent actions — it produces visible ones the user never authorized, which is an authorization defect, not a history defect. |
| **MCP-05** — bulk or destructive agent changes require an exact bound preview and explicit commit; stale commits fail atomically with zero partial writes | ✓ **CHECK** (disclosed) | unchanged | `Keepling.Application.Preview`; `preview_commit_test.exs` 11 cases; `bulk_destructive_via_preview_commit` driven by a live model; `update_stale_expected_revision` returns `refused:task_lifecycle_conflict` with `final_revision` unchanged on both live cross-adapter legs. **Disclosed:** there is no bulk endpoint on the shared command surface, so Gap 1 does not hand an agent an unbound bulk mutation; it hands it N single, revision-gated, recoverable, individually-audited ones. That is an MCP-02 least-privilege problem, and I am charging it there rather than double-counting it here. |
| **SRV-02** — same domain invariants through web, desktop, iPhone, API, and MCP entry points | ✗ **DO NOT CHECK — DEFER** | unchanged | `cross-adapter` still reports `legs_ran=2 legs_blocked=2 legs_failed=0 comparison_ok=true`; electron and iphone drivers remain unwired (window #69), unchanged by 05-13. My second SRV-02 objection — the MCP entry point delivers strictly *more* authority than the surface it fronts — is now half closed: the `client_kind` half is fixed, the `scope` half is Gap 1. |

**Recommendation: check MCP-01, MCP-03, MCP-04, MCP-05. Do not check MCP-02 (withdrawn) or SRV-02
(deferred).**

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `KeeplingWeb.Auth` `:device_grant_authenticated` | `/api/v1/sync`, `/api/v1/device-grants` | `call(conn, :authenticate_device_grant)` → `authenticate_first_party_device_grant/1` | ✓ WIRED | The pipeline atom in router.ex:24 is unchanged; the dispatch at auth.ex:19 now points the same atom at the allow-listed function. Slightly confusing naming — the router still reads `:authenticate_device_grant` — but functionally correct, and confirmed by live probe rather than by reading. |
| `@first_party_client_kinds` | `Keepling.Accounts.DeviceGrant.@client_kinds` | allow-list, default-deny | ✓ WIRED | `~w(electron iphone)` against a vocabulary of `~w(electron iphone mcp)`. A kind added later is refused until deliberately admitted. Correct shape. |
| `/api/v1/account/device-grants` | `DeviceGrantController.list_for_owner/2` | `:api, :authenticated` (+ `:mutation` on delete) | ✓ WIRED | Probed with an agent bearer: 401 `authentication_required` — a *different* problem code from the bearer route's `device_authentication_required`, so the two credential classes are distinguishable in the refusal. |
| `apps/web/src/api/keepling.ts` | `/api/v1/account/device-grants` | fetch with cookies | ✓ WIRED | Re-pointed; `agent-grant-list.test.tsx` asserts the new path; e2e step 5 exercises it end to end for the first time. |
| `KeeplingWeb.Auth` `:client_authenticated` | `/api/v1/commands/*`, `/search`, `/projects` | `authenticate_client/2` → `authenticate_device_grant/1` | ✗ MIS-WIRED | Admits an mcp grant and never carries, let alone checks, its scope. **This is Gap 1.** |
| `Keepling.Application.AgentScope` | the shared command surface | — | ✗ NOT WIRED | All 8 call sites are inside `lib/keepling_web/mcp/`. The "application-boundary gate" does not front the application boundary. |
| `KeeplingWeb.MCP.Resources` / `Tools` | `Keepling.Application.*` | in-process calls | ✓ WIRED | Relevant because it falsifies the carve-out's stated cost: the MCP adapter makes no HTTP call to `/api/v1/search`, `/api/v1/projects` or `/api/v1/commands/*`. |
| `tooling/mcp-client/final-state.mjs` | `/api/v1/account/device-grants` | owner session cookie | ✓ WIRED | The prior ⚠️ HOLLOW entry is resolved. `deviceGrantAccessToken` is gone from the module and all six call sites. |

### Behavioral Spot-Checks (my own runs, this revision)

All probes ran against a disposable PostgreSQL + Phoenix stack booted by
`tooling/mcp-client/client.mjs`'s own `bootDisposableServer`, on non-default ports (55471-55473 /
4231-4233) so the Docker container on 55432 was neither touched nor needed. Grants were obtained
through the real `/oauth/authorize` + PKCE + `/oauth/token` exchange — no hand-injected bearers.

| Behavior | Result | Status |
|----------|--------|--------|
| mcp grant → `GET /api/v1/sync` | 401 `device_authentication_required` | ✓ PASS (gap closed) |
| mcp grant → `GET /api/v1/sync/bootstrap` | 401, no account content in body | ✓ PASS (gap closed) |
| mcp grant → `GET /api/v1/device-grants` | 401 | ✓ PASS (gap closed) |
| mcp grant → `DELETE /api/v1/device-grants/<other installation>` | 401 | ✓ PASS (gap closed) |
| mcp grant → `GET /api/v1/account/device-grants` (the new owner route) | 401 `authentication_required` | ✓ PASS (no new agent path to grants) |
| mcp grant → `DELETE /api/v1/account/device-grants/<other>` | 401 `authentication_required` | ✓ PASS |
| **`tasks.read`-only grant → `POST /api/v1/commands/capture-task`** | **201 accepted, revision 1, task persisted** | ✗ **FAIL (escalation)** |
| Owner reads that task back (`GET /api/v1/tasks/:id`, session cookie) | 200, the agent-written task is really there | ✗ FAIL (confirms the write landed) |
| **`tasks.read`-only grant → `POST /api/v1/commands/trash-task`** | **200 accepted, revision 2** | ✗ **FAIL (destructive)** |
| Owner reads the trashed task back | 404 `task_not_found` — "This task is unavailable or is in Trash" | ✗ FAIL (confirms destruction; recoverable) |
| Owner `GET /api/v1/trash` | the task is present in Trash | ℹ️ recovery model intact |
| Control: same `tasks.read` grant → `keepling.capture_task` at `/mcp/v1` | refused `insufficient_scope` | ✓ the boundary exists — one surface away |
| Control: same grant → `keepling.complete_task` at `/mcp/v1` | refused `insufficient_scope` | ✓ same |
| `tasks.write`-only grant → `GET /api/v1/search` | 200 `{items, next_cursor}` | ✗ FAIL (mirror direction) |
| `tasks.write`-only grant → `GET /api/v1/projects` | 200 `{items, next_cursor}` | ✗ FAIL (mirror direction) |

The two controls matter: they rule out "the credential is simply broken/revoked" and they prove the
product knows how to refuse this exact credential for this exact operation — it just does not do it
on the HTTP twin.

**Credential handling:** I did not run the representative-model lane and did not read, echo, copy
or record `.env.local` in any form. The requester independently ran `pnpm run verify:mcp:model`
(PASS, cases=6) and `pnpm run verify:mcp:phase` (lanes=6 failed=0 blocked=1) at this revision; I
accepted those runs rather than repeating them, because my probes test the boundary more directly
than any lane currently does.

### Probe Execution

| Probe | Command | Result | Status |
|-------|---------|--------|--------|
| Full MCP phase gate | `KEEPLING_E2E_POSTGRES_PORT=55442 pnpm run verify:mcp:phase` | `lanes=6 failed=0 blocked=1`; deterministic 183, protocol 2, simulated-client 9, adversarial 10, representative-model 6 PASS; cross-adapter BLOCKED | PASS with disclosed BLOCK (requester's run, accepted) |
| Adversarial over-delivery mutation test | re-admit `mcp` to `@first_party_client_kinds`, re-run lane | FAIL: `over_delivery case "sync_pull": GET /api/v1/sync answered 200 for an mcp grant; expected 401`; file restored | PASS — the new cases have teeth |
| Phase-1 gate | `KEEPLING_E2E_POSTGRES_PORT=55442 pnpm test:phase-1` | 319 Elixir, 169 web unit, 26/26 Playwright | PASS (requester's run, accepted) |
| Independent escalation probe | `node /tmp/kplprobe/probe*.mjs` (3 disposable stacks, real PKCE grants) | see the spot-check table | ✗ FAILED on scope |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `apps/server/lib/keepling_web/auth.ex` | 94, 178-191 | Authorization input silently dropped — `current_scope` is never assigned on the shared-surface path | 🛑 Blocker | Scope cannot be enforced downstream because it is not carried. This is Gap 1's mechanism. |
| `apps/server/lib/keepling_web/controllers/command_controller.ex` | all 19 actions | Missing scope gate on a surface reachable by an agent credential | 🛑 Blocker | A read-only agent writes and destroys. |
| `apps/server/lib/keepling_web/auth.ex` | 143-151 | Comment asserts a property the code does not have ("scope-checked") and cites a decision that does not say it (D-09) | ⚠️ Warning | A reader auditing this boundary is told it is closed. It is the load-bearing justification for the carve-out. |
| `apps/server/lib/keepling/application/agent_scope.ex` | 1-14 | Module documents itself as "the authoritative, application-boundary scope gate"; every call site is in the MCP adapter | ⚠️ Warning | The moduledoc's own promise ("a bug in the adapter alone cannot widen what an agent grant may do") is false — there is only the adapter layer. |
| `packages/contracts/openapi/keepling.yaml` | `/commands/*` | `security: DeviceBearer` with no scope requirement on 19 command paths | ⚠️ Warning | The published contract documents the over-delivery as intended. |
| `apps/server/lib/keepling_web/router.ex` | 24 | Pipeline plugs `:authenticate_device_grant` but the dispatch resolves to `authenticate_first_party_device_grant/1` | ℹ️ Info | Correct, but the router no longer reads as what it does. Renaming the atom would make the allow-list visible at the mount point. |
| `tooling/mcp-lanes/protocol.mjs` | evidence line | `cases=2` hardcoded rather than counted | ℹ️ Info | Pre-existing, recorded at `382419d`, non-gating, unaddressed (correctly out of 05-13's scope). |

No unreferenced `TBD`/`FIXME`/`XXX` debt markers in the files 05-13 modified.

### What 05-13 Got Right

Recorded deliberately, because the gap above should not read as a dismissal of the work:

- **The allow-list is the right primitive.** `~w(electron iphone)` against a three-value vocabulary
  defaults to DENY for anything added later. A `!= "mcp"` denial would have defaulted to ALLOW.
- **Pipeline placement over per-route checks** is correct for the same reason, and the reasoning is
  written into the code where the next person will find it.
- **Two routes instead of a widened pipeline** settled window #66 without weakening the
  "ignores browser cookies" assertion or opening a new agent path to the owner's grants. I probed
  both directions and both refusals hold, with distinguishable problem codes.
- **The harness was taken off the defect** rather than the defect being left to keep the lane green
  — the outcome I was least confident would happen.
- **The over-delivery cases are genuinely non-vacuous**: exact 401 (not `!= 200`, so a deleted
  route fails), a canary title written through the real MCP surface, a final-state read-back
  through the owner's session, and a control call proving the credential is not merely broken.
- **`auth.ex` and `router.ex` were added to `trackedInputPaths`** unprompted, closing a stale-digest
  hole in the gate's own evidence.
- **The e2e fix is strictly stronger than what it replaced** (an unsatisfiable `getByText`
  substring match), and I confirmed no assertion anywhere in the diff was deleted or loosened.
- **The SUMMARY disclosed the scope gap itself** and explicitly asked a re-verifier to rule on it.
  That disclosure is why this report could go straight to the probe.

### Gaps Summary

One gap, one decision, and it is the other half of the decision 05-13 made.

An agent credential's authority is `client_kind × scope`. 05-13 turned `client_kind` into a
default-deny allow-list and proved it four ways. `scope` remains unenforced and, worse, uncarried:
`authenticate_device_grant/1` assigns the client kind and drops the scope on the floor, so the
nineteen shared command endpoints and four shared read endpoints could not check it even if they
tried. `Keepling.Application.AgentScope` — the module whose own docstring claims to be the
authoritative application-boundary gate so that "a bug in the adapter alone cannot widen what an
agent grant may do" — is called from eight places, all of them inside the MCP adapter.

So a grant the user consented to as read-only captures tasks, edits them, completes them, reopens
them and trashes them, plus roughly fifteen commands the phase's tool set deliberately never
exposed to agents at all. The same token, one route over, is told `insufficient_scope`.

The carve-out that permits this is documented as deliberate. I do not think it survives contact
with its own justification: the comment claims the surface is scope-checked (it is not), cites D-09
(which is a statement about sharing the *query*, not about admitting an agent *bearer*, and which
`MCP.Resources` already satisfies by calling the application modules in-process), and asserts a
cost — breaking search, projects and the command surface for the MCP adapter — that I could not
find a single consumer for, in the product or in the harness.

The fix is plausibly small: either carry `current_scope` through `authenticate_device_grant/1` and
require `tasks.write` (and `tasks.bulk` where the tool set requires it) in `CommandController`, or
refuse `mcp` on `:client_authenticated` / `:client_mutation` the same way `:device_grant_authenticated`
now refuses it. The second is one line and, on the evidence I gathered, breaks nothing. Either way,
the gate needs scope over-delivery cases built and mutation-tested exactly the way 05-13 built and
mutation-tested the kind ones — because that lane is currently green while a read-only credential
destroys tasks, which is the same blind spot in a new coordinate.

SRV-02 is unchanged and still defers on window #69's driver wiring. Window #71 is an acceptable
stop-gap that masks nothing in production and should stay open.

---

_Verified: 2026-09-11 at `70f9cef`_
_Verifier: Claude (gsd-verifier), re-verification after 05-13_
