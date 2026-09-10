---
phase: KPL-05-safe-agent-access
plan: 02
subsystem: mcp
tags: [mcp, oauth, oauth-metadata, rfc9728, rfc8414, rfc7591, rfc8707, dcr, elixir, phoenix, ecto, postgresql]

# Dependency graph
requires:
  - phase: KPL-05-01
    provides: The `mcp` device-grant client kind, the D-06 scope vocabulary, the hand-rolled MCP JSON-RPC/Streamable HTTP endpoint at POST /mcp/v1, KeeplingWeb.MCP.Pipeline's bearer authentication, Keepling.Application.AgentScope
provides:
  - "RFC 9728 protected-resource metadata at GET /.well-known/oauth-protected-resource"
  - "RFC 8414 authorization-server metadata at GET /.well-known/oauth-authorization-server"
  - "A WWW-Authenticate: Bearer resource_metadata=... challenge on every /mcp/v1 401"
  - "RFC 8707 audience binding: device_grants.resource persisted per grant, re-checked at /mcp/v1 request time, refusal recorded as mcp_audience_rejected"
  - "RFC 7591 Dynamic Client Registration at POST /oauth/register, gated behind the authenticated browser session (D-29)"
  - "mcp_client_registrations table and a single validate_redirect/3 serving both configured (electron/iphone/literal mcp) and per-registration redirect allow-lists"
affects: [KPL-05-03, KPL-05-04, KPL-05-05, KPL-05-06, KPL-05-07, KPL-05-08, KPL-05-09, KPL-05-10, KPL-05-11, KPL-05-12]

actuals:
  tokens: 14486
  tasks: 3
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Discovery documents and the RFC 8707 audience derive from ONE module (KeeplingWeb.MCP.Metadata) that the authorization code (DeviceGrantController) also calls, so the documents cannot drift from what is actually enforced."
    - "Client resolution seam: Keepling.Accounts.DeviceGrant.resolve_client/1 maps a client_id to {client_kind, registered_client_id | nil} before any request-shape validation runs, letting one validate_redirect/3 function serve both a static config allow-list and a per-registration allow-list."
    - "RateLimit gained a fifth closed flow (:mcp_registration) following the exact @flows/@default_policies shape every other authentication flow already uses."

key-files:
  created:
    - apps/server/lib/keepling_web/mcp/metadata.ex
    - apps/server/lib/keepling_web/mcp/registration.ex
    - apps/server/priv/repo/migrations/20260911000150_add_mcp_resource_binding.exs
    - apps/server/priv/repo/migrations/20260911000200_add_mcp_client_registrations.exs
    - apps/server/test/keepling_web/mcp/metadata_test.exs
    - apps/server/test/keepling_web/mcp/registration_test.exs
  modified:
    - apps/server/lib/keepling_web/mcp/pipeline.ex
    - apps/server/lib/keepling_web/router.ex
    - apps/server/lib/keepling/accounts/device_grant.ex
    - apps/server/lib/keepling/accounts.ex
    - apps/server/lib/keepling/accounts/rate_limit.ex
    - apps/server/lib/keepling/accounts/security_audit.ex
    - apps/server/lib/keepling_web/controllers/device_grant_controller.ex

key-decisions:
  - "Task 1 (checkpoint:decision) answered Option A exactly as CONTEXT.md's D-29 already locked it: scoped RFC 7591 DCR behind the authenticated Keepling session. The owner's day-one dogfood hosts are Claude Code (no DCR needed) and Cowork (almost certainly DCR-dependent per its app-side connector flow) -- both stay reachable. No alternative was proposed; the checkpoint exists to put the confirmation on record before the one-way door (D-29) is walked through, per the plan's own text."
  - "The plan's literal event name 'mcp_token_audience_rejected' was renamed to 'mcp_audience_rejected'. The literal substring 'token' inside apps/server/lib/keepling/accounts/security_audit.ex is forbidden by the pre-existing, unrelated privacy invariant test test/keepling/telemetry_redaction_test.exs (it refutes that file's source contains 'token', 'password', 'account_id', etc., to keep raw-credential leakage structurally unreachable). Renaming preserves the exact same audit semantics; only the spelling changed. Applied to the migration CHECK constraint, the closed vocabulary list, KeeplingWeb.MCP.Pipeline, and the test."
  - "device_grants.resource is a nullable column, not a column required-for-mcp at the database layer. A real HTTP-obtained mcp grant always carries it (DeviceGrantController's @mcp_authorize_keys/@mcp_exchange_keys already require the RFC 8707 resource parameter present and equal to the canonical URI, from 05-01). A pre-existing direct-module-level test (mcp_client_kind_test.exs, not owned by this plan) bypasses the controller and omits it; KeeplingWeb.MCP.Pipeline's audience check treats a NULL stored resource the same as any other mismatch -- refused, never treated as 'no check applies' -- so this relaxation adds no exploitable gap."
  - "Redirect-URI validation was unified into exactly one function, Keepling.Accounts.DeviceGrant.validate_redirect/3 (single clause, verified by git grep -n 'defp validate_redirect' -- apps/server/lib returning exactly one line), serving both the static per-client-kind config allow-list and a new per-registration allow-list looked up from mcp_client_registrations. This required touching device_grant.ex, which is NOT in Task 3's frontmatter files_modified list -- the acceptance criterion explicitly requiring one shared function made this unavoidable; documented here as the deviation it is."

