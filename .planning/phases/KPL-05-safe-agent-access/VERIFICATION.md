---
phase: KPL-05-safe-agent-access
verified: 2026-09-11T03:12:47Z
status: passed
score: 5/5 success criteria verified
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 4/5
  previous_revision: 70f9cef
  this_revision: b334ecc
  gaps_closed:
    - >-
      The SCOPE half of the agent boundary is CLOSED and independently re-probed with real PKCE
      grants. `authenticate_device_grant/1` now assigns `:current_scope` on every surface it
      authenticates, and `authorize_agent/1` gates `:client_authenticated` / `:client_mutation`
      for agent kinds through `Keepling.Application.AgentScope` -- its first call site outside
      `lib/keepling_web/mcp/`.
    - >-
      Probed the FULL 19-command matrix against four grants (read / write / bulk / all three).
      A `tasks.read`-only grant is refused 403 `insufficient_scope` on all 19. A `tasks.bulk`-only
      grant is refused on all 19. `tasks.write` reaches EXACTLY the six the closed tool set
      reaches and is refused on the other thirteen. The mirror holds: `tasks.write` is refused
      403 on `/api/v1/search`, `/api/v1/projects` and `/api/v1/projects/:id/tasks`.
    - >-
      Not a blanket denial. Controls in the same run: a `tasks.write` grant captured over HTTP
      (201, persisted); a `tasks.read` grant's `/api/v1/search` body is BYTE-IDENTICAL to the
      owner's session body for the same query, so D-09's one shared query survives intact.
    - >-
      The destructive vocabulary is unreachable in one step by any agent scope. `trash-task`
      answered 403 for read, write, bulk AND all-three. `keepling.trash_task` does not exist as
      an MCP tool (`unknown_tool`). The only agent path to trash is preview + commit under
      `tasks.bulk`, and that path's token refuses a forged token, a tampered token, a
      `tasks.read` committer, a `tasks.write` committer, and a stale re-commit.
    - >-
      The kind half from 05-13 did not regress: `/api/v1/sync`, `/api/v1/sync/bootstrap`,
      `GET /api/v1/device-grants`, `DELETE /api/v1/device-grants/:id` all answer 401 to an
      all-scopes mcp grant, and `/api/v1/account/device-grants` answers a distinguishable 401.
    - >-
      `auth.ex`'s false "scope-checked and bounded" justification is corrected in place, naming
      what was true, what was false, and why it was structurally impossible.
  gaps_remaining: []
  regressions: []
deferred:
  - truth: >-
      SRV-02 -- User receives the same domain invariants through web, desktop, iPhone, API, and
      MCP entry points.
    addressed_in: "Unowned -- window #69 driver wiring; not claimed by Phase 6"
    evidence: >-
      REQUIREMENTS.md:128 states SRV-02 completes at the Phase 5 cross-adapter proof. That lane
      exists and runs (web-api and mcp legs PASS, comparison_ok=true); electron and iphone legs
      are BLOCKED on unwired drivers, not missing artifacts. Unchanged by 05-14.
