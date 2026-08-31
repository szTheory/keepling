---
phase: KPL-01-one-trustworthy-task
plan: 05
subsystem: trustworthy-capture
tags: [elixir, phoenix, postgresql, react, playwright, openapi, idempotency, csrf]

requires:
  - phase: KPL-01-03
    provides: Phoenix endpoint, SQL Sandbox cases, independent-connection barrier, and inward-dependency guard
  - phase: KPL-01-04
    provides: Real-stack Playwright orchestration and checked-in OpenAPI generation/drift enforcement
provides:
  - Authenticated React-to-PostgreSQL capture tracer with explicit Inbox state and exact acknowledgement
  - Account-scoped transaction receipt arbitration with stable replay and mutation-identity reuse detection
  - One-transaction task snapshot, activity fact, and terminal result persistence
  - Executable proof that pre-authentication, origin, CSRF, and structural failures create no receipts
affects: [KPL-01-06, KPL-01-07, KPL-01-08, semantic-commands, browser-recovery, activity-history]

actuals:
  tokens: 19886
  tasks: 2
  commits: 5

tech-stack:
  added: []
  patterns: [pure semantic decision, account-scoped receipt gate, native JSONB terminal envelope, generated transport plus handwritten facade, independent PostgreSQL race proof]

key-files:
  created:
    - apps/server/lib/keepling/domain/task.ex
    - apps/server/lib/keepling/application/commands.ex
    - apps/server/lib/keepling/adapters/postgres/command_store.ex
    - apps/server/lib/keepling_web/auth.ex
    - apps/server/lib/keepling_web/controllers/command_controller.ex
    - apps/server/priv/repo/migrations/20260830000100_create_core_task_command_tables.exs
    - apps/server/test/keepling/adapters/postgres/idempotency_test.exs
    - apps/web/e2e/skeleton.spec.ts
    - apps/web/src/api/keepling.ts
    - apps/web/src/features/capture/QuickCapture.tsx
  modified:
    - apps/server/lib/keepling_web/router.ex
    - apps/server/priv/repo/seeds.exs
    - apps/web/e2e/support/stack.ts
    - apps/web/playwright.config.ts
    - apps/web/src/App.tsx
    - apps/web/src/index.css
    - apps/web/src/main.tsx
    - packages/contracts/openapi/keepling.yaml
    - packages/contracts/generated/keepling.ts

key-decisions:
  - "Capture fingerprints use canonical semantic fields, including the trimmed title, and exclude the receipt's mutation identity from the fingerprint payload."
  - "Terminal acknowledgements and activity field deltas are persisted as native JSONB values, preserving the same closed map shape for first delivery, lookup, and replay."
  - "The mutation lookup returns the original stored HTTP status, while OpenAPI and the browser facade expose every accepted/problem terminal class and acknowledgement warnings."

patterns-established:
  - "Receipt gate: insert the account/mutation key under its unique constraint; the winner commits effect, activity, and terminal result, while losers replay only after the winner commits."
  - "Trust boundary: session/account, CSRF, origin, and closed DTO decoding all complete before the shared semantic command can create a receipt."
  - "Browser acknowledgement: generated wire DTOs are mapped through a handwritten facade, and drafts clear only when returned mutation identity matches submission identity."

requirements-completed: [GTD-01, SRV-01, SRV-02, SRV-03, WEB-01, QUAL-01]

coverage:
  - id: D1
    description: "A seeded closed-account browser authenticates, captures into explicit Inbox state, receives the exact acknowledgement, and reloads the PostgreSQL-backed task."
    requirement: GTD-01
    verification:
      - kind: e2e
        ref: "apps/web/e2e/skeleton.spec.ts#@skeleton captures one authenticated task and reloads it from PostgreSQL"
        status: pass
    human_judgment: false
  - id: D2
    description: "Concurrent identical first deliveries on independent PostgreSQL backends create one task/activity/receipt and return one stable stored envelope."
    requirement: SRV-03
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/adapters/postgres/idempotency_test.exs#independent first deliveries converge on one stored envelope"
        status: pass
    human_judgment: false
  - id: D3
    description: "Changed semantics under one mutation identity return mutation_identity_reused without changing task or activity counts; authenticated semantic rejection remains replayable."
    requirement: SRV-03
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/adapters/postgres/idempotency_test.exs#authenticated semantic rejection is terminal and replayable"
        status: pass
    human_judgment: false
  - id: D4
    description: "React reaches persistence only through generated transport, the handwritten facade, Phoenix mapping, and the shared inward semantic command boundary."
    requirement: SRV-02
    verification:
      - kind: integration
        ref: "apps/server/test/architecture_test.exs#domain and semantic application sources have no outward dependencies"
        status: pass
      - kind: other
        ref: "pnpm contracts:check"
        status: pass
    human_judgment: false

