---
phase: KPL-01-one-trustworthy-task
reviewed: 2026-08-31T21:02:09Z
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

**Reviewed:** 2026-08-31T21:02:09Z
**Depth:** standard
**Files Reviewed:** 156
**Status:** issues_found

## Summary

The third fix pass repairs the five findings in the preceding report, including unsupported planning-conflict serialization, expired-session continuation for several list/session surfaces, parsed-5xx capture recovery, exact conflict-resolution lookup, and Today pagination refresh.

The complete anchored phase remains unsafe to ship. Three release-blocking recovery defects remain: task detail, activity, and organization reads still bypass the shared expired-session flow; an uncertain Today move can be replaced by a new mutation; and conflict choices can fence an already dispatched resolution. Two additional robustness defects allow concurrent authentication interruptions to overwrite each other and session administration to assert a definitive outcome after an uncertain response.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: Several routed reads still dead-end on genuine session expiry

**Classification:** BLOCKER

**File:** `/Users/jon/projects/keepling/apps/web/src/features/tasks/TaskEditor.tsx:100-121`

**Also affected:** `/Users/jon/projects/keepling/apps/web/src/features/activity/ActivityList.tsx:236-257`, `/Users/jon/projects/keepling/apps/web/src/features/organizations/OrganizationFields.tsx:138-154`, `/Users/jon/projects/keepling/apps/web/src/features/organizations/OrganizationFields.tsx:387-405`, `/Users/jon/projects/keepling/apps/web/src/app/routes.tsx:144-192`

**Issue:** The router supplies `onAuthenticationRequired` to task and organization screens, but their initial reads discard the actual `authentication_required` problem. `TaskEditor` collapses `getTask`/`getTaskActivity` failures into a generic error whose only action returns to Inbox. Its separately mounted `ActivityList` has no authentication callback at all. `OrganizationFields` and `OrganizationManager` likewise catch every failed read generically and never invoke the callback they already receive. A direct navigation or reload after session expiry therefore cannot complete the promised visible sign-in continuation on these routes; retrying or returning elsewhere is required, and any task draft reconstructed from the route is unavailable.

**Fix:** Give every authenticated read a shared error classifier and continuation wrapper. On `authentication_required`, retain the route/task identity, open the login continuation, and retry the exact read after the new session is established; handle retry failure without an unhandled promise. Pass the callback into `ActivityList` or load task and activity through one owning component. Add real-stack expired-session tests for `/tasks/:id`, activity pagination, `/tasks/:id/organizations`, `/projects`, and `/tags`.

### CR-02: A second Today move can overwrite an unresolved exact mutation

**Classification:** BLOCKER

**File:** `/Users/jon/projects/keepling/apps/web/src/features/lists/TaskList.tsx:281-319`

**Also affected:** `/Users/jon/projects/keepling/apps/web/src/features/lists/TaskList.tsx:420-439`, `/Users/jon/projects/keepling/apps/web/src/features/lists/TaskList.tsx:576-601`

**Issue:** `move()` always allocates a new mutation and overwrites `exactMove.current`. After an unknown response or authentication-required response, `movingTaskId` is reset to `null`; every Earlier/Later button is therefore enabled even though the original exact move remains unresolved. Clicking any move before using “Check again” or “Sign in and continue” replaces the only in-memory reference to the first receipt. The first move may already be accepted, while the new move is submitted against the old order revision and normally rejects stale. The browser can no longer reconcile the accepted first result and violates the exact-recovery guarantee the new Today receipt endpoint was added to provide.

**Fix:** Treat any nonterminal `exactMove.current` as a global Today-order lock. Disable all move controls while its state is `in_flight`, `unknown`, or `authentication_required`, and make `move()` refuse to replace it. Clear the reference only after a verified acknowledgement or terminal rejection. Add a test that forces an after-commit response loss, attempts another row move, then proves the original mutation remains the one checked and reconciled.

### CR-03: Conflict choices can fence a dispatched resolution and hide an accepted result

**Classification:** BLOCKER

**File:** `/Users/jon/projects/keepling/apps/web/src/features/tasks/ConflictResolver.tsx:119-125`

**Also affected:** `/Users/jon/projects/keepling/apps/web/src/features/tasks/ConflictResolver.tsx:160-195`, `/Users/jon/projects/keepling/apps/web/src/features/tasks/ConflictResolver.tsx:235-251`, `/Users/jon/projects/keepling/apps/web/src/features/tasks/ConflictResolver.tsx:261-300`

**Issue:** The selection buttons remain enabled while a resolution is in flight, unknown, or awaiting authentication. `choose()` responds by calling `exactSubmission.current?.fence()`, nulling the exact submission and clearing its visible recovery state. If the dispatched resolution was accepted but its response is delayed or lost, changing a choice permanently discards the mutation identity and acknowledgement path. A subsequent Save creates a different mutation against the already consumed conflict, so the UI can report stale while the first, now-hidden choice is the canonical accepted value.

**Fix:** Freeze every conflict selection once dispatch begins and keep it frozen through `unknown` and `authentication_required`. Only allow selection changes after a terminal verified rejection, or require an explicit cancel that first proves the original mutation was not accepted. Remove the ability to fence an in-flight exact submission. Add deferred-response and after-commit-loss tests that click a choice during recovery and assert the original identity cannot be discarded.

## Warnings

### WR-01: The authentication provider retains only one interruption continuation

**Classification:** WARNING

**File:** `/Users/jon/projects/keepling/apps/web/src/app/AuthProvider.tsx:64-84`

**Also affected:** `/Users/jon/projects/keepling/apps/web/src/app/routes.tsx:92-114`, `/Users/jon/projects/keepling/apps/web/src/app/routes.tsx:176-192`

**Issue:** Every call to `beginReauthentication` replaces the single `resumeRef.current`. The task-detail layout can mount several independently fetching or mutating surfaces at once (Inbox workspace, task editor, activity, undo), and concurrent 401 responses are therefore possible. The last response wins; completing login clears the interruption and invokes only that continuation. Earlier exact submissions remain in authentication-required state with no active overlay, forcing a second authentication cycle and making recovery order-dependent. `completeReauthentication` also clears the overlay before invoking the continuation as a fire-and-forget microtask, so a throwing read retry becomes an unhandled rejection with no shared recovery UI.

**Fix:** Model interruptions as a queue or keyed collection and drain all compatible continuations after one successful login/rotation. Await or explicitly catch each resume result, retaining a visible failed/unknown state when recovery itself fails. Add a test with two simultaneous authentication failures and assert neither continuation is overwritten.

### WR-02: Session administration makes definitive claims after uncertain delivery

**Classification:** WARNING

**File:** `/Users/jon/projects/keepling/apps/web/src/features/sessions/SessionList.tsx:120-151`

**Also affected:** `/Users/jon/projects/keepling/apps/web/src/features/sessions/SessionList.tsx:155-193`

**Issue:** Rename, revoke, and logout are ordinary one-shot requests without a mutation identity or post-failure state check. Every non-authentication failure is treated as definitive: rename says the existing label is unchanged, and revoke/logout says the session remains active. A proxy/network failure or parsed 5xx after the server commits makes those statements false. Retrying a revoke then receives `session_unavailable`, while an accepted logout leaves the page displaying an authenticated session until the next request fails.

**Fix:** Add idempotent mutation receipts for session administration, or reconcile uncertain failures by reloading the session inventory before claiming an outcome. For current-session logout, probe authentication state and transition to logged out when the session is gone. Reserve “unchanged/remains active” copy for verified terminal rejection and add after-commit response-loss tests.

---

_Reviewed: 2026-08-31T21:02:09Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
