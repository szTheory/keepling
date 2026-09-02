---
schema_version: 1
open_count: 49
waived_count: 0
fixed_count: 4
total_count: 53
last_updated: 2026-09-02T18:55:07.591Z
---

# Broken Windows Ledger

> Cross-phase defect register. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 01 | deviation | apps/web/playwright.config.ts |  | Playwright 1.62 required a harness contract so pre-feature --list discovery exits successfully | open |  | 2026-08-31T01:19:02.196Z |  |
| 2 | 01 | deviation | package.json |  | openapi-typescript 7.13.0 required a root-only TypeScript 5.9.3 peer alongside the web TypeScript 6 toolchain | open |  | 2026-08-31T01:19:02.274Z |  |
| 3 | 01 | deviation | apps/web/e2e/support/stack.ts |  | Disposable trust-auth PostgreSQL now rejects every non-loopback bind | open |  | 2026-08-31T01:19:02.349Z |  |
| 4 | KPL-01 | deviation | apps/server/priv/repo/migrations/.formatter.exs |  | Retained the Phoenix generator migration formatter marker so the planned Mix test alias can run before migrations exist | open |  | 2026-08-31T01:31:44.014Z |  |
| 5 | KPL-01 | deviation | apps/server/test/architecture_test.exs |  | Corrected architecture-test formatting found by the plan-level Mix formatter gate | open |  | 2026-08-31T01:31:44.083Z |  |
| 6 | KPL-01 | deviation | apps/web/e2e/support/stack.ts |  | Made the real-stack E2E lifecycle executable before RED | open |  | 2026-08-31T02:10:59.290Z |  |
| 7 | KPL-01 | deviation | apps/server/priv/repo/seeds.exs |  | Added an explicitly test-only closed-account seed | open |  | 2026-08-31T02:10:59.359Z |  |
| 8 | KPL-01 | deviation | apps/web/src/index.css |  | Applied the approved accessible capture baseline | open |  | 2026-08-31T02:10:59.428Z |  |
| 9 | KPL-01 | deviation | apps/server/lib/keepling/adapters/postgres/command_store.ex |  | Corrected double-encoded JSONB terminal results | open |  | 2026-08-31T02:10:59.498Z |  |
| 10 | KPL-01 | deviation | apps/server/mix.exs |  | Added exact reviewed Argon2id and Tzdata dependencies required by the planned setup contract | open |  | 2026-08-31T02:33:05.090Z |  |
| 11 | KPL-01 | deviation | apps/server/priv/repo/migrations/20260830000200_add_closed_setup_and_timezone.exs |  | Bound setup TTL and enforced permanent disablement plus future account credential/timezone fields | open |  | 2026-08-31T02:33:05.162Z |  |
| 12 | KPL-01 | deviation | apps/server/config/config.exs |  | Disabled Tzdata remote updater to close the vulnerable transitive HTTP path | open |  | 2026-08-31T02:33:05.234Z |  |
| 13 | KPL-01 | deviation | apps/web/src/App.tsx |  | Wired Inbox route reachability and exact acknowledgement reconciliation omitted from the plan file list | open |  | 2026-08-31T03:57:58.529Z |  |
| 14 | KPL-01 | deviation | apps/server/lib/keepling/domain/task.ex |  | Added canonical nullable planned_on and deadline_on aggregate fields omitted from the plan file list | open |  | 2026-08-31T05:18:34.955Z |  |
| 15 | KPL-01 | deviation | apps/server/priv/repo/migrations/20260830000650_add_task_view_projections.exs |  | Added durable projection schema and relevant command-store revision advancement omitted from the plan file list | open |  | 2026-08-31T05:48:12.063Z |  |
| 16 | KPL-01 | deviation | apps/web/src/App.tsx |  | Wired authenticated shell list reachability and scoped the resulting legacy test ambiguity | open |  | 2026-08-31T05:48:12.168Z |  |
| 17 | KPL-01 | deviation | apps/server/lib/keepling/application/task_views.ex |  | Removed an Ecto UUID dependency from the persistence-neutral application boundary | open |  | 2026-08-31T05:48:12.271Z |  |
| 18 | KPL-01 | deviation | apps/server/priv/repo/migrations/20260830000650_add_task_view_projections.exs |  | Added exact Today move receipts and honest ambiguous-delivery retry after final trust review | open |  | 2026-08-31T05:48:12.377Z |  |
| 19 | KPL-01 | deviation | apps/web/src/commands/submission.ts |  | Added explicit direct same-ID retry semantics required by lifecycle recovery | open |  | 2026-08-31T14:01:34.378Z |  |
| 20 | KPL-01 | deviation | apps/web/src/commands/submission.ts |  | Classified infrastructure 5xx as unknown delivery rather than terminal rejection | open |  | 2026-08-31T14:01:34.472Z |  |
| 21 | KPL-01 | deviation | apps/server/lib/keepling_web/controllers/test_fault_controller.ex |  | Halted authentication-before-acceptance injection before command dispatch | open |  | 2026-08-31T14:01:34.566Z |  |
| 22 | KPL-01 | deviation | apps/web/src/index.css |  | Resolved the 1024px wide-shell overflow seam with a compact list column | open |  | 2026-08-31T16:02:33.525Z |  |
| 23 | KPL-01 | deviation | apps/web/src/features/tasks/TaskEditor.tsx |  | Reconciled mounted editor state immediately after semantic undo acknowledgement | open |  | 2026-08-31T16:02:33.629Z |  |
| 24 | KPL-01 | deviation | tooling/test-phase-1.sh |  | Pinned disposable migration, compile, and ExUnit lanes to MIX_ENV=test | open |  | 2026-08-31T16:02:33.734Z |  |
| 25 | KPL-01 | lint-warning | apps/web/src/features/lists/TaskList.tsx | 190 | Pre-existing react-hooks/set-state-in-effect lint violation in TaskList | fixed |  | 2026-08-31T22:38:58.822Z | 2026-09-01T02:23:20.832Z |
| 26 | KPL-01 | lint-warning | apps/web/src/features/lists/TrashList.tsx | 91 | Pre-existing react-hooks/set-state-in-effect lint violation in TrashList | fixed |  | 2026-08-31T22:38:58.894Z | 2026-09-01T02:23:20.907Z |
| 27 | KPL-01 | unmet-truth | apps/web/e2e/lifecycle-recovery.spec.ts | 422 | Session revocation remains visible after recent-authentication recovery in the full Phase 1 gate | fixed |  | 2026-09-01T01:37:57.347Z | 2026-09-01T01:42:08.820Z |
| 28 | KPL-01 | lint-warning | apps/web/src/app/AuthProvider.tsx | 259 | Repository ESLint fast-refresh export violation predates Plan 25 | fixed |  | 2026-09-01T01:37:57.421Z | 2026-09-01T02:23:20.983Z |
| 29 | KPL-01 | deviation | apps/web/src/test/ui-contract.test.tsx |  | Exhaustive production-tree gate required mechanical scale closure outside the ten initially listed feature files. | open |  | 2026-09-01T02:22:51.183Z |  |
| 30 | KPL-01 | deviation | apps/web/src/app/AuthProvider.tsx |  | Plan-required repository lint gate required scoped ownership directives for pre-existing findings. | open |  | 2026-09-01T02:22:51.264Z |  |
| 31 | KPL-02 | deviation | apps/server/lib/keepling/application/sync/reference_model.ex |  | Corrected invalid Elixir string-literal typespec discovered during Task 1 compilation | open |  | 2026-09-01T05:55:08.453Z |  |
| 32 | KPL-02 | deviation | apps/server/lib/keepling/application/sync/reference_model.ex |  | Bound immutable command bytes to the outer durable mutation identity | open |  | 2026-09-01T05:55:08.534Z |  |
| 33 | KPL-02 | deviation | apps/server/lib/keepling/accounts/security_audit.ex |  | Extended the closed security-audit vocabulary for bounded device-grant facts | open |  | 2026-09-01T06:19:46.697Z |  |
| 34 | KPL-02 | deviation | apps/server/lib/keepling/accounts/device_grant.ex |  | Made repeated refresh replay fencing idempotent after the first generation advance | open |  | 2026-09-01T06:19:46.778Z |  |
| 35 | KPL-02 | deviation | apps/server/lib/keepling/accounts/device_grant.ex |  | Rejected extra public-client secret and namespace assertion fields | open |  | 2026-09-01T06:19:46.857Z |  |
| 36 | KPL-02 | deviation | apps/server/lib/keepling/application.ex |  | Compatibility configuration is validated before application supervision starts | open |  | 2026-09-01T07:13:47.287Z |  |
| 37 | KPL-02 | deviation | tooling/check-contracts.mjs |  | Compatibility contract gate rejects vacuous or malformed skew evidence | open |  | 2026-09-01T07:13:47.399Z |  |
| 38 | KPL-02 | deviation | tooling/test-compatibility.sh |  | Migration count probe uses explicit PostgreSQL inputs and numeric output isolation | open |  | 2026-09-01T07:13:47.518Z |  |
| 39 | KPL-02 | deviation | infra/caddy/Caddyfile |  | Preserved local HTTP proof without disabling production HTTPS automation | open |  | 2026-09-01T08:35:49.662Z |  |
| 40 | KPL-02 | deviation | tooling/verify-deploy.sh |  | Emitted the setup capability from the running release node | open |  | 2026-09-01T08:35:49.770Z |  |
| 41 | KPL-02 | deviation | tooling/verify-deploy.sh |  | Matched the established direct task-read response contract | open |  | 2026-09-01T08:35:49.877Z |  |
| 42 | KPL-02 | deviation | tooling/test-phase-2.sh |  | Corrected the Phase 2 sync lane to digest the tracked canonical sync vector | open |  | 2026-09-02T03:18:29.294Z |  |
| 43 | KPL-02 | unrun-verify | .planning/phases/KPL-02-synchronization-and-replaceable-server/deferred-items.md |  | Credentialed corrected restore/runtime and DNS cutover/rollback outer acceptance remains explicitly non-passing | open |  | 2026-09-02T03:18:34.980Z |  |
| 44 | KPL-03 | deviation | .npmrc |  | Forge required a hoisted pnpm linker and regenerated lock graph | open |  | 2026-09-02T18:23:00.601Z |  |
| 45 | KPL-03 | deviation | apps/desktop/forge.config.ts |  | Forge packaging was restricted to bundled runtime assets | open |  | 2026-09-02T18:23:00.686Z |  |
| 46 | KPL-03 | deviation | tooling/package-desktop.mjs |  | External app copying required verbatim framework symlinks | open |  | 2026-09-02T18:23:00.770Z |  |
| 47 | KPL-03 | deviation | apps/desktop/main/index.ts |  | Packaged process resources required direct Resources paths | open |  | 2026-09-02T18:23:00.852Z |  |
| 48 | KPL-03 | deviation | apps/desktop/main/index.ts |  | Same-profile ownership required an explicit Electron single-instance lock | open |  | 2026-09-02T18:23:00.938Z |  |
| 49 | KPL-03 | deviation | packages/contracts/openapi/keepling.yaml |  | Approved additive native-token namespace response expansion resolved in plan 03-02 | open |  | 2026-09-02T18:54:39.314Z |  |
| 50 | KPL-03 | deviation | apps/desktop/migrations/0001_initial.sql |  | Persisted storage-neutral synchronization metadata required for relaunch-safe lane replay | open |  | 2026-09-02T18:55:07.249Z |  |
| 51 | KPL-03 | deviation | apps/desktop/tsconfig.json |  | Allowed type-only repository-owned generated contract imports in desktop typechecking | open |  | 2026-09-02T18:55:07.362Z |  |
| 52 | KPL-03 | deviation | apps/desktop/main/adapters/credentials.ts |  | Loaded Electron safeStorage lazily so injected adapter proof runs outside Electron | open |  | 2026-09-02T18:55:07.476Z |  |
| 53 | KPL-03 | deviation | apps/desktop/main/adapters/credentials.ts |  | Added unsigned dogfood credential continuity disclosure for Settings presentation | open |  | 2026-09-02T18:55:07.591Z |  |

