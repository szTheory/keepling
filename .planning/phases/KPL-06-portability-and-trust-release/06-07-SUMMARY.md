---
phase: KPL-06-portability-and-trust-release
plan: 07
subsystem: trust-surface
tags: [agent-consent, device-grants, mutation-receipts, openapi, absent-vs-empty, D-38, D-39, T-06-07]

requires:
  - phase: KPL-06-01
    provides: an honest, correction-first record before new Phase 6 feature work builds on it
provides:
  - Real published grant scope/authorized_at/last_used_at on the agent consent screen, backed by a round-tripping migration and a mutation-gated write path
  - A mutation receipt readable only by the grant that issued it, closing the receipt-scope inversion any tasks.write-scoped agent previously exploited
  - AgentGrantList.tsx's null-lastUsedAt copy corrected from a proven-zero claim to the unknown copy, matching the existing absent-vs-empty pattern for scope/authorizedAt
affects: [KPL-06-09-o22-fix, KPL-06-13-final-verification]

actuals:
  tokens: 7689
  tasks: 4
  commits: 3

tech-stack:
  added: []
  patterns:
    - "A narrow, single-purpose companion function (CommandStore.receipt_issuer/2) beside a general-purpose lookup (lookup_result/2), rather than widening the general function's return shape and breaking every exact-equality caller that already depends on it byte-for-byte"
    - "A bookkeeping write (last_used_at advance) runs inside the same transaction as the mutation it accompanies but is deliberately non-bang/rescue-wrapped so its own failure never fails the user's request"

key-files:
  created:
    - apps/server/priv/repo/migrations/20260912000100_add_device_grant_last_used_at.exs
    - apps/server/priv/repo/migrations/20260912000200_add_command_receipts_issuing_grant.exs
  modified:
    - apps/server/lib/keepling/accounts/device_grant.ex
    - apps/server/lib/keepling_web/controllers/device_grant_controller.ex
    - apps/server/lib/keepling/adapters/postgres/command_store.ex
    - apps/server/lib/keepling_web/auth.ex
    - apps/server/lib/keepling_web/controllers/command_controller.ex
    - apps/server/lib/keepling_web/mcp/dispatch.ex
    - apps/server/lib/keepling_web/mcp/tools.ex
    - packages/contracts/openapi/keepling.yaml
    - packages/contracts/generated/keepling.ts
    - apps/server/test/keepling_web/device_grant_controller_test.exs
    - apps/server/test/keepling_web/agent_authorization_test.exs
    - apps/web/src/features/agents/AgentGrantList.tsx
    - apps/web/src/features/agents/agent-grant-list.test.tsx
    - apps/web/src/api/keepling.ts

key-decisions:
  - "Task 1 (checkpoint:decision): selected Option A -- only a first-delivered mutation advances last_used_at, at no coarsened granularity beyond the mutation's own accepted_at instant, and a null value means not-yet-measured. Lowest write volume, most meaningful consent-screen signal, and keeps the null render on the already-established unknown-copy branch."
  - "The receipt-scope-inversion fix (Task 3) required infrastructure well beyond its declared files_modified (auth.ex only): no column anywhere recorded which grant issued a mutation, so closing the inversion required a new command_receipts.issuing_grant_id column, a write-path threading of device_grant_id through both the HTTP command surface and the MCP JSON-RPC tool-call path, and a narrow new CommandStore.receipt_issuer/2 query -- documented as a Rule 2/3 deviation below."
  - "Kept Commands.lookup_result/3's return shape byte-for-byte unchanged rather than adding issuing_grant_id to it directly -- two pre-existing tests compare its return value with exact `==` against Commands.dispatch's own result, and widening the shared shape broke both. The ownership check reads issuing identity through a separate, deliberately narrow function instead."
  - "A null last_used_at renders 'Not yet reported' unconditionally in this plan's UI, never 'Not yet used', even though Task 2's own write path now makes a null value provably mean zero recorded mutations for a grant -- the plan's own acceptance criteria require this literally, reserving the zero-activity copy for a future, more explicit signal rather than inferring it from null in this pass."

patterns-established:
  - "A single-purpose read function beside a general one, rather than widening a general contract every existing caller already depends on exactly."

requirements-completed: [QUAL-04]

