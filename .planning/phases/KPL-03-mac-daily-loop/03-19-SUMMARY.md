---
phase: KPL-03-mac-daily-loop
plan: 19
subsystem: ui
tags: [offline, presentation, sync, reachability, electron, playwright, accessibility, vacuous-negation]

requires:
  - phase: KPL-03-mac-daily-loop
    provides: "the real KeeplingSyncAdapter wired into bootstrap (03-14), the store-worker sync protocol routing (03-14), the shipped-entry-point e2e pattern (03-13), and the fifteen-row macOS integration lane (03-15..03-18)"
provides:
  - "A synchronization pass that tells UNREACHABLE apart from REJECTED, using a tag from the transport rather than error-message text"
  - "An honest row for an app with no server configured -- it never implies its data is synchronized"
  - "A durable lastSuccessfulContact, written only when the server actually answered, readable across relaunches, null when it never has"
  - "The first surface in the product that renders ANY of MAC-04's presentation rows to a person"
  - "Shipped-entry-point proof against a closed loopback port, a real 500 server, and no server at all"
  - "A swept Playwright e2e/packaged suite: 24 negation sites enumerated, six vacuous ones guarded"
affects: [KPL-03 verification, MAC-04, QUAL-04, apps/web status surface, Quick Entry and Settings windows]

actuals:
  tokens: 30500
  tasks: 3
  commits: 7

tech-stack:
  added: []
  patterns:
    - "Reachability is decided by the layer that knows whether bytes came back, and carried as an own-property tag rather than instanceof -- the adapter, application and tests are bundled through different Vite entry points, so class identity could silently fail across a bundle boundary"
    - "A presentation row with null copy renders NOTHING: quiet states stay quiet rather than displaying a standing reassurance"
    - "A negation is guarded by a positive read of the same surface, never by removing the check"

key-files:
  created:
    - apps/desktop/main/application/sync-reachability.ts
    - apps/desktop/renderer/SyncStatusRow.tsx
  modified:
    - apps/desktop/main/application/DesktopApplication.ts
    - apps/desktop/main/adapters/sync.ts
    - apps/desktop/main/index.ts
    - apps/desktop/store-worker/local-store.ts
    - apps/desktop/store-worker/index.ts
    - apps/desktop/renderer/DesktopShell.tsx
    - apps/desktop/renderer/desktop.css
    - apps/desktop/test/application/sync-presentation.test.ts
    - apps/desktop/test/e2e/gap-closure.spec.ts
    - apps/desktop/test/e2e/accessibility.spec.ts
    - apps/desktop/test/packaged/security.spec.ts
    - tooling/verify-macos-integration.mjs
    - .planning/HANDOFF.json

key-decisions:
  - "No server configured settles on `offline`, not `local_saved`: 'Sync when you're back online' promises a synchronization that nothing is arranged to perform, while 'Offline — showing tasks saved on this Mac' is true word for word. `healthy` was never a candidate"
  - "The reachability boundary is the fetch call ALONE. Everything after it ran because the server answered, so a 500, a malformed body and a bounded-page violation all stay retryable_failure"
  - "lastSuccessfulContact is stored as the raw instant and is never formatted or defaulted in main; no surface renders it today, so inventing a relative-time string would be inventing a claim"
  - "The status row is NOT a live region. The workspace pins exactly one announcer, and a second one would interrupt typing on every background sync change; MAC-04 asks for a state a person can INSPECT, not one that speaks"
  - "A6's flake was fixed at its cause (a deadline asymmetry inside the row), not by re-running until green"

patterns-established:
  - "Union variants are a distinct unreachability shape from unused exported symbols, and the mechanical GAP-1 sweep cannot see them"
  - "A tag that must survive a bundle boundary is an own property with a string sentinel, never a class identity check"

requirements-completed: [MAC-04, QUAL-04]