duration: 26min
completed: 2026-08-30
status: complete
---

# Phase KPL-01 Plan 05: Production Capture and Exact Replay Summary

**Authenticated React capture through one semantic Phoenix command into PostgreSQL, with account-scoped receipt arbitration, stable JSONB replay, and real independent-connection race proof**

## Performance

- **Duration:** 26 min
- **Started:** 2026-08-31T01:42:37Z
- **Completed:** 2026-08-31T02:08:48Z
- **Tasks:** 2
- **Files modified:** 20

## Accomplishments

- Shipped the accepted production walking skeleton: a closed-account browser session captures a titled task into explicit Inbox state, receives its exact mutation acknowledgement, and reloads the durable PostgreSQL projection.
- Kept domain capture pure and transport/storage representations separate while routing React through a handwritten API facade, generated OpenAPI types, Phoenix, and the shared application command.
- Proved duplicate first delivery on two physical PostgreSQL backends produces one task, one activity, one receipt, and semantically identical stored envelopes.
- Persisted authenticated semantic terminal results while proving pre-authentication, origin, CSRF, and structurally invalid requests never enter the receipt store.

## Task Commits

Each task followed its TDD gates and was committed atomically:

1. **Task 1 infrastructure prerequisite: Make real-stack E2E lifecycle executable** - `8eeb422` (fix)
2. **Task 1 RED: Add failing authenticated capture skeleton** - `ce3e881` (test)
3. **Task 1 GREEN: Walk authenticated capture through the production stack** - `a6b2fd9` (feat)
4. **Task 2 RED: Add failing independent-connection idempotency proof** - `33c1da8` (test)
5. **Task 2 GREEN: Make capture replay transactionally exact** - `3b5a537` (feat)

## Files Created/Modified

- `apps/server/lib/keepling/domain/task.ex` - Pure capture decision with canonical title, explicit Inbox state, revision 1, and closed captured activity.
- `apps/server/lib/keepling/application/commands.ex` - Shared semantic command/query port used by outward adapters.
- `apps/server/lib/keepling/adapters/postgres/command_store.ex` - Unique receipt gate, stable replay, task/activity transaction, semantic problems, and account-scoped reads.
- `apps/server/lib/keepling_web/auth.ex` and `apps/server/lib/keepling_web/controllers/command_controller.ex` - Hashed test-session fixture, session/account derivation, origin/CSRF boundary, DTO decoding, and RFC 9457 mapping.
- `apps/server/priv/repo/migrations/20260830000100_create_core_task_command_tables.exs` - Singleton account/session, task, receipt, and activity constraints for the tracer.
- `apps/server/test/keepling/adapters/postgres/idempotency_test.exs` - Real backend race, exact replay, semantic mismatch, stored rejection, and pre-receipt trust-boundary proof.
- `packages/contracts/openapi/keepling.yaml` and `packages/contracts/generated/keepling.ts` - Versioned capture/session/Inbox/mutation transport and deterministic generated TypeScript.
- `apps/web/src/api/keepling.ts` - Handwritten semantic facade that maps generated transport into browser values and preserves warnings.
- `apps/web/src/features/capture/QuickCapture.tsx` and `apps/web/src/App.tsx` - Accessible Inbox capture UI that holds fixed identities until exact acknowledgement.
- `apps/web/e2e/skeleton.spec.ts` - Real Chromium/Phoenix/PostgreSQL tracer evidence.

## Decisions Made

- Canonicalize fingerprint input at the persistence gate using the command type/version, target identity, and trimmed title; the receipt key already scopes mutation identity, so identity itself is not semantic fingerprint content.
- Pass maps directly through Postgrex's JSONB encoder. Pre-encoding with Jason creates a JSON string value and breaks stable replay shape.
- Preserve the original terminal HTTP status for mutation lookup, including 201 acknowledgement and 409/422 problems, instead of inventing a lookup-only result shape.

## Human Verification

The authenticated production capture tracer reached its blocking human-verification checkpoint after `a6b2fd9`. The user response was `approved`, so Task 2 proceeded without redoing or altering the accepted tracer.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Made the real-stack E2E lifecycle executable before RED**
- **Found during:** Task 1 setup
- **Issue:** Mix commands were launched from the wrong boundary, owned process groups stopped serially, and Playwright failure artifacts were not covered by the existing ignore rule.
- **Fix:** Routed Mix through runtime preflight from the repository root, stopped owned processes together, and ignored generated Playwright artifacts.
- **Files modified:** `.gitignore`, `apps/web/e2e/support/stack.ts`, `apps/web/playwright.config.ts`
- **Verification:** The real-stack skeleton starts and stops PostgreSQL 18.6, Phoenix, Vite, and the proxy without leaked processes.
- **Committed in:** `8eeb422`

