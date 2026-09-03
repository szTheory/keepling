# Desktop Physical-Accessibility and Dogfood Evidence Contract (D-42/D-45/D-46)

This document is the evidence contract for the ONE category of Phase 3 (KPL-03) proof that
cannot be automated: a human, at a physical Mac, using the real keyboard/screen
reader/system-settings surface, and the human accumulation of real daily use over real elapsed
time. Everything that CAN be automated already is — see `tooling/verify-desktop-phase.mjs`
(the automated phase gate) and `apps/desktop/test/e2e/accessibility.spec.ts` (the automated
accessibility/appearance proof this document does not duplicate). Read those first: this
document only covers what genuinely requires a human.

**No item in this document may be marked complete by an agent, a script, or self-attestation.**
A human runs every row below, on a real Mac, against the exact artifact named in the evidence
record, and writes down what actually happened.

## Preconditions — do not start until ALL of these are true

1. `tooling/verify-desktop-phase.mjs` reports `Desktop phase gate: PASSED` for the exact
   commit/digest under test.
2. `tooling/measure-desktop-performance.mjs --check-budgets` passes against the same digest
   (see `docs/testing/desktop-performance.md`).
3. The "Initial physical accessibility pass" section below is complete and every row passed
   (or has a recorded, non-blocking limitation — see "Defect severity" below).

Only once all three are true does the seven-day interval (below) begin. If the packaged
artifact changes for ANY reason (a new commit is packaged, a dependency changes, a config
changes) during the interval, the interval RESTARTS at day 1 against the new digest. A partial
week against a stale artifact is not evidence about the artifact actually shipping.

## Evidence record

