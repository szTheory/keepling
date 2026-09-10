---
schema_version: 1
open_count: 7
waived_count: 49
fixed_count: 9
total_count: 65
last_updated: 2026-09-10T00:00:00.000Z
---

# Broken Windows Ledger

> Cross-phase defect register. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 01 | deviation | apps/web/playwright.config.ts |  | Playwright 1.62 required a harness contract so pre-feature --list discovery exits successfully | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T01:19:02.196Z | 2026-09-03T23:50:04.775Z |
| 2 | 01 | deviation | package.json |  | openapi-typescript 7.13.0 required a root-only TypeScript 5.9.3 peer alongside the web TypeScript 6 toolchain | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T01:19:02.274Z | 2026-09-03T23:50:04.865Z |
| 3 | 01 | deviation | apps/web/e2e/support/stack.ts |  | Disposable trust-auth PostgreSQL now rejects every non-loopback bind | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T01:19:02.349Z | 2026-09-03T23:50:04.953Z |
| 4 | KPL-01 | deviation | apps/server/priv/repo/migrations/.formatter.exs |  | Retained the Phoenix generator migration formatter marker so the planned Mix test alias can run before migrations exist | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T01:31:44.014Z | 2026-09-03T23:50:05.039Z |
| 5 | KPL-01 | deviation | apps/server/test/architecture_test.exs |  | Corrected architecture-test formatting found by the plan-level Mix formatter gate | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T01:31:44.083Z | 2026-09-03T23:50:05.124Z |
| 6 | KPL-01 | deviation | apps/web/e2e/support/stack.ts |  | Made the real-stack E2E lifecycle executable before RED | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T02:10:59.290Z | 2026-09-03T23:50:05.208Z |
| 7 | KPL-01 | deviation | apps/server/priv/repo/seeds.exs |  | Added an explicitly test-only closed-account seed | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T02:10:59.359Z | 2026-09-03T23:50:05.293Z |
| 8 | KPL-01 | deviation | apps/web/src/index.css |  | Applied the approved accessible capture baseline | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T02:10:59.428Z | 2026-09-03T23:50:05.380Z |
| 9 | KPL-01 | deviation | apps/server/lib/keepling/adapters/postgres/command_store.ex |  | Corrected double-encoded JSONB terminal results | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T02:10:59.498Z | 2026-09-03T23:50:05.467Z |
| 10 | KPL-01 | deviation | apps/server/mix.exs |  | Added exact reviewed Argon2id and Tzdata dependencies required by the planned setup contract | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T02:33:05.090Z | 2026-09-03T23:50:05.554Z |
| 11 | KPL-01 | deviation | apps/server/priv/repo/migrations/20260830000200_add_closed_setup_and_timezone.exs |  | Bound setup TTL and enforced permanent disablement plus future account credential/timezone fields | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T02:33:05.162Z | 2026-09-03T23:50:05.640Z |
| 12 | KPL-01 | deviation | apps/server/config/config.exs |  | Disabled Tzdata remote updater to close the vulnerable transitive HTTP path | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T02:33:05.234Z | 2026-09-03T23:50:05.726Z |
| 13 | KPL-01 | deviation | apps/web/src/App.tsx |  | Wired Inbox route reachability and exact acknowledgement reconciliation omitted from the plan file list | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T03:57:58.529Z | 2026-09-03T23:50:05.816Z |
| 14 | KPL-01 | deviation | apps/server/lib/keepling/domain/task.ex |  | Added canonical nullable planned_on and deadline_on aggregate fields omitted from the plan file list | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T05:18:34.955Z | 2026-09-03T23:50:05.905Z |
| 15 | KPL-01 | deviation | apps/server/priv/repo/migrations/20260830000650_add_task_view_projections.exs |  | Added durable projection schema and relevant command-store revision advancement omitted from the plan file list | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T05:48:12.063Z | 2026-09-03T23:50:05.993Z |
| 16 | KPL-01 | deviation | apps/web/src/App.tsx |  | Wired authenticated shell list reachability and scoped the resulting legacy test ambiguity | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T05:48:12.168Z | 2026-09-03T23:50:06.084Z |
| 17 | KPL-01 | deviation | apps/server/lib/keepling/application/task_views.ex |  | Removed an Ecto UUID dependency from the persistence-neutral application boundary | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T05:48:12.271Z | 2026-09-03T23:50:06.173Z |
| 18 | KPL-01 | deviation | apps/server/priv/repo/migrations/20260830000650_add_task_view_projections.exs |  | Added exact Today move receipts and honest ambiguous-delivery retry after final trust review | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T05:48:12.377Z | 2026-09-03T23:50:06.259Z |
| 19 | KPL-01 | deviation | apps/web/src/commands/submission.ts |  | Added explicit direct same-ID retry semantics required by lifecycle recovery | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T14:01:34.378Z | 2026-09-03T23:50:06.345Z |
| 20 | KPL-01 | deviation | apps/web/src/commands/submission.ts |  | Classified infrastructure 5xx as unknown delivery rather than terminal rejection | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T14:01:34.472Z | 2026-09-03T23:50:06.437Z |
| 21 | KPL-01 | deviation | apps/server/lib/keepling_web/controllers/test_fault_controller.ex |  | Halted authentication-before-acceptance injection before command dispatch | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T14:01:34.566Z | 2026-09-03T23:50:06.531Z |
| 22 | KPL-01 | deviation | apps/web/src/index.css |  | Resolved the 1024px wide-shell overflow seam with a compact list column | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T16:02:33.525Z | 2026-09-03T23:50:06.625Z |
| 23 | KPL-01 | deviation | apps/web/src/features/tasks/TaskEditor.tsx |  | Reconciled mounted editor state immediately after semantic undo acknowledgement | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T16:02:33.629Z | 2026-09-03T23:50:06.713Z |
| 24 | KPL-01 | deviation | tooling/test-phase-1.sh |  | Pinned disposable migration, compile, and ExUnit lanes to MIX_ENV=test | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-08-31T16:02:33.734Z | 2026-09-03T23:50:06.801Z |
| 25 | KPL-01 | lint-warning | apps/web/src/features/lists/TaskList.tsx | 190 | Pre-existing react-hooks/set-state-in-effect lint violation in TaskList | fixed |  | 2026-08-31T22:38:58.822Z | 2026-09-01T02:23:20.832Z |
| 26 | KPL-01 | lint-warning | apps/web/src/features/lists/TrashList.tsx | 91 | Pre-existing react-hooks/set-state-in-effect lint violation in TrashList | fixed |  | 2026-08-31T22:38:58.894Z | 2026-09-01T02:23:20.907Z |
| 27 | KPL-01 | unmet-truth | apps/web/e2e/lifecycle-recovery.spec.ts | 422 | Session revocation remains visible after recent-authentication recovery in the full Phase 1 gate | fixed |  | 2026-09-01T01:37:57.347Z | 2026-09-01T01:42:08.820Z |
| 28 | KPL-01 | lint-warning | apps/web/src/app/AuthProvider.tsx | 259 | Repository ESLint fast-refresh export violation predates Plan 25 | fixed |  | 2026-09-01T01:37:57.421Z | 2026-09-01T02:23:20.983Z |
| 29 | KPL-01 | deviation | apps/web/src/test/ui-contract.test.tsx |  | Exhaustive production-tree gate required mechanical scale closure outside the ten initially listed feature files. | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T02:22:51.183Z | 2026-09-03T23:50:06.901Z |
| 30 | KPL-01 | deviation | apps/web/src/app/AuthProvider.tsx |  | Plan-required repository lint gate required scoped ownership directives for pre-existing findings. | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T02:22:51.264Z | 2026-09-03T23:50:06.998Z |
| 31 | KPL-02 | deviation | apps/server/lib/keepling/application/sync/reference_model.ex |  | Corrected invalid Elixir string-literal typespec discovered during Task 1 compilation | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T05:55:08.453Z | 2026-09-03T23:50:07.084Z |
| 32 | KPL-02 | deviation | apps/server/lib/keepling/application/sync/reference_model.ex |  | Bound immutable command bytes to the outer durable mutation identity | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T05:55:08.534Z | 2026-09-03T23:50:07.170Z |
| 33 | KPL-02 | deviation | apps/server/lib/keepling/accounts/security_audit.ex |  | Extended the closed security-audit vocabulary for bounded device-grant facts | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T06:19:46.697Z | 2026-09-03T23:50:07.256Z |
| 34 | KPL-02 | deviation | apps/server/lib/keepling/accounts/device_grant.ex |  | Made repeated refresh replay fencing idempotent after the first generation advance | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T06:19:46.778Z | 2026-09-03T23:50:07.342Z |
| 35 | KPL-02 | deviation | apps/server/lib/keepling/accounts/device_grant.ex |  | Rejected extra public-client secret and namespace assertion fields | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T06:19:46.857Z | 2026-09-03T23:50:07.426Z |
| 36 | KPL-02 | deviation | apps/server/lib/keepling/application.ex |  | Compatibility configuration is validated before application supervision starts | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T07:13:47.287Z | 2026-09-03T23:50:07.515Z |
| 37 | KPL-02 | deviation | tooling/check-contracts.mjs |  | Compatibility contract gate rejects vacuous or malformed skew evidence | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T07:13:47.399Z | 2026-09-03T23:50:07.607Z |
| 38 | KPL-02 | deviation | tooling/test-compatibility.sh |  | Migration count probe uses explicit PostgreSQL inputs and numeric output isolation | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T07:13:47.518Z | 2026-09-03T23:50:07.692Z |
| 39 | KPL-02 | deviation | infra/caddy/Caddyfile |  | Preserved local HTTP proof without disabling production HTTPS automation | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T08:35:49.662Z | 2026-09-03T23:50:07.780Z |
| 40 | KPL-02 | deviation | tooling/verify-deploy.sh |  | Emitted the setup capability from the running release node | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T08:35:49.770Z | 2026-09-03T23:50:07.867Z |
| 41 | KPL-02 | deviation | tooling/verify-deploy.sh |  | Matched the established direct task-read response contract | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-01T08:35:49.877Z | 2026-09-03T23:50:07.955Z |
| 42 | KPL-02 | deviation | tooling/test-phase-2.sh |  | Corrected the Phase 2 sync lane to digest the tracked canonical sync vector | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-02T03:18:29.294Z | 2026-09-03T23:50:08.046Z |
| 43 | KPL-02 | unrun-verify | .planning/phases/KPL-02-synchronization-and-replaceable-server/deferred-items.md |  | Credentialed corrected restore/runtime and DNS cutover/rollback outer acceptance remains explicitly non-passing | open |  | 2026-09-02T03:18:34.980Z |  |
| 44 | KPL-03 | deviation | .npmrc |  | Forge required a hoisted pnpm linker and regenerated lock graph | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-02T18:23:00.601Z | 2026-09-03T23:50:08.133Z |
| 45 | KPL-03 | deviation | apps/desktop/forge.config.ts |  | Forge packaging was restricted to bundled runtime assets | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-02T18:23:00.686Z | 2026-09-03T23:50:08.219Z |
| 46 | KPL-03 | deviation | tooling/package-desktop.mjs |  | External app copying required verbatim framework symlinks | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-02T18:23:00.770Z | 2026-09-03T23:50:08.308Z |
| 47 | KPL-03 | deviation | apps/desktop/main/index.ts |  | Packaged process resources required direct Resources paths | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-02T18:23:00.852Z | 2026-09-03T23:50:08.396Z |
| 48 | KPL-03 | deviation | apps/desktop/main/index.ts |  | Same-profile ownership required an explicit Electron single-instance lock | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-02T18:23:00.938Z | 2026-09-03T23:50:08.482Z |
| 49 | KPL-03 | deviation | packages/contracts/openapi/keepling.yaml |  | Approved additive native-token namespace response expansion resolved in plan 03-02 | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-02T18:54:39.314Z | 2026-09-03T23:50:08.569Z |
| 50 | KPL-03 | deviation | apps/desktop/migrations/0001_initial.sql |  | Persisted storage-neutral synchronization metadata required for relaunch-safe lane replay | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-02T18:55:07.249Z | 2026-09-03T23:50:08.653Z |
| 51 | KPL-03 | deviation | apps/desktop/tsconfig.json |  | Allowed type-only repository-owned generated contract imports in desktop typechecking | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-02T18:55:07.362Z | 2026-09-03T23:50:08.740Z |
| 52 | KPL-03 | deviation | apps/desktop/main/adapters/credentials.ts |  | Loaded Electron safeStorage lazily so injected adapter proof runs outside Electron | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-02T18:55:07.476Z | 2026-09-03T23:50:08.827Z |
| 53 | KPL-03 | deviation | apps/desktop/main/adapters/credentials.ts |  | Added unsigned dogfood credential continuity disclosure for Settings presentation | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-02T18:55:07.591Z | 2026-09-03T23:50:08.912Z |
| 54 | KPL-03 | deviation | apps/desktop/main/adapters/credentials.ts |  | 03-13: pane-size persistence (D-06) is N/A -- no resizable-pane UI exists in the shared Workspace presentation to size or restore; documented decision, not a stub. | waived | Recorded plan deviation, not an outstanding defect: a 'deviation' entry documents an approved implementation decision that is already reflected in shipped code and disclosed in its plan SUMMARY. Reviewed individually 2026-09-03; none describes unfixed behaviour. Kept as audit trail rather than as a ship gate. | 2026-09-03T01:41:18.549Z | 2026-09-03T23:50:09.007Z |
| 55 | KPL-03 | unrun-verify | tooling/verify-desktop-phase.mjs |  | macos-integration lane cases=0 at 03-17 HEAD: recorded row evidence is bound to the packaged applicationDigestSha256 and 03-17 changed main/index.ts. Re-record with: pnpm package:desktop && node tooling/verify-macos-integration.mjs --all (O-27) | fixed |  | 2026-09-03T20:47:11.732Z | 2026-09-03T23:49:58.264Z |
| 56 | KPL-03 | unmet-truth | apps/desktop/vitest.config.ts |  | vitest 'worker' project declares include test/worker/** but that directory does not exist; the empty lane is invisible in a full run (O-26) | fixed |  | 2026-09-03T20:47:11.845Z | 2026-09-03T23:49:58.349Z |
| 57 | KPL-03 | unmet-truth | apps/desktop/store-worker/local-store.ts |  | A locally REFUSED change has no durable home: the refused command is terminal and leaves the outbox, so the next applyPull replays the canonical shadow and the person's version is lost -- while the authored copy says "Your version is still on this Mac." (O-43). Do NOT resolve by keeping refused commands queued. | open |  | 2026-09-04T04:12:07.673Z |  |
| 58 | KPL-03 | unmet-truth | packages/web-ui/src/tasks/ConflictResolver.tsx |  | The desktop conflict chooser is title-only, so a lifecycle/Trash conflict reaches a person as copy plus a refresh but with no mine/current choice; apps/web already has the multi-field resolver (O-44) | open |  | 2026-09-04T04:12:07.673Z |  |
| 59 | KPL-03 | unmet-truth | apps/desktop/main/application/DesktopApplication.ts |  | undoLastLocalAction reverses a local change and enqueues NO outbound command, so an undo is invisible to the server -- the same defect class as O-41, needing server-issued undo handles the client does not retain (O-45) | open |  | 2026-09-04T04:12:07.673Z |  |
| 60 | KPL-03 | unmet-truth | apps/desktop/main/application/presentation.ts |  | { kind: preparing } has authored copy and no production construction site; the real site is a first-run bootstrap branch (KeeplingSyncAdapter.bootstrap() is called from nowhere). Reported for a recorded decision, deliberately not wired speculatively and not deleted (O-46) | open |  | 2026-09-04T04:12:07.673Z |  |
| 61 | KPL-03 | unmet-truth | apps/desktop/main/application/presentation.ts |  | { kind: uncertain } and its check_again action have authored copy and no production construction site; constructing it honestly needs the transport to distinguish "never left" from "left, answer lost". Reported for a recorded decision, deliberately not wired speculatively and not deleted (O-47) | open |  | 2026-09-04T04:12:07.673Z |  |
| 62 | KPL-04 | unmet-truth | tooling/verify-real-stack-ios.mjs |  | The server-driven half of D-22 Criterion 2 (auth expiry, account fencing, duplicate replay, structured conflict) could not run on a physical iPhone: KeeplingSyncAdapter refuses any non-HTTPS base URL whose host is not 127.0.0.1/localhost, and over TLS URLSession rejected the lane's self-signed certificate. CLOSED 2026-09-08 (04-18) WITHOUT widening the production transport guard and WITHOUT the planned DEBUG-only lane CA: `tailscale cert` serves the proxy from a MagicDNS name under a real Let's Encrypt certificate, so the phone validates it through the shipping transport and no test-only trust code exists on any configuration. Lane `server-driven-device` PASS cases=4. | fixed |  | 2026-09-07T04:03:27.449Z | 2026-09-08T21:00:00.000Z |
| 63 | KPL-04 | skipped-test | apps/ios/Tests/StorageTests/DataProtectionTests.swift |  | Gate G7's locked-device write is unverified: no programmatic lock control exists (devicectl has no lock verb, XCUIDevice is UI-testing-only, and DataProtectionTests is a unit bundle). UPDATED 2026-09-08 (04-18): the compounding half is GONE -- the device now has a passcode set (`devicectl device info lockState` reports passcodeRequired: true, recorded by resolve-devices.mjs), and the protection class is proven enforceable on hardware. Only the lock-control half remains open, and closing it would mean adding a production protectedDataWillBecomeUnavailable write hook solely to make a gate pass. | open |  | 2026-09-07T04:03:27.539Z |  |
| 64 | KPL-04 | unmet-truth | apps/ios/Tests/StorageTests/Fixtures/migration-1.sqlite |  | The storage lane opened its committed SQLite fixtures IN PLACE and mutated them. SEVERITY WAS UNDERSTATED: the note said only the FIRST run on a fresh checkout tested a pre-migration database, but the mutated migration-1.sqlite was itself COMMITTED (at [1,2] in ada909e, then at [1,2,3] in 624f9f3), and FixtureFactory.ensureMigration1Fixture() returns early when the file exists -- so testMigration1FixtureMigratesForwardToVersion2PreservingVersion1Row asserted [1,2,3] against an already-migrated file on EVERY checkout, migrating nothing. FIXED 2026-09-08 (04-18): every consumer now opens a writable per-run COPY (FixtureFactory.writableCopy, carrying the -wal/-shm siblings), and migration-1.sqlite was regenerated at version 1 only. Verified: the fixture is byte-identical after a full storage-lane run, the working tree stays clean, and storage/storage-gates/durability-posture all pass. | fixed |  | 2026-09-07T04:33:11.054Z | 2026-09-08T22:30:00.000Z |
| 65 | KPL-04 | unmet-truth | tooling/verify-ios-phase.mjs |  | The gate published fewer cases than it ran: `xcodebuildSummary` took the LAST "Executed N tests" line, which for a lane spanning two test bundles is the last BUNDLE's total, not the run's. auth published 4 of 19, undo 8 of 18, sync-presentation 21 of 35, device 26 of 29 -- the published 424/454 totals understated by ~42. Never a false PASS (a failure in any bundle fails the lane however the line is parsed), but D-24's anti-vacuity contract rests on that number meaning what it says, and on `device` the discarded bundle was `DataProtectionTests`, so G7's protection-class hardware evidence contributed ZERO to the published count. FIXED 2026-09-09 (04-18): anchor on the `<Bundle>.xctest` summary line (exactly one per bundle), sum per-bundle totals, subtract skips, and fail when any single bundle executed zero. Verified: auth 19, undo 18, sync-presentation 35, device 29; corrected totals 463 simulator and 496 overall. Found by phase verification, not by a lane. | fixed |  | 2026-09-09T02:00:00.000Z | 2026-09-09T02:30:00.000Z |

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
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-04T04:12:07.673Z",
    "resolved_at": null
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
    "description": "The server-driven half of D-22 Criterion 2 (auth expiry, account fencing, duplicate replay, structured conflict) cannot run on a physical iPhone: KeeplingSyncAdapter refuses any non-HTTPS base URL whose host is not 127.0.0.1/localhost, and over TLS URLSession rejects the lane's self-signed certificate. Needs a DEBUG-only lane CA via an injected ClientTransport; NOT closed by widening the production transport guard.",
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
    "description": "Gate G7's locked-device write is unverified: no programmatic lock control exists (devicectl has no lock verb, XCUIDevice is UI-testing-only, and DataProtectionTests is a unit bundle). Compounded by the device having no passcode set, without which iOS file data protection does not engage at all.",
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
    "description": "The storage lane opened its committed SQLite fixtures IN PLACE and mutated them. SEVERITY WAS UNDERSTATED: the mutated migration-1.sqlite was itself COMMITTED (at [1,2] in ada909e, then at [1,2,3] in 624f9f3), and FixtureFactory.ensureMigration1Fixture() returns early when the file exists -- so the migration test asserted [1,2,3] against an already-migrated file on EVERY checkout, migrating nothing. FIXED 2026-09-08 (04-18): every consumer now opens a writable per-run COPY (FixtureFactory.writableCopy, carrying the -wal/-shm siblings), and migration-1.sqlite was regenerated at version 1 only. Verified: the fixture is byte-identical after a full storage-lane run, the working tree stays clean, and storage/storage-gates/durability-posture all pass.",
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
    "description": "The gate published fewer cases than it ran: xcodebuildSummary took the LAST \"Executed N tests\" line, which for a lane spanning two test bundles is only the final bundle's total -- auth published 4 of 19, undo 8 of 18, sync-presentation 21 of 35, and on the device lane the DISCARDED bundle was DataProtectionTests, so gate G7's hardware evidence contributed ZERO to the published count. FIXED 2026-09-09 (04-18): the parser anchors on each <Bundle>.xctest summary and sums across bundles, subtracts skipped cases, and throws when any bundle reports zero.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-09-09T02:00:00.000Z",
    "resolved_at": "2026-09-09T02:30:00.000Z"
  }
]
````
