# Keepling

## What This Is

Keepling is Jon's open-source, AI-native personal GTD system: the calm and interaction quality he values in Things, combined with trustworthy first-party programmability, durable offline Mac and iPhone clients, and self-hosted data ownership. It is built for one person across multiple devices, generalized through dogfooding, with optional managed hosting preserved as a later business opportunity rather than a v1 burden.

## Core Value

Jon can trust Keepling as his daily task system on Mac and iPhone: capture is immediate, accepted changes are never silently lost or overwritten, and both human and agent actions remain inspectable and recoverable.

## Business Context

- **Customer**: Jon first; later, individuals who value calm GTD, open source, self-hosting, and safe automation.
- **Revenue model**: Complete open-source product; optional hosted operational convenience only after demonstrated demand.
- **Success metric**: Jon stops reaching for Things for the supported Mac-and-iPhone daily loop.
- **Strategy notes**: See `.planning/knowledge/snapshots/2026-08-28-current-worldview.md` and `.planning/knowledge/snapshots/2026-08-28-viability-and-open-source-operations.md`.

## Requirements

### Validated

- ✓ The browser task loop and Phoenix/PostgreSQL semantic boundary preserve task invariants, stable mutation results, explicit conflicts, and recoverable consequential actions — Phase KPL-01
- ✓ High-value server, contract, component, accessibility, responsive, recovery, and real-stack browser behavior can be accepted through deterministic automation with zero required human UAT checkpoints — Phase KPL-01

### Active

- [ ] A user can capture, clarify, schedule, complete, reopen, trash, restore, and undo personal tasks through a coherent GTD domain model.
- [ ] Mac and iPhone clients commit changes locally before reporting success and remain useful through network loss, server outage, termination, and relaunch.
- [ ] The server enforces authorization, invariants, idempotency, revisions, ordered synchronization, recoverable deletion, and explicit conflicts.
- [ ] Inbox and Today provide the first calm, polished daily loop, with complete keyboard interaction on Mac and deliberate native touch interaction on iPhone.
- [ ] MCP exposes bounded reads and narrow semantic writes through the same application commands, with least privilege, visibility, confirmation for high-impact changes, audit, and undo.
- [ ] The product provides neutral export and a supported self-host path whose backups are automatically restore-verified.
- [ ] Automated tests prove high-value behavior at every layer that can catch a distinct failure class while keeping required CI fast.

### Out of Scope

- Collaboration, assignments, shared workspaces, chat, and enterprise administration — these would change the product, authorization model, synchronization, and support burden.
- Billing, a hosted control plane, sales, and paid support — optional hosting is gated on personal success and demonstrated outside demand.
- Windows, Linux, and Android launch support — macOS and iPhone are the personal-success surfaces; later platforms require actual demand.
- Durable browser-offline synchronization — Electron and iPhone own the initial offline guarantee; browser access is online-first.
- Full event sourcing, CRDTs, microservices, Redis, Elasticsearch, Kubernetes, and bespoke orchestration — explicit commands, events, snapshots, and a change feed provide the needed properties with less machinery.
- In-product model hosting, agent memory, retrieval pipelines, or a general chat UI — Keepling supplies safe capabilities to external frontier models.
- Attachments, broad calendar integration, plugins, and multi-channel notification orchestration — defer until the core daily loop is dependable.

## Context

Things is the interaction benchmark, but its supported automation does not provide the remote, semantic capability boundary Jon needs for Codex, Claude Code, and similar tooling. Todoist already offers APIs and MCP, so the wedge is not merely "has MCP"; it is Things-like calm plus offline reliability, safe/reversible agent actions, open-source portability, and unusually good operator experience.

Jon brings Elixir/Phoenix, functional programming, DevOps/SRE, CI/CD, open-source, Electron, product/design, and AI-driven development experience. Existing szTheory projects provide useful DNA, particularly ExifCleaner's release automation and selected libraries, but Keepling must not become an integration showcase. Sigra is the only likely early dogfood dependency; Lockspire, Crosswake, Threadline, Accrue, Chimeway, Rindle, and Scrypath enter only when a concrete requirement earns them.

The selected architecture is a Phoenix/PostgreSQL modular monolith; a React surface shared between browser and Electron; a privileged Electron main process with local SQLite/outbox and narrow preload IPC; a native SwiftUI iPhone client with its own local persistence/outbox; and shared wire contracts, golden behavioral vectors, and semantic design tokens. Persistence, lifecycle, recovery UX, and native UI are deliberately platform-owned rather than forced into a universal abstraction.