coverage:
  - id: D1
    description: "The agent consent screen publishes real scope/authorized_at/last_used_at values (not placeholders), with correct absent-vs-empty nullability, backed by a round-tripping migration and a mutation-gated write path"
    requirement: "QUAL-04"
    verification:
      - kind: unit
        ref: "apps/server/test/keepling_web/device_grant_controller_test.exs -- \"the response publishes real scope/authorized_at/last_used_at, and last_used_at advances only on a mutation\""
        status: pass
      - kind: other
        ref: "mix ecto.migrate && mix ecto.rollback --step 1 && mix ecto.migrate (round-trip, both new migrations)"
        status: pass
      - kind: other
        ref: "pnpm contracts:generate && git diff --exit-code -- packages/contracts/generated/keepling.ts"
        status: pass
      - kind: other
        ref: "pnpm contracts:check"
        status: pass
    human_judgment: false
  - id: D2
    description: "A mutation receipt is readable only by the grant that issued it; a different grant holding the identical write scope is refused with the constant insufficient-scope body"
    requirement: "QUAL-04"
    verification:
      - kind: unit
        ref: "apps/server/test/keepling_web/agent_authorization_test.exs -- \"a mutation receipt is readable only by the grant that issued it, even across grants sharing the same scope\""
        status: pass
      - kind: unit
        ref: "apps/server/test/keepling_web/ (full directory, 25 tests) and apps/server/test/ (full suite, 332 tests) -- no regression"
        status: pass
    human_judgment: false
  - id: D3
    description: "AgentGrantList.tsx renders the unknown copy for a null value on scope, authorized, and last-used independently; the genuinely-no-scopes copy renders only for a literal empty array; a row with one unknown field renders the rest normally"
    requirement: "QUAL-04"
    verification:
      - kind: unit
        ref: "apps/web/src/features/agents/agent-grant-list.test.tsx (14 tests, vitest)"
        status: pass
      - kind: other
        ref: "grep -c 'Not yet reported' apps/web/src/features/agents/AgentGrantList.tsx == 3"
        status: pass
      - kind: other
        ref: "pnpm typecheck:web && pnpm lint:web"
        status: pass
    human_judgment: false

duration: ~70min
completed: 2026-09-11
status: complete
---

# Phase KPL-06 Plan 07: Agent Consent Screen Truth and Receipt-Scope Closure Summary

**Published real grant scope/authorized_at/last_used_at from the server (replacing a placeholder), closed a receipt-scope inversion that let any tasks.write-scoped agent read any other agent's mutation receipt, and fixed the consent screen's null-last-used copy to stop asserting a fact nobody measured.**

## Performance

- **Duration:** ~70 min
- **Tasks:** 4 (1 checkpoint:decision, 3 auto+tdd)
- **Files modified:** 16 (2 created, 14 modified)

## Accomplishments

- **Task 1 (checkpoint:decision):** Selected Option A -- only a first-delivered mutation advances `last_used_at`, at the mutation's own `accepted_at` granularity, with `null` meaning not-yet-measured until a qualifying event occurs.
- **Task 2:** Added a nullable `last_used_at` column to `device_grants` (kept structurally separate from the OAuth-refresh-only `last_refreshed_at`); widened `Accounts.DeviceGrant.list/1` and `grant_response/1` to publish real `scope`, `authorized_at`, and `last_used_at`; wired a transaction-scoped, failure-tolerant write path that advances `last_used_at` only on a first-delivered mutation; widened `DeviceGrantSummary` in the OpenAPI contract with correct nullability and regenerated the TypeScript contract with zero drift.
- **Task 3:** Closed the receipt-scope inversion (T-06-07-01/D-39): added a nullable `issuing_grant_id` column to `command_receipts`, threaded the requester's device-grant identity through both the shared HTTP command surface (`command_controller.ex`) and the MCP JSON-RPC tool-call write path (`dispatch.ex`/`tools.ex`), and added `KeeplingWeb.Auth.authorize_receipt_read/1` -- an extension of the existing `require_agent_authority/1` match-and-dispatch shape, not a new middleware layer -- that refuses a mismatched-owner read with the byte-identical constant insufficient-scope 403 body, while a `nil` issuer (session, first-party, or a receipt pre-dating this column) and a genuinely missing mutation both fall through unrefused to the controller's ordinary handling.
- **Task 4:** Fixed `AgentGrantList.tsx`'s null-`lastUsedAt` render, which previously asserted the proven-zero-activity copy (`"Not yet used"`) for a value the server had never measured -- now renders the unknown copy (`"Not yet reported"`), matching the pre-existing pattern already used for scope and `authorizedAt`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Decide what event advances a device grant's last-used timestamp** -- no commit (decision-only checkpoint; recorded in Decisions Made below)
2. **Task 2: Add the last-used column, its write path, and the widened grant response** -- `75ab74c` (feat)
3. **Task 3: Bind a mutation receipt read to the grant that issued it** -- `3680665` (fix)
4. **Task 4: Render the published values without collapsing unknown into zero** -- `f97145d` (fix)

