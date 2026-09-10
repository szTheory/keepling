---
phase: KPL-05-safe-agent-access
plan: 09
subsystem: ui
tags: [react, mcp, device-grants, activity, undo, accessibility, playwright, real-stack]

# Dependency graph
requires:
  - phase: KPL-05-02
    provides: The mcp device-grant client kind with a scope column, and the pre-registered client_id "mcp" with its own redirect_uri (no DCR required for Claude Code, per D-29)
  - phase: KPL-05-08
    provides: Agent attribution in activity facts (type=agent, principal=authorized_grant, label=grant label, client_kind=mcp) and the server-side GTD-07 undo-handle guarantee for agent-authored actions
provides:
  - "AgentGrantList: a component listing every mcp-kind device grant with scopes/authorized/last-used and a confirmed, uncertain-recovery-aware revoke, mounted at /settings/agents"
  - "listDeviceGrants/revokeDeviceGrant in apps/web/src/api/keepling.ts against the existing GET/DELETE /api/v1/device-grants endpoints"
  - "ActivityList now renders every fact's actor with a non-colour-only agent distinction (icon + accessible-name badge), and a per-fact Undo control reusing the existing undo call path (getMutation + undoTask) rather than a second mechanism"
  - "apps/web/e2e/agent-access.spec.ts, run against the real stack: proves the full PKCE-authorized agent -> tools/call -> activity-history -> undo loop for real (steps 1-4); step 5 (agent-grant management) is written and real but fails today against a genuine, disclosed server-side gap this plan could not fix from apps/web"
affects: [KPL-05-10, KPL-05-11, KPL-05-12]

actuals:
  tokens: 33500
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Per-fact undo without a new wire field: ActivityUndoControl fetches the fact's own CommandAcknowledgement via the EXISTING account-scoped GET /api/v1/mutations/:mutation_id (already used by RecoveryStrip for reconciliation) to obtain the real server-issued undo handle for that historical mutation_id, then calls the existing undoTask(). This works for a fact from ANY adapter (web/electron/iphone/mcp) because Keepling.Adapters.Postgres.CommandStore.lookup_result/1 scopes by account_id only, not by client. No new server endpoint or wire field was needed."
    - "Defensive wire-type widening, not fabrication: WireAgentGrantSummary widens client_kind from the generated DeviceGrantSummary's closed electron|iphone union to string (the server's own device_grants.client_kind CHECK constraint has admitted mcp since 05-01 and genuinely returns it at runtime -- the generated OpenAPI type is simply stale) and reads scope/last_used_at/authorized_at as OPTIONAL extension fields, defaulting to empty/null when the server's real response omits them (which it does, today, on every response) rather than inventing values."

key-files:
  created:
    - apps/web/src/features/agents/AgentGrantList.tsx
    - apps/web/src/features/agents/agent-grant-list.test.tsx
    - apps/web/e2e/agent-access.spec.ts
  modified:
    - apps/web/src/api/keepling.ts
    - apps/web/src/app/routes.tsx
    - apps/web/src/features/activity/ActivityList.tsx
    - apps/web/src/features/activity/activity-list.test.tsx

key-decisions:
  - "Used the pre-registered client_id \"mcp\" for the e2e spec rather than exercising RFC 7591 DCR (POST /oauth/register). 05-CONTEXT.md D-29 names Claude Code as needing no DCR, and 05-02 already proved the DCR path with its own registration_test.exs; this plan's e2e spec needed one full real authorization, not a second proof of registration, and DCR would have added a mutation-pipeline CSRF/origin dance with no payoff for this plan's own must-haves."
  - "Reused GET /api/v1/mutations/:mutation_id + undoTask() for ActivityList's per-fact Undo control instead of extending the ActivityItem wire schema with an undo handle. The wire ActivityItem carries only recovery_state (an enum), never a handle -- extending it is a packages/contracts + apps/server change outside this plan's apps/web-only scope. The mutation-lookup endpoint already returns the full CommandAcknowledgement (including undo) and is already account-scoped (not client-scoped), so it serves the same purpose for a HISTORICAL fact from any adapter without any server change. Verified end to end against the real stack (05-09-SUMMARY.md's own e2e run): an agent-authored completion's Undo control genuinely reverses the task, server-side."
  - "AgentGrantList renders scope/authorized-at/last-used-at defensively from optional wire-extension fields, not from a hardcoded frontend scope list (satisfying the plan's own prohibition), because GET /api/v1/device-grants's real response (KeeplingWeb.DeviceGrantController.grant_response/1) returns only client_kind/generation/id/installation_id/label/revoked today -- scope, authorized_at, and last_used_at are not yet published by that endpoint. This is disclosed as a Deviation below, not silently worked around."