disclosures:
  - id: "receipt-scope-inversion"
    severity: warning
    finding: >-
      `GET /api/v1/mutations/:id` is mapped to `tasks.write`, and the receipt it returns carries
      the FULL task snapshot. Probed at b334ecc: a `tasks.write`-ONLY agent grant read the
      receipt -- including the task title -- of a mutation issued by the OWNER'S BROWSER SESSION,
      while a `tasks.read` grant is refused 403 on the same route. The scope that conveys read
      authority cannot read; the scope that conveys write authority can. Not enumerable (the
      mutation id is a client-chosen UUIDv4 and no agent-reachable surface -- MCP resources,
      tools, or search -- discloses another client's mutation ids; an unknown id answers 404), so
      this is a scope-mapping defect with a high precondition, not a live escalation. 05-14 flagged
      the mapping itself as residual risk #3 ("a judgement, not a probe result"); it is now a
      probe result.
    recommendation: >-
      Open a window. Either require `tasks.read` in addition to `tasks.write` for the receipt
      route, or bind receipt reads to the grant that issued the mutation (which is what D-49's
      "read and write move together" actually argues for). Small, local to `agent_authority/2`
      plus `Commands.lookup_result/3`.
  - id: "rfc8707-audience-not-enforced-outside-mcp"
    severity: info
    finding: >-
      05-14's residual risk #4, ruled on: NOT a defect. Every `mcp` grant is audience-bound to
      `${origin}/mcp/v1` (the controller REQUIRES `resource` to equal the canonical URI for
      client_kind `mcp`), and only `KeeplingWeb.MCP.Pipeline` checks it. Presenting the token at
      `/api/v1` is therefore an audience mismatch by the literal RFC 8707 reading. But the threat
      RFC 8707 exists to stop -- a token minted for resource A being replayed at an unrelated
      resource server B -- has no instance here: same origin, same server, same authorization
      server, same singleton account, and since b334ecc the HTTP authority is a default-deny
      allow-list that mirrors the closed MCP tool set exactly. The token buys nothing at
      `/api/v1` that it does not already buy at `/mcp/v1`. This is a naming/spec-conformance
      inconsistency, not a privilege boundary.
    recommendation: >-
      Do NOT add an audience check at `:client_authenticated` -- it would be option A under a
      different name, and it buys no authority reduction. Record a decision (the shared `/api/v1`
      surface is the same RFC 8707 resource, identified for discovery by its `/mcp/v1` URI), or,
      if strict conformance is wanted later, widen the declared resource rather than narrowing the
      credential. Cost of the strict closure is stated in the report body.
  - id: "preview-token-is-account-bound-not-grant-bound"
    severity: info
    finding: >-
      Probed: a preview token minted by bulk grant A was COMMITTED by a different `tasks.bulk`
      grant B of the same account (`commit_by_other_bulk_grant_same_account` -> committed; the
      owner's subsequent read of the target returns 404 task_not_found). The binding is
      `account_id`, not `grant_id`, which `Preview`'s own moduledoc states plainly
      ("account-bound"), so this is documented behaviour rather than a false claim. Exploiting it
      requires one agent to hand another agent an opaque token both of which already hold
      `tasks.bulk` on the same account -- no privilege is gained.
    recommendation: "No action. Recorded so a future reader does not mistake it for a finding."
coincidental_reliance_items: []
---

# Phase KPL-05: Safe Agent Access -- Third Verification Report

**Phase Goal:** External AI tools can use Keepling meaningfully without bypassing its
authorization, domain rules, or recovery model.
**Verified:** 2026-09-11 (main checkout, `b334ecc`, read-only)
**Status:** passed
**Re-verification:** Yes -- third pass, after 05-14. Previous: gaps_found 4/5 at `70f9cef`
(scope half open); before that gaps_found 4/5 at `382419d` (kind half open).

## Verdict

**MET WITH DISCLOSURE.**

I went looking for a third axis and did not find one. Both halves of `client_kind x scope` are now
default-deny, and I proved it by probe rather than by reading: 19 commands x 4 grants, 4 read
routes x 4 grants, the destructive vocabulary from every scope, the preview/commit token from four
wrong credentials, six path-normalization variants, a method-override attempt, eleven session-only
routes with an agent bearer, and the four 05-13 routes re-probed for regression. Every refusal is an
exact status with an `insufficient_scope` body; every permission is matched by a control proving the
credential still works where its grant says it should.

Two things are disclosed rather than found. One is a real (low-severity) scope-mapping inversion on
`/api/v1/mutations/:id` that I discovered by probe and that 05-14 had itself flagged as an unprobed
judgement. The other is the RFC 8707 audience question, which I rule a design inconsistency and not
a defect. Neither blocks the goal; both are written up with a recommended disposition below.

## Ruling on 05-14's shape decision (option B over option A)

**The judgement was right, and its stated reason is partly overstated.**

Right, for three reasons I checked independently:

1. **It found a consumer I claimed did not exist, and it was correct to say so.** I wrote at
   `70f9cef` that there was "not one code path, product or test" requiring an `mcp` grant on
   `:client_authenticated`. `apps/server/test/keepling/application/projects_test.exs:85` is one,
   and it is deliberate -- the HTTP-level byte-identity assertion across a browser session, an
   electron bearer and an `mcp` bearer. I was wrong; the executor was right to re-check rather than
   inherit, and right to say so out loud.
2. **Option B produces a property option A cannot.** A removes the surface; B bounds the
   credential. Only B creates the `auth.ex -> agent_scope.ex` link the plan's `key_links` demanded,
   and only B makes `AgentScope`'s "application-boundary" moduledoc true -- the exact complaint
   window #72 raised. After A, `AgentScope` would still have been an adapter-local module wearing
   an application-boundary label.
3. **B is not weaker than A in practice.** I probed for the difference and could not create one.
   Everything A would have refused wholesale, B also refuses -- by scope, by the route allow-list,
   or by both -- and B additionally keeps D-09's one shared query provably one query (my probe
   confirmed byte-identity between the `tasks.read` grant's `/api/v1/search` body and the owner's).

Overstated: "refusing agents there would destroy evidence for SRV-02". It would have forced
`projects_test.exs:85` to be **inverted**, not deleted -- the cross-adapter invariant could still
have been asserted between the session and an electron grant, plus the MCP adapter's in-process
result. That is weaker evidence, not no evidence. The decisive argument for B is #2 and #3, not the
test. The conclusion stands; the reasoning leaned on the softest of its three legs.

## Ruling: was keeping trash / restore / undo out of the allow-list correct?

**Correct, and it breaks no legitimate agent flow. This is the best decision in the plan.**

It is a Rule-2 deviation the plan did not ask for, and without it the fix would have been
incomplete in a way the plan's own truths would not have caught: `tasks.write` carries
`tasks.write` and `tasks.bulk` carries `tasks.bulk`, so a scope-only check waves BOTH through to
`POST /api/v1/commands/trash-task` -- a one-step, unpreviewed, drift-unchecked trash that routes
around the entire D-17/D-18 safeguard. The executor found this by reading
`Preview.@destructive_commands` rather than by being told.

No flow is broken, verified three ways:

- `keepling.trash_task` **does not exist** as an MCP tool -- probed, `unknown_tool`. An agent never
  had a one-step trash on any surface, so nothing regressed.
- The designed path still works: a `tasks.bulk`-ONLY grant minted a preview for `trash_task` and
  committed it; the owner's subsequent read returns 404 `task_not_found` and the task is in
  `/api/v1/trash`. Destructive agent action remains possible, previewed, revision-bound and
  recoverable.
- `preview_bulk_change` refuses a non-destructive command (`edit_task` -> invalid arguments), so the
  two-step cannot be used as a general-purpose bypass of the write scope either.

05-14's residual risk #1 (a new route added to `:client_authenticated` later is refused and "will
look like a regression") is the correct trade: the failure mode is a visibly broken feature, not a
silent widening. Accepted as designed.

## Ruling: the RFC 8707 `resource` audience (05-14 residual #4)

**A design question, not a defect. Do not close it by refusing the credential.**

The facts are as 05-14 states: `DeviceGrantController.validate_resource/2` REQUIRES `resource ==
Metadata.resource_uri()` for every `mcp` authorization, so every agent token is audience-bound to
`${origin}/mcp/v1`; `MCP.Pipeline.check_audience/1` is the only enforcement point; `/api/v1`
enforces nothing.

What RFC 8707 buys is protection against a token minted for resource A being replayed at an
unrelated resource server B. There is no B here: same origin, same Phoenix endpoint, same
authorization server, one singleton account -- and, since `b334ecc`, the HTTP authority is a
default-deny allow-list that mirrors the closed tool set one-for-one. I probed for authority the
token holds at `/api/v1` that it does not hold at `/mcp/v1` and found none; the mapping is a
mirror by construction and by test. An audience check there would refuse traffic that is already
scope-bounded to exactly what the audience-checked surface permits. That is option A wearing a
spec citation.

**If it is closed anyway, the cost is:** (a) `projects_test.exs:85`'s HTTP-level D-09 assertion
must be inverted; (b) `AgentScope`'s only non-adapter call site disappears and window #72's
original complaint silently returns; (c) the OpenAPI contract's `DeviceBearer` security scheme on
`/search`, `/projects` and the command paths becomes a lie for one of its three credential classes.
The cheaper honest alternative, if strict conformance is ever wanted, is to widen the DECLARED
resource (or list `/api/v1` in the RFC 9728 metadata) rather than narrow the credential -- which
costs a metadata change and a migration of stored `resource` values, not a boundary change.

Recommendation: record a decision to that effect and close the residual. Not a gap.

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Bounded Inbox/Today/Upcoming/project/task/search reads using **least-privilege authorization** | ✓ VERIFIED | The read surface was already bounded and cursor-paginated; what failed twice was the credential. Both axes now hold under probe: kind (401 on all four first-party routes) and scope (`tasks.write`/`tasks.bulk` refused 403 on `/search`, `/projects`, `/projects/:id/tasks`; `tasks.read` admitted, and its `/api/v1/search` body byte-identical to the owner's). The `tasks.read` grant is refused on all 19 commands. **Disclosure:** the `/api/v1/mutations/:id` receipt mapping (see disclosures) is a scope inversion on the write side, not on the read surface SC1 names. |
| 2 | Capture/update/complete/reopen exactly one task through closed schemas and stable, model-correctable errors | ✓ VERIFIED | Unchanged and now true of the HTTP twin as well: `tasks.write` reaches exactly `capture-task`, `edit-task`, `edit-task-dates`, `assign-task-organizations`, `complete-task`, `reopen-task` and is refused 403 on the other thirteen. Re-observed live: `keepling.capture_task` refused `insufficient_scope` for a `tasks.read` grant, accepted for `tasks.write`. |
| 3 | Ambiguous matches mutate nothing; bulk/high-impact changes require a bound exact preview and explicit commit; stale previews fail atomically | ✓ VERIFIED (strengthened) | The prior disclosure ("preview/commit is a property of the tool surface, not of the credential") is now closed: the HTTP route around the two-step is refused for every agent scope including `tasks.bulk`. Token probed from four wrong angles -- forged (`preview_invalid`), tampered (`preview_invalid`), `tasks.read` committer (`insufficient_scope`), `tasks.write` committer (`insufficient_scope`), re-commit after application (`preview_stale`). `addressing.ex` identity-only on both surfaces. |
| 4 | History shows typed actions, identities/revisions, result, actor, recovery, without private chain of thought | ✓ VERIFIED | Unchanged from `70f9cef`. Attribution derives `client_kind` from the grant; Trash is durable and the owner's `/api/v1/trash` listed the agent-trashed task in my own run, with `trashed_at` and revision intact. `content_isolation_test.exs` 8 cases; `agent-access.spec.ts` 26/26. |
| 5 | Deterministic, protocol, simulated-client, representative-model, adversarial suites score final state and forbidden side effects | ✓ VERIFIED (improved) | `lanes=6 failed=0 blocked=1` (requester's run at this revision): deterministic 183, protocol 2, simulated-client 9, adversarial **16**, representative-model 6 against a LIVE model; `cross-adapter` BLOCKED on window #69 only. The prior coverage complaint is closed: the adversarial lane now probes scope over-delivery (6 cases) as well as kind (4), each asserting exactly 403 with an `insufficient_scope` body, scored on final state read back through the OWNER's session, with a leak check on the refusal body and two controls that fail if the boundary degenerates into a blanket denial. |

**Score:** 5/5 truths verified (0 present, behavior-unverified)

### Requirements Coverage

| Requirement | Recommendation | Change | Evidence |
|-------------|----------------|--------|----------|
| **MCP-01** -- bounded, paginated reads without direct database access | ✓ **CHECK** | unchanged | Re-probed at `b334ecc`: `/api/v1/sync/bootstrap` 401 for an all-scopes mcp grant, and the eleven session-only read routes (`/inbox`, `/today`, `/upcoming`, `/completed`, `/trash`, `/organizations`, `/views/inbox`, `/session`, `/sessions`, `/tasks/:id`, `/tasks/:id/activity`) each answer 401 `authentication_required` to an agent bearer. Every read an agent can reach is bounded and cursor-paginated; none is raw database access. |
| **MCP-02** -- closed semantic schemas, **least-privilege scopes**, idempotency, expected revisions, stable errors | ✓ **CHECK** | **↑ was DO NOT CHECK -- I restore my recommendation** | The falsifier I raised is closed on evidence of the same kind that produced it. Full matrix probed: `tasks.read` refused on 19/19 commands; `tasks.bulk` refused on 19/19; `tasks.write` admitted on exactly the six the tool set reaches; `tasks.write`/`tasks.bulk` refused on all three shared reads; controls green in the same run. **Disclosed:** `/api/v1/mutations/:id` requires `tasks.write` and returns a full task snapshot, so a write-only grant can read content for a mutation id it already knows (including one issued by the owner's browser). Not enumerable, not reachable through any agent surface. It is a scope-mapping wrinkle on a receipt route, not a restatement of the escalation MCP-02 was withdrawn for -- I am checking the box and recording the wrinkle as a window rather than holding an otherwise-closed requirement hostage to it. |
| **MCP-03** -- ambiguous agent requests return candidates and mutate nothing | ✓ **CHECK** | unchanged | Identity-only addressing on both surfaces; `ambiguity_test.exs` 9 cases; live-model `under_determined_target` scored by DB diff. The new HTTP gate adds no name-matching path (the refused commands never reach a decoder). |
| **MCP-04** -- user sees which agent action occurred, identities/revisions, undo path, no private chain of thought | ✓ **CHECK** | unchanged | Attribution unchanged and now applies to a strictly smaller surface. My own run: a bulk-committed trash left the task in the owner's `/api/v1/trash` at revision 2 with `trashed_at` set. |
| **MCP-05** -- bulk/destructive changes require an exact bound preview and explicit commit; stale commits fail atomically | ✓ **CHECK** | **disclosure removed** | The `70f9cef` disclosure was that preview/commit bound the tool surface but not the credential -- an agent could go around it with N single HTTP commands. That route is gone: `trash-task`, `restore-task` and `undo-task` answer 403 to read, write, bulk and all-three. The two-step itself survived forged, tampered, wrong-scope and replayed commits in my probe. Strongest it has been. |
| **SRV-02** -- same domain invariants through web, desktop, iPhone, API, MCP | ✗ **DO NOT CHECK -- DEFER** | unchanged | `cross-adapter` still `legs_ran=2 legs_blocked=2 legs_failed=0 comparison_ok=true`; electron and iphone drivers unwired (window #69). My second SRV-02 objection -- the MCP entry point delivering MORE authority than the surface it fronts -- is now fully closed on both axes, so the only thing left is driver wiring. |

**Recommendation: check MCP-01, MCP-02 (restored), MCP-03, MCP-04, MCP-05. Do not check SRV-02
(deferred to window #69).**

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `KeeplingWeb.Auth.authenticate_device_grant/1` | the conn | `assign(:current_scope, authenticated.scope)` | ✓ WIRED | The root defect is fixed at the root: the scope is now present on EVERY surface a grant authenticates, not only under `MCP.Pipeline`. Confirmed behaviourally -- the 403s are scope-discriminating, not blanket. |
| `KeeplingWeb.Auth.authorize_agent/1` | `Keepling.Application.AgentScope.require/2` | `:client_authenticated` / `:client_mutation` | ✓ WIRED | AgentScope's first call site outside `lib/keepling_web/mcp/`. Its "application-boundary gate" moduledoc is now true of the application. The `70f9cef` ✗ NOT WIRED entry is resolved. |
| `@agent_client_kinds` | `DeviceGrant.@client_kinds` | keyed allow-list | ✓ WIRED | `~w(mcp)` against `~w(electron iphone mcp)`. Browser sessions carry no `current_client_kind`; first-party grants carry no scope. Both leave the gate untouched -- pinned by the fifth server case AND probed (electron/iphone unaffected paths are covered by `agent_authorization_test.exs:228`). |
| `agent_authority/2` route table | `mcp/tools.ex` closed tool set | default-deny mirror | ✓ WIRED | Verified route-by-route against the tool set: 6 writable commands + 3 reads + the receipt. Thirteen commands refused. A path Phoenix routes but the table does not name falls through to `:no_agent_authority` -> 403. |
| `KeeplingWeb.Auth` `:device_grant_authenticated` | `/api/v1/sync`, `/device-grants` | `@first_party_client_kinds` | ✓ WIRED | 05-13's half re-probed at this revision: 401 on all four. No regression. |
| `tooling/mcp-lanes/adversarial.mjs` | the boundary | 16 cases, 2 mutations | ✓ WIRED | Kind + scope over-delivery, exact-status assertions, owner-session final-state scoring, leak checks, two controls. The requester independently reproduced mutation 1 (`@agent_client_kinds` -> `~w()`) and observed the exact failure text; `auth.ex` matches its committed state. |

### Behavioural Spot-Checks (my own probes, this revision)

Two disposable PostgreSQL + Phoenix stacks booted by `tooling/mcp-client/client.mjs`'s own
`bootDisposableServer` on non-default ports (55481/4241, 55482/4242), so the Docker container on
55432 was neither touched nor needed. All grants obtained through the real `/oauth/authorize` +
S256 PKCE + `/oauth/token` exchange -- no hand-injected bearers.

| Probe | Result | Status |
|-------|--------|--------|
| 19 commands x `tasks.read` grant | 403 `insufficient_scope` on all 19 | ✓ PASS |
| 19 commands x `tasks.bulk` grant | 403 on all 19 | ✓ PASS |
| 19 commands x `tasks.write` grant | 400 (reached the decoder) on exactly the 6 allow-listed; 403 on the other 13 | ✓ PASS |
| 19 commands x `read+write+bulk` grant | identical to `tasks.write` -- scope union buys nothing extra | ✓ PASS |
| `/search`, `/projects`, `/projects/:id/tasks` x `tasks.read` | 200 / 200 / 404 (admitted, org absent) | ✓ PASS (control) |
| same three x `tasks.write` and x `tasks.bulk` | 403 on all six | ✓ PASS |
| `POST /commands/trash-task` x read, write, bulk, all | **403 for every one**, `insufficient_scope` body | ✓ PASS |
| `keepling.trash_task` MCP tool | `unknown_tool` -- no direct destructive tool exists | ✓ PASS |
| `tasks.bulk` preview `trash_task` -> commit | committed; owner's read 404 `task_not_found`; task present in `/api/v1/trash` | ✓ PASS (design path intact + recoverable) |
| commit with forged token / tampered token | `preview_invalid` / `preview_invalid` | ✓ PASS |
| commit by `tasks.read` / by `tasks.write` | `insufficient_scope` / `insufficient_scope` | ✓ PASS |
| commit re-issued after application | `preview_stale` | ✓ PASS |
| commit by a DIFFERENT `tasks.bulk` grant, same account | **committed** | ℹ️ documented (see disclosures) |
| preview with a non-destructive command (`edit_task`) | invalid arguments -- the two-step is not a general write bypass | ✓ PASS |
| `tasks.write`-only grant reads the OWNER'S mutation receipt by id | **200 with the full task snapshot, title included** | ⚠️ WARNING (see disclosures) |
| `tasks.read` grant reads the same receipt | 403 `insufficient_scope` | ⚠️ the inversion |
| `/sync`, `/sync/bootstrap`, `GET+DELETE /device-grants` x all-scopes grant | 401 `device_authentication_required` | ✓ PASS (no kind regression) |
| `/account/device-grants` x agent bearer | 401 `authentication_required` (distinguishable code) | ✓ PASS |
| 11 session-only read routes x agent bearer | 401 on all 11 | ✓ PASS |
| Path variants on `trash-task`: trailing slash, `//`, `/./`, `/../`, `%2D` | 403 on all five (normalized, then default-denied) | ✓ PASS |
| `trash-task` uppercased | 404 (no route) | ✓ PASS |
| `?_method=GET` override on `trash-task` | 403 -- `Plug.MethodOverride` cannot synthesize a GET, and `Plug.Head` only maps HEAD->GET onto routes that already exist | ✓ PASS |
| MCP `resources/read keepling://inbox` x `tasks.write` | `insufficient_scope` | ✓ PASS (adapter unchanged) |
| MCP `keepling.capture_task` x `tasks.read` | `insufficient_scope` | ✓ PASS |
| Control: `tasks.write` grant `POST /commands/capture-task` | 201, persisted, snapshot returned | ✓ PASS (not a blanket denial) |
| Control: `tasks.read` grant `/api/v1/search` vs owner session | **byte-identical bodies** | ✓ PASS (D-09 intact) |

**Additional axes examined and cleared (read, then probed where reachable):**

- **Scope widening at token refresh.** `POST /oauth/token` with `grant_type=refresh_token` accepts
  EXACTLY `~w(grant_type refresh_token)` under `exact_keys/2` -- no `scope` and no `resource`, so a
  refresh cannot widen either. Authorization-code exchange likewise takes no `scope`.
- **Client-kind forgery via Dynamic Client Registration.** `DeviceGrant.resolve_client/1` maps every
  registered (DCR) client id to `"mcp"` and nothing else, so a registered client cannot obtain a
  first-party `electron`/`iphone` grant and step around `@agent_client_kinds`.
- **Redirect hijack to mint a first-party grant.** `/oauth/authorize` auto-redirects on the owner's
  session with no consent step, but `validate_redirect/3` requires an exact match against the
  per-kind allow-list, and `electron`/`iphone` are private-use `keepling://` schemes while `mcp` is
  a path on Keepling's own origin. No web-reachable redirect target exists. Pre-existing, out of
  this phase's scope, recorded because I probed for it.
- **`CommandDiscriminator` dispatch confusion.** It never routes on the body's `type`; it verifies
  the declaration against the URL's last path segment and 400s on disagreement, and it runs AFTER
  `authorize_agent/1` in `:client_mutation`. A body claiming `trash_task` cannot reach a different
  controller action.

### Probe Execution

| Probe | Command | Result | Status |
|-------|---------|--------|--------|
| Full MCP phase gate | `KEEPLING_E2E_POSTGRES_PORT=55442 pnpm run verify:mcp:phase` | `lanes=6 failed=0 blocked=1`; adversarial 16, representative-model 6 (live model); cross-adapter BLOCKED on #69 | PASS with disclosed BLOCK (requester's run, accepted) |
| Phase-1 gate | `KEEPLING_E2E_POSTGRES_PORT=55442 pnpm test:phase-1` | exit 0; 324/324 Elixir, 169 web unit, 26/26 e2e | PASS (requester's run, accepted) |
| Adversarial mutation test | empty `@agent_client_kinds`, re-run lane | FAIL: `scope_over_delivery case "read_grant_captures": POST /api/v1/commands/capture-task answered 201 for an mcp grant scoped tasks.read; expected 403`; restored | PASS -- the scope cases have teeth (requester reproduced independently) |
| Independent boundary probe, pass 1 | `node /tmp/kplprobe3/p1.mjs` (disposable stack, real PKCE grants) | 4x19 command matrix, 4x4 read matrix, kind regression, path variants, MCP spot checks | ✓ all as tabulated |
| Independent boundary probe, pass 2 | `node /tmp/kplprobe3/p2.mjs` (disposable stack, real PKCE grants + owner CSRF session) | preview/commit token abuse, receipt disclosure, byte-identity control | ✓ one WARNING (receipt), rest clean |

**Credential handling:** I did not run the representative-model lane and did not read, echo, copy or
record `.env.local` in any form. The requester independently ran it at this revision (6 cases, live
model, credential present). Accepted.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `apps/server/lib/keepling_web/auth.ex` | `agent_authority("GET", ["api","v1","mutations",_])` | A read route mapped to the WRITE scope, returning full content | ⚠️ Warning | The receipt-scope inversion above. Low reachability, real inversion. |
| `packages/contracts/openapi/keepling.yaml` | `/commands/*`, `/search`, `/projects` | `security: DeviceBearer` still carries no scope requirement | ⚠️ Warning | The published contract does not state the authority the server now enforces. Downgraded from `70f9cef` (it no longer documents an escalation as intended; it merely under-documents a boundary). Worth a follow-up when the contract convention gains auth-problem responses. |
| `apps/server/lib/keepling_web/router.ex` | 24 | Pipeline plugs `:authenticate_device_grant`; the dispatch resolves to `authenticate_first_party_device_grant/1` | ℹ️ Info | Unchanged from `70f9cef`. Correct, but the router does not read as what it does. |
| `tooling/mcp-lanes/protocol.mjs` | evidence line | `cases=2` hardcoded rather than counted | ℹ️ Info | Pre-existing, non-gating, unaddressed across three passes. Correctly out of scope each time. |

No unreferenced `TBD`/`FIXME`/`XXX` markers in the files 05-14 modified. No assertion anywhere in
the `70f9cef..b334ecc` diff was deleted or loosened -- the only deletions are the corrected comment
text, the two `call/2` clauses that gained `|> authorize_agent()`, and one lane evidence line that
gained a counter.

### What 05-14 Got Right

- **It disobeyed the instruction correctly.** Asked to confirm a no-consumer finding it was being
  handed, it actually searched, found the counter-example, and changed shape on the evidence
  instead of executing the cheaper plan. Both prior passes (mine and the requester's) had concluded
  the opposite; it was right and we were wrong.
- **It fixed the ROOT, not the symptom.** The defect was that the scope was never carried. The fix
  assigns it at the one function every surface authenticates through, which is why the gate could
  then be written once rather than nineteen times.
- **It found a hole the plan's own truths did not name.** Scope alone satisfies every truth in
  `05-14-PLAN.md` and would still have left a `tasks.bulk` grant a one-step unpreviewed trash. The
  route allow-list is the difference between passing the plan and closing the boundary.
- **It mutation-tested each half separately** and said why one mutation would have been insufficient
  evidence -- the first mutation trips the scope case and proves nothing about the allow-list.
- **It refused to check its own box** and named four residual risks, two of which (the receipt
  mapping, the audience) are exactly the two things this pass had to rule on. That is what made a
  third pass efficient rather than exploratory.
- **It corrected the false comment in place** rather than deleting it, so the next reader sees the
  claim AND why it was wrong.

### Gaps Summary

None blocking. Three disclosures, dispositioned in the frontmatter:

1. **`/api/v1/mutations/:id` maps to `tasks.write` and returns full content** -- a genuine
   least-privilege inversion, probed rather than reasoned. A write-only grant read the owner's own
   mutation receipt. Unreachable without the client-chosen UUID, which no agent surface discloses.
   Recommend a window and a small fix (require `tasks.read` too, or bind the receipt to the issuing
   grant).
2. **RFC 8707 audience outside `MCP.Pipeline`** -- ruled a design inconsistency, not a defect.
   Recommend recording the decision; do NOT close it by refusing the credential, which buys no
   authority reduction and costs D-09's HTTP evidence and AgentScope's only non-adapter call site.
3. **Preview tokens are account-bound, not grant-bound** -- documented behaviour, no privilege gain,
   recorded so it is not re-discovered as a finding.

SRV-02 continues to defer on window #69's driver wiring -- the only thing still standing between
this phase and a complete cross-adapter proof, and it is a tooling gap, not a product one.
Window #71 (the test-suite login budget) keeps the disposition from `70f9cef`: acceptable
stop-gap, masks nothing in production, stays open. 05-14's new tests consume none of that budget --
they mint sessions through `Accounts.create_session/2`.

---

_Verified: 2026-09-11 at `b334ecc`_
_Verifier: Claude (gsd-verifier), third pass, after 05-14_
