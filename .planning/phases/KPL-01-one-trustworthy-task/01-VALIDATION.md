---
phase: 1
slug: one-trustworthy-task
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-08-30
audited: 2026-08-31T23:29:16-04:00
automated_tasks: 60/60
automated_uat: 3/3
manual_uat_required: 0
---

# Phase 1 — Validation Strategy

## Test Infrastructure

| Property | Value |
|---|---|
| Framework | ExUnit + StreamData; Ecto SQL Sandbox against real PostgreSQL; Vitest + Testing Library; Playwright + axe |
| Config | `apps/server/test/test_helper.exs`, all support cases, `apps/web/vitest.config.ts`, `apps/web/src/test/setup.ts`, `apps/web/playwright.config.ts` |
| Quick run | Narrow Mix/Vitest file for the task |
| Full suite | `./tooling/test-phase-1.sh` |
| Runtime | Measure during execution; narrow feedback target below 30 seconds |

## Sampling Rate

- After every task commit: run the task's narrow automated check.
- After every wave: run server, contracts, Vitest, and real-stack smoke lanes that exist at that wave.
- Before verification: run `./tooling/test-phase-1.sh --run`; its final lane validates all three automated UAT evidence mappings after the real-stack suite passes.
- Missing or unavailable PostgreSQL, browser, or UAT-mapping evidence is blocked, never a pass.

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Automated Command | File / Wave 0 State | Status |
|---|---|---:|---|---|---|---|---|---|
| 01-01-T1 | 01-01 | 0 | QUAL-01 | T-KPL01-SC, T-KPL01-01 | Human-approved official provenance precedes every flagged install | `test -f .planning/phases/KPL-01-one-trustworthy-task/01-PACKAGE-APPROVAL.md && for field in Package Version Registry Repository Disposition; do rg -n "^${field}:" .planning/phases/KPL-01-one-trustworthy-task/01-PACKAGE-APPROVAL.md >/dev/null; done` | ❌ Wave 0 — approval artifact created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-01-T2 | 01-01 | 0 | QUAL-01 | T-KPL01-RT | Exact Elixir/OTP/PostgreSQL gate passes without changing `.tool-versions` | `set -eu; before=absent; if test -f .tool-versions; then before=$(shasum -a 256 .tool-versions); fi; ./tooling/runtime-preflight.sh --check; ./tooling/runtime-preflight.sh --exec -- sh -c 'elixir --version && erl -noshell -eval '\''io:format("~s~n", [erlang:system_info(otp_release)]), halt().'\'' && postgres --version && psql --version'; after=absent; if test -f .tool-versions; then after=$(shasum -a 256 .tool-versions); fi; test "$before" = "$after"` | ❌ Wave 0 — manifest/check script created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-02-T1 | 01-02 | 1 | QUAL-01, SRV-02 | T-KPL01-02, T-KPL01-04 | Exact approved Mix graph, including the Hammer 7.4.1 manifest/lock pin, and standalone OTP core compile; app-owned limiter wiring remains owned by 01-07 | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix deps.get --check-locked && mix deps.unlock --check-unused && mix compile --warnings-as-errors'` | ❌ Planned — core scaffold and lockfile created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-02-T2 | 01-02 | 1 | QUAL-01, SRV-02 | T-KPL01-03 | All environment configs compile under the approved runtime | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && MIX_ENV=test mix compile --warnings-as-errors && MIX_ENV=prod mix compile --warnings-as-errors'` | ❌ Planned — environment config created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-03-T1 | 01-03 | 2 | QUAL-01, SRV-02 | T-KPL01-07 | Endpoint/web namespace/router/telemetry/seeds compile and routes list | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix compile --warnings-as-errors && mix phx.routes'` | ❌ Planned — web runtime generated after 01-02 core | ✅ passed — full phase gate 2026-08-31 |
| 01-03-T2 | 01-03 | 2 | SRV-02 | T-KPL01-05, T-KPL01-06 | Inward semantic boundary and independent connections exist first | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/architecture_test.exs'` | ❌ Planned — architecture/concurrency support created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-04-T1 | 01-04 | 1 | WEB-01, WEB-02 | T-KPL01-05 | Vitest and real-stack Playwright configs load before feature use | `pnpm --filter @keepling/web test --run --passWithNoTests && pnpm --filter @keepling/web exec playwright test --list` | ❌ Wave 0 — browser configs/support created by task after 01-01 gate | ✅ passed — full phase gate 2026-08-31 |
| 01-04-T2 | 01-04 | 1 | QUAL-01, SRV-02 | T-KPL01-07, T-KPL01-08 | OpenAPI generation, runtime-gated stack, and phase-runner config execute | `pnpm contracts:check && ./tooling/run-local-stack.sh --check-config && ./tooling/test-phase-1.sh --list` | ❌ Wave 0 — contracts/tooling created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-05-T1 | 01-05 | 3 | GTD-01, WEB-01 | T-KPL01-09..10 | Authenticated capture traverses every production boundary and reloads | `pnpm --filter @keepling/web test:e2e --grep @skeleton` | ❌ Planned — E2E file created by task; Wave 0 complete via 01-01..03 | ✅ passed — full phase gate 2026-08-31 |
| 01-05-T2 | 01-05 | 3 | GTD-01, SRV-03 | T-KPL01-10 | Concurrent replay yields one stable capture | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling/adapters/postgres/idempotency_test.exs' && pnpm contracts:check` | ❌ Planned — focused test created by task; Wave 0 complete via 01-01..03 | ✅ passed — full phase gate 2026-08-31 |
| 01-06-T1 | 01-06 | 4 | SRV-01, SRV-02, SRV-03 | T-KPL01-11..14 | Operator setup token and browser consumption create exactly one account with explicit IANA timezone | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling/accounts/setup_timezone_test.exs --only setup' && pnpm contracts:check` | ❌ Planned — setup command/schema/test/contract created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-06-T2 | 01-06 | 4 | SRV-01, SRV-02, QUAL-01 | T-KPL01-13, T-KPL01-14 | Operator timezone change validates IANA, preserves dates, audits safely, and invalidates projections | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling/accounts/setup_timezone_test.exs --only timezone'` | ❌ Planned — timezone command and focused test created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-07-T1 | 01-07 | 5 | SRV-01 | T-KPL01-13, T-KPL01-14 | Login/recovery/session lifecycle plus atomic OpenAPI/generated drift proof | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling_web/auth_test.exs' && pnpm contracts:check` | ❌ Planned — auth test/contract generated by task | ✅ passed — full phase gate 2026-08-31 |
| 01-07-T2 | 01-07 | 5 | SRV-01, QUAL-01 | T-KPL01-15, T-KPL01-16 | Supervised Hammer 7 limiter starts, restarts, remains usable, isolates setup/login/recovery account/source buckets, bounds backoff, and keeps audit/telemetry private | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling/security_audit_test.exs --only rate_limit && mix test test/keepling/telemetry_redaction_test.exs'` | ❌ Planned — focused limiter lifecycle/bucket and redaction tests created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-08-T1 | 01-08 | 6 | SRV-01, WEB-02 | T-KPL01-17 | Routed setup/login/recovery/reauth consumes checked generated DTOs | `pnpm --filter @keepling/web test --run src/features/auth/auth.test.tsx` | ❌ Planned — component test created by task; generated DTO exists from 01-06/01-07 | ✅ passed — full phase gate 2026-08-31 |
| 01-08-T2 | 01-08 | 6 | SRV-01, WEB-02 | T-KPL01-17 | Reachable setup/session administration and real auth interruption | `pnpm --filter @keepling/web test:e2e --grep @auth-recovery` | ❌ Planned — E2E file created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-09-T1 | 01-09 | 7 | GTD-02, SRV-03 | T-KPL01-18..20 | Touched-field edit, explicit Inbox clarification, and contract drift | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling/domain/edit_task_test.exs' && pnpm contracts:check` | ❌ Planned — server test/vector/contract created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-09-T2 | 01-09 | 7 | GTD-02, WEB-01, WEB-02 | T-KPL01-18..20 | Routed explicit-save editor preserves draft/focus/acknowledgement | `pnpm --filter @keepling/web test --run src/features/tasks/task-editor.test.tsx` | ❌ Planned — component test created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-10-T1 | 01-10 | 8 | GTD-02, SRV-03 | T-KPL01-21..22 | Stable-ID organization commands and collisions remain account-scoped | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling/domain/organization_test.exs' && pnpm contracts:check` | ❌ Planned — server test/vector/contract created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-10-T2 | 01-10 | 8 | GTD-02, WEB-02 | T-KPL01-21..22 | Assignment/management routes use IDs and accessible controls | `pnpm --filter @keepling/web test --run src/features/organizations/organization-fields.test.tsx` | ❌ Planned — component test created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-11-T1 | 01-11 | 9 | SRV-03, QUAL-01 | T-KPL01-23..24 | Atomic safe accepted activity, pagination, and contract drift | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling/application/activity_test.exs' && pnpm contracts:check` | ❌ Planned — server test/vector/contract created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-11-T2 | 01-11 | 9 | WEB-02 | T-KPL01-23..24 | Hostile activity renders as safe text with exact time/focus | `pnpm --filter @keepling/web test --run src/features/activity/activity-list.test.tsx` | ❌ Planned — component test created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-12-T1 | 01-12 | 10 | GTD-03, GTD-04 | T-KPL01-25..26 | Today intent/date truth across timezone/DST and contract drift | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling/domain/task_dates_test.exs' && pnpm contracts:check` | ❌ Planned — server test/vector/contract created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-12-T2 | 01-12 | 10 | GTD-02, GTD-03, WEB-02 | T-KPL01-25..26 | Capture/editor expose separate planned and deadline fields honestly | `pnpm --filter @keepling/web test --run src/features/tasks/task-editor.test.tsx` | ❌ Planned — existing focused test expanded by task | ✅ passed — full phase gate 2026-08-31 |
| 01-13-T1 | 01-13 | 11 | GTD-03, GTD-04 | T-KPL01-27..28 | Timezone views, cursor invalidation, and reorder race are deterministic | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling/adapters/postgres/task_views_test.exs' && pnpm contracts:check` | ❌ Planned — query test/contract created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-13-T2 | 01-13 | 11 | WEB-01, WEB-02 | T-KPL01-27..28 | Routed lists distinguish initial/background/stale and restore focus | `pnpm --filter @keepling/web test --run src/features/lists/task-lists.test.tsx` | ❌ Planned — component test created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-14-T1 | 01-14 | 12 | GTD-05, SRV-03 | T-KPL01-29..30 | Complete/reopen state machine is independently replay-safe | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling/application/task_lifecycle_test.exs' && pnpm contracts:check` | ❌ Planned — lifecycle test/vector/contract created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-14-T2 | 01-14 | 12 | GTD-05, WEB-01, WEB-02 | T-KPL01-29..30 | Acknowledged complete/reopen controls preserve row/focus truth | `pnpm --filter @keepling/web test --run src/features/tasks/lifecycle.test.tsx` | ❌ Planned — component test created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-15-T1 | 01-15 | 13 | GTD-06, SRV-03 | T-KPL01-31..32 | Trash/restore independently preserve all canonical state | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling/application/trash_restore_test.exs' && pnpm contracts:check` | ❌ Planned — preservation test/vector/contract created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-15-T2 | 01-15 | 13 | GTD-06, WEB-02 | T-KPL01-31..32 | Trash route removes only after acknowledged restore | `pnpm --filter @keepling/web test --run src/features/lists/trash-list.test.tsx` | ❌ Planned — component test created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-16-T1 | 01-16 | 14 | SRV-03, WEB-02 | T-KPL01-33..35 | Persisted conflict, replay, and account isolation are stable | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling/adapters/postgres/conflict_test.exs' && pnpm contracts:check` | ❌ Planned — conflict test/vector/contract created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-16-T2 | 01-16 | 14 | WEB-02 | T-KPL01-33..35 | Inline resolver preserves unaffected draft and accessible choices | `pnpm --filter @keepling/web test --run src/features/tasks/conflict-resolver.test.tsx` | ❌ Planned — component test created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-17-T1 | 01-17 | 15 | SRV-03, WEB-02 | T-KPL01-36 | Exact submission state preserves request bytes and identity | `pnpm --filter @keepling/web test --run src/commands/submission.test.ts` | ❌ Planned — state-machine test created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-17-T2 | 01-17 | 15 | SRV-03, WEB-02 | T-KPL01-36..37 | Before/after-commit loss recovers same identity; fault routes cannot ship | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling_web/test_fault_test.exs' && pnpm --filter @keepling/web test:e2e --grep @lifecycle-recovery` | ❌ Planned — fault/E2E tests created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-18-T1 | 01-18 | 16 | GTD-07, SRV-03 | T-KPL01-38..40 | Undo is owned, bounded, one-shot, exact-revision, and drift-checked | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling/application/undo_test.exs' && pnpm contracts:check` | ❌ Planned — undo test/vector/contract created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-18-T2 | 01-18 | 16 | GTD-07, WEB-02 | T-KPL01-38..40 | Persistent recovery exposes no raw handle and keeps native text undo | `pnpm --filter @keepling/web test --run src/features/recovery/recovery-strip.test.tsx` | ❌ Planned — component test created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-19-T1 | 01-19 | 17 | WEB-02, QUAL-01 | T-KPL01-41, T-KPL01-44 | Responsive semantic tokens, focus, themes, and motion contract | `pnpm --filter @keepling/web test --run src/test/ui-contract.test.tsx` | ❌ Planned — token output/component test created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-19-T2 | 01-19 | 17 | WEB-02, QUAL-01 | T-KPL01-41, T-KPL01-44 | Separate overflow and long-text visual/a11y evidence | `pnpm --filter @keepling/web test:e2e --grep @visual-contract` | ❌ Planned — visual E2E file created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-19-T3 | 01-19 | 17 | WEB-01, QUAL-01 | T-KPL01-41..44 | Targeted lifecycle, long-sequence, and telemetry evidence covers new tests | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling/domain/long_sequence_test.exs test/keepling/telemetry_redaction_test.exs' && pnpm --filter @keepling/web test:e2e --grep @phase1-lifecycle` | ❌ Planned — focused server/E2E files created by task | ✅ passed — full phase gate 2026-08-31 |
| 01-20-T1 | 01-20 | 18 | SRV-01, WEB-02, QUAL-01 | T-KPL01-G20-01..03 | Expired task-detail and activity reads resume exact route, draft, and cursor context through real authentication | `pnpm --filter @keepling/web test --run src/features/tasks/task-editor.test.tsx src/features/activity/activity-list.test.tsx && pnpm --filter @keepling/web test:e2e --grep @authenticated-read-task` | `task-editor.test.tsx`, `activity-list.test.tsx`, `authenticated-read-recovery.spec.ts` | ✅ passed — full phase gate 2026-08-31 |
| 01-20-T2 | 01-20 | 18 | SRV-01, WEB-02, QUAL-01 | T-KPL01-G20-01..03 | Assignment, Projects, and Tags reads recover their original task or organization context | `pnpm --filter @keepling/web test --run src/features/organizations/organization-fields.test.tsx && pnpm --filter @keepling/web test:e2e --grep @authenticated-read-organizations` | `organization-fields.test.tsx`, `authenticated-read-recovery.spec.ts` | ✅ passed — full phase gate 2026-08-31 |
| 01-20-T3 | 01-20 | 18 | SRV-01, WEB-02, QUAL-01 | T-KPL01-G20-01..03 | One credential rotation drains concurrent compatible continuations exactly once and keeps failures retryable | `pnpm --filter @keepling/web test --run src/features/auth/auth.test.tsx && pnpm --filter @keepling/web test:e2e --grep @authenticated-read-concurrent` | `auth.test.tsx`, `authenticated-read-recovery.spec.ts` | ✅ passed — full phase gate 2026-08-31 |
| 01-21-T1 | 01-21 | 18 | SRV-03, WEB-02, QUAL-01 | T-KPL01-G21-01..03 | A dispatched conflict choice is immutable while its exact result is nonterminal | `pnpm --filter @keepling/web test --run src/features/tasks/conflict-resolver.test.tsx` | `conflict-resolver.test.tsx` | ✅ passed — full phase gate 2026-08-31 |
| 01-21-T2 | 01-21 | 18 | SRV-03, WEB-02, QUAL-01 | T-KPL01-G21-01..03 | After-commit conflict response loss reconciles the original choice and mutation identity exactly once | `pnpm --filter @keepling/web test:e2e --grep @conflict-resolution-recovery` | `conflict-resolution-recovery.spec.ts` | ✅ passed — full phase gate 2026-08-31 |
| 01-22-T1 | 01-22 | 18 | GTD-03, SRV-03, WEB-02, QUAL-01 | T-KPL01-G22-01..03 | Every Today ordering control is globally locked while one exact move is unresolved | `pnpm --filter @keepling/web test --run src/features/lists/task-lists.test.tsx` | `task-lists.test.tsx` | ✅ passed — full phase gate 2026-08-31 |
| 01-22-T2 | 01-22 | 18 | GTD-03, SRV-03, WEB-02, QUAL-01 | T-KPL01-G22-01..03 | A committed Today move whose response is lost remains recoverable only by its original identity | `pnpm --filter @keepling/web test:e2e --grep @today-order-recovery` | `today-order-recovery.spec.ts` | ✅ passed — full phase gate 2026-08-31 |
| 01-23-T1 | 01-23 | 18 | SRV-01, SRV-03, WEB-02, QUAL-01 | T-KPL01-G23-01..05 | Uncertain rename, revoke, and logout reconcile authoritative inventory/authentication before definitive copy | `pnpm --filter @keepling/web test --run src/features/sessions/session-list.test.tsx` | `session-list.test.tsx` | ✅ passed — full phase gate 2026-08-31 |
| 01-23-T2 | 01-23 | 18 | SRV-01, SRV-03, WEB-02, QUAL-01 | T-KPL01-G23-01..05 | Real after-commit session response loss converges without replaying writes and remains test-only | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling_web/test_fault_test.exs' && pnpm --filter @keepling/web test:e2e --grep @session-reconciliation` | `test_fault_test.exs`, `session-reconciliation.spec.ts` | ✅ passed — full phase gate 2026-08-31 |
| 01-24-T1 | 01-24 | 19 | WEB-02, QUAL-01 | T-KPL01-41 | Endpoint CSP constrains executable resources while hostile task, activity, and conflict values remain inert text | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling_web/security_headers_test.exs' && pnpm --filter @keepling/web test --run src/test/security-content.test.tsx` | `security_headers_test.exs`, `security-content.test.tsx` | ✅ passed — full phase gate 2026-08-31 |
| 01-24-T2 | 01-24 | 19 | SRV-02, QUAL-01 | T-KPL01-28 | Every TaskViews PostgreSQL path consumes a finite timeout and maps cancellation to the stable content-free failure contract | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling/adapters/postgres/task_views_test.exs'` | `task_views_test.exs` | ✅ passed — full phase gate 2026-08-31 |
| 01-24-T3 | 01-24 | 19 | SRV-01, WEB-01, WEB-02, QUAL-01 | T-KPL01-G20-04 | Route-owned authentication continuations dispose on route change/unmount and fence late settlement without canceling live owners | `pnpm --filter @keepling/web test --run src/features/auth/auth.test.tsx && pnpm --filter @keepling/web typecheck` | `auth.test.tsx` | ✅ passed — full phase gate 2026-08-31 |
| 01-25-T1 | 01-25 | 20 | WEB-01, WEB-02, QUAL-01 | T-KPL01-25-01..03 | Narrow and compact-wide users reach every primary destination through a semantic keyboard-complete drawer | `pnpm --filter @keepling/web test --run src/test/ui-contract.test.tsx && pnpm --filter @keepling/web test:e2e --grep @responsive-route-matrix` | `ui-contract.test.tsx`, `responsive-route-matrix.spec.ts` | ✅ passed — full phase gate 2026-08-31 |
| 01-25-T2 | 01-25 | 20 | WEB-01, WEB-02, QUAL-01 | T-KPL01-25-02..03 | Tokenized 1024/1064 workspace boundaries preserve 360/480 panes, canonical routing, and independent scrolling | `pnpm --filter @keepling/web test --run src/test/ui-contract.test.tsx && pnpm --filter @keepling/web test:e2e --grep @responsive-route-matrix && pnpm --filter @keepling/web typecheck` | `ui-contract.test.tsx`, `responsive-route-matrix.spec.ts` | ✅ passed — full phase gate 2026-08-31 |
| 01-25-T3 | 01-25 | 20 | GTD-01..07, WEB-01, WEB-02, QUAL-01 | T-KPL01-25-01..03 | The authenticated route/viewport matrix proves landmarks, focus, scrolling, zero overflow, and axe results without claiming human perception | `pnpm --filter @keepling/web test:e2e --grep @responsive-route-matrix && pnpm --filter @keepling/web test --run src/test/ui-contract.test.tsx` | `responsive-route-matrix.spec.ts`, `ui-contract.test.tsx` | ✅ passed — full phase gate 2026-08-31 |
| 01-26-T1 | 01-26 | 21 | GTD-01, WEB-01, WEB-02 | T-KPL01-26-01..04 | Dirty navigation and capture reauthentication use exact copy, safe initial focus, Escape cancellation, and acknowledgement-gated identity retention | `pnpm --filter @keepling/web test --run src/features/tasks/task-editor.test.tsx && pnpm --filter @keepling/web test:e2e --grep @modal-keyboard` | `task-editor.test.tsx`, `modal-keyboard.spec.ts` | ✅ passed — full phase gate 2026-08-31 |
| 01-26-T2 | 01-26 | 21 | SRV-01, SRV-03, WEB-02 | T-KPL01-26-01..04 | Logout and session revocation use the shared consequential dialog, correct endpoint semantics, single-flight activation, and focus return | `pnpm --filter @keepling/web test --run src/features/sessions/session-list.test.tsx src/test/ui-contract.test.tsx && pnpm --filter @keepling/web test:e2e --grep @modal-keyboard` | `session-list.test.tsx`, `ui-contract.test.tsx`, `modal-keyboard.spec.ts` | ✅ passed — full phase gate 2026-08-31 |
| 01-26-T3 | 01-26 | 21 | WEB-02, QUAL-01 | T-KPL01-26-01..04 | Shared buttons, dialogs, and shell styling consume declared semantic tokens and 44px targets | `pnpm --filter @keepling/web test --run src/test/ui-contract.test.tsx && pnpm --filter @keepling/web lint && pnpm --filter @keepling/web typecheck` | `ui-contract.test.tsx` | ✅ passed — full phase gate 2026-08-31 |
| 01-27-T1 | 01-27 | 22 | SRV-01, WEB-02, QUAL-01 | T-KPL01-27-01..03 | Authentication surfaces use declared visual scales while retaining password-manager, recovery, and reauthentication semantics | `pnpm --filter @keepling/web test --run src/features/auth/auth.test.tsx src/test/ui-contract.test.tsx && pnpm --filter @keepling/web typecheck` | `auth.test.tsx`, `ui-contract.test.tsx` | ✅ passed — full phase gate 2026-08-31 |
| 01-27-T2 | 01-27 | 22 | GTD-01..07, WEB-01, WEB-02 | T-KPL01-27-01..03 | List, organization, and activity hierarchy stays token-compliant without changing focus, pagination, announcements, or text safety | `pnpm --filter @keepling/web test --run src/test/ui-contract.test.tsx && pnpm --filter @keepling/web typecheck` | `ui-contract.test.tsx` | ✅ passed — full phase gate 2026-08-31 |
| 01-27-T3 | 01-27 | 22 | WEB-01, WEB-02, QUAL-01 | T-KPL01-27-01..03 | Exhaustive production-TSX AST checks reject visual drift while conflict and uncertain-delivery state machines remain behaviorally green | `pnpm --filter @keepling/web test --run src/test/ui-contract.test.tsx && pnpm --filter @keepling/web test && pnpm --filter @keepling/web lint && pnpm --filter @keepling/web typecheck` | `ui-contract.test.tsx`, complete Vitest suite | ✅ passed — full phase gate 2026-08-31 |

