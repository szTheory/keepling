---
phase: KPL-03-mac-daily-loop
reviewed: 2026-09-04T00:00:00Z
depth: standard
scope: gap-closure-only
diff_base: 4a5f50a
files_reviewed: 6
files_reviewed_list:
  - apps/desktop/test/e2e/appearance-matrix.spec.ts
  - package.json
  - tooling/package-desktop.mjs
  - tooling/verify-desktop-phase.mjs
  - tooling/verify-macos-integration.mjs
  - tooling/verify-package-reproducibility.mjs
findings:
  critical: 0
  warning: 1
  info: 2
  total: 3
status: issues_found
---

# Phase KPL-03: Code Review Report (gap-closure scope)

**Reviewed:** 2026-09-04
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found

## IMPORTANT — Scope of this document

This is **not** a whole-phase review. It covers only the files changed by
KPL-03's gap-closure plans (03-25, 03-26, 03-27), computed as
`git diff --name-only 4a5f50a..HEAD` filtered to source files. This document
**replaces** a prior `03-REVIEW.md` that reviewed the full phase (141 files,
plans 01-24) and recorded **0 Critical / 3 Warning / 1 Info**. That prior
review's findings (SafeStorage `shouldReEncrypt` discarded, title-based task
lookup after capture, Quick Entry/Settings IPC sender-trust asymmetry, and a
discarded store-open error) are about `apps/desktop/main/**` and
`apps/desktop/renderer/**` files that are **not** part of this diff and were
**not re-examined here**. Anyone tracking phase-wide review status should
treat those four findings as still outstanding until re-verified separately;
they are recorded here only for continuity, not re-validated in this pass.

## Summary

This diff is a verification-harness gap-closure pass, not application code:
`tooling/package-desktop.mjs` (reproducibility manifest + digest-bound
promotion + `--reuse-if-unchanged`), `tooling/verify-package-reproducibility.mjs`
(three/N-build byte-identical comparison with a self-test),
`tooling/verify-desktop-phase.mjs` (the aggregate gate that wires all lanes
together plus the D-48 adversarial-fixture-ownership registry), the new
`tooling/verify-macos-integration.mjs` macOS AX/CGEvent lane (rows A1-A15),
and a new Playwright spec (`appearance-matrix.spec.ts`) proving five
window-size/theme combinations behaviorally rather than by golden image.

Given the reviewer brief's explicit concern — "can this harness report a
PASS it did not earn" — I traced every place that looked like a candidate for
a vacuous pass, a stale cache, a broken restore path, or a non-deterministic
"deterministic" shuffle:

- `evaluateEvidence`/`runGateMode` in `verify-macos-integration.mjs` (the
  digest-bound reuse of the macOS lane's evidence): binds to
  `applicationDigestSha256`, `executableDigestSha256`, all three Swift probe
  source digests, and the lane's *own* source digest; requires every one of
  the 15 rows present and passing; requires a positive case count. It ships
  its own inline self-test (`SELF-TEST-EVIDENCE`, `runEvidenceSelfTest`)
  covering every one of those negative paths (different digest, different
  executable, changed probe, changed lane source, missing `laneSourceDigest`
  field, a failing row, partial-subset coverage, zero cases) plus the
  positive path. This is sound.
- `seededShuffle`/`mulberry32` (`verify-macos-integration.mjs:2544-2563`): a
  standard, correctly-implemented mulberry32 PRNG seeded once from the
  `--seed` argument, driving an in-place Fisher-Yates. Given the same seed it
  produces the same permutation; I verified the algorithm by hand and it
  contains no `Math.random()` fallback or per-call reseeding.
- The system-settings capture/restore machinery
  (`captureSystemSettings`/`applyBaselineAndVerify`/`restoreSystemSettings`/
  `restoreBetweenRows`) restores on: normal completion (`cleanUp`), a thrown
  `LaneFailure`, an `uncaughtException` handler, and `SIGINT`/`SIGTERM`/
  `SIGHUP` handlers registered *before* any mutation is possible order-wise
  (registered at module load, and `assertNoLeftoverCapture` refuses to start
  a run at all if a prior run's capture file is still on disk, rather than
  silently adopting a dirty machine as the new baseline). Restoration is
  verified by re-reading settings in a **separate process** rather than
  trusting an in-process read-back, and the capture file is deleted only
  after that re-read confirms a match. `runSelfTestRestore` proves both the
  mid-row-exception path and a real SIGTERM-to-a-forked-child path.
- Reproducibility (`verify-package-reproducibility.mjs`): `compareTrees`
  returns every entry's disposition, not just diffs, so `comparedEntries`
  can't be silently zero; `--self-test` proves the comparator can see a real
  content/mode/symlink diff before it's ever trusted on a real build; a
  differing `.asar` is descended into by member rather than reported only at
  the container level, and an unextractable archive is reported as an
  explicit `asar-extract-unavailable` diff rather than downgraded to "same".
  `runBuilds` refuses on a dirty tree and requires `--builds >= 2`.
- `tooling/package-desktop.mjs`'s `--reuse-if-unchanged`: re-hashes the
  candidate artifact's bytes on disk (both the `.app` tree and the
  executable) against the manifest's recorded digests before ever reusing it,
  and falls through to a full rebuild — never a hang, never a silent stale
  reuse — on any mismatch, missing file, or unreadable manifest.
