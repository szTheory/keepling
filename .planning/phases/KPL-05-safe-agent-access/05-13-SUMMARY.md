---
phase: KPL-05-safe-agent-access
plan: 13
subsystem: auth
tags: [mcp, device-grants, authorization, privilege-escalation, phoenix, playwright]

requires:
  - phase: KPL-05-safe-agent-access
    provides: "the MCP adapter, its device-grant credential class, and the six-lane evidence gate this plan repairs"
provides:
  - "A symmetric client_kind boundary: :device_grant_authenticated refuses an mcp grant exactly as KeeplingWeb.MCP.Pipeline refuses a non-mcp one"
  - "An owner-session route for grant administration (/api/v1/account/device-grants), leaving the bearer-only route and its assertions untouched"
  - "An evidence harness that reads the grant list with the owner's session instead of the escalation it was supposed to catch"
  - "Over-delivery cases in the adversarial lane: the gate now fails if any of the four native routes stops refusing an agent credential"
affects: [KPL-05 re-verification, MCP-01, SRV-02, any future route placed behind :device_grant_authenticated]

actuals:
  tokens: 41000
  tasks: 4
  commits: 5

tech-stack:
  added: []
  patterns:
    - "Default-deny allow-list on a pipeline entry point rather than a per-route denial"
    - "Two routes, one per credential class, instead of one route with a widened pipeline"
    - "Over-delivery probes: aim the harness's own credential at surfaces the adapter does not front"

key-files:
  created: []
  modified:
    - apps/server/lib/keepling_web/auth.ex
    - apps/server/lib/keepling_web/router.ex
    - apps/server/lib/keepling_web/controllers/device_grant_controller.ex
    - apps/server/test/keepling_web/device_grant_controller_test.exs
    - apps/server/test/keepling_web/sync_controller_test.exs
    - apps/web/src/api/keepling.ts
    - apps/web/e2e/agent-access.spec.ts
    - packages/contracts/openapi/keepling.yaml
    - tooling/mcp-client/final-state.mjs
    - tooling/mcp-lanes/adversarial.mjs

key-decisions:
  - "The refusal lives on the pipeline, not per route: :device_grant_authenticated fronts only first-party native surfaces, and a per-route check defaults to ALLOW for routes added later."
  - "It is an allow-list of electron/iphone rather than a `!= mcp` denial, so a future agent-ish client_kind is refused until someone deliberately admits it."
  - ":client_authenticated is deliberately left admitting mcp grants (D-09) — that surface is scope-checked, bounded, and shared."
  - "Grant administration gets a second route for the browser rather than a widened pipeline on the first, so no existing assertion is weakened and no new path to the owner's grants is opened for an agent."
  - "The refusal reuses the existing device_authentication_required problem shape, disclosing nothing about which kinds are admitted."

patterns-established:
  - "Mirror-image authorization: when one pipeline refuses a client kind, its counterpart must refuse the complement, or the refusal is a one-way door."
  - "Anti-vacuity for negative tests: assert the exact refusal status (401), not `not 200` — a deleted route answers 404 and would silently hollow the assertion."
  - "Boundary controls: after proving a credential is refused everywhere it should be, prove it still works where it should, or the evidence is indistinguishable from a broken credential."

requirements-completed: []

duration: 20min
completed: 2026-09-11
status: complete
---

# Phase KPL-05 Plan 13: Agent Privilege Escalation Gap Closure — Summary

**An MCP agent credential scoped `tasks.read` could read the entire account through the native sync feed, enumerate every device grant, and revoke the owner's iPhone; all four routes now refuse it, the owner's browser got its own route to manage grants, and the adversarial lane fails if any of it regresses.**

## Performance

- **Duration:** ~20 min of execution (plus ~50 min of live gate, e2e and phase-1 runs)
- **Started:** 2026-09-11T01:56Z
- **Completed:** 2026-09-11T02:16Z
- **Tasks:** 4 of 4
- **Files modified:** 10 (plus the regenerated `packages/contracts/generated/keepling.ts`)

