---
status: resolved
trigger: "Draft PR CI failed: retained blocked release manifest is rejected, but verify-release reports that verification did not pass (PASSED)."
created: 2026-09-30
updated: 2026-09-30
---

# Debug Session: Release Verdict Summary

## Symptoms

- **Expected behavior:** A blocked or otherwise non-passing release manifest exits non-zero and its final summary does not claim `PASSED`.
- **Actual behavior:** CI step `Prove the release verifier still refuses a vanished lane and a locally bound lane` fails on the retained `candidate-5` manifest. The verifier prints several `BLOCKED` lane failures and exits 1, then ends with `verification did not pass (PASSED)`.
- **Error evidence:** `.github/workflows/repository-integrity.yml` expects `verification did not pass; see the lane and artifact failures above` and rejects the contradictory `(PASSED)` summary.
- **Timeline:** Reproduced against the draft KPL-02 PR after GitHub Actions reported the `ci-contract` job failure.
- **Reproduction:** `node tooling/verify-release.mjs --manifest .planning/releases/candidate-5/release-manifest.json --offline`.

## Current Focus

bug_class: Bohrbug (deterministic aggregate-summary mismatch)
reasoning_checkpoint:
  hypothesis: overallVerdict stays PASSED for blocked lanes because only missing artifacts change it, while overallFailed correctly records all refusals.
  confirming_evidence:
    - candidate-5 exits 1 with BLOCKED lane errors and a PASSED aggregate verdict.
    - All failure paths update overallFailed; only missing-on-disk artifacts update overallVerdict.
  falsification_test: A blocked manifest without missing artifacts producing a non-PASSED aggregate under the original verifier would disprove the hypothesis.
  fix_rationale: Use the existing overallFailed decision and truthful generic non-pass summary required by the committed workflow; remove the unused partial aggregate rather than inventing precedence among mixed failures.
  blind_spots: Live attestation behavior is outside this offline summary change.
  candidate_causes:
    - code: partial aggregate verdict diverges from the authoritative failure flag.
    - config: workflow expects a summary different from the verifier output.
  and_gate: no; the stale verdict alone contradicts the exit status, regardless of the workflow assertion.
next_action: Parent orchestrator should commit and push the verified code fix, then inspect fresh PR CI; no live action or release claim is authorized by these fixture checks.

- **hypothesis:** `overallVerdict` is initialized to `PASSED` and is not updated for blocked lanes, so the aggregate failure line can contradict the non-zero exit and per-lane failures.
- **test:** Run the exact failing workflow guard against the retained candidate-5 manifest after the fix.
- **expecting:** The verifier still exits non-zero; it prints the workflow's truthful generic non-pass summary and never prints `verification did not pass (PASSED)`.
- **next_action:** No further local debugging; parent may push the verified fix commit and inspect fresh PR CI.

## Evidence

- timestamp: 2026-09-30 — GitHub job `ci-contract` failed at its blocked-manifest summary assertion; its earlier CI-contract and repository-integrity steps passed.
- timestamp: 2026-09-30 — Local reproduction exited 1 after printing `lane package-reproducible status=BLOCKED` and other blocked lanes, but ended with `verification did not pass (PASSED)`.

## Eliminated

- hypothesis: The release verifier accepts the blocked manifest or exits successfully.
  evidence: It reports every blocked lane and exits with code 1; only its aggregate summary is contradictory.

## Resolution

root_cause: The duplicate aggregate state defaults to PASSED and updates only for missing artifacts, so blocked lanes and other hard failures print a contradictory verdict.
oracle_type: specified (committed workflow guard and verifier contract)
fix: Removed the unused partial overallVerdict state and made every aggregate failure print the committed generic non-pass summary. Lane diagnostics and exit behavior are preserved.
files_changed: [tooling/verify-release.mjs]
verification:
  target_test: { result: pass, check: exact committed CI refusal guard including candidate-5 }
  mutation_check: { result: skipped, reason_if_skipped: no Stryker configured }
  no_op_deletion: { result: pass, deletion_justified_by_rca: true, reason: removes redundant inaccurate display state only; all refusal branches and non-zero exits remain }
  adjacent_tests: { result: pass, suites_run: [vanished-lane, local-unattested, not-produced-artifact, dangling-evidence, check-ci-contract, check-repository-integrity, git-diff-check] }
  revert_and_reconfirm: { result: pass, bug_returned_on_revert: true, fixed_on_reapply: true }
  guardrail_verdict: accepted

### Verification evidence

- Exact workflow step completed with `release-verifier guards intact`, exercising all four adversarial fixtures and the retained blocked candidate-5 manifest.
- Replacing the verifier with its HEAD bytes reproduced exit 1 plus `(PASSED)`; restoring the fix produced exit 1 plus the truthful generic non-pass summary.
- `node tooling/check-ci-contract.mjs` passed; repository integrity and all 13 governance assertions passed; `git diff --check` passed.
- No live attestation, deployment, provider, DNS, or release operation was performed.

## Prevention

- Why not caught earlier: the summary verdict was tracked separately from the authoritative failure flag, so blocked lanes could exit non-zero while the display state remained `PASSED`.
- Guard: `.github/workflows/repository-integrity.yml` asserts the retained candidate-5 manifest prints the generic non-pass summary and rejects the contradictory `(PASSED)` text.
