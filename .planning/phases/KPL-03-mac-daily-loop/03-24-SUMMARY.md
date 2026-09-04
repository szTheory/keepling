---
phase: KPL-03-mac-daily-loop
plan: 24
subsystem: desktop-store
tags: [sqlite, migration, outbox, undo, sync, gap-closure, o-51, d-52]
status: complete

requires:
  - phase: KPL-03-mac-daily-loop
    provides: "03-22's resource-key ordering and terminal command outcomes"
  - phase: KPL-03-mac-daily-loop
    provides: "03-23's retained server-issued undo handles and the undo_unavailable presentation"
  - phase: KPL-03-mac-daily-loop
    provides: "03-12/03-15's packaged, real-stack and macOS integration lanes"
provides:
  - "A generalised migration runner: an ordered contiguous set, the D-37 checksum binding kept per version, and a refusal to open a database migrated by a newer build"
  - "migrations/0002_outbox_state.sql: explicit outbox transmission state (queued | in_flight | uncertain)"
  - "beginTransmission / abandonTransmission / undoUnsentLocalAction on the store, routed through the worker protocol and the main proxy"
  - "Undo of a never-transmitted mutation drops the command and reverts locally; an in-flight or uncertain one is refused"
  - "A gate that can HOLD a real server answer, so the undo-versus-in-flight race is proved against real Phoenix"
affects: [MAC-01, MAC-03, O-51, O-47 (reported, not decided)]

actuals:
  tokens: 96000
  tasks: 3
  commits: 9

tech-stack:
  added: []
  patterns:
    - "Monotonic durable state as a safety proof: a row that leaves `queued` never returns, so 'never transmitted' is a fact the store can prove rather than infer"
    - "Ambiguity resolves to refusal, never to the convenient answer: a failed fetch cannot say whether bytes left, so it yields `uncertain`, not `queued`"
    - "Hold the ANSWER, not the request: a forwarding proxy that delivers real bytes to the real server and withholds only the response reproduces a genuine in-flight window with no stubbing"

key-files:
  created:
    - apps/desktop/migrations/0002_outbox_state.sql
    - apps/desktop/test/store/outbox-state-migration.test.ts
    - apps/desktop/test/store/outbox-transmission.test.ts
  modified:
    - apps/desktop/store-worker/local-store.ts
    - apps/desktop/store-worker/index.ts
    - apps/desktop/main/index.ts
    - apps/desktop/main/application/DesktopApplication.ts
    - apps/desktop/main/application/presentation.ts
    - apps/desktop/preload/contracts.ts
    - apps/desktop/renderer/desktopClientFacade.ts
    - apps/desktop/test/e2e/daily-loop.spec.ts
    - apps/desktop/test/e2e/fixture-server-sync.spec.ts
    - apps/desktop/test/packaged/daily-loop.spec.ts
    - apps/desktop/test/real-stack/real-stack-sync.spec.ts
    - apps/desktop/test/store/migrations-faults.test.ts
    - apps/desktop/test/application/undo-reconciliation.test.ts
    - apps/desktop/test/application/sync-vectors.test.ts
    - apps/desktop/test/application/sync-presentation.test.ts
    - apps/desktop/test/application/conflict-presentation.test.ts
    - tooling/verify-macos-integration.mjs
    - tooling/verify-real-stack-desktop.mjs
    - .planning/HANDOFF.json

key-decisions:
  - "A transport failure returns a row to `uncertain`, NOT to `queued` as the plan text said. The plan's own prohibition governs: a failed fetch cannot distinguish 'never left' from 'left and the answer was lost', so returning to a droppable state would reopen the divergence by another route."
  - "Rows that predate the state column migrate to `uncertain`, not to the column default `queued`: a client that recorded no transmission state left no history, and absent state is ambiguous state."
  - "An interrupted transmission is PROMOTED to `uncertain` at the next open, never reset. Retransmitting the same immutable bytes is safe under the server's idempotency; dropping them is not."
  - "The durable `uncertain` state is NOT the presentation `{ kind: 'uncertain' }` (O-47). The variant is still unconstructed and O-47 is still open; constructing it needs the transport to report whether the request body was flushed, which this plan had no authority to decide."
  - "A store that cannot record transmission state stops the push outright, rather than pushing without marking."
  - "A refusal because a command may already be in flight gets its own copy rather than reusing the `unsent` copy, which would assert knowledge this client does not have."
  - "The dropped command's rows are deleted outright (outbox, journal, dependencies, immutable command), because bytes that never left have no counterpart to reconcile against and a permanently `pending` journal row would describe a command nothing can settle."