## Accomplishments

- Closed the privilege escalation (WINDOWS #70). `KeeplingWeb.Auth`'s `:device_grant_authenticated` entry point now allow-lists `electron` and `iphone`, the mirror image of `KeeplingWeb.MCP.Pipeline`'s `client_kind == "mcp"` requirement. `/api/v1/sync`, `/api/v1/sync/bootstrap`, `GET /api/v1/device-grants` and `DELETE /api/v1/device-grants/:installation_id` all answer 401 to an agent credential, and all four still serve the real first-party clients.
- Settled the grant-administration question (WINDOWS #66) without weakening either side of it. `/api/v1/device-grants` stays bearer-only with its "bearer boundary … ignores browser cookies" assertion intact; the owner's browser reaches `/api/v1/account/device-grants` behind `:authenticated`, with `:mutation` on the delete.
- Took the evidence harness off the defect. `final-state.mjs` `readGrants()` read the grant list with the scenario's own MCP bearer and asserted 200, so the green `simulated-client` lane rested on the escalation it should have caught. It now reads the same inventory through the owner's session.
- Gave the gate an over-delivery probe. Four new adversarial cases aim the lane's own agent credential at the four routes and require a refusal from each — the blind spot the escalation lived in.
- `apps/web/e2e/agent-access.spec.ts` now passes to completion (26 passed). It previously died at line 250; step 5 had never run.

## Task Commits

1. **Task 1: make the two pipelines symmetric** — `6085a79` (fix)
2. **Task 2: give grant administration an owner-session route** — `4bf94e5` (feat)
3. **Task 3: re-point the harness off the hole** — `2c8e022` (test)
4. **Task 4: test over-delivery, not just under-delivery** — `9271b5c` (test), plus `8ad4586` (fix) for the e2e assertion the fix finally exposed

## Files Created/Modified

- `apps/server/lib/keepling_web/auth.ex` — `authenticate_first_party_device_grant/1`, the mirror-image refusal, with the reasoning for pipeline-vs-per-route and for leaving `:client_authenticated` alone
- `apps/server/lib/keepling_web/router.ex` — the two owner-session grant-administration routes
- `apps/server/lib/keepling_web/controllers/device_grant_controller.ex` — `list_for_owner/2`, `revoke_for_owner/2`, and a shared `revoke_installation/3`
- `apps/server/test/keepling_web/device_grant_controller_test.exs` — mcp refused on both grant routes with first-party grants still administering; the owner-session route listing, revoking, and refusing a bearer and a cross-origin delete
- `apps/server/test/keepling_web/sync_controller_test.exs` — mcp refused on both sync routes with a canary title proving nothing leaked; electron and iphone still pull and bootstrap
- `apps/web/src/api/keepling.ts` — `listDeviceGrants`/`revokeDeviceGrant` re-pointed at the owner-session route
- `apps/web/e2e/agent-access.spec.ts` — step 5's final assertion rewritten (see deviations)
- `packages/contracts/openapi/keepling.yaml` (+ regenerated `generated/keepling.ts`) — both owner routes documented under `BrowserSession`
- `tooling/mcp-client/final-state.mjs` — `readGrants` on the owner session; `deviceGrantAccessToken` replaced by `includeGrants`
- `tooling/mcp-lanes/adversarial.mjs` — the four over-delivery cases; `auth.ex` and `router.ex` added to `trackedInputPaths`

## Decisions Made

**Where the refusal lives — pipeline, not per route.** `:device_grant_authenticated` fronts exactly four routes and all four are first-party-client surfaces, so there is no route behind it that an agent should reach and therefore no per-route judgement to make. More importantly, a per-route check defaults to ALLOW for any route added behind the pipeline later, which is the failure mode being closed; an allow-list on the pipeline defaults to DENY.

**Allow-list, not `!= "mcp"`.** `Keepling.Accounts.DeviceGrant`'s `@client_kinds` is `~w(electron iphone mcp)` today. A denial of `mcp` admits whatever kind is added next; an allow-list of `electron`/`iphone` refuses it until someone deliberately admits it.

**`:client_authenticated` deliberately untouched.** `authenticate_client/2` calls `authenticate_device_grant/1` directly and keeps admitting `mcp` grants. That is D-09's explicit intent — the shared read/command surface is scope-checked and bounded and is the one query, not a parallel one. The asymmetry between the two entry points is the point: one fronts bounded shared reads, the other fronts the raw device feed and grant administration. Extending the refusal to `:client_authenticated` would have broken `/api/v1/search`, `/api/v1/projects` and the shared command surface for the MCP adapter.

**A second route rather than a widened pipeline.** Moving `/api/v1/device-grants` to `:client_authenticated` would have admitted every device grant — including an agent's — to grant administration, i.e. rebuilt the escalation on the same route, and would have contradicted a deliberate security assertion. Two routes, each with exactly one credential class, weakens neither.

**Same problem shape for the refusal.** `device_authentication_required` / `reauthorize_device` / 401, identical to the mirror refusal in `MCP.Pipeline`. It keeps the closed problem vocabulary closed and discloses nothing about which kinds are admitted.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `agent-access.spec.ts` step 5's final assertion could never pass**
- **Found during:** Task 4 (running the e2e spec after the owner-session route landed)
- **Issue:** With the route fixed, the spec reached line 256 for the first time and failed there. `getByText` is a substring match, and the aria-live confirmation asserted on the preceding line ("Agent access e2e host revoked.") contains the grant label, so `expect(getByText('Agent access e2e host')).not.toBeVisible()` matched the confirmation message itself. The Playwright error context shows the only matching element was `<div class="sr-only" aria-live="polite">Agent access e2e host revoked.</div>` — the grant row was already gone. The assertion was unsatisfiable by construction, whatever the product did.
- **Fix:** Replaced with two assertions scoped to the list: the row's heading inside `getByRole('list', { name: 'Authorized AI agents' })` has count 0, and the "Revoke Agent access e2e host" control has count 0. This is narrower than the text match it replaces — a row stripped of its revoke button would still be a row the owner cannot act on — so nothing was weakened to make a test pass.
- **Files modified:** `apps/web/e2e/agent-access.spec.ts`
- **Verification:** `KEEPLING_E2E_POSTGRES_PORT=55442 pnpm --filter @keepling/web test:e2e -- agent-access.spec.ts` → 26 passed
- **Committed in:** `8ad4586`

**2. [Rule 2 - Missing critical functionality] The new routes were not in the OpenAPI contract**
- **Found during:** Task 2
- **Issue:** The plan's `files_modified` did not include `packages/contracts/openapi/keepling.yaml`, but the web client now calls a route absent from the contract that is the checked-in source of truth for the client-server surface. An undocumented authenticated route is exactly the kind of thing that goes unreviewed.
- **Fix:** Added both `/account/device-grants` paths under the `BrowserSession` security scheme and regenerated `packages/contracts/generated/keepling.ts` via `pnpm run contracts:generate`.
- **Files modified:** `packages/contracts/openapi/keepling.yaml`, `packages/contracts/generated/keepling.ts`
- **Verification:** `pnpm contracts:check` passed (including the generation-drift check)
- **Committed in:** `4bf94e5`

**3. [Rule 2 - Missing critical functionality] `auth.ex` and `router.ex` were not tracked inputs of the adversarial lane**
- **Found during:** Task 4
- **Issue:** The over-delivery cases are assertions *about* those two files, but neither was in the lane's `trackedInputPaths`, so a change to the boundary they define would not have changed the lane's input digest — the gate could have reported a stale verdict for the very property the new cases exist to pin.
- **Fix:** Added both paths to `trackedInputPaths`.
- **Files modified:** `tooling/mcp-lanes/adversarial.mjs`
- **Verification:** the lane's `input_digest` changed from the pre-change value; lane PASS cases=10
- **Committed in:** `9271b5c`

---

**Total deviations:** 3 auto-fixed (1 × Rule 1, 2 × Rule 2)
**Impact on plan:** None on scope. One was a latent test bug the fix exposed; two were correctness gaps in artifacts the plan's own changes made load-bearing.

## Verification Evidence

### Lane table

Full gate: `KEEPLING_E2E_POSTGRES_PORT=55442 pnpm run verify:mcp:phase`, run `2ea37cd7-c14d-41e1-88f5-adb1389930dd`.

| Lane | Status | Cases | Notes |
|------|--------|-------|-------|
| deterministic | PASS | 183 | unchanged |
| protocol | PASS | 2 | unchanged (its case count remains a decorative constant — pre-existing, recorded by the verifier, not addressed here) |
| simulated-client | PASS | 9 | now green *without* depending on the escalation; grant list read through the owner's session |
| adversarial | PASS | **10** | was 6; 6 injection cases + 4 new over-delivery cases |
| representative-model | PASS | 6 | live model, run `4402d88b-edb2-4084-bcdb-710e94f60ebe`, duration 56s. Reported BLOCKED inside the isolated worktree because `.env.local` is gitignored and therefore invisible here — an artifact of isolation, **not** a product fact. Re-run with the main checkout's credential file supplied via `--env-file-if-exists`; a credential was present. Its value was never read, echoed, copied, or written anywhere. |
| cross-adapter | BLOCKED | 0 | `electron` and `iphone` legs on unwired drivers (window #69). Out of scope, unchanged by this plan; `web-api` and `mcp` legs PASS 4 each with `comparison_ok=true`. |

Gate exit remains non-zero solely because of `cross-adapter`. `failed=0` in every run.

### Anti-vacuity: the over-delivery cases were mutation-tested

Re-admitting `mcp` to the pipeline allow-list turns the lane FAIL with
`over_delivery case "sync_pull": GET /api/v1/sync answered 200 for an mcp grant; expected 401`.
The mutation was reverted immediately (`git checkout -- apps/server/lib/keepling_web/auth.ex`); the
committed tree carries `~w(electron iphone)`.

The cases are built not to be vacuous in three further ways: each route must answer *exactly* 401 (a
deleted route answers 404), each refusal body is checked against a canary task title written through
the MCP surface and against another installation's id, the refused DELETE is scored on final state
read back through the owner's session, and a control call proves the same credential still works on
`/mcp/v1` — without which every refusal above would pass equally well against a merely revoked token.

### Other suites

| Suite | Command | Result |
|-------|---------|--------|
| Server ExUnit | `mix test` against a disposable PostgreSQL | 319 passed (1 property, 318 tests) |
| Phase-1 gate | `KEEPLING_E2E_POSTGRES_PORT=55442 pnpm test:phase-1` | exit 0 — all lanes: repository integrity, server compile (`--warnings-as-errors`), server tests, production routes, contracts, web typecheck, 169 Vitest, 26 Playwright, automated UAT coverage |
| Named e2e spec | `pnpm --filter @keepling/web test:e2e -- agent-access.spec.ts` | 26 passed — **passes to completion**; previously failed at line 250 |
| Harness self-test | `node --test tooling/mcp-gate-selftest.mjs` | 10/10 |
| final-state self-check | `node tooling/mcp-client/final-state.mjs --self-check` | cases=3 ok |

## MCP-01 evidence position

**Recommendation: MCP-01 is now checkable, but this plan does not check it. The box stays unchecked
for re-verification to decide.**

MCP-01 reads: bounded, paginated reads without direct database access. The verifier's objection was
never about the read surface — `resources.ex` routes all six views through one shared port with
cursor and limit, 22 resource tests cover it, and a live model read through it. The objection was
that *boundedness was a property of the surface, not of the credential*: the same agent bearer got
200 from `GET /api/v1/sync/bootstrap` with full, unpaginated, unredacted task content, which is
"direct database access" in every sense that matters.

That specific falsifier is now closed, and closed on evidence of the same kind that falsified it:

- The probe's exact three results are inverted and pinned as tests. `GET /api/v1/sync/bootstrap` →
  401 with the canary title absent from the body; `GET /api/v1/device-grants` → 401;
  `DELETE /api/v1/device-grants/<other>` → 401 with the victim grant still present and unrevoked on
  a read-back through the owner's session.
- The inversion is enforced by the gate, not only by unit tests: the adversarial lane drives a real
  agent credential against a real booted server, and mutation-testing confirms it fails if the
  boundary regresses.
- The lane that previously *depended* on the hole no longer does.

Two honest caveats a re-verifier should weigh rather than take from me:

1. **Scope is still not enforced on the MCP read surface's neighbours.** This plan closed the
   `client_kind` boundary. It did not add a scope check to anything — a `tasks.read` grant and a
   `tasks.bulk` grant are treated identically by the pipeline. That was correct scoping for this
   plan (the escalation was kind-shaped, not scope-shaped, and the MCP surface does enforce scope on
   its own tools, which the live model proved by being refused an out-of-scope write). But MCP-01's
   "least privilege" neighbourhood is only as strong as `:client_authenticated`'s own bounds, which
   this plan deliberately left as D-09 wrote them.
2. **The evidence is one revision old for the model lane's *reasoning*, not its mechanics.** The
   representative-model lane passed against this tree with a live model, but its verdicts come from
   final DB state, and no live model was asked to attempt the escalation. The over-delivery cases
   drive the credential directly. An adversarial model prompt aimed at `/api/v1/sync/bootstrap`
   would be strictly stronger evidence and does not exist.

SRV-02 is untouched and still deferred on window #69's driver wiring. Note, though, that the
verifier's second SRV-02 objection — "the MCP entry point delivers strictly more authority than the
surface it fronts" — is the half that closes here.

## Issues Encountered

- The worktree had no `node_modules` and no Elixir `deps`; both were installed before anything could
  run. `mix deps.get` must go through `./tooling/runtime-preflight.sh --exec` or the asdf shim
  silently does nothing useful.
- Port 55432 is held by an unrelated Docker container, as the plan warned. Everything needing the
  e2e PostgreSQL ran with `KEEPLING_E2E_POSTGRES_PORT=55442`; the committed default was not changed
  and the container was not touched.

## Known Stubs

None introduced. Two pre-existing items remain visible and are **not** in this plan's scope:

- `tooling/mcp-lanes/protocol.mjs` hardcodes `cases=2` in its own evidence line (verifier-recorded,
  non-gating).
- `tooling/mcp-lanes/representative-model.mjs:355` `void errorVectors // reserved for a future …`
  (loaded-but-unused, no debt marker).

Separately, `DeviceGrantController.grant_response/1` still omits `scope`, `authorized_at` and
`last_used_at`, so `/settings/agents` renders "No scopes granted" for every agent. That is the
pre-existing gap `apps/web/src/api/keepling.ts:44-60` documents and 05-09-SUMMARY.md disclosed; the
e2e spec's step-5 comment claims the page "lists the grant with exactly its scopes" but the spec
asserts no scopes, so the claim is untested. Untouched here because closing it would change a
response shape this plan had no mandate over — worth an owner.

## Next Phase Readiness

Re-verification of KPL-05 can proceed. `.planning/REQUIREMENTS.md`, `.planning/STATE.md` and
`.planning/ROADMAP.md` were deliberately left unmodified. WINDOWS #66 and #70 are marked `fixed`.

---
*Phase: KPL-05-safe-agent-access*
*Completed: 2026-09-11*

## Self-Check: PASSED

All six named files exist on disk and all five task commits are present in this worktree's history
(`6085a79`, `4bf94e5`, `2c8e022`, `9271b5c`, `8ad4586`, on `d3c3d1c`).
