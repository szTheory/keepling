---
phase: KPL-03-mac-daily-loop
plan: 17
subsystem: testing
tags: [vitest, playwright, electron, pnpm, github-actions, macos, tcc, swift]

requires:
  - phase: KPL-03-mac-daily-loop (03-15, 03-16)
    provides: the green macOS integration lane and the 9-lane desktop phase gate this plan must not weaken
provides:
  - Working test filters on all three desktop lanes, for BOTH `pnpm <lane> <filter>` and `pnpm <lane> -- <filter>`
  - "`pnpm test:changed` — change-scoped lane selection that prints its reasoning and never silently under-selects"
  - "Opt-in headless Electron E2E (`KEEPLING_TEST_HEADLESS=1`), with windowed-only specs tagged rather than weakened"
  - A macos-15 CI job that probes hosted-runner TCC and runs the no-Accessibility macOS rows against the downloaded artifact
affects: [any phase running desktop tests locally, any phase touching .github/workflows/desktop.yml]

actuals:
  tokens: 15238
  tasks: 4
  commits: 4

tech-stack:
  added: []
  patterns:
    - "One argument-forwarding entry point (`tooling/run-tests.mjs`) owns every desktop test lane's argv"
    - "Change-scoped lane selection is a union of matching rules, never first-match, and an unmatched path widens to everything"
    - "Machine-seizing lanes are SELECTED and printed but reported NOT RUN, never silently skipped"
    - "A test-only main-process seam is an explicit `KEEPLING_TEST_*` env var, inert by default (matches KEEPLING_TEST_SYNC_MODE / _USER_DATA_DIR / _EXPOSE_INTERNALS)"
    - "A spec that cannot be trusted headless is tagged `@windowed` and excluded, never weakened to pass"

key-files:
  created:
    - tooling/run-tests.mjs
    - tooling/select-tests.mjs
    - apps/desktop/main/windows/headless-presentation.ts
    - tooling/macos-integration/TccProbe.swift
    - docs/testing/desktop-testing.md
  modified:
    - package.json
    - apps/desktop/package.json
    - apps/desktop/playwright.config.ts
    - apps/desktop/main/index.ts
    - apps/desktop/test/fixtures/wired-app-harness.ts
    - apps/desktop/test/e2e/keyboard-quick-entry.spec.ts
    - .github/workflows/desktop.yml

key-decisions:
  - "pnpm is not the culprit for the swallowed filter — it appends script args verbatim, bare `--` included. vitest (cac) and Playwright's variadic `--project` are what lose them, so the fix belongs at the runner boundary."
  - "`pnpm test:changed` never runs the macOS integration lane or the Elixir server suite automatically; it selects them, prints them as NOT RUN with the exact command, and requires `--include-manual`."
  - "The headless seam is installed in BOTH entry points. The shipped main/index.ts alone would have left two harness-launched specs throwing windows on screen while the run claimed to be headless."
  - "keyboard-quick-entry.spec.ts is tagged @windowed in its entirety, not just its one failing test, because its passing assertions would pass VACUOUSLY headless."
  - "The macOS CI job is deliberately absent from desktop-promote's `needs`, so an experiment can never contribute to a promotion decision."
  - "The 03-17 executor did NOT re-record macOS row evidence for the new packaged digest: doing so types on the real keyboard and mutates real system settings on the operator's machine. Filed as O-27 with the exact command."

patterns-established:
  - "Fix argv at the runner boundary, not by teaching every caller a workaround"
  - "A selector that under-selects manufactures false confidence and is worse than a slow run"
  - "An unrun lane is reported as unrun, never counted as a pass"

requirements-completed: []

