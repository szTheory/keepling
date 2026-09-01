---
phase: KPL-01-one-trustworthy-task
reviewed: 2026-08-31T17:44:27Z
depth: standard
files_reviewed: 155
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
  critical: 4
  warning: 2
  info: 0
  total: 6
status: issues_found
---

# Phase KPL-01: Code Review Report

**Reviewed:** 2026-08-31T17:44:27Z  
**Depth:** standard  
**Files Reviewed:** 155  
**Status:** issues_found

## Summary

The iteration-one patches close the narrow task-detail, capture replay, cursor, operator-URL, rate-limit, organization-management, and audit-write cases they target. The phase is still not safe to ship. The authentication recovery model cannot recover a genuinely expired session, several routed mutation surfaces never receive the continuation callback, and two command paths discard exact recovery state for the phase's own after-commit authentication fault. The audit repair also records reauthentication before the session rotation it claims to audit, and the recovery UI makes a state claim contradicted by its own after-commit fault model.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: A genuinely expired session cannot use the reauthentication continuation

**Classification:** BLOCKER  
**Files:**

- `/Users/jon/projects/keepling/apps/server/lib/keepling_web/auth.ex:58-83`
- `/Users/jon/projects/keepling/apps/server/lib/keepling_web/router.ex:75-102`
- `/Users/jon/projects/keepling/apps/web/src/app/AuthProvider.tsx:64-78`
- `/Users/jon/projects/keepling/apps/web/src/features/auth/Reauthenticate.tsx:26-38`
- `/Users/jon/projects/keepling/apps/web/e2e/lifecycle-recovery.spec.ts:179-205`

**Issue:** In production, `authentication_required` is emitted when `load_session` cannot assign an authenticated account. The browser responds by opening `Reauthenticate`, which posts to `/api/v1/reauthenticate`; that endpoint is itself behind the same `:authenticated` pipeline. An expired, revoked, or otherwise invalid session therefore receives `authentication_required` again and can never rotate credentials or resume the retained mutation. The new undo continuation only works for the synthetic test fault because that fault returns a 401 while deliberately leaving the underlying session valid. Its E2E test further intercepts `/api/v1/reauthenticate` and fabricates a 200 response, so it cannot detect the production route deadlock.

**Fix:** Distinguish `recent_authentication_required` from `authentication_required`. Continue to use `/reauthenticate` only while a valid session exists; for `authentication_required`, retain the exact continuation while running the normal login flow and resume it after a new authenticated session and CSRF token are established. Change the fault's recovery action accordingly and add a real-stack test that expires or revokes the session, performs an actual login without mocking the endpoint, and proves the exact original mutation resumes.

### CR-02: Routed task lifecycle actions never receive the authentication continuation

**Classification:** BLOCKER  
**Files:**

- `/Users/jon/projects/keepling/apps/web/src/app/routes.tsx:123-127`
- `/Users/jon/projects/keepling/apps/web/src/features/lists/TaskList.tsx:317-364`
- `/Users/jon/projects/keepling/apps/web/src/features/tasks/LifecycleActions.tsx:97-117`
- `/Users/jon/projects/keepling/apps/web/e2e/lifecycle-recovery.spec.ts:125-177`

**Issue:** `AppRoutes` has an `onAuthenticationRequired` callback, but it instantiates every `TaskList` without passing it. `TaskList` in turn instantiates `LifecycleActions` without the callback. After either before-acceptance or after-commit authentication interruption, the recovery panel renders “Sign in and continue,” but `requestAuthentication` returns immediately because its callback is undefined. The E2E tests stop after asserting that the button is visible and that the receipt exists; they never click the button or prove reconciliation, so they falsely certify a dead control.

**Fix:** Add the callback to `TaskListProps`, pass it from every routed `TaskList`, and forward it to `LifecycleActions`. Extend both real-stack fault tests to click through actual authentication and assert exact request identity plus final list reconciliation, including the after-commit receipt path.

### CR-03: Task-assignment recovery discards an accepted mutation on an after-commit authentication response

**Classification:** BLOCKER  
**Files:**

- `/Users/jon/projects/keepling/apps/web/src/features/organizations/OrganizationFields.tsx:120-125`
- `/Users/jon/projects/keepling/apps/web/src/features/organizations/OrganizationFields.tsx:158-204`
- `/Users/jon/projects/keepling/apps/web/src/app/routes.tsx:149-153`

