---
phase: KPL-03-mac-daily-loop
plan: 18
subsystem: testing
tags: [macos, accessibility, axuielement, cgevent, flake, evidence-cache, polling]

requires:
  - phase: KPL-03-mac-daily-loop
    provides: "the fifteen-row macOS integration lane, its digest-bound evidence cache, and settledFocus(handle, { until }) from 03-15/03-16/03-17"
provides:
  - "A macOS integration lane in which no row sleeps a fixed amount and then reads AX, appearance or pixel state once before asserting on it"
  - "A MEASURED flake rate: ten consecutive --all runs, 150/150 row executions, two of them under full CPU load"
  - "A desktop phase gate green (lanes=9 failed=0) on evidence recorded by runs containing these fixes"
  - "One stated rule, written into the lane's own source: poll for the condition you are about to assert, never for the absence of change"
  - "A latent FALSE PASS removed from row A8 (negation-shaped assertion against an unrendered settings pane)"
affects: [KPL-03 verification, desktop phase gate, CI desktop-macos-integration job]

actuals:
  tokens: 12300
  tasks: 3
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Exactly two waiting mechanisms in the lane: settledFocus(handle, { until }) for AX focus, waitFor for everything else"
    - "waitFor onTimeout: 'return' — the deadline hands the last observation to the caller's own check instead of aborting the row with only a timeout"

key-files:
  created: []
  modified:
    - tooling/verify-macos-integration.mjs
    - .planning/HANDOFF.json
    - .planning/phases/KPL-03-mac-daily-loop/.continue-here.md

key-decisions:
  - "Poll for the ASSERTED condition, never for quiescence — an absent focus and a pending dead key are both stable indefinitely, so 'the value stopped changing' settles on the failure state"
  - "Corrected the rule previously recorded in O-24 ('the settle predicate must be strictly weaker than the assertion'), which is the exact trap that produces a vacuous green"
  - "A8's settings-pane waits deliberately fail loudly rather than returning the last observation, because a negation asserted against an empty read is vacuously TRUE"
  - "A3's failure was a lane race, not a product defect: the conflict heading mounts before focus moves onto it"

patterns-established:
  - "Every wait is bounded and reports what it last saw; a condition that never holds still fails"
  - "A settle condition covers every condition the row asserts (A14 now settles on legibility, not merely on the background having changed)"

requirements-completed: [MAC-02, QUAL-04]

coverage:
  - id: D1
    description: "Every sleep-then-read-once site in the macOS integration lane settles on the condition it asserts"
    requirement: "QUAL-04"
    verification:
      - kind: integration
        ref: "node tooling/verify-macos-integration.mjs --all (x10, 150/150 rows, 92 cases each)"
        status: pass
    human_judgment: false
  - id: D2
    description: "The lane's flake rate is measured, not assumed, including under CPU load"
    requirement: "QUAL-04"
    verification:
      - kind: integration
        ref: "ten consecutive --all runs; runs 4 and 7 under 18 CPU spinners on 18 cores (222.4s / 208.3s vs idle 168-171s)"
        status: pass
    human_judgment: false
  - id: D3
    description: "The desktop phase gate is green on evidence recorded by a run containing these fixes, and consumes it rather than re-running rows"
    requirement: "MAC-02"
    verification:
      - kind: e2e
        ref: "node tooling/verify-desktop-phase.mjs -> lanes=9 failed=0, macos-integration cases=92 duration_ms=262"
        status: pass
    human_judgment: false
  - id: D4
    description: "The evidence binding genuinely refuses evidence recorded against a different lane source"
    requirement: "QUAL-04"
    verification:
      - kind: integration
        ref: "appended one comment to the lane -> gate refused with 'the lane's own source changed since that evidence was recorded (recorded 278b23c0635f6951, now ba7121f004cce649)'; file restored byte-identically"
        status: pass
    human_judgment: false

duration: 60min
completed: 2026-09-03
status: complete
---

# Phase KPL-03 Plan 18: Remove the sleep-then-read-once shape from every lane row Summary

**Every row of the macOS integration lane now settles on the condition it is about to assert, and the resulting flake rate is measured — ten consecutive full runs, 150/150 row executions, two of them under full CPU load — so a green lane means the product works rather than that the machine happened to be fast.**

## Performance

