# Phase 1 Multi-Source Coverage Audit

All Phase 1 goal, requirement, research, and locked-context items are covered by the 19 plans. Deferred ideas and later-phase adapter proofs are exclusions, not gaps.

| SOURCE | ID / cluster | Feature or constraint | Plan | Status | Notes |
|---|---|---|---|---|---|
| GOAL | — | Authenticated React → Phoenix → PostgreSQL core task lifecycle | 01-05..01-19 | COVERED | 01-05 is the production tracer. |
| REQ | GTD-01 | Stable-identity Inbox capture | 01-05 | COVERED | |
| REQ | GTD-02 | Clarification and all supported fields/organization | 01-09, 01-10, 01-12 | COVERED | Temporal contract has one owner. |
| REQ | GTD-03 | Today intent independent of deadline | 01-12, 01-13 | COVERED | |
| REQ | GTD-04 | Timezone-aware Upcoming/deadline views | 01-12, 01-13 | COVERED | |
| REQ | GTD-05 | Idempotent complete/reopen | 01-14 | COVERED | Dedicated edge row/test. |
| REQ | GTD-06 | Trash/restore without hard deletion | 01-15 | COVERED | Dedicated edge row/test. |
| REQ | GTD-07 | Bounded revision-aware undo | 01-18 | COVERED | |
| REQ | SRV-01 | Personal account, setup, timezone, recovery, sessions | 01-05..01-08, 01-17 | COVERED | 01-06 owns setup-token issuance and account timezone. |
| REQ | SRV-02 | Shared semantic boundary plus web/API adapter proof | 01-02, 01-03, 01-05, 01-06, 01-09..01-18 | COVERED | Desktop/iPhone/MCP adapter proofs remain Phases 3–5. |
| REQ | SRV-03 | Stable idempotent result/error contracts | 01-05, 01-09..01-18 | COVERED | |
| REQ | WEB-01 | Real-stack browser lifecycle | 01-05, 01-08..01-19 | COVERED | |
| REQ | WEB-02 | Honest loading/error/auth/stale/conflict/retry | 01-08..01-19 | COVERED | |
| REQ | QUAL-01 | Layered/adversarial proof | 01-01..01-19 | COVERED | Executing Wave 0 precedes use. |
| RESEARCH | stack/tooling | Approved shallow dependencies and native Mix/pnpm orchestration | 01-01..01-04 | COVERED | |
| RESEARCH | architecture | Pure decisions, transaction interpreter, receipt gate, account day, same-origin auth, activity | 01-02, 01-03, 01-05..01-18 | COVERED | |
| RESEARCH | validation | Complete explicit Phoenix scaffold, real PostgreSQL concurrency/fault harness, generated contracts, browser evidence | 01-02..01-05, 01-17, 01-19 | COVERED | |
| RESEARCH | resolved questions | Bounds/equivalence, timezone, undo matrix, date classification, receipt classes, cursors | 01-05, 01-06, 01-09..01-13, 01-18 | COVERED | Section is marked RESOLVED. |
| RESEARCH | security | ASVS 5.0 L1 auth/session/CSRF/authz/idempotency/XSS/privacy controls | every plan | COVERED | Every threat block has ASVS mapping and high-severity block rule. |
| CONTEXT | D-01..D-03 | Monorepo, inward server boundary, React browser | 01-02..01-05 | COVERED | |
| CONTEXT | D-04..D-08 | Civil dates/account day/Today reasons/exclusions | 01-06, 01-12, 01-13 | COVERED | 01-06 owns account timezone; 01-12 owns task dates. |
| CONTEXT | D-09..D-13 | Routed workspace/capture/drafts/keyboard | 01-05, 01-08, 01-09, 01-12, 01-19 | COVERED | |
| CONTEXT | D-14..D-20 | Explicit Inbox and organization | 01-05, 01-09, 01-10 | COVERED | |
| CONTEXT | D-21..D-30 | Lists/order/cursors/focus/motion | 01-13, 01-14, 01-15, 01-19 | COVERED | |
| CONTEXT | D-31..D-39 | Identity/replay/revisions/merge/conflict/ack | 01-05, 01-09..01-18 | COVERED | |
| CONTEXT | D-40..D-44 | Bounded undo/Trash retention/native text undo | 01-15, 01-18 | COVERED | |
| CONTEXT | D-45..D-55 | Closed setup/password/recovery/sessions/grant seam | 01-05..01-08, 01-17 | COVERED | 01-06 has explicit setup-token and timezone operator commands; 01-07 has recovery issuance. |
| CONTEXT | D-56..D-63 | Atomic safe activity/separation/retention | 01-05, 01-11, 01-18 | COVERED | |

