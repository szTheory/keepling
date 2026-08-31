---
phase: KPL-01-one-trustworthy-task
reviewed: 2026-08-31T19:13:04Z
depth: standard
files_reviewed: 156
files_reviewed_list:
  - .gitignore
  - apps/server/.formatter.exs
  - apps/server/.gitignore
  - apps/server/README.md
  - apps/server/config/config.exs
  - apps/server/config/dev.exs
  - apps/server/config/prod.exs
  - apps/server/config/runtime.exs
  - apps/server/config/test.exs
  - apps/server/lib/keepling.ex
  - apps/server/lib/keepling/accounts.ex
  - apps/server/lib/keepling/accounts/account.ex
  - apps/server/lib/keepling/accounts/rate_limit.ex
  - apps/server/lib/keepling/accounts/security_audit.ex
  - apps/server/lib/keepling/accounts/session.ex
  - apps/server/lib/keepling/adapters/postgres/command_store.ex
  - apps/server/lib/keepling/adapters/postgres/task_views.ex
  - apps/server/lib/keepling/application.ex
  - apps/server/lib/keepling/application/activity.ex
  - apps/server/lib/keepling/application/commands.ex
  - apps/server/lib/keepling/application/task_views.ex
  - apps/server/lib/keepling/application/undo.ex
  - apps/server/lib/keepling/domain/merge.ex
  - apps/server/lib/keepling/domain/organization.ex
  - apps/server/lib/keepling/domain/task.ex
  - apps/server/lib/keepling/domain/task_dates.ex
  - apps/server/lib/keepling/operator_base_url.ex
  - apps/server/lib/keepling/repo.ex
  - apps/server/lib/keepling_web.ex
  - apps/server/lib/keepling_web/auth.ex
  - apps/server/lib/keepling_web/controllers/activity_controller.ex
  - apps/server/lib/keepling_web/controllers/auth_controller.ex
  - apps/server/lib/keepling_web/controllers/command_controller.ex
  - apps/server/lib/keepling_web/controllers/error_json.ex
  - apps/server/lib/keepling_web/controllers/task_view_controller.ex
  - apps/server/lib/keepling_web/controllers/test_fault_controller.ex
  - apps/server/lib/keepling_web/endpoint.ex
  - apps/server/lib/keepling_web/router.ex
  - apps/server/lib/keepling_web/telemetry.ex
  - apps/server/lib/mix/tasks/keepling.recover.ex
  - apps/server/lib/mix/tasks/keepling.setup_token.ex
  - apps/server/lib/mix/tasks/keepling.timezone.ex
  - apps/server/mix.exs
  - apps/server/priv/repo/migrations/.formatter.exs
  - apps/server/priv/repo/migrations/20260830000100_create_core_task_command_tables.exs
  - apps/server/priv/repo/migrations/20260830000200_add_closed_setup_and_timezone.exs
  - apps/server/priv/repo/migrations/20260830000210_expand_auth_lifecycle.exs
  - apps/server/priv/repo/migrations/20260830000300_add_task_details.exs
  - apps/server/priv/repo/migrations/20260830000400_add_organizations.exs
  - apps/server/priv/repo/migrations/20260830000500_expand_task_activity.exs
  - apps/server/priv/repo/migrations/20260830000600_add_task_dates.exs
  - apps/server/priv/repo/migrations/20260830000650_add_task_view_projections.exs
  - apps/server/priv/repo/migrations/20260830000700_add_trash_state.exs
  - apps/server/priv/repo/migrations/20260830000800_add_persisted_conflicts.exs
  - apps/server/priv/repo/migrations/20260830000900_add_undo_handles.exs
  - apps/server/priv/repo/migrations/20260830000950_expand_today_move_receipts.exs
  - apps/server/priv/repo/seeds.exs
  - apps/server/test/architecture_test.exs
  - apps/server/test/keepling/accounts/setup_timezone_test.exs
  - apps/server/test/keepling/adapters/postgres/conflict_test.exs
  - apps/server/test/keepling/adapters/postgres/idempotency_test.exs
  - apps/server/test/keepling/adapters/postgres/task_views_test.exs
  - apps/server/test/keepling/application/activity_test.exs
  - apps/server/test/keepling/application/task_lifecycle_test.exs
  - apps/server/test/keepling/application/trash_restore_test.exs
  - apps/server/test/keepling/application/undo_test.exs
  - apps/server/test/keepling/domain/edit_task_test.exs
  - apps/server/test/keepling/domain/long_sequence_test.exs
  - apps/server/test/keepling/domain/organization_test.exs
  - apps/server/test/keepling/domain/task_dates_test.exs
  - apps/server/test/keepling/operator_base_url_test.exs
  - apps/server/test/keepling/security_audit_test.exs
  - apps/server/test/keepling/telemetry_redaction_test.exs
  - apps/server/test/keepling_web/auth_test.exs
  - apps/server/test/keepling_web/controllers/error_json_test.exs
  - apps/server/test/keepling_web/test_fault_test.exs
  - apps/server/test/support/clock.ex
  - apps/server/test/support/concurrency_case.ex
  - apps/server/test/support/conn_case.ex
  - apps/server/test/support/data_case.ex
  - apps/server/test/test_helper.exs
  - apps/web/.gitignore
  - apps/web/README.md
  - apps/web/components.json
  - apps/web/e2e/auth-recovery.spec.ts
  - apps/web/e2e/lifecycle-recovery.spec.ts
  - apps/web/e2e/phase1.spec.ts
  - apps/web/e2e/skeleton.spec.ts
  - apps/web/e2e/support/stack.ts
  - apps/web/e2e/visual.spec.ts
  - apps/web/eslint.config.js
  - apps/web/index.html
  - apps/web/package.json
  - apps/web/playwright.config.ts
  - apps/web/src/App.tsx
  - apps/web/src/api/keepling.ts
  - apps/web/src/app/AppShell.tsx
  - apps/web/src/app/AuthProvider.tsx
  - apps/web/src/app/routes.tsx
  - apps/web/src/commands/submission.test.ts
  - apps/web/src/commands/submission.ts
  - apps/web/src/components/ui/button.tsx
  - apps/web/src/features/activity/ActivityList.tsx
  - apps/web/src/features/activity/activity-list.test.tsx
  - apps/web/src/features/auth/LoginForm.tsx
  - apps/web/src/features/auth/Reauthenticate.tsx
  - apps/web/src/features/auth/RecoveryReset.tsx
  - apps/web/src/features/auth/SetupForm.tsx
  - apps/web/src/features/auth/auth.test.tsx
  - apps/web/src/features/capture/QuickCapture.tsx
  - apps/web/src/features/lists/TaskList.tsx
  - apps/web/src/features/lists/TodayList.tsx
  - apps/web/src/features/lists/TrashList.tsx
  - apps/web/src/features/lists/UpcomingList.tsx
  - apps/web/src/features/lists/task-lists.test.tsx
  - apps/web/src/features/lists/trash-list.test.tsx
  - apps/web/src/features/organizations/OrganizationFields.tsx
  - apps/web/src/features/organizations/organization-fields.test.tsx
  - apps/web/src/features/recovery/MutationRecoveryPanel.tsx
  - apps/web/src/features/recovery/RecoveryStrip.tsx
  - apps/web/src/features/recovery/recovery-strip.test.tsx
  - apps/web/src/features/sessions/SessionList.tsx
  - apps/web/src/features/tasks/ConflictResolver.tsx
  - apps/web/src/features/tasks/LifecycleActions.tsx
  - apps/web/src/features/tasks/TaskEditor.tsx
  - apps/web/src/features/tasks/conflict-resolver.test.tsx
  - apps/web/src/features/tasks/lifecycle.test.tsx
  - apps/web/src/features/tasks/task-editor.test.tsx
  - apps/web/src/index.css
  - apps/web/src/lib/utils.ts
  - apps/web/src/main.tsx
  - apps/web/src/test/setup.ts
  - apps/web/src/test/ui-contract.test.tsx
  - apps/web/tsconfig.app.json
  - apps/web/tsconfig.json
  - apps/web/tsconfig.node.json
  - apps/web/vite.config.ts
  - apps/web/vitest.config.ts
  - package.json
  - packages/contracts/openapi/keepling.yaml
  - packages/contracts/vectors/activity.json
  - packages/contracts/vectors/conflicts.json
  - packages/contracts/vectors/editing.json
  - packages/contracts/vectors/lifecycle.json
  - packages/contracts/vectors/organizations.json
  - packages/contracts/vectors/task-dates.json
  - packages/contracts/vectors/trash-restore.json
  - packages/contracts/vectors/undo.json
  - packages/design-tokens/css.css
  - packages/design-tokens/tokens.json
  - pnpm-workspace.yaml
  - tooling/check-contracts.mjs
  - tooling/run-local-stack.sh
  - tooling/runtime-preflight.sh
  - tooling/runtime-versions.env
  - tooling/test-phase-1.sh