- **Duration:** ~60 min (of which ~30 min is the ten-run measurement itself)
- **Started:** 2026-09-03T21:41:00Z
- **Completed:** 2026-09-03T22:35:00Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- **Converted every sleep-then-read-once site in the lane**, found by shape across the whole file rather than from the plan's line numbers: A1 (enabled state, sync status), A2 (row announcements, roving focus, selection), A3 (both dialogs and the conflict heading), A5 (detail mount, Complete/Reopen, final focus), A6 (both dialog focus reads), A8 (settings pane, arbitration), A9 (caret before and after, frontmost return), A11 (selection, disabled state), A14 (live re-theme), A15 (layout reflow after resize).
- **Measured the rate instead of assuming it:** ten consecutive `--all` runs with no code change between them, 150/150 rows, 92 cases each, all ten reporting `SETTINGS restore=VERIFIED`. Runs 4 and 7 ran against 18 CPU spinners on an 18-core machine and were measurably slower while still passing.
- **Proved the gate on that evidence:** `lanes=9 failed=0`, `macos-integration cases=92 duration_ms=262` — 262ms for 92 cases is itself the proof of reuse, since a real run is ~170s.
- **Verified the evidence binding is live**, rather than trusting that 55b9398 works: appending one comment to the lane made the gate refuse the record.
- **Removed a latent FALSE PASS from A8** (see Deviations) — the more dangerous sibling of the flakes this plan was written to remove.
- **Corrected the rule recorded in O-24**, which as written would have reintroduced the defect.

## Task Commits

1. **Task 1: Convert every sleep-then-read-once site** — `509e323` (fix)
2. **Task 2: Measure the flake rate** — no code change; measurement only (ten runs, tally below)
3. **Task 3: Prove the gate, record the result** — `a2f73a7` (docs)

## Files Created/Modified

- `tooling/verify-macos-integration.mjs` — every row settles on its asserted condition; `waitFor` gained `onTimeout: 'return'`; A6's ad-hoc polling loop folded into `settledFocus`; shared `usableFocus`/`describeFocus` helpers; the rule stated in `waitFor`'s own documentation.
- `.planning/HANDOFF.json` — O-24 and O-27 closed, O-28 and O-29 added.
- `.planning/phases/KPL-03-mac-daily-loop/.continue-here.md` — new RESUME block with the tally, the digest, the corrected rule and the binding proof.

## The measurement (Task 2)

Ten consecutive `node tooling/verify-macos-integration.mjs --all`, no code change between them, all against
`application_digest=5f8ad9faa50749a5fa0afeb3d34341cfca50694cc61c428f71b94f2d853aeace`:

```
=== RUN 1 END 21:51:30 exit=0 restore_verified=1 loaded=no ===
=== RUN 2 END 21:54:18 exit=0 restore_verified=1 loaded=no ===
=== RUN 3 END 21:57:08 exit=0 restore_verified=1 loaded=no ===
=== RUN 4 END 22:00:53 exit=0 restore_verified=1 loaded=yes ===
=== RUN 5 END 22:03:43 exit=0 restore_verified=1 loaded=no ===
=== RUN 6 END 22:06:34 exit=0 restore_verified=1 loaded=no ===
=== RUN 7 END 22:10:05 exit=0 restore_verified=1 loaded=yes ===
=== RUN 8 END 22:12:56 exit=0 restore_verified=1 loaded=no ===
=== RUN 9 END 22:15:45 exit=0 restore_verified=1 loaded=no ===
=== RUN 10 END 22:18:36 exit=0 restore_verified=1 loaded=no ===
=== TEN CONSECUTIVE RUNS COMPLETE 22:18:36 ===

--- per-row tally across 10 runs ---
A1  PASS=10 FAIL=0     A6  PASS=10 FAIL=0     A11 PASS=10 FAIL=0
A2  PASS=10 FAIL=0     A7  PASS=10 FAIL=0     A12 PASS=10 FAIL=0
A3  PASS=10 FAIL=0     A8  PASS=10 FAIL=0     A13 PASS=10 FAIL=0
A4  PASS=10 FAIL=0     A9  PASS=10 FAIL=0     A14 PASS=10 FAIL=0
A5  PASS=10 FAIL=0     A10 PASS=10 FAIL=0     A15 PASS=10 FAIL=0

every run: rows=15 failed=0 cases=92
every run: SETTINGS restore=VERIFIED every mutated setting matches its captured value   (10 of 10)
```

**Which runs were loaded, and that the load was real.** Runs 4 and 7 ran against 18 concurrent CPU spinners on an 18-core machine (started before the run, killed after it). The load is visible in the timings, which is what makes the loaded runs evidence rather than decoration:

```
run   total    A3        A5        load
1     168.3s   14.66s    43.09s    idle
2     167.9s   14.62s    43.55s    idle
3     170.8s   15.13s    44.60s    idle
4     222.4s   16.20s    51.76s    LOADED
5     170.0s   14.95s    44.19s    idle
6     171.3s   14.65s    44.90s    idle
7     208.3s   16.51s    50.33s    LOADED
8     171.4s   14.99s    44.89s    idle
9     169.0s   14.72s    43.54s    idle
10    170.4s   14.86s    44.57s    idle
```

A3 at 16.2s under load is the same dilation that accompanied the original A4 failure (A3 16.2s against its usual 5.5s at the time). It now passes there.

The driver aborted the tally on any run that failed OR that did not print `SETTINGS restore=VERIFIED`; it never had to.

**Load was CPU, not concurrent lane runs.** The plan suggested "several concurrent `pnpm test:desktop` runs" as an alternative; that was deliberately not used. Concurrent Electron suites open windows and take keyboard focus, and this lane posts real CGEvents to whatever is frontmost — the measurement would have been of the harness interfering with itself, and it also mutates shared system settings. CPU spinners produce the scheduling pressure without touching the frontmost application or the settings domain.

## The gate (Task 3)

```
Desktop phase gate summary: lanes=9 failed=0
  PASS typecheck-desktop cases=1 duration_ms=1080
  PASS typecheck-web cases=1 duration_ms=2208
  PASS unit-pure-vector-store-worker-performance cases=164 duration_ms=1023
  PASS ipc-hostile-bridge cases=66 duration_ms=738
  PASS electron-e2e cases=57 duration_ms=53057
  PASS package-once cases=1 duration_ms=12621
  PASS packaged cases=10 duration_ms=7986
  PASS macos-integration cases=92 duration_ms=262
  PASS privacy cases=1 duration_ms=19
Desktop phase gate: PASSED
```

The evidence it consumed:

```
LANE_EVIDENCE reuse=true application_digest=5f8ad9faa50749a5fa0afeb3d34341cfca50694cc61c428f71b94f2d853aeace
  recorded_at=2026-09-03T22:18:34.719Z source_revision=55b939863581178a4749d2575fd5b4e52e9cb66c
  file=/Users/jon/projects/keepling/.artifacts/macos-integration/evidence/5f8ad9fa….json
LANE_EVIDENCE note=this-gate-run-executed-no-rows-and-changed-no-system-setting
```

`recorded_at=22:18:34` is run 10 of the tally. 262ms for 92 cases is the proof of reuse.

**The binding was verified rather than trusted.** Appending a single comment line to the lane produced:

```
macOS integration lane failed: the lane's own source changed since that evidence was recorded
(recorded 278b23c0635f6951, now ba7121f004cce649), so it no longer describes these assertions
```

The file was then restored byte-identically (`git status` clean) and the gate went green again. This is the mechanism that stops one lucky run from becoming durable green; it works.

## Decisions Made

1. **Poll for the asserted condition, never for quiescence.** Written into `waitFor`'s own documentation so the next person meets it before writing a wait. Both a `null` focus and a pending dead key are stable indefinitely, so a quiescence check settles happily on the failure state and reports a pass.
2. **`waitFor` gained `onTimeout: 'return'` rather than a third helper.** At the deadline it hands the last (falsy) observation back so the caller's own `check` fails with its own detail. The default (fail loudly) is kept where a missing precondition would make the assertion *vacuous* rather than false — see A8 below. Two mechanisms, not three: `settledFocus(handle, { until })` for AX focus, `waitFor` for everything else. A6's ad-hoc polling loop was folded into the former.
3. **A14's settle condition now covers every condition A14 asserts** — background changed AND more than one significant colour AND contrast ≥ 4.5:1 — because a window caught mid-repaint can already report a changed background while its text has not been repainted, which would measure a transient ratio. Previously it settled only on "the background changed".
4. **No assertion was weakened, narrowed or deleted.** The only substantive change to what a row *claims* is A8, where a vacuous claim was made non-vacuous (strengthening). Failure detail was added in several places (`describeFocus(...)`, observed `enabled` values, row announcements) so a red row now says what it saw.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] Row A8 could produce a FALSE PASS, not a flake**