patterns-established:
  - "When a plan's prose and its own prohibitions disagree, the prohibition wins and the disagreement is reported rather than silently resolved"
  - "Prove a durable migration with the SHIPPED artifact opening a database built at the older schema, not with a unit test of the runner alone"
---

# Phase KPL-03 Plan 24: Undo Without a Server, Without a Divergence Window Summary

Undo works again on a Mac with no server, and it is safe because the outbox
can now prove a command's bytes were never transmitted — explicit
`queued | in_flight | uncertain` state behind a generalised migration runner,
with the drop refused for anything the server might already hold.

## What Was Built

**Task 1 — the migration runner.** `#applyMigration` was hardcoded to version
1. It now applies an ordered, contiguous set, keeping the D-37 checksum
binding per version: a recorded checksum that disagrees with the file still
fails loudly and the store does not open. `migrationPath` still names the
initial schema (every caller passes that, and the fault suite proves drift by
pointing it at a corrupted copy in a temporary directory); later migrations
are its siblings, ordered by the version in their names, with the explicitly
named file authoritative for its own version. Two additions the
generalisation made necessary: the set must be contiguous from 1, and a
ledger version this build carries no migration for is refused — checked after
the known set validates, so a drifted file still reports drift rather than
"newer database".

`0002_outbox_state.sql` adds `outbox.state` by `ALTER`, never by dropping and
recreating.

**Task 2 — the state machine and the undo.** `beginTransmission` marks a row
in flight in the instant before its bytes are handed to the transport;
`abandonTransmission` releases it to `uncertain`; an interrupted transmission
is promoted to `uncertain` at the next open. `readyMutations` withholds a live
request. `undoUnsentLocalAction` drops the command only when its state is
`queued` and no later queued command shares its resource key, in the same
transaction that reverts the projection. `DesktopApplication` asks the store
and acts on the answer; it never infers from the outbox's contents. The three
routes are forwarded through the worker protocol and the main proxy, and the
new `in_flight` refusal reaches a person through the preload contract and the
renderer facade as well as the status row.

**Task 3 — the proofs.** Listed below under Verification.

## The State Vocabulary, and Why

- **`queued`** — bytes never handed to the transport. The only droppable state.
- **`in_flight`** — handed over in this process, no outcome yet. Not droppable,
  and withheld from the ready set so one request cannot be posted twice.
- **`uncertain`** — handed over, no outcome ever arrived. Not droppable, still
  pushable: retransmitting the same immutable bytes under the same mutation
  identity and fingerprint is exactly what the server's idempotency is for,
  and it answers `already_satisfied` if the first attempt landed.

The transitions are **monotonic**: a row that leaves `queued` never returns.
That one-way rule is what makes the drop provably safe rather than probably
safe.

**A crash is not a reset.** An `in_flight` row found at startup is promoted to
`uncertain`, never returned to `queued`. The client genuinely does not know
whether those bytes reached the server, and resetting would silently make a
possibly-transmitted command droppable again on every crash. The recovery is
scoped to schema version 2 or above and reads before it writes, so opening a
read-only database with nothing in flight still succeeds and still fails only
on write (D-22/D-38); when something *is* in flight and the file cannot be
written, the open fails loudly instead.

## Two Places the Plan and the Artifacts Disagreed

Reported rather than silently resolved, per the plan's own instruction.