coverage:
  - id: D1
    description: "A user whose machine cannot reach the configured server sees the offline row, not the retryable-failure row, through the shipped entry point"
    requirement: "MAC-04"
    verification:
      - kind: e2e
        ref: "apps/desktop/test/e2e/gap-closure.spec.ts#a configured server this Mac cannot reach shows the offline row -- not the retryable-failure row"
        status: pass
      - kind: unit
        ref: "apps/desktop/test/application/sync-presentation.test.ts#publishes the offline row -- not retryable failure -- when a configured server could not be reached"
        status: pass
    human_judgment: false
  - id: D2
    description: "A server that answered badly still shows retryable-failure -- an answered request is never called offline"
    requirement: "MAC-04"
    verification:
      - kind: e2e
        ref: "apps/desktop/test/e2e/gap-closure.spec.ts#a server that ANSWERS badly still shows the retryable-failure row -- an answered request is never called offline"
        status: pass
      - kind: unit
        ref: "apps/desktop/test/application/sync-presentation.test.ts#does NOT tag a server that answered badly -- a 500 stays a rejected answer"
        status: pass
    human_judgment: false
  - id: D3
    description: "An app with no server configured never publishes a row implying its data is synchronized, and reports a null last contact"
    requirement: "MAC-04"
    verification:
      - kind: e2e
        ref: "apps/desktop/test/e2e/gap-closure.spec.ts#an app with NO server configured never publishes a row implying its data is synchronized"
        status: pass
    human_judgment: false
  - id: D4
    description: "lastSuccessfulContact is durably recorded only when the server actually answered, and is never fabricated"
    requirement: "MAC-04"
    verification:
      - kind: unit
        ref: "apps/desktop/test/application/sync-presentation.test.ts#records a real successful contact when the server answers, so the offline row has an honest source"
        status: pass
      - kind: unit
        ref: "apps/desktop/test/application/sync-presentation.test.ts#reports a null last contact -- never a fabricated one -- when the server has never been reached"
        status: pass
    human_judgment: false
  - id: D5
    description: "Every negation in the Playwright e2e and packaged suites is guarded by a positive read (O-28)"
    requirement: "QUAL-04"
    verification:
      - kind: e2e
        ref: "pnpm test:desktop:e2e (60 passed) and the packaged lane (10 passed) inside node tooling/verify-desktop-phase.mjs"
        status: pass
    human_judgment: false

duration: 28min
completed: 2026-09-03
status: complete
---

# Phase KPL-03 Plan 19: Real Offline State and a Swept Playwright Suite Summary

**`{ kind: 'offline' }` went from a declared-but-never-constructed union variant to a state a person actually sees, told apart from a rejected answer by a tag that comes from the transport — and the sweep to prove it uncovered that no surface in the product rendered any MAC-04 row at all.**

## Performance

- **Duration:** 28 min of execution (plus ~10 min of macOS integration lane runs)
- **Started:** 2026-09-03T19:52Z
- **Completed:** 2026-09-04T00:16Z
- **Tasks:** 3 of 3
- **Files modified:** 14 (2 created)

## Accomplishments

- **The offline row is real and honest.** `runSyncPass()` now settles `offline` only when the request never got an answer, carrying the real prior contact instant or null, and keeps `retryable_failure` for a server that answered and the answer was a problem.
- **The distinction is made where it can honestly be made.** `KeeplingSyncAdapter#json` wraps the `fetch` call alone; everything after that line ran because the server answered. `DesktopApplication` reads a tag and never sniffs message text.
- **An unconfigured app stops implying it is synchronized.** With no server it makes no request at all and settles `offline` with a null contact.
- **MAC-04's rows reach a screen for the first time.** The RED for Task 2 revealed that nothing rendered `summary.copy` for *any* state; `SyncStatusRow` is the first surface that does.
- **The Playwright suites are swept.** All 24 negation sites enumerated with a verdict; six vacuous ones guarded with a positive read, none weakened or deleted.

## Task Commits

