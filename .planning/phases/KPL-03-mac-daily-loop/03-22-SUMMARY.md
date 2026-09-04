---
phase: KPL-03-mac-daily-loop
plan: 22
subsystem: desktop-sync-seam
tags: [gap-closure, sync, conflict, recovery-actions, utility-windows, real-stack]
status: complete
requires:
  - 03-19 (O-30 closed; the offline row is real and the main window renders copy)
  - 03-21 (the packaged app reaches real Phoenix on real PostgreSQL)
provides:
  - every task mutation a person can perform reaching a real server
  - a client that can hear a conflict the real server raises
  - recovery actions that are remedies rather than labels
  - the synchronization row in the Quick Entry and Settings windows
  - a synchronization pass that retries on its own after a reconnect
affects:
  - apps/desktop (application, adapters, store worker, preload, renderer)
  - tooling (real-stack runner and desktop phase gate parsers)
tech-stack:
  added: []
  patterns:
    - one durable enqueue, in the same transaction as the local projection write
    - ordering by resource key rather than by journal dependency, so no outcome can strand a chain
    - a closed list of server refusals the client may settle; everything else stays loud
    - command shapes asserted against the checked-in contract, not against a fixture
key-files:
  created:
    - apps/desktop/main/application/outbound-commands.ts
    - apps/desktop/main/adapters/server-refusal.ts
    - apps/desktop/renderer/UtilitySyncStatusRow.tsx
    - apps/desktop/test/application/outbound-commands.test.ts
    - apps/desktop/test/application/server-refusal.test.ts
    - apps/desktop/test/application/conflict-presentation.test.ts
    - apps/desktop/test/store/outbound-mutations.test.ts
    - apps/desktop/test/renderer/sync-status-row.test.tsx
  modified:
    - apps/desktop/main/application/DesktopApplication.ts
    - apps/desktop/main/application/sync-reachability.ts
    - apps/desktop/main/adapters/sync.ts
    - apps/desktop/main/index.ts
    - apps/desktop/main/windows/quick-entry-window.ts
    - apps/desktop/store-worker/{index.ts,local-store.ts}
    - apps/desktop/preload/{contracts.ts,index.ts,utility-preload.ts}
    - apps/desktop/renderer/{SyncStatusRow.tsx,quick-entry.tsx,settings.tsx}
    - apps/desktop/test/{e2e/gap-closure.spec.ts,ipc/hostile-bridge.test.ts,real-stack/real-stack-sync.spec.ts}
    - tooling/{verify-real-stack-desktop.mjs,verify-desktop-phase.mjs}
decisions:
  - ordering is enforced by resource key, never by journal dependency, because a dependency only clears on an accepted outcome and would strand a task's chain forever once conflicts became reachable
  - the adapter settles a CLOSED list of server refusals (four 409 conflict codes, 422, invalid_command, task_not_found); a 401 is tagged separately and never collapsed into a per-mutation rejection
  - `CommandAcknowledgement.outcome` stays strict at accepted/already_satisfied, because that is what the contract publishes; a conflict arrives as a 409 problem, not as a 200
  - a refusal never overwrites the local row or replays the canonical shadow over it
  - the utility bridge carries copy only -- no recovery action, no write capability
metrics:
  duration: ~4h
  completed: 2026-09-04
actuals:
  tokens: 91000
  tasks: 4
  commits: 11
---

# Phase KPL-03 Plan 22: Carry Every Mutation, and Hear a Conflict Summary

Completing, reopening, trashing, restoring, retitling and moving to Today now
reach a real server and reconcile against it; a conflict that real server
raises reaches a person as conflict copy with a live remedy; and the Quick
Entry window finally says when it is offline.

## The plan's premise for Task 2 was wrong in one load-bearing detail

The plan said `mapAcknowledgement` "accepts only `accepted`/`already_satisfied`
and throws on the `conflict` and `rejected` the contract publishes
(keepling.yaml:1392)". Reading the contract and the server together, that is
not the shape:

- `CommandAcknowledgement.outcome` publishes **exactly** `accepted` and
  `already_satisfied`. A 200 body claiming `conflict` genuinely IS an invalid
  acknowledgement, and `mapAcknowledgement` is right to refuse it. The
  `conflict`/`rejected` at line 1392 are `MutationTrustState` — a **client**
  vocabulary, not an acknowledgement outcome.
- The real server answers a conflict with **HTTP 409 and an RFC 9457 problem**
  (`CommandStore#semantic_rejection`), persisting it
  (`persist_command_conflict`), and answers a semantic refusal with 422.

