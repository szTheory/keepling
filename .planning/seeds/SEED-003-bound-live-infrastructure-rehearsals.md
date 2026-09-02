---
id: SEED-003
status: dormant
planted: 2026-09-01
planted_during: KPL-02 Plan 02-09 execution
trigger_when: when Plan 02-10 defines CI recovery drills, when a provider/bootstrap/recovery/DNS boundary changes, or when a live failure class recurs
scope: medium
---

# SEED-003: Bound live infrastructure rehearsals behind offline proof

## Why This Matters

Disposable live recovery rehearsals are valuable because mocks cannot prove real metadata service behavior, boot timing, provider ownership semantics, DNS propagation, or teardown. They are also slow, credentialed, and unsuitable as the normal debugging loop. Repeating them without converting each novel failure into deterministic local proof wastes time and makes external flakiness look like product progress.

Keepling should use a layered contract: every novel live-boundary failure first becomes an offline fixture and CI gate; the real provider/VM/DNS rehearsal remains a rare outer acceptance test. A live run must be change-triggered, single-attempt, fail-fast, teardown-proven, and incapable of reaching DNS until restore and semantic behavior pass.

## When to Surface

**Trigger:** Surface while executing Plan 02-10's CI and recovery-drill work. Revisit whenever provider, bootstrap, image-transfer, restore, semantic recovery, or DNS adapter behavior changes; when the same live failure class appears twice; or at a deliberate release/recovery checkpoint.

Do not schedule live rehearsals merely because time passed. Prefer a documented change/risk trigger. Promote a recurring failure to a hermetic fixture before authorizing another live candidate whenever the necessary evidence is locally available.

## Scope Estimate

**Medium.** Consolidate the existing deterministic fixture lanes into CI, document which changes activate the credentialed outer rehearsal, and keep secret-bearing live execution outside ordinary pull-request CI unless a deliberately protected environment is introduced. Avoid building a general network simulator unless recurring failures demonstrate leverage.

## Breadcrumbs

- `.planning/phases/KPL-02-synchronization-and-replaceable-server/02-10-PLAN.md` — owns repository-integrity CI and recovery-drill evidence.
- `tooling/verify-host-replacement.sh` — fail-closed outer rehearsal and offline dry-run entry point.
- `tooling/test-host-bootstrap.sh` — deterministic bootstrap and teardown contract.
- `tooling/test-host-bootstrap-diagnostics.sh` — bounded datasource, network, unit, package, and runcmd failure fixtures.
- `tooling/test-image-archive-contract.sh` — immutable archive identity fixtures.
- `tooling/test-remote-prepare-observability.sh` — remote preparation stages, bounded evidence, teardown, and DNS-unreachable fixtures.

## Notes

- Live infrastructure is evidence, not the development loop.
- Every authorized candidate is exactly one attempt; never hide uncertainty with automatic retries.
- Retain only bounded allow-listed diagnostics. Never commit credentials, personal identifiers, provider identifiers, IP addresses, private hostnames, or raw logs.
- A passing mock or provider fixture does not replace the rare real recovery acceptance test; it makes that test focused and interpretable.
