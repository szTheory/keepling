---
status: resolved
trigger: "Continue the authorized PR-branch reconciliation and follow the recommended fixes until intervention is needed."
created: 2026-09-30
updated: 2026-09-30
---

# Debug Session: Gate B private deploy proof failure

## Symptoms

- **Expected behavior:** The PR's source-bound native x64 image route reloads the exact tested image, completes the local deploy and synthetic recovery proof, and emits a valid sanitized result.
- **Actual behavior:** GitHub Actions `image-compose-deploy` fails after the image is built, exported, and reloaded.
- **Error:** `Gate B route refused: private verification step failed: /home/runner/work/keepling/keepling/tooling/verify-deploy.sh` (exit 2). Raw verifier output is correctly kept in the private runner temp workspace and is not present in public logs.
- **Timeline:** First observed on PR #3 after fixing the Linux archive mode check; run `36761607730`, job `110045301287`, checked out merge commit `fbb735c489c2a8aeb94eb9cd8de29a07cd65a32c` containing head `42e7997` and base `aae34ef`.
- **Reproduction:** Run the PR's `image-compose-deploy` workflow on `ubuntu-24.04`; the build/export/reload completes, then the private `verify-deploy.sh --local --recovery-output ...` invocation returns nonzero.

## Current Focus

reasoning_checkpoint:
  hypothesis: Linux refuses the host-owned 0600 credential to the release uid; independently Compose overwrites the requested restored database URL before release startup.
  confirming_evidence:
    - A Linux container with a UID 1001-owned 0600 fixture refused release UID 10001 read access; stdin delivered the same bytes successfully.
    - infra/compose/compose.yml unconditionally exports DATABASE_URL from the source secret after Compose applies the run environment override.
    - The existing full disposable local deploy/recovery check passes on Docker Desktop, whose bind-mount behavior masks the Linux ownership boundary.
  falsification_test: The restored login must read the same private credential as uid 10001 and query current_database() as keepling_recovery_proof; a source DB login or unreadable credential disproves success.
  fix_rationale: Stream private credential bytes through stdin and select a disposable database_url secret before release config loads, then assert actual connection identity.
  blind_spots: The original hosted raw log was not inspected; the corrected native Linux hosted rerun passed, as independently confirmed by the parent workflow.
  candidate_causes:
    - environment: Linux cross-uid bind-mount permissions
    - config: Compose secret export overrides run environment
    - code: earlier deploy smoke failure remains unexcluded on hosted runner
  and_gate: No for the observed Linux read failure; a second independent configuration defect permits false restore evidence on hosts where reading succeeds.
  next_action: Archive the confirmed resolution and commit the sanitized session and knowledge-base entry through GSD.

- **Test:** Full disposable deploy/recovery proof using the existing local release image, plus Linux uid permission reproduction and adjacent fixture suites.
- **Expecting:** Login proves the restored database explicitly; private credential stays 0600; the wrong credential remains rejected.
- **Next action:** None; hosted confirmation received and the resolution is archived.
- **Bug class:** Deterministic environment/configuration failure (Bohrbug); no per-test coverage available for SBFL.
- **Candidate causes:** environment — Linux file ownership prevents uid 10001 from reading the 0600 credential; config — Compose entrypoint replaces the restored DATABASE_URL; code — earlier smoke operation fails independently.
- **Knowledge base:** No matching retained resolution; MemPalace unavailable.

## Evidence

