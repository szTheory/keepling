---
phase: KPL-03-mac-daily-loop
plan: 20
subsystem: testing
tags: [macos, accessibility, axuielement, cgevent, flake, race, deadlines, polling]

requires:
  - phase: KPL-03-mac-daily-loop
    provides: "the fifteen-row macOS integration lane, its digest-bound evidence cache, waitFor/settledFocus from 03-15 through 03-18"
  - phase: KPL-03-mac-daily-loop
    provides: "03-19's SyncStatusRow renderer surface, which had to be ruled out as the cause before the lane could be blamed"
provides:
  - "A macOS integration lane in which no row ACTS on the product after a fixed sleep -- every keystroke, tab traversal and assertion waits for the observable consequence of the action before it"
  - "tabUntil that waits for each press to land before pressing again, with the 24-press budget and every predicate unchanged"
  - "typeIntoField: types real CGEvent keystrokes and does not return until the field actually contains them"
  - "ONE lane-wide WAIT_SCALE replacing per-row deadline tuning, closing O-32"
  - "A MEASURED end of the standalone/--all asymmetry: A3 at 11.55-11.92s inside --all against 11.75-11.89s standalone, where it was 29.5s against 14.6-16.5s"
  - "A real product defect found and filed rather than worked around silently: O-36, Quick Entry loses Escape after Keep Draft"
affects: [KPL-03 verification, desktop phase gate, MAC-02, QUAL-04, Quick Entry focus management]

actuals:
  tokens: 9800
  tasks: 3
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Before acting on the product, wait for the observable consequence of the PREVIOUS action -- the action-side twin of 03-18's read-side rule"
    - "One lane-wide wait multiplier applied UNIFORMLY, never per row and never per invocation mode"
    - "A keystroke helper returns only once its effect is readable in the AX tree, so callers never act on an unrepainted frame"

key-files:
  created: []
  modified:
    - tooling/verify-macos-integration.mjs
    - .planning/HANDOFF.json

key-decisions:
  - "The A3 failure was a lane race, not a product regression: the Discard Draft button does not EXIST until the draft is non-empty, and the row tabbed for it 300ms after typing"
  - "03-19's SyncStatusRow was verified NOT to be in the Quick Entry tab order before the lane was blamed -- it mounts in DesktopShell only"
  - "WAIT_SCALE is applied uniformly rather than only under --all: a mode-dependent factor would recreate the very standalone/--all split O-32 describes"
  - "tabUntil waits for focus to MOVE rather than pressing on a fixed cadence; the budget was not raised and no predicate was relaxed"
  - "activateButton's trailing sleep was deleted outright, not shortened -- all ten call sites already follow it with a waitFor on the consequence they care about"
  - "The Quick Entry Escape defect (O-36) is filed as an open item and named in the helper's comment; only the TEARDOWN step was made deterministic, no assertion was touched"

patterns-established:
  - "Waiting for a control to EXIST before tabbing for it, when its existence is a consequence of the action just taken"
  - "typeIntoField matches ANY field carrying the label, because the main window's capture field shares Quick Entry's label"
  - "Process teardown waits for the process to be REAPED, not for a guess at how long reaping takes"

requirements-completed: [MAC-02, QUAL-04]

coverage:
  - id: D1
    description: "No row in the macOS lane acts on the product after a fixed sleep; every action waits for the consequence of the one before it"
    requirement: "QUAL-04"
    verification:
      - kind: integration
        ref: "grep -n 'sleep(' tooling/verify-macos-integration.mjs -> 9 hits, all inside polling loops or Promise.race deadlines, none preceding an action (was 31 non-polling)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Row A3 passes standalone AND inside a complete --all run, five consecutive times, with no code change between them"
    requirement: "QUAL-04"
    verification:
      - kind: integration
        ref: "node tooling/verify-macos-integration.mjs --rows A3 (x5: 11752/11844/11894/11755/11830 ms) and id=A3 inside five --all runs (11690/11567/11554/11924/11814 ms)"
        status: pass
    human_judgment: false
  - id: D3
    description: "The deadline-under-load problem is resolved lane-wide rather than per row (O-32)"
    requirement: "QUAL-04"
    verification:
      - kind: integration
        ref: "single WAIT_SCALE applied in waitFor, settledFocus, ensureFrontmost, launch and teardown loops; A3's --all/standalone spread collapsed from 29.5s vs 14.6-16.5s to 11.55-11.92s vs 11.75-11.89s"
        status: pass
    human_judgment: false
  - id: D4
    description: "A full --all run records evidence for the artifact under test at rows=15 failed=0, five consecutive times"
    requirement: "MAC-02"
    verification:
      - kind: integration
        ref: "five consecutive `node tooling/verify-macos-integration.mjs --all` on application_digest=937b279c..., each rows=15 failed=0 cases=92 (159136/158106/157982/160720/160625 ms)"
        status: pass
    human_judgment: false
  - id: D5
    description: "The desktop phase gate is green on evidence recorded by a run containing these fixes"
    requirement: "MAC-02"
    verification:
      - kind: e2e
        ref: "node tooling/verify-desktop-phase.mjs -> Desktop phase gate summary: lanes=9 failed=0"
        status: pass
    human_judgment: false