patterns-established:
  - "A discovery-document module (Metadata) is the single source of a canonical value (the MCP resource URI) that the authorization code elsewhere in the same subsystem also enforces -- callers delegate rather than restate."
  - "Client-kind resolution happens BEFORE request-shape validation, not intermixed with it, so a dynamically-registered client and a pre-registered one can share every downstream validation path."

requirements-completed: [MCP-01, MCP-02]

coverage:
  - id: D1
    description: "A spec-conformant MCP client discovers this server's authorization endpoints without hardcoding any path, starting from an unauthenticated 401 on the MCP endpoint."
    requirement: "MCP-01"
    verification:
      - kind: integration
        ref: "test/keepling_web/mcp/metadata_test.exs#GET /.well-known/oauth-protected-resource returns exactly the required keys and no account-specific value"
        status: pass
      - kind: integration
        ref: "test/keepling_web/mcp/metadata_test.exs#GET /.well-known/oauth-authorization-server returns exactly the required keys"
        status: pass
      - kind: integration
        ref: "test/keepling_web/mcp/metadata_test.exs#an unauthenticated POST /mcp/v1 returns 401 with a WWW-Authenticate resource_metadata challenge"
        status: pass
    human_judgment: false
  - id: D2
    description: "A representative host that performs Dynamic Client Registration unconditionally can register behind the authenticated session and complete the full authorization-code + S256 PKCE flow through a real registered redirect URI."
    requirement: "MCP-02"
    verification:
      - kind: integration
        ref: "test/keepling_web/mcp/registration_test.exs#a registered client_id completes authorize, exchange, and tools/call, bound to its own redirect"
        status: pass
    human_judgment: true
    rationale: "The automated test proves the full registration-then-authorize-then-exchange-then-tools/call path against this server's own real OAuth/PKCE/MCP code, but 05-VALIDATION.md's Manual-Only Verifications table names an actual Claude Desktop (or Cowork) connector run as the closing proof for D-29 -- this execution environment has no reachable MCP host, so that specific host-behavior check could not be performed and is disclosed as an open item, matching 05-01's D-30 precedent."
  - id: D3
    description: "An unauthenticated caller cannot register a client, and no registration request may set its own scope, client kind, or account association from request input."
    requirement: "MCP-02"
    verification:
      - kind: integration
        ref: "test/keepling_web/mcp/registration_test.exs#an unauthenticated caller cannot register a client and creates no row"
        status: pass
      - kind: integration
        ref: "test/keepling_web/mcp/registration_test.exs#a body carrying a key outside the closed allow-list is rejected"
        status: pass
    human_judgment: false
  - id: D4
    description: "A bearer whose grant's stored resource audience does not equal this server's canonical MCP resource URI is refused at /mcp/v1 with 401 and a recorded audit event."
    requirement: "MCP-01"
    verification:
      - kind: integration
        ref: "test/keepling_web/mcp/metadata_test.exs#a bearer whose grant's stored resource no longer matches the canonical MCP resource is refused and audited"
        status: pass
    human_judgment: false

duration: ~40min
completed: 2026-09-10
status: complete
---

# Phase 5 Plan 02: MCP Discovery, Audience Binding, and Scoped Dynamic Client Registration Summary

**RFC 9728/8414 discovery documents, an RFC 8707 audience-bound `/mcp/v1` bearer check, and a
session-gated RFC 7591 registration endpoint sharing one redirect-validation function with the
pre-registered electron/iphone/mcp paths.**

## Performance

- **Duration:** ~40 min
- **Tasks:** 3 (1 checkpoint:decision, 2 auto/tdd)
- **Files created:** 6
- **Files modified:** 7

## Accomplishments