**Plan metadata:** (this commit, following)

## Files Created/Modified

- `apps/server/priv/repo/migrations/20260912000100_add_device_grant_last_used_at.exs` -- nullable `last_used_at` column on `device_grants`
- `apps/server/priv/repo/migrations/20260912000200_add_command_receipts_issuing_grant.exs` -- nullable `issuing_grant_id` column on `command_receipts`, FK to `device_grants`, `ON DELETE SET NULL`
- `apps/server/lib/keepling/accounts/device_grant.ex` -- schema field; `list/1` selects and publishes `scope`, `authorized_at`, `last_used_at`
- `apps/server/lib/keepling_web/controllers/device_grant_controller.ex` -- `grant_response/1` widened with the three new keys
- `apps/server/lib/keepling/adapters/postgres/command_store.ex` -- write path for `issuing_grant_id` and `last_used_at`; new `receipt_issuer/2` companion query
- `apps/server/lib/keepling_web/auth.ex` -- `authorize_receipt_read/1`, wired into `require_agent_authority/1`
- `apps/server/lib/keepling_web/controllers/command_controller.ex` -- `context/1` carries `device_grant_id`
- `apps/server/lib/keepling_web/mcp/dispatch.ex` -- JSON-RPC `context/1` carries `device_grant_id`
- `apps/server/lib/keepling_web/mcp/tools.ex` -- `dispatch_context/1` carries `device_grant_id` through to the write path
- `packages/contracts/openapi/keepling.yaml` / `packages/contracts/generated/keepling.ts` -- widened `DeviceGrantSummary`
- `apps/server/test/keepling_web/device_grant_controller_test.exs` -- new response-shape and write-path-gating test
- `apps/server/test/keepling_web/agent_authorization_test.exs` -- new cross-grant receipt-refusal test
- `apps/web/src/features/agents/AgentGrantList.tsx` -- corrected null-`lastUsedAt` copy
- `apps/web/src/features/agents/agent-grant-list.test.tsx` -- two new test cases
- `apps/web/src/api/keepling.ts` -- corrected a now-stale comment (no behavior change)

## Decisions Made

See `key-decisions` in frontmatter. In prose: Task 1's checkpoint selected the lowest-write-volume, most-meaningful option (mutations only, mutation-instant granularity, null means not-measured) exactly as the plan's own recommended default described. Task 3's scope grew well beyond its declared `files_modified` because the architecture genuinely had no way to record "who issued this mutation" anywhere -- that gap, not a design preference, is why the fix touches a migration and five additional files. `Commands.lookup_result/3`'s public return shape was deliberately left untouched (a first attempt to add `issuing_grant_id` to it broke two pre-existing exact-equality tests) in favor of a narrow, single-purpose companion function. Task 4's null-`lastUsedAt` mapping stays unconditionally "unknown" per the plan's own literal acceptance criteria, even though the newly-added write path technically could support a "provably zero" claim -- that stronger claim is deliberately deferred.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2/3 - Missing critical functionality / blocking] Task 3 required a new migration, write-path threading, and a new query function beyond its declared `apps/server/lib/keepling_web/auth.ex`-only scope**
- **Found during:** Task 3 (binding a mutation receipt read to its issuing grant)
- **Issue:** No column anywhere in the schema recorded which device grant issued a mutation. `auth.ex` alone has no way to answer "was this mutation issued by the current grant?" without that data existing and being queryable.
- **Fix:** Added `command_receipts.issuing_grant_id` (migration), threaded `device_grant_id` through `command_controller.ex`'s and `dispatch.ex`'s context builders and `tools.ex`'s `dispatch_context/1` so the write path can record it, and added `CommandStore.receipt_issuer/2` -- a narrow, `Commands.Port`-external query used only by `auth.ex`'s new ownership check.
- **Files modified:** `apps/server/priv/repo/migrations/20260912000200_add_command_receipts_issuing_grant.exs`, `apps/server/lib/keepling/adapters/postgres/command_store.ex`, `apps/server/lib/keepling_web/controllers/command_controller.ex`, `apps/server/lib/keepling_web/mcp/dispatch.ex`, `apps/server/lib/keepling_web/mcp/tools.ex`
- **Verification:** New cross-grant test in `agent_authorization_test.exs`; full server suite (332 tests) and `pnpm contracts:check` unaffected.
- **Committed in:** `3680665` (Task 3 commit)

