# Walking Skeleton — Keepling

**Phase:** 1
**Generated:** 2026-08-30

## Capability Proven End-to-End

> A signed-in personal-account user can capture one task in React, receive its stable identity and exact acknowledgement from Phoenix, and reload the task from PostgreSQL Inbox storage.

## Architectural Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Framework | Standalone Phoenix 1.8 modular monolith plus React 19/Vite browser app | Preserves the inward dependency direction and the existing browser scaffold while proving the real transport boundary (D-01..D-03). |
| Data layer | PostgreSQL 18 through Ecto/Postgrex, with pure domain values mapped to separate Ecto schemas | PostgreSQL is canonical and database constraints/transactions arbitrate durable identity, revision, and replay without coupling the domain to persistence (D-02, D-31..D-32). |
| Auth | Closed one-account setup; Argon2id password authentication; opaque hash-stored database session in a Secure, HttpOnly, host-only, SameSite=Lax cookie; CSRF plus origin/host checks | Implements the locked personal-account and browser-session policy without public registration, browser bearer storage, or copied server credentials (D-45..D-55). |
| Deployment target | Documented local full-stack run against PostgreSQL 18; the replaceable Hetzner target is Phase 2 | Phase 1 proves the whole application locally without pre-empting Phase 2 infrastructure and restore work. |
| Directory layout | `apps/server` for domain/application/adapters/Phoenix, `apps/web` for browser state/UI, `packages/contracts` for OpenAPI/vectors, `packages/design-tokens` for semantic roles | Matches `docs/architecture/REPOSITORY.md`; domain, persistence, wire, and view representations remain distinct. |

## Stack Touched in Phase 1

- [ ] Project scaffold (framework, build, lint, test runner)
- [ ] Routing — at least one real route
- [ ] Database — at least one real read AND one real write
- [ ] UI — at least one interactive element wired to the API
- [ ] Deployment — documented local full-stack run command

## Out of Scope (Deferred to Later Slices)

- Durable browser-offline mutation storage; Electron and iPhone own durable local projection/outbox behavior.
- Ordered multi-client synchronization, release-client compatibility, Hetzner deployment, and restore verification (Phase 2).
- Packaged Electron and native SwiftUI clients (Phases 3–4).
- MCP grants and agent-facing capability surfaces (Phase 5).
- Neutral export and final release evidence (Phase 6).
- Collaboration, hard deletion, recurrence, reminders, calendar/dashboard views, global Recent Changes, and full event sourcing.

## Subsequent Slice Plan

Each later phase adds one vertical slice on top of this skeleton without altering its architectural decisions:

- Phase 2: prove the ordered synchronization contract and replaceable, restore-verified server.
- Phase 3: add the durable offline Electron Mac daily loop.
- Phase 4: add the native durable offline SwiftUI iPhone daily loop.
- Phase 5: expose bounded agent access through the same semantic commands.
- Phase 6: prove portability, release evidence, and sustained dogfood readiness.