findings:
  critical: 3
  warning: 2
  info: 0
  total: 5
status: issues_found
---

# Phase KPL-01: Code Review Report

**Reviewed:** 2026-08-31T19:13:04Z
**Depth:** standard
**Files Reviewed:** 156
**Status:** issues_found

## Summary

The iteration-2 fixes do repair the six previously reported paths: an expired exact task mutation can now continue through login, routed task lifecycle actions receive the authentication callback, organization assignment retains its exact prepared command, Today movement has an account-scoped receipt lookup, reauthentication audit and session rotation are atomic, and the shared recovery strip no longer asserts that an interrupted request was not submitted.

The full anchored phase diff still has three release-blocking correctness/recovery defects and two robustness defects. Most seriously, a normal stale task-date command reaches an unimplemented conflict serializer and crashes instead of returning its promised stable 409 receipt. Several authenticated screens still cannot recover from a genuinely expired session, and quick capture discards mutation identity when a dispatched request receives a parsed 5xx response. Green tests do not cover these real call paths.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: Stale date and planning commands crash while trying to persist an unsupported conflict

**Classification:** BLOCKER

**File:** `/Users/jon/projects/keepling/apps/server/lib/keepling/domain/task_dates.ex:106-134`

**Also affected:** `/Users/jon/projects/keepling/apps/server/lib/keepling/adapters/postgres/command_store.ex:652-678`, `/Users/jon/projects/keepling/apps/server/lib/keepling/adapters/postgres/command_store.ex:719-753`