coverage:
  - id: D1
    description: "`pnpm test:desktop <filter>` and `pnpm test:desktop -- <filter>` both reach the runner; same for :ipc and :e2e"
    verification:
      - kind: integration
        ref: "pnpm test:desktop keyboardCommands && pnpm test:desktop -- keyboardCommands (both 1 file / 19 tests, measured before at 1/19 vs 18/164)"
        status: pass
      - kind: integration
        ref: "pnpm test:desktop:ipc -- hostile-bridge (1 file); pnpm test:desktop:e2e -- keyboard-menus --list (5 tests in 1 file)"
        status: pass
    human_judgment: false
  - id: D2
    description: "`pnpm test:changed` selects the minimum observing lane set and prints the selection with its reasoning"
    verification:
      - kind: integration
        ref: "node tooling/select-tests.mjs --dry-run --paths {apps/desktop/renderer/keyboardCommands.ts | apps/desktop/main/windows/quick-entry-window.ts | .github/workflows/desktop.yml | some/brand/new/area/thing.ts}"
        status: pass
      - kind: integration
        ref: "node tooling/select-tests.mjs --paths apps/desktop/test/renderer/keyboardCommands.test.ts (real execution: unit-renderer, 2 files / 23 tests)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Electron E2E runs without presenting windows under KEEPLING_TEST_HEADLESS=1, except tagged windowed-only specs"
    verification:
      - kind: e2e
        ref: "KEEPLING_TEST_HEADLESS=1 pnpm test:desktop:e2e — 52 passed (41.6s), 7 files"
        status: pass
      - kind: e2e
        ref: "pnpm test:desktop:e2e (default, windowed) — 57 passed (1.1m), 8 files, unchanged"
        status: pass
      - kind: integration
        ref: "BrowserWindow.getAllWindows() after the renderer settles: flag set -> isVisible() false, Dock hidden; flag unset -> isVisible() true, Dock shown"
        status: pass
    human_judgment: false
  - id: D4
    description: "CI runs the macOS integration lane on macos-15 against the downloaded artifact and probes hosted-runner TCC"
    verification:
      - kind: other
        ref: "actionlint .github/workflows/desktop.yml (clean); job downloads artifact, contains no package:desktop/build step"
        status: pass
      - kind: other
        ref: "swiftc -O -swift-version 5 tooling/macos-integration/TccProbe.swift; local positive control reports accessibility/screen-recording/universalaccess all true"
        status: pass
      - kind: e2e
        ref: "a real GitHub-hosted macos-15 run of the desktop-macos-integration job"
        status: unknown
    human_judgment: true
    rationale: "The hosted-runner TCC question CANNOT be answered from this machine. The job, the probe and the YAML are validated, but only a real CI run produces the answer. Recorded as unknown rather than assumed in either direction (O-25)."

duration: 40min
completed: 2026-09-03
status: complete
---

# Phase KPL-03 Plan 17: Cheaper Local Test Runs Summary

**Local test runs are now scopeable, change-aware and optionally windowless, while the phase gate and CI stay exactly as comprehensive as they were.**

## Performance

- **Duration:** ~40 min
- **Started:** 2026-09-03T20:20Z
- **Completed:** 2026-09-03T20:52Z
- **Tasks:** 4 of 4
- **Files modified:** 14 (5 created, 9 modified) — 932 insertions, 18 deletions

## Accomplishments

- **The silently-broken filter is fixed and the fix is measured, not asserted.** `pnpm test:desktop -- keyboardCommands` went from 18 files / 164 tests to 1 file / 19 tests, matching the unprefixed form exactly.
- **`pnpm test:changed` exists** and prints why every lane was chosen, widening to everything on an unmatched path rather than guessing.
- **The E2E suite can run without taking over the screen** — 52 tests in 41.6s with no windows — and the one spec that cannot be trusted headless is tagged and excluded rather than weakened.
- **The hosted-runner TCC question now has an experiment attached to it** instead of an assumption, with a probe whose positive control is verified locally.

## Task Commits

1. **Task 1: Make test filters actually reach the runner** — `429482e` (fix)
2. **Task 2: `pnpm test:changed` change-scoped lane selection** — `5178b37` (feat)
3. **Task 3: Opt-in headless Electron E2E** — `2e210fc` (feat)
4. **Task 4: macOS integration lane in CI + TCC experiment** — `1044326` (ci)

