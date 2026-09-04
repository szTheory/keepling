---
phase: KPL-03-mac-daily-loop
plan: 21
subsystem: desktop-sync-and-server-auth
tags: [device-grant, real-stack, quick-entry, accessibility, contract, gate]
status: complete
requires:
  - 03-19 (O-30 closed; the offline row is real)
  - 03-20 (the macOS lane acts on observed state)
provides:
  - a Quick Entry window whose Escape cannot be disabled by focus position
  - the device-grant credential class as a mutating client (D-49)
  - the packaged Mac app proven against real Phoenix on real PostgreSQL
  - a shared real-backend harness both the web and desktop lanes use
affects:
  - apps/server (router, auth plug, command context, device grant)
  - packages/contracts (DeviceBearer scope, BrowserSession, DurableCommandType)
  - apps/desktop (Quick Entry renderer, capture serialization, local store validation)
  - tooling (new real-stack lane and gate wiring)
tech-stack:
  added: []
  patterns:
    - one credential decision at the pipeline, each class judged by its own rules
    - an optional self-describing discriminator, verified against the endpoint, never routed on
    - a real forwarding proxy as the only mechanism for "unreachable"
key-files:
  created:
    - apps/web/e2e/support/backend.ts
    - apps/desktop/test/real-stack/real-stack-sync.spec.ts
    - apps/server/lib/keepling_web/command_discriminator.ex
    - apps/server/test/keepling_web/device_grant_command_test.exs
    - tooling/verify-real-stack-desktop.mjs
  modified:
    - apps/desktop/renderer/quick-entry.tsx
    - apps/desktop/main/application/DesktopApplication.ts
    - apps/desktop/store-worker/local-store.ts
    - apps/server/lib/keepling_web/{auth.ex,router.ex}
    - apps/server/lib/keepling/accounts/device_grant.ex
    - apps/server/lib/keepling_web/controllers/command_controller.ex
    - packages/contracts/openapi/keepling.yaml
    - tooling/verify-desktop-phase.mjs
    - apps/web/e2e/support/stack.ts
  renamed:
    - apps/desktop/test/e2e/real-stack-sync.spec.ts -> apps/desktop/test/e2e/fixture-server-sync.spec.ts
decisions:
  - D-49 applied: the device-grant credential class may mutate; the command surface is extended rather than forked
  - the durable command bytes carry an optional type discriminator, verified server-side against the endpoint
  - the real-stack lane lives in its own directory and Playwright project, not in test/packaged
  - the misleadingly-named fixture spec is renamed and kept, not deleted
metrics:
  duration: ~3h
  completed: 2026-09-04
actuals:
  tokens: 118000
  tasks: 3
  commits: 12
---

# Phase KPL-03 Plan 21: Close the Last Two Blockers Summary

Escape now works from every focus position in Quick Entry, and the packaged Mac
app exchanges real bytes with real Phoenix on real PostgreSQL — which took
fixing three genuine client/server disagreements that no fixture had ever
surfaced.

## What this plan actually found

The plan's premise was that O-34 was mostly wiring: "the work is wiring the
desktop lane to that existing harness, not building a server story from
scratch." That was wrong, and finding out why was the substance of the plan.

Pointing a real packaged client at a real server for the first time produced
three disagreements in a row:

1. **The device grant could not mutate at all.** The server issued the client a
   grant, accepted it on `GET /api/v1/sync`, and refused the same credential on
   `POST /api/v1/commands/capture-task` and `GET /api/v1/mutations/:id`. Those
   routes required a browser session cookie and a same-origin `Origin`. Filed as
   O-37, escalated as a Rule 4 architectural decision, decided as D-49, and
   implemented here.
2. **The command body was a shape no server accepts.** The desktop serialized
   `{mutation_id, task_id, title, type}`; the contract requires `version: 1`.
   Every capture this client had ever queued would have been refused 400. The
   in-process fixture that was supposed to model the server sent a *different*
   shape than the shipped client, so it did not even fake the client faithfully.