**Issue:** `TaskDates.edit/2`, `plan_for_today/3`, and `unplan/2` legitimately return `{:error, {:edit_conflict, fields}}` when a touched date changed since the caller's base. `CommandStore.decide_existing/6` classifies every `:edit_conflict` as persistable and calls `conflict_values/2`, but that function has clauses only for detail edits, completion/reopen, and trash/restore. An `:edit_task_dates`, `:plan_for_today`, or `:unplan_task` overlap therefore raises `FunctionClauseError` inside the transaction. The exception is not one of the rescued database exceptions, so the request becomes a 500 and its receipt rolls back. Exact replay crashes again instead of returning the contract's terminal 409, making a common multi-device planning conflict unrecoverable.

**Fix:** Restrict persisted conflict handling by both conflict kind and command type, and return a stable semantic rejection for date/planning conflicts unless the persisted-conflict schema, API DTO, and resolver are deliberately expanded. For example:

```elixir
defp persisted_conflict_reason?(%{type: type}, {:edit_conflict, fields})
     when type in [:edit_task, :clarify_task] and is_list(fields),
     do: true

defp persisted_conflict_reason?(%{type: type}, {:edit_conflict, fields})
     when type in [:edit_task_dates, :plan_for_today, :unplan_task] and is_list(fields),
     do: false
```

Pass `command` into the predicate, persist the resulting 409 command receipt, and add adapter/controller tests for overlapping `edit-task-dates`, `plan-for-today`, and `unplan-task` requests, including exact replay and mutation lookup.

### CR-02: Genuine session expiry still leaves list, Trash, and session administration in recovery dead ends

**Classification:** BLOCKER

**File:** `/Users/jon/projects/keepling/apps/web/src/features/lists/TaskList.tsx:143-181`

**Also affected:** `/Users/jon/projects/keepling/apps/web/src/features/lists/TaskList.tsx:502-512`, `/Users/jon/projects/keepling/apps/web/src/app/routes.tsx:117-135`, `/Users/jon/projects/keepling/apps/web/src/features/lists/TrashList.tsx:74-124`, `/Users/jon/projects/keepling/apps/web/src/features/lists/TrashList.tsx:202-211`, `/Users/jon/projects/keepling/apps/web/src/features/sessions/SessionList.tsx:98-123`, `/Users/jon/projects/keepling/apps/web/src/app/AppShell.tsx:158-163`

**Issue:** The iteration-2 callback repair reaches task lifecycle mutations, but the initial/read retry paths never invoke it. `TaskList` recognizes `authentication_required`, then its “Sign in again” button simply repeats the same GET with the same expired cookie. `AuthProvider` still says authenticated, so navigating to `/login` renders “Already signed in.” `/trash` is not wrapped with `withInterruption`; restore maps a 401 to `authentication` but “Sign in and continue” directly resends with the same expired session. `SessionList` similarly turns recent-auth failure into text and closes its dialog without opening reauthentication. These are genuine expired/revoked-session paths, not merely uncertain fault responses: the offered actions repeat 401 forever, and recovery requires an undocumented full reload that discards in-memory intent.

