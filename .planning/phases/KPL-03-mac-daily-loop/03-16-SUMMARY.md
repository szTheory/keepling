---
phase: KPL-03-mac-daily-loop
plan: 16
subsystem: desktop-shell
tags: [macos, electron, focus, quick-entry, accessibility, gap-closure, nsapplication]
status: complete

requires:
  - phase: KPL-03-mac-daily-loop
    provides: "03-10's hardened production bootstrap() in apps/desktop/main/index.ts"
  - phase: KPL-03-mac-daily-loop
    provides: "03-14's QuickEntryWindowController with its declared (but unimplemented) ForegroundAppPort"
  - phase: KPL-03-mac-daily-loop
    provides: "03-15's macOS integration lane, in particular row A9 which measures focus and caret return through the real AX tree"
provides:
  - "ElectronForegroundApp: the production ForegroundAppPort, returning activation to the prior application with no TCC Automation prompt and no native module"
  - "Bootstrap wiring making prior-application focus return reachable in the shipped app for the first time"
  - "A required (no longer optional) foregroundApp option, so this defect class cannot recur silently"
  - "The A7 fix: the dead-key composing letter is gated on the dead key having landed rather than on a fixed 120ms wait"
  - "The A4 fix, and a shared settledFocus() helper: focus is read once it has settled, not once after a sleep"
  - "A fifteen-row green macOS lane recorded as gate evidence, and a fully green desktop phase gate"
affects: [MAC-02, phase verification, GAP-1 closure, dogfood UX]

actuals:
  tokens: 41000
  tasks: 2
  commits: 5

tech-stack:
  added: []
  patterns:
    - "Self-hide as focus return: NSApplication hands activation back to the previously active application when an app hides itself, so the prior app's caret survives because it is reactivated rather than reopened"
    - "Opaque port handles: the handle carries one boolean and never names the other application, so no identity-revealing permission is ever needed"
    - "Settle predicates strictly weaker than the assertion they precede, so waiting can never make a row vacuous"

key-files:
  created:
    - apps/desktop/main/windows/foreground-app.ts
    - apps/desktop/test/application/foreground-app.test.ts
  modified:
    - apps/desktop/main/index.ts
    - apps/desktop/main/windows/quick-entry-window.ts
    - tooling/verify-macos-integration.mjs
    - .planning/HANDOFF.json
    - .planning/phases/KPL-03-mac-daily-loop/.continue-here.md

key-decisions:
  - "Focus return is implemented as app.hide(), which needs no TCC Automation prompt and no native module, at the cost of also hiding Keepling's main window (recorded as O-23)"
  - "Invoked from Keepling's own window, restore shows and focuses the main window and never hides the app; proven by unit test because row A9 structurally cannot measure it"
  - "foregroundApp was made REQUIRED rather than left optional, because an optional port with only a test implementation is exactly how O-21 stayed invisible for five plans"
  - "The un-hide is awaited to SETTLE before Quick Entry is shown, after measuring that NSApplication.unhide: re-keys the main window on a later run-loop turn"
  - "A4 and A7 were fixed at their underlying race rather than by widening sleeps, and both fixes were rate-measured before and after"

patterns-established:
  - "When the lane reports a product defect, first confirm the lane's own mechanism did what it claims; when the lane flaps, measure the timeline through the AX tree before choosing a fix"
  - "Quiescence is not universally a valid settle condition: a pending dead key is stable indefinitely, so 'the value stopped changing' would have settled on the failure"
---

# Phase KPL-03 Plan 16: Quick Entry Prior-Application Focus Return Summary

Quick Entry now returns the user to the exact application and caret offset they came from, via a production `ForegroundAppPort` wired into the real bootstrap — closing the fifth and last open GAP-1 instance and turning the fifteen-row macOS lane and the whole desktop phase gate green.

## What Was Built

`apps/desktop/main/windows/foreground-app.ts` exports `ElectronForegroundApp`, the first and only production implementation of the `ForegroundAppPort` that `QuickEntryWindowController` has declared since 03-04. `bootstrap()` in `apps/desktop/main/index.ts` constructs it and passes it as the `foregroundApp` option.

The mechanism deliberately never learns which application the user came from:

