---
phase: KPL-03-mac-daily-loop
plan: 27
subsystem: testing
tags: [playwright, electron, appearance, accessibility, ui-spec, evidence-contract]

# Dependency graph
requires:
  - phase: KPL-03-mac-daily-loop (03-25, 03-26)
    provides: reproducible desktop packaging (03-25), a machine-state-barriered macOS integration lane with seeded order-independence (03-26)
provides:
  - apps/desktop/test/e2e/appearance-matrix.spec.ts -- ten @windowed Playwright cases proving the five window sizes 03-UI-SPEC.md names, in both themes, against a real resized BrowserWindow
  - An amended 03-UI-SPEC.md whose "Verification Evidence Required" visual-snapshot bullet names an executable artifact or macOS row for every dimension it lists, or is marked NOT BUILT with evidence
  - A dated correction beneath 03-UI-SPEC.md's Checker Sign-Off recording that the visual dimension was approved without a lane ever existing
  - A corrected Overflow row in the UI Considerations table naming its real evidence carriers instead of a visual matrix that never existed
affects: [phase-6-ci, any-future-phase-touching-apps/desktop/renderer]

# Actuals (#2632)
actuals:
  tokens: 5705
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Literal-string test titles for grep-checkable evidence tables: appearance-matrix.spec.ts writes each of its ten titles out as a literal string (not built via template interpolation) specifically so grep against the source file finds each one verbatim -- both this plan's own acceptance criteria and 03-UI-SPEC.md's evidence table cite tests this way."
    - "Resize-then-read-back-before-any-layout-claim: every case calls setContentSize, then getContentSize, then asserts the two match BEFORE asserting anything about layout, so a window that silently failed to resize can never be mistaken for a passing case (proven load-bearing by deliberately breaking it during Task 1)."
    - "Amend-beside-the-record, never rewrite: 03-UI-SPEC.md's evidence table and sign-off correction are added beneath the original text, which stays verbatim and unflagged as wrong -- the amendment carries the correction, the original stays as historical record."

key-files:
  created:
    - apps/desktop/test/e2e/appearance-matrix.spec.ts
  modified:
    - .planning/phases/KPL-03-mac-daily-loop/03-UI-SPEC.md

key-decisions:
  - "Amend the UI-SPEC and build only the one genuinely uncovered dimension (five window sizes), rather than build a desktop visual-snapshot (golden-image) lane. Reasoning recorded in the plan's own gap_2_decision and carried into the UI-SPEC amendment: no CI has ever run in this repository (no git remote), so a golden image could only ever compare against itself on one machine; macOS rows A10/A12/A13/A14 already measure a real WCAG contrast ratio over real rendered pixels for the properties a screenshot would otherwise stand in for; the emulatable properties are already covered behaviorally by accessibility.spec.ts; and AGENTS.md ranks usability above pixel-identical UI."
  - "The 'list and detail regions never collapse' assertion applies only at content widths >=1024px (compact-wide/persistent), where Workspace.tsx actually renders both regions simultaneously. Below 1024px (the 680x520 case) the shipped shell shows exactly one routed surface at a time by design (D-04), so that size asserts non-zero width on the one region it actually shows rather than a vacuous check against a sibling that is never in the DOM. Recorded here as an interpretation of the plan's own behavior text rather than guessed silently, per this plan's planner_assumptions."
  - "Window sizes are read as Electron content size (setContentSize/getContentSize), not outer window size including titlebar chrome -- consistent with how 03-UI-SPEC.md's own Main Window Contract states minimum bounds."
  - "The reachability predicate reused from accessibility.spec.ts's 200% reflow case is visibility-by-role/label of the primary controls, not a literal Tab-key traversal loop -- this is the codebase's own established pattern for 'every primary control remains reachable,' replicated verbatim per the plan's explicit instruction rather than inventing a stronger or weaker check."

requirements-completed: [QUAL-04]

