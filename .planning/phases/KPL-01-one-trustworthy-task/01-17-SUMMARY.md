---
phase: KPL-01-one-trustworthy-task
plan: 17
subsystem: mutation-recovery
tags: [elixir, phoenix, postgresql, react, playwright, idempotency, authentication, uncertain-delivery]

requires:
  - phase: KPL-01-16
    provides: Persisted semantic conflicts, exact-revision commands, stable receipts, and acknowledgement-gated browser reconciliation
provides:
  - One exact browser submission state machine for edits, dates, clarification, and lifecycle commands
  - Persistent unknown-delivery and authentication-interruption recovery with immutable request bytes and mutation identities
  - Credentialed test-only pre/post-acceptance fault injection with real PostgreSQL/Phoenix/Chromium evidence and no production surface
affects: [KPL-01-18, sync, mcp, desktop-offline, iphone-offline]

actuals:
  tokens: 13720
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns: [immutable prepared command, exact acknowledgement gate, operation-aware authentication resume, compile-time test fault isolation]

key-files:
  created:
    - apps/web/src/commands/submission.ts
    - apps/web/src/commands/submission.test.ts
    - apps/web/src/features/recovery/MutationRecoveryPanel.tsx
    - apps/server/lib/keepling_web/controllers/test_fault_controller.ex
    - apps/server/test/keepling_web/test_fault_test.exs
    - apps/web/e2e/lifecycle-recovery.spec.ts
  modified:
    - apps/web/src/api/keepling.ts
    - apps/web/src/features/tasks/TaskEditor.tsx
    - apps/web/src/features/tasks/LifecycleActions.tsx
    - apps/server/lib/keepling_web/router.ex

key-decisions:
  - "Prepare and retain the immutable serialized command body before submission; every lookup, direct retry, and authentication resume remains attached to that exact body and mutation identity."
  - "Authentication recovery remembers whether authentication interrupted a lookup or a send, so sign-in resumes the interrupted operation instead of minting or ambiguously replaying intent."
  - "Fault controls compile only in the test environment, require a random per-run credential, expose no task content or identifiers, and inject faults directly around the real acceptance/response boundary."

patterns-established:
  - "Exact command authority: PreparedTaskCommand owns path, serialized body, mutation identity, and task identity; UI state cannot reconstruct or mutate a retry payload."
  - "Honest recovery: missing or infrastructure responses become persistent unknown state; exact acknowledgement, terminal rejection/conflict, or explicit fence are the only terminal transitions."
  - "Test fault isolation: both module definition and router pipeline are Mix.env test-gated, with credential validation and an executable production absence check."

requirements-completed: [SRV-01, SRV-03, WEB-01, WEB-02, QUAL-01]

coverage:
  - id: D1
    description: "All browser task mutations preserve immutable request bytes, draft, and mutation identity through duplicate activation, unknown delivery, lookup, same-ID retry, and exact acknowledgement."
    requirement: WEB-02
    verification:
      - kind: unit
        ref: "apps/web/src/commands/submission.test.ts"
        status: pass
      - kind: automated_ui
        ref: "apps/web/src/features/tasks/TaskEditor.test.tsx and apps/web/src/features/tasks/LifecycleActions.test.tsx via pnpm --filter @keepling/web test --run"
        status: pass
    human_judgment: false
  - id: D2
    description: "Unknown delivery and authentication interruption render the locked recovery copy and resume the exact interrupted lookup or send without reporting false success."
    requirement: WEB-01
    verification:
      - kind: unit
        ref: "apps/web/src/commands/submission.test.ts#unknown and authentication recovery cases"
        status: pass
      - kind: e2e
        ref: "apps/web/e2e/lifecycle-recovery.spec.ts"
        status: pass
    human_judgment: false
  - id: D3
    description: "Before acceptance stores no result, after commit reconciles one stored result, and both authentication timing boundaries preserve the original mutation identity against real PostgreSQL."
    requirement: SRV-03
    verification:
      - kind: integration
        ref: "apps/server/test/keepling_web/test_fault_test.exs"
        status: pass
      - kind: e2e
        ref: "pnpm --filter @keepling/web test:e2e -- 7/7 passed"
        status: pass
    human_judgment: false
  - id: D4
    description: "Credentialed fault controls remain privacy-safe and test-only; production compilation contains neither the fault module nor any fault route."
    requirement: QUAL-01
    verification:
      - kind: integration
        ref: "apps/server/test/keepling_web/test_fault_test.exs#credential and router isolation"
        status: pass
      - kind: other
        ref: "MIX_ENV=prod compile plus Code.ensure_loaded?/router route absence probe"
        status: pass
      - kind: other
        ref: "pnpm test:phase-1"
        status: pass
    human_judgment: false

duration: 42min
completed: 2026-08-31
status: complete
---

# Phase KPL-01 Plan 17: Exact Mutation Recovery Summary

