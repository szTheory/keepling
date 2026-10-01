---
id: 261001-fik
status: complete
---

# Quick Plan: Fail-Closed Documentation-Only CI Fast Path

## Goal

Keep every pull request visible to CI while avoiding redundant macOS and heavy Phase 2 lanes for a narrowly defined documentation-only change. Any uncertain classification or product, workflow, tooling, dependency, release-evidence, or unknown path runs the full suite.

## Tasks

1. Add a shared Node-only pull request impact classifier. Read the exact pull request revision's changed paths through GitHub's read-only REST API, include rename source paths, verify the file count and revision before and after pagination, and select the full suite on any uncertainty.
2. Gate only the expensive Phase 2, desktop, and iOS jobs. Keep workflow triggers unfiltered and cheap repository checks always running.
3. Add always-run repository, desktop, and iOS summary checks. They pass only when all normal jobs succeed, or when the classifier succeeded as docs-only and every gated job was skipped. Promote the classifier and summary contracts into CI self-tests.
4. Require the stable desktop and iOS summaries on protected `main` while retaining the existing direct contexts during rollout. Do not push source or merge directly to `main`; source rollout proceeds through a green PR.

## Verification

- Run the classifier path self-test and summary result self-tests, including unknown paths, rename paths, unexpected skips, lane failures, and classifier failure.
- Run `tooling/check-ci-contract.mjs`, including its workflow mutation checks.
- Run `actionlint` on all three changed workflows.
- Run `node --check` for the changed Node tools and `git diff --check` for the task's files.
- Read back protected branch required status contexts after adding both stable summaries.
- Review the exact changed paths and leave shared worktree changes unstaged and uncommitted.

## Boundaries

- Keep all workflow triggers unfiltered; do not use `paths` or `paths-ignore` for required workflows.
- Keep every path outside the explicit Markdown and prompt-template allow-list on the full-suite path.
- Never turn an expected skipped lane, failed classifier, cancelled job, or missing summary into a passing aggregate.
- Keep source changes local until they can be submitted and merged through the required PR process.
- Preserve all unrelated Phase 2 work already present in the shared worktree.
