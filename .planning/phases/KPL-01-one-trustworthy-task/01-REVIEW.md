---
phase: KPL-01-one-trustworthy-task
reviewed: 2026-08-31T23:15:07Z
depth: standard
files_reviewed: 21
files_reviewed_list:
  - apps/server/lib/keepling_web/router.ex
  - apps/server/test/keepling_web/test_fault_test.exs
  - apps/web/e2e/authenticated-read-recovery.spec.ts
  - apps/web/e2e/conflict-resolution-recovery.spec.ts
  - apps/web/e2e/session-reconciliation.spec.ts
  - apps/web/e2e/today-order-recovery.spec.ts
  - apps/web/src/app/AuthProvider.tsx
  - apps/web/src/app/routes.tsx
  - apps/web/src/features/activity/ActivityList.tsx
  - apps/web/src/features/activity/activity-list.test.tsx
  - apps/web/src/features/auth/auth.test.tsx
  - apps/web/src/features/lists/TaskList.tsx
  - apps/web/src/features/lists/task-lists.test.tsx
  - apps/web/src/features/organizations/OrganizationFields.tsx
  - apps/web/src/features/organizations/organization-fields.test.tsx
  - apps/web/src/features/sessions/SessionList.tsx
  - apps/web/src/features/sessions/session-list.test.tsx
  - apps/web/src/features/tasks/ConflictResolver.tsx
  - apps/web/src/features/tasks/TaskEditor.tsx
  - apps/web/src/features/tasks/conflict-resolver.test.tsx
  - apps/web/src/features/tasks/task-editor.test.tsx
findings:
  critical: 7
  warning: 2
  info: 0
  total: 9
status: issues_found
---

# Phase KPL-01: Code Review Report

**Reviewed:** 2026-08-31T23:15:07Z
**Depth:** standard
**Files Reviewed:** 21
**Status:** issues_found

## Summary

The gap-closure changes repair the five previously reported happy-path defects, and the focused component suite passes 69/69 tests. The post-fix implementation is still unsafe to ship. Seven blocking state-machine and race defects can lose a queued authentication continuation, discard an exact mutation identity or dirty draft, bypass conflict resolution, strand uncertain session reconciliation, or make mounted task/session projections contradict accepted server state. Two additional warnings cover keyboard isolation and real-stack tests that can pass without proving the behavior named by their tags.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: A continuation registered during an active drain can be skipped or deleted without running

**Classification:** BLOCKER

**File:** `/Users/jon/projects/keepling/apps/web/src/app/AuthProvider.tsx:75-80`

**Also affected:** `/Users/jon/projects/keepling/apps/web/src/app/AuthProvider.tsx:93-117`

**Issue:** `drainContinuations` snapshots the map once. A different-key interruption registered while `Promise.allSettled` is running is not included, so the completed authentication rotation leaves it queued and presents another sign-in/reauthentication prompt. More seriously, a same-key registration replaces the map value while the old callback is in `pending`; when the old callback fulfills, line 106 deletes that key unconditionally and thereby deletes the newer callback even though it never ran. Delayed 401 responses from mounted concurrent reads make this race reachable. This violates the exact-once continuation contract and can silently lose recovery work.

**Fix:** Give every stored entry a unique generation/token, delete it only when the current map value is the exact entry that settled, and keep draining newly registered compatible entries under the same rotated session until the queue is empty. Add a deferred test that registers both a different-key and replacement same-key continuation after draining starts.

### CR-02: Failed resumed reads are reported to the coordinator as successful and permanently removed

**Classification:** BLOCKER

**File:** `/Users/jon/projects/keepling/apps/web/src/features/tasks/TaskEditor.tsx:104-139`

**Also affected:** `/Users/jon/projects/keepling/apps/web/src/features/organizations/OrganizationFields.tsx:148-170`, `/Users/jon/projects/keepling/apps/web/src/features/organizations/OrganizationFields.tsx:415-440`, `/Users/jon/projects/keepling/apps/web/src/features/activity/ActivityList.tsx:256-279`, `/Users/jon/projects/keepling/apps/web/src/app/AuthProvider.tsx:100-110`

