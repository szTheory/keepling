---
phase: quick
plan: 260930-jxm
subsystem: infra
tags: [shell, linux, macos, permissions, gate-b]
requires: []
provides:
  - Explicit Darwin and Linux private-file mode lookup for Phase 2 checks
  - Hermetic Gate B coverage for rejecting a 0644 image archive
affects: [phase-2-gate-b, phase-2-acceptance, phase-2-host-trust]
tech-stack:
  added: []
  patterns: [OS-dispatched stat mode lookup]
key-files:
  created: []
  modified:
    - tooling/verify-phase-2-gate-b.sh
    - tooling/run-phase-2-protected-acceptance.sh
    - tooling/phase-2-live-stage-actions.sh
    - tooling/test-phase-2-gate-b.sh
    - tooling/test-phase-2-hosted-inputs.sh
    - tooling/test-phase-2-host-trust-approval.sh
decisions:
  - "Unsupported operating systems fail closed when reading permission modes."
metrics:
  duration: 12min
  completed: 2026-09-30
status: complete
---

# Quick Task 260930-jxm Summary

**Phase 2 private-file checks now use explicit Darwin/GNU stat dispatch, and Gate B fixtures reject a permissive image archive.**

## Accomplishments

- Replaced ambiguous `stat` fallback expressions with explicit Darwin and Linux branches in all three production scripts.
- Updated hosted-input and host-trust fixture mode assertions to use the same OS dispatch.
- Added a Gate B regression case proving a 0644 exported archive is refused; existing fixtures verify 0600 files and 0700 directories.

## Verification

- `bash -n tooling/verify-phase-2-gate-b.sh tooling/run-phase-2-protected-acceptance.sh tooling/phase-2-live-stage-actions.sh` — passed.
- Production and fixture `rg` scans for `stat -f.*\|\| stat -c` — no matches.
- `./tooling/test-phase-2-gate-b.sh` — passed, 22 cases, 0 external calls.
- `./tooling/test-phase-2-hosted-inputs.sh` — passed.
- `./tooling/test-phase-2-host-trust-approval.sh` — passed, 0 external calls.

The Gate B fixture forces its Linux branch and maps the GNU `stat -c %a` invocation to the host's BSD `stat` implementation, so the dispatch and numeric permission check are exercised on this macOS runner.

## Task Commits

1. **Task 1: Use explicit platform dispatch in Phase 2 privacy checks** — `6b4ee8e`.
2. **Task 2: Add hermetic regression coverage for Linux mode parsing** — `6b4ee8e`.

## Deviations from Plan

The Gate B fixture's `uname` stub was extended to distinguish `-s` from `-m`, and a local `stat` adapter was added so the fixture can exercise its GNU-stat branch on the macOS host. No live provider, DNS, SSH, cloud, acceptance, restore, or teardown operation was run.
