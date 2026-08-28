# Project Research Summary

## Key Findings

**Viability:** Very high as Jon's personal AI-native Things replacement; high but execution-sensitive as a polished open-source product; hosted convenience is plausible but deliberately unvalidated.

**Stack:** Phoenix/PostgreSQL modular monolith; React shared between online browser and Electron presentation; Electron main with durable SQLite/outbox; native SwiftUI iPhone; checked-in contracts/golden vectors; restrained design tokens; Hetzner/OpenTofu/Compose/Caddy reference deployment.

**Table stakes:** Immediate capture, calm Inbox/Today, explicit temporal semantics, keyboard-complete Mac use, native iPhone use, durable offline work, trustworthy sync, export, and verified recovery.

**Differentiator:** Things-like product quality plus safe first-party programmability, offline-native trust, open-source data ownership, and unusually good self-host/operator experience. "Has MCP" alone is insufficient because Todoist already has strong agent tooling.

**Watch out for:** Premature sync generalization, feature parity, collaboration drift, a third browser sync engine, shared-UI lowest-common-denominator design, unsafe agent bulk changes, unverified backups, library dogfooding, and overbuilt CI/operations.

## Implications for Roadmap

1. Prove one useful task lifecycle before formalizing broad synchronization.
2. Build the always-on recoverable server before primary clients depend on it.
3. Let Electron lead durable offline semantics, then prove the same contract independently on iPhone.
4. Add MCP only after application commands and recovery are stable.
5. Treat export, restore, compatibility, security, and exact-artifact evidence as product capabilities, not release-week chores.
6. Delay recurrence and broader Things parity until the core mutation island survives sustained dogfood.

## Sources

The complete dated source ledger, URLs, admitted/corrected claims, and unresolved questions are retained under `.planning/knowledge/snapshots/`. Start with `.planning/knowledge/INDEX.md`; do not treat this synthesis as a substitute for source-level provenance when making a time-sensitive or legal decision.

---
*Synthesized: 2026-08-28 from the exploratory gtd-app workspace*

