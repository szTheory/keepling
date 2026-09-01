---
phase: KPL-01-one-trustworthy-task
reviewed: 2026-08-31T16:24:52Z
depth: standard
files_reviewed: 152
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
  critical: 7
  warning: 1
  info: 0
  total: 8
status: issues_found
---

# Phase KPL-01: Code Review Report

**Reviewed:** 2026-08-31T16:24:52Z  
**Depth:** standard  
**Files Reviewed:** 152  
**Status:** issues_found

## Summary

The phase implements a substantial task, recovery, authentication, and organization surface, but the reviewed code contains seven ship-blocking correctness/security defects and one robustness warning. The most serious failures are concentrated at trust boundaries promised by the phase: several mutations cannot be retried with their original identity after an uncertain response, task detail routes cannot load the tasks that link to them, undo cannot survive reauthentication, completed cursors remain valid across a timezone change that changes their rendered grouping, reauthentication is unthrottled, and the recovery operator can disclose its bearer token over cleartext remote HTTP.

## Narrative Findings (AI reviewer)

### Critical Issues

#### CR-01: Task detail links fail for every task outside the Inbox

**Classification:** BLOCKER  
**Files:**

- `/Users/jon/projects/keepling/apps/web/src/features/tasks/TaskEditor.tsx:103-111`
- `/Users/jon/projects/keepling/apps/web/src/features/organizations/OrganizationFields.tsx:61-69`
- `/Users/jon/projects/keepling/apps/web/src/features/lists/TaskList.tsx:317-324`
- `/Users/jon/projects/keepling/apps/server/lib/keepling/adapters/postgres/command_store.ex:57-66`

**Issue:** Every Today, Upcoming, and Completed row links to `/tasks/:id`, but both task-detail components load the task by calling `getInbox()`. The Inbox query explicitly excludes clarified and completed tasks. Consequently, a valid row from Today, Upcoming, or Completed opens the editor and deterministically lands in its load-error state; organization assignment has the same failure. This is not an intermittent projection issue—the chosen endpoint cannot return those tasks.

**Fix:** Add an account-scoped authoritative `GET /api/v1/tasks/:task_id` endpoint that returns the editable task snapshot independent of list membership (with an explicit policy for trashed tasks), expose it in the contract/client, and use it in both components. Add browser tests that open clarified and completed rows, not only Inbox rows.

#### CR-02: Quick Capture never resends an exact submission after a before-acceptance disconnect

**Classification:** BLOCKER  
**File:** `/Users/jon/projects/keepling/apps/web/src/features/capture/QuickCapture.tsx:114-138`  
**Issue:** When delivery has an unknown outcome, “Check again” performs a mutation lookup. If the server returns `mutation_not_found`, the catch block merely restores the same `unknown` state. Every subsequent check repeats the lookup forever; the preserved capture/plan request is never delivered again. A disconnect before server acceptance therefore strands the capture even though the exact request bytes and mutation ID are still present. The reusable exact-submission implementation already handles this case by transitioning from a not-found lookup to an exact send (`apps/web/src/commands/submission.ts:113-116`).

**Fix:** On `mutation_not_found`, call `deliver(current, activeCsrfToken)` with the preserved `Submission`, or migrate Quick Capture to the existing exact-submission state machine. Add a test that simulates network failure before acceptance, lookup-not-found, then successful exact replay with the original task and mutation IDs.

#### CR-03: Undo cannot continue through reauthentication and loses its recovery identity

**Classification:** BLOCKER  
**Files:**

- `/Users/jon/projects/keepling/apps/web/src/features/recovery/RecoveryStrip.tsx:62-67`
- `/Users/jon/projects/keepling/apps/web/src/features/recovery/RecoveryStrip.tsx:106-109`
- `/Users/jon/projects/keepling/apps/web/src/app/routes.tsx:109-120`

**Issue:** On an `authentication_required` response, the undo strip renders a plain link to `/login` rather than registering a continuation with `AuthProvider`. While the client still believes the session is authenticated, that route displays “Already signed in,” so the user cannot reauthenticate. If the user reloads to refresh auth state, the strip unmounts and its in-memory undo handle/mutation ID is lost. The promised exact undo operation therefore cannot be resumed after session expiry.

**Fix:** Give `RecoveryStrip` the same `onAuthenticationRequired(interruption, continuation)` integration used by other mutation components. Preserve the prepared undo submission while the reauthentication dialog rotates credentials, then retry or reconcile that exact mutation with the new CSRF token. Cover the expired-session undo path in an end-to-end test.

#### CR-04: Timezone changes leave Completed cursors valid after their grouping semantics change

**Classification:** BLOCKER  
**Files:**

