---
phase: 1
slug: one-trustworthy-task
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-30
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit + StreamData; Ecto SQL Sandbox against real PostgreSQL; Vitest + Testing Library; Playwright + axe |
| **Config file** | `apps/server/test/test_helper.exs`, `apps/web/vitest.config.ts`, and `apps/web/playwright.config.ts` — all installed in Wave 0 |
| **Quick run command** | `cd apps/server && mix test --max-failures 1` or `pnpm --filter @keepling/web test --run` for the boundary changed by the task |
| **Full suite command** | `cd apps/server && mix test && cd ../.. && pnpm contracts:check && pnpm --filter @keepling/web test --run && pnpm --filter @keepling/web test:e2e` |
| **Estimated runtime** | To be measured after Wave 0; targeted task checks must remain below 30 seconds |

---

## Sampling Rate

- **After every task commit:** Run the narrow ExUnit test file/directory or Vitest file covering the changed behavior.
- **After every plan wave:** Run the complete server and web unit suites, contract drift checks, and Playwright `@smoke` against real PostgreSQL.
- **Before `$gsd-verify-work`:** Full server, contract, web, and browser suites must be green; visual and accessibility evidence must be reviewed.
- **Max feedback latency:** 30 seconds for task-level checks; measure and record full-suite duration during Wave 0.

---

## Per-Task Verification Map

Plan and task identifiers are assigned by the planner. The behavior-to-command mapping below is mandatory input to those plans.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| TBD | TBD | 0+ | GTD-01 | T-01 / T-03 | Stable identity and exactly-once capture under replay | domain + integration | `cd apps/server && mix test test/keepling/application/capture_task_test.exs` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0+ | GTD-02 | T-02 / T-03 | Closed touched-field edits preserve unrelated fields and validation failures preserve drafts | domain + component | `cd apps/server && mix test test/keepling/domain/edit_task_test.exs` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0+ | GTD-03 | T-02 | Today intent remains independent from deadline semantics | domain vectors | `cd apps/server && mix test test/keepling/domain/task_dates_test.exs` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0+ | GTD-04 | T-02 | Timezone and DST boundaries produce stable Today and Upcoming results | query integration | `cd apps/server && mix test test/keepling/adapters/postgres/task_views_test.exs` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0+ | GTD-05 | T-02 / T-03 | Complete and reopen are idempotent, revision-aware transitions | domain + integration | `cd apps/server && mix test test/keepling/application/task_lifecycle_test.exs` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0+ | GTD-06 | T-02 / T-03 | Trash and restore retain fields and history without hard deletion | domain + integration | `cd apps/server && mix test test/keepling/application/trash_restore_test.exs` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0+ | GTD-07 | T-02 / T-03 | Undo is owned, bounded, one-shot, revision-aware, and replay-safe | domain + integration | `cd apps/server && mix test test/keepling/application/undo_test.exs` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0+ | SRV-01 | T-01 / T-04 / T-05 | Closed setup, hashed sessions, CSRF/origin protection, expiry, revocation, recovery, and account isolation | ConnCase + integration + E2E | `cd apps/server && mix test test/keepling_web/auth_test.exs` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0+ | SRV-02 | T-02 / T-06 | HTTP reaches the same semantic application command boundary without adapter bypass | architecture + contract | `cd apps/server && mix test test/architecture_test.exs` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0+ | SRV-03 | T-02 / T-03 | Duplicate, mismatched, concurrent, rejected, and response-loss mutations have stable outcomes | PostgreSQL concurrency + fault injection | `cd apps/server && mix test test/keepling/adapters/postgres/idempotency_test.exs` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0+ | WEB-01 | T-01 / T-02 / T-03 | Authenticated browser performs the full lifecycle against Phoenix and PostgreSQL | Playwright system | `pnpm --filter @keepling/web test:e2e --grep @smoke` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0+ | WEB-02 | T-01 / T-03 / T-04 | Empty, loading, validation, auth-expired, stale, conflict, retry, and uncertain-delivery states preserve intent and focus | component + E2E | `pnpm --filter @keepling/web test --run` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0+ | QUAL-01 | T-01..T-06 | Long sequences, concurrency, persistence, contract, browser, accessibility, and telemetry boundaries have deterministic proof | all layers | `cd apps/server && mix test && cd ../.. && pnpm contracts:check && pnpm --filter @keepling/web test --run && pnpm --filter @keepling/web test:e2e` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

Threat references are provisional planning labels. The planner must replace or align them with each PLAN.md `<threat_model>` block.

---

## Wave 0 Requirements

- [ ] `apps/server/test/test_helper.exs` and support cases — ExUnit, SQL Sandbox, deterministic clock/ID generators, and independent-connection concurrency helpers.
- [ ] `apps/server/test/keepling/**` and `apps/server/test/keepling_web/**` — initial domain, application, persistence, authentication, HTTP, architecture, and telemetry-redaction test scaffolds.
- [ ] `packages/contracts/` — OpenAPI 3.1 source, JSON schemas, golden vectors, TypeScript generation, and drift check.
- [ ] `apps/web/vitest.config.ts` and `apps/web/src/test/setup.ts` — Vitest, Testing Library, jsdom, and accessible interaction helpers.
- [ ] `apps/web/playwright.config.ts` — real Phoenix/PostgreSQL orchestration, deterministic seeded data, response-loss/fault control, trace, screenshot, and axe evidence.
- [ ] Root scripts coordinate native Mix and pnpm commands without Nx or Turborepo.
- [ ] Measure task-check and full-suite runtimes; replace the estimates above with observed values.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Screen-reader announcements and focus recovery across capture, row removal, validation, conflict, authentication expiry, and uncertain delivery | WEB-02, QUAL-01 | Automated accessibility rules cannot prove announcement timing, reading order, or restored focus quality | Exercise the approved UI-SPEC flows with VoiceOver and keyboard-only input; record route, state, expected announcement, actual announcement, and restored focus target. |
| Reflow, zoom, forced colors, reduced motion, and representative responsive states | WEB-02, QUAL-01 | Visual snapshots do not establish usability or platform accessibility behavior | Review 320, 768, 1024, and 1440px at light/dark, 200% zoom, forced colors, and Reduce Motion using deterministic fixtures for populated, empty, long-content, conflict, auth-expired, and uncertain-delivery states. |
| Authentication recovery preserves dirty drafts without ambiguous replay | SRV-01, WEB-02 | Automated coverage is required, but final interaction trust and recovery copy need human judgment | Expire a session before submission and after an accepted-but-response-lost mutation; reauthenticate and verify the draft, mutation identity, state language, and final outcome remain intelligible and correct. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or explicit Wave 0 dependencies.
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify.
- [ ] Wave 0 covers all missing references.
- [ ] No watch-mode flags.
- [ ] Task-level feedback latency is below 30 seconds.
- [ ] Real PostgreSQL tests prove concurrency and before/after-commit response loss.
- [ ] Visual, keyboard, VoiceOver, reflow, forced-colors, and Reduce Motion evidence is recorded.
- [ ] `nyquist_compliant: true` is set in frontmatter after validation.

**Approval:** pending
