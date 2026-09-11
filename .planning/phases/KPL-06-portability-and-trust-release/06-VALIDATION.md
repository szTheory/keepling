---
phase: "6"
slug: "portability-and-trust-release"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-09-11"
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `06-RESEARCH.md` § Validation Architecture.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `mix test` (ExUnit) for server/export; Vitest for desktop/web; XCTest for iOS; standalone Node scripts (assertion-by-exit-code) for `tooling/*.mjs` gates — all four already established, none new |
| **Config file** | `apps/server/mix.exs`; `apps/desktop/vitest.config.ts`; no config file for `tooling/` scripts |
| **Quick run command** | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling/application/export_test.exs'` |
| **Full suite command** | `node tooling/verify-release.mjs --manifest .planning/releases/<tag>/release-manifest.json` |
| **Estimated runtime** | ~60s quick · release/soak gates are long-pole (minutes to days for SC5) |

---

## Sampling Rate

- **After every task commit:** Run the unit/integration test file for that task.
- **After every plan wave:** Run `node tooling/verify-release.mjs` (once it exists) plus the existing full desktop/server/iOS phase gates.
- **Before `/gsd-verify-work`:** `node tooling/verify-trust-soak.mjs --gate` (SC5) and a green `verify-release.mjs` (SC2/SC3).
- **Max feedback latency:** 120 seconds for per-task sampling.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| TBD | TBD | TBD | DATA-01 | — | Export bundle contains only supported, redacted user history | integration | `./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix test test/keepling/application/export_test.exs'` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | DATA-01 | — | Bundle is readable without Keepling internals | tooling | `node tooling/verify-export-reader.mjs <bundle-path>` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | QUAL-02 | — | No lane is silently skipped or `continue-on-error` | CI | `node tooling/check-ci-contract.mjs` | ✅ | ⬜ pending |
| TBD | TBD | TBD | QUAL-03 | — | Promotion uses the exact tested revision/artifact digest | tooling | `node tooling/verify-release.mjs --manifest <path>` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | QUAL-04, QUAL-05 | — | Cross-client release evidence is complete and revision-bound | tooling | `node tooling/verify-release.mjs --manifest <path>` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | SRV-02 | — | Electron + iPhone cross-adapter legs pass, never skip | tooling | `node tooling/verify-cross-adapter-phase.mjs` | ✅ | ⬜ pending |

*Task IDs are filled in by the planner; rows above are the requirement-level contract each plan must satisfy.*

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `apps/server/test/keepling/application/export_test.exs` — covers DATA-01
- [ ] `tooling/verify-export-reader.mjs` — independent reader, D-07 lane 3
- [ ] `tooling/verify-release.mjs` + `tooling/release-lanes.json` — D-12
- [ ] `tooling/trust-lanes/{oracle,invariants,chaos,census}.mjs` + `tooling/verify-trust-soak.mjs` — D-45..D-51
- [ ] Migration for `last_used_at` tracking (RESEARCH.md Pitfall 5) if D-38's scope includes it after the checkpoint decision

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Sustained Mac+iPhone dogfood period with no unresolved data-loss, silent-overwrite, or recovery-severity defects | SC5 / QUAL-05 | Requires real elapsed calendar time and real human usage; the census/oracle lanes measure it but cannot manufacture it | Run the supported loop daily on Mac and iPhone; `node tooling/verify-trust-soak.mjs --gate` reports the accumulated census and any open recovery-severity defect |
| Apple notarization acceptance of the signed package | SC4 | Depends on Apple's notary service, an external system outside the repo | Submit via the release workflow; the packaged smoke gate recomputes the digest and fails if signing altered it |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
