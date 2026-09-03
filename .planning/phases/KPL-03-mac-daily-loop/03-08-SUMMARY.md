---
phase: KPL-03-mac-daily-loop
plan: 08
subsystem: testing
tags: [electron, performance, sqlite, playwright, regression-budgets]

requires:
  - phase: KPL-03-mac-daily-loop
    plan: 12
    provides: Anti-vacuous desktop test discovery, package-once manifest, digest-bound external smoke
  - phase: KPL-03-mac-daily-loop
    plan: 11
    provides: Wired lifecycle/bootstrap so the packaged app fully exercises capture, Quick Entry, and quit
provides:
  - D-43 measurement orchestrator (tooling/measure-desktop-performance.mjs) covering all twelve named metrics against the exact packaged executable
  - Reviewed baseline + regression-budget decision record (apps/desktop/performance-budgets.json)
  - Reproduction/interpretation contract (docs/testing/desktop-performance.md)
  - Fast, deterministic unit coverage of the tool's pure statistics/privacy/budget-comparison logic (apps/desktop/test/performance/runtime.spec.ts)
affects: [desktop-testing, release-evidence, KPL-03-06]

actuals:
  tokens: 15400
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "CLI tool with an entrypoint guard (`import.meta.url === pathToFileURL(process.argv[1]).href`) so its pure logic can be imported and unit-tested without triggering process.argv parsing or spawning Electron"
    - "Live second SQLite connection for WAL/checkpoint measurement, avoiding the auto-checkpoint-on-close that would otherwise measure a no-op"
    - "Main/renderer thread liveness probing (concurrent cheap round-trip polling) as a black-box, non-invasive proof that a UI-owning thread isn't blocked, without adding instrumentation to application source"

key-files:
  created:
    - tooling/measure-desktop-performance.mjs
    - apps/desktop/test/performance/runtime.spec.ts
    - apps/desktop/performance-budgets.json
    - docs/testing/desktop-performance.md
  modified:
    - apps/desktop/vitest.config.ts
    - apps/desktop/package.json

key-decisions:
  - "wake/reconnect has no OS-level listener in the shipped app; measured the app's only implemented reconciliation path (bootstrap reconcile on relaunch with pending offline mutations) as a disclosed proxy rather than fabricating a measurement of non-existent code"
  - "Quick Entry open-to-focus measures only the FIRST invocation per session, because the resident-window pattern makes every repeat open a fast reshow rather than a fresh open -- mixing the two would misrepresent the metric"
  - "WAL bytes and checkpoint duration are measured via a live, concurrent second SQLite connection while the app's own worker connection stays open, since SQLite auto-checkpoints (and truncates the WAL) when the last connection to a WAL-mode database closes"
  - "list_scroll_frame_p95_ms's sampleFloor uses a fixed, conservatively-below-typical override (100) instead of the exact observed frame count, discovered necessary by direct re-execution: real rAF frame counts over a fixed wall-clock window vary run to run with ordinary scheduler jitter"
  - "Regression budgets are reviewed decision records replaced only by an explicit human-approved --record-baseline rerun, never invented release thresholds"

patterns-established:
  - "D-43 evidence schema: unit, fixture description, sample count, p50/p95/min/max, bound to exact application digest, source revision, and closed environment metadata, with a privacy scan that fails closed on any path/URL/content-like string"

requirements-completed: [MAC-01, MAC-02, MAC-03, MAC-05, QUAL-03]

coverage:
  - id: D1
    description: "All twelve named D-43 metrics are measured against the exact packaged executable with real distributions (not single unrepeated timings), bound to digest/environment/fixture metadata."
    requirement: MAC-01
    verification:
      - kind: other
        ref: "node tooling/measure-desktop-performance.mjs --manifest .artifacts/desktop/package-manifest.json --record-baseline"
        status: pass
    human_judgment: false
  - id: D2
    description: "Main/renderer thread liveness is proven not blocked during local commit and reconnect reconciliation."
    requirement: MAC-02
    verification:
      - kind: other
        ref: "node tooling/measure-desktop-performance.mjs --manifest .artifacts/desktop/package-manifest.json --record-baseline (threadOwnership assertion, fails closed at >300ms round trip)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Regression budgets are recorded per metric with baseline, statistic, budget, sample floor, and rationale; a synthetic regression is rejected and unchanged evidence passes reproducibly (verified twice in direct succession)."
    requirement: QUAL-03
    verification:
      - kind: other
        ref: "node tooling/measure-desktop-performance.mjs --manifest .artifacts/desktop/package-manifest.json --check-budgets --self-test-regression"
        status: pass
    human_judgment: false
  - id: D4
    description: "The tool's pure statistics/privacy/budget-comparison logic has fast, deterministic unit coverage that never spawns Electron."
    verification:
      - kind: unit
        ref: "apps/desktop/test/performance/runtime.spec.ts (15 tests, vitest project 'performance')"
        status: pass
    human_judgment: false
  - id: D5
    description: "Regression baseline suites (desktop, ipc, web, both typechecks) remain intact after this plan's changes."
    verification:
      - kind: other
        ref: "pnpm test:desktop (15 files/132 tests), pnpm test:desktop:ipc (46 tests), pnpm --dir apps/web test --run (15 files/153 tests), pnpm typecheck:desktop, pnpm typecheck:web"
        status: pass
    human_judgment: false