1. **Task 1 (RED): assert unreachable settles offline** — `ed37567` (test)
2. **Task 1 (GREEN): publish the offline row from a real transport reachability tag** — `f885878` (fix)
3. **Task 2 (RED): prove through the shipped window that the offline row reaches a user** — `58b5983` (test)
4. **Task 2 (GREEN): render the MAC-04 status row** — `dfffa08` (feat)
5. **Task 2 (Rule 1): keep exactly one live region** — `97e458e` (fix)
6. **Task 3: guard every vacuous negation in the Playwright suites (O-28)** — `0234da7` (test)
7. **Rule 1: give A6 the same focus deadline for restore as it gives for open** — `195b684` (fix)

## Gate Evidence

Full summary line, verbatim, from `node tooling/verify-desktop-phase.mjs`:

```
Desktop phase gate summary: lanes=9 failed=0
  PASS typecheck-desktop cases=1 duration_ms=1114
  PASS typecheck-web cases=1 duration_ms=2080
  PASS unit-pure-vector-store-worker-performance cases=172 duration_ms=1038
  PASS ipc-hostile-bridge cases=66 duration_ms=675
  PASS electron-e2e cases=60 duration_ms=56124
  PASS package-once cases=1 duration_ms=13026
  PASS packaged cases=10 duration_ms=8821
  PASS macos-integration cases=92 duration_ms=275
  PASS privacy cases=1 duration_ms=20
Desktop phase gate: PASSED
```

macOS integration evidence re-recorded for the new artifact:

```
LANE_ARTIFACT application_digest=e1c9d695da26507ae3a6a3b711f6884df5602022efe62d4a0b0cdf5b389754a4
macOS integration lane summary: rows=15 failed=0 cases=92 duration_ms=172289
macOS integration lane: PASSED cases=92
```

Scoped runs:

```
pnpm test:desktop sync-presentation        Test Files 1 passed (1)   Tests 12 passed (12)
pnpm test:desktop                          Test Files 18 passed (18) Tests 169 passed (169)
pnpm test:desktop:e2e gap-closure          9 passed (13.2s)
pnpm test:desktop:e2e                      60 passed (52.5s)
```

## RED Evidence

Task 1, before any behavior change — the observed rows, not a paraphrase:

```
AssertionError: expected 'retryable_failure' to be 'offline'   (configured server never answered)
AssertionError: expected 'retryable_failure' to be 'offline'   (never-contacted app)
AssertionError: expected 'local_saved' to be 'offline'         (no server configured at all)
AssertionError: expected [] to deeply equal [ '2026-09-03T12:00:00.000Z' ]  (no contact recorded)
AssertionError: expected false to be true                      (transport did not tag a refused connection)
Tests  4 failed | 5 passed (9)   then, with the adapter reverted to HEAD:  1 failed | 11 passed (12)
```

Task 2, before the renderer surface existed — identically for all three cases:

```
Error: expect(locator).toHaveText(expected) failed
Locator: locator('#sync-status-row')
Expected: "Offline — showing tasks saved on this Mac"
Error: element(s) not found
```

## Files Created/Modified

- `apps/desktop/main/application/sync-reachability.ts` — the shared reachability vocabulary: `SyncUnreachableError` and `isSyncUnreachable`. An own-property string tag, not `instanceof`, because the adapter, the application and the tests are bundled through different Vite entry points.
- `apps/desktop/main/adapters/sync.ts` — `#json` wraps the `fetch` call alone and rethrows the tagged error; everything below that line ran because the server answered.
- `apps/desktop/main/application/DesktopApplication.ts` — `runSyncPass()` reads the tag; `SyncPort.configured?()`, `LocalStorePort.recordSuccessfulContact?()`, and `SyncState.lastSuccessfulContact` added (all optional, so no existing port breaks).
- `apps/desktop/store-worker/local-store.ts` / `store-worker/index.ts` — `recordSuccessfulContact` persisted in `namespace_metadata` and routed through the worker protocol; `syncState()` reads it back.
- `apps/desktop/main/index.ts` — `realSync.configured` reports whether an adapter exists; `WorkerLocalStore` forwards `recordSuccessfulContact`.
- `apps/desktop/renderer/SyncStatusRow.tsx` + `DesktopShell.tsx` + `desktop.css` — the main window's status row.
- `apps/desktop/test/application/sync-presentation.test.ts` — eight new cases across the application and transport boundaries.
- `apps/desktop/test/e2e/gap-closure.spec.ts` — three shipped-entry-point cases.
- `apps/desktop/test/e2e/accessibility.spec.ts`, `test/packaged/security.spec.ts` — six O-28 guards.
- `tooling/verify-macos-integration.mjs` — A6's focus-restore deadline.