3. **Every Mac mutation would have been recorded as `client_kind: "web"`** — a
   visible untruth in the user's own activity feed.

None of these were reachable by fixture testing, because a fixture agrees with
whatever the client does.

## Task 1 — O-36, Escape (MAC-02)

Two independent defects, both fixed, because fixing only the visible one leaves
the trap armed for the next dialog.

- **Focus restoration.** The discard confirmation returned focus to nowhere —
  measured as `AXWebArea "Keepling"`, the document. It now returns focus to the
  control that opened it when that control still exists (`Keep Draft`), and to
  the title field when it does not (`Discard Draft` unmounts `Discard Draft…`
  along with the draft, so the fallback is the live path on the confirm branch,
  not decoration).
- **The binding itself.** Escape and Command-Return moved from
  `<div onKeyDown>` to a **window-level** listener. React's synthetic keydown
  only fires for keys delivered *into* that subtree, so with focus on the body
  the key reached the document, never descended, and did nothing. There is now
  no focus position inside the window from which Escape can fail.

Deliberately **not** a main-process global accelerator: Escape is a window-local
key, and a global one would swallow Escape from every other application on the
Mac. `usableFocus()` in the macOS lane still accepts the `AXWebArea` and was
left alone as the plan directed — that is what made row A6 blind here, and
tightening it would turn unrelated rows red.

RED first: both new `@windowed` tests failed, the second timing out with the
window still open, which is the defect verbatim. 7/7 pass after, no existing
assertion weakened. macOS rows A3 5/5 and A6 6/6.

## Task 2 — O-34/O-37, a real server

**The harness is shared, not copied.** The real PostgreSQL + migrations + seed +
Phoenix half of `apps/web/e2e/support/stack.ts` was extracted to
`backend.ts`; `stack.ts` imports it and keeps only what a browser needs on top
(Vite, the single-origin proxy). The desktop lane imports the same module, so it
cannot drift from the harness the web lane proves against.

**The server change (D-49).** One credential decision now lives in
`KeeplingWeb.Auth#authenticate_client`. A request presenting
`Authorization: Bearer` is a native client, authenticated by its device grant,
with CSRF checks skipped because there is no ambient credential to ride. Every
other request is a browser and takes exactly the path it took before —
`load_session`, `require_authenticated`, `protect_from_forgery`, then
`require_trusted_origin` for mutations — with nothing removed and nothing made
conditional.

That last claim is **pinned by tests, not by a comment**: a cookie-authenticated
POST with no `Origin` and with a foreign `Origin` are both still
403 `origin_not_allowed`, and those two assertions passed *before* the change
and still pass after. The account and client kind are derived from the grant and
from nowhere else. Session-management routes stayed browser-only — a device
grant must never mint or end a browser session.

**The discriminator.** An outbox retries exact bytes, never re-serialized, so
after a relaunch the bytes are the only thing left to route by; an online client
posts to a typed endpoint and needs nothing. `type` is therefore an optional
field the server *verifies against the endpoint and never routes on*, refusing a
disagreement rather than guessing, then stripping the key so every decoder keeps
its exact-key discipline.

**The lane.** `test/real-stack/real-stack-sync.spec.ts` launches the packaged
`.app` from the manifest with `KEEPLING_TEST_SYNC_MODE` deliberately unset, so
the real `KeeplingSyncAdapter` runs. It authorizes through the real device-grant
path — the app builds the URL and hands it to `shell.openExternal`; the test
plays only the system-browser half and feeds the real
`keepling://auth/callback` back through the app's own `open-url` handler —
captures while the server is unreachable, proves **the server itself** has no
such mutation (404, not merely "the client did not say Synced"), reconnects, and
reaches Synced. The exact bytes are compared against what the server *received*,
recorded by the forwarding proxy, not against the client's own claim. Both
titles are read back out of real PostgreSQL through `/api/v1/inbox`.