## Measured evidence

### Task 1 — before / after file counts

Baseline reproduced exactly as the plan recorded it:

```
$ pnpm test:desktop keyboardCommands
 Test Files  1 passed (1)
      Tests  19 passed (19)

$ pnpm test:desktop -- keyboardCommands
 Test Files  18 passed (18)
      Tests  164 passed (164)
```

After:

```
$ pnpm test:desktop keyboardCommands
 Test Files  1 passed (1)
      Tests  19 passed (19)

$ pnpm test:desktop -- keyboardCommands
 Test Files  1 passed (1)
      Tests  19 passed (19)
```

Root cause, established by probe rather than inspection. pnpm does **not** drop
the arguments — it appends them to the script command verbatim, bare `--`
included (`npm_lifecycle_script` ends with `-- foo`). The runners lose them:

```
$ pnpm exec vitest run --config vitest.config.ts --project application -- keyboardCommands
      Tests  104 passed (104)          # filter ignored: cac treats post-`--` as passthrough

$ pnpm exec playwright test --config playwright.config.ts --project electron keyboard-menus --list
Error: Project(s) "keyboard-menus" not found.  # `--project` is VARIADIC

$ pnpm exec playwright test --config playwright.config.ts --project=electron keyboard-menus --list
Total: 5 tests in 1 file                       # equals-form keeps the positional a positional
```

Other lanes, after the fix:

```
$ pnpm test:desktop:ipc -- hostile-bridge      ->  1 file  / 66 tests
$ pnpm test:desktop:ipc hostile-bridge         ->  1 file  / 66 tests
$ pnpm test:desktop:e2e -- keyboard-menus --list  ->  5 tests in 1 file
$ pnpm test:desktop:e2e keyboard-menus --list     ->  5 tests in 1 file
```

Unfiltered lanes unchanged (the comprehensive suite stays comprehensive):
164 unit / 66 ipc / 57 e2e in 8 files.

### Task 3 — per-spec headless capability table

Measured one spec at a time with `KEEPLING_TEST_HEADLESS=1`, *after* installing
the seam in the harness entry point as well as the shipped one.

| Spec | Launches | Headless-capable | Result / disqualifying failure |
|---|---|---|---|
| `accessibility.spec.ts` | `dist/main/index.cjs` | yes | 11 passed (9.9s) |
| `daily-loop.spec.ts` | `dist/main/index.cjs` | yes | 2 passed (4.4s) |
| `gap-closure.spec.ts` | `dist/main/index.cjs` | yes | 6 passed (12.8s) |
| `keyboard-menus.spec.ts` | `dist-harness/harness.cjs` | yes | 5 passed (4.6s) |
| `keyboard-quick-entry.spec.ts` | `dist-harness/harness.cjs` | **no — `@windowed`** | **1 failed, 4 passed (8.5s).** `✘ :169:1 Command-Return commits, and typing during IME composition does not commit` — it asserts `isQuickEntryOpen() === true`, which resolves through `QuickEntryWindowController.isOpen()` to `BrowserWindow.isVisible()`, exactly what headless suppresses. The 4 that "passed" include `isOpen() === false` assertions at `:122` and `:148` that would pass **vacuously**, unable to distinguish "hidden after commit" from "never presented". The whole file is therefore tagged, not just the failing test. |
| `lifecycle.spec.ts` | `dist/main/index.cjs` | yes | 12 passed (11.5s) |
| `real-stack-sync.spec.ts` | — (never launches Electron) | n/a | 7 passed (441ms) |
| `sync-recovery.spec.ts` | — (never launches Electron) | n/a | 9 passed (806ms) |

Full runs:

