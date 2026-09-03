---
phase: KPL-03-mac-daily-loop
plan: 15
subsystem: testing
tags: [macos, accessibility, axuielement, cgevent, swift, screencapturekit, electron, playwright, tcc]

requires:
  - phase: KPL-03-mac-daily-loop
    provides: "03-06's anti-vacuous phase gate (tooling/verify-desktop-phase.mjs), the packaged artifact pipeline (package-once -> digest-bound manifest), and the D-42 DOM-level accessibility suite"
  - phase: KPL-03-mac-daily-loop
    provides: "03-13/03-14's wired shipped entry point, real sync pass, and fenced sign-out"
provides:
  - "A macOS-layer integration lane executing rows A1-A15 against the exact packaged .app: the real AXUIElement tree, real CGEvent keystrokes, real input sources, real system settings, and WCAG contrast measured from rendered pixels"
  - "Three Swift probes (AXProbe, SystemSettings, HotkeyRival) compiled on demand and cached by source digest"
  - "Digest-bound evidence caching so the lane runs once per packaged artifact rather than on every gate invocation"
  - "The A4 fix: the workspace unsaved-changes alertdialog moves focus into itself and restores focus on close"
  - "The O-19 fix: runSyncPass() publishes an inspectable syncing presentation that clears on every exit path"
  - "A dogfood contract with no checklist, no evidence record, and no blocking sign-off"
affects: [phase verification, CI, future macOS runner work, GAP-1 closure]

actuals:
  tokens: 48367
  tasks: 4
  commits: 5

tech-stack:
  added: [swiftc, ApplicationServices/AXUIElement, CoreGraphics/CGEvent, Carbon/TISInputSource, Carbon/RegisterEventHotKey, ScreenCaptureKit]
  patterns:
    - "Row runner with per-row named assertions and positive case counts, mirroring the existing lane registry contract"
    - "Capture-before-mutation with restore registered on every exit path including signals, verified by re-read"
    - "Digest-bound evidence reuse (D-47 idiom) with strict, visible, fail-loud rules"
    - "Capability tagging per row (requiresAccessibilityTrust / requiresScreenRecording / requiresProtectedSettingsWrite)"

key-files:
  created:
    - tooling/macos-integration/AXProbe.swift
    - tooling/macos-integration/SystemSettings.swift
    - tooling/macos-integration/HotkeyRival.swift
    - tooling/verify-macos-integration.mjs
    - apps/desktop/test/application/sync-presentation.test.ts
  modified:
    - packages/web-ui/src/workspace/Workspace.tsx
    - apps/desktop/main/application/DesktopApplication.ts
    - apps/desktop/test/e2e/accessibility.spec.ts
    - tooling/verify-desktop-phase.mjs
    - docs/testing/desktop-dogfood.md
    - .planning/phases/KPL-03-mac-daily-loop/03-06-PLAN.md

key-decisions:
  - "Rows A1-A15 are automated at the macOS layer rather than performed by a human; the dogfood contract keeps only informal feedback"
  - "The lane runs once per packaged artifact and the gate reuses digest-bound evidence; it never runs on an ordinary gate invocation"
  - "Missing capability (Accessibility, Screen Recording, Full Disk Access, swiftc, packaged artifact, evidence) is always a loud failure, never a skip or soft pass"
  - "Rows assert what was MEASURED about macOS, not what was predicted: A8 was rewritten after measurement showed global hot keys are not exclusive"
  - "A9's failure is disclosed as a real product defect rather than weakened into a passing assertion"
  - "MAC-02 and QUAL-04 were NOT marked complete (see Requirements below)"

patterns-established:
  - "Anti-vacuous macOS evidence: a row that asserts nothing, is unimplemented, or could not exercise macOS fails the gate"
  - "System-settings safety: closed managed vocabulary, capture to disk before first mutation, restore on exit/exception/SIGINT/SIGTERM/SIGHUP, verified by re-read, with a self-test for both hard paths"
  - "Cross-process verification of privileged writes, because macOS silently no-ops protected preference writes"

requirements-completed: []