- `verify-desktop-phase.mjs`'s `runLane`: a lane can only be marked `passed`
  if it exited 0, its `parse` function didn't throw, and the parsed case
  count is a finite number `> 0` — there is no "assume green" branch. The
  `privacy` lane's `command: 'node', args: []` looked suspicious at first
  (an argument-less `node` invocation could in principle hang waiting on
  stdin) — I confirmed empirically
  (`spawnSync('node', [])` with default stdio) that it exits immediately with
  status 0 in ~20ms, because Node treats a non-TTY, immediately-EOF stdin as
  an empty script. This is a legitimate (if terse) way to run a `parse`-only
  lane through the same accounting path as every subprocess-backed lane; it
  is not a hang risk.
- `appearance-matrix.spec.ts`: resizes the real `BrowserWindow`, reads the
  content size back and asserts it landed *before* asserting anything about
  layout (so a resize that silently no-ops via the `?.` optional chain on
  `getAllWindows()[0]` fails the very next assertion rather than passing
  vacuously), and the "which regions must be non-zero" split at 1024px
  content width is correctly derived from `Workspace.tsx`'s own breakpoint
  and matches the five sizes actually enumerated below it.

I found no Critical issue in this diff. The one Warning and two Info items
below are genuine but narrow.

## Warnings

### WR-01: Fixed 100ms sleep after `emulateMedia` instead of polling for the repaint

**File:** `apps/desktop/test/e2e/appearance-matrix.spec.ts:121-125`
**Issue:** Every other timing-sensitive spot in this same phase's harness
(`tooling/verify-macos-integration.mjs`, see its own extensively-documented
"poll for the condition you are about to assert, never sleep a fixed amount"
rule) treats a fixed sleep as a proven source of flakiness on a loaded
machine. This spec does the opposite immediately after changing the color
scheme:
```ts
await window.emulateMedia({ colorScheme: theme })
// Emulating a colorScheme change alone does not force a layout pass
// in every Electron/Chromium version; give the renderer one tick to
// settle before measuring anything.
await window.waitForTimeout(100)

await expect(window.getByRole('navigation')).toBeVisible()
await expect(window.getByRole('form', { name: 'Add task' })).toBeVisible()
await captureOneTask(window, `Case proof ${size.width}x${size.height} ${theme}`)
```
In practice the risk this creates is muted, not absent: the two `toBeVisible`
assertions that immediately follow have Playwright's own auto-retry (default
~5s) built in, and `captureOneTask`'s `fill`/`click`/`toBeVisible` sequence
adds further real wall-clock time before the overflow measurement later in
the test runs. So a slow theme repaint is unlikely to manufacture a false
pass here — but it is exactly the pattern this phase's own macOS lane
identified, with specific measured flakes, as unsafe on a loaded CI/dev
machine, and a 100ms budget on a genuinely slow repaint could still let the
overflow check (`scrollWidth <= clientWidth`, later in the test) sample a
mid-repaint frame that happens to not yet show the layout the theme change
would eventually produce.
**Fix:** Replace the fixed sleep with a poll for an observable post-theme
consequence, e.g.:
```ts
await window.emulateMedia({ colorScheme: theme })
await expect(window.getByRole('navigation')).toBeVisible()
await window.waitForFunction(
  (expected) => document.documentElement.matches(`[data-theme="${expected}"]`) ||
    getComputedStyle(document.documentElement).colorScheme === expected,
  theme,
)
```
(adjust the predicate to whatever DOM/CSS signal the app actually emits on
theme application) so a genuinely slow repaint extends the wait instead of
being raced.

## Info

### IN-01: `settingsState.applied` is written but never read

**File:** `tooling/verify-macos-integration.mjs:898`
**Issue:** `applySystemSettings` sets `settingsState.applied = true` but no
other code in the file reads `settingsState.applied` (confirmed by search —
it is the only reference to that field). Dead state; harmless today, but a
future reader could reasonably assume it gates some behavior (e.g. whether
restore runs) when it does not.
**Fix:** Remove the field, or if it was intended as a defensive check
somewhere (e.g. in `restoreSystemSettings`, to distinguish "never mutated
anything" from "captured but not yet mutated"), wire it in and assert on it.

### IN-02: `runSelfTestRestore` is defined with no parameters but called with an argument

**File:** `tooling/verify-macos-integration.mjs:2398` (definition) and `:2737` (call site)
**Issue:**
```js
const runSelfTestRestore = async () => { ... }
...
await runSelfTestRestore(context)
```
The extra `context` argument is silently discarded (harmless in JS), but it
suggests either a stale signature after a refactor (the function likely used
to need `context` and no longer does, or was always going to and the wiring
was never finished) or a maintainer's reasonable expectation that
`runSelfTestRestore` has access to the manifest/probe context it is passed.
**Fix:** Drop the argument at the call site, or thread it through if a future
change to this function needs it — either way, remove the mismatch so the
signature reflects reality.

---

_Reviewed: 2026-09-04_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Scope: gap-closure diff only (plans 03-25..03-27); see "IMPORTANT — Scope" above for the superseded whole-phase review's outstanding findings._
