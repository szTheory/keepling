# Decision Log

This log retains why consequential choices made sense at the time. A new decision supersedes an old one explicitly; history is not silently rewritten.

| ID | Date | Decision | Rationale | Status / revisit trigger |
|----|------|----------|-----------|----------------------------|
| D-001 | 2026-08-28 | Build Jon's AI-native Things replacement as a complete open-source product | Personal value does not depend on market adoption; open source improves trust, portfolio value, and feedback | Active; revisit licensing before public release |
| D-002 | 2026-08-28 | Keep optional managed hosting as later operational convenience | Preserves upside without premature tenancy, billing, sales, support, or control-plane work | Deferred until sustained outside demand |
| D-003 | 2026-08-28 | Exclude collaboration and enterprise work management | Those needs would change product identity, authorization, sync, UI, and support | Locked for current product; requires explicit new-product decision |
| D-004 | 2026-08-28 | Use Phoenix/PostgreSQL modular monolith | Strong fit for domain integrity, operations, solo ownership, and Jon's expertise | Revisit only with measured constraint |
| D-005 | 2026-08-28 | Supersede PWA-first with Electron Mac + native SwiftUI iPhone | Durable offline/native integration and Jon's actual daily workflow outweigh distribution convenience | Active |
| D-006 | 2026-08-28 | Keep React browser access online-first and share presentation with Electron | Avoids a third offline sync engine while retaining universal access and UI leverage | Revisit after primary clients are reliable |
| D-007 | 2026-08-28 | Use explicit commands/events/change feed rather than full event sourcing | Preserves typed facts, audit, and CQRS value without event-store complexity | Revisit if replay/temporal requirements emerge |
| D-008 | 2026-08-28 | Treat MCP as a safe adapter over application commands | Models should not bypass deterministic authorization, invariants, confirmation, idempotency, audit, or recovery | Active |
| D-009 | 2026-08-28 | Use one replaceable Hetzner/OpenTofu reference deployment | Lightweight, inspectable, portable, and lower administrative surface than AWS | Recheck provider/pricing at provisioning phase |
| D-010 | 2026-08-28 | Use one coordinating monorepo with no nested Git repositories | Cross-client contracts and planning co-evolve; one GSD root prevents split context and commit ambiguity | Revisit only when a component has a genuinely independent lifecycle |
| D-011 | 2026-08-28 | Name the product Keepling | Best fit for the trusted-steward × playful-familiar territory and natural product-family language | Working name; formal legal/namespace clearance open |
| D-012 | 2026-08-28 | Concentrate brand expression while keeping product UI platform-native | Native feel is part of the value; brand should distinguish without overwhelming daily use | Refine in dedicated UI/brand phase |

