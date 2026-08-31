---
phase: KPL-01-one-trustworthy-task
fixed_at: 2026-08-31T20:01:37Z
review_path: .planning/phases/KPL-01-one-trustworthy-task/01-REVIEW.md
iteration: 3
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
commits:
  - 19eeb96
  - 6a49141
  - 8263482
  - daa2d84
  - d01d386
  - f03461e
  - 25acaef
  - 58f9513
tests:
  - focused web regression suite: 4 files and 39 tests passed
  - focused TypeScript typecheck: passed
  - standalone Playwright real-stack suite: 13 passed
  - repository integrity: passed
  - runtime preflight and migrations: passed
  - server ExUnit suite: 105 passed
  - production route and privacy isolation: passed
  - contract drift check: passed
  - complete TypeScript typecheck: passed
  - complete Vitest suite: 94 passed
  - complete Playwright real-stack suite: 13 passed
  - schema drift hook: no drift
  - codebase drift hook: skipped because no STRUCTURE.md exists
  - UI safety gate: passed
unresolved: []
---

# Phase KPL-01: Code Review Fix Report

**Fixed at:** 2026-08-31T20:01:37Z  
**Source review:** `.planning/phases/KPL-01-one-trustworthy-task/01-REVIEW.md`  
**Iteration:** 3 (final permitted fix pass)

**Summary:**

- Findings in scope: 5
- Fixed: 5
- Skipped: 0
- Unresolved: 0

## Fixed Issues

### CR-01: Stale date and planning commands crash while trying to persist an unsupported conflict

**Files modified:** `apps/server/lib/keepling/adapters/postgres/command_store.ex`, `apps/server/test/keepling/domain/task_dates_test.exs`  
**Commit:** `19eeb96`  
**Status:** fixed: requires human verification  
**Applied fix:** Persisted conflict serialization is now gated by both conflict kind and supported command type. Stale `edit-task-dates`, `plan-for-today`, and `unplan-task` overlaps return stable semantic 409 receipts instead of entering the unsupported serializer. Adapter and HTTP coverage proves exact replay, mutation lookup, and the absence of an unsupported persisted-conflict row for all three commands.

### CR-02: Genuine session expiry still leaves list, Trash, and session administration in recovery dead ends

**Files modified:** `apps/web/src/App.tsx`, `apps/web/src/api/keepling.ts`, `apps/web/src/app/AppShell.tsx`, `apps/web/src/app/routes.tsx`, `apps/web/src/features/auth/Reauthenticate.tsx`, `apps/web/src/features/auth/auth.test.tsx`, `apps/web/src/features/lists/TaskList.tsx`, `apps/web/src/features/lists/TrashList.tsx`, `apps/web/src/features/lists/task-lists.test.tsx`, `apps/web/src/features/lists/trash-list.test.tsx`, `apps/web/src/features/sessions/SessionList.tsx`, `apps/web/e2e/lifecycle-recovery.spec.ts`  
**Commits:** `6a49141`, `f03461e`, `25acaef`, `58f9513`  
**Status:** fixed: requires human verification  
**Applied fix:** Authenticated read surfaces now enter the shared login continuation when the session is genuinely invalid. Trash is routed through the interruption overlay and restores through one immutable exact submission with receipt-first reconciliation. Session label/revoke actions consistently request sign-in or recent reauthentication and resume the original admin action. Real-stack tests revoke or age the live session, complete visible login/reauthentication, and prove the original list read, exact restore, and targeted session revocation finish successfully.

### CR-03: Quick capture discards its accepted mutation identity on a dispatched 5xx and can create duplicate tasks

**Files modified:** `apps/web/src/api/keepling.ts`, `apps/web/src/features/auth/auth.test.tsx`, `apps/web/src/features/capture/QuickCapture.tsx`  
**Commit:** `8263482`  
**Status:** fixed: requires human verification  
**Applied fix:** Capture and optional planning requests are prepared once with immutable task, mutation, and request identities. Every dispatched 5xx is classified as submitted-unknown, retains the original submission, and performs receipt lookup before any byte-for-byte resend. A parsed 503-after-commit regression proves the stored receipt settles the original task with one POST and no duplicate identity.

### WR-01: Conflict resolution labels resubmission as a receipt check and bypasses the shared exact-recovery state machine

**Files modified:** `apps/web/src/api/keepling.ts`, `apps/web/src/features/tasks/ConflictResolver.tsx`, `apps/web/src/features/tasks/conflict-resolver.test.tsx`  
**Commit:** `daa2d84`  
**Status:** fixed: requires human verification  
**Applied fix:** Conflict resolution now uses one immutable exact submission, treats post-dispatch authentication as submitted-unknown, and checks the mutation receipt before any resend. Settlement verifies mutation ID, task ID, and `resolvedConflictId`. Focused tests cover before acceptance, after commit, authentication after dispatch, and changed acknowledgement identity.

### WR-02: Moving the last visible Today row can be accepted against a hidden row while the UI shows no movement and retains a stale cursor

**Files modified:** `apps/web/src/features/lists/TaskList.tsx`, `apps/web/src/features/lists/task-lists.test.tsx`  
**Commit:** `d01d386`  
**Status:** fixed: requires human verification  
**Applied fix:** An acknowledged Today move with unloaded rows now refreshes the authoritative first page and replaces both the visible rows and pagination cursor. If that refresh fails, the stale cursor is discarded instead of being reused. The multi-page regression crosses the visible boundary and then loads the next page with the refreshed cursor.

## Verification

Verification ran in the **main checkout after the isolated review-fix worktree was fast-forwarded and transactionally removed**.

- Focused TypeScript compilation passed, and the four focused regression files passed all 39 tests.
- A standalone real-stack browser run passed all 13 Playwright tests on isolated Vite `42732`, Phoenix `42733`, and PostgreSQL `56432` ports.
- `./tooling/test-phase-1.sh --run` then passed from a fresh isolated stack: repository integrity, Elixir `1.20.2` / OTP `29.0.5` / PostgreSQL `18.6` runtime preflight, all migrations, 105/105 ExUnit tests, production-route/privacy isolation, contract drift, TypeScript typecheck, 94/94 Vitest tests, and 13/13 Playwright tests.
- The schema-drift hook reported no drift; the codebase-drift hook was non-blockingly skipped because the project has no `STRUCTURE.md`; the UI safety gate reported no block.
- `git worktree list` shows only the main checkout, no `gsd-reviewfix/*` branch remains, and `.review-fix-recovery-pending.json` is absent.

## Unresolved Issues

None. This is the third and final automated fix pass, so no post-fix re-review is scheduled under the workflow cap.

---

_Fixed: 2026-08-31T20:01:37Z_  
_Fixer: the agent (gsd-code-fixer)_  
_Iteration: 3_