**1. "returns to `queued` on a TRANSPORT failure" (design guidance) versus
"Absent or ambiguous state is a REFUSAL, never an assumed 'queued'"
(prohibition).** These contradict each other. A transport failure is exactly
the ambiguous case: `fetch` rejecting cannot distinguish "the request never
left" from "it left and the answer was lost" — which is O-47's own finding,
recorded in this repository. Returning the row to `queued` would make it
droppable again and reopen the divergence by another route. **The prohibition
wins**: a transport failure yields `uncertain`. The row is still pushed, so
nothing is stranded; only the undo refuses it.

**2. The plan's `queued | in_flight` two-state vocabulary is not sufficient.**
With only two states, either an interrupted `in_flight` row is reset to
`queued` (unsafe) or it is never pushed again (a permanent stall for a
person's real work). The third state resolves both.

## O-47: named explicitly, not wired silently

This plan constructs a durable state it calls `uncertain`, and that is
**adjacent to but not the same thing as** the presentation variant
`{ kind: 'uncertain' }` that O-47 reports as unconstructed. The durable state
is the fact ("this command's bytes were handed over and no answer came
back"); the presentation variant is a claim to a person about a specific
change, with a Check Again action. **The variant is still unconstructed and
O-47 is still open.** It was not wired here, deliberately: constructing it
honestly needs the transport to report whether the request body was flushed,
which is a decision this plan did not carry.

That transport work is also the natural next step for a related limit found
here: a connection **refused** provably never transmitted anything, but the
adapter reports it identically to a socket error after the body was sent, so
undo refuses both. Refusing is safe, and no correctness claim depends on
narrowing it.

O-43 and O-46 were not touched and are unchanged.

## Verification

Every lane below was run at this revision.

```
Desktop phase gate summary: lanes=10 failed=0
  PASS typecheck-desktop cases=1 duration_ms=1010
  PASS typecheck-web cases=1 duration_ms=1645
  PASS unit-pure-vector-store-worker-performance cases=297 duration_ms=1070
  PASS ipc-hostile-bridge cases=75 duration_ms=652
  PASS electron-e2e cases=66 duration_ms=55558
  PASS package-once cases=1 duration_ms=12311
  PASS packaged cases=11 duration_ms=8306
  PASS real-stack-sync cases=5 duration_ms=19418
  PASS macos-integration cases=93 duration_ms=249
  PASS privacy cases=1 duration_ms=19
Desktop phase gate: PASSED
```

**The riskiest truth — an existing database opens, migrates, and keeps both
its tasks and its queued commands — is proved by the SHIPPED artifact.** The
packaged lane (11 cases, up from 10) seeds a genuine pre-0002 database, built
by the same store code against a migrations directory holding only 0001, with
a task and a queued command. The packaged Keepling opens it: the ledger reads
`[1, 2]`, the task is on screen, the store is still writable, the queued
command survives with its exact bytes, and it is `uncertain` while the command
captured after the migration is `queued`. Four unit cases cover the same
lineage plus per-version checksum drift and the newer-database refusal.

**The dangerous case is proved against real behaviour, not a branch.** The
real-stack lane's forwarding proxy can now hold an *answer*: the request goes
to real Phoenix, which really applies it, and only the response is withheld.
No fetch is stubbed and `KEEPLING_TEST_SYNC_MODE` is absent.

```
REAL_STACK_IN_FLIGHT held=1 refused=1 command_survived=1 server_holds_completion=1
REAL_STACK_UNDO handle=server_issued undo_arrived=1 reverted_on_server=1 survived_relaunch=1 dropped_never_transmitted=1 never_reached_server=1
Desktop real-stack lane passed: cases=5 synced=2 exact_bytes=1 outcomes=accepted,conflict server_origin=http://localhost:4102 command_types=8 conflicts=1 undo=1
```

With a `complete_task` genuinely on the wire — the client's own outbox row
reads `in_flight` and the proxy has seen the exact bytes arrive — the undo is
refused, the command survives with the same bytes, nothing is queued behind
it, and releasing the answer settles it with the server holding the
completion. That last fact is the proof the bytes really had left, and
therefore that dropping them would have deleted a change the server accepted.
The other half is checked the same way: with the server unreachable the pass
fails at the *pull*, nothing is transmitted, the undo drops the command — and
when the network returns the server never receives that completion.

**MAC-01's promise is back on a real Mac.** macOS row A5 (packaged app, no
server configured, real CGEvent keystrokes) now asserts that Command-Z
reverses the restore and that nothing claims a refusal, read from the live
AXUIElement tree. `rows=15 failed=0 cases=93`, re-recorded against
`applicationDigestSha256=8058ed13b8b4d96897e159b369e771e8ff654313765b82772ad931eff9e5a3d3`.
The digest was stable across this session's packaging runs, so O-40 did not
bite; the binding was not loosened and O-40 stays open.

## Deviations from Plan

### Scope beyond `files_modified`

The plan listed five files. These were also required, none optional:

- `store-worker/index.ts` and `main/index.ts` — without the worker routes and
  the proxy methods the shipped app would run the state machine in a store
  the main process cannot reach, which is the O-16 defect class exactly.
- `preload/contracts.ts` and `renderer/desktopClientFacade.ts` — the new
  refusal reason would have been rejected by the preload schema, and the
  facade would have shown "Nothing to undo." for it.
- `presentation.ts` — the refusal needed authored copy.
- Six test files, `verify-macos-integration.mjs` and
  `verify-real-stack-desktop.mjs` — the behaviour they asserted changed.

### [Rule 1 — Bug] A vacuous assertion in the E2E undo test

`test/e2e/daily-loop.spec.ts` polled
`getByRole('button', { name: 'Complete' }).count()`. Playwright matches an
accessible name by **substring** by default, so the "Undo Complete" button the
test had just clicked satisfied the assertion — the test could not fail. Fixed
with `exact: true` throughout. The trap is specific to `.count()`, which is
non-strict; a `click()` or `toBeVisible()` on a two-match locator raises a
strict-mode violation instead. That was the only `.count()` use in the desktop
suite; there are now none.

### [Rule 1 — Bug] The same test waited for something that could never arrive

It expected an undo capability to be issued in-session under
`KEEPLING_TEST_SYNC_MODE=acknowledge`, but with no configured adapter
`scheduleSyncPass` returns immediately, so no acknowledgement — and no
capability — could ever arrive. It now acknowledges through a relaunch's
bootstrap reconcile, waits for the retained capability, asserts nothing is
queued (so a local drop is impossible and only the handle path remains),
drives the undo with Command-Z (the "Undo Complete" button is a session-local
affordance and the action happened in the previous session), and asserts a
real `undo_task` command is queued afterwards.

### [Rule 2 — Missing critical functionality] Two additions to the runner

Contiguity and the newer-database refusal are not in the plan text. A gap in
the set produces a schema no version number describes; an older binary
writing a database a newer schema governs is a durability hazard. Both fail
loudly.

## Known Limits

- **A refusal the store classifies as `unknown` shows the `unsent` copy.**
  That is unchanged shipped behaviour, and it is imprecise for one case: a
  command the server settled without issuing a capability (a `capture_task`,
  say) has reached the server, and "This change hasn't reached the server
  yet" is then untrue. Not corrected here because doing so is a copy decision
  beyond this plan; filed as O-54.
- **A connection refused is treated as ambiguous** rather than as proof the
  bytes never left. Safe, and narrowing it is O-47's transport work.
- **The `blocked` refusal is hard to reach in ordinary use**, because
  `last_local_action` always names the most recent command for that task. It
  is proved at the store boundary via `acceptMutation` and kept as an
  invariant rather than removed.

## What I Could Not Exercise

- **A real process crash mid-POST.** The recovery is proved by closing the
  store with a row left `in_flight` and reopening it, which is the same
  durable situation, but no test kills the process during a live request.
- **A real pre-0002 database from an earlier shipped build.** The fixtures
  build one with the current store code at the older schema; nobody has a
  Keepling profile predating this work.
- **A person's judgement of the new copy.** Automated lanes assert the exact
  strings; whether "on its way to the server" reads well is not something a
  test can tell you.
- **The digest instability of O-40.** It did not reproduce this session
  (packaging was stable across runs), so nothing new was learned about it.

## Self-Check: PASSED