## Post-Task / Phase Gate

After every task-level command above has passed, run `./tooling/test-phase-1.sh --run` once as the consolidated phase gate; it complements rather than replaces the targeted task commands.

## Fresh Final-Tree Automated Evidence — 2026-08-31 (`e866a22`)

| Boundary | Command | Result |
|---|---|---|
| Complete fail-fast phase gate | `./tooling/test-phase-1.sh --run` | Exit 0 at 2026-08-31T22:55-04:00: repository integrity, Elixir 1.20.2 / OTP 29.0.5 / PostgreSQL 18.6, fresh migrations, 109/109 ExUnit, production-route isolation, contract drift, TypeScript, 147/147 Vitest, and 25/25 Playwright |
| Plans 20–23 recovery E2E | Included in the complete gate | Authenticated reads, conflict choice, Today order, and session administration all passed against Phoenix/PostgreSQL |
| Review-fix route identity | Included in 147 Vitest tests | Deferred task A→B and Inbox→Today settlement-order regressions passed |
| Plans 24–27 hardening and UI closure | Included in the complete gate | CSP/content safety, real PostgreSQL cancellation, continuation disposal, responsive route matrix, modal keyboard behavior, and exhaustive TSX token contract passed |
| Test inventory | `rg --files` plus disabled-marker scan | 20 ExUnit files, 13 Vitest files, 11 Playwright files; zero skipped/disabled/only requirement tests found |
| Repository web lint | `pnpm lint:web` | Exit 0 after the complete phase gate |
| Overflow regression | Included in 25 Playwright tests | 1023/1024/1063/1064, light/dark, and 200% zoom geometry oracle passed |