**Fix:** Centralize authentication failure handling at the authenticated API/AuthProvider boundary, or pass the same interruption callback through every authenticated surface. An expired session must clear stale auth and present login; `recent_authentication_required` must open the reauthentication overlay. Wrap Trash and Sessions in the routed interruption boundary, convert restore to the shared exact-submission state machine, and have read retries transition auth before retrying. Add real-stack tests that revoke/expire the current session on each screen and complete the visible login/reauth flow through the final read or mutation acknowledgement.

### CR-03: Quick capture discards its accepted mutation identity on a dispatched 5xx and can create duplicate tasks

**Classification:** BLOCKER

**File:** `/Users/jon/projects/keepling/apps/web/src/features/capture/QuickCapture.tsx:83-113`

**Also affected:** `/Users/jon/projects/keepling/apps/web/src/features/capture/QuickCapture.tsx:147-162`, `/Users/jon/projects/keepling/apps/web/src/commands/submission.ts:147-174`

**Issue:** After dispatch, `QuickCapture.deliver` treats every parsed `KeeplingApiError` other than authentication as terminal. For the capture stage, line 108 clears `submission`, unlocks the draft, and the next click creates new task and mutation IDs. That includes all 5xx responses, even though a reverse proxy or fault boundary can produce a 5xx after the server accepted and receipted the original request. The shared submission classifier correctly treats status `>= 500` as unknown, but QuickCapture bypasses it. A user following the enabled retry path can therefore create a second accepted task while the first accepted task remains in PostgreSQL, violating the phase's no-silent-duplication trust requirement.

**Fix:** Run both capture and optional plan stages through `createTaskSubmission` with immutable prepared requests, or at minimum classify every post-dispatch 5xx as unknown, retain the original request and identity, and call `getMutation` before any resend. Add a test where the server commits capture but the client receives a parsed 5xx response (not only a thrown network error), then assert lookup settles the original mutation and no second task ID is generated.

## Warnings

### WR-01: Conflict resolution labels resubmission as a receipt check and bypasses the shared exact-recovery state machine

**Classification:** WARNING

**File:** `/Users/jon/projects/keepling/apps/web/src/features/tasks/ConflictResolver.tsx:107-143`

**Also affected:** `/Users/jon/projects/keepling/apps/web/src/features/tasks/ConflictResolver.tsx:224-229`

**Issue:** An authentication error is recorded as `kind: 'not-submitted'` even though it was caught after `resolveTaskConflict` dispatched, and the resume callback sends immediately. A transport-unknown state displays “Checking whether your resolution was saved…” but its “Check again” action also calls `deliver`, which sends instead of looking up the receipt. Server idempotency limits duplicate writes, but the UI's state and wording are false and recovery does not verify the stored acknowledgement's conflict identity before deciding to replay.

**Fix:** Prepare the resolve command once and use `createTaskSubmission` (with the additional `resolvedConflictId` identity match). Mark post-dispatch authentication as `submitted-unknown`, perform `getMutation` before resend, and add before-acceptance, after-commit, authentication-after-commit, and changed-identity tests.

### WR-02: Moving the last visible Today row can be accepted against a hidden row while the UI shows no movement and retains a stale cursor

**Classification:** WARNING

**File:** `/Users/jon/projects/keepling/apps/web/src/features/lists/TaskList.tsx:115-125`

**Also affected:** `/Users/jon/projects/keepling/apps/web/src/features/lists/TaskList.tsx:222-239`, `/Users/jon/projects/keepling/apps/web/src/features/lists/TaskList.tsx:390-410`, `/Users/jon/projects/keepling/apps/server/lib/keepling/adapters/postgres/task_views.ex:601-627`

**Issue:** Today pages load only a slice, but every row receives Earlier/Later controls. The server reorders the complete section (up to 500 tasks), while the client `swap` refuses to move past the loaded array boundary. If a 20-item page has a hidden item 21, moving item 20 later is accepted and swaps it with the hidden row on the server; settlement advances `orderRevision` but leaves visible items and `nextCursor` unchanged. The user sees “Today order updated” with no visible change, and the next load-more request uses a cursor bound to the old order revision and fails stale.

**Fix:** Disable boundary movement until the adjacent row is loaded, or refresh the authoritative first page after acknowledgement and replace both rows and cursor. Add a test with more than one Today page that moves the last visible row across the page boundary and then loads the next page without a stale-cursor error.

---

_Reviewed: 2026-08-31T19:13:04Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
