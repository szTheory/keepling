---
schema_version: 1
open_count: 28
waived_count: 50
fixed_count: 16
closed_count: 1
total_count: 95
last_updated: 2026-09-12T04:30:00.000Z
---

# Broken Windows Ledger

> Cross-phase defect register. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at | owner |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------| ------- |
| 1 | 01 | deviation | apps/web/playwright.config.ts |  | Playwright 1.62 required a harness contract so pre-feature --list discovery exits successfully | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T01:19:02.196Z | 2026-09-03T23:50:04.775Z | 01 |
| 2 | 01 | deviation | package.json |  | openapi-typescript 7.13.0 required a root-only TypeScript 5.9.3 peer alongside the web TypeScript 6 toolchain | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T01:19:02.274Z | 2026-09-03T23:50:04.865Z | 01 |
| 3 | 01 | deviation | apps/web/e2e/support/stack.ts |  | Disposable trust-auth PostgreSQL now rejects every non-loopback bind | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T01:19:02.349Z | 2026-09-03T23:50:04.953Z | 01 |
| 4 | KPL-01 | deviation | apps/server/priv/repo/migrations/.formatter.exs |  | Retained the Phoenix generator migration formatter marker so the planned Mix test alias can run before migrations exist | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T01:31:44.014Z | 2026-09-03T23:50:05.039Z | KPL-01 |
| 5 | KPL-01 | deviation | apps/server/test/architecture_test.exs |  | Corrected architecture-test formatting found by the plan-level Mix formatter gate | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T01:31:44.083Z | 2026-09-03T23:50:05.124Z | KPL-01 |
| 6 | KPL-01 | deviation | apps/web/e2e/support/stack.ts |  | Made the real-stack E2E lifecycle executable before RED | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T02:10:59.290Z | 2026-09-03T23:50:05.208Z | KPL-01 |
| 7 | KPL-01 | deviation | apps/server/priv/repo/seeds.exs |  | Added an explicitly test-only closed-account seed | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T02:10:59.359Z | 2026-09-03T23:50:05.293Z | KPL-01 |
| 8 | KPL-01 | deviation | apps/web/src/index.css |  | Applied the approved accessible capture baseline | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T02:10:59.428Z | 2026-09-03T23:50:05.380Z | KPL-01 |
| 9 | KPL-01 | deviation | apps/server/lib/keepling/adapters/postgres/command_store.ex |  | Corrected double-encoded JSONB terminal results | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T02:10:59.498Z | 2026-09-03T23:50:05.467Z | KPL-01 |
| 10 | KPL-01 | deviation | apps/server/mix.exs |  | Added exact reviewed Argon2id and Tzdata dependencies required by the planned setup contract | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T02:33:05.090Z | 2026-09-03T23:50:05.554Z | KPL-01 |
| 11 | KPL-01 | deviation | apps/server/priv/repo/migrations/20260830000200_add_closed_setup_and_timezone.exs |  | Bound setup TTL and enforced permanent disablement plus future account credential/timezone fields | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T02:33:05.162Z | 2026-09-03T23:50:05.640Z | KPL-01 |
| 12 | KPL-01 | deviation | apps/server/config/config.exs |  | Disabled Tzdata remote updater to close the vulnerable transitive HTTP path | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T02:33:05.234Z | 2026-09-03T23:50:05.726Z | KPL-01 |
| 13 | KPL-01 | deviation | apps/web/src/App.tsx |  | Wired Inbox route reachability and exact acknowledgement reconciliation omitted from the plan file list | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T03:57:58.529Z | 2026-09-03T23:50:05.816Z | KPL-01 |
| 14 | KPL-01 | deviation | apps/server/lib/keepling/domain/task.ex |  | Added canonical nullable planned_on and deadline_on aggregate fields omitted from the plan file list | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T05:18:34.955Z | 2026-09-03T23:50:05.905Z | KPL-01 |
| 15 | KPL-01 | deviation | apps/server/priv/repo/migrations/20260830000650_add_task_view_projections.exs |  | Added durable projection schema and relevant command-store revision advancement omitted from the plan file list | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T05:48:12.063Z | 2026-09-03T23:50:05.993Z | KPL-01 |
| 16 | KPL-01 | deviation | apps/web/src/App.tsx |  | Wired authenticated shell list reachability and scoped the resulting legacy test ambiguity | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T05:48:12.168Z | 2026-09-03T23:50:06.084Z | KPL-01 |
| 17 | KPL-01 | deviation | apps/server/lib/keepling/application/task_views.ex |  | Removed an Ecto UUID dependency from the persistence-neutral application boundary | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T05:48:12.271Z | 2026-09-03T23:50:06.173Z | KPL-01 |
| 18 | KPL-01 | deviation | apps/server/priv/repo/migrations/20260830000650_add_task_view_projections.exs |  | Added exact Today move receipts and honest ambiguous-delivery retry after final trust review | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T05:48:12.377Z | 2026-09-03T23:50:06.259Z | KPL-01 |
| 19 | KPL-01 | deviation | apps/web/src/commands/submission.ts |  | Added explicit direct same-ID retry semantics required by lifecycle recovery | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T14:01:34.378Z | 2026-09-03T23:50:06.345Z | KPL-01 |
| 20 | KPL-01 | deviation | apps/web/src/commands/submission.ts |  | Classified infrastructure 5xx as unknown delivery rather than terminal rejection | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T14:01:34.472Z | 2026-09-03T23:50:06.437Z | KPL-01 |
| 21 | KPL-01 | deviation | apps/server/lib/keepling_web/controllers/test_fault_controller.ex |  | Halted authentication-before-acceptance injection before command dispatch | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T14:01:34.566Z | 2026-09-03T23:50:06.531Z | KPL-01 |
| 22 | KPL-01 | deviation | apps/web/src/index.css |  | Resolved the 1024px wide-shell overflow seam with a compact list column | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T16:02:33.525Z | 2026-09-03T23:50:06.625Z | KPL-01 |
| 23 | KPL-01 | deviation | apps/web/src/features/tasks/TaskEditor.tsx |  | Reconciled mounted editor state immediately after semantic undo acknowledgement | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T16:02:33.629Z | 2026-09-03T23:50:06.713Z | KPL-01 |
| 24 | KPL-01 | deviation | tooling/test-phase-1.sh |  | Pinned disposable migration, compile, and ExUnit lanes to MIX_ENV=test | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T16:02:33.734Z | 2026-09-03T23:50:06.801Z | KPL-01 |
| 25 | KPL-01 | lint-warning | apps/web/src/features/lists/TaskList.tsx | 190 | Pre-existing react-hooks/set-state-in-effect lint violation in TaskList | fixed |  | 2026-08-31T22:38:58.822Z | 2026-09-01T02:23:20.832Z | KPL-01 |
| 26 | KPL-01 | lint-warning | apps/web/src/features/lists/TrashList.tsx | 91 | Pre-existing react-hooks/set-state-in-effect lint violation in TrashList | fixed |  | 2026-08-31T22:38:58.894Z | 2026-09-01T02:23:20.907Z | KPL-01 |
| 27 | KPL-01 | unmet-truth | apps/web/e2e/lifecycle-recovery.spec.ts | 422 | Session revocation remains visible after recent-authentication recovery in the full Phase 1 gate | fixed |  | 2026-09-01T01:37:57.347Z | 2026-09-01T01:42:08.820Z | KPL-01 |
| 28 | KPL-01 | lint-warning | apps/web/src/app/AuthProvider.tsx | 259 | Repository ESLint fast-refresh export violation predates Plan 25 | fixed |  | 2026-09-01T01:37:57.421Z | 2026-09-01T02:23:20.983Z | KPL-01 |
| 29 | KPL-01 | deviation | apps/web/src/test/ui-contract.test.tsx |  | Exhaustive production-tree gate required mechanical scale closure outside the ten initially listed feature files. | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T02:22:51.183Z | 2026-09-03T23:50:06.901Z | KPL-01 |
| 30 | KPL-01 | deviation | apps/web/src/app/AuthProvider.tsx |  | Plan-required repository lint gate required scoped ownership directives for pre-existing findings. | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T02:22:51.264Z | 2026-09-03T23:50:06.998Z | KPL-01 |
| 31 | KPL-02 | deviation | apps/server/lib/keepling/application/sync/reference_model.ex |  | Corrected invalid Elixir string-literal typespec discovered during Task 1 compilation | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T05:55:08.453Z | 2026-09-03T23:50:07.084Z | KPL-02 |
| 32 | KPL-02 | deviation | apps/server/lib/keepling/application/sync/reference_model.ex |  | Bound immutable command bytes to the outer durable mutation identity | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T05:55:08.534Z | 2026-09-03T23:50:07.170Z | KPL-02 |
| 33 | KPL-02 | deviation | apps/server/lib/keepling/accounts/security_audit.ex |  | Extended the closed security-audit vocabulary for bounded device-grant facts | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T06:19:46.697Z | 2026-09-03T23:50:07.256Z | KPL-02 |
| 34 | KPL-02 | deviation | apps/server/lib/keepling/accounts/device_grant.ex |  | Made repeated refresh replay fencing idempotent after the first generation advance | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T06:19:46.778Z | 2026-09-03T23:50:07.342Z | KPL-02 |
| 35 | KPL-02 | deviation | apps/server/lib/keepling/accounts/device_grant.ex |  | Rejected extra public-client secret and namespace assertion fields | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T06:19:46.857Z | 2026-09-03T23:50:07.426Z | KPL-02 |
| 36 | KPL-02 | deviation | apps/server/lib/keepling/application.ex |  | Compatibility configuration is validated before application supervision starts | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T07:13:47.287Z | 2026-09-03T23:50:07.515Z | KPL-02 |
| 37 | KPL-02 | deviation | tooling/check-contracts.mjs |  | Compatibility contract gate rejects vacuous or malformed skew evidence | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T07:13:47.399Z | 2026-09-03T23:50:07.607Z | KPL-02 |
| 38 | KPL-02 | deviation | tooling/test-compatibility.sh |  | Migration count probe uses explicit PostgreSQL inputs and numeric output isolation | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T07:13:47.518Z | 2026-09-03T23:50:07.692Z | KPL-02 |
| 39 | KPL-02 | deviation | infra/caddy/Caddyfile |  | Preserved local HTTP proof without disabling production HTTPS automation | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T08:35:49.662Z | 2026-09-03T23:50:07.780Z | KPL-02 |
| 40 | KPL-02 | deviation | tooling/verify-deploy.sh |  | Emitted the setup capability from the running release node | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T08:35:49.770Z | 2026-09-03T23:50:07.867Z | KPL-02 |
| 41 | KPL-02 | deviation | tooling/verify-deploy.sh |  | Matched the established direct task-read response contract | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T08:35:49.877Z | 2026-09-03T23:50:07.955Z | KPL-02 |
| 42 | KPL-02 | deviation | tooling/test-phase-2.sh |  | Corrected the Phase 2 sync lane to digest the tracked canonical sync vector | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-02T03:18:29.294Z | 2026-09-03T23:50:08.046Z | KPL-02 |
| 43 | KPL-02 | unrun-verify | .planning/phases/KPL-02-synchronization-and-replaceable-server/deferred-items.md |  | Credentialed corrected restore/runtime and DNS cutover/rollback outer acceptance remains explicitly non-passing | open |  | 2026-09-02T03:18:34.980Z |  | BACKLOG/999.2 |
| 44 | KPL-03 | deviation | .npmrc |  | Forge required a hoisted pnpm linker and regenerated lock graph | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-02T18:23:00.601Z | 2026-09-03T23:50:08.133Z | KPL-03 |
| 45 | KPL-03 | deviation | apps/desktop/forge.config.ts |  | Forge packaging was restricted to bundled runtime assets | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-02T18:23:00.686Z | 2026-09-03T23:50:08.219Z | KPL-03 |
| 46 | KPL-03 | deviation | tooling/package-desktop.mjs |  | External app copying required verbatim framework symlinks | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-02T18:23:00.770Z | 2026-09-03T23:50:08.308Z | KPL-03 |
| 47 | KPL-03 | deviation | apps/desktop/main/index.ts |  | Packaged process resources required direct Resources paths | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-02T18:23:00.852Z | 2026-09-03T23:50:08.396Z | KPL-03 |
| 48 | KPL-03 | deviation | apps/desktop/main/index.ts |  | Same-profile ownership required an explicit Electron single-instance lock | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-02T18:23:00.938Z | 2026-09-03T23:50:08.482Z | KPL-03 |
| 49 | KPL-03 | deviation | packages/contracts/openapi/keepling.yaml |  | Approved additive native-token namespace response expansion resolved in plan 03-02 | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-02T18:54:39.314Z | 2026-09-03T23:50:08.569Z | KPL-03 |
| 50 | KPL-03 | deviation | apps/desktop/migrations/0001_initial.sql |  | Persisted storage-neutral synchronization metadata required for relaunch-safe lane replay | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-02T18:55:07.249Z | 2026-09-03T23:50:08.653Z | KPL-03 |
| 51 | KPL-03 | deviation | apps/desktop/tsconfig.json |  | Allowed type-only repository-owned generated contract imports in desktop typechecking | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-02T18:55:07.362Z | 2026-09-03T23:50:08.740Z | KPL-03 |
| 52 | KPL-03 | deviation | apps/desktop/main/adapters/credentials.ts |  | Loaded Electron safeStorage lazily so injected adapter proof runs outside Electron | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-02T18:55:07.476Z | 2026-09-03T23:50:08.827Z | KPL-03 |
| 53 | KPL-03 | deviation | apps/desktop/main/adapters/credentials.ts |  | Added unsigned dogfood credential continuity disclosure for Settings presentation | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-02T18:55:07.591Z | 2026-09-03T23:50:08.912Z | KPL-03 |
| 54 | KPL-03 | deviation | apps/desktop/main/adapters/credentials.ts |  | 03-13: pane-size persistence (D-06) is N/A -- no resizable-pane UI exists in the shared Workspace presentation to size or restore; documented decision, not a stub. | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-03T01:41:18.549Z | 2026-09-03T23:50:09.007Z | KPL-03 |
| 55 | KPL-03 | unrun-verify | tooling/verify-desktop-phase.mjs |  | macos-integration lane cases=0 at 03-17 HEAD: recorded row evidence is bound to the packaged applicationDigestSha256 and 03-17 changed main/index.ts. Re-record with: pnpm package:desktop && node tooling/verify-macos-integration.mjs --all (O-27) | fixed |  | 2026-09-03T20:47:11.732Z | 2026-09-03T23:49:58.264Z | KPL-03 |
| 56 | KPL-03 | unmet-truth | apps/desktop/vitest.config.ts |  | vitest 'worker' project declares include test/worker/** but that directory does not exist; the empty lane is invisible in a full run (O-26) | fixed |  | 2026-09-03T20:47:11.845Z | 2026-09-03T23:49:58.349Z | KPL-03 |
| 57 | KPL-03 | unmet-truth | apps/desktop/store-worker/local-store.ts |  | A locally REFUSED change has no durable home: the refused command is terminal and leaves the outbox, so the next applyPull replays the canonical shadow and the person's version is lost -- while the authored copy says "Your version is still on this Mac." (O-43). Do NOT resolve by keeping refused commands queued. | open |  | 2026-09-04T04:12:07.673Z |  | KPL-03 |
| 58 | KPL-03 | unmet-truth | packages/web-ui/src/tasks/ConflictResolver.tsx |  | The desktop conflict chooser is title-only, so a lifecycle/Trash conflict reaches a person as copy plus a refresh but with no mine/current choice; apps/web already has the multi-field resolver (O-44) | open |  | 2026-09-04T04:12:07.673Z |  | KPL-03 |
| 59 | KPL-03 | unmet-truth | apps/desktop/main/application/DesktopApplication.ts |  | undoLastLocalAction reverses a local change and enqueues NO outbound command, so an undo is invisible to the server -- the same defect class as O-41, needing server-issued undo handles the client does not retain (O-45) | fixed | CLOSED 2026-09-11 (06-01): verified against source, not merely carried forward. `DesktopApplication.ts` lines 466-517 document and implement O-45's real fix -- `undoLastLocalAction` now retains the server-issued undo handle from acknowledgements and reconciles through it (`POST /commands/undo-task`), refusing loudly rather than silently when no handle exists yet or the handle has expired. This row was stale; the code has been fixed since. | 2026-09-04T04:12:07.673Z | 2026-09-11T00:00:00.000Z | KPL-03 |
| 60 | KPL-03 | unmet-truth | apps/desktop/main/application/presentation.ts |  | { kind: preparing } has authored copy and no production construction site; the real site is a first-run bootstrap branch (KeeplingSyncAdapter.bootstrap() is called from nowhere). Reported for a recorded decision, deliberately not wired speculatively and not deleted (O-46) | open |  | 2026-09-04T04:12:07.673Z |  | KPL-03 |
| 61 | KPL-03 | unmet-truth | apps/desktop/main/application/presentation.ts |  | { kind: uncertain } and its check_again action have authored copy and no production construction site; constructing it honestly needs the transport to distinguish "never left" from "left, answer lost". Reported for a recorded decision, deliberately not wired speculatively and not deleted (O-47) | open |  | 2026-09-04T04:12:07.673Z |  | KPL-03 |
| 62 | KPL-04 | unmet-truth | tooling/verify-real-stack-ios.mjs |  | The server-driven half of D-22 Criterion 2 (auth expiry, account fencing, duplicate replay, structured conflict) could not run on a physical iPhone: KeeplingSyncAdapter refuses any non-HTTPS base URL whose host is not 127.0.0.1/localhost, and over TLS URLSession rejected the lane's self-signed certificate. CLOSED 2026-09-08 (04-18) WITHOUT widening the production transport guard and WITHOUT the planned DEBUG-only lane CA: `tailscale cert` serves the proxy from a MagicDNS name under a real Let's Encrypt certificate, so the phone validates it through the shipping transport and no test-only trust code exists on any configuration. Lane `server-driven-device` PASS cases=4. | fixed |  | 2026-09-07T04:03:27.449Z | 2026-09-08T21:00:00.000Z | KPL-04 |
| 63 | KPL-04 | skipped-test | apps/ios/Tests/StorageTests/DataProtectionTests.swift |  | Gate G7's locked-device write is unverified: no programmatic lock control exists (devicectl has no lock verb, XCUIDevice is UI-testing-only, and DataProtectionTests is a unit bundle). UPDATED 2026-09-08 (04-18): the compounding half is GONE -- the device now has a passcode set (`devicectl device info lockState` reports passcodeRequired: true, recorded by resolve-devices.mjs), and the protection class is proven enforceable on hardware. Only the lock-control half remains open, and closing it would mean adding a production protectedDataWillBecomeUnavailable write hook solely to make a gate pass. | open |  | 2026-09-07T04:03:27.539Z |  | BACKLOG |
| 64 | KPL-04 | unmet-truth | apps/ios/Tests/StorageTests/Fixtures/migration-1.sqlite |  | The storage lane opened its committed SQLite fixtures IN PLACE and mutated them. SEVERITY WAS UNDERSTATED: the note said only the FIRST run on a fresh checkout tested a pre-migration database, but the mutated migration-1.sqlite was itself COMMITTED (at [1,2] in ada909e, then at [1,2,3] in 624f9f3), and FixtureFactory.ensureMigration1Fixture() returns early when the file exists -- so testMigration1FixtureMigratesForwardToVersion2PreservingVersion1Row asserted [1,2,3] against an already-migrated file on EVERY checkout, migrating nothing. FIXED 2026-09-08 (04-18): every consumer now opens a writable per-run COPY (FixtureFactory.writableCopy, carrying the -wal/-shm siblings), and migration-1.sqlite was regenerated at version 1 only. Verified: the fixture is byte-identical after a full storage-lane run, the working tree stays clean, and storage/storage-gates/durability-posture all pass. | fixed |  | 2026-09-07T04:33:11.054Z | 2026-09-08T22:30:00.000Z | KPL-04 |
| 65 | KPL-04 | unmet-truth | tooling/verify-ios-phase.mjs |  | The gate published fewer cases than it ran: `xcodebuildSummary` took the LAST "Executed N tests" line, which for a lane spanning two test bundles is the last BUNDLE's total, not the run's. auth published 4 of 19, undo 8 of 18, sync-presentation 21 of 35, device 26 of 29 -- the published 424/454 totals understated by ~42. Never a false PASS (a failure in any bundle fails the lane however the line is parsed), but D-24's anti-vacuity contract rests on that number meaning what it says, and on `device` the discarded bundle was `DataProtectionTests`, so G7's protection-class hardware evidence contributed ZERO to the published count. FIXED 2026-09-09 (04-18): anchor on the `<Bundle>.xctest` summary line (exactly one per bundle), sum per-bundle totals, subtract skips, and fail when any single bundle executed zero. Verified: auth 19, undo 18, sync-presentation 35, device 29; corrected totals 463 simulator and 496 overall. Found by phase verification, not by a lane. | fixed |  | 2026-09-09T02:00:00.000Z | 2026-09-09T02:30:00.000Z | KPL-04 |
| 66 | KPL-05 | unmet-truth | apps/server/lib/keepling_web/router.ex | 121 | Browser cannot list or revoke agent grants: GET/DELETE /api/v1/device-grants sit behind the bearer-only :device_grant_authenticated pipeline, so a session-cookie request 401s and apps/web/e2e/agent-access.spec.ts fails at line 250 (step 5). Steps 1-4 pass, so this does NOT implicate MCP-01..05's text. Note apps/server/test/keepling_web/device_grant_controller_test.exs deliberately ASSERTS the 401 ("bearer boundary ... ignores browser cookies") while apps/web/src/api/keepling.ts:600 calls the same route with cookies -- two plans in one phase encoding opposite intentions for the endpoint; each one's unit tests pass and only the e2e crossing both catches it. CORRECTED 2026-09-10: this entry previously said moving the routes to :client_authenticated WOULD INTRODUCE an escalation letting any device grant, including an MCP agent, enumerate and revoke the owner's grants. The causality was inverted -- that escalation is already present in the committed pipeline (see window #70), because :device_grant_authenticated accepts an mcp grant today. So this is the third face of one decision, not an independent item: fix #70's missing client_kind refusal, and settle grant administration as owner-session-authenticated at the same time. Recommended shape: leave /api/v1/device-grants bearer-only exactly as tested and add a SEPARATE owner-session route (:authenticated, plus :mutation on the delete) for grant management, re-pointing the web client at it -- this weakens no existing assertion and adds no new path for an agent to reach the owner's grants. | fixed |  | 2026-09-10T23:42:06.351Z | 2026-09-11T02:13:45.161Z | KPL-05 |
| 67 | KPL-05 | unmet-truth | .planning/phases/KPL-05-safe-agent-access |  | Phase KPL-05 has ROADMAP 'UI hint: yes' and shipped frontend in 05-09 (AgentGrantList.tsx, ActivityList.tsx, /settings/agents route) with no UI-SPEC.md. The ui.safety-gate blocks on this (block = frontend && hasUiFiles && !hasUiSpec); it intermittently reads false only because hasUiFiles is computed from git diff HEAD~1..HEAD, a documented single-commit limitation. Resolve with /gsd-ui-review before phase completion. | fixed |  | 2026-09-10T23:42:13.957Z | 2026-09-11T04:13:38.031Z | KPL-05 |
| 68 | KPL-05 | skipped-test | apps/web/e2e/authenticated-read-recovery.spec.ts | 154 | Flaky under the full 26-test Playwright run: '@authenticated-read-organizations restores assignment, Projects, and Tags routes' intermittently times out at 30s waiting for getByLabel('New project name'), with the page still showing Inbox -- the pushState+popstate navigation to /projects does not take. Observed failing in 2 of 4 full-suite runs during KPL-05; passes every time in isolation (1.3s) and passes when run immediately after the failing agent-access spec, so it is neither a code regression nor simple ordering interference. Route matching in routes.tsx is correctly ordered (/projects at line 340 precedes /settings/agents at 364). Suspect a race between the popstate dispatch and the app's location read under full-suite load. | open |  | 2026-09-11T00:17:48.787Z |  | KPL-05 |
| 69 | 05 | unrun-verify | tooling/cross-adapter/legs.mjs |  | Cross-adapter lane (05-12): electron and iphone legs BLOCKED because neither has a live DRIVER wired yet -- not because their artifacts are missing. The packaged Electron build does exist at apps/desktop/out (that path is gitignored, so it is invisible from an isolated worktree, which is why 05-12 reported it absent); the Keepling app is installed on the booted simulator. runElectronLeg() needs a live IPC driver against the packaged .app (mirror apps/desktop/test/real-stack/real-stack-sync.spec.ts); runIphoneLeg() needs a live UI/recording-proxy driver against the installed app (mirror tooling/verify-real-stack-ios.mjs). web-api and mcp legs PASS with identical result_code/conflict_shape/activity_fact/final_revision across all 4 shared scenarios. SRV-02 stays unchecked pending both legs. | fixed | 06-05: both drivers wired and live. tooling/cross-adapter/electron-driver.mjs drives the packaged Mac app's real task-list UI via Playwright; tooling/cross-adapter/iphone-driver.mjs drives the real Swift KeeplingSyncAdapter (two new methods on the existing ServerDrivenTests.swift test target) via xcodebuild test-without-building. pnpm verify:cross-adapter now reports legs_total=4 legs_ran=4 legs_blocked=0 legs_failed=0 comparison_ok=true. A real cross-client contract bug (ConflictField.field's OpenAPI enum missing completed_at/trashed_at) was found and fixed en route. SRV-02 is checked. | 2026-09-11T01:31:52.629Z | 2026-09-11T20:15:00.000Z | Phase 6 |
| 70 | 05 | unmet-truth | apps/server/lib/keepling_web/auth.ex | 117 | PRIVILEGE ESCALATION, confirmed by live probe and by reading: an MCP agent credential reaches surfaces the MCP adapter does not front. KeeplingWeb.MCP.Pipeline (mcp/pipeline.ex:34) refuses a grant whose client_kind != "mcp"; KeeplingWeb.Auth.authenticate_device_grant/1 (auth.ex:117-149) performs no mirror-image refusal -- it assigns current_client_kind and never checks it. That pipeline fronts GET /api/v1/sync, GET /api/v1/sync/bootstrap, and GET+DELETE /api/v1/device-grants (router.ex:120-127). SyncController has no client_kind check; DeviceGrantController.list/2 and revoke/2 check neither client_kind nor scope. Probed with a grant scoped ["tasks.read"] only: GET /api/v1/sync/bootstrap -> 200 with full account content, GET /api/v1/device-grants -> 200 listing all installations, DELETE /api/v1/device-grants/<other> -> 200 device_grant_revoked, after which the victim grant 401s on /mcp/v1. So an agent reads the entire account around the bounded/paginated/redacted read surface that 05-03/05-04 built, and can revoke the owner's iPhone or desktop. AGGRAVATOR: the harness depends on the hole -- tooling/mcp-client/final-state.mjs:68-78 reads the grant list with a device-grant bearer and asserts 200, so the green simulated-client lane rests on the escalation it should catch; closing the hole breaks that lane and it must be re-pointed at the owner session. ROOT BLIND SPOT: every lane tests for under-delivery (agent denied something it should get); none tests over-delivery (agent reaching a surface the adapter does not front). Needs adversarial negative cases on all four routes. Found by gsd-verifier during KPL-05 phase verification; see VERIFICATION.md. | fixed |  | 2026-09-11T01:52:56.106Z | 2026-09-11T02:13:45.033Z | 05 |
| 71 | 05 | unmet-truth | apps/server/config/test.exs | 18 | The Elixir suite has an implicit LOGIN BUDGET and no guard on it. config/test.exs caps the login rate-limit bucket per 5-minute window; every test that calls a login helper spends from one shared seeded-account bucket. 05-13 added server tests that each sign in, which pushed the suite past the old cap of 50 and emptied the bucket mid-run. auth_controller.ex:59 maps {:error, :rate_limited, _} to the same 401 authentication_failed a wrong password returns -- correct for a caller, who must not learn whether they are throttled or wrong, but it means an exhausted bucket is INDISTINGUISHABLE from a credential failure in a test log. The four tests that failed (KeeplingWeb.MCP.ToolsTest x3, KeeplingWeb.MCP.ErrorsTest x1) had nothing to do with the change that caused it; they were simply the ones that ran after the bucket emptied, and the executor that added the tests reported the suite green. Raised 50 -> 400 in KPL-05-13 follow-up (test config only; the production abuse policy in that block is deliberately untouched), so headroom is now roughly 8x rather than 1.06x. The failure mode is not closed, only deferred: the next plan that adds sign-ins hits the same wall and it will again surface as an authentication failure in an unrelated test. Worth either asserting the login count against the cap in the suite, or making the test-env rate limiter emit a distinguishable error so a throttled login cannot be mistaken for a bad credential. | open |  | 2026-09-11T02:22:01.221Z |  | 05 |
| 72 | 05 | unmet-truth | apps/server/lib/keepling_web/auth.ex | 147 | SECOND, LARGER ESCALATION -- scope half of the same boundary, confirmed by re-verification probe and by reading. A credential's authority is client_kind X scope. KPL-05-13 made client_kind default-deny on :device_grant_authenticated; scope outside /mcp/v1 is not merely unchecked, it is NOT CARRIED: authenticate_device_grant/1 assigns current_client_kind and never assigns current_scope, so the 19 shared /api/v1/commands/* endpoints could not check it if they tried. CommandController contains no reference to scope. Keepling.Application.AgentScope calls itself 'the authoritative, application-boundary scope gate' so that 'a bug in the adapter alone cannot widen what an agent grant may do', yet all its call sites are inside lib/keepling_web/mcp/. Probed with real PKCE grants: a tasks.read-only grant POSTed /api/v1/commands/capture-task -> 201 persisted, and /api/v1/commands/trash-task -> 200 with the owner's read then returning 404; the same token at /mcp/v1 is refused insufficient_scope. Mirror: a tasks.write-only grant GET /api/v1/search and /api/v1/projects -> 200. The agent reaches all 19 shared commands, ~15 of which the MCP tool set deliberately never exposes (trash, restore, undo, resolve-conflict, plan-for-today, move-today, five org commands). THE :client_authenticated CARVE-OUT IS NOT DEFENSIBLE: auth.ex:147 justifies it as 'scope-checked and bounded' -- bounded is true, scope-checked is impossible because the scope is not in the conn; D-09 (05-CONTEXT.md:102) requires shared application-level QUERIES, which MCP.Resources already satisfies by calling Keepling.Application.Search in-process, and says nothing about which credential classes an HTTP route admits; and the carve-out's stated cost is not real -- mcp/resources.ex and mcp/tools.ex make no HTTP calls, final-state.mjs uses the owner session, and the cross-adapter web-api leg posts with session cookie + CSRF, so no consumer was found. PRE-EXISTING, not introduced by 05-13, and it invalidates the earlier CHECK of MCP-02 (least-privilege scopes). Fix is either refusing mcp on :client_authenticated/:client_mutation, or carrying current_scope and enforcing it in CommandController -- plus scope over-delivery cases in the adversarial lane, mutation-tested the way 05-13 mutation-tested the kind ones. | fixed |  | 2026-09-11T02:34:24.731Z | 2026-09-11T04:13:00.585Z | 05 |
| 73 | 05 | unmet-truth | apps/server/lib/keepling_web/auth.ex | 200 | Receipt scope inversion, found by third-pass probe. agent_authority("GET", ["api","v1","mutations",_id]) maps to tasks.write, documented as 'the receipt moves WITH the write: readable by the authority that could have issued it' (D-49). The rationale is coherent for an idempotency receipt, but it is enforced at the CLASS level, not the INSTANCE level: a tasks.write-only grant read the receipt of a mutation issued by the OWNER'S BROWSER SESSION -- 200 with the full task snapshot including title -- while a tasks.read grant is refused 403 on the same route. So the scope that conveys reading cannot read, and the scope that conveys writing reads another client's result. Severity WARNING, not blocker, and MCP-02 was checked over it: mutation ids are client-chosen UUIDv4, no agent-reachable surface discloses another client's mutation id, and an unknown id answers 404, so the receipt is not enumerable -- an agent must already know the id. Two candidate fixes: require tasks.read IN ADDITION to tasks.write on that route, or bind a receipt to the grant that issued the mutation so 'could have issued it' means this credential rather than this credential class. The second is the one that matches the comment's own wording. | open |  | 2026-09-11T03:16:33.943Z |  | 05 |
| 74 | 05 | deviation | apps/server/lib/keepling_web/auth.ex | 147 | DECISION RECORD OWED: RFC 8707 resource-audience scope of an mcp grant. An mcp grant is audience-bound to the MCP resource URI, and that audience is enforced only by KeeplingWeb.MCP.Pipeline; presenting the same grant at /api/v1 is therefore arguably an audience violation independent of scope. Third-pass verification ruled this a DESIGN QUESTION, not a defect, on the following grounds: same origin, same endpoint, same authorization server, one singleton account, and since 05-14 the HTTP authority is a default-deny mirror of the closed MCP tool set -- so the token buys nothing at /api/v1 that it does not already buy at /mcp/v1. Recorded rather than silently accepted because the cost of the other choice is specific and worth knowing before anyone revisits it: enforcing the audience at /api/v1 would invert apps/server/test/keepling/application/projects_test.exs:85 (the deliberate D-09 byte-identity assertion across browser session, electron bearer and mcp bearer), delete Keepling.Application.AgentScope's only call site outside lib/keepling_web/mcp/ and thereby reopen window #72's adapter-locality problem, and make the DeviceBearer abstraction false for one of three credential classes. If strict RFC 8707 conformance is wanted later, the recommended direction is to WIDEN THE DECLARED RESOURCE rather than narrow the credential. | waived | 06-11: recorded as decision D-013 in `.planning/knowledge/DECISIONS.md` -- an RFC 8707 audience check at `:client_authenticated` would buy no reduction in actual authority given this repository's single origin, single authorization server, and single account, and would invert the deliberate D-09 byte-identity assertion. Not a defect; closed by decision, not by an implementation change. | 2026-09-11T03:16:34.067Z | 2026-09-11T21:30:00.000Z | 05 |
| 75 | 05 | unmet-truth | .planning/REQUIREMENTS.md | 21 | gsd-tools phase complete marks the WRONG requirement boxes for this project, and it has now done so twice on the same box. Running 'phase complete 05' checked SRV-02 -- whose own inline comment reads 'This box stays unchecked until both legs pass', whose cross-adapter electron and iphone legs are still BLOCKED on unwired drivers (window #69), and which third-pass verification explicitly recommended DEFER -- while leaving MCP-01..05 unchecked despite all five being recommended CHECK at 5/5. Exactly backwards. The first occurrence is recorded in the D-28 note on that same line, so this is a repeat, not a one-off. CAUSE is structural and will recur for every phase in this project: .planning/REQUIREMENTS.md's Traceability table carries GROUPED rows ('MCP-01..05, SRV-02 and cross-adapter completion \| Phase 5 \| ...') rather than one row per REQ-ID, so the tool's per-ID row matcher finds nothing for any individual ID and falls back to the ROADMAP citation -- which names SRV-02 for Phase 5 and therefore checks it. The tool DISCLOSED this rather than hiding it, in two warnings on the same run: '39 REQ-ID(s) found in body but missing from Traceability table' and 'Traceability row write skipped for REQ-ID(s) cited by ROADMAP (no matching row found): SRV-02'. Corrected by hand for Phase 5. Until the Traceability table carries one row per REQ-ID, DO NOT trust phase complete's requirement marking -- diff .planning/REQUIREMENTS.md after every phase completion and correct it against the phase's VERIFICATION.md. | open |  | 2026-09-11T03:18:17.153Z |  | 05 |
| 76 | 05 | unmet-truth | apps/server/lib/keepling_web/controllers/device_grant_controller.ex | 167 | CONSENT UI CANNOT SHOW WHAT IT IS FOR: KeeplingWeb.DeviceGrantController.grant_response/1 (device_grant_controller.ex:167-175) publishes only client_kind, generation, id, installation_id, label, revoked. It does NOT publish scope, authorized_at, or last_used_at. /settings/agents (AgentGrantList.tsx) is the screen where the user decides whether an AI agent still gets to read and write their tasks, and the two facts that should drive that decision -- what this agent may do, and when it last did anything -- are unavailable there today; all three fields render 'Not yet reported' for every agent. Found by the retroactive UI audit (05-UI-REVIEW.md, Pillar 6). AGGRAVATOR FOUND AND FIXED IN THE SAME AUDIT: apps/web/src/api/keepling.ts mapped 'scope: grant.scope ?? []', collapsing 'the server did not report a scope list' into 'this grant holds no scopes', so AgentGrantList.tsx rendered 'No scopes granted' for EVERY agent -- a false claim of zero permissions, on consent UI, about grants that really held tasks.read/tasks.write. Fixed by preserving null through the mapping and rendering 'Not yet reported', with a mutation-tested case in agent-grant-list.test.tsx ('reports an omitted scope list as unreported, never as holding no scopes'); reverting the mapping kills that test. The remaining work is server-side and needs both halves: publish the three fields from Keepling.Accounts.DeviceGrant, and widen DeviceGrantSummary in packages/contracts/openapi/keepling.yaml so the generated TS stops being stale (keepling.ts:47-66 documents the widening it had to do locally). No frontend rework is needed after that -- the component reads all three defensively already. NOTE the distinction the fix preserves and the server must respect: an absent scope key means UNKNOWN, an empty array means GENUINELY NO SCOPES; they are opposite claims on this screen and must not be collapsed again. | open |  | 2026-09-11T04:13:26.978Z |  | 05 |
| 77 | 05 | deviation | .planning/ROADMAP.md |  | PROCEDURE, generalized from window #67 (now closed by 05-UI-REVIEW.md): a phase whose ROADMAP entry carries a UI hint must get a UI-SPEC.md BEFORE execution, not a retroactive audit after it. The audit showed the absence had a concrete cost, not a paperwork one: with no design contract, the question 'what should an agent row show, and what should it say when it does not know' was never settled before the code was written, and the answer got decided by a '?? []' default in a wire mapper -- which is how consent UI came to tell the user, falsely, that every authorized agent held no scopes. A UI-SPEC would have had to answer the empty/unknown-state question explicitly, because that is one of the seven dimensions gsd-ui-checker validates. ALSO NOTE, for whoever runs the next retroactive audit: this one's original top finding was FALSE at CRITICAL severity -- it reported that /settings/agents was non-functional because the endpoints reject session cookies, which was true when 05-09-SUMMARY.md was written and was closed by 05-13 (window #66, owner-session routes at router.ex:146 and :152, which the web client already calls at keepling.ts:600,616). The auditor read the phase's own summaries as current state. Summaries are history; the tree is state. Audit the tree. | open |  | 2026-09-11T04:13:44.809Z |  | 05 |
| 78 | 06 | unmet-truth | apps/desktop/renderer/DesktopShell.tsx | 53 | Class: data-loss. Keyboard command dispatch bypasses the unsaved-changes guard: `new-task`, `go-inbox` and `go-today` in `DesktopShell.tsx`'s command-dispatch effect call `facade.setRoute` DIRECTLY, while every mouse-driven navigation (nav links, task selection) in `packages/web-ui/src/workspace/Workspace.tsx` routes through `attemptNavigation`, which asks the person before discarding a dirty editor's unsaved edits. Filed as O-22 (`.planning/STATE.md` Blockers). A person mid-edit who presses Cmd-1/Cmd-2/Cmd-N loses the in-progress edit with no dialog, no warning, and no recovery -- a silent data-loss defect in the supported daily keyboard loop MAC-02 names explicitly. Fix belongs in the keyboard dispatch effect: route these three cases through the same `attemptNavigation` guard mouse navigation already uses, not a parallel bypass. | fixed | 06-09: `DesktopShell.tsx`'s `new-task`/`go-inbox`/`go-today` keyboard commands now call `workspaceRef.current?.guardedSetRoute(...)` instead of `facade.setRoute(...)` directly, routing through the same dirty-state guard mouse navigation already used. Proven against the real shipped Electron app in `apps/desktop/test/e2e/guarded-navigation.spec.ts` (7/7 cases). | 2026-09-11T18:00:00.000Z | 2026-09-11T21:30:00.000Z | Phase 6 |
| 79 | 06 | deviation | tooling/generate-known-limitations.mjs |  | `gsd-tools windows` (`fixed`/`waive`/`append`) cannot currently write to this repository's `.planning/WINDOWS.md`: every write attempt errors "Ledger table region could not be located ... refusing to write", apparently because this file's rendered markdown table carries an `owner` column (added by plan 06-01) that the tool's canonical fenced JSON block has no matching field for, so the tool cannot reconcile the two representations to safely rewrite either. Row #78 was found stale during 06-11 (already fixed by 06-09, still marked open here) and had to be corrected by hand-editing both the JSON block and the rendered table directly, exactly as the tool's own refusal message instructs ("Edit the fenced JSON block directly -- the sole source of truth"), because the sanctioned CLI path is unavailable. This should be repaired (either by adding `owner` to the canonical JSON schema, or by removing it from the rendered table) before the next plan needs to mark a row fixed or waived. | open |  | 2026-09-11T21:30:00.000Z |  | 06-11 |
| 80 | 06 | deviation | .github/workflows/desktop.yml |  | DECISION DEFERRED BY THE OWNER (2026-09-11): server OCI image signing is not implemented, and this is a recorded decision rather than an oversight. Plan 06-10 Task 3 was to `cosign` the server image's pushed digest, but NOTHING IN THIS REPOSITORY BUILDS OR PUSHES THAT IMAGE TO ANY REGISTRY, so there is no digest to sign. `06-RESEARCH.md` Pattern 5 names the gap itself ("Registry: GHCR or wherever image is pushed") and never resolves it. The owner was asked directly during the 06-10 checkpoint and chose to defer rather than have a registry guessed at: adding a build-and-push pipeline is new infrastructure, well outside 06-10's declared `files_modified`, and picking a registry is a decision with cost, retention and access consequences that outlive this phase. TO CLOSE: decide where the server image is published and what triggers a push, then add the build+push pipeline and sign the resulting digest. Everything else in 06-10 Task 3 (job-scoped `id-token`/`attestations` permissions, `attest-build-provenance`, exact-Level-2 claim discipline, the checksum release-body template) IS implemented and passing, so this is the single remaining piece of that task. Until it is closed, no supply-chain document may claim the server image is signed. | open |  | 2026-09-11T23:15:00.000Z |  | BACKLOG |
| 81 | 06 | unmet-truth | docs/security/SUPPLY-CHAIN.md | 40 | Class: overclaim. docs/security/SUPPLY-CHAIN.md section 2 states in the present tense that "The self-hosted server's container image is signed keylessly, by digest, using the GitHub Actions workflow's own OIDC identity (Sigstore/cosign)." IT IS NOT. Window #80 records that server OCI image signing was deferred by the owner because nothing in this repository builds or pushes that image to any registry, and window #80's own closing sentence states the rule this violates: "Until it is closed, no supply-chain document may claim the server image is signed." The claim predates 06-10 Task 2 (it landed in commit bb43580 with Task 4) and lives outside Task 2's declared file scope, so 06-10 Task 2 reported it rather than editing it inline. This repository is headed for a public Apache-2.0 release and this is a public-facing trust document, so a false present-tense control claim is the exact overclaim class this phase spent three plans refusing elsewhere. TO CLOSE: reword section 2's image-signing paragraph to future/conditional form naming window #80 as the blocker, or close window #80 and make the sentence true. | closed |  | 2026-09-12T02:30:00.000Z |  | BACKLOG |
| 82 | 06 | unmet-truth | tooling/verify-package-reproducibility.mjs |  | Class: gate-regression. tooling/verify-desktop-phase.mjs's package-reproducible lane FAILS as of plan 06-10 Task 2, taking the desktop phase gate from 10/11 to 9/11. Two separate builds at one clean revision now differ in 16 of 618 compared entries, and the 16 are exactly the signature-bearing ones: every signed Mach-O (Electron Framework, all four helpers, Contents/MacOS/Keepling, the bundled dylibs) plus both _CodeSignature/CodeResources files. The other 602 entries are byte-identical, so the PAYLOAD is still reproducible; the SIGNATURES are not, and cannot be: @electron/osx-sign signs with --timestamp, embedding a fresh RFC 3161 secure timestamp from Apple's timestamp authority into every signature blob, and a secure timestamp is REQUIRED for notarization. A signed build is not byte-reproducible by construction. TO CLOSE, pick one deliberately: (a) have the lane invoke packaging with KEEPLING_MACOS_SKIP_SIGNING=1 (the escape hatch already exists in forge.config.ts and tooling/package-desktop.mjs), so it keeps asserting byte-identical builds and stops asserting byte-identical signatures; or (b) keep signing on and assert the narrower true thing -- every non-signature entry identical AND the differing set exactly the signature-bearing set -- which needs a real signature-blob classifier, not a path allowlist. WHAT MUST NOT HAPPEN is relaxing the existing comparison to ignore these 16 paths and calling the lane green; that is the loosened-binding trap the 06-10 Task 1 checkpoint exists to refuse, and it would silently stop noticing a genuine payload change inside a signed binary. | open |  | 2026-09-12T02:45:00.000Z |  | BACKLOG |
| 83 | 06 | unmet-truth | tooling/verify-export-reader.mjs |  | Class: unwired-lane. The independent export reader exists and runs locally, but NO committed workflow job under .github/ invokes it. `tooling/verify-export-reader.mjs` is referenced only by SUPPORT.md, PRIVACY.md and itself; a prior revision of `tooling/release-lanes.json` claimed repository-integrity.yml/ci-contract runs it and no such step exists. An unwired lane may never report PASSED because it has no job it could have passed in, so `.planning/releases/candidate-1/release-manifest.json` records `export-reader` as BLOCKED with a zero case count. This matters beyond bookkeeping: DATA-01 asserts a person can export all their data in a versioned, documented, neutral format without internal database knowledge, and the public PRIVACY.md leans on the reader as the evidence that the export is genuinely readable without Keepling. Both currently rest on a lane no continuous-integration run has ever executed. TO CLOSE: add a job to .github/workflows/repository-integrity.yml running `node tooling/verify-export-reader.mjs --golden`, add `export-reader` to the required-lane list in tooling/check-ci-contract.mjs, and re-run the release manifest at the resulting revision. | open |  | 2026-09-12T04:10:00.000Z |  | BACKLOG |
| 84 | 06 | unrun-verify | tooling/verify-macos-integration.mjs |  | Class: physical-blocker. macOS integration row A14 (Light and Dark change while the app is open) cannot run on a hosted GitHub runner, and this is now an OBSERVED boundary rather than a prediction. A14 is the only row that changes a system appearance setting WHILE the application is already running and asserts the window re-themes without a relaunch; delivering that change to a running process needs a logged-in Aqua session whose appearance daemon posts AppleInterfaceThemeChangedNotification, which a hosted runner has not got. Measured both ways at revision 26628e1: `ROW id=A14 status=FAIL cases=4` on macos-15 with `background stayed` an all-zero colour (run 34668212473, job desktop-macos-integration), and `status=PASS cases=4` on a real logged-in session. Rows A10, A12 and A13 pass on the same runner because each applies its setting BEFORE launch. The row has been split out as the `macos-integration-live-appearance` lane, authority local-attested with a stated physical blocker, and emits an explicit zero-case BLOCKED entry into every release manifest rather than disappearing. It is NOT a product defect and must not be recorded as one. TO CLOSE with continuous-integration authority: run the row on a self-hosted macOS runner with a real logged-in session, against the exact continuous-integration-built bytes. | open |  | 2026-09-12T04:10:00.000Z |  | BACKLOG |
| 85 | 06 | unmet-truth | tooling/test-phase-2.sh |  | Class: privacy-gate-failure. The `phase2-server` lane FAILS its mandatory post-run privacy scan at revision 26628e1. The lane's own command succeeded (`mix compile --warnings-as-errors && mix test`), and then `./tooling/verify-privacy.sh` over the lane's diagnostic log reported `hostile sentinel found in a diagnostic artifact` and the job exited non-zero (run 34668212479). Because no PASS line was emitted, no case count from that lane may be claimed, and the `export-elixir` lane -- whose evidence IS that job -- is BLOCKED with it. The cause is NOT yet isolated. It may well be a test-fixture literal appearing in ExUnit output rather than a product leak: `apps/server/test/keepling_web/mcp/content_isolation_test.exs` is the only server test outside the two redaction suites that uses a vector sentinel, and it uses them as in-test literals. But probably-benign is not a standard this project accepts from a privacy gate, and the same scan passes on every other lane. QUAL-05 stays checked on the strength of the `phase2-privacy` lane, which PASSED with 17 cases at this revision, and carries a dated addendum naming this row so the claim can never be cited without it. TO CLOSE: reproduce with `./tooling/test-phase-2.sh --lane server`, identify the emitter, and either stop it emitting or record why the appearance is not a leak. | open |  | 2026-09-12T04:10:00.000Z |  | BACKLOG |
| 86 | 06 | unmet-truth | apps/server/mix.lock |  | Class: vulnerable-dependency. The `image-compose-deploy` lane FAILS at revision 26628e1 because the server image build's dependency audit reports hackney 1.25.0 as VULNERABLE with four open advisories: EEF-CVE-2026-47071 (HIGH, SOCKS5 TLS upgrade ignores caller timeout), EEF-CVE-2026-47075 (MEDIUM, CR/LF injection in query parameter), EEF-CVE-2026-47076 (MEDIUM, SSRF allowlist bypass via percent-encoded host) and EEF-CVE-2026-47069 (LOW, CRLF injection in cookie domain and path options). This is a real supply-chain finding in the bytes the self-hosted server image would ship, not an infrastructure fault, and it is one of the two failures that keep the `all-required-passed` aggregator red. The audit firing is the control working. TO CLOSE: raise the hackney dependency (directly, or via whichever parent pulls it in) to a version carrying no open advisory, then re-run `./tooling/test-phase-2.sh --lane image-compose-deploy`. | open |  | 2026-09-12T04:10:00.000Z |  | BACKLOG |
| 87 | 06 | unmet-truth | .github/workflows/repository-integrity.yml |  | Class: ci-provisioning-defect. The `Install asdf` step is not idempotent against its own cache, so the `phase2-sync-property` and `phase2-backup-restore` jobs never reach their lanes. The step runs `git clone https://github.com/asdf-vm/asdf.git "$HOME/.asdf" --branch v0.14.1` unconditionally, but an earlier `actions/cache` restore of `~/.asdf/installs` has already created `$HOME/.asdf`, so the clone dies with `fatal: destination path '/home/runner/.asdf' already exists and is not an empty directory` and exit 128. Observed at revision 26628e1 in run 34668212479 for both jobs. This is toolchain provisioning failing before any project code runs; neither lane's result says anything about the product, and both are recorded as BLOCKED with this reason rather than as failures. It is also one of the two causes -- via phase2-linux -- that keep the `all-required-passed` aggregator red, and so it is part of what keeps QUAL-02 unchecked. TO CLOSE: make the step a no-op when `$HOME/.asdf/.git` already exists (or restore the cache after the clone), and re-run both lanes. | open |  | 2026-09-12T04:10:00.000Z |  | BACKLOG |
| 88 | 06 | unrun-verify | .github/workflows/desktop.yml |  | Class: unproven-clause. QUAL-03's second clause -- distribution jobs do not silently rebuild different bytes -- still has NO passing lane behind it, and this is now a tested absence rather than an untested one. The 2026-09-04 disclosure on QUAL-03 said clause 2 was unproven only because no workflow had ever executed and that Phase 6 must re-verify it against a real remote before any release claim. Phase 6 now has a real remote, and at revision 26628e1 the `desktop-promote` job was SKIPPED: its `needs` gate requires every required desktop lane to have succeeded, and `desktop-macos-integration` did not, because of row A14's physical blocker (window 84). The gate refusing to promote is the gate working correctly, but it means no promotion has yet happened at any revision, so `desktop-promote`, `slsa-provenance-attestation` and `sbom-generation` are all BLOCKED and no provenance attestation or bill of materials exists for any revision. QUAL-03 has therefore been UNCHECKED, with clause 1 (the digest binding, proven again at this revision by `desktop-packaged` passing 11 cases against the exact continuous-integration application digest) recorded as still proven. TO CLOSE: close window 84 so the macOS lane passes on a hosted runner, let `desktop-promote` run, and re-verify at the resulting revision with `node tooling/verify-release.mjs --manifest .planning/releases/<tag>/release-manifest.json`. | open |  | 2026-09-12T04:10:00.000Z |  | BACKLOG |
| 89 | 06 | unmet-truth | tooling/release-lanes.json |  | Class: contract-in-tension-with-evidence. The `macos-integration-full-grant` lane records its physical blocker as a hosted GitHub runner being unable to receive a non-interactive TCC Accessibility grant. The `hosted-runner-tcc-report` lane exists precisely to publish what the runner ACTUALLY grants rather than what the contract predicts, and at revision 26628e1 it answered `accessibility_trusted: true`, alongside `screen_recording_preflight: true` and a `universal_access_write` that persisted and read back a matching token (run 34668212473). That is in direct tension with the recorded blocker, and it was surfaced by the reporting step doing its job. It is NOT yet resolved either way: the report describes the TccProbe process at probe time, and no run has attempted the full-grant rows on a hosted runner, so neither the contract nor the report has been falsified. What must not happen is the tension being left unstated while the blocker keeps reading as settled fact. TO CLOSE: run `node tooling/verify-macos-integration.mjs --rows A1,A2,A3` on a hosted macos-15 runner against downloaded continuous-integration bytes and record the outcome, then either wire the full-grant rows into continuous integration or replace the blocker text with what the attempt actually showed. | open |  | 2026-09-12T04:10:00.000Z |  | BACKLOG |
| 90 | 06 | unmet-truth | .planning/releases/candidate-1/release-manifest.json |  | Class: partial-retention. D-13 requires the release evidence to be retained both in the repository AND as GitHub Release assets, which do not expire. The repository half is done: the manifest, all five artefact records, both full continuous-integration logs and a per-lane evidence log for every lane that produced one are committed under `.planning/releases/candidate-1/`. The release-asset half is NOT done, because attaching assets requires pushing and creating a release and this revision has neither been tagged nor released. The 14-day build-artefact retention in the workflows is untouched and is a convenience, not the retention mechanism. Nothing is currently lost -- the committed copy does not expire either -- so this is a partial, not a gap. TO CLOSE: tag the release revision and run `gh release create <tag> .planning/releases/<tag>/release-manifest.json .planning/releases/<tag>/artifacts/* .planning/releases/<tag>/evidence/**`, or record a decision that the committed copy is the sole retention mechanism and amend D-13. | open |  | 2026-09-12T04:10:00.000Z |  | BACKLOG |
| 91 | 06 | unmet-truth | .github/workflows/desktop.yml |  | Class: no-continuous-integration-signing. Every continuous-integration-built desktop artefact is UNSIGNED and UNNOTARIZED, at every revision so far, because the Developer ID .p12 has not been exported to repository secrets. The `desktop-package` job detects this and takes its documented unsigned path, printing `No Developer ID certificate is reachable from this event (push). This artifact is UNSIGNED and UNNOTARIZED, and the package manifest records it as such`, and the manifest does record it (codeSigning.developerIdSigned false, notarization.status not-attempted) -- the machinery is behaving correctly and honestly. The consequence is what matters: a signed, notarized and stapled build HAS been produced and verified end to end locally (spctl --assess returns accepted with source Notarized Developer ID), but that attestation binds to LOCALLY BUILT bytes, and nothing local may bind to locally built bytes. So no signing claim may currently be attached to any released artefact, and `.planning/releases/candidate-1/release-manifest.json` states the unsigned fact directly on the artefact entry. TO CLOSE: export the Developer ID .p12 and its password to repository secrets (an owner action), re-run desktop.yml, and re-verify the manifest at the resulting revision. | open |  | 2026-09-12T04:10:00.000Z |  | BACKLOG |
| 92 | 06 | unmet-truth | tooling/verify-cross-adapter-phase.mjs |  | Class: unwired-lane-behind-a-checked-box. SRV-02 is CHECKED on the strength of plan 06-05's cross-adapter run, which was real and thorough -- all four legs (web-api, mcp, electron, iphone) passed with byte-identical result_code, conflict_shape, activity_fact and final_revision across all four shared scenarios, and it surfaced and fixed a genuine cross-client contract bug (ConflictField.field's OpenAPI enum was missing completed_at and trashed_at, which fatally crashed the real Swift decoder). But that run was LOCAL. The `cross-adapter-phase` lane is ciWiring unwired: no committed workflow job runs `node tooling/verify-cross-adapter-phase.mjs`, so the lane is BLOCKED with a zero case count in .planning/releases/candidate-1/release-manifest.json and SRV-02 has no continuous-integration-authoritative evidence at revision 26628e1. Plan 06-13 deliberately did NOT uncheck the box: the evidence behind it genuinely ran and passed, the gap is CI authority rather than falsity, and re-adjudicating another plan's finding was outside this plan's scope. It is filed here instead so the gap is owned rather than silent, which is the whole point of D-35. This row is adjacent to, not a duplicate of, row 75 (which is about `gsd-tools phase complete` checking the wrong boxes). TO CLOSE: add a committed job running `node tooling/verify-cross-adapter-phase.mjs`, add `cross-adapter-phase` to the required-lane list in tooling/check-ci-contract.mjs, and re-verify the release manifest at the resulting revision. OR decide explicitly that a local cross-adapter run is sufficient authority for SRV-02 and record that decision. | open |  | 2026-09-12T04:20:00.000Z |  | BACKLOG |
| 93 | 06 | unmet-truth | tooling/check-ci-contract.mjs |  | Class: contract-names-a-lane-nothing-runs. D-14 names `phase-1-desktop`, `mcp-gate-selftest` and `mcp-phase-non-model` as REQUIRED on pull requests and main, and no committed workflow job runs any of them: nothing invokes `./tooling/test-phase-1.sh`, `node tooling/mcp-gate-selftest.mjs`, or `node tooling/verify-mcp-phase.mjs` non-model lanes. All three are recorded ciWiring unwired in tooling/release-lanes.json and appear as explicit zero-case BLOCKED entries in .planning/releases/candidate-1/release-manifest.json, which is the honest treatment -- an omitted lane reads as satisfied. The gap is that a lane the lane-assignment decision calls required has never once been enforced, so 'required' currently means required-on-paper for these three. Their inventory owner was moved from KPL-06 to backlog by plan 06-13, because KPL-06 is the final phase of the milestone and may not remain the owner of a lane still BLOCKED at its end. TO CLOSE: add a job per lane to .github/workflows/repository-integrity.yml, add each lane to the required-lane list in tooling/check-ci-contract.mjs (which asserts the committed contract and would then fail closed on regression), and re-verify the release manifest at the resulting revision. | open |  | 2026-09-12T04:30:00.000Z |  | BACKLOG |
| 94 | 06 | unrun-verify | tooling/verify-trust-soak.mjs |  | Class: measurement-window-not-accumulated. The trust soak's verdict is BLOCKED with ZERO samples and this is the correct state, not a failure to fix. .artifacts/trust-soak/trust-soak-evidence.json reports verdict BLOCKED, every one of the ten chaos operator counts at 0, every invariant I1 through I10 at samples 0 violations 0 disposition BLOCKED, an empty dailyUsageCensus, and detectionFloor confidence null with its own note: insufficient accumulated samples to state a detection floor, this proves nothing about defects of any rarity yet. The window accumulates in calendar time, which no plan can manufacture. Consequently the fifth release criterion's defect-absence half is satisfied by this gate's verdict and by nothing else -- not by judgement, and never by owner dogfood feedback, which is reported as an outcome and given no evidence row. The lane keeps the release manifest's overall verdict non-zero, which is exactly what it is for. Its inventory owner was moved from KPL-06 to backlog because KPL-06 is ending. TO CLOSE: accumulate the stated measurement window, then `node tooling/verify-trust-soak.mjs` and re-verify the release manifest. | open |  | 2026-09-12T04:30:00.000Z |  | BACKLOG |
| 95 | 06 | unrun-verify | .github/workflows/recovery-drills.yml |  | Class: scheduled-lane-never-bound-to-a-revision. The `daily-restore`, `weekly-historical-pitr` and `quarterly-host-replacement` lanes live in a schedule-triggered workflow, so no run of any of them exists AT the candidate release revision 26628e1 and all three are recorded as explicit zero-case BLOCKED entries in .planning/releases/candidate-1/release-manifest.json. They are not broken -- a scheduled drill passing last night is real evidence about last night's tree. What is missing is a way to bind a drill result to the exact revision being released, which is what every other lane in the manifest does. Their inventory owner was moved from KPL-06 to backlog because KPL-06 is ending. TO CLOSE: add `workflow_dispatch` to recovery-drills.yml so the drills can be run at a named revision, dispatch them at the release revision, and bind their run ids into that revision's manifest. | open |  | 2026-09-12T04:30:00.000Z |  | BACKLOG |

````json
[
  {
    "id": 1,
    "kind": "deviation",
    "phase": "01",
    "file": "apps/web/playwright.config.ts",
    "line": null,
    "description": "Playwright 1.62 required a harness contract so pre-feature --list discovery exits successfully",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T01:19:02.196Z",
    "resolved_at": "2026-09-03T23:50:04.775Z"
  },
  {
    "id": 2,
    "kind": "deviation",
    "phase": "01",
    "file": "package.json",
    "line": null,
    "description": "openapi-typescript 7.13.0 required a root-only TypeScript 5.9.3 peer alongside the web TypeScript 6 toolchain",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T01:19:02.274Z",
    "resolved_at": "2026-09-03T23:50:04.865Z"
  },
  {
    "id": 3,
    "kind": "deviation",
    "phase": "01",
    "file": "apps/web/e2e/support/stack.ts",
    "line": null,
    "description": "Disposable trust-auth PostgreSQL now rejects every non-loopback bind",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T01:19:02.349Z",
    "resolved_at": "2026-09-03T23:50:04.953Z"
  },
  {
    "id": 4,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/priv/repo/migrations/.formatter.exs",
    "line": null,
    "description": "Retained the Phoenix generator migration formatter marker so the planned Mix test alias can run before migrations exist",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T01:31:44.014Z",
    "resolved_at": "2026-09-03T23:50:05.039Z"
  },
  {
    "id": 5,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/test/architecture_test.exs",
    "line": null,
    "description": "Corrected architecture-test formatting found by the plan-level Mix formatter gate",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T01:31:44.083Z",
    "resolved_at": "2026-09-03T23:50:05.124Z"
  },
  {
    "id": 6,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/web/e2e/support/stack.ts",
    "line": null,
    "description": "Made the real-stack E2E lifecycle executable before RED",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T02:10:59.290Z",
    "resolved_at": "2026-09-03T23:50:05.208Z"
  },
  {
    "id": 7,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/priv/repo/seeds.exs",
    "line": null,
    "description": "Added an explicitly test-only closed-account seed",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T02:10:59.359Z",
    "resolved_at": "2026-09-03T23:50:05.293Z"
  },
  {
    "id": 8,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/web/src/index.css",
    "line": null,
    "description": "Applied the approved accessible capture baseline",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T02:10:59.428Z",
    "resolved_at": "2026-09-03T23:50:05.380Z"
  },
  {
    "id": 9,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/lib/keepling/adapters/postgres/command_store.ex",
    "line": null,
    "description": "Corrected double-encoded JSONB terminal results",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T02:10:59.498Z",
    "resolved_at": "2026-09-03T23:50:05.467Z"
  },
  {
    "id": 10,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/mix.exs",
    "line": null,
    "description": "Added exact reviewed Argon2id and Tzdata dependencies required by the planned setup contract",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T02:33:05.090Z",
    "resolved_at": "2026-09-03T23:50:05.554Z"
  },
  {
    "id": 11,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/priv/repo/migrations/20260830000200_add_closed_setup_and_timezone.exs",
    "line": null,
    "description": "Bound setup TTL and enforced permanent disablement plus future account credential/timezone fields",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T02:33:05.162Z",
    "resolved_at": "2026-09-03T23:50:05.640Z"
  },
  {
    "id": 12,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/config/config.exs",
    "line": null,
    "description": "Disabled Tzdata remote updater to close the vulnerable transitive HTTP path",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T02:33:05.234Z",
    "resolved_at": "2026-09-03T23:50:05.726Z"
  },
  {
    "id": 13,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/web/src/App.tsx",
    "line": null,
    "description": "Wired Inbox route reachability and exact acknowledgement reconciliation omitted from the plan file list",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T03:57:58.529Z",
    "resolved_at": "2026-09-03T23:50:05.816Z"
  },
  {
    "id": 14,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/lib/keepling/domain/task.ex",
    "line": null,
    "description": "Added canonical nullable planned_on and deadline_on aggregate fields omitted from the plan file list",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T05:18:34.955Z",
    "resolved_at": "2026-09-03T23:50:05.905Z"
  },
  {
    "id": 15,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/priv/repo/migrations/20260830000650_add_task_view_projections.exs",
    "line": null,
    "description": "Added durable projection schema and relevant command-store revision advancement omitted from the plan file list",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T05:48:12.063Z",
    "resolved_at": "2026-09-03T23:50:05.993Z"
  },
  {
    "id": 16,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/web/src/App.tsx",
    "line": null,
    "description": "Wired authenticated shell list reachability and scoped the resulting legacy test ambiguity",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T05:48:12.168Z",
    "resolved_at": "2026-09-03T23:50:06.084Z"
  },
  {
    "id": 17,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/lib/keepling/application/task_views.ex",
    "line": null,
    "description": "Removed an Ecto UUID dependency from the persistence-neutral application boundary",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T05:48:12.271Z",
    "resolved_at": "2026-09-03T23:50:06.173Z"
  },
  {
    "id": 18,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/priv/repo/migrations/20260830000650_add_task_view_projections.exs",
    "line": null,
    "description": "Added exact Today move receipts and honest ambiguous-delivery retry after final trust review",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T05:48:12.377Z",
    "resolved_at": "2026-09-03T23:50:06.259Z"
  },
  {
    "id": 19,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/web/src/commands/submission.ts",
    "line": null,
    "description": "Added explicit direct same-ID retry semantics required by lifecycle recovery",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T14:01:34.378Z",
    "resolved_at": "2026-09-03T23:50:06.345Z"
  },
  {
    "id": 20,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/web/src/commands/submission.ts",
    "line": null,
    "description": "Classified infrastructure 5xx as unknown delivery rather than terminal rejection",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T14:01:34.472Z",
    "resolved_at": "2026-09-03T23:50:06.437Z"
  },
  {
    "id": 21,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/lib/keepling_web/controllers/test_fault_controller.ex",
    "line": null,
    "description": "Halted authentication-before-acceptance injection before command dispatch",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T14:01:34.566Z",
    "resolved_at": "2026-09-03T23:50:06.531Z"
  },
  {
    "id": 22,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/web/src/index.css",
    "line": null,
    "description": "Resolved the 1024px wide-shell overflow seam with a compact list column",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T16:02:33.525Z",
    "resolved_at": "2026-09-03T23:50:06.625Z"
  },
  {
    "id": 23,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/web/src/features/tasks/TaskEditor.tsx",
    "line": null,
    "description": "Reconciled mounted editor state immediately after semantic undo acknowledgement",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T16:02:33.629Z",
    "resolved_at": "2026-09-03T23:50:06.713Z"
  },
  {
    "id": 24,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "tooling/test-phase-1.sh",
    "line": null,
    "description": "Pinned disposable migration, compile, and ExUnit lanes to MIX_ENV=test",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-08-31T16:02:33.734Z",
    "resolved_at": "2026-09-03T23:50:06.801Z"
  },
  {
    "id": 25,
    "kind": "lint-warning",
    "phase": "KPL-01",
    "file": "apps/web/src/features/lists/TaskList.tsx",
    "line": 190,
    "description": "Pre-existing react-hooks/set-state-in-effect lint violation in TaskList",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-08-31T22:38:58.822Z",
    "resolved_at": "2026-09-01T02:23:20.832Z"
  },
  {
    "id": 26,
    "kind": "lint-warning",
    "phase": "KPL-01",
    "file": "apps/web/src/features/lists/TrashList.tsx",
    "line": 91,
    "description": "Pre-existing react-hooks/set-state-in-effect lint violation in TrashList",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-08-31T22:38:58.894Z",
    "resolved_at": "2026-09-01T02:23:20.907Z"
  },
  {
    "id": 27,
    "kind": "unmet-truth",
    "phase": "KPL-01",
    "file": "apps/web/e2e/lifecycle-recovery.spec.ts",
    "line": 422,
    "description": "Session revocation remains visible after recent-authentication recovery in the full Phase 1 gate",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-01T01:37:57.347Z",
    "resolved_at": "2026-09-01T01:42:08.820Z"
  },
  {
    "id": 28,
    "kind": "lint-warning",
    "phase": "KPL-01",
    "file": "apps/web/src/app/AuthProvider.tsx",
    "line": 259,
    "description": "Repository ESLint fast-refresh export violation predates Plan 25",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-01T01:37:57.421Z",
    "resolved_at": "2026-09-01T02:23:20.983Z"
  },
  {
    "id": 29,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/web/src/test/ui-contract.test.tsx",
    "line": null,
    "description": "Exhaustive production-tree gate required mechanical scale closure outside the ten initially listed feature files.",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-01T02:22:51.183Z",
    "resolved_at": "2026-09-03T23:50:06.901Z"
  },
  {
    "id": 30,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/web/src/app/AuthProvider.tsx",
    "line": null,
    "description": "Plan-required repository lint gate required scoped ownership directives for pre-existing findings.",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-01T02:22:51.264Z",
    "resolved_at": "2026-09-03T23:50:06.998Z"
  },
  {
    "id": 31,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "apps/server/lib/keepling/application/sync/reference_model.ex",
    "line": null,
    "description": "Corrected invalid Elixir string-literal typespec discovered during Task 1 compilation",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-01T05:55:08.453Z",
    "resolved_at": "2026-09-03T23:50:07.084Z"
  },
  {
    "id": 32,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "apps/server/lib/keepling/application/sync/reference_model.ex",
    "line": null,
    "description": "Bound immutable command bytes to the outer durable mutation identity",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-01T05:55:08.534Z",
    "resolved_at": "2026-09-03T23:50:07.170Z"
  },
  {
    "id": 33,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "apps/server/lib/keepling/accounts/security_audit.ex",
    "line": null,
    "description": "Extended the closed security-audit vocabulary for bounded device-grant facts",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-01T06:19:46.697Z",
    "resolved_at": "2026-09-03T23:50:07.256Z"
  },
  {
    "id": 34,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "apps/server/lib/keepling/accounts/device_grant.ex",
    "line": null,
    "description": "Made repeated refresh replay fencing idempotent after the first generation advance",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-01T06:19:46.778Z",
    "resolved_at": "2026-09-03T23:50:07.342Z"
  },
  {
    "id": 35,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "apps/server/lib/keepling/accounts/device_grant.ex",
    "line": null,
    "description": "Rejected extra public-client secret and namespace assertion fields",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-01T06:19:46.857Z",
    "resolved_at": "2026-09-03T23:50:07.426Z"
  },
  {
    "id": 36,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "apps/server/lib/keepling/application.ex",
    "line": null,
    "description": "Compatibility configuration is validated before application supervision starts",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-01T07:13:47.287Z",
    "resolved_at": "2026-09-03T23:50:07.515Z"
  },
  {
    "id": 37,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "tooling/check-contracts.mjs",
    "line": null,
    "description": "Compatibility contract gate rejects vacuous or malformed skew evidence",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-01T07:13:47.399Z",
    "resolved_at": "2026-09-03T23:50:07.607Z"
  },
  {
    "id": 38,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "tooling/test-compatibility.sh",
    "line": null,
    "description": "Migration count probe uses explicit PostgreSQL inputs and numeric output isolation",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-01T07:13:47.518Z",
    "resolved_at": "2026-09-03T23:50:07.692Z"
  },
  {
    "id": 39,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "infra/caddy/Caddyfile",
    "line": null,
    "description": "Preserved local HTTP proof without disabling production HTTPS automation",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-01T08:35:49.662Z",
    "resolved_at": "2026-09-03T23:50:07.780Z"
  },
  {
    "id": 40,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "tooling/verify-deploy.sh",
    "line": null,
    "description": "Emitted the setup capability from the running release node",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-01T08:35:49.770Z",
    "resolved_at": "2026-09-03T23:50:07.867Z"
  },
  {
    "id": 41,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "tooling/verify-deploy.sh",
    "line": null,
    "description": "Matched the established direct task-read response contract",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-01T08:35:49.877Z",
    "resolved_at": "2026-09-03T23:50:07.955Z"
  },
  {
    "id": 42,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "tooling/test-phase-2.sh",
    "line": null,
    "description": "Corrected the Phase 2 sync lane to digest the tracked canonical sync vector",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-02T03:18:29.294Z",
    "resolved_at": "2026-09-03T23:50:08.046Z"
  },
  {
    "id": 43,
    "kind": "unrun-verify",
    "phase": "KPL-02",
    "file": ".planning/phases/KPL-02-synchronization-and-replaceable-server/deferred-items.md",
    "line": null,
    "description": "Credentialed corrected restore/runtime and DNS cutover/rollback outer acceptance remains explicitly non-passing",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T03:18:34.980Z",
    "resolved_at": null
  },
  {
    "id": 44,
    "kind": "deviation",
    "phase": "KPL-03",
    "file": ".npmrc",
    "line": null,
    "description": "Forge required a hoisted pnpm linker and regenerated lock graph",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-02T18:23:00.601Z",
    "resolved_at": "2026-09-03T23:50:08.133Z"
  },
  {
    "id": 45,
    "kind": "deviation",
    "phase": "KPL-03",
    "file": "apps/desktop/forge.config.ts",
    "line": null,
    "description": "Forge packaging was restricted to bundled runtime assets",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-02T18:23:00.686Z",
    "resolved_at": "2026-09-03T23:50:08.219Z"
  },
  {
    "id": 46,
    "kind": "deviation",
    "phase": "KPL-03",
    "file": "tooling/package-desktop.mjs",
    "line": null,
    "description": "External app copying required verbatim framework symlinks",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-02T18:23:00.770Z",
    "resolved_at": "2026-09-03T23:50:08.308Z"
  },
  {
    "id": 47,
    "kind": "deviation",
    "phase": "KPL-03",
    "file": "apps/desktop/main/index.ts",
    "line": null,
    "description": "Packaged process resources required direct Resources paths",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-02T18:23:00.852Z",
    "resolved_at": "2026-09-03T23:50:08.396Z"
  },
  {
    "id": 48,
    "kind": "deviation",
    "phase": "KPL-03",
    "file": "apps/desktop/main/index.ts",
    "line": null,
    "description": "Same-profile ownership required an explicit Electron single-instance lock",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-02T18:23:00.938Z",
    "resolved_at": "2026-09-03T23:50:08.482Z"
  },
  {
    "id": 49,
    "kind": "deviation",
    "phase": "KPL-03",
    "file": "packages/contracts/openapi/keepling.yaml",
    "line": null,
    "description": "Approved additive native-token namespace response expansion resolved in plan 03-02",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-02T18:54:39.314Z",
    "resolved_at": "2026-09-03T23:50:08.569Z"
  },
  {
    "id": 50,
    "kind": "deviation",
    "phase": "KPL-03",
    "file": "apps/desktop/migrations/0001_initial.sql",
    "line": null,
    "description": "Persisted storage-neutral synchronization metadata required for relaunch-safe lane replay",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-02T18:55:07.249Z",
    "resolved_at": "2026-09-03T23:50:08.653Z"
  },
  {
    "id": 51,
    "kind": "deviation",
    "phase": "KPL-03",
    "file": "apps/desktop/tsconfig.json",
    "line": null,
    "description": "Allowed type-only repository-owned generated contract imports in desktop typechecking",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-02T18:55:07.362Z",
    "resolved_at": "2026-09-03T23:50:08.740Z"
  },
  {
    "id": 52,
    "kind": "deviation",
    "phase": "KPL-03",
    "file": "apps/desktop/main/adapters/credentials.ts",
    "line": null,
    "description": "Loaded Electron safeStorage lazily so injected adapter proof runs outside Electron",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-02T18:55:07.476Z",
    "resolved_at": "2026-09-03T23:50:08.827Z"
  },
  {
    "id": 53,
    "kind": "deviation",
    "phase": "KPL-03",
    "file": "apps/desktop/main/adapters/credentials.ts",
    "line": null,
    "description": "Added unsigned dogfood credential continuity disclosure for Settings presentation",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-02T18:55:07.591Z",
    "resolved_at": "2026-09-03T23:50:08.912Z"
  },
  {
    "id": 54,
    "kind": "deviation",
    "phase": "KPL-03",
    "file": "apps/desktop/main/adapters/credentials.ts",
    "line": null,
    "description": "03-13: pane-size persistence (D-06) is N/A -- no resizable-pane UI exists in the shared Workspace presentation to size or restore; documented decision, not a stub.",
    "status": "waived",
    "reason": "Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate.",
    "recorded_at": "2026-09-03T01:41:18.549Z",
    "resolved_at": "2026-09-03T23:50:09.007Z"
  },
  {
    "id": 55,
    "kind": "unrun-verify",
    "phase": "KPL-03",
    "file": "tooling/verify-desktop-phase.mjs",
    "line": null,
    "description": "macos-integration lane cases=0 at 03-17 HEAD: recorded row evidence is bound to the packaged applicationDigestSha256 and 03-17 changed main/index.ts. Re-record with: pnpm package:desktop && node tooling/verify-macos-integration.mjs --all (O-27)",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-03T20:47:11.732Z",
    "resolved_at": "2026-09-03T23:49:58.264Z"
  },
  {
    "id": 56,
    "kind": "unmet-truth",
    "phase": "KPL-03",
    "file": "apps/desktop/vitest.config.ts",
    "line": null,
    "description": "vitest 'worker' project declares include test/worker/** but that directory does not exist; the empty lane is invisible in a full run (O-26)",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-03T20:47:11.845Z",
    "resolved_at": "2026-09-03T23:49:58.349Z"
  },
  {
    "id": 57,
    "kind": "unmet-truth",
    "phase": "KPL-03",
    "file": "apps/desktop/store-worker/local-store.ts",
    "line": null,
    "description": "A locally REFUSED change has no durable home: the refused command is terminal and leaves the outbox, so the next applyPull replays the canonical shadow and the person's version is lost -- while the authored copy says \"Your version is still on this Mac.\" (O-43). Do NOT resolve by keeping refused commands queued.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-04T04:12:07.673Z",
    "resolved_at": null
  },
  {
    "id": 58,
    "kind": "unmet-truth",
    "phase": "KPL-03",
    "file": "packages/web-ui/src/tasks/ConflictResolver.tsx",
    "line": null,
    "description": "The desktop conflict chooser is title-only, so a lifecycle/Trash conflict reaches a person as copy plus a refresh but with no mine/current choice; apps/web already has the multi-field resolver (O-44)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-04T04:12:07.673Z",
    "resolved_at": null
  },
  {
    "id": 59,
    "kind": "unmet-truth",
    "phase": "KPL-03",
    "file": "apps/desktop/main/application/DesktopApplication.ts",
    "line": null,
    "description": "undoLastLocalAction reverses a local change and enqueues NO outbound command, so an undo is invisible to the server -- the same defect class as O-41, needing server-issued undo handles the client does not retain (O-45)",
    "status": "fixed",
    "reason": "CLOSED 2026-09-11 (06-01): verified against source, not merely carried forward. DesktopApplication.ts lines 466-517 document and implement O-45's real fix -- undoLastLocalAction now retains the server-issued undo handle from acknowledgements and reconciles through it (POST /commands/undo-task), refusing loudly rather than silently when no handle exists yet or the handle has expired. This row was stale; the code has been fixed since.",
    "recorded_at": "2026-09-04T04:12:07.673Z",
    "resolved_at": "2026-09-11T00:00:00.000Z"
  },
  {
    "id": 60,
    "kind": "unmet-truth",
    "phase": "KPL-03",
    "file": "apps/desktop/main/application/presentation.ts",
    "line": null,
    "description": "{ kind: preparing } has authored copy and no production construction site; the real site is a first-run bootstrap branch (KeeplingSyncAdapter.bootstrap() is called from nowhere). Reported for a recorded decision, deliberately not wired speculatively and not deleted (O-46)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-04T04:12:07.673Z",
    "resolved_at": null
  },
  {
    "id": 61,
    "kind": "unmet-truth",
    "phase": "KPL-03",
    "file": "apps/desktop/main/application/presentation.ts",
    "line": null,
    "description": "{ kind: uncertain } and its check_again action have authored copy and no production construction site; constructing it honestly needs the transport to distinguish \"never left\" from \"left, answer lost\". Reported for a recorded decision, deliberately not wired speculatively and not deleted (O-47)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-04T04:12:07.673Z",
    "resolved_at": null
  },
  {
    "id": 62,
    "kind": "unmet-truth",
    "phase": "KPL-04",
    "file": "tooling/verify-real-stack-ios.mjs",
    "line": null,
    "description": "The server-driven half of D-22 Criterion 2 (auth expiry, account fencing, duplicate replay, structured conflict) could not run on a physical iPhone: KeeplingSyncAdapter refuses any non-HTTPS base URL whose host is not 127.0.0.1/localhost, and over TLS URLSession rejected the lane's self-signed certificate. CLOSED 2026-09-08 (04-18) WITHOUT widening the production transport guard and WITHOUT the planned DEBUG-only lane CA: `tailscale cert` serves the proxy from a MagicDNS name under a real Let's Encrypt certificate, so the phone validates it through the shipping transport and no test-only trust code exists on any configuration. Lane `server-driven-device` PASS cases=4.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-07T04:03:27.449Z",
    "resolved_at": "2026-09-08T21:00:00.000Z"
  },
  {
    "id": 63,
    "kind": "skipped-test",
    "phase": "KPL-04",
    "file": "apps/ios/Tests/StorageTests/DataProtectionTests.swift",
    "line": null,
    "description": "Gate G7's locked-device write is unverified: no programmatic lock control exists (devicectl has no lock verb, XCUIDevice is UI-testing-only, and DataProtectionTests is a unit bundle). UPDATED 2026-09-08 (04-18): the compounding half is GONE -- the device now has a passcode set (`devicectl device info lockState` reports passcodeRequired: true, recorded by resolve-devices.mjs), and the protection class is proven enforceable on hardware. Only the lock-control half remains open, and closing it would mean adding a production protectedDataWillBecomeUnavailable write hook solely to make a gate pass.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-07T04:03:27.539Z",
    "resolved_at": null
  },
  {
    "id": 64,
    "kind": "unmet-truth",
    "phase": "KPL-04",
    "file": "apps/ios/Tests/StorageTests/Fixtures/migration-1.sqlite",
    "line": null,
    "description": "The storage lane opened its committed SQLite fixtures IN PLACE and mutated them. SEVERITY WAS UNDERSTATED: the note said only the FIRST run on a fresh checkout tested a pre-migration database, but the mutated migration-1.sqlite was itself COMMITTED (at [1,2] in ada909e, then at [1,2,3] in 624f9f3), and FixtureFactory.ensureMigration1Fixture() returns early when the file exists -- so testMigration1FixtureMigratesForwardToVersion2PreservingVersion1Row asserted [1,2,3] against an already-migrated file on EVERY checkout, migrating nothing. FIXED 2026-09-08 (04-18): every consumer now opens a writable per-run COPY (FixtureFactory.writableCopy, carrying the -wal/-shm siblings), and migration-1.sqlite was regenerated at version 1 only. Verified: the fixture is byte-identical after a full storage-lane run, the working tree stays clean, and storage/storage-gates/durability-posture all pass.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-07T04:33:11.054Z",
    "resolved_at": "2026-09-08T22:30:00.000Z"
  },
  {
    "id": 65,
    "kind": "unmet-truth",
    "phase": "KPL-04",
    "file": "tooling/verify-ios-phase.mjs",
    "line": null,
    "description": "The gate published fewer cases than it ran: `xcodebuildSummary` took the LAST \"Executed N tests\" line, which for a lane spanning two test bundles is the last BUNDLE's total, not the run's. auth published 4 of 19, undo 8 of 18, sync-presentation 21 of 35, device 26 of 29 -- the published 424/454 totals understated by ~42. Never a false PASS (a failure in any bundle fails the lane however the line is parsed), but D-24's anti-vacuity contract rests on that number meaning what it says, and on `device` the discarded bundle was `DataProtectionTests`, so G7's protection-class hardware evidence contributed ZERO to the published count. FIXED 2026-09-09 (04-18): anchor on the `<Bundle>.xctest` summary line (exactly one per bundle), sum per-bundle totals, subtract skips, and fail when any single bundle executed zero. Verified: auth 19, undo 18, sync-presentation 35, device 29; corrected totals 463 simulator and 496 overall. Found by phase verification, not by a lane.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-09T02:00:00.000Z",
    "resolved_at": "2026-09-09T02:30:00.000Z"
  },
  {
    "id": 66,
    "kind": "unmet-truth",
    "phase": "KPL-05",
    "file": "apps/server/lib/keepling_web/router.ex",
    "line": 121,
    "description": "Browser cannot list or revoke agent grants: GET/DELETE /api/v1/device-grants sit behind the bearer-only :device_grant_authenticated pipeline, so a session-cookie request 401s and apps/web/e2e/agent-access.spec.ts fails at line 250 (step 5). Steps 1-4 pass, so this does NOT implicate MCP-01..05's text. Note apps/server/test/keepling_web/device_grant_controller_test.exs deliberately ASSERTS the 401 (\"bearer boundary ... ignores browser cookies\") while apps/web/src/api/keepling.ts:600 calls the same route with cookies -- two plans in one phase encoding opposite intentions for the endpoint; each one's unit tests pass and only the e2e crossing both catches it. CORRECTED 2026-09-10: this entry previously said moving the routes to :client_authenticated WOULD INTRODUCE an escalation letting any device grant, including an MCP agent, enumerate and revoke the owner's grants. The causality was inverted -- that escalation is already present in the committed pipeline (see window #70), because :device_grant_authenticated accepts an mcp grant today. So this is the third face of one decision, not an independent item: fix #70's missing client_kind refusal, and settle grant administration as owner-session-authenticated at the same time. Recommended shape: leave /api/v1/device-grants bearer-only exactly as tested and add a SEPARATE owner-session route (:authenticated, plus :mutation on the delete) for grant management, re-pointing the web client at it -- this weakens no existing assertion and adds no new path for an agent to reach the owner's grants.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-10T23:42:06.351Z",
    "resolved_at": "2026-09-11T02:13:45.161Z"
  },
  {
    "id": 67,
    "kind": "unmet-truth",
    "phase": "KPL-05",
    "file": ".planning/phases/KPL-05-safe-agent-access",
    "line": null,
    "description": "Phase KPL-05 has ROADMAP 'UI hint: yes' and shipped frontend in 05-09 (AgentGrantList.tsx, ActivityList.tsx, /settings/agents route) with no UI-SPEC.md. The ui.safety-gate blocks on this (block = frontend && hasUiFiles && !hasUiSpec); it intermittently reads false only because hasUiFiles is computed from git diff HEAD~1..HEAD, a documented single-commit limitation. Resolve with /gsd-ui-review before phase completion.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-10T23:42:13.957Z",
    "resolved_at": "2026-09-11T04:13:38.031Z"
  },
  {
    "id": 68,
    "kind": "skipped-test",
    "phase": "KPL-05",
    "file": "apps/web/e2e/authenticated-read-recovery.spec.ts",
    "line": 154,
    "description": "Flaky under the full 26-test Playwright run: '@authenticated-read-organizations restores assignment, Projects, and Tags routes' intermittently times out at 30s waiting for getByLabel('New project name'), with the page still showing Inbox -- the pushState+popstate navigation to /projects does not take. Observed failing in 2 of 4 full-suite runs during KPL-05; passes every time in isolation (1.3s) and passes when run immediately after the failing agent-access spec, so it is neither a code regression nor simple ordering interference. Route matching in routes.tsx is correctly ordered (/projects at line 340 precedes /settings/agents at 364). Suspect a race between the popstate dispatch and the app's location read under full-suite load.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-11T00:17:48.787Z",
    "resolved_at": null
  },
  {
    "id": 69,
    "kind": "unrun-verify",
    "phase": "05",
    "file": "tooling/cross-adapter/legs.mjs",
    "line": null,
    "description": "Cross-adapter lane (05-12): electron and iphone legs BLOCKED because neither has a live DRIVER wired yet -- not because their artifacts are missing. The packaged Electron build does exist at apps/desktop/out (that path is gitignored, so it is invisible from an isolated worktree, which is why 05-12 reported it absent); the Keepling app is installed on the booted simulator. runElectronLeg() needs a live IPC driver against the packaged .app (mirror apps/desktop/test/real-stack/real-stack-sync.spec.ts); runIphoneLeg() needs a live UI/recording-proxy driver against the installed app (mirror tooling/verify-real-stack-ios.mjs). web-api and mcp legs PASS with identical result_code/conflict_shape/activity_fact/final_revision across all 4 shared scenarios. SRV-02 stays unchecked pending both legs.",
    "status": "fixed",
    "reason": "06-05: both drivers wired and live. tooling/cross-adapter/electron-driver.mjs drives the packaged Mac app's real task-list UI via Playwright; tooling/cross-adapter/iphone-driver.mjs drives the real Swift KeeplingSyncAdapter (two new methods on the existing ServerDrivenTests.swift test target) via xcodebuild test-without-building. pnpm verify:cross-adapter now reports legs_total=4 legs_ran=4 legs_blocked=0 legs_failed=0 comparison_ok=true. A real cross-client contract bug (ConflictField.field's OpenAPI enum missing completed_at/trashed_at) was found and fixed en route. SRV-02 is checked.",
    "recorded_at": "2026-09-11T01:31:52.629Z",
    "resolved_at": "2026-09-11T20:15:00.000Z"
  },
  {
    "id": 70,
    "kind": "unmet-truth",
    "phase": "05",
    "file": "apps/server/lib/keepling_web/auth.ex",
    "line": 117,
    "description": "PRIVILEGE ESCALATION, confirmed by live probe and by reading: an MCP agent credential reaches surfaces the MCP adapter does not front. KeeplingWeb.MCP.Pipeline (mcp/pipeline.ex:34) refuses a grant whose client_kind != \"mcp\"; KeeplingWeb.Auth.authenticate_device_grant/1 (auth.ex:117-149) performs no mirror-image refusal -- it assigns current_client_kind and never checks it. That pipeline fronts GET /api/v1/sync, GET /api/v1/sync/bootstrap, and GET+DELETE /api/v1/device-grants (router.ex:120-127). SyncController has no client_kind check; DeviceGrantController.list/2 and revoke/2 check neither client_kind nor scope. Probed with a grant scoped [\"tasks.read\"] only: GET /api/v1/sync/bootstrap -> 200 with full account content, GET /api/v1/device-grants -> 200 listing all installations, DELETE /api/v1/device-grants/<other> -> 200 device_grant_revoked, after which the victim grant 401s on /mcp/v1. So an agent reads the entire account around the bounded/paginated/redacted read surface that 05-03/05-04 built, and can revoke the owner's iPhone or desktop. AGGRAVATOR: the harness depends on the hole -- tooling/mcp-client/final-state.mjs:68-78 reads the grant list with a device-grant bearer and asserts 200, so the green simulated-client lane rests on the escalation it should catch; closing the hole breaks that lane and it must be re-pointed at the owner session. ROOT BLIND SPOT: every lane tests for under-delivery (agent denied something it should get); none tests over-delivery (agent reaching a surface the adapter does not front). Needs adversarial negative cases on all four routes. Found by gsd-verifier during KPL-05 phase verification; see VERIFICATION.md.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-11T01:52:56.106Z",
    "resolved_at": "2026-09-11T02:13:45.033Z"
  },
  {
    "id": 71,
    "kind": "unmet-truth",
    "phase": "05",
    "file": "apps/server/config/test.exs",
    "line": 18,
    "description": "The Elixir suite has an implicit LOGIN BUDGET and no guard on it. config/test.exs caps the login rate-limit bucket per 5-minute window; every test that calls a login helper spends from one shared seeded-account bucket. 05-13 added server tests that each sign in, which pushed the suite past the old cap of 50 and emptied the bucket mid-run. auth_controller.ex:59 maps {:error, :rate_limited, _} to the same 401 authentication_failed a wrong password returns -- correct for a caller, who must not learn whether they are throttled or wrong, but it means an exhausted bucket is INDISTINGUISHABLE from a credential failure in a test log. The four tests that failed (KeeplingWeb.MCP.ToolsTest x3, KeeplingWeb.MCP.ErrorsTest x1) had nothing to do with the change that caused it; they were simply the ones that ran after the bucket emptied, and the executor that added the tests reported the suite green. Raised 50 -> 400 in KPL-05-13 follow-up (test config only; the production abuse policy in that block is deliberately untouched), so headroom is now roughly 8x rather than 1.06x. The failure mode is not closed, only deferred: the next plan that adds sign-ins hits the same wall and it will again surface as an authentication failure in an unrelated test. Worth either asserting the login count against the cap in the suite, or making the test-env rate limiter emit a distinguishable error so a throttled login cannot be mistaken for a bad credential.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-11T02:22:01.221Z",
    "resolved_at": null
  },
  {
    "id": 72,
    "kind": "unmet-truth",
    "phase": "05",
    "file": "apps/server/lib/keepling_web/auth.ex",
    "line": 147,
    "description": "SECOND, LARGER ESCALATION -- scope half of the same boundary, confirmed by re-verification probe and by reading. A credential's authority is client_kind X scope. KPL-05-13 made client_kind default-deny on :device_grant_authenticated; scope outside /mcp/v1 is not merely unchecked, it is NOT CARRIED: authenticate_device_grant/1 assigns current_client_kind and never assigns current_scope, so the 19 shared /api/v1/commands/* endpoints could not check it if they tried. CommandController contains no reference to scope. Keepling.Application.AgentScope calls itself 'the authoritative, application-boundary scope gate' so that 'a bug in the adapter alone cannot widen what an agent grant may do', yet all its call sites are inside lib/keepling_web/mcp/. Probed with real PKCE grants: a tasks.read-only grant POSTed /api/v1/commands/capture-task -> 201 persisted, and /api/v1/commands/trash-task -> 200 with the owner's read then returning 404; the same token at /mcp/v1 is refused insufficient_scope. Mirror: a tasks.write-only grant GET /api/v1/search and /api/v1/projects -> 200. The agent reaches all 19 shared commands, ~15 of which the MCP tool set deliberately never exposes (trash, restore, undo, resolve-conflict, plan-for-today, move-today, five org commands). THE :client_authenticated CARVE-OUT IS NOT DEFENSIBLE: auth.ex:147 justifies it as 'scope-checked and bounded' -- bounded is true, scope-checked is impossible because the scope is not in the conn; D-09 (05-CONTEXT.md:102) requires shared application-level QUERIES, which MCP.Resources already satisfies by calling Keepling.Application.Search in-process, and says nothing about which credential classes an HTTP route admits; and the carve-out's stated cost is not real -- mcp/resources.ex and mcp/tools.ex make no HTTP calls, final-state.mjs uses the owner session, and the cross-adapter web-api leg posts with session cookie + CSRF, so no consumer was found. PRE-EXISTING, not introduced by 05-13, and it invalidates the earlier CHECK of MCP-02 (least-privilege scopes). Fix is either refusing mcp on :client_authenticated/:client_mutation, or carrying current_scope and enforcing it in CommandController -- plus scope over-delivery cases in the adversarial lane, mutation-tested the way 05-13 mutation-tested the kind ones.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-11T02:34:24.731Z",
    "resolved_at": "2026-09-11T04:13:00.585Z"
  },
  {
    "id": 73,
    "kind": "unmet-truth",
    "phase": "05",
    "file": "apps/server/lib/keepling_web/auth.ex",
    "line": 200,
    "description": "Receipt scope inversion, found by third-pass probe. agent_authority(\"GET\", [\"api\",\"v1\",\"mutations\",_id]) maps to tasks.write, documented as 'the receipt moves WITH the write: readable by the authority that could have issued it' (D-49). The rationale is coherent for an idempotency receipt, but it is enforced at the CLASS level, not the INSTANCE level: a tasks.write-only grant read the receipt of a mutation issued by the OWNER'S BROWSER SESSION -- 200 with the full task snapshot including title -- while a tasks.read grant is refused 403 on the same route. So the scope that conveys reading cannot read, and the scope that conveys writing reads another client's result. Severity WARNING, not blocker, and MCP-02 was checked over it: mutation ids are client-chosen UUIDv4, no agent-reachable surface discloses another client's mutation id, and an unknown id answers 404, so the receipt is not enumerable -- an agent must already know the id. Two candidate fixes: require tasks.read IN ADDITION to tasks.write on that route, or bind a receipt to the grant that issued the mutation so 'could have issued it' means this credential rather than this credential class. The second is the one that matches the comment's own wording.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-11T03:16:33.943Z",
    "resolved_at": null
  },
  {
    "id": 74,
    "kind": "deviation",
    "phase": "05",
    "file": "apps/server/lib/keepling_web/auth.ex",
    "line": 147,
    "description": "DECISION RECORD OWED: RFC 8707 resource-audience scope of an mcp grant. An mcp grant is audience-bound to the MCP resource URI, and that audience is enforced only by KeeplingWeb.MCP.Pipeline; presenting the same grant at /api/v1 is therefore arguably an audience violation independent of scope. Third-pass verification ruled this a DESIGN QUESTION, not a defect, on the following grounds: same origin, same endpoint, same authorization server, one singleton account, and since 05-14 the HTTP authority is a default-deny mirror of the closed MCP tool set -- so the token buys nothing at /api/v1 that it does not already buy at /mcp/v1. Recorded rather than silently accepted because the cost of the other choice is specific and worth knowing before anyone revisits it: enforcing the audience at /api/v1 would invert apps/server/test/keepling/application/projects_test.exs:85 (the deliberate D-09 byte-identity assertion across browser session, electron bearer and mcp bearer), delete Keepling.Application.AgentScope's only call site outside lib/keepling_web/mcp/ and thereby reopen window #72's adapter-locality problem, and make the DeviceBearer abstraction false for one of three credential classes. If strict RFC 8707 conformance is wanted later, the recommended direction is to WIDEN THE DECLARED RESOURCE rather than narrow the credential.",
    "status": "waived",
    "reason": "06-11: recorded as decision D-013 in .planning/knowledge/DECISIONS.md -- an RFC 8707 audience check at :client_authenticated would buy no reduction in actual authority given this repository's single origin, single authorization server, and single account, and would invert the deliberate D-09 byte-identity assertion. Not a defect; closed by decision, not by an implementation change.",
    "recorded_at": "2026-09-11T03:16:34.067Z",
    "resolved_at": "2026-09-11T21:30:00.000Z"
  },
  {
    "id": 75,
    "kind": "unmet-truth",
    "phase": "05",
    "file": ".planning/REQUIREMENTS.md",
    "line": 21,
    "description": "gsd-tools phase complete marks the WRONG requirement boxes for this project, and it has now done so twice on the same box. Running 'phase complete 05' checked SRV-02 -- whose own inline comment reads 'This box stays unchecked until both legs pass', whose cross-adapter electron and iphone legs are still BLOCKED on unwired drivers (window #69), and which third-pass verification explicitly recommended DEFER -- while leaving MCP-01..05 unchecked despite all five being recommended CHECK at 5/5. Exactly backwards. The first occurrence is recorded in the D-28 note on that same line, so this is a repeat, not a one-off. CAUSE is structural and will recur for every phase in this project: .planning/REQUIREMENTS.md's Traceability table carries GROUPED rows ('MCP-01..05, SRV-02 and cross-adapter completion | Phase 5 | ...') rather than one row per REQ-ID, so the tool's per-ID row matcher finds nothing for any individual ID and falls back to the ROADMAP citation -- which names SRV-02 for Phase 5 and therefore checks it. The tool DISCLOSED this rather than hiding it, in two warnings on the same run: '39 REQ-ID(s) found in body but missing from Traceability table' and 'Traceability row write skipped for REQ-ID(s) cited by ROADMAP (no matching row found): SRV-02'. Corrected by hand for Phase 5. Until the Traceability table carries one row per REQ-ID, DO NOT trust phase complete's requirement marking -- diff .planning/REQUIREMENTS.md after every phase completion and correct it against the phase's VERIFICATION.md.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-11T03:18:17.153Z",
    "resolved_at": null
  },
  {
    "id": 76,
    "kind": "unmet-truth",
    "phase": "05",
    "file": "apps/server/lib/keepling_web/controllers/device_grant_controller.ex",
    "line": 167,
    "description": "CONSENT UI CANNOT SHOW WHAT IT IS FOR: KeeplingWeb.DeviceGrantController.grant_response/1 (device_grant_controller.ex:167-175) publishes only client_kind, generation, id, installation_id, label, revoked. It does NOT publish scope, authorized_at, or last_used_at. /settings/agents (AgentGrantList.tsx) is the screen where the user decides whether an AI agent still gets to read and write their tasks, and the two facts that should drive that decision -- what this agent may do, and when it last did anything -- are unavailable there today; all three fields render 'Not yet reported' for every agent. Found by the retroactive UI audit (05-UI-REVIEW.md, Pillar 6). AGGRAVATOR FOUND AND FIXED IN THE SAME AUDIT: apps/web/src/api/keepling.ts mapped 'scope: grant.scope ?? []', collapsing 'the server did not report a scope list' into 'this grant holds no scopes', so AgentGrantList.tsx rendered 'No scopes granted' for EVERY agent -- a false claim of zero permissions, on consent UI, about grants that really held tasks.read/tasks.write. Fixed by preserving null through the mapping and rendering 'Not yet reported', with a mutation-tested case in agent-grant-list.test.tsx ('reports an omitted scope list as unreported, never as holding no scopes'); reverting the mapping kills that test. The remaining work is server-side and needs both halves: publish the three fields from Keepling.Accounts.DeviceGrant, and widen DeviceGrantSummary in packages/contracts/openapi/keepling.yaml so the generated TS stops being stale (keepling.ts:47-66 documents the widening it had to do locally). No frontend rework is needed after that -- the component reads all three defensively already. NOTE the distinction the fix preserves and the server must respect: an absent scope key means UNKNOWN, an empty array means GENUINELY NO SCOPES; they are opposite claims on this screen and must not be collapsed again.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-11T04:13:26.978Z",
    "resolved_at": null
  },
  {
    "id": 77,
    "kind": "deviation",
    "phase": "05",
    "file": ".planning/ROADMAP.md",
    "line": null,
    "description": "PROCEDURE, generalized from window #67 (now closed by 05-UI-REVIEW.md): a phase whose ROADMAP entry carries a UI hint must get a UI-SPEC.md BEFORE execution, not a retroactive audit after it. The audit showed the absence had a concrete cost, not a paperwork one: with no design contract, the question 'what should an agent row show, and what should it say when it does not know' was never settled before the code was written, and the answer got decided by a '?? []' default in a wire mapper -- which is how consent UI came to tell the user, falsely, that every authorized agent held no scopes. A UI-SPEC would have had to answer the empty/unknown-state question explicitly, because that is one of the seven dimensions gsd-ui-checker validates. ALSO NOTE, for whoever runs the next retroactive audit: this one's original top finding was FALSE at CRITICAL severity -- it reported that /settings/agents was non-functional because the endpoints reject session cookies, which was true when 05-09-SUMMARY.md was written and was closed by 05-13 (window #66, owner-session routes at router.ex:146 and :152, which the web client already calls at keepling.ts:600,616). The auditor read the phase's own summaries as current state. Summaries are history; the tree is state. Audit the tree.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-11T04:13:44.809Z",
    "resolved_at": null
  },
  {
    "id": 78,
    "kind": "unmet-truth",
    "phase": "06",
    "file": "apps/desktop/renderer/DesktopShell.tsx",
    "line": 53,
    "description": "Class: data-loss. Keyboard command dispatch bypasses the unsaved-changes guard: new-task, go-inbox and go-today in DesktopShell.tsx's command-dispatch effect call facade.setRoute DIRECTLY, while every mouse-driven navigation (nav links, task selection) in packages/web-ui/src/workspace/Workspace.tsx routes through attemptNavigation, which asks the person before discarding a dirty editor's unsaved edits. Filed as O-22 (.planning/STATE.md Blockers). A person mid-edit who presses Cmd-1/Cmd-2/Cmd-N loses the in-progress edit with no dialog, no warning, and no recovery -- a silent data-loss defect in the supported daily keyboard loop MAC-02 names explicitly. Fix belongs in the keyboard dispatch effect: route these three cases through the same attemptNavigation guard mouse navigation already uses, not a parallel bypass.",
    "status": "fixed",
    "reason": "06-09: DesktopShell.tsx's new-task/go-inbox/go-today keyboard commands now call workspaceRef.current?.guardedSetRoute(...) instead of facade.setRoute(...) directly, routing through the same dirty-state guard mouse navigation already used. Proven against the real shipped Electron app in apps/desktop/test/e2e/guarded-navigation.spec.ts (7/7 cases).",
    "recorded_at": "2026-09-11T18:00:00.000Z",
    "resolved_at": "2026-09-11T21:30:00.000Z"
  },
  {
    "id": 79,
    "kind": "deviation",
    "phase": "06",
    "file": "tooling/generate-known-limitations.mjs",
    "line": null,
    "description": "gsd-tools windows (fixed/waive/append) cannot currently write to this repository's .planning/WINDOWS.md: every write attempt errors \"Ledger table region could not be located ... refusing to write\", apparently because this file's rendered markdown table carries an owner column (added by plan 06-01) that the tool's canonical fenced JSON block has no matching field for, so the tool cannot reconcile the two representations to safely rewrite either. Row #78 was found stale during 06-11 (already fixed by 06-09, still marked open here) and had to be corrected by hand-editing both the JSON block and the rendered table directly, exactly as the tool's own refusal message instructs (\"Edit the fenced JSON block directly -- the sole source of truth\"), because the sanctioned CLI path is unavailable. This should be repaired (either by adding owner to the canonical JSON schema, or by removing it from the rendered table) before the next plan needs to mark a row fixed or waived.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-11T21:30:00.000Z",
    "resolved_at": null
  },
  {
    "id": 80,
    "kind": "deviation",
    "phase": "06",
    "file": ".github/workflows/desktop.yml",
    "line": null,
    "description": "DECISION DEFERRED BY THE OWNER (2026-09-11): server OCI image signing is not implemented, and this is a recorded decision rather than an oversight. Plan 06-10 Task 3 was to cosign the server image's pushed digest, but NOTHING IN THIS REPOSITORY BUILDS OR PUSHES THAT IMAGE TO ANY REGISTRY, so there is no digest to sign. 06-RESEARCH.md Pattern 5 names the gap itself ('Registry: GHCR or wherever image is pushed') and never resolves it. The owner was asked directly during the 06-10 checkpoint and chose to defer rather than have a registry guessed at: adding a build-and-push pipeline is new infrastructure, well outside 06-10's declared files_modified, and picking a registry is a decision with cost, retention and access consequences that outlive this phase. TO CLOSE: decide where the server image is published and what triggers a push, then add the build+push pipeline and sign the resulting digest. Everything else in 06-10 Task 3 (job-scoped id-token/attestations permissions, attest-build-provenance, exact-Level-2 claim discipline, the checksum release-body template) IS implemented and passing, so this is the single remaining piece of that task. Until it is closed, no supply-chain document may claim the server image is signed.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-11T23:15:00.000Z",
    "resolved_at": null
  },
  {
    "id": 81,
    "kind": "unmet-truth",
    "phase": "06",
    "file": "docs/security/SUPPLY-CHAIN.md",
    "line": 40,
    "description": "Class: overclaim. docs/security/SUPPLY-CHAIN.md section 2 states in the present tense that \"The self-hosted server's container image is signed keylessly, by digest, using the GitHub Actions workflow's own OIDC identity (Sigstore/cosign).\" IT IS NOT. Window #80 records that server OCI image signing was deferred by the owner because nothing in this repository builds or pushes that image to any registry, and window #80's own closing sentence states the rule this violates: \"Until it is closed, no supply-chain document may claim the server image is signed.\" The claim predates 06-10 Task 2 (it landed in commit bb43580 with Task 4) and lives outside Task 2's declared file scope, so 06-10 Task 2 reported it rather than editing it inline. This repository is headed for a public Apache-2.0 release and this is a public-facing trust document, so a false present-tense control claim is the exact overclaim class this phase spent three plans refusing elsewhere. TO CLOSE: reword section 2's image-signing paragraph to future/conditional form naming window #80 as the blocker, or close window #80 and make the sentence true.",
    "status": "closed",
    "reason": "",
    "recorded_at": "2026-09-12T02:30:00.000Z",
    "resolved_at": null,
    "resolution": "Section 2's image-signing paragraph now states in bold that the server image is NOT signed, names window #80 as the blocker, and moves the keyless-by-digest language into the conditional future. The key-custody claim, which was true, is kept and stated separately. The section heading no longer advertises keyless image signing. The same pass also corrected the adjacent claim that the reproducibility lane is a load-bearing provenance control, since window #82 records that it fails for Developer ID builds."
  },
  {
    "id": 82,
    "kind": "unmet-truth",
    "phase": "06",
    "file": "tooling/verify-package-reproducibility.mjs",
    "line": null,
    "description": "Class: gate-regression. tooling/verify-desktop-phase.mjs's package-reproducible lane FAILS as of plan 06-10 Task 2, taking the desktop phase gate from 10/11 to 9/11. Two separate builds at one clean revision now differ in 16 of 618 compared entries, and the 16 are exactly the signature-bearing ones: every signed Mach-O (Electron Framework, all four helpers, Contents/MacOS/Keepling, the bundled dylibs) plus both _CodeSignature/CodeResources files. The other 602 entries are byte-identical, so the PAYLOAD is still reproducible; the SIGNATURES are not, and cannot be: @electron/osx-sign signs with --timestamp, embedding a fresh RFC 3161 secure timestamp from Apple's timestamp authority into every signature blob, and a secure timestamp is REQUIRED for notarization. A signed build is not byte-reproducible by construction. TO CLOSE, pick one deliberately: (a) have the lane invoke packaging with KEEPLING_MACOS_SKIP_SIGNING=1 (the escape hatch already exists in forge.config.ts and tooling/package-desktop.mjs), so it keeps asserting byte-identical builds and stops asserting byte-identical signatures; or (b) keep signing on and assert the narrower true thing -- every non-signature entry identical AND the differing set exactly the signature-bearing set -- which needs a real signature-blob classifier, not a path allowlist. WHAT MUST NOT HAPPEN is relaxing the existing comparison to ignore these 16 paths and calling the lane green; that is the loosened-binding trap the 06-10 Task 1 checkpoint exists to refuse, and it would silently stop noticing a genuine payload change inside a signed binary.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-12T02:45:00.000Z",
    "resolved_at": null
  },
  {
    "id": 83,
    "kind": "unmet-truth",
    "phase": "06",
    "file": "tooling/verify-export-reader.mjs",
    "line": null,
    "description": "Class: unwired-lane. The independent export reader exists and runs locally, but NO committed workflow job under .github/ invokes it. `tooling/verify-export-reader.mjs` is referenced only by SUPPORT.md, PRIVACY.md and itself; a prior revision of `tooling/release-lanes.json` claimed repository-integrity.yml/ci-contract runs it and no such step exists. An unwired lane may never report PASSED because it has no job it could have passed in, so `.planning/releases/candidate-1/release-manifest.json` records `export-reader` as BLOCKED with a zero case count. This matters beyond bookkeeping: DATA-01 asserts a person can export all their data in a versioned, documented, neutral format without internal database knowledge, and the public PRIVACY.md leans on the reader as the evidence that the export is genuinely readable without Keepling. Both currently rest on a lane no continuous-integration run has ever executed. TO CLOSE: add a job to .github/workflows/repository-integrity.yml running `node tooling/verify-export-reader.mjs --golden`, add `export-reader` to the required-lane list in tooling/check-ci-contract.mjs, and re-run the release manifest at the resulting revision.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-12T04:10:00.000Z",
    "resolved_at": null,
    "owner": "BACKLOG"
  },
  {
    "id": 84,
    "kind": "unrun-verify",
    "phase": "06",
    "file": "tooling/verify-macos-integration.mjs",
    "line": null,
    "description": "Class: physical-blocker. macOS integration row A14 (Light and Dark change while the app is open) cannot run on a hosted GitHub runner, and this is now an OBSERVED boundary rather than a prediction. A14 is the only row that changes a system appearance setting WHILE the application is already running and asserts the window re-themes without a relaunch; delivering that change to a running process needs a logged-in Aqua session whose appearance daemon posts AppleInterfaceThemeChangedNotification, which a hosted runner has not got. Measured both ways at revision 26628e1: `ROW id=A14 status=FAIL cases=4` on macos-15 with `background stayed` an all-zero colour (run 34668212473, job desktop-macos-integration), and `status=PASS cases=4` on a real logged-in session. Rows A10, A12 and A13 pass on the same runner because each applies its setting BEFORE launch. The row has been split out as the `macos-integration-live-appearance` lane, authority local-attested with a stated physical blocker, and emits an explicit zero-case BLOCKED entry into every release manifest rather than disappearing. It is NOT a product defect and must not be recorded as one. TO CLOSE with continuous-integration authority: run the row on a self-hosted macOS runner with a real logged-in session, against the exact continuous-integration-built bytes.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-12T04:10:00.000Z",
    "resolved_at": null,
    "owner": "BACKLOG"
  },
  {
    "id": 85,
    "kind": "unmet-truth",
    "phase": "06",
    "file": "tooling/test-phase-2.sh",
    "line": null,
    "description": "Class: privacy-gate-failure. The `phase2-server` lane FAILS its mandatory post-run privacy scan at revision 26628e1. The lane's own command succeeded (`mix compile --warnings-as-errors && mix test`), and then `./tooling/verify-privacy.sh` over the lane's diagnostic log reported `hostile sentinel found in a diagnostic artifact` and the job exited non-zero (run 34668212479). Because no PASS line was emitted, no case count from that lane may be claimed, and the `export-elixir` lane -- whose evidence IS that job -- is BLOCKED with it. The cause is NOT yet isolated. It may well be a test-fixture literal appearing in ExUnit output rather than a product leak: `apps/server/test/keepling_web/mcp/content_isolation_test.exs` is the only server test outside the two redaction suites that uses a vector sentinel, and it uses them as in-test literals. But probably-benign is not a standard this project accepts from a privacy gate, and the same scan passes on every other lane. QUAL-05 stays checked on the strength of the `phase2-privacy` lane, which PASSED with 17 cases at this revision, and carries a dated addendum naming this row so the claim can never be cited without it. TO CLOSE: reproduce with `./tooling/test-phase-2.sh --lane server`, identify the emitter, and either stop it emitting or record why the appearance is not a leak.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-12T04:10:00.000Z",
    "resolved_at": null,
    "owner": "BACKLOG"
  },
  {
    "id": 86,
    "kind": "unmet-truth",
    "phase": "06",
    "file": "apps/server/mix.lock",
    "line": null,
    "description": "Class: vulnerable-dependency. The `image-compose-deploy` lane FAILS at revision 26628e1 because the server image build's dependency audit reports hackney 1.25.0 as VULNERABLE with four open advisories: EEF-CVE-2026-47071 (HIGH, SOCKS5 TLS upgrade ignores caller timeout), EEF-CVE-2026-47075 (MEDIUM, CR/LF injection in query parameter), EEF-CVE-2026-47076 (MEDIUM, SSRF allowlist bypass via percent-encoded host) and EEF-CVE-2026-47069 (LOW, CRLF injection in cookie domain and path options). This is a real supply-chain finding in the bytes the self-hosted server image would ship, not an infrastructure fault, and it is one of the two failures that keep the `all-required-passed` aggregator red. The audit firing is the control working. TO CLOSE: raise the hackney dependency (directly, or via whichever parent pulls it in) to a version carrying no open advisory, then re-run `./tooling/test-phase-2.sh --lane image-compose-deploy`.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-12T04:10:00.000Z",
    "resolved_at": null,
    "owner": "BACKLOG"
  },
  {
    "id": 87,
    "kind": "unmet-truth",
    "phase": "06",
    "file": ".github/workflows/repository-integrity.yml",
    "line": null,
    "description": "Class: ci-provisioning-defect. The `Install asdf` step is not idempotent against its own cache, so the `phase2-sync-property` and `phase2-backup-restore` jobs never reach their lanes. The step runs `git clone https://github.com/asdf-vm/asdf.git \"$HOME/.asdf\" --branch v0.14.1` unconditionally, but an earlier `actions/cache` restore of `~/.asdf/installs` has already created `$HOME/.asdf`, so the clone dies with `fatal: destination path '/home/runner/.asdf' already exists and is not an empty directory` and exit 128. Observed at revision 26628e1 in run 34668212479 for both jobs. This is toolchain provisioning failing before any project code runs; neither lane's result says anything about the product, and both are recorded as BLOCKED with this reason rather than as failures. It is also one of the two causes -- via phase2-linux -- that keep the `all-required-passed` aggregator red, and so it is part of what keeps QUAL-02 unchecked. TO CLOSE: make the step a no-op when `$HOME/.asdf/.git` already exists (or restore the cache after the clone), and re-run both lanes.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-12T04:10:00.000Z",
    "resolved_at": null,
    "owner": "BACKLOG"
  },
  {
    "id": 88,
    "kind": "unrun-verify",
    "phase": "06",
    "file": ".github/workflows/desktop.yml",
    "line": null,
    "description": "Class: unproven-clause. QUAL-03's second clause -- distribution jobs do not silently rebuild different bytes -- still has NO passing lane behind it, and this is now a tested absence rather than an untested one. The 2026-09-04 disclosure on QUAL-03 said clause 2 was unproven only because no workflow had ever executed and that Phase 6 must re-verify it against a real remote before any release claim. Phase 6 now has a real remote, and at revision 26628e1 the `desktop-promote` job was SKIPPED: its `needs` gate requires every required desktop lane to have succeeded, and `desktop-macos-integration` did not, because of row A14's physical blocker (window 84). The gate refusing to promote is the gate working correctly, but it means no promotion has yet happened at any revision, so `desktop-promote`, `slsa-provenance-attestation` and `sbom-generation` are all BLOCKED and no provenance attestation or bill of materials exists for any revision. QUAL-03 has therefore been UNCHECKED, with clause 1 (the digest binding, proven again at this revision by `desktop-packaged` passing 11 cases against the exact continuous-integration application digest) recorded as still proven. TO CLOSE: close window 84 so the macOS lane passes on a hosted runner, let `desktop-promote` run, and re-verify at the resulting revision with `node tooling/verify-release.mjs --manifest .planning/releases/<tag>/release-manifest.json`.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-12T04:10:00.000Z",
    "resolved_at": null,
    "owner": "BACKLOG"
  },
  {
    "id": 89,
    "kind": "unmet-truth",
    "phase": "06",
    "file": "tooling/release-lanes.json",
    "line": null,
    "description": "Class: contract-in-tension-with-evidence. The `macos-integration-full-grant` lane records its physical blocker as a hosted GitHub runner being unable to receive a non-interactive TCC Accessibility grant. The `hosted-runner-tcc-report` lane exists precisely to publish what the runner ACTUALLY grants rather than what the contract predicts, and at revision 26628e1 it answered `accessibility_trusted: true`, alongside `screen_recording_preflight: true` and a `universal_access_write` that persisted and read back a matching token (run 34668212473). That is in direct tension with the recorded blocker, and it was surfaced by the reporting step doing its job. It is NOT yet resolved either way: the report describes the TccProbe process at probe time, and no run has attempted the full-grant rows on a hosted runner, so neither the contract nor the report has been falsified. What must not happen is the tension being left unstated while the blocker keeps reading as settled fact. TO CLOSE: run `node tooling/verify-macos-integration.mjs --rows A1,A2,A3` on a hosted macos-15 runner against downloaded continuous-integration bytes and record the outcome, then either wire the full-grant rows into continuous integration or replace the blocker text with what the attempt actually showed.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-12T04:10:00.000Z",
    "resolved_at": null,
    "owner": "BACKLOG"
  },
  {
    "id": 90,
    "kind": "unmet-truth",
    "phase": "06",
    "file": ".planning/releases/candidate-1/release-manifest.json",
    "line": null,
    "description": "Class: partial-retention. D-13 requires the release evidence to be retained both in the repository AND as GitHub Release assets, which do not expire. The repository half is done: the manifest, all five artefact records, both full continuous-integration logs and a per-lane evidence log for every lane that produced one are committed under `.planning/releases/candidate-1/`. The release-asset half is NOT done, because attaching assets requires pushing and creating a release and this revision has neither been tagged nor released. The 14-day build-artefact retention in the workflows is untouched and is a convenience, not the retention mechanism. Nothing is currently lost -- the committed copy does not expire either -- so this is a partial, not a gap. TO CLOSE: tag the release revision and run `gh release create <tag> .planning/releases/<tag>/release-manifest.json .planning/releases/<tag>/artifacts/* .planning/releases/<tag>/evidence/**`, or record a decision that the committed copy is the sole retention mechanism and amend D-13.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-12T04:10:00.000Z",
    "resolved_at": null,
    "owner": "BACKLOG"
  },
  {
    "id": 91,
    "kind": "unmet-truth",
    "phase": "06",
    "file": ".github/workflows/desktop.yml",
    "line": null,
    "description": "Class: no-continuous-integration-signing. Every continuous-integration-built desktop artefact is UNSIGNED and UNNOTARIZED, at every revision so far, because the Developer ID .p12 has not been exported to repository secrets. The `desktop-package` job detects this and takes its documented unsigned path, printing `No Developer ID certificate is reachable from this event (push). This artifact is UNSIGNED and UNNOTARIZED, and the package manifest records it as such`, and the manifest does record it (codeSigning.developerIdSigned false, notarization.status not-attempted) -- the machinery is behaving correctly and honestly. The consequence is what matters: a signed, notarized and stapled build HAS been produced and verified end to end locally (spctl --assess returns accepted with source Notarized Developer ID), but that attestation binds to LOCALLY BUILT bytes, and nothing local may bind to locally built bytes. So no signing claim may currently be attached to any released artefact, and `.planning/releases/candidate-1/release-manifest.json` states the unsigned fact directly on the artefact entry. TO CLOSE: export the Developer ID .p12 and its password to repository secrets (an owner action), re-run desktop.yml, and re-verify the manifest at the resulting revision.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-12T04:10:00.000Z",
    "resolved_at": null,
    "owner": "BACKLOG"
  },
  {
    "id": 92,
    "kind": "unmet-truth",
    "phase": "06",
    "file": "tooling/verify-cross-adapter-phase.mjs",
    "line": null,
    "description": "Class: unwired-lane-behind-a-checked-box. SRV-02 is CHECKED on the strength of plan 06-05's cross-adapter run, which was real and thorough -- all four legs (web-api, mcp, electron, iphone) passed with byte-identical result_code, conflict_shape, activity_fact and final_revision across all four shared scenarios, and it surfaced and fixed a genuine cross-client contract bug (ConflictField.field's OpenAPI enum was missing completed_at and trashed_at, which fatally crashed the real Swift decoder). But that run was LOCAL. The `cross-adapter-phase` lane is ciWiring unwired: no committed workflow job runs `node tooling/verify-cross-adapter-phase.mjs`, so the lane is BLOCKED with a zero case count in .planning/releases/candidate-1/release-manifest.json and SRV-02 has no continuous-integration-authoritative evidence at revision 26628e1. Plan 06-13 deliberately did NOT uncheck the box: the evidence behind it genuinely ran and passed, the gap is CI authority rather than falsity, and re-adjudicating another plan's finding was outside this plan's scope. It is filed here instead so the gap is owned rather than silent, which is the whole point of D-35. This row is adjacent to, not a duplicate of, row 75 (which is about `gsd-tools phase complete` checking the wrong boxes). TO CLOSE: add a committed job running `node tooling/verify-cross-adapter-phase.mjs`, add `cross-adapter-phase` to the required-lane list in tooling/check-ci-contract.mjs, and re-verify the release manifest at the resulting revision. OR decide explicitly that a local cross-adapter run is sufficient authority for SRV-02 and record that decision.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-12T04:20:00.000Z",
    "resolved_at": null,
    "owner": "BACKLOG"
  },
  {
    "id": 93,
    "kind": "unmet-truth",
    "phase": "06",
    "file": "tooling/check-ci-contract.mjs",
    "line": null,
    "description": "Class: contract-names-a-lane-nothing-runs. D-14 names `phase-1-desktop`, `mcp-gate-selftest` and `mcp-phase-non-model` as REQUIRED on pull requests and main, and no committed workflow job runs any of them: nothing invokes `./tooling/test-phase-1.sh`, `node tooling/mcp-gate-selftest.mjs`, or `node tooling/verify-mcp-phase.mjs` non-model lanes. All three are recorded ciWiring unwired in tooling/release-lanes.json and appear as explicit zero-case BLOCKED entries in .planning/releases/candidate-1/release-manifest.json, which is the honest treatment -- an omitted lane reads as satisfied. The gap is that a lane the lane-assignment decision calls required has never once been enforced, so 'required' currently means required-on-paper for these three. Their inventory owner was moved from KPL-06 to backlog by plan 06-13, because KPL-06 is the final phase of the milestone and may not remain the owner of a lane still BLOCKED at its end. TO CLOSE: add a job per lane to .github/workflows/repository-integrity.yml, add each lane to the required-lane list in tooling/check-ci-contract.mjs (which asserts the committed contract and would then fail closed on regression), and re-verify the release manifest at the resulting revision.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-12T04:30:00.000Z",
    "resolved_at": null,
    "owner": "BACKLOG"
  },
  {
    "id": 94,
    "kind": "unrun-verify",
    "phase": "06",
    "file": "tooling/verify-trust-soak.mjs",
    "line": null,
    "description": "Class: measurement-window-not-accumulated. The trust soak's verdict is BLOCKED with ZERO samples and this is the correct state, not a failure to fix. .artifacts/trust-soak/trust-soak-evidence.json reports verdict BLOCKED, every one of the ten chaos operator counts at 0, every invariant I1 through I10 at samples 0 violations 0 disposition BLOCKED, an empty dailyUsageCensus, and detectionFloor confidence null with its own note: insufficient accumulated samples to state a detection floor, this proves nothing about defects of any rarity yet. The window accumulates in calendar time, which no plan can manufacture. Consequently the fifth release criterion's defect-absence half is satisfied by this gate's verdict and by nothing else -- not by judgement, and never by owner dogfood feedback, which is reported as an outcome and given no evidence row. The lane keeps the release manifest's overall verdict non-zero, which is exactly what it is for. Its inventory owner was moved from KPL-06 to backlog because KPL-06 is ending. TO CLOSE: accumulate the stated measurement window, then `node tooling/verify-trust-soak.mjs` and re-verify the release manifest.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-12T04:30:00.000Z",
    "resolved_at": null,
    "owner": "BACKLOG"
  },
  {
    "id": 95,
    "kind": "unrun-verify",
    "phase": "06",
    "file": ".github/workflows/recovery-drills.yml",
    "line": null,
    "description": "Class: scheduled-lane-never-bound-to-a-revision. The `daily-restore`, `weekly-historical-pitr` and `quarterly-host-replacement` lanes live in a schedule-triggered workflow, so no run of any of them exists AT the candidate release revision 26628e1 and all three are recorded as explicit zero-case BLOCKED entries in .planning/releases/candidate-1/release-manifest.json. They are not broken -- a scheduled drill passing last night is real evidence about last night's tree. What is missing is a way to bind a drill result to the exact revision being released, which is what every other lane in the manifest does. Their inventory owner was moved from KPL-06 to backlog because KPL-06 is ending. TO CLOSE: add `workflow_dispatch` to recovery-drills.yml so the drills can be run at a named revision, dispatch them at the release revision, and bind their run ids into that revision's manifest.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-12T04:30:00.000Z",
    "resolved_at": null,
    "owner": "BACKLOG"
  }
]
````