```
$ KEEPLING_TEST_HEADLESS=1 pnpm test:desktop:e2e
  52 passed (41.6s)        # 52 tests in 7 files

$ pnpm test:desktop:e2e                # default, unchanged
  57 passed (1.1m)         # 57 tests in 8 files
```

Proof the seam is real rather than a no-op — `BrowserWindow.getAllWindows()`
inspected after the renderer settles:

```
KEEPLING_TEST_HEADLESS=1  -> {"windows":[{"title":"Keepling — Inbox","visible":false}],"dockVisible":false}
KEEPLING_TEST_HEADLESS=   -> {"windows":[{"title":"Keepling — Inbox","visible":true}],"dockVisible":true}
```

### Task 2 — selector output for four genuinely different paths

```
$ node tooling/select-tests.mjs --dry-run --paths apps/desktop/renderer/keyboardCommands.ts
  apps/desktop/renderer/keyboardCommands.ts
      via apps/desktop/renderer/** -> unit-renderer, unit-application, e2e, typecheck-desktop, packaged

$ node tooling/select-tests.mjs --dry-run --paths apps/desktop/main/windows/quick-entry-window.ts
      via apps/desktop/main/windows/** -> unit-application, e2e, typecheck-desktop, packaged, macos-integration
      via apps/desktop/main/**         -> unit-application, ipc, e2e, typecheck-desktop, packaged
  [NOT RUN] macos-integration -- posts real OS keystrokes and mutates real system settings

$ node tooling/select-tests.mjs --dry-run --paths .github/workflows/desktop.yml
      via .github/** -> (none)   because CI definition: only a real CI run can observe it
  no lane can observe these changes

$ node tooling/select-tests.mjs --dry-run --paths some/brand/new/area/thing.ts
      via (no rule) -> contracts, e2e, ipc, macos-integration, packaged, server, typecheck-desktop,
                       typecheck-web, unit-all, unit-application, unit-performance, unit-renderer,
                       unit-store, web-unit
      because UNMATCHED path -- widening to every lane rather than guessing
```

Real (non-dry) execution:

```
$ node tooling/select-tests.mjs --paths apps/desktop/test/renderer/keyboardCommands.test.ts
  [run] unit-renderer -- vitest renderer project
--- unit-renderer: node tooling/run-tests.mjs unit --project=renderer ---
 Test Files  2 passed (2)
      Tests  23 passed (23)
=== result ===
  ran: unit-renderer
  full authority: node tooling/verify-desktop-phase.mjs
```

### Task 4 — CI job and TCC probe

```
$ actionlint .github/workflows/desktop.yml
ACTIONLINT CLEAN

needs: ['desktop-package']     runs-on: macos-15     continue-on-error: True
steps: checkout, setup-node, install, download-artifact, TCC probe, rebase manifest,
       verify-macos-integration --without-accessibility-trust, upload TCC report
REBUILDS? False        DOWNLOADS? True
desktop-promote needs: ['desktop-units','desktop-package','desktop-packaged','desktop-e2e']   # job absent, by design
```

Probe positive control, run locally where all three permissions are granted:

```json
{ "accessibility_trusted" : true,
  "screen_recording_preflight" : true,
  "universal_access_write" : { "persisted" : true, "read_back_matched_token" : true },
  "process_ancestry" : [ {"name":"TccProbe"}, {"name":"zsh"}, ..., {"name":"Terminal"} ] }
```

The probe can report `true`, so a `false` from a runner will be a real answer
rather than a probe artefact. Cleanup verified: `defaults read
com.apple.universalaccess keeplingTccProbe` → *does not exist*.

**The hosted-runner TCC question is UNSETTLED.** I cannot trigger CI, and no
real run of this job has happened. This plan makes **no claim** about whether a
GitHub-hosted `macos-15` runner can be granted Accessibility, Screen Recording
or a protected settings write. The job, the probe and the YAML are validated;
the answer awaits a real run. Filed as **O-25**.

## Files Created/Modified