- timestamp: 2026-09-30 — `gh pr view 3` shows the latest check `image-compose-deploy` failed while `phase2-verified-image` succeeded.
- timestamp: 2026-09-30 — GitHub job log confirms checkout of merge commit `fbb735c489c2a8aeb94eb9cd8de29a07cd65a32c`, invocation of `verify-phase-2-gate-b.sh`, and only the sanitized failure naming `verify-deploy.sh`.
- timestamp: 2026-09-30 — `tooling/verify-phase-2-gate-b.sh` routes verifier output to a mode-0600 private log under a mode-0700 temporary root and reports only the failing executable.
- timestamp: 2026-09-30 — Local runner has Docker, Compose, `uuidgen`, and `jq`; this does not yet prove parity with Ubuntu CI.
- timestamp: 2026-09-30 — Linux container fixture with owner UID 1001, mode 0600, and release reader UID 10001 denied file reads; streaming the same bytes through stdin succeeded. No host credential was printed.
- timestamp: 2026-09-30 — Existing local full deploy/recovery proof passed, showing Docker Desktop did not expose the Linux credential ownership defect.
- timestamp: 2026-09-30 — A current_database() assertion added to the full recovery login failed against source database keepling, confirming the existing -e DATABASE_URL override and an attempted inside-eval override both fail to select the disposable restore before runtime config loads.
- timestamp: 2026-09-30 — Gate B fixture suite passed 22 cases (1 positive, 21 refused); synthetic recovery fixtures passed; shell syntax and diff whitespace checks passed.
- timestamp: 2026-09-30 — Corrected full disposable deploy/recovery proof exited 0; login/read/write/undo/restored_login were all true; private credential retained mode 0600. Positive restore login now also proves actual database identity. The negative credential check remains active.
- timestamp: 2026-09-30 — Parent workflow confirmed commit 4dd7e3c was pushed to gsd/kpl-02-plan28-follow-on-pr under existing authorization. GitHub Actions image-compose-deploy passed on the native Linux runner; phase2-verified-image and phase2-privacy also passed. The parent independently confirmed all required checks passed. This records sanitized check outcomes only; no PR merge or live infrastructure operation was performed.

## Eliminated

- hypothesis: Changing DATABASE_URL inside eval selects the restored database before application startup.
  evidence: The new current_database() assertion failed with the source database keepling; release runtime configuration had already captured the source URL before eval ran.
  timestamp: 2026-09-30

- **Hypothesis:** The current failure is still the exported archive's privacy/mode check.
  **Evidence:** The job now advances through the image build, archive export, archive contract verification, deletion/reload, and reaches the deploy verifier invocation.

## Resolution

root_cause: Host-owned mode-0600 credential is unreadable by the release UID on Linux; independently, Compose replaces the restored database URL with its source secret before release runtime configuration loads.
fix: Stream private credential through stdin; select a separate disposable database_url secret for each restore-login process; assert current_database() before both positive and negative authentication checks.
files_changed: [tooling/verify-deploy.sh]
oracle_type: specified (restored_login must refer to the restored database and a private credential must remain mode 0600)
verification:
  target_test: pass (full disposable local deploy/recovery proof; all five semantic booleans true and credential mode 0600)
  mutation_check: skipped (Stryker is not configured for shell scripts)
  no_op_deletion: pass (positive and negative authentication remain, database identity assertion added)
  adjacent_tests: pass (test-phase-2-gate-b.sh, test-prepare-synthetic-recovery.sh)
  revert_and_reconfirm: pass at isolated mechanism boundary (source-secret selection failed current_database assertion, corrected secret selection passed the same assertion; Linux file read refused, stdin transport accepted).
  hosted_linux: pass (parent independently confirmed image-compose-deploy, phase2-verified-image, phase2-privacy, and all required checks after push of 4dd7e3c)
  checkpoint_confirmation: accepted (parent supplied hosted environment confirmation and instructed archival)
  guardrail_verdict: accepted

## Prevention

- **Environment branch:** A host-owned 0600 credential crossed a UID boundary through a bind mount. Docker Desktop allowed the local proof to pass while native Linux refused the release UID. Delivering the credential through stdin removes that ownership dependency without weakening its host mode.
- **Configuration branch:** Compose populated DATABASE_URL from its source secret before release configuration loaded. Environment and inside-eval overrides therefore did not select the restore, and authentication alone could succeed against the source. Selecting the disposable secret before startup and asserting current_database() closes that false-positive path.
- **Why not caught:** The local deploy proof masked the Linux ownership difference, and its restored-login assertion did not previously verify the connected database. Native Linux image-compose-deploy caught the ownership failure.
- **Recurrence guard:** tooling/verify-deploy.sh recovery_fixture_login selects the disposable database secret, streams credentials through stdin, and asserts current_database() before authentication; prove_recovery_login_fixture retains positive and negative credential checks. Existing local proof and the confirmed hosted Linux check passed with these guards.
- **Semantic indexing:** MemPalace unavailable; knowledge-base.md is the durable fallback.
