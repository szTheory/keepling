# Open Questions

These are deliberate decisions, not forgotten work. Resolve each in the phase where the answer becomes consequential.

| ID | Question | Recommended decision point | Evidence needed |
|----|----------|----------------------------|-----------------|
| OQ-001 | What exact temporal fields distinguish Today intent, defer/start, scheduled date, deadline, and reminder? | Phase 1 discussion | Things workflow inventory and concrete user scenarios |
| OQ-002 | What is the minimum supported Things-parity loop for Jon? | Phase 1 discussion | One-week workflow diary and migration sample |
| OQ-003 | Which license and contributor/trademark policy should Keepling use? | Before public repository launch | Distribution-specific legal review and hosted strategy |
| OQ-004 | Is iOS 17+ the correct minimum and is SwiftData sufficient? | Phase 4 research/planning | Current Apple support expectations and migration spike |
| OQ-005 | Which Electron SQLite adapter survives packaging, migration, and performance proof? | Phase 3 research/spike | Pinned Electron runtime experiment and packaged artifact |
| OQ-006 | What authentication/device-token model safely fences logout, account switch, and revocation? | Phase 1–2 | Threat model and client lifecycle scenarios |
| OQ-007 | What released-client compatibility window must the server honor? | Before first downloadable/TestFlight build | Dogfood cadence and upgrade behavior |
| OQ-008 | What at-rest threat model applies to task text and outbox data? | Phase 2–4 | Device threat assumptions and recovery cost |
| OQ-009 | What RPO/RTO and retention justify PITR versus verified logical backups? | Phase 2 | Personal tolerance, data-change rate, restore drill timings |
| OQ-010 | When should Apple Developer enrollment and Electron signing occur? | Before continuous device/public distribution requires it | Provisioning friction and signed-only platform capabilities |
| OQ-011 | Is Keepling legally and operationally clear across trademarks, domains, GitHub, App Stores, npm, and Hex? | Before public reveal/repository publication | Comprehensive clearance ledger and counsel review |
| OQ-012 | Which representative MCP hosts/models define the real-model eval matrix? | Phase 5 | Jon's actual tool usage and protocol support |

