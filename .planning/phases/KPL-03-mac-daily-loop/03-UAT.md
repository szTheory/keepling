---
status: complete
phase: KPL-03-mac-daily-loop
source: 03-13..03-24 SUMMARY.md (24 plans, 24 summaries)
started: 2026-09-04T10:50:00Z
updated: 2026-09-04T11:20:00Z
---

## Current Test

[testing complete]

<!--
METHOD. This phase runs under a standing zero-human-UAT constraint: no test
below was answered by a person. Each result is the observed output of an
automated lane that drives the SHIPPED artifact -- the packaged .app, the real
accessibility tree, or a real Phoenix server on real PostgreSQL. Where no such
evidence exists the row says so and is recorded as an issue or as blocked, never
as a pass. `workflow.live_dom_uat` is false and the product is Electron rather
than a web page, so the browser-MCP automated-UI path does not apply.
-->

## Tests

### 1. Capture, edit, complete/reopen, Today, trash/restore through the shipped app
expected: the complete daily loop works in the packaged application, through user-visible roles only
result: pass
evidence: packaged lane, 'the packaged app completes capture, edit, complete/reopen, Today placement, and trash/restore through the exact contract'; e2e 'completes the full daily loop through user-visible roles only'

### 2. Every mutation reaches a real server
expected: all eight command types reach real Phoenix and reconcile against real PostgreSQL
result: pass
evidence: real-stack lane, 'every mutation a person can perform reaches real Phoenix and reconciles against real PostgreSQL'; asserted by name at the server via the forwarding proxy, not from the client's own state

### 3. Offline capture survives a hard kill
expected: an offline capture and a Quick Entry draft both survive a hard kill and relaunch, then reconcile
result: pass
evidence: packaged lane, offline-capture and daily-loop specs; the server itself returned 404 for the mutation while offline

### 4. An edit never overtakes its capture
expected: ordering holds under reconnection
result: pass
evidence: real-stack lane proves ARRIVAL ORDER at the server (['capture_task','edit_task']), not merely local queue order

### 5. A real server conflict reaches the person
expected: a conflict raised by a real second writer is surfaced as conflict copy in the shipped window
result: pass
evidence: real-stack lane; conflict produced by a real browser client editing the same task through the real server while the app was disconnected

### 6. Undo reconciles, and works with no server
expected: undo reaches the server via its issued handle; with no server configured undo still works locally
result: pass
evidence: real-stack REAL_STACK_UNDO handle=server_issued reverted_on_server=1 survived_relaunch=1; and REAL_STACK_IN_FLIGHT held=1 refused=1 command_survived=1 server_holds_completion=1

### 7. An existing database survives the schema migration
expected: a database written before the outbox-state column opens, migrates, and keeps its tasks AND queued commands
result: pass
evidence: packaged lane (11 cases) -- proven by the SHIPPED artifact opening a genuine pre-0002 database, not by a unit fixture

### 8. Synchronization state is visible without reading logs
expected: offline, syncing, conflict, authentication-expired and unrecoverable are each visible, with working remedies
result: pass
evidence: e2e specs for the offline row, the retryable-failure row, the unconfigured case, Retry running a REAL pass, Export writing a real file, and Quick Entry saying so in its own window

### 9. Keyboard-only operation and VoiceOver
expected: the scoped sequence is completable by keyboard alone; focus is never trapped or lost
result: pass
evidence: macOS rows A1-A8 against the real AXUIElement tree of the shipped app (A5 13 cases, A6 6 cases, A7 non-US dead keys, A8 real global-shortcut OS arbitration)

### 10. Privacy: no task content leaks
expected: task text, credentials, tokens and paths never enter diagnostics, menus, app-switcher metadata or renderer APIs
result: pass
evidence: privacy lane; e2e 'the native window title names only Keepling and the coarse destination, never task content (D-07)'

### 11. Prior-application focus and caret return, in a full lane run
expected: macOS row A9 passes as part of the complete A1-A15 recording run
result: issue
reported: "ROW id=A9 status=FAIL cases=1 duration_ms=118970 -- could not reach the Quick Entry capture field by keyboard within 24 tab presses (focus stopped on nothing). Lane aborted: 15 rows requested but 9 reported."
severity: major