**Issue:** Each registered callback awaits `load(false)`, but those load functions catch the retry failure internally and resolve normally. `Promise.allSettled` therefore classifies the continuation as fulfilled and deletes it. Task detail then offers only “Return to Inbox,” task assignments have no retry control, and organization management has no read retry control. A transient failure or second 401 immediately after sign-in thus discards the retained continuation and dead-ends the original route despite the provider's advertised visible retry state.

**Fix:** Make a resumed load reject after placing an appropriate retained UI state, or return an explicit success/failure result that the provider honors. Keep failed entries queued and expose the shared “Try continuing again” action. Add component tests where the post-authentication retry fails once and then succeeds without navigation or a new intent.

### CR-03: Any same-task acknowledgement can erase a dirty draft and an unresolved exact edit

**Classification:** BLOCKER

**File:** `/Users/jon/projects/keepling/apps/web/src/features/tasks/TaskEditor.tsx:149-169`

**Issue:** The global `keepling:task-acknowledged` listener accepts every acknowledgement with the same task ID, then unconditionally clears `submission`, drops `exactSubmission.current`, clears recovery, and replaces the entire draft. The mounted global undo strip can emit such an acknowledgement while the editor contains unsaved work or while its own edit is unknown/authentication-required. The user's draft is then silently overwritten and the original mutation identity becomes unreachable, even though the external acknowledgement is unrelated to that exact submission.

**Fix:** Do not apply external acknowledgements destructively while the editor is dirty or owns a nonterminal exact submission. Queue/reconcile the external snapshot, preserve or explicitly rebase the draft, and retain the original receipt lookup until terminal settlement. Add tests for an external undo acknowledgement during both a dirty unsaved edit and an unknown edit submission.

### CR-04: The underlying editor can submit a new mutation while conflict resolution is active

**Classification:** BLOCKER

**File:** `/Users/jon/projects/keepling/apps/web/src/features/tasks/TaskEditor.tsx:177-185`

**Also affected:** `/Users/jon/projects/keepling/apps/web/src/features/tasks/TaskEditor.tsx:382-389`, `/Users/jon/projects/keepling/apps/web/src/features/tasks/TaskEditor.tsx:587-598`, `/Users/jon/projects/keepling/apps/web/src/features/tasks/TaskEditor.tsx:747-763`, `/Users/jon/projects/keepling/apps/web/src/features/tasks/ConflictResolver.tsx:119-164`

**Issue:** Receiving a conflict clears `submission`, so `locked` becomes false even while `commandState.kind === 'conflict'`. The new resolver correctly freezes its own controls after resolution dispatch, but the editor fields and its separate “Save changes”/“Save & move out of Inbox” buttons remain enabled. A user can bypass the resolver, create another edit mutation against the old revision, or dispatch that edit while the first resolution is in flight/unknown. This defeats the immutable-resolution fix and can create another persisted conflict or race the accepted resolution.

**Fix:** Treat an active conflict as an editor-level lock (`submission !== null || commandState.kind === 'conflict'`). Unlock the editor only through the explicit “Keep editing” transition or after terminal resolution. Add a regression test that attempts the underlying form submission before and during a deferred resolution and asserts no edit command is sent.

### CR-05: Authentication expiry during session reconciliation becomes an endless unknown state

**Classification:** BLOCKER

**File:** `/Users/jon/projects/keepling/apps/web/src/features/sessions/SessionList.tsx:86-131`

**Issue:** After an uncertain rename or revoke, `reconcile` catches every `listSessions` failure and sets `status: 'unknown'`. It does not classify `authentication_required` or register the retained read with `onAuthenticationRequired`. “Check again” therefore repeats the same unauthenticated read forever. Reloading and signing in loses the retained intended/previous label or revoke identity, so the browser can no longer finish the promised authoritative reconciliation in place.

**Fix:** Classify authentication failures in reconciliation and register a read continuation keyed to the retained `SessionRecovery` action. After session rotation, retry only `listSessions`, not the mutation; keep unknown state for genuinely unreadable non-auth failures. Test a 503 mutation followed by 401 inventory and successful post-login inventory.

### CR-06: Concurrent session actions overwrite each other's accepted UI results