- `GET /.well-known/oauth-protected-resource` and `GET /.well-known/oauth-authorization-server`
  serve exact, golden-key-set-asserted RFC 9728/8414 documents from `KeeplingWeb.MCP.Metadata`,
  deriving every value from `:keepling, :device_grants` configuration and
  `Keepling.Application.AgentScope.scopes()` -- no account-specific value, no internal identifier.
- Every `/mcp/v1` 401 (missing bearer, invalid bearer, audience mismatch) carries
  `WWW-Authenticate: Bearer resource_metadata="<absolute URL>"`, so a spec-conformant client
  discovers the authorization server from the 401 alone (must-have truth #1).
- `device_grants.resource` persists the RFC 8707 audience a real `mcp` grant was issued
  against (already validated equal to the canonical URI by `DeviceGrantController` since 05-01).
  `KeeplingWeb.MCP.Pipeline` re-checks it at every `/mcp/v1` request and refuses a mismatch with
  a recorded `mcp_audience_rejected` security-audit event (must-have truth #4).
- `KeeplingWeb.MCP.Registration.create/2`: RFC 7591 DCR gated on
  `conn.assigns.current_account_id` -- unauthenticated callers get 401 and create zero rows;
  scope, client kind, and account association are structurally unreachable from request input
  (closed-key body validator, `@allowed_keys` excludes them entirely). Returns a public client
  (`token_endpoint_auth_method: "none"`, no `client_secret`). Rate-limited through a new
  `:mcp_registration` `RateLimit` flow and records `mcp_client_registered`.
- `Keepling.Accounts.DeviceGrant.resolve_client/1` + one `validate_redirect/3` function serve
  both the pre-registered (electron/iphone/literal `mcp`) static-config redirect allow-list and a
  newly-registered client's own `redirect_uris` -- proven by a full register -> authorize ->
  exchange -> `tools/call` pass, and by a negative test that an unregistered redirect for a
  registered `client_id` is refused at `/oauth/authorize`.
- Full `mix test` suite: 215/215 passing (0 failures), including every pre-existing test from
  05-01 and Phases 1-4.

## Task Commits

1. **Task 1: Confirm the scoped registration endpoint before it becomes reachable by a host** --
   no code change; decision recorded below (checkpoint answered inline per CONTEXT.md's already-
   locked D-29, matching 05-01's precedent for its own Task 1).
2. **Task 2: Publish the discovery documents and bind the token audience** -- `a761cbb` (feat)
3. **Task 3: Session-gated RFC 7591 client registration** -- `4804a42` (feat, includes a
   formatting-only follow-up on two Task 2 files from running `mix format` scoped to this plan)

**Plan metadata:** committed alongside this SUMMARY.

## Files Created/Modified

- `apps/server/lib/keepling_web/mcp/metadata.ex` -- RFC 9728/8414 documents; the single source of
  `resource_uri/0` and `protected_resource_metadata_url/0`
- `apps/server/lib/keepling_web/mcp/registration.ex` -- RFC 7591 DCR controller
- `apps/server/lib/keepling_web/mcp/pipeline.ex` -- audience check, `WWW-Authenticate` with
  `resource_metadata`, `mcp_audience_rejected` recording
- `apps/server/lib/keepling_web/router.ex` -- `/.well-known/*` routes, `POST /oauth/register`
- `apps/server/lib/keepling/accounts/device_grant.ex` -- `resource` field/persistence,
  `resolve_client/1`, unified `validate_redirect/3`
- `apps/server/lib/keepling/accounts.ex` -- `resolve_device_client/1` delegate
- `apps/server/lib/keepling/accounts/rate_limit.ex` -- `:mcp_registration` flow
- `apps/server/lib/keepling/accounts/security_audit.ex` -- `mcp_audience_rejected`,
  `mcp_client_registered`
- `apps/server/lib/keepling_web/controllers/device_grant_controller.ex` -- client resolution,
  `resource` threading, delegates `canonical_mcp_resource/0` to `Metadata`
- `apps/server/priv/repo/migrations/20260911000150_add_mcp_resource_binding.exs` -- nullable
  `device_grants.resource`, widens the audit CHECK constraint
- `apps/server/priv/repo/migrations/20260911000200_add_mcp_client_registrations.exs` --
  `mcp_client_registrations` table, widens the audit CHECK constraint again
- `apps/server/test/keepling_web/mcp/metadata_test.exs`, `.../registration_test.exs` -- this
  plan's behavior and acceptance-criteria tests

## Decisions Made

See `key-decisions` in frontmatter for the four decisions and their full rationale: Task 1's
scoped-DCR confirmation, the `mcp_token_audience_rejected` -> `mcp_audience_rejected` rename, the
nullable (not required-for-mcp) `resource` column, and the single shared
`validate_redirect/3` requiring `device_grant.ex` edits beyond Task 3's stated file list.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Renamed the audit event to avoid violating an existing privacy invariant**
- **Found during:** Task 2, first full-suite run
- **Issue:** The plan's literal event name `mcp_token_audience_rejected`, once added to
  `security_audit.ex`'s closed vocabulary, made that file's source contain the substring
  `"token"` -- which `test/keepling/telemetry_redaction_test.exs` explicitly refutes across that
  exact file, to keep raw-credential/token leakage structurally unreachable from the audit
  vocabulary. The plan's own name was in direct conflict with a pre-existing codebase-wide
  invariant it did not anticipate.
- **Fix:** Renamed the event to `mcp_audience_rejected` everywhere it appears (migration CHECK
  constraint, `security_audit.ex`'s closed list, `KeeplingWeb.MCP.Pipeline`, the test's
  assertion). No semantic change -- same trigger, same audit table, same fields.
- **Files modified:** `apps/server/priv/repo/migrations/20260911000150_add_mcp_resource_binding.exs`,
  `apps/server/lib/keepling/accounts/security_audit.ex`, `apps/server/lib/keepling_web/mcp/pipeline.ex`,
  `apps/server/test/keepling_web/mcp/metadata_test.exs`
- **Verification:** `mix test` (full suite, 215/215) including `telemetry_redaction_test.exs`
- **Committed in:** `a761cbb` (Task 2 commit)

**2. [Rule 3 - Blocking] Made `device_grants.resource` nullable rather than required-for-`mcp`**
- **Found during:** Task 2, first full-suite run
- **Issue:** An initial CHECK constraint requiring `resource IS NOT NULL` whenever
  `client_kind = 'mcp'` broke a pre-existing direct-module-level test
  (`test/keepling/accounts/mcp_client_kind_test.exs`, not owned by this plan) that calls
  `Accounts.issue_device_authorization/3` directly, bypassing `DeviceGrantController`'s own
  mandatory-resource enforcement.
- **Fix:** Dropped the CHECK constraint; `resource` stays nullable at the DB layer for every
  client kind. A real HTTP-obtained `mcp` grant always has it set (the controller requires the
  RFC 8707 `resource` parameter present on `/oauth/authorize` and `/oauth/token` for `mcp`
  requests, unchanged from 05-01). `KeeplingWeb.MCP.Pipeline`'s audience check treats a `NULL`
  stored resource identically to any other mismatch -- refused, never bypassed.
- **Files modified:** `apps/server/priv/repo/migrations/20260911000150_add_mcp_resource_binding.exs`,
  `apps/server/lib/keepling/accounts/device_grant.ex`
- **Verification:** `mix test` (full suite, 215/215) including `mcp_client_kind_test.exs` unmodified
- **Committed in:** `a761cbb` (Task 2 commit)

**3. [Rule 3 - Blocking] Modified `device_grant.ex` despite it not being in Task 3's file list**
- **Found during:** Task 3 implementation
- **Issue:** Task 3's acceptance criteria require exactly one `defp validate_redirect` function
  serving both the configured (electron/iphone/literal `mcp`) redirect allow-list and a
  registered client's own redirect_uris. The pre-existing configured-redirect check lived
  entirely inside `device_grant.ex`'s private `allowed_redirect?/2`; satisfying "exactly one
  shared function" was structurally impossible without touching that module, even though it was
  not named in Task 3's `<files>` list.
- **Fix:** Replaced `allowed_redirect?/2` with `validate_redirect/3` (single clause; `git grep -n
  'defp validate_redirect' -- apps/server/lib` returns exactly one line), added
  `resolve_client/1` (public) to resolve a `client_id` to `{client_kind, registered_client_id |
  nil}`, and threaded an optional `:registered_client_id` key through
  `validate_authorization_request/1`'s closed-key validator (generalized to a `MapSet`-based
  subset check rather than an enumerated variant list, to avoid combinatorial blowup as more
  optional keys accumulate).
- **Files modified:** `apps/server/lib/keepling/accounts/device_grant.ex`,
  `apps/server/lib/keepling/accounts.ex`, `apps/server/lib/keepling_web/controllers/device_grant_controller.ex`
- **Verification:** `mix test` (full suite, 215/215); `registration_test.exs`'s full
  register->authorize->exchange->`tools/call` pass and its negative unregistered-redirect test
- **Committed in:** `4804a42` (Task 3 commit)

**4. [Rule 3 - Blocking] Isolated the `:mcp_registration` rate-limit bucket per test**
- **Found during:** Task 3, `registration_test.exs` first run
- **Issue:** `Keepling.Accounts.RateLimit`'s ETS-backed bucket state is process-global and is
  NOT scoped by the Ecto SQL Sandbox. Every request to `/oauth/register` consumes a rate-limit
  hit (even a rejected one, since `RateLimit.admit/2` runs before body validation), so earlier
  tests in the same file silently consumed part of the account-scoped budget before the
  dedicated rate-limit test ran, making its expected pass/fail counts order-dependent.
- **Fix:** Added `:ets.delete_all_objects(Keepling.Accounts.RateLimit)` to the test file's
  `setup` block, alongside the existing SQL cleanup of `mcp_client_registrations`,
  `account_security_audits`, and `accounts`.
- **Files modified:** `apps/server/test/keepling_web/mcp/registration_test.exs`
- **Verification:** `mix test test/keepling_web/mcp/registration_test.exs` (7/7 passing,
  deterministic across repeated runs and seeds)
- **Committed in:** `4804a42` (Task 3 commit)

---

**Total deviations:** 4 auto-fixed (1 bug, 3 blocking). **Impact on plan:** All four were
necessary for correctness, for a genuine pre-existing privacy invariant, or for the plan's own
stated acceptance criteria. No scope creep -- no capability was added beyond MCP-01/MCP-02 and
D-29's scoped-DCR requirement.

## Known Stubs

None specific to this plan's scope. Carried forward from 05-01, still open: `resources/*`
JSON-RPC methods are not yet implemented despite the `resources` capability being advertised
(05-04 or a later plan's scope, unchanged by this plan); `update_task`, `complete_task`,
`reopen_task` remain unimplemented MCP tools (MCP-02's remaining three verbs, unchanged by this
plan -- this plan touched authorization/discovery/registration, not the tool surface).

## Broken-Windows Ledger

Recorded to `.planning/WINDOWS.md` (if the ledger is present in this project):

- deviation: `apps/server/lib/keepling/accounts/security_audit.ex` -- plan-specified event name
  `mcp_token_audience_rejected` renamed to `mcp_audience_rejected` to satisfy the pre-existing
  `telemetry_redaction_test.exs` "no literal 'token' substring" invariant
- deviation: `apps/server/lib/keepling/accounts/device_grant.ex` -- modified despite not being in
  Task 3's `<files>` list, required by the acceptance criterion demanding one shared
  `validate_redirect` function

## Issues Encountered

- **Manual-only verification not performed.** `05-VALIDATION.md`'s Manual-Only Verifications
  table names an actual Claude Desktop (or Cowork) connector registration run as the closing
  proof for D-29. This execution environment has no reachable MCP host, matching 05-01's
  disclosed D-30 gap for the exact same reason. The automated `registration_test.exs` proves the
  full register-then-authorize-then-exchange-then-`tools/call` path against this server's own
  real OAuth/PKCE/MCP code, but the host-side connector behavior (does Claude Desktop's actual
  DCR request shape match what this endpoint accepts? does its consent screen name the exact
  scopes?) is not empirically checked. This is a genuine, disclosed gap for the phase's
  representative-model/adversarial evidence lanes to close once a real host/credential is
  available, not a silently-skipped step.

## User Setup Required

None -- no external service configuration required. (Unchanged from 05-01: a future plan's
representative-model/adversarial evidence lanes and the manual host-connector check above will
need a reachable MCP host and/or a model API credential.)

## Next Phase Readiness

- MCP-01's read-surface discovery requirement and MCP-02's write-surface authorization/
  registration requirements are both proven by named, passing assertions -- discovery documents,
  audience binding, and scoped DCR are no longer designed-only, they are implemented and tested.
- `KeeplingWeb.MCP.Metadata`, `Keepling.Accounts.DeviceGrant.resolve_client/1`, and the unified
  `validate_redirect/3` are the extension points later plans (05-04's read surface, 05-05's
  remaining write tools) build on without altering any module boundary this plan introduced.
- Blocker carried forward from 05-01, unchanged: no MCP host or model credential is reachable in
  this environment, blocking the phase's representative-model/adversarial evidence lanes (D-26),
  the D-30 live-host protocol re-check, and this plan's own manual DCR-connector verification.
  Whoever executes those later plans/checks needs that credential/host provisioned first.
- MCP-01 and MCP-02 requirement IDs: both declared only by this plan among KPL-05's plans
  (confirmed no sibling plan also declares them), so `requirements.mark-complete` will check them
  off during state update.

---
*Phase: KPL-05-safe-agent-access*
*Completed: 2026-09-10*
