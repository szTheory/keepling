# Deferred Items

- `mix deps.get --check-locked` reports existing security advisories for transitive `hackney 1.25.0` (including CVE-2026-47071). Plan 02-01 adds only test-scoped `stream_data 1.4.0`; changing the existing `tzdata`/`hackney` dependency path is outside this plan and requires separate dependency review.

## Plan 02-09 live acceptance deferral

Plan 02-09 remains incomplete. Its bounded live rehearsal sequence proved source-driven provider creation, exact state/ownership reconciliation and teardown, ordered network bootstrap, protected artifact transfer, and—during an earlier disposable rehearsal—dual-store restoration, synchronization-epoch rotation, and user-level login/read/write/edit/undo behavior. Every disposable resource graph was removed, remote disposable state was emptied, and the DNS mutation gate remained fail-closed whenever an earlier candidate gate failed.

The final integrated acceptance chain has not yet proved restore/runtime semantics followed by authoritative and recursive DNS cutover, propagation, rollback, and rollback propagation using the corrected image-identity contract. A hard run cap now defers those external gates; no further live candidate belongs to this execution sequence. Plan 02-09 must not gain a summary or completion claim until fresh outer-boundary evidence exists.

The local contract now distinguishes the OCI manifest descriptor digest from the Docker config ImageID, binds both Docker-save and OCI archive views to the same config and root filesystem layers, and uses a bounded exactly-one engine inventory delta only as the inspected target selector. Plan 02-10 should make these hermetic archive, image-engine, bootstrap, state/ownership, teardown-first, and DNS-unreachable regressions required CI inputs under SEED-003. Each novel live-boundary failure becomes an offline fixture and CI gate; paid provider/DNS rehearsal remains a rare, single-attempt outer acceptance test rather than a debugging loop.