**Immutable browser commands with honest unknown/authentication recovery and credentialed real-stack pre/post-acceptance fault proof**

## Performance

- **Duration:** 42 min
- **Started:** 2026-08-31T13:16:52Z
- **Completed:** 2026-08-31T13:58:01Z
- **Tasks:** 2
- **Files modified:** 10

## Accomplishments

- Centralized every browser edit, date, clarification, and lifecycle mutation behind a single state machine whose immutable prepared command retains the exact serialized request, mutation identity, task identity, and draft until a matching terminal acknowledgement.
- Added persistent exact-copy recovery panels for unknown delivery and authentication interruption; checking performs lookup then same-ID send only after an exact not-found result, direct retry reuses the original bytes, duplicate activation is fenced, and authentication resumes the interrupted operation.
- Added credentialed, privacy-safe test-only faults before acceptance, after commit, and at both authentication timings, then proved the real effects and receipts through disposable PostgreSQL, Phoenix, Vite, and Chromium while proving the fault surface is absent from production compilation.
- Passed the complete server, contracts, browser unit, typecheck, lint, build, Phase 1 aggregate, production isolation, and seven-case real-browser lanes.

## Task Commits

Each planned TDD task has an explicit RED commit followed by its GREEN commit:

1. **Task 1 RED: Add failing exact submission proof** - `71ddc15` (test)
2. **Task 1 GREEN: Centralize exact mutation recovery** - `a56ad78` (feat)
3. **Task 2 RED: Add failing fault isolation proof** - `0a65916` (test)
4. **Task 2 GREEN: Prove real mutation response loss** - `cd13e0c` (test)

## Files Created/Modified

- `apps/web/src/commands/submission.ts` and `apps/web/src/commands/submission.test.ts` - Generic exact submission state, duplicate fence, lookup/direct retry, operation-aware authentication resume, exact acknowledgement validation, and ten focused behavior cases.
- `apps/web/src/api/keepling.ts` - Immutable prepared edit, clarify, date, and lifecycle commands plus raw-body exact submission.
- `apps/web/src/features/recovery/MutationRecoveryPanel.tsx` - Persistent locked unknown and authentication recovery copy/actions.
- `apps/web/src/features/tasks/TaskEditor.tsx` and `apps/web/src/features/tasks/LifecycleActions.tsx` - Shared exact orchestration, retained drafts, explicit checking/retry/sign-in continuation, and acknowledgement-only success reconciliation.
- `apps/server/lib/keepling_web/controllers/test_fault_controller.ex` and `apps/server/lib/keepling_web/router.ex` - Test-compiled credentialed before-acceptance, after-commit, and authentication timing faults on authenticated mutation pipelines only.
- `apps/server/test/keepling_web/test_fault_test.exs` - Six server proofs for receipt/effect timing, opaque bad credentials, authentication timing, privacy, and router gating.
- `apps/web/e2e/lifecycle-recovery.spec.ts` - Four real-stack lifecycle cases proving exact before/after-commit and before/after-commit-auth behavior.

## Decisions Made

- Serialized command bytes are prepared once and retained as the retry authority. The UI may display or reconcile state, but it cannot regenerate a request during recovery.
- “Check again” first asks the server for the original mutation result and sends the same body only after exact not-found; the separate “Try again” path is an explicit same-ID resend. Neither path creates a new intent.
- Authentication-required state retains whether send or lookup was interrupted. “Sign in and continue” resumes that operation and remains nonterminal until exact acknowledgement, rejection, or conflict.
- Pre-acceptance response loss uses a deterministic infrastructure response rather than a hanging connection; the browser treats all infrastructure 5xx responses as unknown because acceptance cannot be inferred from transport status.
- The fault module and router pipeline are compile-time test-only in addition to a random credential check, so a production boot cannot expose even a dormant fault endpoint.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added explicit direct same-ID retry semantics**
- **Found during:** Task 1 full browser unit verification
- **Issue:** The initial controller exposed lookup-based checking only, while existing lifecycle recovery correctly required an explicit retry to resend immediately with the retained identity.
- **Fix:** Added a direct `retry()` transition that resends the immutable prepared command without minting an identity or changing bytes; “Check again” retains lookup-first semantics.
- **Files modified:** `apps/web/src/commands/submission.ts`, `apps/web/src/features/tasks/LifecycleActions.tsx`
- **Verification:** All 62 browser unit tests passed, including the existing lifecycle recovery case.
- **Committed in:** `a56ad78`

**2. [Rule 1 - Bug] Classified infrastructure 5xx as unknown delivery**
- **Found during:** Task 2 real-browser before-acceptance proof
- **Issue:** The browser initially treated a deterministic response-loss 503 as terminal rejection even though transport failure cannot prove whether acceptance occurred.
- **Fix:** Classified 5xx problem responses as persistent unknown delivery while retaining explicit 4xx rejection/conflict semantics.
- **Files modified:** `apps/web/src/commands/submission.ts`
- **Verification:** Before-acceptance and after-commit Chromium cases both preserved the exact command and reconciled correctly; all submission unit tests passed.
- **Committed in:** `cd13e0c`