patterns-established:
  - "A component test's mock JSON is not obligated to match a stale generated wire type exactly -- when a real server field (client_kind: \"mcp\") is closed out of the OpenAPI-generated union by a documentation lag rather than a real constraint, widen the LOCAL consuming type (not the shared generated one, which packages/contracts owns) and prove it against the real server before trusting it, exactly as this plan's e2e run did."

requirements-completed: [MCP-04]

coverage:
  - id: D1
    description: "The user can see every authorized AI agent, its exact scopes, and when it was last used, and can revoke an agent with the same confirmation/uncertain-recovery care SessionList already takes."
    requirement: "MCP-04"
    verification:
      - kind: unit
        ref: "apps/web/src/features/agents/agent-grant-list.test.tsx#lists only agent-kind grants with their exact scopes, filtering out non-agent client kinds"
        status: pass
      - kind: unit
        ref: "apps/web/src/features/agents/agent-grant-list.test.tsx#renders a zero-scope grant as holding no scopes, never a scope name"
        status: pass
      - kind: unit
        ref: "apps/web/src/features/agents/agent-grant-list.test.tsx#reports an uncertain revocation as still authorized only after inventory proves presence"
        status: pass
      - kind: e2e
        ref: "apps/web/e2e/agent-access.spec.ts#step 5 (/settings/agents list + revoke)"
        status: fail
    human_judgment: true
    rationale: "Component-level behavior is fully proven by unit tests against realistic mock payloads, but the live server does not yet authenticate GET/DELETE /api/v1/device-grants by browser session cookie (see Deviations) -- a human (or the follow-up server-side plan that closes this gap) must confirm the real end-to-end truth once that server change lands; this plan cannot self-certify it from apps/web alone."
  - id: D2
    description: "The activity history visibly distinguishes an agent action from the user's own, naming the agent grant, with the distinction conveyed by more than colour and announced to assistive technology."
    requirement: "MCP-04"
    verification:
      - kind: unit
        ref: "apps/web/src/features/activity/activity-list.test.tsx#renders an agent fact with a queryable, non-colour-only actor distinction"
        status: pass
      - kind: unit
        ref: "apps/web/src/features/activity/activity-list.test.tsx#interleaves agent and user facts in one ordered list, with no separate agent-only view"
        status: pass
      - kind: e2e
        ref: "apps/web/e2e/agent-access.spec.ts#step 3 (activity history attribution)"
        status: pass
    human_judgment: false
  - id: D3
    description: "An agent action in the history offers the same undo affordance a user action offers, and using it reverses the action, read back from the server."
    requirement: "MCP-04"
    verification:
      - kind: unit
        ref: "apps/web/src/features/activity/activity-list.test.tsx#exposes the undo control for an agent fact with an available recovery state"
        status: pass
      - kind: unit
        ref: "apps/web/src/features/activity/activity-list.test.tsx#shows no undo control and says why for an expired agent fact"
        status: pass
      - kind: unit
        ref: "apps/web/src/features/activity/activity-list.test.tsx#activates the undo control on an agent fact and reverses the action through the shared undo path"
        status: pass
      - kind: e2e
        ref: "apps/web/e2e/agent-access.spec.ts#step 4 (undo activation + server readback)"
        status: pass
    human_judgment: false
  - id: D4
    description: "No new client application, window, or shell is added; both surfaces live in the existing web app."
    requirement: "MCP-04"
    verification:
      - kind: other
        ref: "apps/web/src/app/routes.tsx: /settings/agents mounted alongside existing routes in the same AppRoutes switch, no new entry point"
        status: pass
    human_judgment: false

duration: ~3h
completed: 2026-09-10
status: complete
---

# Phase 5 Plan 09: Agent Grant Management and Agent-Aware Activity History Summary

**`/settings/agents` lists and revokes MCP agent grants, `ActivityList` now attributes and (via the existing undo call path) undoes agent facts, and a real-stack Playwright spec proves the whole authorize -> act -> see -> undo loop end to end -- with one server-side gap this plan discovered and could not close from `apps/web` disclosed below rather than papered over.**

## Performance

- **Duration:** ~3h
- **Tasks:** 3 (all `type="auto" tdd="true"` or `type="auto"`)
- **Files created:** 3
- **Files modified:** 4

## Accomplishments