So the defect was real and **worse than filed**. `#json` threw a plain `Error`
for every non-OK status, `runSyncPass` caught it, and a 409 landed on
*"Couldn't reach the server. Your changes stay on this Mac."* with a Retry
button that would retry, forever, a command the server had already decided
about. Not merely unheard — **misheard, as a transport failure.**

I did **not** widen `mapAcknowledgement`. Widening it would have made a genuine
contract violation silent, which is the exact trade the plan's prohibition
forbids. The classification happens where the status code lives, in the
transport, and `mapAcknowledgement` stays strict — pinned by a test that a 200
claiming `conflict` is still refused loudly.

## Task 1 — O-41: every mutation reaches the wire

`type: 'capture_task'` really was the only command desktop production code
could construct. `editTask`, `applyLifecycle` and `moveToday` wrote the local
projection and enqueued nothing.

**Following the capture path, not inventing a second mechanism.**
`outbound-commands.ts` is a pure builder for the other seven command types. Its
bytes are the contract's request body for the endpoint they will be posted to,
plus the optional `type` discriminator, `version: 1` present. Every shape is
asserted against `packages/contracts/openapi/keepling.yaml` **itself** —
required fields present *and* no extra key, because the server decoders compare
the exact key set — rather than against a hand-copied list. That is the O-34
`version` omission made structurally unrepeatable.

**Atomicity.** The outbox insert joins the same `BEGIN IMMEDIATE` as the
projection write, and the worker request carries both halves in one message.
Two transactions in a row would leave a crash window between telling a person
their change is safe and recording the intent to send it.

### Ordering — how it is handled, and how it is proved

**The mechanism:** every command carries the single resource key
`task:<id>`, and `readyMutations` already excluded any mutation sharing a
resource key with an **earlier** outbox entry. So while a capture sits in the
outbox, an edit of the same task is durable but not pushable.

**Why not a journal dependency.** `mutation_dependencies` would also block, but
it only unblocks on an `accepted`/`already_satisfied` outcome. The moment
Task 2 made conflicts reachable, a conflicted capture would have stranded every
later mutation on that task in the outbox forever, reported as "Saved on this
Mac", with nothing able to settle it. The resource key has no such stuck state:
the earlier entry leaves the outbox on **any** terminal outcome. `dependencies`
is deliberately empty and the reason is written at the construction site.

**Proved three ways, not asserted:**

1. `test/store/outbound-mutations.test.ts` — both are queued, only the capture
   is ready; the edit becomes ready only once the capture leaves the outbox.
   Deleting the resource-key filter makes exactly those two cases fail
   (verified by deliberate mutation).
2. The same file proves a chain of three holds its order and that mutations on
   *different* tasks still flush in one pass — so the rule is not just "nothing
   ever ships".
3. The real-stack lane asserts the **arrival order at the server**:
   `['capture_task', 'edit_task']`, read from the forwarding proxy's record of
   what the server received, not from the client's outbox — which is the thing
   under test.

**The basis chain.** `taskSyncBasis` rebases each queued command on the effect
of the previous queued one, falling back to the canonical shadow, so two
offline edits do not send the same stale base twice and get reported as a
conflict against a value this client itself just supplied. Each effect records
`expectedRevision + 1`, because that is what the server produces on acceptance
— without it, two commands queued before the first is acknowledged both claim
the same revision and `trash_task`/`restore_task`, which the server compares
exactly, are refused on the second.

## Task 2 — O-38: hearing a conflict, both halves

**(a)** The adapter classifies what the server answered, from a **closed** list:
the four 409 conflict codes, every 422, and `invalid_command` / `task_not_found`.
Everything else — 403, 5xx, malformed bodies — still throws and still lands on
the retryable-failure row.

A **401 is tagged separately** and never becomes a per-mutation rejection.
Every authentication problem the server emits carries `retryable: false`, so a
rule keyed on that field alone would have silently discarded a whole outbox as
"the server didn't accept these changes" when the truth is "sign in again".
This is Rule 2: `{ kind: 'authentication_required' }` previously had only the
failed-callback construction site, and now has one on the pass itself.

**(b)** `{ kind: 'conflict' }` and `{ kind: 'rejected' }` are constructed in
`runSyncPass` and reach the window with their authored copy and action. A
conflict outranks a rejection outranks a pending row, because a conflict is the
only one that needs a *choice*.

