# Desktop Performance Evidence (D-43)

`tooling/measure-desktop-performance.mjs` is the D-43 measurement orchestrator. It measures
every named D-43 metric against the **exact packaged executable** selected by a
`package-desktop.mjs` manifest — never a development/source build — and produces:

- `.artifacts/desktop/performance-evidence.json` — the raw measurement evidence (distributions,
  sample counts, fixture descriptions, environment metadata, thread-ownership assertions).
- `apps/desktop/performance-budgets.json` — the reviewed baseline + regression-budget decision
  record, written only by an explicit `--record-baseline` run.

## What this measures, and how

| Metric | Fixture / method |
|---|---|
| `cold_launch_to_local_interactive_ms` | Fresh disposable profile (empty local store). Time from process spawn to the capture form (`getByLabel('What do you want to keep?')`) becoming visible — the actual moment a person can type. |
| `warm_launch_to_local_interactive_ms` | Same profile as a prior session (initialized local store). Same interactive marker as cold launch. |
| `quick_entry_open_to_focus_ms` | First Quick Entry invocation per session, driven through the real native `Menu` (`MenuItem#click()`), timed to the title field being focused. Quick Entry is a resident window — repeat opens in the same session reuse the existing `BrowserWindow` and are a faster reshow, not a fresh open, so only the first invocation per session is a fair "open" sample (see "Known scope gap" below for why this isn't disclosed as vacuous). |
| `local_commit_ms` | Fill + submit the main window's capture form, timed to the post-COMMIT `"Saved on this Mac"` indicator (D-03) — never a paint or optimistic-update proxy. |
| `list_scroll_frame_p95_ms` | Deterministic 500-task fixture built by applying the exact same migration SQL and `schema_migrations` checksum ledger row the app itself writes (`NodeSqliteLocalStore#applyMigration`), then inserting synthetic `Fixture task N` rows directly. A driven scroll runs `requestAnimationFrame` for 1.5s, recording frame timestamps; the first 5 frames are discarded as warmup and the remaining deltas are the sample set. |
| `idle_cpu_percent` / `idle_memory_mb` | 10 samples of `app.getAppMetrics()` at 150ms intervals with no interaction, after a 400ms settle. |
| `wake_reconnect_main_thread_work_ms` / `wake_reconnect_renderer_thread_work_ms` | See "Known scope gap" below — this is a disclosed proxy, not a measurement of an OS-level wake event. |
| `wal_bytes` / `checkpoint_ms` | 10 sequential captures through the real write path, then a **live, concurrent** second `node:sqlite` connection stats the `-wal` file and runs `PRAGMA wal_checkpoint(TRUNCATE)` while the app's own worker connection stays open. This is deliberate: SQLite auto-checkpoints (and truncates the WAL) when the *last* connection to a WAL-mode database closes, so measuring after `app.close()` would silently measure a checkpoint that already happened for free. SQLite's WAL mode explicitly supports a second reader/writer connection from another process against the same file; this was verified empirically before being relied on here. |
| `packaged_app_bytes` | Exact copied `.app` bundle, recursive byte sum (symlinks excluded), from the same manifest `smoke-desktop-packaged.mjs` verifies. |

Every metric records: unit, fixture description, sample count, p50/p95/min/max, and is bound to
the exact `applicationDigestSha256` / `sourceRevision` from the package manifest plus closed
environment metadata (arch, CPU model/count, embedded Electron/Chrome/Node/V8 versions, host
Node version, OS release, platform, total memory). No task titles, profile paths, or database
paths are ever written to evidence — `privacyScan()` walks the entire evidence object before
it is written and fails closed if it finds a path-like or URL-like string outside a small
allowlist of digest/revision fields.

## Thread-ownership assertion

D-43 requires proof that database/network work does not block the Electron main or renderer
thread. The script polls a cheap round trip (`application.evaluate(() => Date.now())` on the
main process, `window.evaluate(() => performance.now())` on the renderer) at 15ms intervals
while the local commit and the reconnect reconciliation are in flight, and asserts the maximum
observed round trip never exceeds 300ms. That ceiling is generous enough to absorb ordinary
CDP/IPC round-trip noise while still catching multi-second synchronous blocking, which is the
actual risk this assertion guards against. The result is recorded in evidence under
`threadOwnership.commit` / `threadOwnership.reconnect`.

## Regression budgets, not fabricated release thresholds

`apps/desktop/performance-budgets.json` is a **reviewed decision record**, not a
mechanically-generated pass/fail gate. Each metric's entry carries:

- `baseline` — the recorded statistic (p50 or p95, per metric) from the `--record-baseline` run.
- `budget` — either `{ kind: "relative", value: <fraction> }` (percentage headroom over
  baseline) or `{ kind: "absolute", value: <units> }` (flat headroom), chosen per-metric based
  on the metric's real variance characteristics.
- `sampleFloor` — the minimum sample count `--check-budgets` will accept; fewer samples fails
  closed rather than comparing an under-sampled run. For every metric with a fixed sample
  count (all except scroll frame pacing), this is recorded exactly as observed. `--record-baseline`
  discovered by direct re-execution that `list_scroll_frame_p95_ms`'s sample count -- the number
  of `requestAnimationFrame` callbacks that actually fire during a fixed 1.5s window -- varies
  run to run with ordinary scheduler jitter (observed 175 vs 176 frames on an otherwise identical
  machine); recording that exact count as `sampleFloor` made `--check-budgets` fail on normal
  jitter, not a regression. It uses a fixed, conservatively-below-typical override (100) instead
  (see `SAMPLE_FLOOR_OVERRIDES` in the script).
- `rationale` — why that specific budget was chosen (see the table in the script's
  `REGRESSION_BUDGETS` constant for the reasoning behind each one).

No product release threshold is invented. `--record-baseline` records **what was actually
measured**, and the budget is a regression-detection tolerance around that baseline — nothing
here should be read as "the product must launch in Xms" unless CONTEXT.md states that
independently.

## Reproduction

```sh
node tooling/package-desktop.mjs --platform darwin
# capture the manifest path it prints, or read $TMPDIR/keepling-desktop-latest-manifest-*.txt

node tooling/measure-desktop-performance.mjs --manifest <manifest-path> --record-baseline
node tooling/measure-desktop-performance.mjs --manifest <manifest-path> --check-budgets --self-test-regression
```

`--record-baseline` and `--check-budgets` are combinable in one invocation. `--self-test-regression`
is a self-check on `--check-budgets`'s own logic: it clones the real `cold_launch_to_local_interactive_ms`
samples, injects a large synthetic regression (`value * 10 + 5000`), and asserts the comparison
correctly rejects it — proving the budget check is not vacuous — before reporting the real
(non-injected) result as the actual pass/fail outcome.

## Noise handling

Every timing metric is a **distribution**, never a single run: launch/session metrics take 3
independent sessions, idle sampling takes 10 in-session samples, scroll frame pacing takes
~170+ real animation frames per run, and WAL/checkpoint take 3 independent write-then-checkpoint
sessions. `--check-budgets` compares the metric's recorded statistic (p50 or p95, matching
whichever the budget was recorded against) rather than a single sample, and refuses to compare
at all if the current run has fewer samples than the budget's `sampleFloor`.