coverage:
  - id: D1
    description: "The workspace unsaved-changes alertdialog moves focus into itself onto the safe default action and returns focus to a visible operable element on close (A4 fix)"
    verification:
      - kind: e2e
        ref: "apps/desktop/test/e2e/accessibility.spec.ts#dialog focus: the workspace unsaved-changes alertdialog moves focus into itself"
        status: pass
      - kind: integration
        ref: "node tooling/verify-macos-integration.mjs --rows A4 (6 cases, real AX tree)"
        status: pass
    human_judgment: false
  - id: D2
    description: "runSyncPass() publishes an inspectable syncing presentation that clears on every exit path and makes no durability claim (O-19)"
    verification:
      - kind: unit
        ref: "apps/desktop/test/application/sync-presentation.test.ts (4 cases)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Screen-reader-layer rows A1-A4 executed against the packaged app via the real AXUIElement tree"
    verification:
      - kind: integration
        ref: "node tooling/verify-macos-integration.mjs --rows A1,A2,A3,A4 (rows=4 failed=0 cases=32)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Keyboard rows A5-A7 executed by real CGEvent keystrokes with Full Keyboard Access and a real dead-key input source"
    verification:
      - kind: integration
        ref: "node tooling/verify-macos-integration.mjs --rows A5,A6,A7 (rows=3 failed=0 cases=21)"
        status: pass
    human_judgment: false
  - id: D5
    description: "System settings mutated by the lane are restored on a mid-row exception and on a real external interruption, verified by re-read"
    verification:
      - kind: integration
        ref: "node tooling/verify-macos-integration.mjs --self-test-restore (rows=3 failed=0 cases=17)"
        status: pass
    human_judgment: false
  - id: D6
    description: "Digest-bound evidence is reused only when complete, wholly passing, and bound to this artifact and these probe sources"
    verification:
      - kind: unit
        ref: "node tooling/verify-macos-integration.mjs --self-test-restore -> SELF-TEST-EVIDENCE (9 cases, pure function, positive and negative)"
        status: pass
    human_judgment: false
  - id: D7
    description: "A8: real OS arbitration of a colliding global accelerator, measured with a real rival application"
    verification:
      - kind: integration
        ref: "node tooling/verify-macos-integration.mjs --rows A8 (8 cases)"
        status: pass
    human_judgment: false
  - id: D8
    description: "A15: no primary control is clipped at the reduced logical size a ~200% scaled display produces"
    verification:
      - kind: integration
        ref: "node tooling/verify-macos-integration.mjs --rows A15 (7 cases, AX frames)"
        status: pass
    human_judgment: false
  - id: D9
    description: "A9: prior-application focus and caret return after Quick Entry"
    verification:
      - kind: integration
        ref: "node tooling/verify-macos-integration.mjs --rows A9"
        status: fail
    human_judgment: false
  - id: D10
    description: "A10-A14: legibility under real accessibility/appearance settings, measured as WCAG contrast over rendered pixels"
    verification:
      - kind: integration
        ref: "node tooling/verify-macos-integration.mjs --rows A10,A11,A12,A13,A14"
        status: unknown
    human_judgment: false
  - id: D11
    description: "The dogfood contract requires no human checklist, no evidence record, and no blocking sign-off"
    verification:
      - kind: other
        ref: "docs/testing/desktop-dogfood.md rewritten; 03-06 Task 3 converted to a non-blocking superseded note; verify-desktop-phase.mjs prints NOT_A_GATE instead of DEFERRED for dogfood"
        status: pass
    human_judgment: false

duration: 2h 35m
completed: 2026-09-03
status: complete
---

# Phase KPL-03 Plan 15: Automated macOS-Layer Accessibility Evidence Summary

**A Swift AX/CGEvent/ScreenCaptureKit probe suite and a digest-bound lane that execute the fifteen-row physical accessibility checklist against the packaged `.app` at the macOS layer, plus the two defects that checklist was documenting instead of solving — and one new real defect the lane found on its first run.**

## Performance

- **Duration:** 2h 35m
- **Tasks:** 4
- **Commits:** 5
- **Files created:** 5
- **Files modified:** 6

## Accomplishments

