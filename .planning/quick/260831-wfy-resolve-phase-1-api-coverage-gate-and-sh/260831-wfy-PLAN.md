---
quick_id: 260831-wfy
mode: quick-full
status: complete
description: Resolve Phase 1 API coverage gate and shift all feasible human UAT into deterministic integration and end-to-end automation
must_haves:
  truths:
    - "The API coverage gate passes because Phase 1 explicitly declares that its Phoenix HTTP boundary is first-party and no external API or SDK is integrated."
    - "Every Phase 1 UAT checkpoint is mapped to executable browser, integration, or component evidence and the consolidated phase gate fails if that mapping disappears."
    - "Canonical Phase 1 UAT and verification report zero required human checkpoints only after the fresh consolidated gate passes."
  artifacts:
    - ".planning/phases/KPL-01-one-trustworthy-task/COVERAGE.md"
    - "tooling/check-phase-1-uat-coverage.mjs"
    - "tooling/test-phase-1.sh"
    - ".planning/phases/KPL-01-one-trustworthy-task/01-UAT.md"
    - ".planning/phases/KPL-01-one-trustworthy-task/01-VERIFICATION.md"
  key_links:
    - "tooling/test-phase-1.sh runs the UAT coverage checker and then the complete Playwright real-stack suite."
    - "The UAT coverage checker validates the canonical UAT evidence references against listed Playwright tests and repository files."
    - "Phase summary coverage metadata classifies every deliverable as automatically covered without validation errors."
---

# Quick Task 260831-wfy Plan

## Task 1: Establish executable automated-UAT traceability

files:
  - `.planning/phases/KPL-01-one-trustworthy-task/COVERAGE.md`
  - `tooling/check-phase-1-uat-coverage.mjs`
  - `tooling/test-phase-1.sh`
  - relevant `apps/web/e2e/*.spec.ts` files

action: Add the reasoned no-external-API declaration required by the coverage gate. Tag the existing real-stack browser cases that prove keyboard/accessibility continuity, responsive/reflow behavior, and password-manager-compatible authentication/recovery semantics. Add a deterministic checker that validates each automated UAT checkpoint has the required executable evidence, and wire it into the consolidated Phase 1 gate.

verify:
  - `node tooling/check-phase-1-uat-coverage.mjs`
  - `node /Users/jon/.claude/gsd-core/bin/gsd-tools.cjs check api-coverage.verify-pre .planning/phases/KPL-01-one-trustworthy-task --raw`

done: The API gate passes and removing or renaming any required UAT evidence makes the automated-UAT lane fail.

## Task 2: Replace manual checkpoint metadata with automated contract evidence

files:
  - `.planning/phases/KPL-01-one-trustworthy-task/01-08-SUMMARY.md`
  - `.planning/phases/KPL-01-one-trustworthy-task/01-14-SUMMARY.md`
  - `.planning/phases/KPL-01-one-trustworthy-task/01-19-SUMMARY.md`
  - `.planning/phases/KPL-01-one-trustworthy-task/01-25-SUMMARY.md`
  - `.planning/phases/KPL-01-one-trustworthy-task/01-26-SUMMARY.md`
  - `.planning/phases/KPL-01-one-trustworthy-task/01-27-SUMMARY.md`
  - `.planning/phases/KPL-01-one-trustworthy-task/01-UAT.md`
  - `.planning/phases/KPL-01-one-trustworthy-task/01-VERIFICATION.md`
  - `.planning/phases/KPL-01-one-trustworthy-task/01-VALIDATION.md`

action: Reframe Phase 1 acceptance around objective browser contracts that can be falsified in CI: accessibility-tree semantics, focus/keyboard behavior, live-region text, deterministic geometry/overflow/theme/media-query behavior, autocomplete/paste/reveal semantics, one-use recovery, and exact reauthentication replay. Correct invalid coverage kinds, attach passing evidence refs, and mark the canonical UAT entries as automated only after the fresh gate succeeds. Preserve real VoiceOver listening, subjective visual taste, and specific third-party password-manager observations as optional non-gating dogfood, without claiming those external experiences were automated.

verify:
  - classify every `*-SUMMARY.md` with `uat.classify-coverage` and require `all_auto_covered: true` with no errors
  - validate `01-UAT.md` through `tooling/check-phase-1-uat-coverage.mjs`

done: A new or resumed `$gsd-verify-work 1` has no required human checkpoint to present, and no historical coverage entry remains malformed.

## Task 3: Run final-tree proof and canonicalize completion evidence

files:
  - `.planning/quick/260831-wfy-resolve-phase-1-api-coverage-gate-and-sh/260831-wfy-SUMMARY.md`
  - `.planning/quick/260831-wfy-resolve-phase-1-api-coverage-gate-and-sh/260831-wfy-VERIFICATION.md`
  - `.planning/STATE.md`

action: Run the complete Phase 1 gate after the last source or evidence edit. Then rerun the API coverage check, automated-UAT checker, summary classifier audit, and GSD Phase 1 UAT-plus-verification completion predicate. Record exact counts and any remaining limitation.

verify:
  - `./tooling/test-phase-1.sh --run`
  - API coverage gate returns `block: false`
  - all phase summary coverage results are fully automated with zero errors
  - `gsd phase uat-passed KPL-01 --require-verification` returns `passed: true`

done: Fresh executable evidence supports the zero-required-human-UAT state and the quick task has a passed verification artifact.
