# Project Research: Stack

**Status:** imported synthesis of the 2026-08-28 exploratory study  
**Primary provenance:** `.planning/knowledge/snapshots/2026-08-28-platform-and-architecture.md`, `2026-08-28-deployment-and-recovery.md`

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

Architecture choices: high. Exact library and version choices: intentionally deferred to phase research because they are time-sensitive.