The final-tree audit found no missing, partial, disabled, or failing automated requirement test. No test file was generated because the existing behavioral suites already prove every automated PLAN truth and requirement lane; adding a redundant test would not close a gap.

## Requirement Coverage

| Requirement | Source Plans | Automated Boundary | Status |
|---|---|---|---|
| GTD-01 | 05, 19, 25–27 | Capture idempotency + real-stack skeleton/lifecycle + responsive/consequential UI contracts | ✅ covered |
| GTD-02 | 09, 10, 12, 19, 25, 27 | Edit, organization, date domain/component/E2E + exhaustive UI contract | ✅ covered |
| GTD-03 | 12, 13, 19, 22, 25, 27 | Today date/order projections + after-commit recovery + routed UI contract | ✅ covered |
| GTD-04 | 12, 13, 19, 25, 27 | Account-timezone Today/Upcoming projections + routed UI contract | ✅ covered |
| GTD-05 | 14, 19, 25, 27 | Complete/reopen application, UI, real-stack lifecycle, and route matrix | ✅ covered |
| GTD-06 | 15, 19, 25, 27 | Durable Trash/restore preservation + routed UI | ✅ covered |
| GTD-07 | 18, 19, 25, 27 | Revision-aware one-shot undo race + recovery/routed UI | ✅ covered |
| SRV-01 | 05–08, 17, 19, 20, 23–24 | Closed account/session authority, auth recovery, reconciliation, and continuation disposal | ✅ covered for Phase 1 |
| SRV-02 | 02–06, 09–19, 24 | Shared semantic boundary, PostgreSQL, Phoenix, contracts, CSP, and bounded reads | ✅ covered for Phase 1 |
| SRV-03 | 05–07, 09–23, 26 | Stable receipts, conflict/ordering/session uncertainty, and exact consequential UI | ✅ covered |
| WEB-01 | 04–05, 09, 13–14, 17, 19, 24–27 | Real browser daily loop plus hardened responsive route/modal coverage | ✅ covered |
| WEB-02 | 04, 08–27 | Loading/empty/error/auth/conflict/retry/focus/reflow/content/modal/token states | ✅ automated coverage and UAT mapping passed |
| QUAL-01 | 01–07, 11, 16–27 | Integrity, migrations, privacy, production isolation, all test layers, security/UI drift gates | ✅ automated coverage and UAT mapping passed |