**What a refusal does to the local row.** The store no longer writes the
canonical shadow from a refusal (a 409 carries only the affected fields;
writing it would blank everything unmentioned, and `#upsertProjection` would
then display the task's identifier as its title), and no longer replays the
shadow over the projection after one (which would erase the person's edit while
telling them "Your version is still on this Mac").

## Task 3 — O-42: every action is a remedy

Every code now does something real, and TypeScript exhaustiveness makes adding
a code without an effect a **compile error** rather than another dead button.
Two capabilities had to be built because none existed:

- **`retrySync`.** `scheduleSyncPass` is fire-and-forget and swallows its own
  failure — right for an automatic trigger, wrong for a button someone just
  pressed. This awaits the pass and reports, sharing the in-flight guard.
- **`exportLocalData`.** `namespace_mismatch` offers Inspect / Export / "Remove
  data from this Mac…" side by side, and Export was a label no surface read —
  so the only live-looking way out of a fenced namespace was the one that
  DELETES, with no way to take the data first. For a project whose core value
  is that accepted changes are never silently lost, that is a data-safety
  defect. It writes tasks **and the unsent commands** to a main-owned path.

Neither takes an argument: a renderer cannot aim a push or direct a write. The
row is still not a live region. Removal is still never confirmed from a single
press.

The renderer test derives its action list by running the **shipped**
`deriveDesktopPresentation`, so an action added tomorrow is covered the moment
it exists rather than the day someone remembers to extend a list. Removing the
action rendering makes 15 of its 17 cases fail.

## Task 4 — O-31(a): the utility windows

Quick Entry and Settings load `preload/utility-preload.ts`; `window.keepling`
and `subscribePresentation` do not exist in their JS context, which the e2e
case asserts before anything else. This is a new schema-validated channel plus
publisher wiring, following the main bridge's pattern exactly: listener
registered at module load, same strict schema, same D-29 sequence contract with
a gap closed by refetching.

Copy only, verbatim, **no** recovery action and no write capability — the
remedies act on the main window's Sync & Recovery region, which does not exist
in a utility window. Pinned by a test. `assertTrustedUtilitySender` is disjoint
from the main window's, so a utility window can never become a second sender
for the task-mutation surface; the static handler scan enforces the pairing
both ways.

`apps/web` is out of scope, as the plan directed.

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 2 — missing critical functionality] a reconnected app never synced**
- **Found during:** Task 1, running the real-stack lane end to end.
- **Issue:** `computeSyncBackoff` was defined, exported, and called from
  **nowhere** — not production, not a test. Same complete-but-unreachable shape
  as O-9/O-12/O-16/O-30/O-41/O-42. A pass ran only when a person made another
  change, so an app that went offline, queued work and came back online sat
  there showing "Saved on this Mac" until they happened to type something.
  MAC-03 says a mutation is made and *later reconciled*.
- **Fix:** a bounded, unref'd, single-timer backoff retry driven by the
  **outbox**, not the pass's return value; reset on a clean pass; cancelled on
  quit; and reset by a Retry press, which means *now*.
- **Commit:** `b35e97c`

**2. [Rule 1 — bug] a refusal erased the person's local change**
- **Found during:** Task 2, first store test of the rejected path.
- **Issue:** `acknowledge` replayed the canonical shadow after every outcome,
  so a rejected edit reverted on screen while the copy said "Your version is
  still on this Mac."
- **Fix:** replay only on an accepted outcome. See the known limit below.
- **Commit:** `4bd8241`

### Scope deviations

- **`main/windows/quick-entry-window.ts`** gained a `getWindow()` accessor (not
  in `files_modified`), mirroring `SettingsWindowController`, because the
  publisher and the trust check both need the live WebContents.
- **`preload/index.ts`, `renderer/settings.tsx`, `test/e2e/gap-closure.spec.ts`,
  `test/ipc/hostile-bridge.test.ts`** were also modified. The first two are the
  other ends of channels the plan did name; the two test files are pins that
  correctly caught the new surface (the bridge key list, the trust-helper
  pairing, the trigger-site count).
- **`tooling/verify-real-stack-desktop.mjs` and `tooling/verify-desktop-phase.mjs`**
  were strengthened so a run that only ever captured, or never heard a
  conflict, fails. Without that the new lane could go quiet and stay green.

### No checkpoints

None were raised. The one place I considered stopping — the plan's incorrect
description of where `conflict` lives — is a correction to a mechanism, not to
the intent or the evidence path, so it is reported here rather than escalated.