````json
[
  {
    "id": 1,
    "kind": "deviation",
    "phase": "01",
    "file": "apps/web/playwright.config.ts",
    "line": null,
    "description": "Playwright 1.62 required a harness contract so pre-feature --list discovery exits successfully",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T01:19:02.196Z",
    "resolved_at": null
  },
  {
    "id": 2,
    "kind": "deviation",
    "phase": "01",
    "file": "package.json",
    "line": null,
    "description": "openapi-typescript 7.13.0 required a root-only TypeScript 5.9.3 peer alongside the web TypeScript 6 toolchain",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T01:19:02.274Z",
    "resolved_at": null
  },
  {
    "id": 3,
    "kind": "deviation",
    "phase": "01",
    "file": "apps/web/e2e/support/stack.ts",
    "line": null,
    "description": "Disposable trust-auth PostgreSQL now rejects every non-loopback bind",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T01:19:02.349Z",
    "resolved_at": null
  },
  {
    "id": 4,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/priv/repo/migrations/.formatter.exs",
    "line": null,
    "description": "Retained the Phoenix generator migration formatter marker so the planned Mix test alias can run before migrations exist",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T01:31:44.014Z",
    "resolved_at": null
  },
  {
    "id": 5,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/test/architecture_test.exs",
    "line": null,
    "description": "Corrected architecture-test formatting found by the plan-level Mix formatter gate",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T01:31:44.083Z",
    "resolved_at": null
  },
  {
    "id": 6,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/web/e2e/support/stack.ts",
    "line": null,
    "description": "Made the real-stack E2E lifecycle executable before RED",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T02:10:59.290Z",
    "resolved_at": null
  },
  {
    "id": 7,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/priv/repo/seeds.exs",
    "line": null,
    "description": "Added an explicitly test-only closed-account seed",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T02:10:59.359Z",
    "resolved_at": null
  },
  {
    "id": 8,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/web/src/index.css",
    "line": null,
    "description": "Applied the approved accessible capture baseline",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T02:10:59.428Z",
    "resolved_at": null
  },
  {
    "id": 9,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/lib/keepling/adapters/postgres/command_store.ex",
    "line": null,
    "description": "Corrected double-encoded JSONB terminal results",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T02:10:59.498Z",
    "resolved_at": null
  },
  {
    "id": 10,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/mix.exs",
    "line": null,
    "description": "Added exact reviewed Argon2id and Tzdata dependencies required by the planned setup contract",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T02:33:05.090Z",
    "resolved_at": null
  },
  {
    "id": 11,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/priv/repo/migrations/20260830000200_add_closed_setup_and_timezone.exs",
    "line": null,
    "description": "Bound setup TTL and enforced permanent disablement plus future account credential/timezone fields",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T02:33:05.162Z",
    "resolved_at": null
  },
  {
    "id": 12,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/config/config.exs",
    "line": null,
    "description": "Disabled Tzdata remote updater to close the vulnerable transitive HTTP path",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T02:33:05.234Z",
    "resolved_at": null
  },
  {
    "id": 13,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/web/src/App.tsx",
    "line": null,
    "description": "Wired Inbox route reachability and exact acknowledgement reconciliation omitted from the plan file list",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T03:57:58.529Z",
    "resolved_at": null
  },
  {
    "id": 14,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/lib/keepling/domain/task.ex",
    "line": null,
    "description": "Added canonical nullable planned_on and deadline_on aggregate fields omitted from the plan file list",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T05:18:34.955Z",
    "resolved_at": null
  },
  {
    "id": 15,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/priv/repo/migrations/20260830000650_add_task_view_projections.exs",
    "line": null,
    "description": "Added durable projection schema and relevant command-store revision advancement omitted from the plan file list",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T05:48:12.063Z",
    "resolved_at": null
  },
  {
    "id": 16,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/web/src/App.tsx",
    "line": null,
    "description": "Wired authenticated shell list reachability and scoped the resulting legacy test ambiguity",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T05:48:12.168Z",
    "resolved_at": null
  },
  {
    "id": 17,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/lib/keepling/application/task_views.ex",
    "line": null,
    "description": "Removed an Ecto UUID dependency from the persistence-neutral application boundary",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T05:48:12.271Z",
    "resolved_at": null
  },
  {
    "id": 18,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/priv/repo/migrations/20260830000650_add_task_view_projections.exs",
    "line": null,
    "description": "Added exact Today move receipts and honest ambiguous-delivery retry after final trust review",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T05:48:12.377Z",
    "resolved_at": null
  },
  {
    "id": 19,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/web/src/commands/submission.ts",
    "line": null,
    "description": "Added explicit direct same-ID retry semantics required by lifecycle recovery",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T14:01:34.378Z",
    "resolved_at": null
  },
  {
    "id": 20,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/web/src/commands/submission.ts",
    "line": null,
    "description": "Classified infrastructure 5xx as unknown delivery rather than terminal rejection",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T14:01:34.472Z",
    "resolved_at": null
  },
  {
    "id": 21,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/server/lib/keepling_web/controllers/test_fault_controller.ex",
    "line": null,
    "description": "Halted authentication-before-acceptance injection before command dispatch",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T14:01:34.566Z",
    "resolved_at": null
  },
  {
    "id": 22,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/web/src/index.css",
    "line": null,
    "description": "Resolved the 1024px wide-shell overflow seam with a compact list column",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T16:02:33.525Z",
    "resolved_at": null
  },
  {
    "id": 23,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/web/src/features/tasks/TaskEditor.tsx",
    "line": null,
    "description": "Reconciled mounted editor state immediately after semantic undo acknowledgement",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T16:02:33.629Z",
    "resolved_at": null
  },
  {
    "id": 24,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "tooling/test-phase-1.sh",
    "line": null,
    "description": "Pinned disposable migration, compile, and ExUnit lanes to MIX_ENV=test",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-31T16:02:33.734Z",
    "resolved_at": null
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
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T02:22:51.183Z",
    "resolved_at": null
  },
  {
    "id": 30,
    "kind": "deviation",
    "phase": "KPL-01",
    "file": "apps/web/src/app/AuthProvider.tsx",
    "line": null,
    "description": "Plan-required repository lint gate required scoped ownership directives for pre-existing findings.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T02:22:51.264Z",
    "resolved_at": null
  },
  {
    "id": 31,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "apps/server/lib/keepling/application/sync/reference_model.ex",
    "line": null,
    "description": "Corrected invalid Elixir string-literal typespec discovered during Task 1 compilation",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T05:55:08.453Z",
    "resolved_at": null
  },
  {
    "id": 32,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "apps/server/lib/keepling/application/sync/reference_model.ex",
    "line": null,
    "description": "Bound immutable command bytes to the outer durable mutation identity",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T05:55:08.534Z",
    "resolved_at": null
  },
  {
    "id": 33,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "apps/server/lib/keepling/accounts/security_audit.ex",
    "line": null,
    "description": "Extended the closed security-audit vocabulary for bounded device-grant facts",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T06:19:46.697Z",
    "resolved_at": null
  },
  {
    "id": 34,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "apps/server/lib/keepling/accounts/device_grant.ex",
    "line": null,
    "description": "Made repeated refresh replay fencing idempotent after the first generation advance",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T06:19:46.778Z",
    "resolved_at": null
  },
  {
    "id": 35,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "apps/server/lib/keepling/accounts/device_grant.ex",
    "line": null,
    "description": "Rejected extra public-client secret and namespace assertion fields",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T06:19:46.857Z",
    "resolved_at": null
  },
  {
    "id": 36,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "apps/server/lib/keepling/application.ex",
    "line": null,
    "description": "Compatibility configuration is validated before application supervision starts",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T07:13:47.287Z",
    "resolved_at": null
  },
  {
    "id": 37,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "tooling/check-contracts.mjs",
    "line": null,
    "description": "Compatibility contract gate rejects vacuous or malformed skew evidence",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T07:13:47.399Z",
    "resolved_at": null
  },
  {
    "id": 38,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "tooling/test-compatibility.sh",
    "line": null,
    "description": "Migration count probe uses explicit PostgreSQL inputs and numeric output isolation",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T07:13:47.518Z",
    "resolved_at": null
  },
  {
    "id": 39,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "infra/caddy/Caddyfile",
    "line": null,
    "description": "Preserved local HTTP proof without disabling production HTTPS automation",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T08:35:49.662Z",
    "resolved_at": null
  },
  {
    "id": 40,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "tooling/verify-deploy.sh",
    "line": null,
    "description": "Emitted the setup capability from the running release node",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T08:35:49.770Z",
    "resolved_at": null
  },
  {
    "id": 41,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "tooling/verify-deploy.sh",
    "line": null,
    "description": "Matched the established direct task-read response contract",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-01T08:35:49.877Z",
    "resolved_at": null
  },
  {
    "id": 42,
    "kind": "deviation",
    "phase": "KPL-02",
    "file": "tooling/test-phase-2.sh",
    "line": null,
    "description": "Corrected the Phase 2 sync lane to digest the tracked canonical sync vector",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T03:18:29.294Z",
    "resolved_at": null
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
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T18:23:00.601Z",
    "resolved_at": null
  },
  {
    "id": 45,
    "kind": "deviation",
    "phase": "KPL-03",
    "file": "apps/desktop/forge.config.ts",
    "line": null,
    "description": "Forge packaging was restricted to bundled runtime assets",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T18:23:00.686Z",
    "resolved_at": null
  },
  {
    "id": 46,
    "kind": "deviation",
    "phase": "KPL-03",
    "file": "tooling/package-desktop.mjs",
    "line": null,
    "description": "External app copying required verbatim framework symlinks",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T18:23:00.770Z",
    "resolved_at": null
  },
  {
    "id": 47,
    "kind": "deviation",
    "phase": "KPL-03",
    "file": "apps/desktop/main/index.ts",
    "line": null,
    "description": "Packaged process resources required direct Resources paths",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T18:23:00.852Z",
    "resolved_at": null
  },
  {
    "id": 48,
    "kind": "deviation",
    "phase": "KPL-03",
    "file": "apps/desktop/main/index.ts",
    "line": null,
    "description": "Same-profile ownership required an explicit Electron single-instance lock",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T18:23:00.938Z",
    "resolved_at": null
  },
  {
    "id": 49,
    "kind": "deviation",
    "phase": "KPL-03",
    "file": "packages/contracts/openapi/keepling.yaml",
    "line": null,
    "description": "Approved additive native-token namespace response expansion resolved in plan 03-02",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T18:54:39.314Z",
    "resolved_at": null
  },
  {
    "id": 50,
    "kind": "deviation",
    "phase": "KPL-03",
    "file": "apps/desktop/migrations/0001_initial.sql",
    "line": null,
    "description": "Persisted storage-neutral synchronization metadata required for relaunch-safe lane replay",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T18:55:07.249Z",
    "resolved_at": null
  },
  {
    "id": 51,
    "kind": "deviation",
    "phase": "KPL-03",
    "file": "apps/desktop/tsconfig.json",
    "line": null,
    "description": "Allowed type-only repository-owned generated contract imports in desktop typechecking",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T18:55:07.362Z",
    "resolved_at": null
  },
  {
    "id": 52,
    "kind": "deviation",
    "phase": "KPL-03",
    "file": "apps/desktop/main/adapters/credentials.ts",
    "line": null,
    "description": "Loaded Electron safeStorage lazily so injected adapter proof runs outside Electron",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T18:55:07.476Z",
    "resolved_at": null
  },
  {
    "id": 53,
    "kind": "deviation",
    "phase": "KPL-03",
    "file": "apps/desktop/main/adapters/credentials.ts",
    "line": null,
    "description": "Added unsigned dogfood credential continuity disclosure for Settings presentation",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-02T18:55:07.591Z",
    "resolved_at": null
  }
]
````