## Spec-less Probe Accounting — 18 Exact Rows

| Probe ID | Source row | Classification | Disposition | Exact destination |
|---|---|---|---|---|
| EDGE-01 | GTD-01 edge | unclassified edge | retain as explicit boundary matrix, no inferred extra product rule | 01-05 `must_haves.truths` + Task 2 behavior; 01-VALIDATION 01-05-T2 |
| EDGE-02 | GTD-02 edge | unclassified edge | resolve with versioned bounds/equivalence vectors | 01-09 Task 1 behavior; 01-10 Task 1 behavior |
| EDGE-03 | GTD-04 edge | unclassified edge | resolve with full date/DST/cursor truth tables | 01-12 Task 1 behavior; 01-13 Task 1 behavior |
| EDGE-04 | GTD-05 edge | unclassified lifecycle edge | separate complete/reopen state-machine row | 01-14 `must_haves.truths`; 01-VALIDATION 01-14-T1 |
| EDGE-05 | GTD-06 edge | unclassified lifecycle edge | separate Trash/restore preservation row | 01-15 `must_haves.truths`; 01-VALIDATION 01-15-T1 |
| EDGE-06 | GTD-07 edge | unclassified recovery edge | explicit supported/unsupported matrix and no-change classes | 01-18 Task 1 behavior |
| EDGE-07 | SRV-01 edge | unclassified auth edge | setup/recovery races, expiry boundaries, timezone ownership, reachability | 01-06 Tasks 1–2; 01-07 Task 1; 01-08 Task 2; 01-VALIDATION 01-06..08 |
| EDGE-08 | SRV-02 edge | concurrency/adapter edge | Phase 1 semantic boundary + web/API proof; later adapters own their proof | 01-02/01-03 architecture truths; 01-05 Task 2 done; ROADMAP/REQUIREMENTS traceability |
| EDGE-09 | SRV-03 edge | terminal-result edge | exact retained classes, mismatch, conflicts, before/after-commit loss | 01-RESEARCH resolved item 5; 01-05 Task 2; 01-17 Task 2 |
| EDGE-10 | WEB-01 edge | unclassified system edge | real-stack tracer and full lifecycle, no smoke-only completion claim | 01-05 Task 1; 01-19 Task 3 |
| UI-01 | Empty | explicit | authoritative zero only | 01-13 Task 2 behavior; 01-19 Task 1 behavior |
| UI-02 | Loading | explicit | named skeleton/progress; last-good background state | 01-13 Task 2 behavior; 01-19 Task 1 behavior |
| UI-03 | Error | explicit | distinct validation/auth/stale/conflict/unknown/retry copy | 01-08, 01-16, 01-17 tasks; 01-19 Task 1 |
| UI-04 | Populated | explicit | semantic stable rows/groups/pagination | 01-11 Task 2; 01-13 Task 2 |
| UI-05 | Partial | explicit | absent optionals and preserved accepted/draft values | 01-09 Task 2; 01-16 Task 2; 01-19 Task 1 |
| UI-06 | Zero/one/many | explicit | same headings/geometry plus explicit pagination | 01-13 Task 2; 01-19 Task 1 |
| UI-07 | Overflow | backstop | distinct structured marker and viewport suite | 01-19 Task 2 behavior `UI-BACKSTOP-OVERFLOW` |
| UI-08 | Long text | backstop | distinct structured marker and held-out long fixtures | 01-19 Task 2 behavior `UI-BACKSTOP-LONG-TEXT` |

## Exclusions Confirmed

- Durable browser-offline/outbox, native PKCE credentials, passkeys, global Recent Changes, MCP UI, hard deletion, recurrence/reminders, broader organization, and CRDT/event-sourcing work remain deferred exactly as CONTEXT.md specifies.
- Phase 1 does not claim desktop, iPhone, or MCP adapter completion for SRV-02.