## Baseline replacement approval

Re-running `--record-baseline` **overwrites** `apps/desktop/performance-budgets.json`. This is a
deliberate, human-reviewed action, not something CI or a routine packaging step should do
automatically: a baseline should only move when a person has looked at the new numbers and
agreed the shift is expected (e.g. a deliberate architecture change) rather than an
unnoticed regression. Treat a `--record-baseline` diff in review exactly like a diff to any
other checked-in decision record.

**A runtime, storage, or artifact change reruns the exact packaged lane.** Any change to the
Electron/Chrome/Node/V8 version, the SQLite adapter, the migration schema, or the packaging
pipeline invalidates the previous baseline's assumptions (different embedded runtime, different
WAL/checkpoint behavior, different bundle size floor). Re-run `package-desktop.mjs` and
`--record-baseline` against the new packaged artifact before trusting `--check-budgets` again.

## Known scope gap: wake/reconnect has no OS-level listener yet

Verified by source inspection of `apps/desktop/main/index.ts`, `main/lifecycle.ts`, and
`main/application/DesktopApplication.ts`: there is **no `powerMonitor` "resume"/"unlock-screen"
listener, and no periodic or online-event-triggered sync pass** wired into the shipped app
today. The only implemented reconciliation code path is `DesktopApplication#reconcile()`, run
once at bootstrap before the first window is created.

Because of that, this script cannot honestly measure "the main-thread work an OS wake/reconnect
event triggers" — no such event handler exists to measure. Fabricating a number for
non-existent code would violate this plan's evidence rules. Instead, `wake_reconnect_*_ms`
measures the closest **real** analog this codebase implements: capture a task while offline,
quit, relaunch with the network reachable (`KEEPLING_TEST_SYNC_MODE=acknowledge`), and let the
bootstrap reconcile pass settle the queued mutation — exactly the scenario the
`offline-capture`/`lifecycle` E2E suites already exercise. `wake_reconnect_main_thread_work_ms`
is reported as the **marginal** cost over an equivalent warm-launch control (same profile class,
nothing pending) from the same run, to isolate the reconciliation cost specifically rather than
conflating it with ordinary launch time. `wake_reconnect_renderer_thread_work_ms` is the time
from interactive to the acknowledged task's `"Synced"` repaint.

This is disclosed here, and in the executing plan's SUMMARY.md, as a **known gap**, not silently
patched: wiring a real `powerMonitor` resume listener and a reachability-triggered sync pass is
real, scoped follow-on work in `apps/desktop/main/**`, outside this plan's `files_modified`
(tests, tooling, budgets, and docs only).
