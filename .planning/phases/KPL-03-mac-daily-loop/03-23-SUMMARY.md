---
phase: KPL-03-mac-daily-loop
plan: 23
subsystem: desktop-sync-seam
tags: [gap-closure, sync, undo, capability, real-stack, macos-lane]
status: complete
requires:
  - 03-22 (O-41 closed; the resource-key ordering rule and classifyServerRefusal exist to be reused)
  - 03-21 (the packaged app reaches real Phoenix on real PostgreSQL)
provides:
  - undo reaching a real server and reversing the change there
  - a server-issued undo capability retained across quit and relaunch
  - a loud, authored refusal when no capability was ever issued
  - the last MAC-03 blocker closed on real-server evidence
affects:
  - apps/desktop (application, adapters, store worker, preload, renderer, main)
  - tooling (real-stack runner, macOS integration lane, desktop phase gate)
tech-stack:
  added: []
  patterns:
    - a capability is retained verbatim from the server, never minted, derived or repaired
    - one closed refusal list, consulted at every status the server actually answers with
    - an operation that cannot be reconciled is refused at the point of action, not accepted locally and dropped
    - a new presentation variant arrives with its production construction site, never before it
key-files:
  created:
    - apps/desktop/test/store/undo-handles.test.ts
    - apps/desktop/test/application/undo-reconciliation.test.ts
  modified:
    - apps/desktop/main/application/outbound-commands.ts
    - apps/desktop/main/application/DesktopApplication.ts
    - apps/desktop/main/application/presentation.ts
    - apps/desktop/main/adapters/server-refusal.ts
    - apps/desktop/main/adapters/sync.ts
    - apps/desktop/main/index.ts
    - apps/desktop/store-worker/{index.ts,local-store.ts}
    - apps/desktop/preload/contracts.ts
    - apps/desktop/renderer/desktopClientFacade.ts
    - apps/desktop/test/application/{outbound-commands,server-refusal,sync-presentation}.test.ts
    - apps/desktop/test/e2e/daily-loop.spec.ts
    - apps/desktop/test/real-stack/real-stack-sync.spec.ts
    - tooling/{verify-real-stack-desktop.mjs,verify-desktop-phase.mjs,verify-macos-integration.mjs}
decisions:
  - an undo whose mutation was never acknowledged is REFUSED at the point of action with authored copy, not deferred and not accepted locally
  - an expired handle is refused from the server's own expires_at, never a client-invented lifetime
  - undo_uncertain is never settled, because the server itself does not know whether the compensation applied
  - handles live in namespace_metadata, not a new table, because the single-migration checksum gate would fault every existing local store
  - the undo carries the same task:<id> resource key as every other command; no second ordering mechanism
metrics:
  duration: ~2h
  completed: 2026-09-04
actuals:
  tokens: 47000
  tasks: 3
  commits: 7
---

# Phase KPL-03 Plan 23: Make Undo Reconcile Summary

Undo now reaches a real Phoenix server, reverses the change in real
PostgreSQL, and survives a real quit and relaunch on the way there — and
when no server-issued capability exists it refuses out loud instead of
quietly diverging this Mac from the server forever.

## The plan's prose was wrong about where the expiry lives, and the contract won

The plan said an expired undo "must surface as a decided refusal through the
path 03-22 built for 409/422", and to "check whether the server's expiry code
is already in REJECTION_CODES; add it there if not."

It is not there, and adding it there alone would have done **nothing**.
`POST /commands/undo-task` publishes `UndoResult` — a `oneOf` of
`CommandAcknowledgement` and `UndoNoChange` — and the server answers a
no-change with **HTTP 200** for `expired`, `stale`, `already_applied` and
`uncertain`, and **404** only for `unknown`
(`CommandStore#undo_no_change`: `status: if(outcome == :unknown, do: 404,
else: 200)`). `classifyServerRefusal` was only ever reached for a **non-OK**
status, so a code added to its list would never have been consulted.

This is the same class of error 03-22 found when the plan located `conflict`
in the wrong enum, and it was found the same way: by reading the contract and
the server instead of the prose. **The contract won.** What survives from the
plan is the *intent*, which was right: one mechanism, not two. There is still
exactly one closed list and one classifier; it is now also consulted at the
two statuses the undo endpoint actually uses.

### What the defect actually was, before the fix

Worse than "undo does not reconcile". A 200 `UndoNoChange` has no `snapshot`,
so `mapAcknowledgement` threw `server acknowledgement is invalid`,
`runSyncPass` caught it, and an undo the server had **decided** about landed
on *"Couldn't reach the server. Your changes stay on this Mac."* with a Retry
button that would retry it forever. Not unheard — **misheard, as a transport
failure.** The identical misdiagnosis O-38 fixed for conflicts, one endpoint
later.

## What was built

