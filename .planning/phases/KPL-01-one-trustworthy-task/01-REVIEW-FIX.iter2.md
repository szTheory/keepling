---
phase: KPL-01-one-trustworthy-task
fixed_at: 2026-08-31T17:32:53Z
review_path: .planning/phases/KPL-01-one-trustworthy-task/01-REVIEW.md
iteration: 1
findings_in_scope: 8
fixed: 8
skipped: 0
status: all_fixed
commits:
  - 2bb5764
  - 53a6e8a
  - 4bc85d3
  - 5f66fb9
  - d0d639a
  - edd4076
  - 30e32b6
  - 5015774
  - 28d7b78
  - 4e533af
  - ffb0d22
  - 63835db
  - f4cf6a7
  - 4111f2f
  - 011a7b2
tests:
  - repository integrity passed
  - server compile and 102 ExUnit tests passed
  - production route isolation passed
  - contract drift check passed
  - TypeScript typecheck passed
  - 78 Vitest tests passed
  - 11 Playwright real-stack tests passed
unresolved: []
---

# Phase KPL-01: Code Review Fix Report

**Fixed at:** 2026-08-31T17:32:53Z  
**Source review:** `.planning/phases/KPL-01-one-trustworthy-task/01-REVIEW.md`  
**Iteration:** 1

**Summary:**

- Findings in scope: 8
- Fixed: 8
- Skipped: 0

## Fixed Issues

### CR-01: Task detail links fail for every task outside the Inbox

**Files modified:** `apps/server/lib/keepling/adapters/postgres/command_store.ex`, `apps/server/lib/keepling/application/commands.ex`, `apps/server/lib/keepling_web/controllers/command_controller.ex`, `apps/server/lib/keepling_web/router.ex`, `packages/contracts/openapi/keepling.yaml`, `packages/contracts/generated/keepling.ts`, `apps/web/src/api/keepling.ts`, task and organization detail consumers, and focused server/browser/E2E tests  
**Commits:** `2bb5764`, `28d7b78`, `f4cf6a7`  
**Status:** fixed: requires human verification  
**Applied fix:** Added an account-scoped authoritative task-detail endpoint that includes Inbox, clarified, and completed tasks while explicitly excluding Trash. Task detail consumers now load by stable task identity, and regression fixtures exercise non-Inbox routes.

### CR-02: Quick Capture never resends an exact submission after a before-acceptance disconnect

**Files modified:** `apps/web/src/features/capture/QuickCapture.tsx`, `apps/web/src/features/auth/auth.test.tsx`  
**Commits:** `53a6e8a`, `ffb0d22`, `63835db`  
**Status:** fixed: requires human verification  
**Applied fix:** A missing mutation receipt now triggers retransmission of the already-prepared capture or planning command, preserving the original body and mutation/task identities. The regression test proves response loss, lookup miss, and byte-equivalent resend.

### CR-03: Undo cannot continue through reauthentication and loses its recovery identity

**Files modified:** `apps/web/src/App.tsx`, `apps/web/src/app/AppShell.tsx`, `apps/web/src/features/recovery/RecoveryStrip.tsx`, `apps/web/src/features/recovery/recovery-strip.test.tsx`, `apps/web/e2e/lifecycle-recovery.spec.ts`  
**Commits:** `4bc85d3`, `4111f2f`, `011a7b2`  
**Status:** fixed: requires human verification  
**Applied fix:** RecoveryStrip retains the prepared undo submission, routes authentication interruptions through the shared reauthentication continuation, uses the rotated CSRF token, and resumes the exact mutation identity and handle. Unit and real-stack tests cover the continuation.

### CR-04: Timezone changes leave Completed cursors valid after their grouping semantics change

**Files modified:** `apps/server/lib/keepling/accounts.ex`, `apps/server/test/keepling/accounts/setup_timezone_test.exs`, `apps/server/test/keepling/adapters/postgres/task_views_test.exs`  
**Commit:** `5f66fb9`  
**Status:** fixed: requires human verification  
**Applied fix:** A timezone change now increments `completed_view_revision` in the same locked account transaction as every other timezone-sensitive view revision. A pre-change Completed cursor is proven stale afterward.

### CR-05: The recovery operator permits bearer-token links over remote cleartext HTTP

**Files modified:** `apps/server/lib/keepling/operator_base_url.ex`, `apps/server/lib/mix/tasks/keepling.recover.ex`, `apps/server/lib/mix/tasks/keepling.setup_token.ex`, `apps/server/test/keepling/operator_base_url_test.exs`  
**Commit:** `d0d639a`  
**Status:** fixed  
**Applied fix:** Setup and recovery operators share one validated base-URL policy: remote capability links require HTTPS, HTTP is limited to loopback addresses, URI userinfo is rejected, and token paths are constructed safely.

### CR-06: Reauthentication has no brute-force or resource-exhaustion limit

**Files modified:** `apps/server/lib/keepling/accounts/rate_limit.ex`, `apps/server/lib/keepling_web/controllers/auth_controller.ex`, `apps/server/test/keepling/security_audit_test.exs`  
**Commit:** `edd4076`  
**Status:** fixed: requires human verification  
**Applied fix:** Reauthentication now passes through closed account and coarsened-source buckets before password verification, with bounded backoff, privacy-safe decision telemetry, and response equivalence between invalid and limited requests.

### CR-07: Organization management discards mutation identity on uncertain delivery

**Files modified:** `apps/web/src/api/keepling.ts`, `apps/web/src/app/routes.tsx`, `apps/web/src/commands/submission.ts`, `apps/web/src/features/organizations/OrganizationFields.tsx`, `apps/web/src/features/organizations/organization-fields.test.tsx`  
**Commit:** `30e32b6`  
**Status:** fixed: requires human verification  
**Applied fix:** Create, rename, archive, and unarchive now use the exact-submission state machine, retain their prepared request and identity across uncertain delivery and reauthentication, look up exact receipts, and resend only after an exact not-found result.

### WR-01: Security audit persistence failures are silently treated as success

**Files modified:** `apps/server/lib/keepling/accounts.ex`, `apps/server/lib/keepling/accounts/rate_limit.ex`, `apps/server/lib/keepling/accounts/security_audit.ex`, `apps/server/lib/keepling/application.ex`, `apps/server/test/keepling/security_audit_test.exs`, `apps/server/test/keepling/telemetry_redaction_test.exs`  
**Commits:** `5015774`, `4e533af`  
**Status:** fixed: requires human verification  
**Applied fix:** Success-critical audit writes now share the transaction with login/session/recovery state and roll it back on failure. Intentional best-effort writes preserve availability while emitting closed privacy-safe telemetry/logging and latching operator-readable degraded audit health. Failure-path tests cover both policies.

## Verification

Verification ran in the **main checkout after every review-fix worktree was fast-forwarded and transactionally removed**.

- `tooling/check-repository-integrity.sh` — passed.
- Phase server lane — runtime preflight, migrations, warning-free compile, and 102/102 ExUnit tests passed against disposable PostgreSQL.
- Production route isolation — passed.
- `pnpm contracts:check` — passed.
- `pnpm --filter @keepling/web typecheck` — passed.
- `pnpm --filter @keepling/web test --run --passWithNoTests` — 78/78 passed.
- Playwright real-stack suite — 11/11 passed. Alternate isolated ports were used because an unrelated user-owned Python server already occupied the default port 4173.

No in-scope finding remains unresolved.

---

_Fixed: 2026-08-31T17:32:53Z_  
_Fixer: the agent (gsd-code-fixer)_  
_Iteration: 1_