## Decisions Made

**The no-server-configured row is `offline`, deliberately.** The plan asked for the reasoning to be recorded. `healthy` is the one answer that is clearly wrong — a quiet row a person reads as "everything is synchronized" when nothing has ever been synchronized. `local_saved`'s copy is "Saved on this Mac. Sync when you're back online", which promises a synchronization that nothing is arranged to perform; there is no server to come back online *to*. `offline`'s copy — "Offline — showing tasks saved on this Mac" — is true word for word in this situation, and its `lastSuccessfulContact` is honestly null because this app has never contacted anything. It also carries no action, which is right: there is nothing for the person to retry.

**`lastSuccessfulContact` is stored raw and never formatted.** The unit fixture uses a human string ('10 minutes ago'), but no surface renders the field today (grep: only `presentation.ts` and `preload/contracts.ts` mention it). Formatting it in main would be inventing a presentation decision nobody has made; storing the instant keeps the fact and defers the wording.

**Recording contact is best-effort.** A local store that cannot write the instant must not downgrade a genuine successful pass into a retryable failure, so the write is wrapped and swallowed (D-18). It is a presentation source, never a correctness step.

**The status row does not announce.** See Deviations.

## Deviations from Plan

### 1. [Rule 2 — Missing critical functionality] Nothing rendered any presentation copy

- **Found during:** Task 2 RED.
- **Issue:** `DesktopApplication` has published a closed presentation row for every state since 03-05 and the preload bridge has delivered it with a sequence contract since 03-08, but no surface anywhere rendered `summary.copy`. `renderer/desktopClientFacade.ts` subscribed only to trigger a snapshot refetch. Every one of MAC-04's rows — not just `offline` — was unreachable to a person, which is why the RED failed identically for all three cases with `element(s) not found`.
- **Fix:** `apps/desktop/renderer/SyncStatusRow.tsx`, wired into `DesktopShell`. It renders main's copy verbatim and infers nothing; a null copy renders nothing at all, so `healthy` and the anti-flicker grace period stay quiet.
- **Commit:** `dfffa08`. Recorded as **O-31** in HANDOFF.json, still open for the Quick Entry/Settings windows and for apps/web.

### 2. [Rule 1 — Bug] The new row broke the single-live-region contract

- **Found during:** Task 3 verification, immediately after the row landed.
- **Issue:** `expect(locator('[aria-live]')).toHaveCount(1)` → `Received: 2` (`accessibility.spec.ts:112`). The row carried its own `aria-live="polite" role="status"`.
- **Fix:** The contract is right and the row was wrong. A second announcer would interrupt whatever someone is typing on every background synchronization change. The row is now a labeled complementary landmark that is always there to look at and never speaks; `SyncRecovery` remains the single announcer. Whether an offline transition *should* be announced is an unmade product decision, recorded in O-31.
- **Commit:** `97e458e`.

### 3. [Rule 1 — Bug] A6 failed inside `--all` on a deadline asymmetry