coverage:
  - id: D1
    description: "The five window sizes 03-UI-SPEC.md names (680x520, 1024x700, 1064x700, 1180x780, 1440x900) are proven in both light and dark against a real resized Electron window: no horizontal overflow, primary controls reachable, list/detail regions never collapsed"
    requirement: QUAL-04
    verification:
      - kind: e2e
        ref: "apps/desktop/test/e2e/appearance-matrix.spec.ts -- all 10 'appearance matrix: ...' titles"
        status: pass
    human_judgment: false
  - id: D2
    description: "Every dimension in 03-UI-SPEC.md's Verification Evidence Required visual-snapshot bullet names an executable artifact (test title or macOS row id), or is explicitly marked NOT BUILT with its evidence"
    requirement: QUAL-04
    verification:
      - kind: other
        ref: "grep -F verification of every cited test title against its named file (accessibility.spec.ts, appearance-matrix.spec.ts); tooling/verify-macos-integration.mjs row ids A10/A12/A13/A14 confirmed present in source"
        status: pass
    human_judgment: false
  - id: D3
    description: "The Checker Sign-Off's erroneous approval of the visual dimension is corrected in a dated record that still shows the original entries unchanged"
    requirement: QUAL-04
    verification:
      - kind: other
        ref: "git diff -- .planning/phases/KPL-03-mac-daily-loop/03-UI-SPEC.md shows the seven original sign-off lines as unmodified context; a new '### Dated correction' section added beneath them"
        status: pass
    human_judgment: true
    rationale: "Whether the correction's wording is adequately honest (does not soften or overclaim) is a judgment call about prose, not something a grep can fully certify -- the acceptance criteria's mechanical checks (original text present, phrase removed, correction block exists) all pass, but a human should read the actual amendment text."
  - id: D4
    description: "The full desktop phase gate reports failed=0 with no lane at cases=0, including a freshly re-recorded macos-integration lane, across two consecutive runs"
    requirement: QUAL-04
    verification:
      - kind: other
        ref: "node tooling/verify-desktop-phase.mjs (x2 consecutive): lanes=11 failed=0 both times; electron-e2e cases=76 both times (10 higher than the 66 recorded in 03-VERIFICATION.md); macos-integration cases=93 both times, reusing evidence in ~300ms"
        status: pass
    human_judgment: false

duration: 70min
completed: 2026-09-04
status: complete
---

# Phase KPL-03 Plan 27: Appearance Matrix and UI-SPEC Evidence Correction Summary

**Built ten behavioral Playwright cases proving 03-UI-SPEC.md's five named window sizes in both themes against a real resized Electron window, then amended the UI-SPEC's evidence contract to name an executable artifact for every dimension it claims (or mark it NOT BUILT), correcting a sign-off that approved a visual-snapshot lane which never existed.**

## Performance

