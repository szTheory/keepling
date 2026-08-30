---
phase: 1
slug: one-trustworthy-task
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-30
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
- Before verification: run `./tooling/test-phase-1.sh` plus end-of-phase human checks.
- Missing/unavailable PostgreSQL or browser evidence is `human_needed`/blocked, never a pass.

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Automated Command | Status |
|---|---|---:|---|---|---|---|---|
| 01-02-T2 | 01-02 | 1 | SRV-02 | T-KPL01-03 | Inward semantic boundary and independent connections exist first | `cd apps/server && mix test test/architecture_test.exs` | ⬜ pending |
| 01-03-T1 | 01-03 | 1 | WEB-01, WEB-02 | T-KPL01-04 | Vitest and real-stack Playwright configs load before feature use | `pnpm --filter @keepling/web test --run --passWithNoTests && pnpm --filter @keepling/web exec playwright test --list` | ⬜ pending |
| 01-04-T2 | 01-04 | 2 | GTD-01, SRV-03 | T-KPL01-08 | Concurrent replay yields one stable capture | `cd apps/server && mix test test/keepling/adapters/postgres/idempotency_test.exs` | ⬜ pending |
| 01-05-T1 | 01-05 | 3 | SRV-01 | T-KPL01-11..14 | Closed auth/recovery/session lifecycle and isolation | `cd apps/server && mix test test/keepling_web/auth_test.exs` | ⬜ pending |
| 01-06-T2 | 01-06 | 4 | SRV-01, WEB-02 | T-KPL01-15..17 | Reachable login/recovery/session UI and auth interruption | `pnpm --filter @keepling/web test:e2e --grep @auth-recovery` | ⬜ pending |
| 01-07-T1 | 01-07 | 5 | GTD-02 | T-KPL01-18..20 | Touched-field edit and clarification | `cd apps/server && mix test test/keepling/domain/edit_task_test.exs` | ⬜ pending |
| 01-08-T1 | 01-08 | 6 | GTD-02 | T-KPL01-21..22 | Stable-ID organization and collisions | `cd apps/server && mix test test/keepling/domain/organization_test.exs` | ⬜ pending |
| 01-09-T1 | 01-09 | 7 | SRV-03 | T-KPL01-23..24 | Atomic safe accepted activity | `cd apps/server && mix test test/keepling/application/activity_test.exs` | ⬜ pending |
| 01-10-T1 | 01-10 | 8 | GTD-03 | T-KPL01-25..26 | Today intent/date truth across DST | `cd apps/server && mix test test/keepling/domain/task_dates_test.exs` | ⬜ pending |
| 01-11-T1 | 01-11 | 9 | GTD-04 | T-KPL01-27..28 | Timezone views, cursor invalidation, reorder race | `cd apps/server && mix test test/keepling/adapters/postgres/task_views_test.exs` | ⬜ pending |
| 01-12-T1 | 01-12 | 10 | GTD-05 | T-KPL01-29..30 | Complete/reopen independently classified and replay-safe | `cd apps/server && mix test test/keepling/application/task_lifecycle_test.exs` | ⬜ pending |
| 01-13-T1 | 01-13 | 11 | GTD-06 | T-KPL01-31..32 | Trash/restore independently preserve canonical state | `cd apps/server && mix test test/keepling/application/trash_restore_test.exs` | ⬜ pending |
| 01-14-T1 | 01-14 | 12 | SRV-03, WEB-02 | T-KPL01-33..35 | Persisted conflict and account isolation | `cd apps/server && mix test test/keepling/adapters/postgres/conflict_test.exs` | ⬜ pending |
| 01-15-T2 | 01-15 | 13 | SRV-03, WEB-02 | T-KPL01-36..37 | Before/after-commit loss recovers same identity | `pnpm --filter @keepling/web test:e2e --grep @lifecycle-recovery` | ⬜ pending |
| 01-16-T1 | 01-16 | 14 | GTD-07 | T-KPL01-38..40 | Undo owned, bounded, one-shot, exact revision | `cd apps/server && mix test test/keepling/application/undo_test.exs` | ⬜ pending |
| 01-17-T2 | 01-17 | 15 | WEB-02 | T-KPL01-41 | Separate overflow and long-text visual/a11y evidence | `pnpm --filter @keepling/web test:e2e --grep @visual-contract` | ⬜ pending |
| 01-17-T3 | 01-17 | 15 | WEB-01, QUAL-01 | T-KPL01-41..44 | Full lifecycle, sequences, telemetry, and threat gate | `./tooling/test-phase-1.sh` | ⬜ pending |

## Wave 0 Requirements and Ordering

- [ ] Plan 01-01 resolves package legitimacy before any flagged install.
- [ ] Plan 01-02 creates `test_helper.exs`, DataCase, ConnCase, Clock, and ConcurrencyCase before Plan 01-04 uses them.
- [ ] Plan 01-03 creates Vitest config/setup before any component test command.
- [ ] Plan 01-03 creates Playwright config/stack orchestration before the tracer E2E command.
- [ ] Plan 01-03 creates OpenAPI generation/drift and native root scripts before later contract/full-suite commands.
- [ ] No test command references a file/config/helper created in the same or a later task before its creation step.

## Manual-Only Verifications

| Behavior | Requirement | Instructions |
|---|---|---|
| Screen-reader announcements and focus recovery across capture, validation, conflict, auth expiry, uncertain delivery, pagination, lifecycle, undo, sessions | WEB-02, QUAL-01 | Use VoiceOver and keyboard; record route/state, expected/actual announcement, and final focus. |
| Reflow, themes, zoom, forced colors, motion | WEB-02, QUAL-01 | Review 320/768/1024/1440, light/dark, 200% zoom, forced colors, Reduce Motion with deterministic fixtures. |
| Password manager and recovery trust | SRV-01, WEB-02 | Verify paste, AutoFill, reveal, one-use recovery, and both auth-expiry timings without secret disclosure. |

## Validation Sign-Off

- [ ] Every task has an automated verify and no watch flags.
- [ ] Wave 0 prerequisites execute before dependent verification.
- [ ] Narrow feedback is measured below 30 seconds or split further.
- [ ] Real PostgreSQL proves concurrency and before/after-commit loss.
- [ ] Visual, keyboard, VoiceOver, reflow, forced-colors, and Reduce Motion evidence is recorded.
- [ ] `nyquist_compliant: true` and `wave_0_complete: true` are set only from fresh passing evidence.

**Approval:** pending