**2. [Rule 1 - Bug, self-caught during verification] Widening `Commands.lookup_result/3`'s return shape broke two pre-existing exact-equality tests**
- **Found during:** Task 3, first full-suite verification run
- **Issue:** An initial implementation added `issuing_grant_id` directly to `lookup_result/2`'s returned map. Two pre-existing tests (`idempotency_test.exs`, `task_dates_test.exs`) assert `elem(rejected, 1) == result` between `Commands.dispatch`'s direct result and `Commands.lookup_result`'s replayed result -- the added key broke both equalities.
- **Fix:** Reverted `lookup_result/2` to its original return shape and added the ownership-check data through the separate `receipt_issuer/2` function instead, called only from `auth.ex`.
- **Files modified:** `apps/server/lib/keepling/adapters/postgres/command_store.ex`
- **Verification:** Full server suite re-run, 332/332 passing.
- **Committed in:** `3680665` (Task 3 commit; the regression was caught and fixed before that commit was made)

**3. [Rule 1 - Doc bug] Stale comment in `apps/web/src/api/keepling.ts`**
- **Found during:** Task 4
- **Issue:** A comment above `WireAgentGrantSummary` asserted the server "does not yet publish `scope`, `last_used_at`, or `authorized_at`" -- true before this plan, false after Task 2.
- **Fix:** Corrected the comment to describe the current, accurate state; left the defensive `?:` type markers in place (harmless) and the still-true `client_kind` staleness note unchanged (that gap is unrelated to this plan).
- **Files modified:** `apps/web/src/api/keepling.ts`
- **Verification:** `pnpm typecheck:web`, `pnpm lint:web` (comment-only change, no logic affected).
- **Committed in:** `f97145d` (Task 4 commit)

---

**Total deviations:** 3 (1 missing-critical/blocking necessary for Task 3's stated acceptance criteria, 1 self-caught bug from the first attempt at that same fix, 1 doc-only correction).
**Impact on plan:** All three are necessary for correctness or accuracy; no scope creep beyond what Task 3's own acceptance criteria required and no functional change from the doc fix.

## Issues Encountered

None beyond the deviations above.

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness

The consent screen now states real values and a mutation receipt is bound to its issuing grant. `docs/architecture/MCP-SURFACE.md`'s trust boundary at "agent bearer token -> mutation receipt read" is closed structurally, not by convention. Plan 06-09 (O-22 fix) and the phase's final verification lane both build on this record.

No blockers introduced by this plan.

---
*Phase: KPL-06-portability-and-trust-release*
*Completed: 2026-09-11*

## Self-Check: PASSED

- All key-files.created exist on disk (verified with `[ -f ]`).
- All three task commits (`75ab74c`, `3680665`, `f97145d`) exist in `git log --oneline --all`.
- Re-ran every task's `<verify>` block: migration round-trips (both new migrations), `mix test test/keepling_web/device_grant_controller_test.exs` and `agent_authorization_test.exs` (25 tests), `mix test` (full suite, 332 tests), `pnpm contracts:generate` + no-diff check, `pnpm contracts:check`, `grep -n 'last_refreshed_at' device_grant_controller.ex` (no match inside `grant_response/1`), `pnpm --dir apps/web exec vitest run src/features/agents` (14 tests), `pnpm typecheck:web`, `pnpm lint:web`, `grep -c 'Not yet reported' AgentGrantList.tsx` (3) -- all pass.