- `/Users/jon/projects/keepling/apps/server/lib/keepling/accounts.ex:896-939`
- `/Users/jon/projects/keepling/apps/server/lib/keepling/adapters/postgres/task_views.ex:205-226`
- `/Users/jon/projects/keepling/apps/server/lib/keepling/adapters/postgres/task_views.ex:439-453`
- `/Users/jon/projects/keepling/apps/web/src/features/lists/TaskList.tsx:155-167`

**Issue:** Changing the account timezone bumps Today, Upcoming, and Activity revisions, but not `completed_view_revision`. Completed items derive `completed_on` and their Today/Earlier section from the account timezone. An old Completed cursor is therefore accepted after a timezone change even though the representation semantics have changed, and the browser appends the newly interpreted page to already rendered items from the old timezone. The result can be a single Completed list with internally inconsistent dates and sections.

**Fix:** Select, increment, and return `completed_view_revision` in the timezone-change transaction alongside the other affected revisions. Update the setting result/contract if it exposes revision state, and add a test proving that a Completed cursor issued before a timezone change is rejected as stale.

#### CR-05: The recovery operator permits bearer-token links over remote cleartext HTTP

**Classification:** BLOCKER  
**Files:**

- `/Users/jon/projects/keepling/apps/server/lib/mix/tasks/keepling.recover.ex:24-47`
- `/Users/jon/projects/keepling/apps/server/lib/mix/tasks/keepling.setup_token.ex:47-58`

**Issue:** `mix keepling.recover` accepts any absolute `http://` host and prints a password-reset bearer token into that URL. Running the documented recovery command with a non-loopback HTTP base URL exposes the token to network interception and gives the interceptor control of the account password and sessions. The setup-token command correctly limits cleartext HTTP to loopback, so the two equally sensitive operator paths have inconsistent security enforcement.

**Fix:** Share one base-URL validator between both tasks: require HTTPS for non-loopback hosts, permit HTTP only for loopback development addresses, reject URI userinfo, and update the error text accordingly. Add unit coverage for remote HTTP rejection and localhost/HTTPS acceptance.

#### CR-06: Reauthentication has no brute-force or resource-exhaustion limit

**Classification:** BLOCKER  
**Files:**

- `/Users/jon/projects/keepling/apps/server/lib/keepling_web/controllers/auth_controller.ex:111-125`
- `/Users/jon/projects/keepling/apps/server/lib/keepling/accounts/rate_limit.ex:17-35`

**Issue:** Setup, login, and recovery are protected by account/source rate limiting, but the reauthentication endpoint performs an Argon2 password verification and session rotation without any admission check. A compromised but not recently authenticated session can make unlimited password guesses against the recent-authentication gate; independently, repeated Argon2 calls provide a straightforward authenticated CPU-exhaustion path.

**Fix:** Add a `:reauthentication` policy to `RateLimit`, admit requests by account and coarsened source before password verification, and record/emit the same privacy-safe decisions as other authentication flows. Return a generic rate-limited authentication response and add tests for both account and source buckets.

#### CR-07: Organization management discards mutation identity on uncertain delivery

**Classification:** BLOCKER  
**File:** `/Users/jon/projects/keepling/apps/web/src/features/organizations/OrganizationFields.tsx:293-404`  
**Issue:** Create, rename, archive, and unarchive each construct a fresh mutation ID inside the click handler and discard the request on every error. A response lost after server acceptance is shown as a generic failure; retrying creates a different organization for Create or sends a different mutation against stale revision state for the other operations. This bypasses the server’s mutation-receipt/idempotency contract and permits accepted organization changes to be silently misreported or duplicated.

**Fix:** Prepare and retain an immutable submission for each organization action before network delivery. On a transport-unknown result, expose reconciliation and retry the exact mutation/request bytes until a terminal acknowledgement or rejection is known; only then clear it. Reuse the generic exact-submission state machine and add accepted-but-response-lost tests for all four operations.

### Warnings

#### WR-01: Security audit persistence failures are silently treated as success

**Classification:** WARNING  
**Files:**

- `/Users/jon/projects/keepling/apps/server/lib/keepling/accounts.ex:848-857`
- `/Users/jon/projects/keepling/apps/server/lib/keepling/accounts/rate_limit.ex:109-125`

**Issue:** Both general security-audit writes and rate-limit audit writes swallow database errors and exceptions without surfacing any signal. Login, reauthentication, session revocation, recovery issuance, and throttling can therefore succeed while their supposedly inspectable security trail is silently absent. That weakens incident reconstruction and violates the project’s requirement that human and agent actions remain inspectable.

**Fix:** Make audit insertion part of the same transaction for security state changes whose success requires an audit record. Where an availability-driven fail-open policy is intentional (for example, recording a rejected login), emit a privacy-safe structured error/metric and expose degraded audit health so operators can detect the gap; add failure-path tests for both policies.

---

_Reviewed: 2026-08-31T16:24:52Z_  
_Reviewer: the agent (gsd-code-reviewer)_  
_Depth: standard_
