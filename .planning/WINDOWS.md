---
schema_version: 1
open_count: 28
waived_count: 0
fixed_count: 4
total_count: 32
last_updated: 2026-09-01T05:55:08.534Z
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
  }
]
````
