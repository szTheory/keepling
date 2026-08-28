# Project Research: Architecture

**Status:** imported synthesis of the 2026-08-28 exploratory study  
**Primary provenance:** `.planning/knowledge/snapshots/2026-08-28-platform-and-architecture.md`

## System shape

```text
                           contracts + golden vectors
                              /        |        \
                             /         |         \
React web / Electron UI → command/query/sync API ← SwiftUI iPhone
             |                      |
Electron main: SQLite/outbox     Phoenix application boundary ← MCP
                                    |
                           domain + Postgres snapshots
                           mutation receipts/change feed
```

## Boundary rules

- Domain and application commands import no transport, MCP, UI, generated client, or client-persistence code.
- HTTP, synchronization, and MCP adapt semantic commands; they do not invent separate business rules.
- Ecto schemas are persistence details, not wire or client models.
- Shared React UI depends on a narrow client facade, never Electron APIs, SQLite, filesystem, or credentials.
- Electron main owns durable desktop data and privileged OS integration; preload exposes a small validated semantic IPC surface.
- SwiftUI reimplements client orchestration against the same contracts/vectors; it does not share cross-runtime domain code.
- Design tokens share meaning, not pixel-identical controls or layout.
- The sync feed, typed domain facts, durable security audit, diagnostic telemetry, and event-sourced reconstruction are distinct concepts.

## Build order

1. One real browser task lifecycle through Phoenix/PostgreSQL.
2. Formal mutation/change-feed vectors and replaceable reference deployment.
3. Electron Mac offline tracer, then daily-loop polish.
4. Native iPhone offline tracer, then native affordances.
5. MCP safety and representative-model evaluation.
6. Cross-client portability, recovery, compatibility, and release evidence.