The selected brand is Keepling: a small, dependable familiar that quietly keeps commitments safe. The identity is provisional beyond the name; logo, icon, typography refinements, and final color validation receive their own design phase and tournament.

## Constraints

- **Architecture**: Modular monolith with inward dependency direction — business rules remain independent of Phoenix transport, MCP, storage, Electron, React, and SwiftUI.
- **Canonical storage**: PostgreSQL on the server; no additional canonical data service without measured need.
- **Offline correctness**: Local projection and durable outbox commit atomically before success; retry is idempotent; outbox entries remain until exact acknowledgement.
- **Compatibility**: Server deploys must tolerate supported released clients; schema/API changes use expand, migrate, age out, contract.
- **Platforms**: macOS Electron and native iPhone are required for personal success; web is online-first; other platforms are deferred.
- **Operations**: One replaceable Hetzner VM is the reference target; app + PostgreSQL is the complexity ceiling until a requirement proves otherwise.
- **Recovery**: A backup is unhealthy until a disposable restore proves it; no irreplaceable state lives in containers or build directories.
- **Privacy**: No raw task titles, notes, prompts, tokens, or arbitrary identifiers in diagnostic telemetry; no default-on remote telemetry for self-hosters.
- **Quality**: Happy paths, errors, boundary conditions, recovery, accessibility, migrations, packaged artifacts, and physical-device behavior receive proportionate proof.
- **Dependencies**: Prefer BEAM/OTP, Phoenix, Ecto, PostgreSQL, browser/OS capabilities, small local code, and shallow dependency trees.
- **Design**: Native platform conventions and usability outrank pixel-identical cross-platform UI; motion conveys state and honors Reduce Motion.
- **Product**: Focused personal GTD only; feature breadth cannot erase the calm, deliberate experience.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Name the product Keepling | Distinctive coined name with trusted-steward and playful-familiar meaning; works across product extensions | — Pending formal clearance |
| Complete open source first | Maximizes trust, dogfooding, community, portfolio value, and low-friction iteration | — Pending validation |
| Optional hosted convenience later | Preserves a business path without premature tenancy, billing, support, or control-plane work | — Pending demand |
| One coordinating monorepo | Server, clients, contracts, tokens, infrastructure, and planning will co-evolve | ✓ Phase KPL-01 validated the server, web, contracts, tokens, and planning layout |
| Phoenix/PostgreSQL modular monolith | Strong domain integrity, operational simplicity, and fit with Jon's expertise | ✓ Phase KPL-01 validated the domain/application, Ecto, Phoenix, and PostgreSQL boundaries |
| React for browser and Electron presentation | Shares expensive presentation work while platform adapters retain storage and lifecycle ownership | ◐ Browser presentation validated in Phase KPL-01; packaged Electron proof remains Phase KPL-03 |
| Native SwiftUI iPhone client | Reliable offline capture and native integration are non-negotiable; PWA is not the correctness baseline | — Pending implementation |
| Electron Mac client | Recreates Jon's always-open Things workflow and leverages existing experience | — Pending implementation |
| Explicit commands/events/change feed, not full event sourcing | Retains auditability and functional semantics without event-store cost | — Pending implementation |
| Safe MCP adapter, not an embedded AI subsystem | External models do reasoning; Keepling deterministically enforces rules, scope, confirmation, and recovery | — Pending implementation |
| Hetzner/OpenTofu reference deployment | Lightweight, inspectable, replaceable self-hosting without AWS administrative surface | — Pending implementation |
| Build vertical tracer slices | Each phase must produce a user-observable capability and evidence, not an isolated technical layer | — Pending implementation |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition:**

1. Move shipped and proven requirements to Validated with the phase reference.
2. Move invalidated requirements to Out of Scope with the evidence.
3. Add genuinely new requirements without silently expanding existing ones.
4. Record consequential decisions and their observed outcomes.
5. Update What This Is if product reality has drifted.

**After each milestone:**

1. Review the entire document.
2. Recheck the Core Value and personal-success criterion.
3. Recheck business assumptions against actual usage and support load.
4. Audit deferred scope and reasons.
5. Update context, risks, and evidence links.

---
*Last updated: 2026-08-31 after Phase KPL-01*
