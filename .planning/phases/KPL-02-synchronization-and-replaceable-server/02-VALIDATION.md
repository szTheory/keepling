---
phase: "2"
slug: "synchronization-and-replaceable-server"
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-09-01"
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit with PostgreSQL integration; checked-in OpenAPI/JSON vectors; Compose, OpenTofu, Caddy, OCI, and pgBackRest validation lanes |
| **Config file** | `apps/server/mix.exs`, `apps/server/test/test_helper.exs`, `packages/contracts/`, and Phase 2 Wave 0 infrastructure fixtures |
| **Quick run command** | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling/application/sync test/keepling/adapters/postgres/sync_feed_test.exs'` |
| **Full suite command** | `./tooling/test-phase-2.sh --run` |
| **Estimated runtime** | Measure during Wave 0; keep per-task lanes under 30 seconds where possible |

---

## Sampling Rate

- **After every task commit:** Run the task's narrow ExUnit, contract, OpenTofu, Compose, or shell verification command.
- **After every plan wave:** Run `./tooling/test-phase-2.sh --run` with disposable PostgreSQL and local Compose.
- **Before `$gsd-verify-work`:** The full Phase 2 suite, credentialed restore proof, and host-replacement evidence must be green.
- **Max feedback latency:** 30 seconds for per-task sampling where possible; scheduled restore and live-infrastructure lanes report measured duration separately.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 02-W0-01 | Wave 0 | 0 | SRV-04, SRV-05 | T-02-sync | Atomic feed, exact receipts, conflicts, and reset semantics | property + PostgreSQL integration | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling/application/sync test/keepling/adapters/postgres/sync_feed_test.exs'` | ❌ W0 | ⬜ pending |
| 02-W0-02 | Wave 0 | 0 | SRV-06 | T-02-compat | Current/previous protocol representations remain executable | contract + migration matrix | `pnpm contracts:check && ./tooling/test-compatibility.sh` | ❌ W0 | ⬜ pending |
| 02-W0-03 | Wave 0 | 0 | DATA-02 | T-02-recovery | Restores are isolated, exact, and semantically verified | restore integration | `./tooling/verify-restore.sh --fixture newest-logical && ./tooling/verify-restore.sh --fixture latest-wal` | ❌ W0 | ⬜ pending |
| 02-W0-04 | Wave 0 | 0 | DATA-03, OPS-02 | T-02-host | Host replacement is source-driven and preserves no hidden canonical state | infrastructure E2E | `./tooling/verify-host-replacement.sh --dry-run` | ❌ W0 | ⬜ pending |
| 02-W0-05 | Wave 0 | 0 | OPS-01, OPS-03 | T-02-deploy | Private PostgreSQL, immutable digest, readiness, and safe interruption | container integration | `docker compose config && ./tooling/verify-compose.sh && ./tooling/verify-deploy.sh --local` | ❌ W0 | ⬜ pending |
| 02-W0-06 | Wave 0 | 0 | OPS-04, OPS-05 | T-02-operator | Stable operator verbs fail closed and diagnostics disclose no secrets | ExUnit + CLI black-box | `mix test test/keepling/application/ops && ./tooling/test-ops-cli.sh` | ❌ W0 | ⬜ pending |
| 02-W0-07 | Wave 0 | 0 | QUAL-02 | — | Required CI fan-out is deterministic and non-vacuous | CI self-test | `./tooling/check-ci-contract.mjs` | ❌ W0 | ⬜ pending |
| 02-W0-08 | Wave 0 | 0 | QUAL-05 | T-02-privacy | Hostile task content and identifiers never enter diagnostics | redaction integration + artifact scan | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling/telemetry_redaction_test.exs test/keepling/ops_redaction_test.exs'` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Add and verify the storage-neutral synchronization state-machine schema, reference reducer, property harness, and golden-vector runner.
- [ ] Add sync scenario support, deterministic failure injection, and real two-connection PostgreSQL concurrency fixtures.
- [ ] Add current/previous protocol simulators, frozen codec fixtures, and compatibility/migration matrix tooling.
- [ ] Extend the disposable PostgreSQL fixture for pgBackRest physical paths and add an isolated S3-compatible repository fixture.
- [ ] Add OCI image, Compose, Caddy, pgBackRest, OpenTofu, deploy, restore, and host-replacement validation commands.
- [ ] Add hostile diagnostic-bundle fixtures and anti-vacuity scans across logs, metrics, traces, JSON, manifests, stdout, and stderr.
- [ ] Add `./tooling/test-phase-2.sh --run` as the consolidated full-suite entry point.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Fresh Hetzner host replacement and DNS rehearsal | DATA-03, OPS-02, OPS-03 | Requires credentials, billable provider resources, and controlled DNS authority | Provision from source, deploy the tested digest, restore into the empty target, verify epoch rotation and user-level login/read/write/undo, then rehearse DNS cutover and record exact evidence. |
| Independent off-host backup mirror | DATA-02 | Requires two separately controlled provider accounts and recovery credentials | Prove encrypted backup retrieval from the primary and mirror accounts, then complete disposable restore verification from each without using app-container credentials. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies.
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify.
- [ ] Wave 0 covers all MISSING references.
- [ ] No watch-mode flags.
- [ ] Per-task feedback latency is under 30 seconds where possible and slower lanes record measured duration.
- [ ] `nyquist_compliant: true` set in frontmatter.

**Approval:** pending