duration: 75min
completed: 2026-09-04
status: complete
---

# Phase KPL-03 Plan 20: Remove the sleep-then-ACT shape from the macOS lane Summary

**The macOS lane no longer acts on elapsed time: every keystroke, tab traversal and assertion now waits for the observable consequence of the action before it, and the standalone/`--all` asymmetry that O-32 named is gone rather than padded — A3 now runs 11.55–11.92s inside `--all` against 11.75–11.89s standalone, where it was 29.5s against 14.6–16.5s.**

## Performance

- **Duration:** ~75 min (of which ~45 min is the five-run proof and the gate)
- **Tasks:** 3
- **Files modified:** 2

## The RED, stated honestly

The plan's RED — A3 failing with `could not reach the Discard Draft button by
keyboard within 24 tab presses (focus stopped on AXTextField "What do you want
to keep?")` — **did not reproduce on demand.** The first `--rows A3` run of this
session PASSED, in 14635ms, on `application_digest=937b279c…`.

That is not a reason to skip the work; it is the diagnosis. A row that fails
twice with two different messages and then passes on identical, verified-
reproducible bytes is racing by definition. The RED here is therefore the code
SHAPE, which is deterministic and was counted: 31 non-polling `sleep()` calls,
every one of them followed by an action that assumed the previous action had
already landed.

A second, genuinely deterministic RED did appear mid-task and is recorded below
under Deviations — the first run after the conversion failed with `timed out
waiting for Quick Entry to close`, which turned out to be a real product defect
the old fixed sleeps had been hiding.

## Task Commits

1. **Tasks 1 + 2: convert every sleep-then-ACT site; resolve deadlines lane-wide** — `cc8bf64` (fix). Committed as one unit because they are one: `tabUntil`'s new per-press wait is itself a bounded wait and is meaningless without the scale that bounds it.
2. **Task 3: prove it** — this SUMMARY and the HANDOFF update (docs). Task 3 produced no code change by design; its output is the measurement below.

## What changed in `tooling/verify-macos-integration.mjs`

- **`tabUntil` waits for each press to LAND before pressing again.** It pressed
  Tab on a fixed 120ms cadence, which outruns a loaded renderer: presses queue
  while focus is read behind them, the budget is consumed by moves that were
  never observed, and the row reports "could not reach X within N presses"
  against a window that is working. **The 24-press budget was not raised and no
  predicate was relaxed** — focus that genuinely never moves still burns every
  press and still fails with what it last saw, because the per-press wait
  returns at its own deadline instead of failing the row.
- **`typeIntoField`** posts real CGEvent keystrokes and does not return until
  the field actually contains them. It matches *any* field carrying the label,
  because while Quick Entry is open the main window's capture field is still in
  the tree under the same label and would satisfy a first-match wait forever.
  Its `expect` option handles appends, where what is typed (`" edited"`) is not
  what the field should read (`"Keyboard loop edited"`).
- **Wait for the control the previous action produces.** A3 and A6 now wait for
  the Discard Draft button to exist before tabbing for it. It only exists once
  the draft is non-empty — this is the measured A3 failure, exactly.
- **Every other sleep-then-ACT site** converted to the consequence it was
  guessing at: the field `cmd+n` produces; the detail editor `return` mounts;
  the dialog a Space opens or closes; the app becoming frontmost after `raise`;
  a killed process being reaped; the rival hot-key app exiting; the Settings
  pane closing before the accelerator is posted; TextEdit's caret landing before
  six relative `left` presses are aimed at it.
- **`activateButton`'s trailing `sleep(500)` was deleted, not shortened.** All
  ten call sites already follow it with a `waitFor` on the consequence they care
  about, which is a stronger and cheaper wait; the sleep only delayed it.
- **O-32, lane-wide:** one `WAIT_SCALE` multiplies every bounded wait —
  `waitFor`, `settledFocus`, `ensureFrontmost`, the launch loop, the teardown
  loops. It is applied **uniformly**, not only under `--all`, because a
  mode-dependent factor would recreate the standalone/`--all` split the item
  describes. It weakens nothing and costs nothing on the happy path: a wait
  whose condition is already true returns on its first poll, so the larger
  budget is only ever spent on a genuine failure.

**Sleeps remaining: 9**, down from 36 (31 of them non-polling). Every one is
inside a polling loop or a `Promise.race` deadline. None precedes an action.

## The five `--all` runs (Task 3)

All on `application_digest=937b279ce76952f0180c31ca1cf0deee0ccd42b199a13116d5f22adcfe3c2684`,
`source_revision=19bc60b9981c6bbeab65469166f9497877e525df`, no code change
between them.

| Run | Result | Cases | Duration | A3 duration |
| --- | ------ | ----- | -------- | ----------- |
| 1 | `rows=15 failed=0` | 92 | 159136 ms | 11690 ms |
| 2 | `rows=15 failed=0` | 92 | 158106 ms | 11567 ms |
| 3 | `rows=15 failed=0` | 92 | 157982 ms | 11554 ms |
| 4 | `rows=15 failed=0` | 92 | 160720 ms | 11924 ms |
| 5 | `rows=15 failed=0` | 92 | 160625 ms | 11814 ms |

75/75 row executions, 460/460 cases.

**Five consecutive A3 standalone runs:** 11752, 11844, 11894, 11755, 11830 ms —
all `status=PASS cases=5`.

**The point of those two columns together.** O-32 was about a row tuned in one
context and consumed in another. A3's spread across the two contexts is now
11554–11924 ms (`--all`) against 11752–11894 ms (standalone): the contexts are
indistinguishable. Before this plan it was 29.5s against 14.6–16.5s. The
asymmetry was removed, not absorbed by a bigger number — and the row got
**faster**, from 14.6s to 11.8s standalone, because waiting for a condition
returns the moment it holds while a sleep always costs its full length.

## The gate

```
Desktop phase gate summary: lanes=9 failed=0
```

Full lane list from that run:

```
  PASS typecheck-desktop cases=1 duration_ms=1061
  PASS typecheck-web cases=1 duration_ms=1785
  PASS unit-pure-vector-store-worker-performance cases=172 duration_ms=1180
  PASS ipc-hostile-bridge cases=66 duration_ms=646
  PASS electron-e2e cases=60 duration_ms=51907
  PASS package-once cases=1 duration_ms=12545
  PASS packaged cases=10 duration_ms=8135
  PASS macos-integration cases=92 duration_ms=269
  PASS privacy cases=1 duration_ms=17
Desktop phase gate: PASSED
```

`macos-integration cases=92 duration_ms=269` is itself the proof of evidence
reuse: a real run is ~160s.

## Deviations from Plan

### [Rule 1 — Bug, in the product, found not assumed] Quick Entry loses Escape after "Keep Draft" (filed as O-36)

**Found during:** Task 1, on the first run after the conversion.

**Issue:** The converted A3 failed deterministically with `timed out waiting for
Quick Entry to close`. The plan explicitly forbids treating a failure as a
product regression without evidence, so evidence was gathered: a standalone
AXProbe diagnostic reproduced the sequence twice and printed focus at each step.

After dismissing the discard confirmation with **Keep Draft**, AX focus is on
`AXWebArea "Keepling"` — the *document* — not on the `Discard Draft…` button
that opened the dialog. `apps/desktop/renderer/quick-entry.tsx` binds its Escape
handler with `onKeyDown` on a div *inside* the React root, so a keydown targeted
at the document never reaches it. Escape was posted and both windows were still
present 2s later (`windows=["Keepling","Keepling — Inbox"]`, capture fields=2).
Tabbing back into the field and posting the **same** Escape hid the window
immediately (`windows=["Keepling — Inbox"]`, capture fields=1).

So a person who opens the discard confirmation and keeps their draft loses
Escape as a way out of Quick Entry until they tab somewhere.

**Why the old code did not see it:** it pressed Escape after `sleep(400)` and
never checked whether anything happened.

**Why A6 does not fail on it:** `usableFocus()` accepts any non-`AXApplication`
node with a non-zero frame, and the `AXWebArea` qualifies. Focus is "usable" but
is not on the invoking control, which is what WAI-ARIA requires of a dismissed
dialog. Tightening `usableFocus` to exclude container roles would turn this into
a red row — a deliberate decision for a later plan, not a silent change here.

**Fix applied:** none to the product. A3 and A6 use Escape at that point purely
as **teardown** — neither asserts anything about Escape — so both now call
`returnFocusIntoQuickEntry()` first. The finding is named in that helper's
comment and filed as **O-36** in `HANDOFF.json`, with the reproduction, the
`quick-entry.tsx` cause, and the reason A6 is blind to it.

**Not a workaround of the plan's prohibition:** no assertion was weakened,
deleted or narrowed, no tab budget was reduced, and no sleep was widened.

### [Rule 2 — Missing critical wait] The plan's prohibition on blaming 03-19 was checked, not assumed

`SyncStatusRow` was confirmed to mount in `DesktopShell` only and not in
`quick-entry.tsx`, so it is not in the Quick Entry tab order and could not have
consumed A3's tab budget. The lane was blamed only after that was ruled out.

## Open Items

- **O-32 — CLOSED.** Written into `.planning/HANDOFF.json` per the plan's
  `open_item_protocol`, with the closing evidence, not only described here.
- **O-36 — NEW, open.** Written into `open_items`, not only into this SUMMARY.

## Known Stubs

None.

## Self-Check: PASSED

- `tooling/verify-macos-integration.mjs` — FOUND
- `.planning/phases/KPL-03-mac-daily-loop/03-20-SUMMARY.md` — FOUND
- `.planning/HANDOFF.json` — FOUND, O-32 `status: closed`, O-36 present
- commit `cc8bf64` — FOUND in `git log`