## Validation Audit 2026-08-31

| Metric | Count |
|---|---:|
| Plans mapped | 27/27 |
| Completed summaries audited | 27/27 |
| Plan tasks with automated commands | 60/60 |
| Phase requirements with automated coverage | 13/13 |
| Automated gaps found | 0 |
| Tests generated | 0 |
| Automated UAT checkpoints | 3/3 |
| Required human UAT items | 0 |

## Wave 0 Requirements and Ordering

- [x] Plan 01-01 resolves package legitimacy before any flagged install.
- [x] Plan 01-01 creates and passes `tooling/runtime-preflight.sh` for Elixir 1.20.2 / OTP 29.0.5 / PostgreSQL 18.6 while leaving `.tool-versions` unchanged.
- [x] Plan 01-02 creates every Mix/core/config output including `mix.lock`, all environment configs, `Keepling`, Application, and Repo.
- [x] Plan 01-02 pins and locks Hammer 7.4.1; Plan 01-07 owns the app-defined ETS limiter and adds it to `Keepling.Application` supervision.
- [x] Plan 01-03 creates `KeeplingWeb`, Endpoint, router, telemetry, seeds, `test_helper.exs`, DataCase, ConnCase, Clock, and ConcurrencyCase before Plan 01-05 uses them.
- [x] Plan 01-04 creates Vitest config/setup before any component test command.
- [x] Plan 01-04 creates Playwright config/stack orchestration before the tracer E2E command.
- [x] Plan 01-04 creates OpenAPI generation/drift and native root scripts before later contract/full-suite commands.
- [x] Plan 01-06 proves setup-token singleton races and account timezone ownership before auth UI or date projections consume them.
- [x] Plan 01-07 proves limiter application startup, forced-child restart/reuse, and setup/login/recovery account/source bucket isolation before auth UI consumes those endpoints.
- [x] No test command references a file/config/helper created in the same or a later task before its creation step.

