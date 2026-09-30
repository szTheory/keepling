---
quick_id: 260930-jxm
mode: quick-full
status: planned
description: Make Phase 2 private-file mode checks portable across macOS and Linux so Gate B accepts correctly private image archives
must_haves:
  truths:
    - "Private-file mode checks return only the permission bits on supported macOS and Linux hosts."
    - "Gate B and related Phase 2 fixture checks pass for files created with mode 0600 under Linux GNU stat."
    - "All same-class mode-check callsites use explicit OS dispatch consistent with verify-host-replacement.sh."
  artifacts:
    - "tooling/verify-phase-2-gate-b.sh"
    - "tooling/run-phase-2-protected-acceptance.sh"
    - "tooling/phase-2-live-stage-actions.sh"
    - "tooling/test-phase-2-hosted-inputs.sh"
    - "tooling/test-phase-2-host-trust-approval.sh"
    - "tooling/test-phase-2-gate-b.sh"
  key_links:
    - "The permission-mode helper used by Gate B yields the exact numeric mode consumed by private_external_file."
    - "Fixture tests exercise the OS-specific stat behavior without invoking a live provider, DNS, SSH, or restore operation."
---

# Quick Task 260930-jxm Plan

## Objective

Correct the Linux Gate B archive privacy-check failure by replacing ambiguous `stat` fallback expressions at the identified Phase 2 callsites with explicit Darwin versus GNU/Linux dispatch, following `tooling/verify-host-replacement.sh`.

Purpose: Preserve the existing privacy guarantee while making the permission check portable on Linux CI.
Output: Consistent mode extraction across production and fixture scripts, plus hermetic regression evidence.

## Task 1: Use explicit platform dispatch in Phase 2 privacy checks

files:
  - `tooling/verify-phase-2-gate-b.sh`
  - `tooling/run-phase-2-protected-acceptance.sh`
  - `tooling/phase-2-live-stage-actions.sh`

action: Replace the `stat -f ... || stat -c ...` expressions with explicit Darwin and GNU/Linux branches, matching the `uname` dispatch pattern in `tooling/verify-host-replacement.sh`. Ensure the mode helper returns only the octal permission digits and propagates unsupported-platform/stat errors so Gate B compares the archive's actual mode to `600`. Preserve current acceptance behavior and all existing protections; do not add live provider, DNS, SSH, or restore execution.

verify:
  - `bash -n tooling/verify-phase-2-gate-b.sh tooling/run-phase-2-protected-acceptance.sh tooling/phase-2-live-stage-actions.sh`
  - `rg -n 'stat -f.*\|\| stat -c' tooling/verify-phase-2-gate-b.sh tooling/run-phase-2-protected-acceptance.sh tooling/phase-2-live-stage-actions.sh` returns no matches

done: Each production mode lookup uses explicit OS dispatch and a private 0600 image archive passes the Linux mode predicate.

## Task 2: Add hermetic regression coverage for Linux mode parsing

files:
  - `tooling/test-phase-2-gate-b.sh`
  - `tooling/test-phase-2-hosted-inputs.sh`
  - `tooling/test-phase-2-host-trust-approval.sh`

action: Update the fixture assertions' remaining mode lookups to use explicit Darwin and GNU/Linux dispatch. Add or extend fixture coverage to prove 0600 files and 0700 directories are recognized on GNU stat, and that an archive with a broader mode is rejected by Gate B. Keep test execution isolated to generated fixtures and local stub tools; do not call any live provider, DNS, SSH, or restore path.

verify:
  - `./tooling/test-phase-2-gate-b.sh`
  - `./tooling/test-phase-2-hosted-inputs.sh`
  - `./tooling/test-phase-2-host-trust-approval.sh`
  - `rg -n 'stat -f.*\|\| stat -c' tooling/test-phase-2-hosted-inputs.sh tooling/test-phase-2-host-trust-approval.sh` returns no matches

done: Hermetic Gate B and trust/input fixture tests prove private modes are recognized portably and reject non-private archive modes.

## Threat Model

| Boundary | Threat | Severity | Disposition | Mitigation |
|---|---|---:|---|---|
| Local archive and credential files → Phase 2 gate scripts | Incorrect permission parsing could allow a non-private archive or credential file through a trust check. | high | mitigate | Explicit OS dispatch returns only permission digits; fixture tests cover private and permissive modes on GNU stat. |
| Fixture test scripts → external infrastructure | A test could mutate external infrastructure while exercising trust checks. | medium | mitigate | Tests use generated local fixtures and stub executables; live provider, DNS, SSH, and restore actions are excluded. |

## Verification

Run the three targeted fixture scripts and syntax checks in this plan. Do not run live-host or restore acceptance lanes.

## Success Criteria

The Gate B image-archive privacy assertion passes on GNU/Linux for an exported 0600 archive, rejects a broader permission mode, and the related Phase 2 mode checks no longer use shell-fallback `stat` syntax.
