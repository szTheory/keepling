---
id: 261001-fik
status: complete
completed: 2026-10-01
commit: null
---

# Summary: Add a Fail-Closed Documentation-Only PR Fast Path

Added a shared Node-only pull request classifier and result verifier. The classifier accepts only root Markdown, `docs/**/*.md`, `.planning/**/*.md` outside release evidence, and direct `.planning/knowledge/templates/*.prompt.txt` files. It includes both sides of renames, verifies the changed-file count and exact event head/base revisions against GitHub's read-only API before and after pagination, and defaults to full CI when metadata, API access, paths, or revision identity is uncertain.

Repository, desktop, and iOS workflows retain unfiltered pull request and main-push triggers. The repository keeps its contract, integrity, host-fixture, and export checks always running; only the expensive Phase 2 lanes are gated. Desktop and iOS now have stable always-run summary checks that fail on classifier failure, unexpected skips, or failed lanes. Desktop promotion remains success-gated and never runs on a docs-only PR.

The CI contract runs classifier and summary self-tests and checks workflow gate wiring, summary names, required dependencies, and mutation cases. The existing main-branch image artifact job was retained and included in the docs-only heavy-lane accounting. Main's iOS privacy diagnostic check was changed from a shellcheck-warning template string to equivalent string concatenation so `actionlint` passes without ignoring diagnostics.

The always-run CI contract now downloads actionlint v1.7.12 from its official release, verifies the pinned Linux x64 SHA-256, and runs it against every workflow. This catches workflow expressions and embedded shell errors on every PR without adding a third-party action.

Protected `main` now requires `Desktop checks passed` and `iOS simulator checks passed`, with GitHub Actions App ID 15368, while retaining all nine existing required contexts. No source was pushed to `main`; the source will proceed through a pull request.

## Verification

- Exact `main` source assembly: `tooling/check-ci-contract.mjs` passed. The archive has no `.git` metadata, so only the temporary test copy of `tooling/test-phase-2.sh` was adjusted to bypass its repository-root lookup; the committed runner is unchanged.
- The official actionlint v1.7.12 Linux x64 release archive matched its pinned SHA-256, and the same-version macOS arm64 binary passed all six assembled workflow files. CI verifies the Linux archive digest before use.
- Classifier self-test passed: 11 cases.
- Summary verifier self-test passed: 8 cases.
- Node syntax checks passed for the classifier, result verifier, and CI contract checker.
- Privacy verifier self-test passed: 12 surfaces.
- GitHub read-back confirmed both new summary contexts and all existing required contexts remain configured on protected `main`.
- No source PR CI run has completed yet; merge remains gated on the required PR checks passing.

The changes were assembled from trusted `main` for the upcoming PR. Unrelated in-progress local Phase 2 workflow edits were preserved in the shared worktree and excluded from the PR source.