- **The checklist is gone, and its claims are now executed by machine.** Rows A1-A15 are driven against the exact packaged artifact through the real `AXUIElement` tree (the same data VoiceOver speaks), real `CGEvent` keystrokes, real input sources, real system settings, and WCAG contrast computed from real rendered pixels. `docs/testing/desktop-dogfood.md` now asks a person for one thing: informal feedback, with no format, no counts and no sign-off.
- **A4 is fixed, not described.** The workspace unsaved-changes alertdialog moves focus onto "Keep Editing" when it opens and restores focus to a visible operable element when it closes. `accessibility.spec.ts` asserts the fixed behaviour instead of asserting the defect persists, and A4 proves it again at the macOS layer.
- **O-19 is closed.** `runSyncPass()` publishes the `updating` row for the duration of a pass and clears it on every exit path, so MAC-04's fifth state is inspectable in the shipped app. It makes no durability claim and never clobbers a conflict surfaced mid-pass.
- **The lane costs the machine nothing on an ordinary run.** Rows execute once per packaged artifact; the gate reuses evidence bound to that exact `applicationDigestSha256` and the Swift probe source digests, executing no row and changing no setting.
- **It found a real bug immediately.** A9 discovered that prior-application focus return is unimplemented in the shipped app.

## Task Commits

1. **Task 1 (RED): failing tests for dialog focus and the syncing presentation** — `a5e67a7` (test)
2. **Task 1 (GREEN): A4 focus fix and the O-19 syncing presentation** — `a29335b` (fix)
3. **Task 2: AXProbe.swift, the row runner, rows A1-A4, lane registration** — `650ba89` (feat)
4. **Task 3: SystemSettings.swift, rows A5-A7 and A10-A15, guaranteed restore** — `ddf5166` (feat)
5. **Task 4: HotkeyRival.swift, rows A8-A9, evidence caching, dogfood rewrite** — `c949541` (feat)

## Verification Evidence (all re-run, real output)

| Command | Result |
|---|---|
| `pnpm test:desktop` | 17 files / **156 tests** passed (baseline 152, +4 new) |
| `pnpm test:desktop:e2e` | **57 passed** (unchanged; the A4 case is inverted, not added) |
| `pnpm test:desktop:ipc` | **66** (via gate lane) |
| `pnpm typecheck:desktop` / `typecheck:web` | clean |
| `pnpm --dir apps/web test --run` | 15 files / **153 tests** passed |
| `--rows A1,A2,A3,A4` | rows=4 failed=0 **cases=32** |
| `--rows A5,A6,A7,A15` | rows=4 failed=0 **cases=28** |
| `--rows A8` | PASS **cases=8** |
| `--rows A9` | **FAIL cases=2** — real defect, see below |
| `--rows A10..A14` | **loud failure**: Screen Recording and Full Disk Access not granted |
| `--self-test-restore` | rows=3 failed=0 **cases=17**, `SETTINGS restore=VERIFIED` |
| `node tooling/verify-desktop-phase.mjs` | **lanes=9 failed=1** — 8 pass, `macos-integration` fails |

**Final gate lane counts:** typecheck-desktop 1, typecheck-web 1, unit 156, ipc 66, electron-e2e 57, package-once 1, packaged 10, privacy 1, **macos-integration FAIL (0)**. All 15 A-row ownership entries and all 18 D-48 ownership rows PASS.

## Findings (the important part)

### 1. A9 — prior-application focus return is unimplemented in the shipped app (new GAP-1 instance)

