# Project Research: Pitfalls

**Status:** imported synthesis of the 2026-08-28 exploratory study  
**Primary provenance:** all files under `.planning/knowledge/snapshots/`

| Pitfall | Early warning | Prevention / roadmap owner |
|---------|---------------|----------------------------|
| Sync consumes the product | Protocol abstractions grow before one useful task loop exists | Phase 1 proves a task end to end; Phase 2 formalizes only observed mutation needs |
| False exactly-once claims | Correctness assumes one network delivery | Idempotent effects plus exact mutation acknowledgement and retained outbox; Phase 2 |
| Shared UI becomes lowest common denominator | Platform-specific behavior leaks into shared components | Narrow facades, platform adapters, and deliberate SwiftUI duplication; Phases 3–4 |
| Hosted web content inside Electron breaks offline/trust | Desktop startup or UI requires server availability | Package local renderer assets; Electron main owns durable store; Phase 3 |
| PWA becomes mobile correctness baseline | iPhone capture depends on browser scheduling/storage behavior | Native SwiftUI and durable local outbox; Phase 4 |
| App Store clients are stranded by server deploy | Breaking wire/schema changes assume simultaneous releases | Additive contracts, tolerant readers, compatibility window, expand/migrate/contract; Phase 2 onward |
| Agent safety relies on prompt obedience | Raw patches or broad tools exist; confirmation is merely model text | Semantic tools, scopes, server-side binding, atomic preview/commit, audit/undo; Phase 5 |
| Backups provide false confidence | A job reports success but restoration is untested | Disposable restore verification and DR drills; Phase 2 and 6 |
| Self-hosting becomes consultancy | Multiple nominally supported topologies and hidden state | Portable contract plus one official Hetzner topology and explicit support boundary; Phase 2 |
| Dogfooding becomes library marketing | szTheory dependencies appear without product need | Dependency decision record and direct-dependency budget; every phase |
| CI becomes a second product | Slow redundant matrices run on every change | Layered evidence, path-aware leaves, shared-change fan-out, promotion gates; every phase |
| Brand looks derivative or generic AI | Blue box, red check, violet glow, sparkle/robot motifs | Keepling brand seed and dedicated identity tournament; UI phase |
| Telemetry leaks private content | Narrative logs include titles, notes, payloads, tokens, IDs | Closed structured events, redaction negative tests, safe diagnostic bundle; Phase 2 onward |
| Full event sourcing/CRDTs arrive by taste | Infrastructure is added before a replay/concurrency requirement | Snapshots, typed facts, ordered feed, explicit conflicts first; architecture review |