- `captureActiveApp()` records one boolean — was **Keepling** frontmost when Quick Entry opened — read from `BrowserWindow.getFocusedWindow()`. The handle stays opaque; it is tagged so a handle this adapter did not mint restores nothing rather than hiding the application on a guess.
- `restoreActiveApp(handle)` branches. Keepling was **not** frontmost → `app.hide()`; macOS returns activation to the previously active application, and because that application is *reactivated* rather than reopened, its caret, selection and scroll position survive untouched. Keepling **was** frontmost → do not hide; show and focus the main window instead, so invoking Quick Entry from Keepling itself never makes the app vanish.

This needs no TCC Automation prompt and no native module, which is what the plan's prohibitions required.

## Task-by-Task

**Task 1 — adapter and bootstrap wiring** (`e2bc5ea`)

Verification, as the plan specified:

```
$ pnpm --filter @keepling/desktop typecheck
> tsc --project tsconfig.json --noEmit --pretty false
(clean)

$ pnpm test:desktop:e2e
  57 passed (50.4s)

$ rg -n "foregroundApp" apps/desktop/main
apps/desktop/main/index.ts:697:  const foregroundApp = new ElectronForegroundApp({
apps/desktop/main/index.ts:704:    foregroundApp,
```

The recording double in `test/fixtures/wired-app-harness.ts` was left in place and the harness was not repointed at the production adapter, per the plan: it proves capture/restore *sequencing* deterministically, which real window-server focus cannot.

**Task 2 — prove A9, then the full lane** (`06ac82d`, `14a2f4b`, `1ff88a8`, `b810736`)

Final `--all` run, against the packaged `.app`:

```
LANE_INPUT swiftc="Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)" ax_probe_digest=9765f77ae1d35e29 settings_probe_digest=550be5960aadeef6
LANE_ARTIFACT application_digest=ffcb4a92459956e21708b415f4b4b8b0babde91452ee308a5e633e766d346c59 executable=/var/folders/f3/f0clj9rd2zb85n2c849wcsrc0000gn/T/keepling-desktop-package-rbxN26/Keepling.app/Contents/MacOS/Keepling source_revision=b810736bdc716792df60ca67e3c7cab605fe5843
ROW id=A1 status=PASS cases=10 duration_ms=6894
ROW id=A2 status=PASS cases=11 duration_ms=11005
ROW id=A3 status=PASS cases=5 duration_ms=15543
ROW id=A4 status=PASS cases=6 duration_ms=11668
SETTINGS captured=6 file=/Users/jon/projects/keepling/.artifacts/macos-integration/settings-capture.json
ROW id=A5 status=PASS cases=12 duration_ms=47831
ROW id=A6 status=PASS cases=6 duration_ms=27102
ROW id=A7 status=PASS cases=3 duration_ms=7077
ROW id=A8 status=PASS cases=8 duration_ms=17071
ROW id=A9 status=PASS cases=6 duration_ms=16779
ROW id=A10 status=PASS cases=3 duration_ms=2264
ROW id=A11 status=PASS cases=5 duration_ms=8791
ROW id=A12 status=PASS cases=3 duration_ms=2311
ROW id=A13 status=PASS cases=3 duration_ms=2280
ROW id=A14 status=PASS cases=4 duration_ms=4786
ROW id=A15 status=PASS cases=7 duration_ms=7508
LANE_EVIDENCE recorded=true file=/Users/jon/projects/keepling/.artifacts/macos-integration/evidence/ffcb4a92459956e21708b415f4b4b8b0babde91452ee308a5e633e766d346c59.json rows=15 cases=92
SETTINGS restore=VERIFIED every mutated setting matches its captured value
macOS integration lane summary: rows=15 failed=0 cases=92 duration_ms=190824
  PASS A1 VoiceOver layer: capture cases=10
  PASS A2 VoiceOver layer: list navigation and selection cases=11
  PASS A3 VoiceOver layer: dialogs announce themselves cases=5
  PASS A4 VoiceOver layer: the unsaved-changes dialog cases=6
  PASS A5 Full Keyboard Access: the complete scoped sequence, keyboard only cases=12
  PASS A6 Full Keyboard Access: focus is never trapped or lost cases=6
  PASS A7 Non-US layout with dead keys cases=3
  PASS A8 Real global-shortcut collision and OS arbitration cases=8
  PASS A9 Prior-application focus and caret return cases=6
  PASS A10 Increase Contrast cases=3
  PASS A11 Differentiate Without Color cases=5
  PASS A12 Reduce Transparency cases=3
  PASS A13 Reduce Motion cases=3
  PASS A14 Light/Dark change while the app is open cases=4
  PASS A15 200% zoom equivalent: no primary control is clipped cases=7
macOS integration lane: PASSED cases=92
```

