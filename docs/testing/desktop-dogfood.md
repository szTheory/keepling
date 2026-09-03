# Desktop Dogfood (D-42/D-45/D-46)

**Nothing in this document is a checklist, a gate, or a sign-off. There is no form to fill in,
nothing to count, and nothing to certify.** Keepling's evidence comes from machines. What is
asked of a person is one thing only: use the app and say what you think.

Everything the old version of this document asked a human to perform by hand — the fifteen-row
physical accessibility pass A1-A15 — is now executed against the packaged `.app` by
`tooling/verify-macos-integration.mjs`, at the macOS layer those rows were always about: the real
`AXUIElement` tree VoiceOver speaks, real `CGEvent` keystrokes, real input sources, and real
system settings.

## Just use it, and tell me what you think

Use the packaged app for whatever you would normally use a task app for. If something annoys you,
feels slow, reads wrong, or makes you reach for another app instead — say so, in whatever form is
convenient. A sentence is fine. There is no required cadence, no required duration, no active-day
count, and no disposition vocabulary.

That is the whole contract.

## What the machines cover, so you do not have to

| Layer | Owner |
|---|---|
| Unit, store, worker, IPC, renderer | `pnpm test:desktop`, `pnpm test:desktop:ipc` |
| Real Electron end-to-end, DOM/ARIA accessibility, appearance media queries | `apps/desktop/test/e2e/accessibility.spec.ts` and friends |
| The exact packaged artifact | `tooling/smoke-desktop-packaged.mjs` |
| Performance budgets | `tooling/measure-desktop-performance.mjs --check-budgets` |
| **The macOS layer: rows A1-A15** | **`tooling/verify-macos-integration.mjs`** |
| All of the above, as one anti-vacuous gate | `tooling/verify-desktop-phase.mjs` |

### Rows A1-A15, and what actually asserts them now

| # | Row | How it is asserted by machine |
|---|---|---|
| A1 | Screen-reader capture | Reads the real AX tree: the capture field's label, the Add Task button's name and its state change, real keystrokes landing as `AXValue`, and the post-submit "Saved on this Mac" announcement. |
| A2 | Screen-reader list navigation | Each row's announced name carries title AND sync status; roving AX focus moves by arrow key without selecting; `aria-current` selection stays distinguishable from AX focus (D-05). |
| A3 | Dialogs announce themselves | Quick Entry discard confirmation and the inline sync conflict each move AX focus into themselves, with the heading reachable in the focused element's ancestry. |
| A4 | Unsaved-changes dialog | Focus moves onto the safe default action ("Keep Editing") and returns to a visible operable element on close. (Previously a disclosed gap; **fixed** in plan 03-15.) |
| A5 | Full Keyboard Access, end to end | Full Keyboard Access enabled as the real OS setting, then capture → open → edit → save → complete → reopen → Today → un-Today → trash → restore → undo driven by `CGEvent` keys alone. The lane posts no mouse event at all. |
| A6 | Focus never trapped or lost | Every dialog opened and closed by keyboard, including the destructive branch that removes the element focus was on; after each close, focus must be on a visible, operable element. |
| A7 | Non-US layout / dead keys | A dead-key layout is enabled and selected for real; a raw virtual key code is posted so the OS composes through the active input source; the composed character is asserted in `AXValue` and after commit. |
| A8 | Real global-shortcut collision | A separate real process registers the same accelerator through the same Carbon API and reports what the OS delivered to it. |
| A9 | Prior-app focus return | A real prior application is focused with a caret at a known offset; Quick Entry is invoked and both submitted and discarded; frontmost application and `AXSelectedTextRange` are asserted unchanged. |
| A10 | Increase Contrast | Real OS setting, legibility asserted as a measured WCAG contrast ratio over captured pixels. |
| A11 | Differentiate Without Color | Real OS setting, plus assertions that sync status, selection and validation are conveyed by text and announced state, not colour. |
| A12 | Reduce Transparency | Real OS setting, measured contrast. |
| A13 | Reduce Motion | Real OS setting, measured contrast. |
| A14 | Light/Dark while running | Appearance changed while the app is open; the window's measured background colour must actually change, with contrast still passing. |
| A15 | ~200% zoom equivalent | The window is reduced through the accessibility API and every primary control is asserted unclipped inside the window's real AX frame. |

Two rows carry **measured findings** rather than clean passes, and they are recorded here rather
than quietly dropped:

- **A8**: macOS global hot keys are **not exclusive**. Both applications' registrations succeed
  (verified in both orders) and the keystroke is delivered to **both**. A colliding application
  therefore does not steal Keepling's accelerator, and Keepling reporting the accelerator as
  available is a true statement. The row asserts exactly that, having measured it.