The namespace check is real rather than nominal: the client configured
`http://127.0.0.1:4103`, and the origin it ends up holding is
`http://localhost:4102` — the value the **server** supplied. Deliberately
different, so a client that derived its own namespace would fail here.

**Outcomes observed: `accepted` only.** This lane deliberately does not
construct a conflict or rejection. `mapAcknowledgement` throws on the `conflict`
and `rejected` the contract declares (O-38), and building a case that trips it
would report someone else's defect as this lane's failure. **This lane does not
prove conflict reconciliation and does not claim to.**

## Task 3 — the gate

New `real-stack-sync` lane, with a parse that needs a positive case count **and**
a positive settled-mutation count **and** a proven exact-bytes retry, so a green
run that settled nothing fails. It runs headless — unlike the two Playwright
lanes, which are forced windowed because they assert real presentation; this
one asserts bytes on a socket and rows in PostgreSQL, where a window costs time
and proves nothing.

Its runner refuses the lane if `KEEPLING_TEST_SYNC_MODE` appears in the spec or
the environment, if a stubbed `fetch` or a `.invalid` host appears, if the shared
harness import disappears, or if the evidence line is missing. A name is not
allowed to be the evidence again.

### Placement — a deliberate deviation from the plan's stated path

The plan named `apps/desktop/test/packaged/real-stack-sync.spec.ts` and
explicitly delegated the project decision. The lane lives in its own directory
and its own Playwright project instead, because it is the only packaged lane
needing Elixir and PostgreSQL: folding it into `packaged` would make every other
packaged spec unrunnable without that toolchain and would hide its case count
inside another lane's, so a real-stack run that executed zero cases would be
invisible. Keeping it out of `test/packaged` also keeps
`smoke-desktop-packaged.mjs`'s "every file here is a packaged spec" rule true
rather than teaching it an exception list — which is how a spec stops being run
without anyone noticing.

### Disposition of the misleadingly-named spec

`test/e2e/real-stack-sync.spec.ts` → `test/e2e/fixture-server-sync.spec.ts`,
**renamed and kept**. It never had a real stack; its name alone got MAC-03
checked on a false citation and unchecked hours later. It is kept because what it
actually does is valuable and is *not* covered by the real lane — PKCE state
matching, an unsolicited callback from a competing app, single-use codes, refresh
rotation, detected refresh replay, sign-out fencing order, and a hostile server
answering with someone else's mutation identity. Several of those cannot be
induced against an honest real server, which is what a contract-faithful fixture
is for. The D-48 registry follows the rename and gains a `real-server` category.

## Non-vacuity, measured

The lane failed four times during construction, each for a different real
reason: PostgreSQL's 103-byte Unix-socket path limit, the packaged app sending a
body with no `version`, a stale Settings pane, and a real race in
`handleCallback`. Then a deliberate mutation — pointing the app at a port with
nothing listening — **makes the lane fail**. The spec was restored
byte-identically afterwards (`git status` clean, no diff).

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 2 — missing critical functionality] `client_kind` hardcoded `"web"`**
- **Found during:** Task 2, reading `CommandController.context/1`.
- **Issue:** every mutation was recorded as a browser mutation regardless of
  credential, so a Mac capture would appear as a web capture in the user's own
  activity feed.
- **Fix:** derived from the authenticating credential; `authenticate_access` now
  returns the grant's `client_kind`.
- **Commit:** `468f940`

**2. [Rule 1 — bug] the desktop's durable command bytes omit `version`**
- **Found during:** Task 2, first real push.
- **Fix:** serialize the contract body; `NodeSqliteLocalStore` now also refuses
  bytes without `version`, so bytes a server will refuse cannot reach the outbox
  at all. Five fixtures and one pinned fingerprint updated to the real shape
  rather than leaving the validator lax to accommodate them.
- **Commit:** `54ab80a`

**3. [Rule 1 — bug] the real-stack lane read account state once and flaked**
- **Fix:** polled to a bounded deadline, reporting the last observation.
- **Commit:** `8cea811`

