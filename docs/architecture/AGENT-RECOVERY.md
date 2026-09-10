# Agent Undo Recovery — What This Server Guarantees, and Where That Guarantee Stops

Phase KPL-05, Plan 08. Written after reading the current source of the desktop client's local
undo affordance, not from the open defect ledger's description of it at filing time.

## What the server-side undo handle guarantees for an agent action

An agent action of a command type in `Keepling.Application.Undo.@supported_commands`
(`edit_task`, `clarify_task`, `return_to_inbox`, `plan_for_today`, `unplan_task`, `complete_task`,
`reopen_task`, `trash_task`, `restore_task`) is recorded with `recovery_state: "available"` and a
server-issued, account-bound, one-shot undo handle — the exact same handle shape, the exact same
`valid_for_seconds/0` expiry bound (24 hours), and the exact same compensation mechanism a
human-authored action of the same command type receives.

`Keepling.Application.Undo.compensation/2` takes a command and an activity fact, never an actor.
`Keepling.Adapters.Postgres.CommandStore`'s `issue_undo/5` and `apply_undo_delivery/4` read
`handle.original_command_type` and `command.expected_revision`/`handle.produced_revision`, never
`actor_type`. There is no code path in this undo mechanism that treats an agent-authored fact
differently from a human-authored one — undoing an agent action through
`POST /commands/undo-task` (or the equivalent internal `Keepling.Application.Undo.dispatch/3`
call) reverses the task to its prior field values, advances its revision, and is itself recorded
as a new activity fact attributed to whoever performed the undo. This is the guarantee D-22 binds
agent safety to: an agent action the user can see but cannot undo does not satisfy MCP-04, and
this is the proof that it is not the case.

An agent action of a command type **outside** `@supported_commands` (today, only `capture_task`
reaches an agent grant) is recorded with `recovery_state: "not_available"`. It carries no undo
handle and claims none — MCP-04's history surface never overstates what recovery is actually
available for a given fact.

An undo handle that has aged past its expiry reports `recovery_state`/outcome `expired` through
the same generic expiry check every handle goes through (`apply_undo_delivery/4`'s
`DateTime.compare(context.accepted_at, handle.expires_at)`), not an opaque failure — this applies
identically whether the original action was agent- or human-authored.

## Where this guarantee is reached, and where it is proven

This guarantee is reached through the server's command endpoints (`POST /commands/*`,
`POST /commands/undo-task`) and through the web client, which calls them. It is proven end to end
by `apps/server/test/keepling/application/agent_history_test.exs`'s undo round-trip test: an
agent-authored `edit_task` is issued, recorded `available`, undone through the exact same
`Keepling.Application.Undo.dispatch/3` path a human action uses, and the task's field values are
asserted at three points — before the agent action, after it, and after the undo — along with the
revision advancing and the undo itself appearing as a new, correctly-attributed activity fact.

## The desktop client's local undo affordance — a separate path, and a corrected claim

`.planning/WINDOWS.md` row 59 (filed 2026-09-04, phase KPL-03) records:

> `undoLastLocalAction` reverses a local change and enqueues NO outbound command, so an undo is
> invisible to the server -- the same defect class as O-41, needing server-issued undo handles the
> client does not retain (O-45)

Reading the current source rather than trusting that row: `apps/desktop/main/application/
DesktopApplication.ts`'s `undoLastLocalAction` (see its own header comment, "O-45: undo, made to
RECONCILE") now retains the server-issued handle as acknowledgements arrive, builds a real
`buildUndoCommand` targeting the retained handle, and calls
`apps/desktop/store-worker/local-store.ts`'s `undoLastLocalAction(outbound)`, which calls
`#enqueueOutbound(outbound)` — the identical durable-outbox mechanism every other desktop
command uses (`git log -S'#enqueueOutbound(outbound)'` names the closing commit,
`feat(KPL-03-23): make undo reconcile, and refuse loudly when it cannot (O-45)`).

**This means window 59, as literally written, no longer describes the current desktop source.**
The desktop client's local undo does now enqueue an outbound command reaching the server, through
the same reconciliation path O-41's fix established for other local writes. This document records
that finding rather than repeating the stale claim, but does not edit the ledger row itself —
reconciling `.planning/WINDOWS.md` row 59's status is a separate act this plan was not scoped to
perform (it was not in this plan's `files_modified` list, and the ledger's counts/format are
tool-managed).

What this plan's own proof does **not** cover, and therefore does not claim:

- Whether an **agent-authored** activity fact's undo handle round-trips correctly when undone
  *from the desktop leg specifically* — this plan proves the server-reached path (server + web
  client) only. The desktop leg's undo-command construction, its outbox delivery, and the
  server's acceptance of that specific outbound shape for an agent-originated original action are
  not independently exercised here.
- Whether desktop's undo-command delivery is itself synchronous with the user's action (it is
  queued to the durable outbox and delivered on the next sync pass, same as every other desktop
  command) — this is consistent with the rest of the desktop write model and is not a gap
  specific to undo or to agent actions.

## What the cross-adapter proof (05-12) may and may not claim from this

Plan 05-12's cross-adapter proof should therefore verify the desktop undo leg as a real,
non-defective path — not skip it as previously assumed broken — but it should independently
prove (not assume from this document) that an agent-authored action's undo round-trips
identically when undone through the desktop leg specifically, exactly as it must independently
prove parity for the web/API, Electron, and iPhone legs per D-27. This document claims undo
parity for the server-reached path (server + web client), proven here; it does not itself claim
desktop-leg parity for an agent-authored fact, which 05-12 owns.
