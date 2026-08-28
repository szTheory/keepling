# Keepling Knowledge Index

This is the durable entry point for Keepling's retained second brain. GSD lifecycle files define current intent; normalized research files support planning; dated snapshots preserve the evidence and reasoning that produced those conclusions.

## Reading order for a new session

1. `../PROJECT.md` — current product truth and constraints.
2. `../STATE.md` — current workflow position and next action.
3. `../ROADMAP.md` and `../REQUIREMENTS.md` — intended delivery and traceability.
4. `../research/SUMMARY.md` — normalized research synthesis.
5. `../../docs/brand/BRAND-SEED.md` — provisional Keepling identity.
6. `../../docs/architecture/REPOSITORY.md` — repository and dependency boundaries.
7. `DECISIONS.md` and `OPEN-QUESTIONS.md` — decision history and unresolved items.
8. `snapshots/` — full dated research snapshots with source provenance.

## Knowledge layers

| Layer | Purpose | Mutation rule |
|-------|---------|---------------|
| `.planning/PROJECT.md` | Current product truth | Update at phase/milestone transitions |
| `.planning/STATE.md` | Current GSD position | Update through GSD workflows |
| `.planning/research/` | Planning-oriented synthesis | Refresh when evidence materially changes |
| `.planning/knowledge/DECISIONS.md` | Consequential decision history | Append/supersede; do not rewrite history |
| `.planning/knowledge/OPEN-QUESTIONS.md` | Unresolved choices and triggers | Resolve with evidence and link the decision |
| `.planning/knowledge/snapshots/` | Dated raw/high-signal exploration | Preserve; supersede explicitly rather than edit away |
| `.planning/knowledge/provenance/` | Original prompts and migration records | Immutable historical context |

## Snapshot catalog

| Snapshot | Status | Primary use |
|----------|--------|-------------|
| `2026-08-28-current-worldview.md` | Current working view | Product thesis, boundaries, engineering DNA |
| `2026-08-28-platform-and-architecture.md` | Current working view | Clients, sync, monorepo, tests, React/SwiftUI boundary |
| `2026-08-28-deployment-and-recovery.md` | Current working view | Hetzner reference topology and recovery contract |
| `2026-08-28-mcp-agent-safety-and-evals.md` | Research snapshot | MCP surface, authorization, safety, eval ladder |
| `2026-08-28-viability-and-open-source-operations.md` | Research snapshot | Market position, OSS model, hosted gates |
| `2026-08-28-brand-and-naming-brief.md` | Superseded in part | Naming criteria; Keepling is now selected |

## Provenance convention

Source-derived claims in retained snapshots use explicit dispositions:

- **admit** — evidence supports the claim within stated scope;
- **refute/correct** — evidence contradicts or narrows the claim;
- **abstain/unresolved** — evidence is insufficient or the choice remains a product decision.

"No result found" never means legal clearance. Dated web claims must be rechecked when a phase depends on them.

