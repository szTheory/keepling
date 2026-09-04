---
phase: KPL-03-mac-daily-loop
plan: 06
subsystem: testing
tags: [packaging, evidence, digest, gate, accessibility, dogfood, ci]

requires:
  - phase: KPL-03-mac-daily-loop
    provides: "the packaged artifact pipeline, the nine-lane desktop gate, and the fifteen-row macOS integration lane"
provides:
  - "Package-once/consume-many evidence: one build digest flows through packaged tests and promotion without a rebuild"
  - "The anti-vacuous nine-lane desktop phase gate with positive case counts, durations and tracked-input digests per lane"
  - "Automated packaged security, privacy and accessibility evidence against the exact copied executable"
  - "A recorded decision that this phase requires ZERO human verification, with the physical rows automated instead"
affects: [KPL-03 verification, desktop phase gate, requirement re-derivation]

actuals:
  tokens: 0
  tasks: 3
  commits: 0

tech-stack:
  added: []
  patterns:
    - "Digest-bound evidence: a lane records its result keyed on applicationDigestSha256 and the gate reuses it for exactly that artifact"

key-files:
  created: []
  modified: []

key-decisions:
  - "Task 3's blocking human checkpoint was SUPERSEDED IN PLACE by plan 03-15 rather than deleted, so the change stays auditable"
  - "Tasks 1 and 2 were delivered incrementally by later plans that overtook this one; no work was re-executed to produce this summary"
  - "Signed/notarized credential continuity remains explicitly deferred and unproven, and is never recorded as passing"

patterns-established:
  - "A plan overtaken by later work is closed with a summary that verifies delivery, not by re-running it"
---

# Phase KPL-03 Plan 06: Packaged Evidence, the Phase Gate, and the Superseded Human Checkpoint

**Closed as DELIVERED, not executed.** Every artifact this plan owns exists and is
exercised by the gate; its one blocking human task was superseded by 03-15. This
summary records that with fresh evidence rather than re-running finished work.

## Why this plan has no commits of its own

03-06 sat at the end of a dependency chain (`depends_on: [03-03, 03-04, 03-05, 03-08]`)
and the plans that unblocked it delivered its content as they went. That is a real
planning defect worth naming — it is the same allocation problem GAP-1 describes,
seen from the other side: work with no clear owner drifts to whoever reaches it
first. Re-executing it now would rebuild what already exists and prove nothing.

## Task 1 — build once, test exact bytes, promote only the recorded digest: DELIVERED

`tooling/package-desktop.mjs` produces an immutable manifest; `tooling/smoke-desktop-packaged.mjs`
consumes only that manifest and refuses source-tree, dev-server and rebuild paths.
`apps/desktop/test/packaged/{daily-loop,offline-capture,security}.spec.ts` run against
the copied `.app` outside the source tree.

**Reproducibility measured 2026-09-04** (it had never actually been tested; an earlier
attempt read a stale fossil manifest and compared it with itself). Two consecutive
`pnpm package:desktop` runs on an unchanged tree:

```
applicationDigestSha256 = 937b279ce76952f0...   (both)
executableDigestSha256  = cb1ff05197251895...   (both)
```

The build is reproducible, so a digest change means the inputs genuinely changed.
That is the property the whole digest-bound evidence cache rests on, and it is now
evidence rather than assumption.

## Task 2 — one anti-vacuous phase gate: DELIVERED

`tooling/verify-desktop-phase.mjs`, verified at this HEAD:

```
Desktop phase gate summary: lanes=9 failed=0
  PASS typecheck-desktop                          cases=1    duration_ms=1025
  PASS typecheck-web                              cases=1    duration_ms=1833
  PASS unit-pure-vector-store-worker-performance  cases=172  duration_ms=967
  PASS ipc-hostile-bridge                         cases=66   duration_ms=687
  PASS electron-e2e                               cases=60   duration_ms=52818
  PASS package-once                               cases=1    duration_ms=12728
  PASS packaged                                   cases=10   duration_ms=8127
  PASS macos-integration                          cases=92   duration_ms=274
  PASS privacy                                    cases=1    duration_ms=20
Desktop phase gate: PASSED
```

`macos-integration` at 274ms is digest-bound evidence REUSE; the producing run is
~160s and recorded `rows=15 failed=0 cases=92` for this exact artifact.

The gate also forces `KEEPLING_TEST_HEADLESS=0` on both Playwright lanes, so the
complete windowed suite — including the five `@windowed` specs a headless run
cannot honestly assert — runs here even though the local default is now headless.

## Task 3 — the human checkpoint: SUPERSEDED by 03-15, not performed

This was a `checkpoint:human-verify gate="blocking"` task requiring a person to work
a fifteen-row physical accessibility checklist and a seven-consecutive-calendar-day
dogfood interval with a structured evidence record.

It is superseded under a recorded decision that this project requires zero human
verification. Rows A1–A15 are executed by `tooling/verify-macos-integration.mjs`
against the exact packaged artifact, at the macOS layer those rows were always
about: the real AXUIElement tree VoiceOver speaks, real CGEvent keystrokes, real
input sources, real system appearance, and computed WCAG contrast from captured
pixels. The checklist, the evidence record, the seven-day accounting and the
blocking sign-off are gone. What remains of dogfooding is informal feedback with
no format, no counts and no sign-off, and it gates nothing.

The plan's frontmatter `autonomous: false` was left as written; it described Task 3
and is now historical.

## Not swept up by this

**Signed/notarized credential continuity remains explicitly deferred and unproven.**
Nothing in this phase signs or notarizes the `.app`; every packaged test launches an
unsigned ad-hoc artifact. The gate prints it as `DEFERRED ... status=NON_PASSING` on
every run, and it must never be recorded as passing.

**CI has never run.** There is no git remote, so `.github/workflows/desktop.yml` has
never executed. This plan's CI wiring exists and is well-formed; it is not evidence
(O-35).

## Requirement status

This plan does NOT mark any requirement complete. Re-derivation is the orchestrator's,
against the evidence above (O-17).
