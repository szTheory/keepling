---
phase: KPL-01-one-trustworthy-task
fixed_at: 2026-08-31T23:56:58Z
review_path: .planning/phases/KPL-01-one-trustworthy-task/01-REVIEW.md
iteration: 3
findings_in_scope: 2
fixed: 2
skipped: 0
status: all_fixed
commits:
  - be6c461
  - 31f5b05
  - 2e3e2b1
tests:
  - focused web regression suite: 2 files and 30 tests passed
  - complete web TypeScript typecheck: passed
  - targeted ESLint: passed
  - repository diff check: passed
unresolved: []
---

# Phase KPL-01: Code Review Fix Report

**Fixed at:** 2026-08-31T23:56:58Z  
**Source review:** `.planning/phases/KPL-01-one-trustworthy-task/01-REVIEW.md`  
**Iteration:** 3

**Summary:**

- Findings in scope: 2
- Fixed: 2
- Skipped: 0

## Fixed Issues

### CR-01: Changing task routes leaves the editor able to mutate the previously open task

**Files modified:** `apps/web/src/app/routes.tsx`, `apps/web/src/features/tasks/task-editor.test.tsx`  
**Commit:** `be6c461`  
**Status:** fixed: requires human verification  
**Applied fix:** Keyed the routed task-detail subtree by `taskId`, so changing from task A to task B synchronously unmounts A's editor, activity, draft, conflict, submission, and exact-recovery state before B's reads settle. The deferred route regression attempts both keyboard and button submission against the detached A form, proves no A mutation is sent, then resolves B and proves the next edit uses B's identity and revision.

### CR-02: A response from a list route the user left can overwrite the newly selected list

**Files modified:** `apps/web/src/app/routes.tsx`, `apps/web/src/features/lists/task-lists.test.tsx`  
**Commits:** `31f5b05`, `2e3e2b1`  
**Status:** fixed: requires human verification  
**Applied fix:** Keyed every routed `TaskList` by its view identity, which resets rows, cursor, account-day metadata, Today ordering state, pagination errors, move recovery, and lifecycle locks whenever the route changes. Deferred regressions cover Inbox and Today initial reads settling in both orders and an old Inbox pagination response settling after Today; only Today rows remain, and subsequent controls retain Today's cursor and order revision.

## Skipped Issues

None.

## Verification

Verification ran in the **main checkout after the isolated review-fix worktree was fast-forwarded and transactionally removed**.

- `pnpm --filter @keepling/web exec vitest run src/features/tasks/task-editor.test.tsx src/features/lists/task-lists.test.tsx` passed: 2 files, 30 tests.
- `pnpm --filter @keepling/web typecheck` passed.
- `pnpm --filter @keepling/web exec eslint src/app/routes.tsx src/features/tasks/task-editor.test.tsx src/features/lists/task-lists.test.tsx` passed.
- `git diff --check` passed.
- `git worktree list` shows only the main checkout, no `gsd-reviewfix/*` branch remains, and `.review-fix-recovery-pending.json` is absent.

---

_Fixed: 2026-08-31T23:56:58Z_  
_Fixer: the agent (gsd-code-fixer)_  
_Iteration: 3_