### 12. Desktop visual evidence at the specified breakpoints and accessibility modes
expected: 03-UI-SPEC.md requires light/dark snapshots at 680x520, 1024x700, 1064x700, 1180x780 and 1440x900, plus 200% zoom, Increase Contrast/forced colors, Reduce Transparency and Reduce Motion
result: issue
reported: "No desktop visual-snapshot evidence exists. No snapshot directories, and no toHaveScreenshot/toMatchSnapshot anywhere in apps/desktop. The repository's only visual spec is apps/web/e2e/visual.spec.ts, which covers the WEB app. The UI-SPEC checker signed this dimension off as PASS."
severity: minor

### 13. Signed and notarized credential continuity
expected: credentials survive across a signed, notarized build
result: blocked
blocked_by: release-build
reason: explicitly deferred and unproven for the whole phase; requires a signing identity this environment does not have

### 14. CI execution of the release workflows
expected: .github/workflows lanes run and gate promotion
result: blocked
blocked_by: third-party
reason: O-35 -- there is no git remote, by standing constraint, so nothing in .github/workflows has ever executed. Disclosed inline at QUAL-02/QUAL-03 rather than claimed.

## Summary

total: 14
passed: 10
issues: 2
pending: 0
skipped: 0
blocked: 2

## Gaps

- truth: "macOS row A9 passes as part of the complete A1-A15 recording run"
  status: failed
  reason: "A9 FAILED under --all after 118970ms ('focus stopped on nothing'), aborting rows A10-A15 so they never ran. Re-run standalone via --rows A9 it PASSES in 9420ms with 6 cases. Deterministic difference, not a broken feature: interference from the immediately preceding row A8, which registers a rival global shortcut and forces real OS arbitration."
  severity: major
  test: 11
  root_cause: "Not yet diagnosed. The shape matches the A3 defect 03-20 fixed -- a row that passes standalone and fails under --all because a prior row left machine state behind. A8 is the prime suspect because it is the only row that registers a rival application-level global shortcut."
  artifacts:
    - path: "tooling/verify-macos-integration.mjs"
      issue: "A9 depends on machine state that A8 mutates; the 119s duration indicates a hang to timeout rather than a fast assertion failure"
  missing:
    - "Diagnose the A8 -> A9 interference and fix the race in A9, per O-29: the response to a flaky row is to fix the race, NEVER to re-record until a run happens to pass."
    - "IMPORTANT CONSEQUENCE for the gate: --all is the RECORDING path. The phase gate's macos-integration lane REUSES recorded evidence bound to the artifact digest and does not re-run the rows, so `lanes=10 failed=0` does NOT mean the rows pass today. Recorded evidence 8058ed13 (15 rows, source_revision d76b1e1) is for the current artifact and was captured on a run that succeeded."
  debug_session: ""

- truth: "Desktop visual evidence exists at the breakpoints and accessibility modes the UI-SPEC requires"
  status: failed
  reason: "No desktop visual-snapshot evidence exists at all -- no snapshot directories, no toHaveScreenshot/toMatchSnapshot in apps/desktop. The UI-SPEC's 'Verification Evidence Required' section demands light/dark snapshots at five named breakpoints plus 200% zoom, Increase Contrast/forced colors, Reduce Transparency and Reduce Motion, and the checker signed the visual dimension off as PASS."
  severity: minor
  test: 12
  root_cause: "An evidence requirement was written into the UI-SPEC and signed off without a corresponding lane ever being built. Same family as the QUAL-02 CI disclosure: a claim about evidence that does not exist."
  artifacts:
    - path: ".planning/phases/KPL-03-mac-daily-loop/03-UI-SPEC.md"
      issue: "Verification Evidence Required lists desktop visual snapshots; nothing implements them"
  missing:
    - "Decide deliberately: build a desktop visual-snapshot lane, or amend the UI-SPEC to state that the theme/contrast/motion/reflow properties are proven BEHAVIOURALLY (e2e specs '200% reflow', 'theme', 'contrast: forced-colors', 'motion: prefers-reduced-motion', and the theme-change-mid-dialog case) rather than by pixel comparison."
    - "Do NOT resolve by quietly deleting the requirement from the spec."
  debug_session: ""