duration: 105min
completed: 2026-09-03
status: complete
---

# Phase KPL-03 Plan 08: D-43 Desktop Performance Evidence Summary

**D-43 measurement orchestrator, twelve-metric evidence schema, and reviewed regression-budget record against the exact packaged Keepling.app**

## Performance

- **Duration:** 105 min
- **Started:** 2026-09-02T23:53:20Z
- **Completed:** 2026-09-03T01:38:00Z
- **Tasks:** 2
- **Files modified:** 6 (4 created, 2 modified)

## Accomplishments

- Built `tooling/measure-desktop-performance.mjs`, which launches the exact manifest-selected, digest-verified packaged `.app` (never a dev build) and produces real distribution evidence — sample count, p50/p95/min/max, fixture description, and environment metadata — for all twelve named D-43 metrics.
- Proved main/renderer thread ownership with a concurrent liveness probe (15ms-interval round trips, 300ms ceiling) during local commit and reconnect reconciliation; this is a real, enforced assertion (fails closed), not documentation.
- Recorded a reviewed regression-budget decision record (`apps/desktop/performance-budgets.json`) with a per-metric statistic, relative/absolute budget, sample floor, and variance-based rationale — never a fabricated release threshold.
- Verified `--check-budgets --self-test-regression` end-to-end **twice in direct succession** on real, freshly re-measured live-Electron evidence, confirming it (a) passes reproducibly on unchanged code and (b) rejects an injected 10x+5000ms regression every time.
- Wrote `docs/testing/desktop-performance.md`: measurement method per metric, the thread-liveness contract, reproduction steps, noise handling, baseline-replacement approval, and the runtime/storage/artifact re-run rule.
- Exported the tool's pure statistics/privacy/budget-comparison logic behind an entrypoint guard and added `apps/desktop/test/performance/runtime.spec.ts` (15 fast unit tests, ~200ms, zero Electron spawns) plus a new `performance` vitest project so the tests are actually discoverable (not vacuous).

## Task Commits

1. **Task 1: Measure every D-43 product and runtime path against one exact packaged digest** - `2fdf88d` (feat)
2. **Task 2: Record named regression-budget decisions and fail later measurements on drift** - `1ae7553` (feat)

_Note: both tasks share `tooling/measure-desktop-performance.mjs`, which was authored complete in the Task 1 commit; Task 2's commit adds the budget record and docs it enables._

## Files Created/Modified

- `tooling/measure-desktop-performance.mjs` — D-43 measurement orchestrator: manifest/digest verification, environment metadata, disposable profile management, fixture DB construction, live Electron launch helpers, thread-liveness probes, all twelve metric collectors, evidence assembly + privacy scan, `--record-baseline` and `--check-budgets --self-test-regression` CLI modes.
- `apps/desktop/test/performance/runtime.spec.ts` — unit tests for `percentile`/`summarize`, `privacyScan`, `compareMetricAgainstBudget`, and `round`.
- `apps/desktop/performance-budgets.json` — reviewed baseline + regression-budget record for all twelve metrics, recorded against this machine's environment.
- `docs/testing/desktop-performance.md` — measurement method, reproduction, noise handling, baseline-replacement approval, known scope gap disclosure.
- `apps/desktop/vitest.config.ts` — added the `performance` project (`test/performance/**/*.{test,spec}.ts`, node environment).
- `apps/desktop/package.json` — added `--project performance` to the `test` script so it runs under `pnpm test:desktop`.

## Decisions Made

