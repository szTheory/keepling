---
schema_version: 1
open_count: 3
waived_count: 0
fixed_count: 0
total_count: 3
last_updated: 2026-08-31T01:19:02.349Z
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
  }
]
````