**The handle is retained, never minted.** `CommandAcknowledgement.undo` is an
`UndoAvailability` — `expires_at`, `handle`, `label` — where the handle is an
opaque, account-bound, one-shot capability of 43..128 URL-safe base64
characters. `mapAcknowledgement` reads it and **throws** on a malformed one
rather than repairing it, for the same reason it refuses a 200 claiming
`conflict`. The local store is the only writer, keyed by the mutation the
handle undoes.

**The bytes are the contract's, exactly.** `UndoTaskCommand` publishes
`handle`, `mutation_id`, `version` and the optional `type` discriminator —
**no `task_id` and no `expected_revision`**. The server resolves both from the
handle it minted (`apply_undo_delivery` reads `handle.task_id` and compares
`handle.produced_revision` itself), and `decode_undo` compares the key set
**exactly**, so either extra key is a 400. Asserted against the checked-in
`keepling.yaml`, not a fixture.

**Ordering is 03-22's, unchanged.** The task identity travels *outside* the
bytes, in `effect.entityId` and the `task:<id>` resource key, so an undo
cannot overtake the mutation it undoes. `dependencies` stays empty. No second
mechanism, and `push` gained one optional `{ taskId }` argument that is this
client's own local routing key and is never sent.

**Atomicity.** The projection revert and the outbox insert share one
`BEGIN IMMEDIATE`, as every other mutation does.

**Where handles live, and why not a new table.** `namespace_metadata` — the
key/value table the draft, the sync fence, the bound namespace and the last
successful contact already use. Not a preference: there is exactly **one**
migration, and `#applyMigration` refuses to open a database whose recorded
checksum for version 1 disagrees with the file. Editing `0001_initial.sql`
would fault every **existing** local store into the closed "Keepling can't
open the tasks saved on this Mac" recovery state. Building a migration-2
mechanism to avoid that is real work with its own failure modes and was not
this plan's to do. Spent and lapsed handles are swept on each write; nothing
extends or renews one.

## The decision the plan asked to be made deliberately

An undo of a mutation whose acknowledgement never arrived has **no handle**.
Three answers were available. This client **refuses at the point of action**,
with authored copy, on both surfaces a person might be looking at.

Deferring would mean holding an intent with no bytes, materialising them
later from a handle that may never arrive, and inventing an in-doubt state to
describe the wait — a second durability mechanism alongside the outbox, and a
decision on `{ kind: 'uncertain' }` (**O-47**, out of scope). Refusing keeps
one mechanism and keeps the failure loud, which is what *"never silently
dropped"* actually requires.

An **expired** handle is refused from the server's own `expires_at`. That is
not a duplicate of the server's check: offline the server cannot be asked, and
queueing a command already certain to be refused would report an undo as
"Saved on this Mac" until a reconnect could disprove it. Online, the server's
`undo_expired` / `undo_stale` / `undo_already_applied` no-change settles the
command terminally through the same closed list.

`undo_uncertain` is **deliberately never settled**. It is the only no-change
the server marks `retryable: true`, emitted when the stored compensation
failed validation, and the server does not know whether anything applied.
Recording that as terminal would invent a decision nobody made. It stays
loud. O-47 owns what a person should *see* there and is untouched.

`{ kind: 'undo_unavailable' }` is a **new** presentation variant that arrived
with its production construction site on the same day it was declared — not
another unconstructed union member (O-49). It is deliberately not `rejected`,
whose copy says *"The server didn't accept this change"*; here the server was
never asked. `unsent` offers **Retry**, because syncing is what makes the
handle arrive. `expired` offers nothing, because nothing can change it.

## The cost, stated plainly

**On a Mac with no server configured, undo is now unavailable entirely.** No
mutation is ever acknowledged there, so no capability is ever issued, so every
Command-Z is a refusal. That is a real regression in local capability, traded
for never again diverging a Mac from a server in silence. It follows directly
from the plan's own truth *"never retained fails LOUDLY"*, applied without
special cases — but it is a **product decision worth revisiting**, and it is
filed as **O-51** rather than buried here.

Two lanes were changed *because they asserted the old behaviour*, and both now
assert the new one rather than being relaxed:

- `test/e2e/daily-loop.spec.ts` asserted that undo reversed a restore in an
  app with no server. It now asserts the refusal on both surfaces and that
  nothing changed — and a **new** spec proves the reconciling path once a
  server has issued a capability.
- macOS row **A5** asserted that Command-Z put the task back in Trash. Its
  claim — *"undo is reachable by keyboard alone"* — is unchanged and is now
  proved by finding the authored refusal copy in the real AXUIElement tree
  (what a screen reader would read out) **and** that nothing changed. That is
  a stronger observation than the list-membership check it replaced.
  A5: 10 cases → 13.

## What the tests actually exercised — honestly

**The real-stack lane (`REAL_STACK_UNDO`), against real Phoenix on real
PostgreSQL, packaged artifact, no stubbed transport, `KEEPLING_TEST_SYNC_MODE`
absent:**