Row A9's six cases are the two endings (`submitted` via Return, `discarded` via Escape) × three assertions each: the prior application really has a caret at a known non-zero offset beforehand; focus returns to the same prior application; and the caret comes back to exactly the same location and length. No assertion was weakened and no timeout widened.

The phase gate that consumes this evidence:

```
Desktop phase gate summary: lanes=9 failed=0
  PASS typecheck-desktop cases=1 duration_ms=1202
  PASS typecheck-web cases=1 duration_ms=2140
  PASS unit-pure-vector-store-worker-performance cases=164 duration_ms=1275
  PASS ipc-hostile-bridge cases=66 duration_ms=678
  PASS electron-e2e cases=57 duration_ms=52626
  PASS package-once cases=1 duration_ms=12853
  PASS packaged cases=10 duration_ms=8373
  PASS macos-integration cases=92 duration_ms=264
  PASS privacy cases=1 duration_ms=19
Desktop phase gate: PASSED
```

`macos-integration` completed in 264ms because it reused the digest-bound evidence and executed no row — the once-per-artifact property is intact.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] The second Quick Entry invocation typed into the wrong window** (`06ac82d`)

- **Found during:** Task 2, first `--rows A9` run. A9 got further than before (4 cases, up from a first-case failure) and then timed out waiting for Quick Entry to close.
- **Investigation:** Rather than assume, I instrumented the row to print frontmost, window z-order and the AX focused element at each step. The measurement:

  ```
  DEBUG submitted afterOpen  frontmost=Keepling windows=["Keepling","Keepling — Inbox"]
                             focused=AXTextField "What do you want to keep?"
  DEBUG submitted afterKey   frontmost=TextEdit  windows=["Keepling — Inbox"]
  DEBUG discarded afterOpen  frontmost=Keepling windows=["Keepling — Inbox","Keepling"]
                             focused=AXWebArea  "Keepling — Inbox"
  DEBUG discarded afterKey   frontmost=Keepling windows=["Keepling — Inbox","Keepling"]
  ```

  The first capture worked perfectly. On the second, the **main** window was in front and held AX focus, so `tabUntil` matched the *main window's* capture field, the text and the Escape went there, and Quick Entry never closed.
- **Cause:** `NSApplication.unhide:` finishes on a later run-loop turn. Capture un-hid the application and returned; `open()` then showed and focused Quick Entry; the un-hide *then* re-ordered and re-keyed the main window on top of it.
- **Fix:** `captureActiveApp()` is now async and polls to a bounded 2s deadline for the un-hide to **settle** (Keepling owning a focused window again) before returning, so the caller shows Quick Entry last. A machine that never settles proceeds at the deadline rather than hanging the global shortcut.

**2. [Rule 2 — Missing critical functionality] `foregroundApp` was still optional** (`14a2f4b`)

The plan prohibited making the option "optional-in-practice by allowing bootstrap to omit it". Wiring bootstrap satisfies that today, but nothing prevented the regression — and an optional port whose only implementation lived in test code is precisely how O-21 survived five plans. Both construction sites (shipped bootstrap and E2E harness) now supply it, so the option is required and a caller that forgets it does not compile. The `?.` call sites and the `| undefined` field type went with it.

**3. [Rule 1 — Bug, lane] Row A7 flapped ~1 in 8 against unchanged product code** (`1ff88a8`)

- **Symptom:** `A7: a dead-key sequence composes the accented character in the field ... field value was "Caf'"` — the pending dead key, with the `e` that should compose with it missing.
- **First attempt was wrong, and measurement caught it.** I first added a quiescence settle ("wait for the value to stop changing"). It still failed 1 in 13. Measuring the real timeline showed why:

  ```
  DEBUG a7 beforeDeadKey="Caf"
  DEBUG a7 afterDeadKey+100ms="Caf'" ... afterDeadKey+1000ms="Caf'"
  DEBUG a7 afterE+100ms="Café"
  ```

  A pending dead key is stable **indefinitely**, so quiescence settles on the failure. Quiescence is not universally a valid settle condition.
- **Fix:** the keystrokes are posted separately, each gated on a polled settle — prefix landed, dead key pending, composition resolved — replacing the fixed `wait:120` inside a single burst. The assertion is untouched and still fails on `"Caf'e"` or `"Cafe"`.
- **Rate:** ~1 failure in 8 before; 13 consecutive passes after.