See `key-decisions` above (wake/reconnect proxy, Quick-Entry first-open-only, live-connection WAL/checkpoint measurement, scroll-frame sample-floor override, reviewed-not-invented budgets).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Manifest path mismatch between the plan's `<verify>` commands and `package-desktop.mjs`'s actual output location**
- **Found during:** Task 1, first `<verify>` run
- **Issue:** The plan's `<verify>` commands (and this SUMMARY's own coverage refs) use `--manifest .artifacts/desktop/package-manifest.json`, but `tooling/package-desktop.mjs` (owned by Plan 03-12, out of this plan's scope) writes the manifest to a system-temp path recorded via a `$TMPDIR` locator file, never to `.artifacts/desktop/`.
- **Fix:** Ran `package-desktop.mjs`, then copied the produced manifest to `.artifacts/desktop/package-manifest.json` (an established evidence-output location this plan already writes `performance-evidence.json` to). Did not modify `package-desktop.mjs`'s own output location — that stays owned by 03-12.
- **Files modified:** none (copy only; `.artifacts/` is untracked, same treatment as `apps/desktop/out/`)
- **Verification:** Both plan `<verify>` commands, run literally as written in PLAN.md, pass against this path.
- **Committed in:** N/A (not a tracked file)

**2. [Rule 2 - Missing Critical] `apps/desktop/test/performance/runtime.spec.ts` had no discovery lane**
- **Found during:** Task 1, while placing the test file
- **Issue:** No existing vitest project glob matched `test/performance/**`, and `pnpm test:desktop` explicitly lists 4 named `--project` flags that don't include it. A test file nothing discovers is exactly the vacuous-evidence failure this phase's harness model (Plan 03-12) exists to prevent.
- **Fix:** Added a `performance` project to `apps/desktop/vitest.config.ts` (matching the established named-project, zero-case-refusing pattern) and added `--project performance` to `apps/desktop/package.json`'s `test` script.
- **Files modified:** `apps/desktop/vitest.config.ts`, `apps/desktop/package.json`
- **Verification:** `pnpm test:desktop` now reports 15 files / 132 tests (was 14/117); the new file's 15 tests are counted in that total.
- **Committed in:** `2fdf88d`

**3. [Rule 1 - Bug] `list_scroll_frame_p95_ms`'s recorded `sampleFloor` was flaky by construction**
- **Found during:** Task 2, re-running `--check-budgets` a second time against a fresh live measurement (not simulated — this was caught by genuinely re-executing the tool)
- **Issue:** `--record-baseline` recorded `sampleFloor` as the exact observed frame count (176). `requestAnimationFrame` frame counts over a fixed 1.5s wall-clock window vary with ordinary OS scheduler jitter (observed 175 vs 176 across otherwise-identical runs on the same machine), so the very next `--check-budgets` run failed on `insufficient samples`, not a real regression.
- **Fix:** Added a `SAMPLE_FLOOR_OVERRIDES` map; `list_scroll_frame_p95_ms` now records a fixed, conservatively-below-typical floor (100) instead of its raw observed count. Every other metric has a fixed sample count (constant `SAMPLE_COUNTS`) and is unaffected.
- **Files modified:** `tooling/measure-desktop-performance.mjs`
- **Verification:** Re-ran `--record-baseline` then `--check-budgets --self-test-regression` twice in direct succession on fresh live evidence each time; both passed. This exact bug is why the plan's "run twice" verification discipline matters — a single run would not have caught it.
- **Committed in:** `2fdf88d` (fixed before the commit; the flaky version was never committed)

**4. [Rule 1 - Bug] `checkpoint_ms`'s relative regression budget was untestable at its own baseline**
- **Found during:** Task 2, reviewing the recorded baseline before finalizing
- **Issue:** `PRAGMA wal_checkpoint(TRUNCATE)` on a small WAL completes in 0-1ms at `Date.now()`'s millisecond resolution. A 50%-relative budget on a baseline of 1ms produces a 1.5ms threshold — any run reporting a real (but still fast) 2ms would fail purely from integer-millisecond quantization, not a genuine regression.
- **Fix:** Changed `checkpoint_ms`'s budget to `{ kind: 'absolute', value: 10 }` (documented rationale in the script and in `docs/testing/desktop-performance.md`).
- **Files modified:** `tooling/measure-desktop-performance.mjs`
- **Verification:** Same two-run confirmation as deviation 3.
- **Committed in:** `2fdf88d`

---

**Total deviations:** 4 auto-fixed (1 Rule 3 blocking, 1 Rule 2 missing-critical, 2 Rule 1 bugs)
**Impact on plan:** All four were necessary for the plan's own verify commands and evidence rules to hold reliably; none expand scope beyond the plan's stated files. Deviations 3 and 4 were caught only because this plan's own "re-run and report reproducibly" discipline was followed literally — a single measurement run would have shipped a budget file with a real (if narrow) flakiness defect.

## Issues Encountered

None beyond the deviations above.

## Known Scope Gaps (disclosed, not silently fixed — this plan owns tests/tooling/docs only, not application source)

- **Wake/reconnect has no OS-level listener wired into the shipped app.** Verified by source inspection of `apps/desktop/main/index.ts`, `main/lifecycle.ts`, and `main/application/DesktopApplication.ts`: there is no `powerMonitor` resume/online listener and no periodic sync pass. `wake_reconnect_main_thread_work_ms` / `wake_reconnect_renderer_thread_work_ms` measure the only real reconciliation path this codebase implements today — the bootstrap `reconcile()` pass on relaunch with queued offline mutations — labeled explicitly as a proxy in evidence (`fixture` field) and documented in full in `docs/testing/desktop-performance.md`. This is real, scoped follow-on work in `apps/desktop/main/**`, outside this plan's authorized files. Recommend a future plan wire a `powerMonitor` resume listener and a reachability-triggered `runSyncPass()` call, then re-measure this metric against a genuine wake event.
- **Quick Entry open-to-focus measures first-open-per-session only**, not steady-state reshow, because the window is resident (created once, then shown/hidden). Disclosed in the evidence `fixture` field and in the docs. Not a defect — the metric is honestly scoped to what the app's window lifecycle makes measurable as a fair "open" sample.
- **`performance-budgets.json` is machine-specific** (recorded on this dev machine's Apple Silicon / macOS environment, captured in the file's own `environment` block). Per `docs/testing/desktop-performance.md`, re-baselining on a different reference machine (or CI) is expected before treating these numbers as release gates rather than local regression-detection.
- **`test:desktop:e2e` was not re-run** in this plan (unaffected files — no `main/`, `preload/`, `renderer/`, or `test/e2e/` changes were made). `pnpm typecheck:desktop` passing (which compiles the whole desktop TS project including `test/`) is the coverage this plan relied on for the unaffected suite.

## User Setup Required

None — no external service configuration required.

## Threat Flags

None. No new network endpoints, auth paths, or trust-boundary schema changes were introduced. The two threat-modelled boundaries (artifact-under-test spoofing, evidence information disclosure) are both mitigated exactly as declared in the plan's threat register: exact manifest/digest verification before any measurement, and a fail-closed privacy scan over the full evidence object before it is written.

## Next Phase Readiness

- D-43's measurement contract is complete, real (not vacuous), and reproducible on demand via `node tooling/measure-desktop-performance.mjs --manifest <manifest> --record-baseline` / `--check-budgets [--self-test-regression]`.
- Regression baseline confirmed intact and re-reported: `pnpm test:desktop` 15 files / 132 tests (grew from 14/117 by exactly this plan's new spec file), `pnpm test:desktop:ipc` 46/46, `pnpm --dir apps/web test --run` 15 files / 153 tests (unchanged), `pnpm typecheck:desktop` clean, `pnpm typecheck:web` clean.
- Wave 11 (`03-06`) can proceed; it owns `test/packaged`, `tooling/`, docs, and CI, and does not depend on this plan's files beyond the now-established `.artifacts/desktop/` evidence-output convention.
- The wake/reconnect and Quick-Entry-reshow scope gaps above are real follow-on work, not blockers for this plan's own completion — flagged here per this phase's GAP-1 precedent so they are decided deliberately rather than passing unnoticed.

## Self-Check: PASSED

- `[ -f tooling/measure-desktop-performance.mjs ]` → FOUND
- `[ -f apps/desktop/test/performance/runtime.spec.ts ]` → FOUND
- `[ -f apps/desktop/performance-budgets.json ]` → FOUND
- `[ -f docs/testing/desktop-performance.md ]` → FOUND
- `git log --oneline --all --grep="KPL-03-08"` → 2 commits found (`2fdf88d`, `1ae7553`)
- Re-ran both plan `<verify>` commands literally as written in PLAN.md against `.artifacts/desktop/package-manifest.json`: both pass.
- Re-ran the plan's `<acceptance_criteria>` for both tasks: all twelve metrics present with non-zero sample counts/units/digest/environment/privacy pass (Task 1); every metric has one baseline/budget/rationale, a synthetic regression is rejected, and unchanged evidence passes reproducibly across two consecutive runs (Task 2).
- Re-ran the full regression baseline: desktop 15/132, ipc 46/46, web 15/153, both typechecks clean.

---
*Phase: KPL-03-mac-daily-loop*
*Completed: 2026-09-03*