**Issue:** Organization management now uses `ExactSubmission`, but assigning a project or tags still uses a bespoke path. Every `KeeplingApiError` other than a conflict clears `pendingSubmission`. The phase's `authentication_after_commit` fault can replace a successfully committed command response with an `authentication_required` problem, so this branch discards the only mutation identity capable of looking up the accepted receipt. The route also provides no authentication-continuation callback. A later Save creates a new mutation against the pre-acknowledgement task snapshot, allowing an accepted assignment to be silently misreported and retried as stale or conflicting.

**Fix:** Prepare assignment request bytes before delivery and drive them through `createTaskSubmission`/`ExactSubmission`, preserving lookup-versus-send state and the original mutation/task identity. Add `onAuthenticationRequired` to `OrganizationFields`, pass it from `AppRoutes`, and add before-acceptance, after-commit, response-loss, and exact-replay tests.

### CR-04: Today ordering loses the exact command and has no authentication recovery action

**Classification:** BLOCKER  
**Files:**

- `/Users/jon/projects/keepling/apps/web/src/features/lists/TaskList.tsx:194-259`
- `/Users/jon/projects/keepling/apps/web/src/features/lists/TaskList.tsx:491-512`

**Issue:** Today moves retain `submission` only for non-API transport exceptions. An `authentication_after_commit` response is a `KeeplingApiError`, so the code sets `moveError` but never stores the mutation ID in `unknownMove`. The error panel renders authentication copy with no button at all. The order change may already be committed while the browser keeps the old order and permanently loses the receipt identity needed to reconcile it. Other 5xx problem responses are likewise classified as generic and discard the command despite the API's own service-unavailable guidance to check the same mutation identity.

**Fix:** Put Today moves behind the same exact-submission state machine, with an acknowledgement matcher for mutation/task identity and order revision. Preserve all authentication and 5xx responses as recoverable unknown outcomes, wire the authentication callback, and test both after-commit authentication replacement and response loss through final reconciliation.

## Warnings

### WR-01: Reauthentication audit commits before session rotation and can record an action that never occurred

**Classification:** WARNING  
**Files:**

- `/Users/jon/projects/keepling/apps/server/lib/keepling/accounts.ex:231-265`
- `/Users/jon/projects/keepling/apps/server/lib/keepling/accounts.ex:274-329`
- `/Users/jon/projects/keepling/apps/server/lib/keepling_web/controllers/auth_controller.ex:111-138`

**Issue:** A valid password causes `record_required_security_audit("reauthenticated", now)` to commit in its own transaction. Only afterward does the controller call `rotate_session` in a separate statement/transaction. If rotation returns `:session_unavailable`, the database fails, or the process exits between calls, the audit trail says reauthentication succeeded even though no credential or recent-auth state was rotated. This is the same audit/state atomicity defect the iteration-one repair claims to close.

**Fix:** Expose one application operation that verifies the password and atomically rotates the locked session plus inserts `reauthenticated` in a single transaction. Return the rotated session only after both writes commit, and add an injected rotation/audit failure test proving neither state nor success audit can commit alone.

### WR-02: Authentication recovery copy asserts “not submitted” and “nothing changed” for an explicitly uncertain response

**Classification:** WARNING  
**Files:**

- `/Users/jon/projects/keepling/apps/web/src/features/recovery/RecoveryStrip.tsx:53-80`
- `/Users/jon/projects/keepling/apps/web/src/features/recovery/RecoveryStrip.tsx:90-96`
- `/Users/jon/projects/keepling/apps/web/src/features/organizations/OrganizationFields.tsx:390-402`
- `/Users/jon/projects/keepling/apps/server/lib/keepling_web/controllers/test_fault_controller.ex:76-87`

**Issue:** Both continuations label any authentication error during a send as `not-submitted`; the undo strip additionally tells the user “Nothing was changed.” The server's own `authentication_after_commit` mode deliberately replaces the response after committing the mutation, so neither claim is justified. Exact replay keeps the operation idempotent, but the UI violates the project's honest-state requirement and can mislead a user who leaves before reconciliation.

**Fix:** Treat every response received after dispatch as `submitted-unknown` unless the server provides a trustworthy before-acceptance proof. Use neutral copy such as “Checking whether the change was saved,” then lookup the receipt before any resend; reserve “nothing changed” for a terminal, verified rejection.

---

_Reviewed: 2026-08-31T17:44:27Z_  
_Reviewer: the agent (gsd-code-reviewer)_  
_Depth: standard_