- `apps/web/src/features/agents/AgentGrantList.tsx`: modelled directly on `SessionList` -- an `AlertDialog` confirmation naming the agent, the identical uncertain-recovery treatment for a revoke whose outcome is unknown (never optimistic removal), an empty state that says no AI agents are authorized (never an empty table), and no scope string hardcoded anywhere in the component (`grep -c "tasks.read" AgentGrantList.tsx` is 0) -- scopes render only from what the server actually returned.
- `apps/web/src/api/keepling.ts` gained `listDeviceGrants`/`revokeDeviceGrant` against the existing `GET`/`DELETE /api/v1/device-grants` endpoints, typed from a local extension of `packages/contracts/generated/keepling.ts`'s `DeviceGrantSummary` (documented as a deliberate, disclosed widening -- see Deviations).
- `apps/web/src/features/activity/ActivityList.tsx`: every fact's actor now renders through `ActorLabel` -- an agent fact gets an icon plus a text "AI agent" badge with its own accessible name (never colour alone). A new `ActivityUndoControl` gives every fact whose `recoveryState` is `available` a real Undo button, reusing `getMutation`/`undoTask` (the exact functions `RecoveryStrip` already uses) rather than inventing a second undo mechanism or a new wire field. A non-`available` state (`expired`/`undone`/`stale`/`not_available`) renders an explanatory reason instead of a hidden control.
- `apps/web/e2e/agent-access.spec.ts`: one Playwright spec against the real stack (no stubbed fetch, no `.invalid` host, no test-only sync mode) covering all five plan-numbered steps as assertions in one test. **Run against the real stack in this worktree to verify, not just authored:** steps 1-4 (PKCE authorization with the pre-registered `mcp` client, `tools/call` capture+complete, activity-history attribution, and undo activation with a server readback of `completed_at: null`) all pass for real. Step 5 fails against the real server today -- see Deviations.
- Full `pnpm --filter @keepling/web test` (169/169), `pnpm --filter @keepling/web typecheck`, and `pnpm lint:web` all pass.

## Task Commits

1. **Task 1: The agent grant management view** -- `6c7ef99` (feat)
2. **Task 2: Agent actions in the one history, with the same undo affordance** -- `1a81de1` (feat)
3. **Task 3: End-to-end proof against the real stack** -- `8e48e42` (test)

**Plan metadata:** committed alongside this SUMMARY.

## Files Created/Modified

- `apps/web/src/api/keepling.ts` -- `listDeviceGrants`/`revokeDeviceGrant`, `AgentGrant` type, the disclosed `WireAgentGrantSummary` extension
- `apps/web/src/features/agents/AgentGrantList.tsx` -- the agent grant management view
- `apps/web/src/features/agents/agent-grant-list.test.tsx` -- its component tests
- `apps/web/src/app/routes.tsx` -- mounts `AgentGrantList` at `/settings/agents`; threads `csrfToken` into `ActivityList`
- `apps/web/src/features/activity/ActivityList.tsx` -- `ActorLabel`, `AgentActorIcon`, `ActivityUndoControl`
- `apps/web/src/features/activity/activity-list.test.tsx` -- interleaving, distinction, and undo-activation tests
- `apps/web/e2e/agent-access.spec.ts` -- the real-stack proof

## Decisions Made

See `key-decisions` in frontmatter: the pre-registered `client_id` over DCR for the e2e spec, reusing `GET /api/v1/mutations/:mutation_id` + `undoTask()` for per-fact undo instead of a new wire field, and rendering agent-grant scope/timestamps defensively rather than hardcoding them.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Off-scale Tailwind utilities in the new agent-badge/scope markup**
- **Found during:** Task 1/2, first `pnpm test` run (the repository's `ui-contract.test.tsx` gate)
- **Issue:** `gap-1.5`, `px-1.5 py-0.5`, and `text-xs` are off the project's declared design-token scale (`src/test/ui-contract.test.tsx`'s `offScaleFeatureUtilities` regex) and are structurally forbidden.
- **Fix:** Replaced with the on-scale equivalents `SessionList`'s own "Current browser" badge already uses (`gap-2`, `px-2 py-1`, `text-sm font-semibold`).
- **Files modified:** `apps/web/src/features/activity/ActivityList.tsx`, `apps/web/src/features/agents/AgentGrantList.tsx`
- **Verification:** `pnpm --filter @keepling/web test` (full suite, was 3 failing, now 169/169)
- **Committed in:** `6c7ef99` (Task 1), `1a81de1` (Task 2)

### Architectural Blocker (Rule 4 -- disclosed, not auto-fixed)