- **Found during:** Task 1, while converting A8's `sleep(1800)`-then-read-once settings-pane read.
- **Issue:** Both A8 phases assert a *negation* — `!/Quick Entry shortcut isn.t available/.test(settingsText)` ("Keepling does not report the accelerator as unavailable"). Asserted against a Settings pane that has not rendered yet, `settingsText` is empty and the negation is **vacuously true**. A slow Settings window would therefore have produced a green A8, not a red one. This is strictly worse than the flakes this plan targets: a flake is visible, a vacuous pass is not.
- **Fix:** Both phases now wait for the pane to have *stated a position* — either `Current shortcut` or the unavailable message is present — and that wait deliberately does **not** use `onTimeout: 'return'`, so a pane that never renders fails the row loudly instead of returning an empty string into the negation.
- **Files modified:** `tooling/verify-macos-integration.mjs`
- **Verification:** A8 10/10 across the tally.
- **Committed in:** `509e323`
- **Recorded as:** O-28 in `.planning/HANDOFF.json` (the class is not lane-specific; the Playwright suites have not been swept for it).

**2. [Rule 2 — Missing critical functionality] Failing rows could not say what they saw**

- **Found during:** Task 1.
- **Issue:** Several converted checks would have thrown a `TypeError` on a null observation (`movedRow.title`, `ancestryText(focused)` in A2/A3/A4) instead of failing with a message, and others reported no observation at all.
- **Fix:** Null-safe assertions plus a shared `describeFocus(node)` and explicit observed values in detail strings.
- **Files modified:** `tooling/verify-macos-integration.mjs`
- **Verification:** `node --check`, then the ten-run tally.
- **Committed in:** `509e323`

---

**Total deviations:** 2 auto-fixed (1 × Rule 1, 1 × Rule 2). **Impact:** no scope creep; both are inside the file this plan owns, and the first is the same class of defect the plan exists to remove.

## Issues Encountered

**A3 — a lane race, NOT a product defect.** The plan started from a red A3 ("the conflict moves focus to its own heading … focus was on nothing") and asked explicitly for a plain answer if a row turned out to be a genuine product defect. It is not one. The conflict heading **mounts before** the app moves focus onto it; the row read focus the instant `waitFor` found the heading, sampling the gap in between. Polling for the focus the check asserts on (10s deadline) makes A3 10/10, and the first verification run showed it passing in 14.8s, well inside the deadline. The product moves focus to the conflict heading correctly.

**Rows converted that had never been observed to flake** (A1's sync-status read, A2's row announcements, A9's caret and frontmost reads, A11, A15) were converted anyway because they share the shape. Two of them are not merely theoretical: A1's and A2's "Saved on this Mac" assertions were made against a wait that only required the row *title* to appear, so they asserted on a second paint they never waited for.

## Reads deliberately left alone (they are samples, not races)

- `pixelAppearanceRow`'s `before = measureContrast(handle)` for A14 — the *point* is to capture the pre-change appearance; waiting for a condition here would defeat the comparison. The app is idle and the setting has not been applied yet.
- The contrast measurements in A10, A12, A13 and A11 — those settings are applied **before** the app launches, so the value read is a steady state, not a value in flight. Only A14 changes a setting while the app is open, and only A14 polls.
- `tabUntil` (already polls), `captureTaskByKeyboard`'s `waitFor`, and `settledFocus` itself.
- Fixed `sleep()` calls that are followed by a *poll* rather than by a read (e.g. `postKeys(...)` then `sleep(400)` then `tabUntil(...)`) — those are pacing, not races. They remain, and are harmless; every read downstream of them is bounded.
- `readSystemSettings()` assertions ("the setting is genuinely applied at the OS level") — `applySystemSettings` is synchronous and these read the OS, not the app.

## Known Stubs

None.

## User Setup Required

None — all three macOS TCC grants (Accessibility, Screen Recording, Full Disk Access) were already in place, and the lane restored every mutated system setting on all twelve runs it performed (10 tally + 1 A2/A3 verification + gate runs, which mutate nothing).

## Next Phase Readiness

- The desktop phase gate is green end-to-end (`lanes=9 failed=0`) on evidence produced by this lane's fixed rows.
- **O-25 remains open and is now the load-bearing one:** the `desktop-macos-integration` CI job is still non-blocking. The lane's trustworthiness has been measured locally; nothing yet forces it to stay green in CI.
- **O-29** records the honest bound: 0 failures in 10 runs bounds the per-row rate below roughly 2% at 95% confidence. It does not prove zero. If a row flakes again, fix the race in that row — do not re-record until a run happens to pass.
- Any future edit to `tooling/verify-macos-integration.mjs` invalidates this evidence by design and requires a fresh `--all` recording on Jon's machine.

---
*Phase: KPL-03-mac-daily-loop*
*Completed: 2026-09-03*