- **Duration:** ~70 min active execution (includes an out-of-scope but required macOS-integration evidence re-recording of ~3 minutes, triggered by this plan's own source changes invalidating the prior packaged-artifact digest)
- **Started:** 2026-09-04T19:00:00Z
- **Completed:** 2026-09-04T20:10:00Z
- **Tasks:** 3
- **Files modified:** 2 (1 created, 1 modified)

## Accomplishments

- `apps/desktop/test/e2e/appearance-matrix.spec.ts`: ten `@windowed` Playwright cases (five sizes × two themes) each resizing the real `BrowserWindow`, reading `getContentSize()` back and asserting it landed BEFORE any layout claim (proven load-bearing by deliberately breaking it and confirming the test fails), then asserting no window-level horizontal overflow, the nav/capture-form/list controls are reachable (reusing `accessibility.spec.ts`'s own 200% reflow reachability predicate verbatim), and — at the content widths where the shipped shell actually renders list and detail simultaneously (>=1024px) — that neither region collapses to zero width.
- Closed the one evidence dimension VERIFICATION.md Gap 2 identified as genuinely uncovered: no code anywhere in the repository resized the desktop window and asserted the result before this plan. `node tooling/verify-desktop-phase.mjs` now reports `electron-e2e cases=76`, ten higher than the 66 recorded in 03-VERIFICATION.md.
- Amended `03-UI-SPEC.md` in four additive, dated places (nothing deleted): (1) a dated amendment beneath the original visual-snapshot requirement explaining the evidence-form change and its five reasons; (2) a per-dimension `Dimension | Evidence | Artifact` table naming a verbatim test title or macOS row id (A10/A12/A13/A14) for every dimension, with the responsive drawer/224-360-480 composition recorded `NOT BUILT` citing `desktop.css`'s zero media queries and a `git grep -i drawer` miss; (3) the Overflow row's backstop statement rewritten to name `appearance-matrix.spec.ts` and `accessibility.spec.ts` as its real evidence carriers, instead of "the specified visual matrix" that never existed; (4) a dated correction beneath the Checker Sign-Off recording that the visual dimension was approved without a lane ever existing, with the original seven sign-off lines left unchanged.
- Discovered during Task 3's own verification that this plan's file changes invalidated the packaged application's digest, making the macOS-integration lane's recorded evidence stale for the new digest (unrelated to visual/appearance-matrix content — any source change under `apps/desktop` does this by the lane's own digest-binding design). Re-ran `pnpm package:desktop && node tooling/verify-macos-integration.mjs --all` (after one retry past a `FOCUS_STOLEN by_bundle=com.apple.Terminal` interference event on this shared machine, matching the class 03-26-SUMMARY already documented) to produce fresh evidence: `rows=15 failed=0 cases=93`. Confirmed the full gate reuses it cleanly across two consecutive runs.
- No `toHaveScreenshot`, `toMatchSnapshot`, or baseline directory was introduced anywhere in `apps/desktop` — confirmed by `grep -rn "toHaveScreenshot\|toMatchSnapshot" apps/desktop`, which returns exactly one hit: this file's own header comment stating that it deliberately does not add one.

## Task Commits

1. **Task 1: One window size, one theme, proven end to end** - `9f0fb37` (test)
2. **Task 2: Expand to all five sizes in both themes** - `5ca756e` (test)
3. **Task 3: Amend the UI-SPEC evidence contract and correct the sign-off** - `30ce952` (docs)

**Plan metadata:** committed alongside this SUMMARY.

## Files Created/Modified

- `apps/desktop/test/e2e/appearance-matrix.spec.ts` - Ten `@windowed` behavioral cases proving 03-UI-SPEC.md's five named window sizes in both themes.
- `.planning/phases/KPL-03-mac-daily-loop/03-UI-SPEC.md` - Dated amendment + per-dimension evidence table on the visual-snapshot requirement; corrected Overflow backstop attribution; dated correction beneath Checker Sign-Off.

## Decisions Made

See `key-decisions` in the frontmatter above.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] macOS-integration evidence went stale for the new application digest, blocking Task 3's own `<verify>` gate**

- **Found during:** Task 3, running the required `node tooling/verify-desktop-phase.mjs` verification.
- **Issue:** This plan's source changes under `apps/desktop` changed the packaged application's `applicationDigestSha256` on the next `pnpm package:desktop`. `tooling/verify-macos-integration.mjs` binds its recorded evidence to an exact digest by design (03-25/03-26's anti-vacuity work), so the gate reported `macos-integration cases=0` with `no macOS integration evidence exists for application digest ...` — a real gate failure blocking this plan's own literal `<verify>` command, though the underlying cause (any `apps/desktop` change invalidates the digest) is not specific to appearance-matrix content and is not a defect this plan's files introduced.
- **Fix:** Ran `pnpm package:desktop && node tooling/verify-macos-integration.mjs --all` per the failure's own suggested remedy. First two attempts hit `FOCUS_STOLEN by_bundle=com.apple.Terminal` (a real, confirmed third-party focus-theft event on this shared, multi-tenant machine — matching the exact interference class 03-26-SUMMARY already measured and documented, not a lane defect). Third attempt completed cleanly: `rows=15 failed=0 cases=93`.
- **Files modified:** None (evidence is recorded to `.artifacts/macos-integration/`, which is gitignored per 03-08's disclosure; no source file was touched to fix this).
- **Verification:** `node tooling/verify-desktop-phase.mjs` run twice consecutively after the re-recording: `lanes=11 failed=0` both times, `macos-integration cases=93` both times, reusing the evidence in ~300ms rather than re-running.
- **Committed in:** No commit needed — this produces only gitignored evidence artifacts, not source changes.

---

**Total deviations:** 1 auto-fixed (Rule 3 blocking issue, resolved by re-running existing tooling — no code changed)
**Impact on plan:** Necessary to satisfy this plan's own literal `<verify>` command (`node tooling/verify-desktop-phase.mjs` with `failed=0` and no lane at `cases=0`). No scope creep: no file outside this plan's declared `files_modified` was changed; the fix is a tooling re-run whose evidence output is gitignored.

## Environment Notes (not deviations from this plan's code)

Two of three `verify-macos-integration.mjs --all` attempts hit `FOCUS_STOLEN by_bundle=com.apple.Terminal by_pid=64196` — confirmed via `ps -p 64196` to be a real, long-running Terminal.app process on this shared, multi-tenant machine (multiple concurrent `tty` sessions were logged in throughout, matching 03-26-SUMMARY's own "shared, actively multi-tenant desktop" disclosure for this same environment). Per the standing rule established in that plan: neither attempt was treated as a lane pass, no timeout or wait budget was raised in response, and no evidence was recorded from either failed attempt — only the clean third run's evidence was recorded and is what the gate now reuses.

## Issues Encountered

None beyond the Rule 3 deviation and the environmental interference both documented above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- VERIFICATION.md Gap 2 is closed: the five window sizes have real behavioral evidence, and 03-UI-SPEC.md's evidence contract now names an executable artifact or macOS row for every dimension it lists, with the one genuinely unbuilt feature (responsive drawer composition) disclosed rather than hidden.
- Both VERIFICATION.md gaps (Gap 1 via 03-25/03-26, Gap 2 via this plan) are now closed. `node tooling/verify-desktop-phase.mjs` is green (`lanes=11 failed=0`) on two consecutive runs with a freshly recorded macOS-integration evidence set.
- The responsive drawer navigation (1024-1063px) and 224/360/480px persistent composition (1064px+) remain genuinely unbuilt (`desktop.css` has zero media queries; `git grep -i drawer` finds nothing). This is now disclosed in 03-UI-SPEC.md as `NOT BUILT` rather than silently claimed proven or deleted from the spec — a deliberate decision for a later phase, not a defect in this one.
- This plan did not mark any requirement checkbox in `.planning/REQUIREMENTS.md` and touched no `.planning/` file other than `03-UI-SPEC.md` and this SUMMARY, per its own prohibitions.

---
*Phase: KPL-03-mac-daily-loop*
*Completed: 2026-09-04*

## Self-Check: PASSED

- `apps/desktop/test/e2e/appearance-matrix.spec.ts` exists on disk: FOUND
- `.planning/phases/KPL-03-mac-daily-loop/03-27-SUMMARY.md` exists on disk: FOUND
- Commit `9f0fb37` (Task 1) found in git log: FOUND
- Commit `5ca756e` (Task 2) found in git log: FOUND
- Commit `30ce952` (Task 3) found in git log: FOUND
- Re-ran plan-level `<verification>`: `KEEPLING_TEST_HEADLESS=0 pnpm test:desktop:e2e -- -g "appearance matrix"` reports 10 passed, 0 failed; `grep -rn "toHaveScreenshot\|toMatchSnapshot" apps/desktop` returns only this file's own explanatory comment, no functional usage; every test title cited in the UI-SPEC evidence table verified present verbatim in its named file; `grep -F "1064px proves the first 224/360/480px persistent composition" .planning/phases/KPL-03-mac-daily-loop/03-UI-SPEC.md` still matches; `node tooling/verify-desktop-phase.mjs` reports `lanes=11 failed=0` on two consecutive runs with no lane at `cases=0`.