**4. [Rule 1 — Bug, lane] Row A4 flapped 3 times in 6 runs against unchanged product code** (`b810736`)

- **Symptom:** three different failures, all reporting `focus was on nothing`, at both of A4's focus reads. I first suspected the shared `captureTaskByKeyboard` helper and instrumented it; it was innocent (`field="Edit me" want="Edit me"` on every run).
- **Cause:** mounting and dismissing the unsaved-changes dialog moves focus in more than one step and leaves the application with **no** focused element in between. A4 slept a fixed 800ms/600ms and then read focus once — the identical defect class `fbdf2b4` fixed for A6.
- **Fix:** a shared `settledFocus(handle)` helper polls until focus is non-null and unchanged across consecutive reads; A4 also waits for the dialog to mount instead of sleeping. Settling is deliberately **weaker** than anything the row asserts — it waits for focus to stop *moving*, never for focus to be on a particular element — so focus settling on the wrong node, on `AXApplication`, or on a removed zero-sized node still fails the row. At the deadline it returns whatever it last saw, including `null`, so a real "focus is lost" product defect is still reported rather than waited away.
- **Rate:** 3 failures in 6 before; 12 passes in 12 after.

Deviations 3 and 4 are lane fixes, not product fixes, and the plan explicitly authorised them ("If any row other than A9 flakes, fix the underlying race ... never by widening a fixed sleep").

## Authentication Gates

None. All three TCC permissions (Accessibility, Screen Recording, Full Disk Access) were already granted to the inherited Terminal process, so all fifteen rows ran. No new permission is required by the shipped app — that was a hard prohibition and the chosen mechanism honours it.

## Known Stubs

None. `ElectronForegroundApp` has no placeholder branch, no TODO, and no hardcoded empty value; both of its branches are exercised (the hide branch by row A9 against a real prior application, the Keepling-frontmost branch by unit test).

## Requirements

**MAC-02** is now satisfiable at the macOS layer: the global shortcut opens Quick Entry over another application, the capture commits, and the user is returned to that application with their caret intact — measured, not inferred. I have **not** marked it complete here, because the phase convention (O-17) is that requirements are checked against phase verification rather than by an executing plan, and MAC-03/04/05 and QUAL-03/04 need their own evidence check.

## New Open Items — written to HANDOFF.json

Both are in `.planning/HANDOFF.json` `open_items`, not only described here (O-22).

- **O-23 — focus return hides Keepling's main window too.** macOS only hands activation back when an application hides *itself*, so restoring focus necessarily hides the main window: capture from TextEdit with a Keepling window visible and afterwards that window is gone (hidden, not closed) rather than merely behind TextEdit. Every alternative examined needs something we refuse to ship — activating another application by bundle identifier needs its identity, which needs an AppleScript/Automation TCC prompt or a native `NSRunningApplication` module. The next capture un-hides the app, so nothing is stranded. Decide at dogfood; do **not** "fix" it by dropping `app.hide()`, which silently reintroduces O-21.
- **O-24 — the lane still contains sleep-then-read-once patterns.** Three rows have now been caught flapping against unchanged product code (A6 in `fbdf2b4`; A4 and A7 here). A1, A2, A3, A5, A8 and `captureTaskByKeyboard` still share the shape and should be assumed to harbour it.

**O-21 is marked CLOSED** in `HANDOFF.json` with the measured evidence, the mechanism, and the resolution of the UX decision it flagged.

## Self-Check: PASSED

Created files exist:

```
FOUND: apps/desktop/main/windows/foreground-app.ts
FOUND: apps/desktop/test/application/foreground-app.test.ts
FOUND: .planning/phases/KPL-03-mac-daily-loop/03-16-SUMMARY.md
```

Commits exist:

```
FOUND: e2bc5ea  feat(KPL-03-16): give Quick Entry a real prior-application focus-return adapter
FOUND: 06ac82d  fix(KPL-03-16): wait for the un-hide to settle before Quick Entry is shown
FOUND: 14a2f4b  refactor(KPL-03-16): make the Quick Entry foreground port required, not optional
FOUND: 1ff88a8  fix(KPL-03-16): gate A7's composing letter on the dead key having landed
FOUND: b810736  fix(KPL-03-16): make A4 read focus once it has SETTLED, not once after a sleep
```