**2. [Rule 4 - Architectural] `GET`/`DELETE /api/v1/device-grants` are bearer-only, unreachable by the browser's own session**
- **Found during:** Task 3, running the e2e spec against the real stack
- **Issue:** `apps/server/lib/keepling_web/router.ex` mounts both routes behind the `:device_grant_authenticated` pipeline, which is `KeeplingWeb.Auth.authenticate_device_grant/1` -- it requires an `Authorization: Bearer <device-grant access token>` header and explicitly does NOT accept a browser session cookie. `AgentGrantList.tsx`'s `fetch` calls (`credentials: 'same-origin'`, matching the plan's literal instruction to call "the existing device-grant list and revoke endpoints") can never authenticate against the real server: confirmed empirically in this worktree, not assumed -- the e2e spec's step 5, run against the real stack, shows the exact live failure ("Couldn't load AI agents. Nothing was changed.").
- **Scope:** Fixing this requires a session-cookie-authenticated route (or widening the existing pipeline to accept either credential class, mirroring `KeeplingWeb.Auth.authenticate_client/2`'s existing `:client_authenticated`/`:client_mutation` pattern used elsewhere) in `apps/server/lib/keepling_web/router.ex` and `apps/server/lib/keepling_web/auth.ex` -- entirely `apps/server` work, outside this plan's `apps/web`-only worktree boundary (05-03 and 05-07 own concurrent `apps/server` changes in this same wave; touching `router.ex`/`auth.ex` here would conflict with their scope and this plan's own instructions).
- **What is NOT blocked:** `AgentGrantList.tsx` itself is fully built, fully unit-tested, and will work correctly the moment a session-cookie-authenticated path exists -- no frontend rework is needed. Task 2's per-fact undo control (which reads `GET /api/v1/mutations/:mutation_id`, a DIFFERENT, already session-cookie-authenticated endpoint) is unaffected and proven working end to end against the real server.
- **Impact on this plan's must-haves:** the truth "the user can see every authorized AI agent... and can revoke an agent from that view" is proven at the component level (unit tests, realistic mock payloads) but NOT provable end-to-end against the real server until the above server-side gap closes. Documented as `human_judgment: true` on coverage item D1 rather than a false `pass`.
- **Not committed as a workaround:** no bearer-token forwarding, no client-side credential minting, and no relaxation of the endpoint's real authorization model was added to "make the test green" -- that would be exactly the kind of silent authorization weakening `05-CONTEXT.md`'s adversarial posture (D-24) exists to forbid.

### Also disclosed (not blocking, but real gaps found while implementing)

**3. [Disclosed] `GET /api/v1/device-grants`'s real response omits `scope`, `authorized_at`, and `last_used_at`**
- **Found during:** Task 1, reading `KeeplingWeb.DeviceGrantController.grant_response/1` and `Keepling.Accounts.DeviceGrant.list/1`'s SQL
- **Detail:** The server persists `scope` on `device_grants` (05-01) but neither `list/1`'s `SELECT` nor `grant_response/1`'s returned map include it, and there is no `last_used_at`/`authorized_at` column or field anywhere on this path. `AgentGrantList.tsx` reads these three fields defensively (optional, via `WireAgentGrantSummary`) and renders "No scopes granted" / "Not yet reported" / "Not yet used" when they are absent -- which is every real response today. The view will start showing real values automatically once a follow-up server-side plan adds them to `grant_response/1` and `Accounts.DeviceGrant.list/1`'s query; no frontend change will be needed.
- **Files affected:** `apps/web/src/api/keepling.ts` (documented inline at `WireAgentGrantSummary`)

**4. [Disclosed] The generated `DeviceGrantSummary.client_kind` type is stale relative to the real server**
- **Found during:** Task 1, `pnpm typecheck`
- **Detail:** `packages/contracts/openapi/keepling.yaml`'s `NativeClientIdentity` enum (used by `DeviceGrantSummary.client_kind`) is closed to `electron | iphone` -- it has never been updated to admit `mcp`, even though `device_grants.client_kind`'s own database CHECK constraint has admitted `mcp` since 05-01 and the real endpoint genuinely returns `client_kind: "mcp"` rows (confirmed by this plan's own e2e run, which saw real `mcp` grants filtered correctly). `apps/web/src/api/keepling.ts`'s `WireAgentGrantSummary` widens `client_kind` to `string` locally rather than editing the shared generated file (`packages/contracts` is out of this plan's scope). A follow-up plan should regenerate `packages/contracts/generated/keepling.ts` from a corrected `openapi/keepling.yaml`.

---

**Total deviations:** 2 auto-fixed (both Rule 1, UI-scale), 1 architectural blocker (Rule 4, disclosed, not auto-fixable from `apps/web`), 2 further disclosed pre-existing contract/server gaps found during implementation. **Impact on plan:** Tasks 1 and 2 are fully complete, tested, and proven working against the real server where the relevant endpoints are already reachable from a browser session. Task 3's spec is fully written to the plan's specification and proves 4 of 5 numbered steps for real against the live stack; step 5 documents a real, pre-existing, out-of-scope server bug this plan discovered rather than concealing it behind a weakened assertion.

## Known Stubs

- `AgentGrantList.tsx`'s scope/authorized-at/last-used-at rendering is a real, tested implementation whose live values are currently always empty/absent because the server doesn't publish them yet (Deviation 3). Not a stub in the sense of fake data -- it renders exactly what the server returns, honestly, and picks up real values with zero code change once the server catches up.
- `apps/web/e2e/agent-access.spec.ts`'s step 5 (list/revoke via `/settings/agents`) cannot pass against the real server until Deviation 2 is closed server-side. The spec is not weakened or skipped -- it asserts the real, currently-failing behavior.

## Broken-Windows Ledger

No `gsd-tools.cjs` binary was available in this worktree (matching 05-08's disclosed finding for the same reason), so `.planning/WINDOWS.md` could not be updated via `gsd_run windows append`. Recorded here for a future pass with tooling access to reconcile mechanically:

- deviation (architectural, disclosed): `apps/server/lib/keepling_web/router.ex` / `apps/server/lib/keepling_web/auth.ex` -- `GET`/`DELETE /api/v1/device-grants` require bearer device-grant authentication only; no session-cookie-authenticated path exists for the account owner's own browser to manage their account's device grants. Blocks `apps/web/e2e/agent-access.spec.ts`'s step 5 and the live behavior of `AgentGrantList.tsx` (see Deviation 2 above). Kind: `deviation`. Phase: `05`.
- deviation (disclosed, non-blocking): `packages/contracts/openapi/keepling.yaml`'s `DeviceGrantSummary`/`NativeClientIdentity` do not publish `scope`, `authorized_at`, `last_used_at`, or the `mcp` client kind, even though the server has returned `client_kind: "mcp"` at runtime since 05-01. Kind: `deviation`. Phase: `05`.

## Issues Encountered

- The real-stack e2e run required two separate test-account sessions (one hit directly against Phoenix's own origin for the OAuth/MCP calls that `apps/web/e2e/support/stack.ts`'s single-origin proxy does not forward, and one through the proxy's `baseURL` origin for the browser page's own cookie-authenticated fetches) -- cookies are per-origin, and the proxy only forwards `/api/*`. Both sessions sign in to the same deterministic seeded single account (D-003), so this is not a multi-account concern, just a same-account, two-origin test-harness detail. Documented inline in the spec.
- The e2e spec's initial two authoring attempts failed on real-server validation this plan's author had not anticipated purely from reading source: a 16-byte OAuth `state` value (`Keepling.Accounts.DeviceGrant.unpredictable_state?/1` requires >= 32 decoded bytes) and an exact-string UI match that didn't account for the "AI agent" badge text being interposed between the actor label and the action verb in the rendered sentence. Both were found and fixed by actually running the spec against the real stack rather than only reasoning about it -- consistent with this phase's own anti-vacuity discipline.

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness

- MCP-04's activity-attribution and undo-affordance halves (must-haves 3 and 4) are proven end to end against the real server, including a real agent-authored completion genuinely reversed through the web UI.
- The agent-grant-management half (must-haves 1 and 2) is built and unit-tested but blocked end-to-end by a real, disclosed server-side authentication gap (Deviation 2) that a future plan must close in `apps/server/lib/keepling_web/router.ex`/`auth.ex` before `/settings/agents` is usable against a real deployment. No `apps/web` rework will be needed once that lands.
- `packages/contracts`'s `DeviceGrantSummary` schema should be corrected (Deviation 4) alongside the server-side fix above, in the same follow-up plan, so `scope`/`authorized_at`/`last_used_at`/`client_kind: "mcp"` are all published together rather than in separate passes.
- MCP-04 is declared by four plans in this phase (05-01, 05-08, 05-09, 05-10); per the orchestrator's shared-ID gate, it will only flip to `Complete` in `REQUIREMENTS.md` once all four have summaries -- unaffected by this plan's own partial (unit-proven, not yet end-to-end-proven) coverage of D1.

---
*Phase: KPL-05-safe-agent-access*
*Completed: 2026-09-10*
