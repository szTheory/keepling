---
phase: KPL-03-mac-daily-loop
plan: 26
subsystem: testing
tags: [macos-integration, accessibility, ax-api, cgevent, flake-diagnosis, seeded-shuffle]

# Dependency graph
requires:
  - phase: KPL-03-mac-daily-loop (03-25)
    provides: tooling/verify-package-reproducibility.mjs, --reuse-if-unchanged on package-desktop.mjs, package-reproducible gate lane, a stable applicationDigestSha256 that survives repeated gate runs
provides:
  - A machine-state census (censusMachineState/assertCleanSlate) that refuses to start or continue on a machine not in the state every row assumes, naming the exact dirty item
  - Between-row restoration of the input source and every managed system setting, closing the exit-scoped-only restoration gap that let state leak across rows and across runs
  - A leftover settings-capture.json is now a loud, attributed refusal (assertNoLeftoverCapture) with a --restore-from-capture remedy, instead of being silently adopted as a new baseline
  - Mid-sequence FOCUS_STOLEN detection naming the pid and bundle identifier that took focus, converting a silent mistype into an immediate, attributed failure
  - Teardown that waits for confirmed absence from the AX/window list before the next row starts (confirmTeardownComplete), not just process reaping
  - A reference-counted disposable-profile cleanup (profileRefCounts/retainProfile) safe for A3's deliberate same-profile handle reuse
  - --order <source|shuffle> --seed <n> with a dependency-free seeded PRNG, proving a full recording pass is a property of the rows, not one ordering
  - A fresh, complete, reproducible A1-A15 recording (rows=15 failed=0 cases=93) bound to the current applicationDigestSha256, reused cleanly by two consecutive verify-desktop-phase.mjs gate runs
affects: [03-27, phase-6-ci]

# Actuals (#2632)
actuals:
  tokens: 8200
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Machine-state barrier: census real reads (managed settings, input source, process list via pgrep -f against real compiled binary paths) before/between/after every row, and fail loudly by naming the exact mismatching item rather than warning or skipping."
    - "Chunked mid-sequence assertion: postKeys re-checks the condition it depends on (frontmost) after each delivered chunk rather than only before the whole sequence, so a stolen precondition is caught at its own moment instead of surfacing as a later unrelated timeout."
    - "Reference-counted disposable resources: a resource (profile directory) allocated once but deliberately shared across two handles in one row is only released when every referencing handle is done with it, not on the first handle's teardown."
    - "Seeded PRNG for order-independence proofs: a tiny inline mulberry32 (no dependency) makes a reproducible non-default ordering a first-class, citable CLI mode rather than a one-off manual test."

key-files:
  created: []
  modified:
    - tooling/verify-macos-integration.mjs

key-decisions:
  - "The machine-state census reads settings/input-source exclusively through the existing SystemSettings capture subcommand and identifies processes via pgrep -f against real compiled binary paths (the packaged executable, the compiled HotkeyRival probe) -- SystemSettings.swift and AXProbe.swift needed zero changes, confirmed by an empty git diff on both files across all three tasks."
  - "FOCUS_STOLEN checking is opt-out (assertFrontmost: false), not opt-in, applied at exactly the three call sites whose own correct effect is an intentional focus change (A9's accelerator posted from the prior application, and A9's final submit/discard keys) -- every other call site, including all of A8's same-app accelerator posts, keeps the check on by default."
  - "quitApplication's new confirmTeardownComplete is a no-op for probeBinary === null handles (the untrusted/pixel-appearance rows) by design, since those rows deliberately never touch the accessibility API -- verified --without-accessibility-trust is unaffected (rows=4 failed=0)."
  - "A3's same-profile handle reuse (capture a task, quit, relaunch with syncMode: 'conflict' against identical on-disk data) is the ONLY place in the file with this pattern, confirmed by grep across every allocateProfile call site -- reference counting was scoped narrowly to that one row rather than restructuring every row's profile lifecycle."
  - "The final recorded evidence run (step 5) was preceded by committing all source changes first, so git status --porcelain was empty at the moment recording began, per the plan's own record-last rule."

requirements-completed: [MAC-02, QUAL-03]