- **Found during:** the gate run after Task 3.
- **Issue:** A6's final case failed with `last read was nothing` inside `--all` (row duration 39.5s) while passing 4/4 standalone (24.9–25.5s). Per the standing rule I did **not** re-run until green: the row waits 10s for a dialog to *open* but gave only 5s for focus to be restored after one *closes*, even though restoration is the slower operation (the destructive branch commits a route change, re-renders the list, and runs two focus effects).
- **Fix:** both deadlines are 10s. `usableFocus(last)` is asserted exactly as before and `settledFocus` still returns whatever it last saw at the deadline, so genuinely lost focus still fails loudly.
- **Commit:** `195b684`. Generalisation recorded as **O-32**.

### 4. [Disclosed file scope] Files touched beyond the plan's `files_modified`

`sync-reachability.ts`, `adapters/sync.ts`, `store-worker/local-store.ts`, `store-worker/index.ts`, `renderer/SyncStatusRow.tsx`, `DesktopShell.tsx`, `desktop.css`, `test/application/sync-presentation.test.ts`, `test/e2e/accessibility.spec.ts`, `test/packaged/security.spec.ts`, `tooling/verify-macos-integration.mjs`. The plan's declared list named `recovery-presentation.test.ts` for the unit proof; the new cases went to `sync-presentation.test.ts` instead, which already owns `runSyncPass()` presentation behavior. `recovery-presentation.test.ts` needed no change — its `offline` fixture was already correct and still passes.

## O-28 Sweep: Every Site and Its Verdict

24 negation sites in `test/e2e/**` and `test/packaged/**`. Six were vacuous and are now guarded; eighteen were already safe.

| Site | Assertion | Verdict |
|---|---|---|
| gap-closure.spec.ts:89 | `not.toContain('super-secret-refresh-token-value')` | SAFE — guarded by `expect(onDisk.length).toBeGreaterThan(0)` on the line above |
| gap-closure.spec.ts:342 | `getByText(RETRYABLE_COPY).toHaveCount(0)` | SAFE — new, guarded by `toHaveText(OFFLINE_COPY)` above it |
| gap-closure.spec.ts:371 | `getByText(OFFLINE_COPY).toHaveCount(0)` | SAFE — guarded by `toHaveText(RETRYABLE_COPY)` above it |
| gap-closure.spec.ts:393 | `not.toMatch(/synced\|up to date\|everything/i)` | SAFE — guarded by `toHaveText` plus an explicit non-empty length check |
| keyboard-menus.spec.ts:126 | `getByRole('button', { name: 'Reopen' }).toHaveCount(0)` | SAFE — followed by `Complete` `toBeVisible()`, proving the pane rendered |
| keyboard-menus.spec.ts:147 | `title not.toContain('Extremely private task title')` | SAFE — guarded by `expect(title).toBe('Keepling — Inbox')` immediately before |
| accessibility.spec.ts:55 | `heading 'Inbox Is Clear' toHaveCount(0)` | SAFE — guarded by `getByRole('list', { name: 'Tasks' }).toBeVisible()` |
| accessibility.spec.ts:82 | `firstRow not.toHaveAttribute('aria-current')` | SAFE — guarded by `expect(firstRow).toBeFocused()` |
| **accessibility.spec.ts:83** | `secondRow not.toHaveAttribute('aria-current')` | **VACUOUS → GUARDED.** A negated locator matcher passes against a locator resolving to nothing; `secondRow` had no positive read. Added `toBeVisible()` |
| accessibility.spec.ts:87 | `secondRow not.toHaveAttribute('aria-current')` | SAFE — guarded by `toBeFocused()` on the same locator |
| **accessibility.spec.ts:93** | `firstRow not.toHaveAttribute('aria-current')` | **VACUOUS → GUARDED.** Same shape; the preceding positive is on a different locator. Added `toBeVisible()` |
| accessibility.spec.ts:112/123 | `[aria-live] toHaveCount(1)` | SAFE — a positive count, not a negation |
| accessibility.spec.ts:210 | `dialog toHaveCount(0)` | SAFE — the same locator was asserted `toBeVisible()` earlier, so this proves a real disappearance |
| accessibility.spec.ts:221 | `focusAfterClose not.toBeNull()` | SAFE — followed by `expect(focusAfterClose?.visible).toBe(true)`, which fails on null |
| **accessibility.spec.ts:260** | `darkBackground not.toBe(lightBackground)` | **VACUOUS → GUARDED.** A pair of malformed readings could differ for a reason unrelated to the OS appearance. Both are now asserted to match `/^rgba?\(/` first |
| **accessibility.spec.ts:274** | `color not.toBe('')` | **VACUOUS → GUARDED.** Admits any value at all, including a non-colour. Now states what was read |
| **accessibility.spec.ts:290** | `withMotion not.toBe('0s')` | **VACUOUS → GUARDED.** The strongest one: the evaluate returns `null` when there is no button to measure, and `null !== '0s'` passed — a window that rendered no controls "proved" motion was enabled |
| accessibility.spec.ts:296 | `reduced toBe('0s')` | SAFE — a positive equality |
| daily-loop.spec.ts:71 | `[data-workspace-dirty="true"] toHaveCount(0)` | SAFE — guarded by the saved-title heading `toBeVisible()` above |
| daily-loop.spec.ts:124 | `'This task changed somewhere else.' toHaveCount(0)` | SAFE — the same text was asserted visible before the resolution, and a positive `Buy milk` read follows |
| keyboard-quick-entry.spec.ts:178 | `draft toBeNull()` | SAFE — the preceding `toHaveValue('Ping accountant')` proves the draft was non-null before the discard |
| real-stack-sync.spec.ts:112 | `adapter.load() resolves.toBeNull()` | SAFE — preceded by `resolves.toBe(credential)` on the same adapter |
| real-stack-sync.spec.ts:433 | `readyMutations() toHaveLength(0)` | SAFE — preceded by `expect(pass.settled).toBe(1)` and an exact-bytes equality |
| real-stack-sync.spec.ts:504, 527 | `accessToken() resolves.toBeNull()` | SAFE — preceded by a positive read of the same credential family (`server.revoked` equality; the refresh outcome equality) |
| **packaged/security.spec.ts:159** | `outcome not.toBe('granted')` | **VACUOUS → GUARDED.** Passed for `undefined`. Now asserts `toMatch(/^denied:/)` — the positive fact the test exists to establish |

