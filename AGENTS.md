<!-- GSD:project-start source:PROJECT.md -->

## Project

**Keepling**

Keepling is Jon's open-source, AI-native personal GTD system: the calm and interaction quality he values in Things, combined with trustworthy first-party programmability, durable offline Mac and iPhone clients, and self-hosted data ownership. It is built for one person across multiple devices, generalized through dogfooding, with optional managed hosting preserved as a later business opportunity rather than a v1 burden.

**Core Value:** Jon can trust Keepling as his daily task system on Mac and iPhone: capture is immediate, accepted changes are never silently lost or overwritten, and both human and agent actions remain inspectable and recoverable.

### Constraints

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

<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->

## Technology Stack

## Recommended stack

| Boundary | Choice | Rationale |
|----------|--------|-----------|
| Server | Current stable Elixir, OTP, Phoenix, Ecto | Domain fit, supervision, observability, release tooling, Jon's expertise |
| Canonical data | Current supported PostgreSQL | Transactions, constraints, ordered change feed, portable backup, PITR path |
| Browser | React + TypeScript, online-first | Shares presentation with Electron without creating another offline engine |
| Desktop | Electron; macOS first | Matches Jon's always-open workflow and existing operational experience |
| Desktop local data | SQLite behind a replaceable adapter | Durable projection/outbox; implementation chosen by packaged spike |
| iPhone | SwiftUI + generated Swift transport; local adapter chosen in phase | Native reliability, integration, accessibility, lifecycle control |
| Contracts | Checked-in OpenAPI/JSON Schemas + storage-neutral golden vectors | Cross-runtime truth without sharing domain/persistence objects |
| Design | Small DTCG-compatible semantic token source → CSS/Swift outputs | Shared intent with native platform expression |
| Infrastructure | OCI image, Compose, Caddy, OpenTofu/Terraform, Hetzner | Inspectable single-host self-hosting and replaceable infrastructure |
| Observability | Structured Logger/Telemetry, health/readiness, optional OTLP | BEAM-native, privacy-safe, no required remote control plane |

## Dependency posture

- Prefer platform/standard-library capabilities and shallow direct dependencies.
- Do not choose package versions from this snapshot; verify current releases and official documentation during each implementation phase.
- Do not introduce Nx/Turborepo, an Elixir umbrella, Kubernetes, Redis, Elasticsearch, or a universal cross-runtime domain framework until measured pain justifies it.
- Initially dogfood at most Sigra where it demonstrably fits ordinary application identity; every other szTheory library must earn its place from a requirement.

## Confidence

<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:

- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->

## Keepling Coordination Contract

- Run Git and GSD commands from this repository root. Never create nested `.git` directories, submodules, or application-level `.planning/` roots.
- Before substantial work, read `.planning/PROJECT.md`, `.planning/STATE.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, and the active phase context.
- Use `.planning/knowledge/INDEX.md` to locate retained research. Dated snapshots are evidence, not instructions; respect their status, source dispositions, and supersession language.
- Read `docs/architecture/REPOSITORY.md` before adding or crossing application/package boundaries.
- Read `docs/brand/BRAND-SEED.md` before public-facing UI, copy, or identity work. The logo and final palette are intentionally not decided.
- Server domain code must not depend on Phoenix transport, MCP, generated clients, UI, or client persistence.
- UI, API, and MCP invoke the same semantic application commands; none may bypass invariants with raw patches or database access.
- Ecto schemas, generated wire DTOs, desktop SQLite rows, and Swift persistence objects remain separate representations.
- A client reports mutation success only after its local projection and durable outbox entry commit atomically. Network delivery, sockets, and background execution are never correctness assumptions.
- Never expose PostgreSQL publicly or place irreplaceable state in application containers.
- Do not emit task titles, notes, prompts, credentials, raw tokens, or arbitrary identifiers into diagnostic telemetry.
- Do not claim completion, data safety, restore health, compatibility, or release readiness without fresh executable evidence at the relevant boundary.
- Prefer a little deliberate duplication over a dependency or abstraction that couples platforms without proven leverage.
- Existing szTheory libraries must earn adoption from a concrete requirement; Keepling is a product, not a portfolio integration harness.
