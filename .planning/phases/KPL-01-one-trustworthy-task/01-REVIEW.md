---
phase: KPL-01-one-trustworthy-task
reviewed: 2026-08-31T23:50:13Z
depth: standard
files_reviewed: 21
files_reviewed_list:
  - apps/server/lib/keepling_web/router.ex
  - apps/server/test/keepling_web/test_fault_test.exs
  - apps/web/e2e/authenticated-read-recovery.spec.ts
  - apps/web/e2e/conflict-resolution-recovery.spec.ts
  - apps/web/e2e/session-reconciliation.spec.ts
  - apps/web/e2e/today-order-recovery.spec.ts
  - apps/web/src/app/AuthProvider.tsx
  - apps/web/src/app/routes.tsx
  - apps/web/src/features/activity/ActivityList.tsx
  - apps/web/src/features/activity/activity-list.test.tsx
  - apps/web/src/features/auth/auth.test.tsx
  - apps/web/src/features/lists/TaskList.tsx
  - apps/web/src/features/lists/task-lists.test.tsx
  - apps/web/src/features/organizations/OrganizationFields.tsx
  - apps/web/src/features/organizations/organization-fields.test.tsx
  - apps/web/src/features/sessions/SessionList.tsx
  - apps/web/src/features/sessions/session-list.test.tsx
  - apps/web/src/features/tasks/ConflictResolver.tsx
  - apps/web/src/features/tasks/TaskEditor.tsx
  - apps/web/src/features/tasks/conflict-resolver.test.tsx
  - apps/web/src/features/tasks/task-editor.test.tsx
findings:
  critical: 2
  warning: 0
  info: 0
  total: 2
status: issues_found
---

# Phase KPL-01: Code Review Report

**Reviewed:** 2026-08-31T23:50:13Z
**Depth:** standard
**Files Reviewed:** 21
**Status:** issues_found

## Summary

The iteration-two fixes close all five findings from the preceding report. Session writes now reconcile rather than replay after authentication, continuation drains are bounded per credential rotation, conflict-mode edit entry points are locked, list pagination and lifecycle operations serialize, and conflict locking is rendered from React state. No regression was found in the earlier task-detail, exact-replay, undo/authentication, organization, Today-order, session, activity, accessibility, or test-fault repairs.

The phase is not clean. Two route-identity races remain in reviewed components. React preserves each component while only its route prop changes, but neither component fences its retained state and outstanding reads to that new identity. One race can submit an edit for the task that was previously open; the other can permanently display a response from the list route the user already left. Existing tests mount one route identity at a time and therefore cannot detect either failure.

Pass-2 finding disposition:

| Prior finding | Result |
| --- | --- |
| CR-01 | Closed; rename, revoke, and logout authenticate into authoritative inventory reconciliation and never replay the write. |
| CR-02 | Closed; each drain snapshots eligible continuation generations, and repeated authentication remains retryable without an automatic loop. |
| CR-03 | Closed; submit, form, keyboard, navigation, and rendered dirty-save paths all enforce the conflict/submission lock. |
| CR-04 | Closed; pagination, lifecycle, and Today movement lock one another, and accepted projection writes use current state. |
| WR-01 | Closed; `ConflictResolver` derives its rendered lock from React state and passes targeted lint. |

Original pass-1 regression check: the previously repaired CR-01 through CR-07 and WR-01 through WR-02 behaviors remain closed in this scope. The focused tests cover their happy recovery paths, exact identities, repeated authentication, concurrent settlement, accessibility controls, and authoritative assertions; the two findings below concern route identity transitions absent from those suites.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: Changing task routes leaves the editor able to mutate the previously open task

**Classification:** BLOCKER

**File:** `/Users/jon/projects/keepling/apps/web/src/features/tasks/TaskEditor.tsx:104-160`

**Also affected:** `/Users/jon/projects/keepling/apps/web/src/app/routes.tsx:296-308`, `/Users/jon/projects/keepling/apps/web/src/features/tasks/task-editor.test.tsx:1-757`

**Issue:** `AppRoutes` renders the same unkeyed `TaskEditor` component for every `/tasks/:id` route, so React preserves the instance when the user opens task B from task A. The load effect is correctly fenced against a late response, but it never resets `loadState`, `draft`, `submission`, or exact recovery state when `taskId` changes. Until B's read finishes, `acceptedTask` is still A and the old form remains enabled. A quick edit/save on the B URL therefore builds a command from A's ID and revision and can successfully change the wrong task. The reviewed tests mount a single task identity and never rerender or navigate an existing editor from A to B, so they pass without exercising this data-integrity path.

**Fix:** Bind editor lifetime to route identity (for example, render `<TaskEditor key={taskId} ... />`) or synchronously fence all command handlers to the loaded task ID and reset the full editor/recovery state to `loading` whenever `taskId` changes. Add a deferred A-to-B navigation test: keep B's GET pending, attempt keyboard and button submission, assert no mutation is sent for A, then resolve B and assert any subsequent command contains B's ID and revision.

### CR-02: A response from a list route the user left can overwrite the newly selected list

**Classification:** BLOCKER

**File:** `/Users/jon/projects/keepling/apps/web/src/features/lists/TaskList.tsx:163-231`

**Also affected:** `/Users/jon/projects/keepling/apps/web/src/app/routes.tsx:251-254`, `/Users/jon/projects/keepling/apps/web/src/features/lists/task-lists.test.tsx:84-565`

**Issue:** Inbox, Today, Upcoming, and Completed all render the same unkeyed `TaskList`; switching between them changes only `view`, so the instance and its asynchronous work survive. Neither `load` nor `loadMore` records a request generation or checks that its captured `view` is still current before writing `state`. If the user switches from Inbox to Today and the Today request resolves first, a slower Inbox request can settle afterward and replace the Today page with Inbox rows and metadata. A pending pagination response from the old route can likewise append old-route rows to the new route. The current tests render fixed `view` props and exercise operation ordering within one list, but never rerender across list identities with reversed response order.

**Fix:** Key `TaskList` by `view`, or add a monotonically increasing request generation/abort controller and accept a response only when both its generation and route identity still match. Reset view-specific state (`state`, pagination errors, move submission, and lifecycle lock) on identity change. Add deferred Inbox-to-Today and paginated-Inbox-to-Today tests in both settlement orders and assert that only Today rows, cursor, account day, and order revision remain.

## Verification

- `pnpm --filter @keepling/web exec vitest run ...` passed the seven focused files: 84 tests.
- `pnpm --filter @keepling/web typecheck` passed.
- Targeted ESLint is clean for the pass-2 CR-01, CR-02, CR-03, and WR-01 files. It still reports the pre-existing `react-hooks/set-state-in-effect` error at `TaskList.tsx:196`; consistent with the prior review, that performance-only rule failure is not a narrative finding.
- `git diff --check` passed.
- The focused server test was not run because `KEEPLING_TEST_DATABASE_URL` is not configured in this review environment.

---

_Reviewed: 2026-08-31T23:50:13Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