## Automated UAT Contracts

| Behavior | Requirement | Status | Evidence marker |
|---|---|---|---|
| Accessibility semantics, keyboard continuity, focus recovery, and exact state announcements | WEB-02, QUAL-01 | passed | `@uat-accessibility` |
| Reflow, themes, zoom, forced colors, motion, long text, and zero page overflow | WEB-02, QUAL-01 | passed | `@uat-reflow` |
| Password-manager-compatible inputs, one-use recovery, and exact authentication continuation | SRV-01, WEB-02 | passed | `@uat-auth-interop` |

Real VoiceOver listening quality, subjective visual taste, and particular third-party password-manager extensions are optional dogfood observations, not Phase 1 acceptance gates.

## Validation Sign-Off

- [x] Every task has an automated verify and no watch flags.
- [x] Wave 0 prerequisites execute before dependent verification.
- [x] Narrow feedback is measured below 30 seconds or split further.
- [x] Real PostgreSQL proves concurrency and before/after-commit loss.
- [x] All three Phase 1 UAT contracts are mapped to executable component/integration/E2E evidence and the coverage checker passed.
- [x] `nyquist_compliant: true` and `wave_0_complete: true` are supported by the fresh full phase gate.

**Approval:** automated evidence and all three UAT mappings passed; zero human UAT is required for Phase 1 acceptance