coverage:
  - id: D1
    description: "A machine-state census refuses before any row runs (and between rows) when the machine is not in the state rows assume, naming the specific dirty item (leftover process, unrestored settings-capture.json)"
    requirement: MAC-02
    verification:
      - kind: other
        ref: "node tooling/verify-macos-integration.mjs --rows A1 (a planted settings-capture.json refused with MACHINE_STATE_DIRTY, exit 1; a manually launched Keepling process refused at before-first-row)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Input source and managed settings are restored between rows, not only at process exit; --restore-from-capture recovers a leftover capture file"
    requirement: MAC-02
    verification:
      - kind: other
        ref: "node tooling/verify-macos-integration.mjs --rows A7 && node tooling/verify-macos-integration.mjs --rows A1 (no leaked input source between separate invocations); --restore-from-capture applies, verifies, and deletes the capture file"
        status: pass
    human_judgment: false
  - id: D3
    description: "Mid-sequence focus theft and an unfinished teardown fail immediately, naming the responsible pid/bundle, instead of surfacing later as an unrelated timeout"
    requirement: MAC-02
    verification:
      - kind: other
        ref: "node tooling/verify-macos-integration.mjs --rows A8,A9 (rows=2 failed=0); manual reproduction of the FOCUS_STOLEN predicate against the real compiled AXProbe binary and a real second application raised mid-test"
        status: pass
    human_judgment: false
  - id: D4
    description: "A full A1-A15 recording passes on two consecutive runs and under a seeded shuffled order, and the phase gate reuses that evidence cleanly across two consecutive invocations"
    requirement: QUAL-03
    verification:
      - kind: other
        ref: "node tooling/verify-macos-integration.mjs --all (x2, rows=15 failed=0 cases=93 both times); --all --order shuffle --seed 1337 (rows=15 failed=0, ROW_ORDER differs from source); node tooling/verify-desktop-phase.mjs (x2, lanes=11 failed=0 both times, macos-integration reused evidence in 251ms/248ms)"
        status: pass
    human_judgment: false

duration: 2h 30min
completed: 2026-09-04
status: complete
---

# Phase KPL-03 Plan 26: macOS Machine-State Barrier and Order-Independence Summary

**Built a real-read machine-state census, mid-sequence focus-theft detection, and a confirmed-teardown wait for the macOS integration lane, fixed a Rule 1 profile-deletion regression it exposed in row A3, and proved a full A1-A15 recording passes on two consecutive runs and under a seeded shuffle -- closing the second half of VERIFICATION.md Gap 1.**

## Performance

- **Duration:** 2h 30min (includes a checkpoint pause for a locked screen; active execution time was roughly 90 minutes)
- **Started:** 2026-09-04T17:15:00Z
- **Completed:** 2026-09-04T18:45:00Z
- **Tasks:** 3
- **Files modified:** 1

## Accomplishments