Copy this block into a dated file (e.g. `desktop-dogfood-evidence-2026-09-03.md`, kept locally —
this contract does not mandate committing raw dogfood logs to the repository) and fill in every
field. **Never write task titles, note bodies, prompt text, credentials, raw tokens, or any
other private/arbitrary identifier into this record** — only counts, dispositions, and closed
category names (matching the same "closed vocabulary, no free-text content" discipline
`tooling/measure-desktop-performance.mjs`'s privacy scan enforces).

```
Artifact digest (applicationDigestSha256): <from package-manifest.json>
Source revision:                            <sourceRevision>
Hardware:                                   <Mac model, chip>
macOS version:                              <e.g. 15.x>
Interval start date:                        <YYYY-MM-DD>
Interval end date (start + 6 days):         <YYYY-MM-DD>
Active-use days (>=5 required):             <count, list dates>
Scoped Things fallbacks (must be 0):        <count; if >0, describe each>
Accepted-mutation loss / silent overwrite
  incidents (must be 0):                    <count; if >0, describe each>
Unresolved release-blocking defects
  (must be 0):                              <count; if >0, describe each>
```

## Initial physical accessibility pass (before the interval starts)

Run every row against the exact packaged `.app` named by the artifact digest above — never a
`pnpm dev` window, never Xcode/Simulator, never a screen-recording substitute.

| # | Check | How | Pass condition |
|---|---|---|---|
| A1 | VoiceOver: capture | Cmd-F5 to start VoiceOver. Tab to the capture field, type a task, submit. | VoiceOver announces the field's label ("What do you want to keep?"), the Add Task button's name and state, and the post-submit "Saved on this Mac" status without requiring a second interaction to discover it. |
| A2 | VoiceOver: list navigation | With VoiceOver on, navigate the task list with VO-Right-Arrow / standard list navigation. | Each row's accessible name includes the task title and its sync status; the currently SELECTED task (if any) is distinguishable from the currently VoiceOver-focused row (D-05 — see `accessibility.spec.ts`'s automated proxy for the underlying `aria-current` mechanism; this row is the real screen-reader confirmation of it). |
| A3 | VoiceOver: dialogs | Trigger the Quick Entry discard-draft confirmation and the inline sync conflict (see `test/e2e/daily-loop.spec.ts`'s conflict fixture for how to reproduce a conflict manually via `KEEPLING_TEST_SYNC_MODE=conflict`, or use a real second device/account). | VoiceOver announces the dialog's heading immediately, without requiring the person to explore the window to discover the interruption happened. |
| A4 | VoiceOver: unsaved-changes dialog | Trigger the "Discard unsaved changes?" dialog (edit a task, then navigate away before saving). | The dialog moves focus into itself, onto the safe non-destructive default action ("Keep Editing"), so VoiceOver announces the interruption immediately; closing it returns focus to a visible, operable element. (Previously a disclosed gap; **fixed** in plan 03-15 and asserted by `accessibility.spec.ts`.) |
| A5 | Full Keyboard Access: end-to-end | System Settings → Keyboard → Full Keyboard Access → On. Without touching the mouse/trackpad, capture a task, open it, edit, complete/reopen, add to Today, remove from Today, move to Trash, restore, undo. | Every control in that sequence is reachable and operable via Tab/Shift-Tab/Space/Return/Arrow keys alone. Record any control that requires the mouse. |
| A6 | Full Keyboard Access: focus never gets trapped or lost | With Full Keyboard Access on, open and close every dialog (Quick Entry discard, sync conflict, unsaved-changes) via keyboard only. | Focus is always on a visible, operable element after each dialog closes — never on a removed/hidden element, never silently reset to `<body>`. |
| A7 | Non-US layout / dead keys | System Settings → Keyboard → Input Sources → add a non-US layout with dead keys (e.g. German, Spanish, or French). Switch to it. Type a task title containing an accented character produced via a dead-key sequence (e.g. `´` + `e` → `é` on a Spanish/US-International layout). | The composed character appears correctly in the title field; the title commits and displays correctly afterward. Record the exact layout used. |
| A8 | Real global-shortcut collision | Launch another real app that also registers a global shortcut close to Keepling's Quick Entry accelerator (or deliberately rebind another app to the SAME accelerator via Settings → Quick Entry Shortcut first, to force a genuine OS-level collision), then invoke the Quick Entry shortcut. | Record what actually happens: does Keepling's shortcut win, silently lose, or does Settings' rebind flow correctly detect and reject the collision? This is real OS arbitration — no test harness can synthesize it. |
| A9 | Prior-app focus return | From another real foreground app (e.g. a text editor with a document open), invoke Quick Entry, capture a task, and either submit or Escape/discard. | Keyboard focus returns to the SAME prior app and the SAME place in it (e.g. the same text field, cursor position preserved) — never to Keepling's main window, never to the Dock, never to a random other app. |
| A10 | Increase Contrast | System Settings → Accessibility → Display → Increase Contrast → On. Relaunch (or leave running and observe live). | All text and control boundaries remain legible; nothing becomes invisible or indistinguishable from its background. |
| A11 | Differentiate Without Color | System Settings → Accessibility → Display → Differentiate Without Color → On. | Sync status ("Saved on this Mac" / "Synced"), selection, and validation errors (`role="alert"` text) are all conveyed by TEXT, not color alone — confirm nothing relies solely on a color cue to be understood. |
| A12 | Reduce Transparency | System Settings → Accessibility → Display → Reduce Transparency → On. | No layout breakage; any previously-translucent surface remains legible with a solid background. |
| A13 | Reduce Motion | System Settings → Accessibility → Display → Reduce Motion → On. | Button hover/transition effects are visibly absent (matches `accessibility.spec.ts`'s automated `prefers-reduced-motion` proof — this row confirms the REAL OS setting, not just the emulated media query, drives the same behavior). |
| A14 | Light/dark change while the app is open | System Settings → Appearance. Toggle between Light and Dark while Keepling is running (no relaunch). | The window re-themes live, matches `accessibility.spec.ts`'s `color-scheme` proof, and no content becomes unreadable during or after the transition. |
| A15 | 200% zoom (real macOS display zoom, not window resize) | System Settings → Accessibility → Zoom → enable, or use a Mac set to a scaled-resolution display equivalent to ~200%. | All primary controls (capture field, Add Task, route tabs, task list, editor) remain visible and operable; no critical control is clipped off-screen. |

**Defect severity.** For any FAILING row above, record: what failed, whether it blocks daily use
of the scoped actions (release-blocking) or is a lesser limitation (non-blocking, e.g. A4's
disclosed gap). The dogfood interval below MUST NOT start with an unresolved release-blocking
defect from this pass.

## Seven-day bounded dogfood interval

Once the preconditions above are satisfied:

1. Use the packaged app (the exact digest under test) for every scoped daily-loop action —
   capture, edit, complete/reopen, Today, Trash/restore, undo, sync/conflict handling — for
   seven **consecutive calendar days**, with **at least five** of those days containing real,
   active use (not merely leaving the app open).
2. On any day the artifact changes (a new package is built from a new commit), STOP the
   interval and restart at day 1 against the new digest, per "Preconditions" above.
3. Record, using ONLY closed category names and counts (never free text containing task
   content):
   - Every scoped action for which the person fell back to Things instead of Keepling, and why
     (closed category: e.g. `missing-recurrence`, `missing-reminder-time`, `crash`,
     `data-loss-fear`, `other`).
   - Every accepted-mutation loss or silent overwrite (a change the app said was
     "Saved"/"Synced" that was later found to be missing or wrong) — this must be **zero**.
     Any occurrence is a release-blocking defect.
   - Every interruption: an offline period, a relaunch (planned or crash-recovery), a hard
     quit, a conflict encountered and how it was resolved.
   - Every defect encountered, with a disposition: `fixed-before-interval-end`,
     `deferred-non-blocking`, or `unresolved-blocking` (the interval cannot conclude
     successfully while any item carries `unresolved-blocking`).

## Explicitly deferred, NOT proven by this document or the automated gate

**Signed/notarized credential continuity remains explicitly unproven.** Nothing in this
document, `tooling/verify-desktop-phase.mjs`, or the packaged Playwright suites signs or
notarizes the `.app` — every packaged test launches an ad-hoc-built (unsigned) artifact. Do
NOT record this row as passing under any circumstance; it is out of scope for this phase's
pass claim and requires a dedicated signing/notarization + Gatekeeper-launch verification pass
before it can be claimed.

## Success criteria (D-45/D-46)

The dogfood interval is successful, and this document's evidence record may be cited as
supporting a daily-use-readiness claim, only when:

- The initial physical accessibility pass has zero unresolved release-blocking defects.
- The interval covers seven consecutive calendar days with at least five active-use days
  against one unchanged digest.
- Zero scoped Things fallbacks.
- Zero accepted-mutation loss or silent overwrite incidents.
- Zero unresolved release-blocking defects at interval end.
- Signed/notarized credential continuity is explicitly recorded as unproven, not silently
  omitted.