| Observed | How |
|---|---|
| `handle=server_issued` | the `UndoAvailability` real Phoenix minted for a real `complete_task`, read back out of the app's own SQLite; shape, future expiry and server-authored label asserted |
| `undo_arrived=1` | the outbox's **exact bytes** found among the bodies the forwarding proxy watched arrive on `/commands/undo-task` |
| `reverted_on_server=1` | the **server's own** `completed_at` back to null and its revision **up**, because the server applied a compensation |
| `survived_relaunch=1` | the app really quit and really relaunched with the undo queued; the bytes afterwards byte-identical |
| `refused_without_handle=1` | an undo of a never-acknowledged mutation refused with copy on screen, enqueueing nothing |

**Not observed there, and not claimed:** an **expired** handle. The server's
lifetime is 24 hours (`Undo.valid_for_seconds`) and nothing in the lane may
shorten it. `undo_expired` / `undo_stale` / `undo_already_applied` /
`undo_unknown` are proved exhaustively at the unit boundary in
`test/application/server-refusal.test.ts`, driven with the server's **own**
`undo_no_change` bodies; the client-side expiry refusal is proved in
`test/application/undo-reconciliation.test.ts`.

**Also not observed anywhere:** a real `undo_uncertain` from the server. It
requires the stored compensation to fail validation, which no reachable input
produces. Its handling (stay loud) is unit-proved only.

The `daily-loop.spec.ts` "undo reconciles" case runs against the
`KEEPLING_TEST_SYNC_MODE=acknowledge` fixture, which now issues a
contract-shaped capability because a server that accepts a compensatable
command issues one. **That capability is a fixture**, which is precisely why
the real-stack lane exists and forbids that mode. It is a UI-path proof, not a
server-agreement proof.

## Deviations from Plan

### File scope

The plan's `files_modified` named six files. Closing O-45 honestly needed
more, each for a stated reason:

| File | Why |
|---|---|
| `main/application/presentation.ts` | the refusal needed authored copy and a construction site; reusing `rejected` would have said the server refused when it was never asked |
| `preload/contracts.ts` | `undoResultSchema` is `.strict()`; the optional `reason` had to be admitted |
| `store-worker/index.ts`, `main/index.ts` | the worker port had to carry the undo command and the new `undoTarget` read; an unrouted operation is O-20's failure mode |
| `renderer/desktopClientFacade.ts` | the refusal reaches `SyncRecovery`'s live region and had to say the same thing main says |
| `test/e2e/daily-loop.spec.ts`, `tooling/verify-macos-integration.mjs` | both asserted the old behaviour (see above) |
| `tooling/verify-real-stack-desktop.mjs`, `tooling/verify-desktop-phase.mjs` | evidence a lane does not enforce is a lane that can go green having proved nothing |
| `test/application/sync-presentation.test.ts` | its `readyMutations` fixture omitted `effect` entirely; stating both halves makes it an honest stand-in for the real store |

### [Rule 2 — missing critical functionality] the test stub now issues a capability

`main/index.ts`'s `KEEPLING_TEST_SYNC_MODE=acknowledge` stub is **playing the
server**, and a real server that accepts a compensatable command issues an
undo capability. Without one, every e2e undo became a refusal and the shipped
UI path had no coverage at all. The fixture handle is contract-shaped and the
real-stack lane forbids the mode, so it can never stand in for real evidence.

## Known Stubs

None introduced.

## Scope discipline

**O-43, O-46 and O-47 remain open and untouched.** Nothing here gave a refused
local change a durable home, constructed `{ kind: 'preparing' }`, or
constructed `{ kind: 'uncertain' }` — the last of which was the live
temptation, and was declined by leaving `undo_uncertain` unsettled and loud.

**No requirement checkbox was marked** (O-17). MAC-03 is for the orchestrator
to re-derive against this evidence.

## Gate

```
Desktop phase gate summary: lanes=10 failed=0
  PASS typecheck-desktop cases=1 duration_ms=1174
  PASS typecheck-web cases=1 duration_ms=1936
  PASS unit-pure-vector-store-worker-performance cases=282 duration_ms=1228
  PASS ipc-hostile-bridge cases=75 duration_ms=699
  PASS electron-e2e cases=66 duration_ms=61381
  PASS package-once cases=1 duration_ms=13041
  PASS packaged cases=10 duration_ms=8831
  PASS real-stack-sync cases=4 duration_ms=15861
  PASS macos-integration cases=93 duration_ms=275
  PASS privacy cases=1 duration_ms=19
Desktop phase gate: PASSED
```

`application_digest=2783671b10fd4ce386ca77dc4c9730ba7c4bed568eeee5e2c8fd27f7da8a349e`,
macOS evidence re-recorded for that digest (rows=15 failed=0 cases=93,
`SETTINGS restore=VERIFIED`). The digest was **stable across two consecutive
`pnpm package:desktop` invocations at this revision** — measured, not assumed
— so O-40 did not bite this time. O-40 stays open; the binding was not
loosened.

## Self-Check: PASSED