**Classification:** BLOCKER

**File:** `/Users/jon/projects/keepling/apps/web/src/features/sessions/SessionList.tsx:190-203`

**Also affected:** `/Users/jon/projects/keepling/apps/web/src/features/sessions/SessionList.tsx:235-251`, `/Users/jon/projects/keepling/apps/web/src/features/sessions/SessionList.tsx:367-408`

**Issue:** Starting one request sets `busySessionId`, but controls for every other session remain enabled. Each success handler writes from its render-time `state.sessions` closure rather than a functional update. Two renames/revokes that settle out of order can therefore accept both server changes while the last React update resurrects a revoked session or restores another session's old label. The UI then silently contradicts authoritative state and displays only the last outcome.

**Fix:** Either serialize all session administration while any write is in flight, or track concurrent actions independently and use functional state updates for every result. Reconcile inventory after overlapping actions. Add deferred two-session tests whose responses resolve in both orders.

### CR-07: A Today move response can resurrect a concurrently completed task

**Classification:** BLOCKER

**File:** `/Users/jon/projects/keepling/apps/web/src/features/lists/TaskList.tsx:240-269`

**Also affected:** `/Users/jon/projects/keepling/apps/web/src/features/lists/TaskList.tsx:361-405`, `/Users/jon/projects/keepling/apps/web/src/features/lists/TaskList.tsx:425-455`

**Issue:** The global lock disables only Earlier/Later. Lifecycle controls remain active while a move is in flight. If the move commits, then completion removes the task locally before the delayed move response settles, `settleMove` applies a swap to its stale render-time `state.page` and writes that old page back, resurrecting the completed task in Today. The same stale closure can discard rows appended by concurrent pagination. Both server mutations may be accepted while the browser shows an impossible projection.

**Fix:** Serialize Today-order and lifecycle operations that affect the same projection, or settle the move through functional state updates/reload authoritative Today before writing. Disable conflicting lifecycle/pagination controls while an exact move is nonterminal. Add a deferred move test followed by an accepted completion before the move response resolves.

## Warnings

### WR-01: The authentication overlay hides background content from AT but leaves it keyboard-interactive

**Classification:** WARNING

**File:** `/Users/jon/projects/keepling/apps/web/src/app/routes.tsx:67-83`

**Also affected:** `/Users/jon/projects/keepling/apps/web/src/app/routes.tsx:138-179`

**Issue:** `InterruptionBoundary` applies only `aria-hidden` to retained route elements. `aria-hidden` does not prevent focus or activation, and the overlay has no dialog semantics or focus trap. Keyboard users can tab into and activate visually covered controls, including mutation controls whose static continuation keys can replace pending work. This is an accessibility regression and a state-integrity hazard.

**Fix:** Apply `inert` to every retained background root while interrupted, give the overlay appropriate modal-dialog semantics and focus management, then restore the prior focused element and prior `inert`/`aria-hidden` values on settlement. Add a keyboard test that proves focus cannot leave the recovery surface.

### WR-02: The new real-stack read test can pass while activity and collection recovery are broken

**Classification:** WARNING

**File:** `/Users/jon/projects/keepling/apps/web/e2e/authenticated-read-recovery.spec.ts:79-105`

**Also affected:** `/Users/jon/projects/keepling/apps/web/e2e/authenticated-read-recovery.spec.ts:108-151`, `/Users/jon/projects/keepling/apps/web/src/features/auth/auth.test.tsx:128-209`

**Issue:** The task test asserts only the Activity heading, which is rendered during loading, error, and success, so it still passes if the activity continuation never runs. Projects and Tags similarly assert headings that render before their inventories settle. The coordinator unit test registers every callback before draining; it never registers a continuation during a deferred drain, so it cannot expose CR-01. The `@authenticated-read-concurrent` tag therefore overstates the exercised boundary.

**Fix:** Assert a known captured activity row and authoritative organization data after sign-in, exercise real cursor pagination expiry, and defer one resume while registering another different-key and same-key continuation during the active drain. Assert every callback runs exactly once under the same rotation.

---

_Reviewed: 2026-08-31T23:15:07Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