- `tooling/run-tests.mjs` — one argv-forwarding entry point for the `unit`, `ipc` and `e2e` lanes; strips bare `--`, uses `--project=<name>`, and lets an explicit `--project=` replace the lane's default project set
- `tooling/select-tests.mjs` — change→lane mapping, reasoning output, manual-lane reporting, `--dry-run` / `--paths` / `--include-manual`
- `apps/desktop/main/windows/headless-presentation.ts` — the `KEEPLING_TEST_HEADLESS=1` seam
- `tooling/macos-integration/TccProbe.swift` — non-prompting hosted-runner TCC report
- `docs/testing/desktop-testing.md` — the lane table, scoping, `test:changed`, headless capability table, and the CI experiment
- `package.json` — adds `test:changed`
- `apps/desktop/package.json` — `test`/`test:e2e`/`test:ipc` route through `run-tests.mjs`
- `apps/desktop/playwright.config.ts` — `grepInvert: /@windowed/` when headless, `undefined` otherwise
- `apps/desktop/main/index.ts` — installs the headless seam before any window is constructed
- `apps/desktop/test/fixtures/wired-app-harness.ts` — installs the same seam
- `apps/desktop/test/e2e/keyboard-quick-entry.spec.ts` — 5 tests tagged `@windowed` with the reason documented in the file header
- `.github/workflows/desktop.yml` — `desktop-macos-integration` job
- `.planning/HANDOFF.json` — corrected the now-false filter guidance; added O-25, O-26, O-27
- `.planning/phases/KPL-03-mac-daily-loop/.continue-here.md` — same correction

## Decisions Made

See `key-decisions` in the frontmatter. The two most consequential:

1. **The `--` guidance in `.continue-here.md` and `HANDOFF.json` was corrected, but committed plan `<verify>` commands were left untouched.** Those commands become *correct* once the filter works; rewriting historical plan text would have violated the standing "do not edit committed plan verify commands" rule for no benefit. What did need correcting was the *instruction* telling readers the form does not work, plus an explicit note that pre-03-17 counts reported against a `-- <name>` command are full-suite counts.
2. **The whole `keyboard-quick-entry.spec.ts` file is tagged, not just its failing test.** Tagging only the failure would have left two assertions passing vacuously under headless — precisely the "headless-and-weakened" outcome the plan prohibits.

## Deviations from Plan

### 1. [Rule 3 — Blocking] The headless seam had to be installed in a second entry point

- **Found during:** Task 3
- **Issue:** The first headless run reported 57/57 passing, which was too good. Investigation showed `keyboard-menus.spec.ts` and `keyboard-quick-entry.spec.ts` launch `dist-harness/harness.cjs`, not `dist/main/index.cjs` — so the seam installed in `main/index.ts` never ran for them, and their windows were still being presented while the run claimed to be headless.
- **Fix:** Installed `installHeadlessPresentation` in `test/fixtures/wired-app-harness.ts` too. This immediately surfaced the genuine `keyboard-quick-entry` failure that the plan predicted.
- **Files modified:** `apps/desktop/test/fixtures/wired-app-harness.ts`
- **Verification:** Per-spec measurement above; `keyboard-quick-entry` now fails headless as it should, and is tagged.
- **Committed in:** `2e210fc`

### 2. [Rule 2 — Missing critical functionality] `run-tests.mjs` gained project-override semantics

- **Found during:** Task 2
- **Issue:** The selector needs to narrow the unit lane to a single vitest project, but an extra `--project` would have unioned with the lane's five defaults and narrowed nothing.
- **Fix:** An explicit `--project=<name>` now *replaces* the lane defaults.
- **Verification:** `node tooling/run-tests.mjs unit --project=renderer` → 23 tests (vs 164 unfiltered).
- **Committed in:** `5178b37`

### 3. [Scope] `apps/desktop/main/windows/main-window.ts` was not modified

