---
phase: "KPL-01"
slug: "one-trustworthy-task"
status: verified
threats_open: 0
asvs_level: 1
block_on: high
register_authored_at_plan_time: true
created: "2026-08-31"
audited: "2026-08-31T23:39:12-04:00"
---

# Phase KPL-01 — Security

> ASVS L1 verification of the plan-time STRIDE register. Open high-severity threats block phase advancement; medium threats remain tracked but non-blocking.

## Trust Boundaries

| Boundary | Description | Data Crossing |
|---|---|---|
| Browser ↔ Phoenix | Authenticated API reads and semantic commands | Task content, session credentials, mutation identities |
| Phoenix ↔ domain/application | Transport invokes the inward semantic boundary | Validated commands and authoritative outcomes |
| Application ↔ PostgreSQL | Canonical state, receipts, conflicts, activity, sessions | Account-scoped durable records |
| Test fault boundary ↔ production | Response-loss simulation exists only in test | Synthetic failure controls; never production data |
| Operator/runtime ↔ release | Runtime configuration, setup, recovery, dependencies | Credentials, capability tokens, executable supply chain |

## Threat Register Summary

| Severity | Total | Mitigated | Accepted | Open |
|---|---:|---:|---:|---:|
| High | 60 | 60 | 0 | 0 |
| Medium | 22 | 22 | 0 | 0 |
| Low | 5 | 1 | 4 | 0 |
| **Total** | **87** | **83** | **4** | **0** |

### Mitigated entries (83)

`T-KPL01-SC`, `T-KPL01-01`, `T-KPL01-RT`, `T-KPL01-02`, `T-KPL01-03`, `T-KPL01-04`, `T-KPL01-05` (two plan entries), `T-KPL01-06`, `T-KPL01-07` (two plan entries), `T-KPL01-08`, `T-KPL01-09`, `T-KPL01-10`, `T-KPL01-11` (two plan entries), `T-KPL01-12` (two plan entries), `T-KPL01-13` (two plan entries), `T-KPL01-14` (two plan entries), `T-KPL01-15`, `T-KPL01-16`, `T-KPL01-17`, `T-KPL01-18` (two plan entries), `T-KPL01-19` (two plan entries), `T-KPL01-20` through `T-KPL01-44`, `T-KPL01-G20-01` through `T-KPL01-G20-04`, `T-KPL01-G21-01` through `T-KPL01-G21-04`, `T-KPL01-G22-01` through `T-KPL01-G22-03`, `T-KPL01-G23-01` through `T-KPL01-G23-05`, the Plan 24 repeat rows for `T-KPL01-41`, `T-KPL01-28`, and `T-KPL01-G20-04`, `T-KPL01-25-01` through `T-KPL01-25-03`, `T-KPL01-26-01` through `T-KPL01-26-04`, and `T-KPL01-27-01` through `T-KPL01-27-03`.

Verified controls include exact dependency/runtime gates, environment validation, inward architecture boundaries, account-scoped authorization, CSRF/origin checks, hash-only capabilities, idempotent receipts, persisted conflicts, HMAC cursors, test-only fault isolation, telemetry redaction, exact browser recovery, authoritative session reconciliation, restrictive endpoint CSP, bounded task-view query timeouts, and route-owned authentication continuation disposal. Evidence remains in the owning PLAN/SUMMARY files and implementation tests.

### Open entries

None.

## Accepted Risks Log

| Threat ID | Severity | Boundary | Accepted rationale |
|---|---:|---|---|
| `T-KPL01-24-SC` | low | Dependency supply chain | Plan 24 installed no package and changed no dependency; its security work used existing platform and repository capabilities. |
| `T-KPL01-25-SC` | low | Dependency supply chain | Plan 25 reused the already-installed Base UI package for the navigation drawer; no install occurred. |
| `T-KPL01-26-SC` | low | Dependency supply chain | Plan 26 reused the already-installed Base UI package for alert dialogs; no install occurred. |
| `T-KPL01-27-SC` | low | Dependency supply chain | Plan 27 was a mechanical source normalization and introduced no package or external service. |

These are explicit plan-time `accept` dispositions, not unreviewed implementation risks. The final audit verified that the stated dependency posture remained true.

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Blocking Open | Run By |
|---|---:|---:|---:|---:|---|
| 2026-08-31 | 70 | 67 | 3 | 1 | gsd-security-auditor |
| 2026-08-31 | 70 | 70 | 0 | 0 | gsd-security-auditor |
| 2026-09-01 | 87 | 83 mitigated + 4 accepted | 0 | 0 | gsd-security-auditor |
| 2026-08-31 verify-work refresh | 87 | 83 mitigated + 4 accepted | 0 | 0 | inline ASVS L1 recheck + full automated gate |

## Sign-Off

- [x] All threats have a disposition.
- [x] All accepted risks are explicitly logged with their plan-time rationale.
- [x] `threats_open: 0` confirmed.
- [x] `status: verified` set in frontmatter.

**Approval:** verified after Plans 01-24 through 01-27, review iteration 4, and final threat re-audit.

Fresh verify-work evidence at 2026-08-31T23:39:12-04:00 passed repository integrity, 109/109 server tests, contract drift, 147/147 browser-unit/component tests, 25/25 real-stack browser tests, privacy/production-isolation checks, and 3/3 automated UAT mappings. No implementation or threat-register change invalidated the existing ASVS L1 dispositions.
