---
schema_version: 1
open_count: 14
waived_count: 0
fixed_count: 0
total_count: 14
last_updated: 2026-08-31T05:18:34.955Z
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
  }
]
````