- **A9**: **currently failing, and correctly so.** `QuickEntryWindowController` accepts an
  optional `foregroundApp` port and calls it to capture and restore the prior application, but
  no implementation of that port exists and none is passed in `main/index.ts#bootstrap()`. Prior
  application focus return is therefore not implemented in the shipped app. This was found by the
  lane on its first run.

## What the lane does to the machine it runs on, and how it undoes it

This lane is not passive. While it runs it:

- takes over the keyboard (it posts real key events, so do not type during a run),
- enables Full Keyboard Access,
- enables and selects an additional keyboard input source,
- switches the system appearance between Light and Dark,
- turns on Increase Contrast, Differentiate Without Color, Reduce Transparency and Reduce Motion,
- resizes the app window,
- briefly runs a second small process that registers a global shortcut.

Every one of those settings is **captured to disk before the first mutation** and restored on
every exit path — normal exit, an exception, and SIGINT/SIGTERM/SIGHUP — with restoration
**verified by re-reading**. `node tooling/verify-macos-integration.mjs --self-test-restore` proves
both hard cases: a mid-row exception, and a real external `SIGTERM` to a real child process that
has no tidy return path.

If a run is ever cut short in a way that still leaves something changed:

```bash
node tooling/verify-macos-integration.mjs --restore
```

restores from the capture taken before the first mutation and verifies the result.

## It does not run on every gate invocation

Because of the above, the rows are executed **once per packaged artifact**, not once per gate run:

```bash
pnpm package:desktop && node tooling/verify-macos-integration.mjs --all
```

That records the result against the exact `applicationDigestSha256` (the same digest-binding
idiom D-47 already uses for package-once → promotion). `tooling/verify-desktop-phase.mjs` then
runs the lane as `--gate`, which **executes no row and changes no setting** — it reuses that
record and prints the digest and the original run timestamp so the reuse is never invisible.

Reuse is strict. Evidence is bound to the artifact digest *and* to the Swift probe source
digests, must cover every row, and must contain no failing row. Missing, stale, partial or
failing evidence is a loud failure naming the command that produces it — never a skip and never a
soft pass. An ordinary gate run, and ordinary local development, touch nothing.

The standalone runner is also opt-in: with no mode flag it prints its usage and exits rather than
taking over the machine.

## One-time permissions

The lane needs capabilities macOS protects. Each absent capability is a **loud failure naming the
exact System Settings path** — never a skip, never a soft pass, because a row that did not
actually exercise macOS must never report green.

| Capability | Needed by | Where to grant it |
|---|---|---|
| Accessibility | A1-A9, A11, A15 (AX tree reads, `CGEvent` posting) | System Settings → Privacy & Security → Accessibility |
| Screen Recording | A10-A14 (WCAG contrast measured from real pixels) | System Settings → Privacy & Security → Screen Recording |
| Full Disk Access | A10-A13 (writing the protected `com.apple.universalaccess` domain) | System Settings → Privacy & Security → Full Disk Access |

Grant them to the application that *runs* the lane — the terminal, IDE or CI agent process — not
to the compiled probe; TCC attributes the grant to the responsible process. SIP protects the TCC
database, so this cannot be scripted. It is a one-time approval that then persists.

`com.apple.universalaccess` deserves a specific warning: an unentitled process may write to it
and receive **no error** while nothing is actually stored. The lane therefore verifies every
settings write by re-reading it in a separate process, and treats a silently-rejected write as a
failure.

### Rows that need no Accessibility grant

Each row is tagged in the runner with `requiresAccessibilityTrust`, and
`--without-accessibility-trust` runs exactly the subset that does not need it: **A10, A12, A13,
A14**. Those rows use no accessibility API and post no keystrokes — they launch the packaged app,
apply the real OS setting, and measure contrast from rendered pixels. A11 and A15 do need the
grant, because A11's "conveyed by text, not colour" claim is a claim about the accessibility tree
and A15 asserts control geometry read from AX frames; weakening either to avoid AX would assert
less than the row says. Evidence recorded from a partial subset can never satisfy the gate as if
it covered all fifteen rows.

## Explicitly deferred, NOT proven by this document or the automated gate

**Signed/notarized credential continuity remains explicitly unproven.** Nothing in this
document, `tooling/verify-desktop-phase.mjs`, `tooling/verify-macos-integration.mjs`, or the
packaged Playwright suites signs or notarizes the `.app` — every packaged test launches an
ad-hoc-built (unsigned) artifact. Do NOT record this row as passing under any circumstance; it is
out of scope for this phase's pass claim and requires a dedicated signing/notarization +
Gatekeeper-launch verification pass before it can be claimed.