**3. [Rule 1 - Bug] Halted authentication-before-acceptance injection**
- **Found during:** Task 2 server fault suite
- **Issue:** The first authentication fault sent a 401 without halting the Plug connection, allowing the mutation controller to continue and store a receipt.
- **Fix:** Halted immediately after the authentication response so the pre-acceptance fault cannot cross the command boundary.
- **Files modified:** `apps/server/lib/keepling_web/controllers/test_fault_controller.ex`
- **Verification:** Six server fault tests and both authentication Chromium cases passed with the expected receipt presence/absence.
- **Committed in:** `cd13e0c`

---

**Total deviations:** 3 auto-fixed Rule 1 bugs
**Impact on plan:** All corrections were required for honest retry, infrastructure ambiguity, or acceptance-boundary correctness; no unrelated feature, schema, endpoint, or dependency was added.

## Issues Encountered

- Keepling's server guard requires explicit test-only database and secret variables; focused and full server runs were supplied the existing local test database plus a per-run 32-byte fault credential.
- A raw raised connection error before acceptance left the browser fetch pending in this real-stack harness. The test fault was changed to a deterministic 503 infrastructure response, preserving the semantically important “no acceptance and no trustworthy delivery conclusion” boundary without a timeout-dependent test.
- Lifecycle actions are intentionally unavailable in Inbox. The E2E helper captures a task, moves it to Today through the real UI, then injects faults into the completion command.
- The existing E2E harness's public startup/import seam was minimally inspected to compose the new real-stack suite without duplicating or bypassing its disposable PostgreSQL ownership.
- The production router probe initially omitted mandatory runtime configuration; supplying inert `DATABASE_URL`, `SECRET_KEY_BASE`, and `PHX_HOST` values allowed a no-start compiled-code inspection without connecting to a database.

## TDD Gate Compliance

- Task 1 RED commit `71ddc15` failed because the exact submission module did not exist. GREEN commit `a56ad78` made ten focused cases and the complete 62-test browser suite pass.
- Task 2 RED commit `0a65916` failed because the test fault controller and router plug did not exist. GREEN commit `cd13e0c` made six focused server cases and four new real-stack Chromium cases pass.
- Both RED commits precede their matching GREEN commits; no implementation was committed before its failing behavioral proof.

## Known Stubs

None - no TODO, FIXME, skipped test, placeholder production behavior, mock production data source, hardcoded empty rendered data, or unrun verification remains in the 10 realized files. Date input placeholders and local empty accumulator/ref initialization are intentional UI/program state, not shipped stubs.

## Threat Surface

- T-KPL01-36 is mitigated by immutable serialized commands, fixed mutation identities, exact acknowledgement validation, terminal lookup/replay, duplicate fencing, and persistent unknown/authentication recovery with real acceptance-timing proof.
- T-KPL01-37 is mitigated by compile-time test-only module and router definitions, random per-run credential validation, opaque unauthorized responses, privacy-safe constant fault messages, and an executable production absence probe.
- The planned authenticated mutation fault plug is the only new trust-boundary surface. No schema, telemetry, file-access, production endpoint, or authentication method outside the plan threat model was introduced, and no high-severity mitigation remains open.

## Verification Evidence

- `mix test`: 86/86 server tests passed.
- `pnpm contracts:check`: OpenAPI and generated TypeScript agree.
- `pnpm --filter @keepling/web test --run`: 9 files and 62/62 tests passed.
- Browser typecheck, ESLint, and production Vite build passed; 66 modules transformed.
- `pnpm test:phase-1`: repository integrity, runtime preflight, contracts, browser tests, and seven listed real-stack cases passed.
- `pnpm --filter @keepling/web test:e2e`: 7/7 Chromium cases passed against owned disposable PostgreSQL and Phoenix processes.
- `MIX_ENV=prod mix compile --warnings-as-errors` plus compiled router/module inspection printed `production fault surface absent`.

## User Setup Required

None - no external service configuration is required. The fault credential is generated/provided only by the owned test harness and is not a production setting.

## Next Phase Readiness

- Plan 01-18 can build final phase-level proof on one browser mutation contract that now survives missing responses and authentication boundaries without false success or duplicate intent.
- Exact prepared-command and acknowledgement-gate patterns are ready for reuse by future offline clients without coupling domain rules to browser transport.
- No blockers or open high-severity mitigations remain.

## Self-Check: PASSED

- All six created implementation/proof files and this summary exist at their recorded paths.
- Task commits `71ddc15`, `a56ad78`, `0a65916`, and `cd13e0c` resolve to commits in repository history.
- Fresh verification passed at every planned boundary, and both the realized implementation diff and summary pass `git diff --check`.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-31*