### Scope deviations

- **Placement of the lane** — see above.
- **The rename** of the fixture spec, which the plan asked to be explicit about.
- **The contract gained an optional `type` discriminator.** This was not in the
  plan. It was forced by the collision between "exact bytes are retried, never
  re-serialized" and a body shape with no room to say what it is. The
  alternative — a local-store schema migration to carry the command type in a
  column — would have required rewriting a checksum-guarded single-migration
  runner, which is a larger and less reversible change.

### Checkpoint

One Rule 4 checkpoint was raised and answered mid-plan (O-37 → D-49), which is
why the server, the contract, and the context derivation are in scope at all.

## Known gaps and open items

- **O-38 (not mine, live now).** `mapAcknowledgement` throws on the `conflict`
  and `rejected` outcomes the server emits and the contract publishes. Latent
  until a packaged path reached a real server; closing O-34/O-37 makes it live.
  Deliberately not touched: widening the validator without building the conflict
  presentation path would convert a loud failure into a silent one. Mirrored into
  `open_items`, since it had been filed in prose only.
- **O-39 (new).** Settings shows a stale account state after the sign-in callback
  lands. The sign-in fully succeeds; only the pane is stale. The lane reloads the
  renderer — a read, not a nudge — and says so at the call site.
- **O-40 (new).** The packaged application digest is not reproducible across
  invocations at one revision; three different digests were observed at
  `fc3ac82` with a clean tree. This matters because the macOS evidence reuse is
  bound to that digest, and it cost two extra 160-second row runs in this
  session. Recorded with an explicit warning **not** to fix it by loosening the
  binding.
- **A3/A8 flakes observed.** Each failed once and passed on re-run and in the
  recorded full pass. Inside the previously measured <2%-per-row bound; left to
  the lane that owns them, per direction.
- **Edits still never reach the server.** `editTask`/`applyLifecycle`/`moveToday`
  update the local projection only and enqueue nothing, so `capture_task` is the
  only command type that can reach the wire today. Not a regression and not in
  scope; noted because "the Mac app syncs" is now true only for captures.
- Signed/notarized credential continuity remains explicitly deferred and unproven.

## Verification

```
Desktop phase gate summary: lanes=10 failed=0
  PASS typecheck-desktop cases=1 duration_ms=1152
  PASS typecheck-web cases=1 duration_ms=1867
  PASS unit-pure-vector-store-worker-performance cases=172 duration_ms=1139
  PASS ipc-hostile-bridge cases=66 duration_ms=656
  PASS electron-e2e cases=62 duration_ms=53343
  PASS package-once cases=1 duration_ms=12436
  PASS packaged cases=10 duration_ms=7817
  PASS real-stack-sync cases=1 duration_ms=5528
  PASS macos-integration cases=92 duration_ms=251
  PASS privacy cases=1 duration_ms=19
Desktop phase gate: PASSED
```

Also run:

```
Desktop real-stack lane passed: cases=1 synced=2 exact_bytes=1 outcomes=accepted
  server_origin=http://localhost:4102
  digest=3631df5f4ed97ecc5c3563a9508537990d3ebf678a6e0cc9905d5b2732714146

macOS integration lane summary: rows=15 failed=0 cases=92 duration_ms=160399
macOS integration lane: PASSED cases=92   (SETTINGS restore=VERIFIED)

apps/server: 188 passed (1 property, 187 tests)
pnpm contracts:check: passed
pnpm test:desktop: 172 passed
keyboard-quick-entry (windowed): 7 passed
```

The environment caveat recorded elsewhere in this project does **not** apply:
PostgreSQL 18.6 and Phoenix both start cleanly on this machine. There was no
`shmget` failure at any point.

## Self-Check: PASSED

All created files exist on disk; all twelve commit hashes resolve in
`git log`; the gate summary above is a verbatim copy of a run executed after the
final code commit.