`QuickEntryWindowController` accepts an optional `foregroundApp` port and calls `captureActiveApp()` on open and `restoreActiveApp()` on hide. **No implementation of that port exists anywhere, and none is passed in `main/index.ts#bootstrap()`** (verified by grep: the only references are the port's own declaration and use). The optional port silently no-ops, so nothing throws and nothing restores focus.

Measured behaviour: with TextEdit focused and a caret at a known offset, invoking Quick Entry and submitting leaves **Keepling** frontmost. The caret assertion is never reached.

This is the same structural defect as O-1/O-11/O-12/O-15 — a designed capability that no plan was authorized to wire — with one difference: here the adapter was never written at all, so closing it is new implementation work (a `ForegroundAppPort` adapter plus wiring), and it carries a real UX decision (when Keepling should hide itself if Quick Entry was invoked from Keepling's own window). It is therefore disclosed rather than half-fixed. **Recommend O-21.**

### 2. A8 — macOS global hot keys are not exclusive (measured, contradicting the plan's premise)

The plan expected a rival to either win or lose the accelerator. Measurement says neither: **both registrations succeed, in either order, and the keystroke is delivered to both processes.** A colliding application therefore does not silently steal Keepling's accelerator, and Keepling reporting the accelerator as available is a true statement. The row was rewritten to assert what was measured, including that Keepling's reported state matches what the OS actually did.

An earlier draft of this row asserted "exactly one process received it" and reported a `LIMITATION` about Keepling believing it held a shortcut it did not. **That was wrong** — an artifact of detecting the Quick Entry window only by title while the Settings window was frontmost. It was corrected after improving detection to two independent signals. Recording it because a plausible-looking false finding is exactly what an anti-vacuous gate must not ship.

### 3. Chromium publishes only a structure-level AX tree unless an assistive client is present

Setting `AXManualAccessibility` from the probe is racy: sometimes the tree came up complete (live regions, control values, `aria-current`), sometimes structurally correct but attribute-poor. A lane reading the poor tree would silently assert less than it claims. Fixed deterministically by launching with `--force-renderer-accessibility` (a runtime switch, not a byte change; the state a real screen reader produces) **and** asserting the tree reached complete mode before any row runs.

### 4. `com.apple.universalaccess` accepts writes that silently do nothing

An unentitled process may write that domain and receive **no error** while nothing is stored — precisely the vacuous-pass hazard this lane exists to prevent. Every settings write is now verified by a re-read **in a separate process** (an in-process read-back is satisfied by the preferences cache), and a silently-rejected write fails the lane naming Full Disk Access.

### 5. `Cmd-1`/`Cmd-2` bypass the unsaved-changes guard

`apps/desktop/renderer/DesktopShell.tsx` routes the `go-inbox`/`go-today` semantic commands straight through `facade.setRoute`, so keyboard navigation skips `Workspace`'s dirty check that mouse navigation goes through. Rows A4 and A6 navigate via the destination control instead. Not fixed here: `DesktopShell.tsx` is outside this plan's `files_modified`, and routing it through the guard needs the dirty state to cross a component boundary — a design change, not a local fix. **Recommend O-22.** Severity is bounded: an editor draft makes no durability claim (D-03).

## Capability requirements (observed)

Each is a loud failure with the exact System Settings path when absent — never a skip.

| Capability | Rows | Status on this machine |
|---|---|---|
| Accessibility (TCC) | A1-A9, A11, A15 | **granted** — the AX rows all ran |
| Screen Recording | A10-A14 | **not granted** — those rows fail loudly, preflighted before anything launches |
| Full Disk Access | A10-A13 | **not granted** — protected-domain writes rejected, detected by re-read |
| `swiftc` | all | present (Apple Swift 6.3.3) |

TCC attributes the grant to the *responsible* process, so it must be given to the terminal/IDE/CI agent, not to the compiled probe. The probe reports its process ancestry in the failure message to make that actionable.

### Accessibility-trust split (corrected from the predicted boundary)

Each row carries `requiresAccessibilityTrust`, and `--without-accessibility-trust` runs exactly the untrusted subset. The predicted split was A1-A9 trusted / A10-A15 untrusted. **Observed: A11 and A15 also require it.** A11's "conveyed by text, not colour" claim is a claim about the accessibility tree, and A15 asserts control geometry read from AX frames; rewriting either to avoid AX would assert something weaker than the row says, so they are tagged honestly instead. The untrusted subset is **A10, A12, A13, A14** — no accessibility API, no keystrokes, just the real OS setting and measured pixels.

One correction to the framing: no row is free of *all* TCC grants. A10-A14 need Screen Recording (there are no pixels to measure without it) and A10-A13 additionally need Full Disk Access. Those are tracked as separate flags (`requiresScreenRecording`, `requiresProtectedSettingsWrite`) because they are separate grants.

## System-settings safety

The lane changes real settings on whatever machine runs it. Guarantees, all proven rather than asserted:

- A **closed managed vocabulary** — there is no free-form "write any default" command, because a restore can only be trusted if the set of things that can change is bounded.
- The current values are **captured to disk before the first mutation**, so even a `kill -9` leaves a record.
- Restore is registered on normal exit, exception, `SIGINT`, `SIGTERM` and `SIGHUP` **before anything changes**, and is **verified by re-reading**.
- `--self-test-restore` proves both hard paths: a mid-row exception, and a real external `SIGTERM` to a real child process that has *no tidy return path* (it mutates, announces, and then waits forever — only the signal handler can put the machine back).
- `--restore` manually restores from the last capture.
- Every settings-touching run in this session ended with `SETTINGS restore=VERIFIED`.

## Digest-bound evidence caching (scope change during execution)

The plan as written registered the lane to run on every `verify-desktop-phase.mjs` invocation. That is not acceptable on a personal workstation — the lane flips the display to dark mode, toggles accessibility settings, resizes the window and drives the keyboard. Resolved with the phase's own D-47 idiom:

- A complete, wholly passing `--all` run records its result against the exact `applicationDigestSha256`, with the Swift probe source digests, row ids, case counts, durations and a timestamp, at `.artifacts/macos-integration/evidence/<digest>.json`.
- `verify-desktop-phase.mjs` invokes `--gate`, which **executes no row and changes no setting**. It reuses the record only when the artifact digest AND all three probe source digests match, the record covers every row, and no recorded row failed — and it always prints the digest and the original run timestamp, so reuse is never invisible.
- Missing, stale, partial or failing evidence is a **loud failure** naming the exact command to produce it. A record covering only the untrusted subset can never satisfy the gate as if it covered all fifteen.
- The standalone runner is opt-in: with no mode flag it prints usage and exits.

The reuse rules are a pure function with a dedicated self-test (`SELF-TEST-EVIDENCE`, 9 cases) covering the positive case and six rejection cases, runnable with no Mac, no permissions and no rows — because a cache that quietly never reuses, or quietly always reuses, is worse than none.

**Evidence location:** `.artifacts/macos-integration/evidence/`. `.artifacts/` is deliberately gitignored (O-14 added it precisely so generated evidence cannot be committed), so this is a stable, inspectable working-tree path rather than a scratch temp dir — not a git-tracked file. If git-tracked evidence is wanted later, that is a deliberate change to the O-14 decision.

## Why the gate is currently red

`macos-integration` fails because **no complete passing run exists for the current artifact**, and one cannot exist until (a) A9's defect is fixed and (b) Screen Recording and Full Disk Access are granted once. This is the gate working: the lane refuses to record or reuse partial evidence, and refuses to let a row that did not exercise macOS report green. The other eight lanes pass, and every count matches or beats the prior baseline (unit 152 → 156).

## Requirements

**Neither `MAC-02` nor `QUAL-04` was marked complete.** Known tooling defect O-17 means `requirements.mark-complete` marks every id in a plan's frontmatter, and this corrupted `REQUIREMENTS.md` once already, so each was checked against real evidence:

- **MAC-02** ("complete keyboard navigation and quick entry"): the blocking reason recorded in `REQUIREMENTS.md` was "pending physical keyboard/IME/accessibility evidence", and that evidence now exists and is automated — A5 (12 cases, the complete scoped sequence by CGEvent keys alone), A6 (6), A7 (3, real dead-key composition), A3 and A8 (Quick Entry through the real global accelerator). **Left unchecked** because the lane that produces this evidence cannot currently go green (A9 fails, A10-A14 ungranted), and marking a requirement complete against a red lane is the kind of claim this phase exists to avoid. It should be marked as soon as the lane is green.
- **QUAL-04** ("representative user-level coverage for populated/empty/loading/offline/denied/stale/conflict/partial/retry/unrecoverable states"): its recorded blocker (physical/accessibility evidence) is removed, and O-19 makes MAC-04's fifth state reachable, but this plan did not verify per-screen state coverage end to end. **Left unchecked** — unverified.

MAC-01/03/04/05 and QUAL-03 are not this plan's to mark.

## Deviations from Plan

### Auto-fixed / adjusted

**1. [Rule 3 - Blocking] Chromium accessibility tree came up incomplete**
- **Found during:** Task 2. Rows intermittently could not see live regions, control values or `aria-current`.
- **Fix:** launch with `--force-renderer-accessibility` and assert the tree reached complete mode before any row runs.
- **Committed in:** `650ba89`

**2. [Rule 1 - Bug] Protected-domain writes silently no-op**
- **Found during:** Task 3. `apply` reported success from its own in-process read-back while nothing reached disk.
- **Fix:** verify every apply by re-reading in a separate process; a rejected write fails the lane naming Full Disk Access.
- **Committed in:** `ddf5166`

**3. [Rule 1 - Bug] The row runner swallowed non-assertion errors**
- **Found during:** Task 3. A `ReferenceError` inside a row surfaced as a bare "cases=0" with no message.
- **Fix:** print the wrapped error and stack before rethrowing.
- **Committed in:** `ddf5166`

**4. [Rule 1 - Bug] The A9 harness stole the focus it was measuring**
- **Found during:** Task 4. `postKeys` unconditionally raised the app, making the harness the prior application.
- **Fix:** `postKeys`/`tabUntil` take `raise: false`; A9 never forces Keepling frontmost after Quick Entry opens.
- **Committed in:** `c949541`

### Plan assumptions corrected by measurement

**5. A8's premise** — the plan assumed exclusive arbitration. Both processes receive the accelerator. Row rewritten to assert the measured behaviour.

**6. A15's mechanism** — the plan asked for a real ~200% display zoom. Changing the display mode on someone's machine risks leaving a bad resolution, and macOS Zoom is a magnifier that does not reflow. The row instead reduces the real window through the accessibility API to the logical size a scaled display produces and asserts every primary control is unclipped **inside the window's real AX frame** — an AX-level geometry assertion, distinct from `accessibility.spec.ts`'s DOM `scrollWidth` proof. The window stops at the app's own minimum size, so the row asserts it genuinely shrank rather than hitting an arbitrary number.

**7. A11's `extra` hook** — implemented as a full row rather than a variant, because it needs the accessibility tree while A10/A12/A13/A14 deliberately do not.

### Scope change accepted mid-execution

**8. Evidence caching** (see above) — the plan's registration would have run the lane on every gate invocation. Replaced with digest-bound reuse.

**9. Row capability tagging** — added `requiresAccessibilityTrust` and the `--without-accessibility-trust` selector, with the observed boundary rather than the predicted one.

---

**Total deviations:** 4 auto-fixed bugs/blockers, 3 measurement-driven plan corrections, 2 accepted scope changes.
**Impact:** every change made the evidence stricter or the machine safer. No assertion was weakened to make a row pass.

## Issues Encountered

- The plan's Task 4 acceptance criterion says "no blocking human checkpoint... remains anywhere in Phase 3". `03-01-PLAN.md` still contains two checkpoints (`checkpoint:human-verify gate="blocking-human"` for `electron@44.1.1`/`zod@4.5.4` package legitimacy, and a `checkpoint:decision`). **Deliberately left alone**: 03-01 is a completed plan with a SUMMARY, those checkpoints were resolved, and package-legitimacy gates are the one category the executor rules require to stay human. They are not accessibility UAT and they gate nothing now.

## Known Stubs

None. No stub, placeholder, or hardcoded-empty value was introduced.

## Threat Flags

None. The lane's threat register (T-KPL03-15-01..04) is addressed: settings restore is verified and self-tested (01); the broad Accessibility capability is disclosed rather than assumed, and the probes are compiled from tracked, digest-checked source (02); rows run against the manifest's exact artifact digest and never rebuild, and a skipped or zero-case row fails the gate (03); the rival is a local, tracked, short-lived process that unregisters on exit and self-terminates after 300 seconds (04).

## Next Phase Readiness

**Blocking the `macos-integration` lane going green:**

1. **O-21** — implement and wire a `ForegroundAppPort` so Quick Entry returns focus to the prior application (A9). Needs ownership of `main/index.ts` plus a decision about behaviour when Quick Entry is invoked from Keepling's own window.
2. Grant **Screen Recording** and **Full Disk Access** once, then run `pnpm package:desktop && node tooling/verify-macos-integration.mjs --all` to record evidence for the artifact.

**Recommended follow-ups:**

3. **O-22** — route `Cmd-1`/`Cmd-2` through the unsaved-changes guard.
4. **Dedicated macOS runner.** This lane belongs on a dedicated or self-hosted macOS runner so it never touches a personal machine at all. The untrusted subset (`--without-accessibility-trust`: A10, A12, A13, A14) is the natural first step, since it needs no Accessibility grant — though it does still need Screen Recording, and A10/A12/A13 need Full Disk Access, so even that subset needs verification on a hosted runner before it can be claimed. **Whether TCC can be granted on hosted runners at all is not asserted here** — it needs a real CI run as evidence. Explicitly out of scope for this plan; no CI wiring was added.
5. Mark **MAC-02** once the lane is green; assess **QUAL-04** separately against per-screen state coverage.

---
*Phase: KPL-03-mac-daily-loop*
*Completed: 2026-09-03*

## Self-Check: PASSED

All five created files exist on disk and all five task commits are present in `git log`.
