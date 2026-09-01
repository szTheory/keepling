---
id: SEED-001
status: dormant
planted: 2026-09-01
planted_during: KPL-02 Plan 02-09 execution
trigger_when: when planning safe agent access, automation, or developer and operator ergonomics
scope: unknown
---

# SEED-001: Provide a first-party, AI-friendly Keepling CLI

## Why This Matters

A first-party Keepling CLI could make the system easier for people and AI tools to use, automate, inspect, and troubleshoot without bypassing Keepling's semantic application commands or reaching into PostgreSQL. It should extend the product's intent—trustworthy first-party programmability and inspectable, recoverable agent actions—rather than become a second rules engine or an infrastructure-only utility.

The useful product question is broader than “add shell commands”: determine whether a user-facing CLI is the clearest composable interface for humans, scripts, and AI agents alongside the API and MCP adapter, while preserving least privilege, stable errors, idempotency, expected revisions, exact previews for high-impact changes, and privacy-safe output.

## When to Surface

**Trigger:** Surface when planning Phase 5 safe agent access, MCP integration, public automation surfaces, or broader developer/operator ergonomics. Surface earlier if dogfooding reveals repeated manual API work or AI tools need a dependable local command interface.

This is a trajectory signal, not Phase 2 scope: the current operator CLI is an architectural breadcrumb and potential shared convention, but it is not yet the proposed end-user task CLI.

## Scope Estimate

**Unknown.** First decide whether this is a thin adapter over the same authenticated semantic commands used by API/MCP or a larger product surface. Favor a thin adapter with generated/checked contracts and no independent domain behavior.

## Breadcrumbs

- `.planning/ROADMAP.md` — Phase 5 owns safe agent access and cross-adapter semantic behavior.
- `.planning/REQUIREMENTS.md` — `MCP-01..05` define least privilege, stable semantic mutations, ambiguity refusal, inspectability, and exact preview/commit safety.
- `.planning/phases/KPL-02-synchronization-and-replaceable-server/02-06-SUMMARY.md` — an existing privacy-safe operator CLI establishes stable output/exit patterns, but serves deployment and recovery operations rather than personal task use.
- `tooling/keepling-ops` — concrete operator-only CLI precedent; avoid conflating it with a future user/agent task CLI.
- `docs/brand/BRAND-SEED.md` — “Keepling MCP” is already a recognized product-family construction; evaluate how a CLI fits without unnecessary sub-branding.

## Notes

- Keep all business invariants in the existing inward domain/application boundary.
- API, MCP, UI, and any CLI should invoke the same semantic commands and authorization model.
- Design for calm, bounded, machine-readable output that remains useful to a person at a terminal.
- Revisit packaging, authentication, offline behavior, and supported-platform distribution only when this seed surfaces into planned work.
