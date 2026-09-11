# Tracer artifact placeholder

This directory stands in for "the packaged desktop application" artifact for
the 06-02 Task 1 tracer slice only: it exists to prove the release-evidence
spine (CI job -> artifact digest -> release-manifest.json ->
verify-release.mjs -> committed retention) end-to-end with ONE lane and ONE
artifact, per 06-02-PLAN.md's tracer scope.

The real macOS `.app` bundle produced by `tooling/package-desktop.mjs` is
too large and platform-specific to commit to git, and is not built by the
fast `ci-contract` job this tracer's lane runs in (it runs on
`ubuntu-24.04`; the real desktop package is built on `macos-15` by
`.github/workflows/desktop.yml`, wired separately). This committed
placeholder lets `verify-release.mjs` recompute a real digest fully offline
against a real committed bundle, exactly as the must-have truth requires,
without requiring a macOS runner or a multi-hundred-megabyte git blob.