**2. [Rule 3 - Blocking] Added an explicitly test-only closed-account seed**
- **Found during:** Task 1 GREEN
- **Issue:** The required authenticated browser tracer had no account to sign into, while production bootstrap correctly remained closed for Plan 01-06.
- **Fix:** Added a deterministic account only when both Mix test mode and the isolated Phase 1 E2E seed gate are active.
- **Files modified:** `apps/server/priv/repo/seeds.exs`
- **Verification:** Playwright authenticates the seeded account; normal deployment seeds still create no account.
- **Committed in:** `a6b2fd9`

**3. [Rule 2 - Missing Critical] Applied the approved accessible capture baseline**
- **Found during:** Task 1 GREEN
- **Issue:** A public-facing production tracer required the approved semantic light/dark tokens, visible focus, Reduce Motion, and forced-colors behavior not present in the initial shell.
- **Fix:** Applied the Phase 1 UI-SPEC roles and platform preference hooks without selecting a final logo or palette.
- **Files modified:** `apps/web/src/index.css`, `apps/web/src/main.tsx`
- **Verification:** Production web build and authenticated browser tracer pass; the user approved the rendered tracer checkpoint.
- **Committed in:** `a6b2fd9`

**4. [Rule 1 - Bug] Corrected double-encoded JSONB terminal results**
- **Found during:** Task 2 RED
- **Issue:** First delivery returned a map, but the receipt stored a JSON string because maps were Jason-encoded before Postgrex JSONB encoding; concurrent replay therefore returned a different semantic shape.
- **Fix:** Passed terminal bodies and changed-field maps directly to the JSONB encoder and canonicalized fingerprint content.
- **Files modified:** `apps/server/lib/keepling/adapters/postgres/command_store.ex`
- **Verification:** The independent-connection test now passes 3/3, with one stable envelope and one task/activity/receipt.
- **Committed in:** `3b5a537`

---

**Total deviations:** 4 auto-fixed (1 Rule 1 bug, 1 Rule 2 missing critical control, 2 Rule 3 blocking issues)
**Impact on plan:** All changes were required to make the planned production tracer truthful, accessible, and transactionally replayable; no new product capability or architectural boundary was introduced.

## Issues Encountered

- Context7 MCP and CLI documentation lookup were unavailable. Implementation was grounded in the installed exact-version Ecto/Postgrex/Phoenix source and then exercised against PostgreSQL 18.6 with the pinned runtime wrapper.
- The first idempotency RED run proved the receipt JSONB column held a JSON string rather than the original result object. This was the intended failure signal, not a test-harness artifact.

## TDD Gate Compliance

- Task 1 RED commit `ce3e881` introduced the real authenticated browser tracer before implementation; GREEN commit `a6b2fd9` made the complete production path pass.
- Task 2 RED commit `33c1da8` recorded 1/3 passing and two failures caused by non-identical first/replay envelope shapes; GREEN commit `3b5a537` made the target pass 3/3.
- No refactor-only commit was needed after either GREEN gate.

## Known Stubs

None - no placeholder, TODO, skipped test, mock data source, or unrun verification remains in the files changed by this plan.

## Threat Surface

All new network, authentication, receipt, task/activity schema, and account-scoped lookup surfaces are covered by the plan threat model. No additional unmodeled trust boundary was introduced.

## Verification Evidence

- `mix test` - 9/9 server tests pass on PostgreSQL 18.6.
- Targeted idempotency plus architecture gate - 7/7 pass.
- Full Playwright run - 2/2 pass, including the authenticated `@skeleton` tracer against a disposable real stack.
- `pnpm --filter @keepling/web build` - TypeScript and production Vite build pass.
- `pnpm contracts:check` and `./tooling/test-phase-1.sh --run` - generated transport and all currently available Phase 1 lanes pass.

## User Setup Required

None - all verification uses executor-owned disposable PostgreSQL and test-only seeded state; production account bootstrap remains closed for Plan 01-06.

## Next Phase Readiness

- Plan 01-06 can replace the test-only sign-in fixture with operator-owned setup, password authentication, recovery, and durable session policy while reusing the account/session boundary.
- Later semantic command plans can reuse the receipt gate and closed result envelope without duplicating transaction or adapter logic.
- No high-severity spoofing, tampering, elevation, or disclosure mitigation assigned to this plan remains open.

## Self-Check: PASSED

- All required implementation, migration, contract, browser, E2E, and summary files exist on disk.
- Task commits `8eeb422`, `ce3e881`, `a6b2fd9`, `33c1da8`, and `3b5a537` exist in Git history.
- Required actuals, coverage, requirement IDs, TDD evidence, deviations, and `status: complete` metadata are present.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-30*