The plan's `files_modified` listed it, but it contains no `show()` call — window presentation happens in `lifecycle.ts`, `quick-entry-window.ts`, `settings-window.ts` and `foreground-app.ts`. A central prototype-level install covers all of them, including any future window, so no call site needed editing. Deviating *downward* in blast radius.

---

**Total deviations:** 3 (1 × Rule 3, 1 × Rule 2, 1 × scope reduction). No scope creep; nothing weakened.

## Issues Encountered

### The desktop phase gate is currently RED, for a reason that is not a regression

`node tooling/verify-desktop-phase.mjs` at this HEAD reports:

```
Desktop phase gate summary: lanes=9 failed=1
  PASS typecheck-desktop cases=1                 PASS typecheck-web cases=1
  PASS unit-pure-vector-store-worker-performance cases=164
  PASS ipc-hostile-bridge cases=66               PASS electron-e2e cases=57
  PASS package-once cases=1                      PASS packaged cases=10
  FAIL macos-integration cases=0                 PASS privacy cases=1
```

```
macOS integration lane failed: no macOS integration evidence exists for application
digest 5f8ad9faa50749a5fa0afeb3d34341cfca50694cc61c428f71b94f2d853aeace
```

Task 3 edits `apps/desktop/main/index.ts`, which ships inside the packaged app,
so the packaged digest moved from `ffcb4a92459956e2…` (15 rows / 92 cases,
recorded 2026-09-03T20:13:34Z) to `5f8ad9faa5074…`. Row evidence is bound to the
digest, so the gate correctly refuses to reuse it. **Every other lane passes with
unchanged counts**, and no lane was reduced, skipped or made conditional.

I deliberately did **not** re-record it. The command types on the real keyboard
and mutates real system settings on the operator's machine, and a partial
`--rows` recording would not restore the gate anyway (the gate requires evidence
for every row). One command fixes it, at a moment of the operator's choosing:

```sh
pnpm package:desktop && node tooling/verify-macos-integration.mjs --all
```

Filed as **O-27** in `.planning/HANDOFF.json`, and in `.planning/WINDOWS.md`.

### Incidental finding: a vitest project with no tests

`apps/desktop/vitest.config.ts` declares a `worker` project including
`test/worker/**` with `passWithNoTests: false`, but that directory does not
exist. A full run hides this (vitest's check is satisfied by the other
projects); `node tooling/run-tests.mjs unit --project=worker` alone fails with
"No test files found". The real worker *is* covered today, but from
`test/e2e/sync-recovery.spec.ts`, not from the lane whose name advertises it.
Filed as **O-26**; not fixed here (out of this plan's scope, and fixing it means
either writing tests or deleting an advertised lane — a decision, not a typo).

## Open items filed

| id | Item |
|---|---|
| O-25 | `desktop-macos-integration` is `continue-on-error` for its first run only. After a real run: make it required or delete it. The TCC question is unsettled until then. |
| O-26 | The vitest `worker` project has zero test files and the empty lane is invisible in a full run. |
| O-27 | macOS row evidence must be re-recorded for the post-03-17 packaged digest; exact command included. |

## User Setup Required

None. One optional operator action exists (O-27's re-record command), which is
automation the operator schedules, not manual verification.

## Next Phase Readiness

Ready, with one caveat: **the phase gate will report `lanes=9 failed=1` until
O-27's one command is run.** Do not read that as a weakened gate — it is the
gate refusing stale evidence for changed bytes, which is exactly the behaviour
03-15/03-16 built.

The TCC experiment is armed but unanswered. Nothing downstream should assume an
answer in either direction until the `desktop-macos-integration` job has
actually run.

---
*Phase: KPL-03-mac-daily-loop*
*Completed: 2026-09-03*

## Self-Check: PASSED

All 6 created files exist on disk; all 4 task commits (`429482e`, `5178b37`,
`2e210fc`, `1044326`) resolve in `git log`; O-25/O-26/O-27 are present in
`.planning/HANDOFF.json` `open_items`.
