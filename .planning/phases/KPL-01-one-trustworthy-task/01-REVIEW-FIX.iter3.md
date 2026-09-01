---
phase: KPL-01-one-trustworthy-task
fixed_at: 2026-08-31T18:58:06Z
review_path: .planning/phases/KPL-01-one-trustworthy-task/01-REVIEW.md
iteration: 2
findings_in_scope: 6
fixed: 6
skipped: 0
status: all_fixed
commits:
  - 70bff23
  - b9c609e
  - 0f22475
  - b2f1673
  - f14a166
  - 9325634
  - c7709da
tests:
  - focused web regression suite: 53 passed
  - focused lifecycle real-stack suite: 5 passed
  - repository integrity: passed
  - server compile and ExUnit suite: 103 passed
  - production route isolation: passed
  - contract drift check: passed
  - TypeScript typecheck: passed
  - complete Vitest suite: 84 passed
  - complete Playwright real-stack suite: 11 passed
unresolved: []
---

# Phase KPL-01: Code Review Fix Report

**Fixed at:** 2026-08-31T18:58:06Z  
**Source review:** `.planning/phases/KPL-01-one-trustworthy-task/01-REVIEW.md`  
**Iteration:** 2

**Summary:**

- Findings in scope: 6
- Fixed: 6
- Skipped: 0

## Fixed Issues

### CR-01: A genuinely expired session cannot use the reauthentication continuation

**Files modified:** `apps/server/lib/keepling_web/controllers/test_fault_controller.ex`, `apps/server/test/keepling_web/test_fault_test.exs`, `apps/web/src/App.tsx`, `apps/web/src/app/AuthProvider.tsx`, `apps/web/src/app/routes.tsx`, `apps/web/src/commands/submission.ts`, `apps/web/src/features/auth/LoginForm.tsx`, `apps/web/src/features/auth/Reauthenticate.tsx`, continuation-producing mutation components, and focused unit/E2E tests  
**Commits:** `70bff23`, `c7709da`  
**Status:** fixed: requires human verification  
**Applied fix:** Invalid-session `authentication_required` now uses the normal login flow, while valid-session `recent_authentication_required` continues to use session rotation. The exact interruption and resume closure remain mounted through login, AuthProvider actions are stable across interruption state changes, and the real-stack revoked-session test logs in with a new session and CSRF token before reconciling and replaying the original undo identity.

### CR-02: Routed task lifecycle actions never receive the authentication continuation

**Files modified:** `apps/web/src/app/routes.tsx`, `apps/web/src/features/lists/TaskList.tsx`, `apps/web/e2e/lifecycle-recovery.spec.ts`  
**Commit:** `b9c609e`  
**Status:** fixed: requires human verification  
**Applied fix:** Every routed task list now receives and forwards the authentication callback to lifecycle actions. Before-acceptance and after-commit browser tests click through the real login flow, assert immutable request identity, and prove the final Complete-to-Reopen reconciliation; the after-commit path resolves from the stored receipt without resending.

### CR-03: Task-assignment recovery discards an accepted mutation on an after-commit authentication response

**Files modified:** `apps/web/src/api/keepling.ts`, `apps/web/src/app/routes.tsx`, `apps/web/src/features/organizations/OrganizationFields.tsx`, `apps/web/src/features/organizations/organization-fields.test.tsx`  
**Commit:** `0f22475`  
**Status:** fixed: requires human verification  
**Applied fix:** Task assignment now prepares immutable request bytes and runs through the shared exact-submission state machine. Its routed continuation retains the mutation and task identity, checks the receipt after authentication or response loss, and resends byte-for-byte only after a verified receipt miss. Focused tests cover before acceptance, after commit, response loss, and 5xx uncertainty.

### CR-04: Today ordering loses the exact command and has no authentication recovery action

**Files modified:** `apps/server/lib/keepling/adapters/postgres/task_views.ex`, `apps/server/lib/keepling/application/task_views.ex`, `apps/server/lib/keepling_web/controllers/task_view_controller.ex`, `apps/server/lib/keepling_web/router.ex`, `apps/server/priv/repo/migrations/20260830000950_expand_today_move_receipts.exs`, `apps/server/test/keepling/adapters/postgres/task_views_test.exs`, `apps/web/src/api/keepling.ts`, `apps/web/src/features/lists/TaskList.tsx`, `apps/web/src/features/lists/task-lists.test.tsx`, `packages/contracts/openapi/keepling.yaml`, `packages/contracts/generated/keepling.ts`  
**Commit:** `b2f1673`  
**Status:** fixed: requires human verification  
**Applied fix:** Today moves now retain an immutable exact submission and reconcile through an authenticated, account-scoped Today receipt endpoint. Stored receipts include mutation, task, and order revision identity. Authentication, response loss, and 5xx paths preserve uncertainty and check the receipt before any exact replay.

### WR-01: Reauthentication audit commits before session rotation and can record an action that never occurred

**Files modified:** `apps/server/lib/keepling/accounts.ex`, `apps/server/lib/keepling_web/controllers/auth_controller.ex`, `apps/server/test/keepling/security_audit_test.exs`  
**Commit:** `f14a166`  
**Status:** fixed: requires human verification  
**Applied fix:** Password verification, locked-session rotation, and required `reauthenticated` audit insertion now execute through one application transaction. Injected audit failure and unavailable-session tests prove neither rotation nor success audit can commit alone.

### WR-02: Authentication recovery copy asserts “not submitted” and “nothing changed” for an explicitly uncertain response

**Files modified:** `apps/web/src/commands/submission.ts`, `apps/web/src/features/recovery/MutationRecoveryPanel.tsx`, `apps/web/src/features/recovery/RecoveryStrip.tsx`, `apps/web/src/features/organizations/OrganizationFields.tsx`, `apps/web/src/features/tasks/LifecycleActions.tsx`, `apps/web/src/features/capture/QuickCapture.tsx`, related routed surfaces, and focused unit/E2E tests  
**Commit:** `9325634`  
**Status:** fixed: requires human verification  
**Applied fix:** Every exact submission that receives authentication after dispatch is represented as `submitted-unknown`. Recovery copy is neutral, continuations check the original receipt first, accepted after-commit results do not resend, and exact replay occurs only after a terminal receipt miss. Verified no-change language remains reserved for terminal rejections.

## Verification

Verification ran in the **main checkout after the isolated review-fix worktrees were fast-forwarded and transactionally removed**.

- `pnpm --filter @keepling/web exec vitest run src/commands/submission.test.ts src/features/recovery/recovery-strip.test.tsx src/features/organizations/organization-fields.test.tsx src/features/lists/task-lists.test.tsx src/features/tasks/lifecycle.test.tsx src/features/auth/auth.test.tsx` — 6 files, 53 tests passed.
- `KEEPLING_E2E_PORT=4273 pnpm --filter @keepling/web exec playwright test e2e/lifecycle-recovery.spec.ts` — 5/5 real-stack lifecycle recovery tests passed.
- `KEEPLING_E2E_PORT=4273 ./tooling/test-phase-1.sh --run` — repository integrity, migrations, warning-free server compile, 103/103 ExUnit tests, production route isolation, contract drift, TypeScript typecheck, 84/84 Vitest tests, and 11/11 Playwright real-stack tests passed.
- Alternate port 4273 was used because an unrelated user-owned Python process already occupied the default port 4173; that process was not touched.

No in-scope finding remains unresolved.

---

_Fixed: 2026-08-31T18:58:06Z_  
_Fixer: the agent (gsd-code-fixer)_  
_Iteration: 2_