- `censusMachineState()`/`assertCleanSlate()`: a real-reads-only barrier (managed settings + input source via the existing `SystemSettings capture`, process counts via `pgrep -f` against real compiled binary paths) wired before the first row, before every row, and after every row. On the very first run of this session it immediately caught a genuine leftover `settings-capture.json` from a previous interrupted run on this machine -- refused with `MACHINE_STATE_DIRTY`, not silently adopted as a new baseline. `--restore-from-capture` recovers it (applies, verifies by re-reading, deletes the marker only after `SETTINGS restore=VERIFIED`).
- `restoreBetweenRows()`: input source and every managed setting are now put back to baseline after every row, not only at process exit -- verified with `--rows A7 && --rows A1` showing zero leaked input source between two entirely separate process invocations.
- `postKeys` delivers a sequence in chunks and re-checks frontmost after each one, failing immediately with `FOCUS_STOLEN by_pid=<pid> by_bundle=<id> during=<sequence>` instead of letting the rest of a sequence silently go to the wrong window. Three call sites whose own correct effect is an intended focus change (A9's cross-application accelerator post and its final submit/discard keys) are the explicit, narrow exceptions.
- `confirmTeardownComplete()`: `quitApplication` now waits for the pid to actually leave the AX window list and frontmost status, not just for the process to be reaped -- closing the race where the next row's `ensureFrontmost` started against a teardown that looked done but was still finishing at the window-server level. A8's rival-process teardown now waits on the same process census, not a kill-and-hope.
- **Rule 1 bug found and fixed during Task 3's own verification run:** the new profile-deletion-on-teardown wiped row A3's captured task before its second (same-profile, `syncMode: 'conflict'`) handle could launch against it, reproduced as `Inbox Is Clear` in the AX tree and a `timed out waiting for the inline conflict presentation` failure. Fixed with reference counting (`profileRefCounts`/`retainProfile`), scoped to the one row in the file that deliberately shares a profile across two handles.
- `--order <source|shuffle> --seed <n>` with an inline, dependency-free seeded PRNG (mulberry32 + Fisher-Yates). `--all --order shuffle --seed 1337` produced `ROW_ORDER mode=shuffle seed=1337 order=A14,A12,A2,A1,A6,A7,A10,A9,A13,A4,A5,A8,A11,A15,A3` and still reported `rows=15 failed=0`. Evidence records now carry `rowOrder` and `seed`.
- A full recording sequence: two consecutive `--all` runs (`rows=15 failed=0 cases=93` both times), one shuffled run, and a final post-commit recording run whose evidence `node tooling/verify-desktop-phase.mjs` reused cleanly across two consecutive gate invocations (`lanes=11 failed=0` both times; `macos-integration` reused in 251ms/248ms rather than re-running).
- `tooling/macos-integration/SystemSettings.swift` and `AXProbe.swift` are byte-for-byte unchanged across all three tasks (confirmed by empty `git diff --stat`) -- the census reads through the existing `capture` subcommand, and `frontmost` already reported a bundle identifier.

## Task Commits

1. **Task 1: A machine-state census that refuses, names the item, and runs between rows** - `f09a2f8` (feat)
2. **Task 2: Make focus theft and unfinished teardown loud at the moment they happen** - `20f956f` (feat)
3. **Task 3: Prove order-independence, record evidence last, and close the gate** - `14894c4` (feat, includes the Rule 1 profile-reuse fix found while satisfying this task's own verify sequence)

**Plan metadata:** committed alongside this SUMMARY.

## Files Created/Modified

- `tooling/verify-macos-integration.mjs` - Machine-state census and barrier, between-row restoration, `--restore-from-capture`, chunked `postKeys` with `FOCUS_STOLEN` detection, `confirmTeardownComplete`, reference-counted profile cleanup, `--order`/`--seed` with a seeded shuffle, `rowOrder`/`seed` evidence fields.

## Decisions Made

See `key-decisions` in the frontmatter above.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Profile-deletion regression broke row A3's same-profile conflict fixture**

- **Found during:** Task 3, while running the required `--all` sequence (first attempt after committing Task 2)
- **Issue:** Task 2's `removeHandleProfile` deleted a handle's disposable profile directory the moment its own teardown was confirmed. Row A3 is the only row in the file that deliberately reuses one allocated profile across two separate handles (capture a task, quit, relaunch with `syncMode: 'conflict'` against the identical on-disk SQLite data). The eager delete wiped the just-captured task before the second handle ever launched, so the conflict fixture had nothing to report a conflict against -- reproduced independently as `Inbox Is Clear` in a manual AX-tree dump of the reused profile, matching the row's own `timed out waiting for the inline conflict presentation` failure exactly.
- **Fix:** Added `profileRefCounts`/`retainProfile`: a profile is deleted only once every handle that was ever given that path has had its own teardown confirmed. Row A3 now calls `retainProfile(profilePath)` before its first handle's `quitApplication`, so the shared directory survives until the second (conflict) handle's own teardown completes. Every other row keeps its original one-allocation-per-handle behavior unchanged (confirmed: `--rows A1` still reports `cases=10`, `--without-accessibility-trust` still reports `rows=4 failed=0`).
- **Files modified:** `tooling/verify-macos-integration.mjs`
- **Verification:** `node tooling/verify-macos-integration.mjs --rows A3` failed twice with the profile wiped, passed after the fix (`cases=5`), and the same fixed code produced three consecutive full-15-row `--all`/shuffle passes with A3 green in each.
- **Committed in:** `14894c4` (folded into Task 3's commit since it was required to satisfy Task 3's own `--all` verification and Task 2's commit had already landed; disclosed in the commit message)

---

**Total deviations:** 1 auto-fixed (Rule 1 bug)
**Impact on plan:** Necessary for correctness -- without it, no `--all` recording run could ever pass, since A3 is one of the 15 rows the completeness rule requires. No scope creep: the fix is narrowly scoped to the one row that shares a profile, and every other row's behavior is unchanged.

## Environment Notes (not deviations from this plan's code)

This machine is a shared, actively multi-tenant desktop during this session: `who` showed two concurrent `claude` sessions and a `chrome-devtools-mcp` session running throughout, plus a real macOS `SecurityAgent` (system authentication) dialog appeared and held frontmost late in this session, unrelated to this work. Consequently, several verification attempts hit **named, confirmed, third-party interference** rather than a lane defect:

- Two `FOCUS_STOLEN` events (`by_bundle=com.google.Chrome`, `by_bundle=com.openai.codex`) and one `settledFocus` miss in A3, each confirmed via `AXProbe frontmost` plus the absence of any leftover Keepling/rival process or `settings-capture.json` afterward, then a clean retry.
- Two additional interference events surfaced when re-confirming the plan's literal shuffle `<verify>` command a second time *after* the Task 3 commit (a same-application, different-window `FOCUS_STOLEN by_bundle=com.apple.Terminal`, and later a real `com.apple.SecurityAgent` dialog that was still open when this SUMMARY was written). These did not affect the plan's actual required proof: the required two-consecutive-`--all`-plus-shuffle sequence, the recorded evidence, and both `verify-desktop-phase.mjs` gate runs had already completed cleanly, in order, **before** the Task 3 commit and before either of these two later events occurred.
- Per the standing rule, none of this was treated as a lane pass or as a code defect, no timeout/WAIT_SCALE/tab-budget was raised in response to any of it, and no evidence was recorded from a run that needed a retry -- the recorded evidence is from the single clean post-commit run described above.

An operator running this lane on a shared machine should expect this class of interruption and should not treat it as a regression in the lane itself.

## Issues Encountered

None beyond the Rule 1 deviation and the environmental interference both documented above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- VERIFICATION.md Gap 1 is now closed on both halves: 03-25 closed the packaging-non-reproducibility root cause, and this plan closes the `--all` recording run's cross-row/cross-run interference. `node tooling/verify-desktop-phase.mjs` reports `lanes=11 failed=0` on two consecutive runs with `macos-integration` reusing digest-bound evidence both times.
- 03-27 (Gap 2, desktop visual-snapshot evidence) remains and was explicitly out of scope for this plan.
- The census's real-read design means a future row or fixture that mutates a NEW managed setting or spawns a new long-lived process class will need its own `MANAGED_KEYS`/process-pattern entry to be covered by the barrier -- not automatic, and worth checking when a new row is added.
- A real `com.apple.SecurityAgent` dialog was observed open on this shared machine at the end of this session, unrelated to Keepling or this lane -- flagged for the user's awareness, not something this plan can or should act on.

---
*Phase: KPL-03-mac-daily-loop*
*Completed: 2026-09-04*

## Self-Check: PASSED

- `tooling/verify-macos-integration.mjs` exists on disk: FOUND
- `.planning/phases/KPL-03-mac-daily-loop/03-26-SUMMARY.md` exists on disk: FOUND
- Commit `f09a2f8` (Task 1) found in git log: FOUND
- Commit `20f956f` (Task 2) found in git log: FOUND
- Commit `14894c4` (Task 3) found in git log: FOUND
- Re-ran plan-level `<verification>`: `--all` reported `rows=15 failed=0` on two consecutive invocations (cases=93 both times); `--all --order shuffle --seed 1337` reported `rows=15 failed=0` with a `ROW_ORDER` line materially different from source order; `--without-accessibility-trust` reported `rows=4 failed=0`; `node tooling/verify-desktop-phase.mjs` reported `lanes=11 failed=0` twice consecutively with no lane at `cases=0`; `git diff -- tooling/verify-macos-integration.mjs | grep -E "^\+.*(timeoutMs: [0-9]|WAIT_SCALE|limit: [0-9])"` returned no matches (no raised timeout, WAIT_SCALE, or tab budget).
