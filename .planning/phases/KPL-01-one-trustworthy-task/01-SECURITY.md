---
phase: "KPL-01"
slug: "one-trustworthy-task"
status: verified
threats_open: 0
asvs_level: 1
block_on: high
register_authored_at_plan_time: true
created: "2026-08-31"
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

| Severity | Total | Closed | Open |
|---|---:|---:|---:|
| High | 59 | 59 | 0 |
| Medium | 11 | 11 | 0 |
| **Total** | **70** | **70** | **0** |

### Closed entries (70)

`T-KPL01-SC`, `T-KPL01-01`, `T-KPL01-RT`, `T-KPL01-02`, `T-KPL01-03`, `T-KPL01-04`, `T-KPL01-05` (two plan entries), `T-KPL01-06`, `T-KPL01-07` (two plan entries), `T-KPL01-08`, `T-KPL01-09`, `T-KPL01-10`, `T-KPL01-11` (two plan entries), `T-KPL01-12` (two plan entries), `T-KPL01-13` (two plan entries), `T-KPL01-14` (two plan entries), `T-KPL01-15`, `T-KPL01-16`, `T-KPL01-17`, `T-KPL01-18` (two plan entries), `T-KPL01-19` (two plan entries), `T-KPL01-20` through `T-KPL01-44`, `T-KPL01-G20-01` through `T-KPL01-G20-04`, `T-KPL01-G21-01` through `T-KPL01-G21-04`, `T-KPL01-G22-01` through `T-KPL01-G22-03`, and `T-KPL01-G23-01` through `T-KPL01-G23-05`.

Verified controls include exact dependency/runtime gates, environment validation, inward architecture boundaries, account-scoped authorization, CSRF/origin checks, hash-only capabilities, idempotent receipts, persisted conflicts, HMAC cursors, test-only fault isolation, telemetry redaction, exact browser recovery, authoritative session reconciliation, restrictive endpoint CSP, bounded task-view query timeouts, and route-owned authentication continuation disposal. Evidence remains in the owning PLAN/SUMMARY files and implementation tests.

### Open entries

None.

## Accepted Risks Log

No accepted risks. All plan-time dispositions are `mitigate`.

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Blocking Open | Run By |
|---|---:|---:|---:|---:|---|
| 2026-08-31 | 70 | 67 | 3 | 1 | gsd-security-auditor |
| 2026-08-31 | 70 | 70 | 0 | 0 | gsd-security-auditor |

## Sign-Off

- [x] All threats have a disposition.
- [x] No risks were silently accepted or transferred.
- [x] `threats_open: 0` confirmed.
- [x] `status: verified` set in frontmatter.

**Approval:** verified after Plan 01-24 remediation and re-audit.