## Known Stubs

None. No hardcoded empty value, placeholder string, or unwired component was
introduced.

## Known limits, reported rather than papered over

1. **A refused local change has no durable home.** Not replaying the shadow
   keeps the person's version on screen immediately after a refusal, which is
   what the copy promises — but the refused command is terminal and gone from
   the outbox, so the **next pull replaces it**. Giving a refused change a
   durable home is a product decision this plan had no authority to make.
   Filed as **O-43**.
2. **The desktop's conflict chooser is title-only.** A mine/current record is
   written only when the server named a divergent `title`. A lifecycle or Trash
   conflict diverges on `completed_at`/`trashed_at`, and offering two
   timestamps under `ConflictResolver`'s "choose which title Keepling should
   keep" would be a lie in the UI. Those conflicts still reach a person as the
   `conflict` row, and `review_conflict` falls back to refreshing from the
   server — exactly the `refresh_task` recovery the server itself names.
   `apps/web` already has the multi-field resolver; the desktop does not.
   Filed as **O-44**.
3. **`undo` is the same defect class, still open.** `undoLastLocalAction`
   reverses a local edit and enqueues nothing, so an undo is invisible to the
   server. The contract's `undo_task` needs a server-issued `handle` from the
   acknowledgement's `undo` field, which the desktop does not retain. Filed as
   **O-45**.
4. **Offline plan-then-unplan of the same task will conflict.** The account day
   `plan_for_today` resolves is the server's; this client does not know it and
   must not invent one, so a queued plan leaves `planned_on` unknown and a
   following unplan sends a base the server has moved past. The server answers
   with a real conflict, which is now surfaced rather than swallowed.

## Reporting back on `preparing` and `uncertain` (as the plan asked)

Both are still declared with authored copy and **no production construction
site**, and I deliberately neither deleted nor speculatively wired them.

- **`preparing`** ("Preparing your tasks for offline use…") would be
  constructed by a first-run **bootstrap** — `KeeplingSyncAdapter.bootstrap()`
  exists, hits `/api/v1/sync/bootstrap`, and is called from nowhere. The real
  construction site is a first-pass-after-sign-in branch in `runSyncPass` that
  publishes `preparing` while the initial bootstrap page set is being applied.
  That is a behaviour change to first-run, not a wiring job.
- **`uncertain`** ("Checking whether this change was accepted…") with its
  `Check Again` action is the **in-doubt** state: a push whose answer never
  arrived, where the mutation may or may not have been accepted. Its real
  construction site is the `SyncUnreachableError` path **for a push that had
  already been sent** — distinguishing "never left" from "left, answer lost"
  requires the transport to report whether the request body was flushed, which
  it currently does not. `KeeplingSyncAdapter.lookup()` is the resolution
  (`Check Again` → re-read the receipt), and it is already wired for
  `reconcile()`.

Both need a recorded decision. Filed as **O-46** (`preparing`) and **O-47**
(`uncertain`).

## What the tests actually exercised — honestly

- **Outcomes observed against the REAL server:** `accepted` and `conflict`.
  `rejected` is **not** constructed in the real-stack lane and is not claimed
  there; it is proved exhaustively at the unit boundary against the server's
  own problem bodies (`server-refusal.test.ts`), and its presentation path is
  proved in `conflict-presentation.test.ts`. `already_satisfied` was not
  deliberately constructed anywhere.
- **Command types observed ARRIVING at the real server:** `capture_task`,
  `edit_task`, `complete_task`, `reopen_task`, `plan_for_today`,
  `unplan_task`, `trash_task`, `restore_task` — all eight, asserted by name.
  `move_today_task` (reordering inside Today) has no desktop surface and was
  not exercised. `clarify_task`, `return_to_inbox`, `edit_task_dates`,
  `undo_task` and the organization commands are not constructed by the desktop
  at all.
- **The conflict was produced by a real second writer** — a real browser client
  against the real server on its own port while the app's link was down — not
  by a fixture and not by `KEEPLING_TEST_SYNC_MODE`, which appears nowhere in
  the real-stack spec or its environment (the runner refuses the lane if it
  does).
- **Reconciliation was verified against the SERVER**, via `/api/v1/tasks/:id`,
  `/api/v1/trash`, `/api/v1/inbox` and the forwarding proxy's record of
  received bodies — never against the client's own row. The client's "Synced"
  label is used nowhere as evidence.