## Open Items

Written into `.planning/HANDOFF.json` `open_items`, not only here.

- **O-30 — CLOSED.** The offline state is constructed in production, distinguishes unreachable from rejected, and is proven through the shipped entry point.
- **O-28 — CLOSED.** The Playwright e2e and packaged suites are swept; the table above is the record.
- **O-31 — NEW, open.** No renderer surface rendered any presentation copy. Fixed for the desktop main window only: Quick Entry and Settings still show nothing, apps/web has no equivalent, and whether an offline transition should be *announced* (and by which single announcer) is an unmade product decision.
- **O-32 — NEW, open.** Fixed deadlines in the macOS lane were tuned standalone but are consumed inside `--all`, which runs ~1.6x slower because the VoiceOver-layer rows leave an AX client attached. A6 is fixed; the other fixed timeouts should be audited against `--all` timings rather than waiting for each to flake once.
- **O-33 — NEW, open.** Carried forward from O-30: the mechanical GAP-1 sweep looks for exported *symbols* referenced only by tests and structurally cannot see a union *variant* that is never constructed. Until it enumerates variants, a clean GAP-1 result must not be read as "no unreachable delivered code remains". Hand-check candidates: the rest of `DesktopPresentationInput`, `RecoveryActionCode` (authored action codes that nothing in the renderer dispatches on), and `SyncOutcome`.

## Requirements

`MAC-04` and `QUAL-04` are listed in this plan's frontmatter and their evidence now exists, but **no checkbox in `.planning/REQUIREMENTS.md` was touched** — requirement re-derivation is the orchestrator's, per O-17.

## Self-Check: PASSED
