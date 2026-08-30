# Phase 1 Multi-Source Coverage Audit

All Phase 1 source items are covered by the seven execution plans. Deferred ideas and requirements assigned to later roadmap phases are excluded, not missing.

| SOURCE | ID / cluster | Feature or constraint | Plan | Status |
|---|---|---|---|---|
| GOAL | — | Authenticated React → Phoenix → PostgreSQL core task lifecycle | 01-01, 01-03..01-07 | COVERED |
| REQ | GTD-01 | Stable-identity Inbox capture | 01-01 | COVERED |
| REQ | GTD-02 | Clarification and full supported fields | 01-04 | COVERED |
| REQ | GTD-03 | Today intent independent of deadline | 01-05 | COVERED |
| REQ | GTD-04 | Timezone-aware Upcoming/deadline inspection | 01-05 | COVERED |
| REQ | GTD-05 | Idempotent complete/reopen | 01-06 | COVERED |
| REQ | GTD-06 | Trash/restore without hard deletion | 01-06 | COVERED |
| REQ | GTD-07 | Bounded revision-aware undo | 01-07 | COVERED |
| REQ | SRV-01 | Personal-account authentication and owned sessions | 01-01, 01-03 | COVERED |
| REQ | SRV-02 | One semantic command boundary for every adapter | 01-01, 01-04..01-07 | COVERED |
| REQ | SRV-03 | Stable idempotent mutation result/error contracts | 01-01, 01-06, 01-07 | COVERED |
| REQ | WEB-01 | Real-stack browser lifecycle | 01-01, 01-04..01-06 | COVERED |
| REQ | WEB-02 | Honest loading/error/auth/stale/conflict/retry states | 01-03..01-07 | COVERED |
| REQ | QUAL-01 | Deterministic layered and adversarial proof | 01-01, 01-02, 01-07 | COVERED |
| RESEARCH | stack/tooling | Pinned Phoenix/Ecto/PostgreSQL/React stack, ExUnit/StreamData/Vitest/Playwright/axe, root native-tool scripts | 01-01, 01-02 | COVERED |
| RESEARCH | architecture | Pure decisions, transactional interpreter, account-scoped receipt gate, narrow merge, account day, same-origin sessions, append-only activity | 01-01, 01-03..01-07 | COVERED |
| RESEARCH | validation | Real PostgreSQL concurrency/fault harness, contracts/vectors, browser state/evidence matrix, architecture and telemetry guards | 01-01, 01-07 | COVERED |
| RESEARCH | security | ASVS L1 auth/session/CSRF/authorization/idempotency/XSS/abuse/privacy controls | 01-01, 01-03, 01-06, 01-07 | COVERED |
| CONTEXT | D-01..D-03 | Monorepo and inward modular-monolith/browser boundaries | 01-01 | COVERED |
| CONTEXT | D-04..D-08 | Civil dates, account timezone/day, Today reasons and temporal exclusions | 01-05 | COVERED |
| CONTEXT | D-09..D-13 | Responsive routed workspace, quick capture, draft/dirty/keyboard behavior | 01-01, 01-04, 01-07 | COVERED |
| CONTEXT | D-14..D-20 | Explicit Inbox, projects/tags and archive rules | 01-01, 01-04 | COVERED |
| CONTEXT | D-21..D-30 | List ordering, views, cursors, focus, motion and exclusions | 01-05, 01-07 | COVERED |
| CONTEXT | D-31..D-39 | Mutation identity, replay, revisions, merge, conflicts and acknowledgements | 01-01, 01-06 | COVERED |
| CONTEXT | D-40..D-44 | Bounded semantic undo, Trash retention, native text undo | 01-07 | COVERED |
| CONTEXT | D-45..D-55 | Closed setup, password auth, recovery, sessions, CSRF, rate limits and grant seam | 01-01, 01-03 | COVERED |
| CONTEXT | D-56..D-63 | Atomic append-only task activity, safe rendering/pagination/separation/retention | 01-01, 01-04, 01-07 | COVERED |

## Spec-less probe accounting

- All 18 edge-probe rows are represented in plan `must_haves`: category-specific rows are explicit truths/backstops, and the nine unclassified rows remain flagged assumptions.
- The two-stage prohibition recall retained three bespoke product prohibitions; each is descriptor-less, `status: unverified`, and `flagged: true` in plan must-haves. Canon security items are handled by the ASVS threat models and were not minted again.
- The UI probe's six explicit state categories and two evidence backstops are lifted into Plans 01, 03, 04, 05, 06, and 07.