- **The `retry` action was proved against a real socket** (the server's request
  count moves on the press); `export` against a real file on disk. The other
  action codes are proved at the renderer boundary against the shipped
  presentation deriver, not end to end.
- **`check_again` has no production-reachable state** (it rides on `uncertain`,
  which is unconstructed), so it is handled but not exercised.
- **Signed/notarized credential continuity remains deferred and unproven.**
  Every packaged run launches an unsigned ad-hoc artifact.

## Non-vacuity, measured

Four deliberate mutations, each restored byte-identically afterwards
(`git status` clean):

| Mutation | Result |
|---|---|
| Drop `version` from lifecycle command bytes | 4 of 20 contract cases fail |
| Remove the resource-key filter in `readyMutations` | exactly the 2 ordering cases fail |
| Stop rendering `summary.actions` | 15 of 17 recovery cases fail |
| Change the expected conflict copy in the real-stack lane | lane fails, reporting the REAL copy it observed: "This task changed somewhere else. Choose what to keep. Other tasks can continue." |

The last one is the direct evidence that the packaged app, against real
Phoenix, really put that sentence on screen after a real second writer's
divergence.

A fifth attempt — disabling the 409 branch in `classifyServerRefusal` and
re-running the real-stack lane — **could not be performed**, and I am recording
that rather than implying it was: `package-desktop.mjs` refuses to package a
dirty tree ("package inputs must be committed before package-once records a
source revision"), so the mutated main bundle was never packaged and the lane
silently reused the previous artifact. The digest in that run is identical to
the previous one, which is how I caught it. Committing a deliberate defect to
run it was not worth the history.

## O-40 during this plan

Live and behaved exactly as recorded. The macOS lane refused reused evidence
for a new digest and the 15-row suite was re-recorded once
(`a67d50273bd2335a…`, 92 cases, 160.9s). The digest binding was **not**
loosened. Running `pnpm package:desktop && node tooling/verify-macos-integration.mjs --all`
and then the gate in the same shell held, as the O-40 workaround predicts.

## Verification

```
Desktop phase gate summary: lanes=10 failed=0
  PASS typecheck-desktop cases=1 duration_ms=1201
  PASS typecheck-web cases=1 duration_ms=2094
  PASS unit-pure-vector-store-worker-performance cases=251 duration_ms=1379
  PASS ipc-hostile-bridge cases=75 duration_ms=701
  PASS electron-e2e cases=65 duration_ms=57004
  PASS package-once cases=1 duration_ms=12883
  PASS packaged cases=10 duration_ms=8214
  PASS real-stack-sync cases=3 duration_ms=12061
  PASS macos-integration cases=92 duration_ms=254
  PASS privacy cases=1 duration_ms=17
Desktop phase gate: PASSED
```

`macos-integration` at 254ms against a 160,957ms real run is the proof of
evidence reuse for the artifact under test.

Also run:

```
Desktop real-stack lane passed: cases=3 synced=2 exact_bytes=1
  outcomes=accepted,conflict server_origin=http://localhost:4102
  command_types=8 conflicts=1
  digest=d5e6f47d0a65def2389c768bf59f9b99888bf444927cbc1f3872f19628d1eaa8

REAL_STACK_MUTATIONS command_types=capture_task,complete_task,edit_task,
  plan_for_today,reopen_task,restore_task,trash_task,unplan_task
  final_revision=8 outbox=0
REAL_STACK_CONFLICT ordering=capture_task,edit_task outcomes=conflict
  conflicts=1 second_writer=real

macOS integration lane summary: rows=15 failed=0 cases=92 duration_ms=160957
macOS integration lane: PASSED cases=92

pnpm test:desktop:     251 passed (was 172)
pnpm test:desktop:ipc:  75 passed (was 66)
pnpm test:desktop:e2e:  58 passed headless (65 windowed in the gate)
pnpm contracts:check:  passed
```

`final_revision=8` is the server's own count: one capture plus seven accepted
mutations. A client whose commands were refused would have left it at 1.

## Requirements

MAC-03 and MAC-04 are **not** checked here. Per O-17 that is the
orchestrator's, and per D-50 the evidence above is what they should be
re-derived against.

## Self-Check: PASSED

All eight created files exist on disk; all eleven commit hashes resolve in
`git log`; the gate summary above is a verbatim copy of a run executed after
the final code commit (`ebb83b2`). The four untracked paths — `.gsd/`,
`.planning/milestone.lock`, `.planning/research/.cache/`, `.tool-versions` —
are untouched and unstaged.
