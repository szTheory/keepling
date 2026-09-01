---
phase: KPL-02-synchronization-and-replaceable-server
plan: 02
subsystem: synchronization
tags: [elixir, postgres, ordered-feed, hmac-cursor, bootstrap, tombstones]

requires:
  - phase: KPL-02-synchronization-and-replaceable-server
    plan: 01
    provides: storage-neutral reducer, immutable local intent, monotonic entity revisions, and exact acknowledgement semantics
  - phase: KPL-02-synchronization-and-replaceable-server
    plan: 03
    provides: server-derived installation namespace and synchronization-generation fencing
provides:
  - Atomic account-sequenced command outcome, snapshot, conflict, tombstone, and undo feed envelopes
  - HMAC-authenticated namespace, restore-epoch, protocol, codec, expiry, and low-water-bound feed cursors
  - Authorized high-water bootstrap with stable keyset paging and strict post-high-water catch-up
affects: [sync-transport, compatibility, desktop-offline-store, ios-offline-store, restore-epoch]

actuals:
  tokens: 14334
  tasks: 3
  commits: 7

tech-stack:
  added: []
  patterns: [locked account feed clock, deterministic envelope ordinals, closed reset reasons, high-water bootstrap]

key-files:
  created:
    - apps/server/priv/repo/migrations/20260901000100_add_sync_feed.exs
    - apps/server/lib/keepling/adapters/postgres/sync_feed.ex
    - apps/server/lib/keepling/application/sync.ex
    - apps/server/lib/keepling/application/sync/cursor.ex
    - apps/server/test/keepling/adapters/postgres/sync_feed_test.exs
    - apps/server/test/keepling/application/sync/cursor_test.exs
    - apps/server/test/keepling/application/sync/bootstrap_test.exs
  modified:
    - apps/server/lib/keepling/adapters/postgres/command_store.ex
    - apps/server/test/support/sync_scenario.ex

key-decisions:
  - "Every first delivery reserves one account sequence before semantic resource locks; ordinal zero is the terminal command outcome and related canonical envelopes follow deterministically."
  - "Feed cursors and bootstrap cursors are separate authenticated codecs; both bind issuer, origin, server instance, account subject, installation generation, restore epoch, and protocol train."
  - "Bootstrap keyset order is not expected to contain every concurrent write; strict feed catch-up after the captured high-water is the gap-free authority."
  - "Task organization removal emits membership tombstones while the owning task and Trash remain canonical snapshots."

patterns-established:
  - "Atomic feed: receipt arbitration, account sequence reservation, semantic effect/conflict, ordered envelopes, and receipt finalization share one Repo.transact boundary."
  - "Closed recovery: cursor tamper, namespace mismatch, restore epoch, protocol, codec, expiry, and low-water conditions map to explicit bootstrap, quarantine, or upgrade actions."
  - "Gap-free bootstrap: authorize first, capture high-water, enumerate stable identities, then pull strictly after high-water while replaying immutable local intent."

requirements-completed: [SRV-04, SRV-05]

coverage:
  - id: D1
    description: "Every first command delivery commits one gap-free account sequence containing its terminal outcome and deterministic canonical envelopes; replay and rollback append nothing."
    requirement: SRV-04
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/adapters/postgres/sync_feed_test.exs#first delivery, rollback, conflict, concurrency, and tombstone cases"
        status: pass
    human_judgment: false
  - id: D2
    description: "Opaque feed positions are authenticated against the complete server-derived namespace, restore epoch, protocol, codec, expiry, and low-water state with closed recovery reasons."
    requirement: SRV-04
    verification:
      - kind: unit
        ref: "apps/server/test/keepling/application/sync/cursor_test.exs#authenticated and reset-reason cases"
        status: pass
    human_judgment: false
  - id: D3
    description: "High-water bootstrap remains gap-free across multiple pages and concurrent writes while preserving Trash snapshots and immutable local pending intent."
    requirement: SRV-05
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/application/sync/bootstrap_test.exs#multi-page, concurrent-write, Trash, local-intent, and namespace cases"
        status: pass
      - kind: integration
        ref: "mix test sync + Phase 1 idempotency/conflict regressions#29 passed including 1 property"
        status: pass
    human_judgment: false

duration: 16min
completed: 2026-09-01
status: complete
---

# Phase KPL-02 Plan 02: Atomic Feed, Authenticated Cursor, and Bootstrap Summary

**A transactionally ordered PostgreSQL feed now pairs with namespace-bound opaque cursors and gap-free high-water bootstrap recovery.**

## Performance

- **Duration:** 16 min
- **Started:** 2026-09-01T06:23:11Z
- **Completed:** 2026-09-01T06:38:53Z
- **Tasks:** 3
- **Files modified:** 9 implementation and proof files

## Accomplishments

- Added account-scoped clocks, restore epochs, and compound-position feed storage whose sequence reservation, semantic result, conflict/activity state, envelopes, and terminal receipt share one PostgreSQL transaction.
- Added distinct HMAC-authenticated feed and bootstrap cursor behavior with independent adapter authorization and closed bootstrap/quarantine/upgrade recovery results.
- Proved stable keyset bootstrap plus strict post-high-water catch-up across empty, multi-page, concurrent-write, Trash, namespace-reset, and pending-local scenarios.
- Emitted deterministic membership tombstones for canonical project/tag collection removal without reinterpreting Trash as deletion.

## Task Commits

Each TDD task was committed as a RED test followed by its GREEN implementation:

1. **Task 1 RED: failing atomic feed proof** - `a77a3d8` (test)
2. **Task 1 GREEN: ordered transactional feed** - `a399669` (feat)
3. **Task 2 RED: failing authenticated cursor contract** - `661136f` (test)
4. **Task 2 GREEN: namespace-bound feed cursor** - `78f5a87` (feat)
5. **Task 3 RED: failing gap-free bootstrap proof** - `971ff29` (test)
6. **Task 3 GREEN: high-water canonical bootstrap** - `3e56e15` (feat)
7. **Deviation fix: collection membership tombstones** - `72b31b0` (fix)

## Files Created/Modified

- `apps/server/priv/repo/migrations/20260901000100_add_sync_feed.exs` - Additive feed clocks, epochs, envelopes, compound positions, constraints, and receipt linkage.
- `apps/server/lib/keepling/adapters/postgres/command_store.ex` - Reserves feed order and appends terminal envelopes before receipt finalization.
- `apps/server/lib/keepling/adapters/postgres/sync_feed.ex` - Feed writer/reader, independent namespace authorization, bootstrap enumeration, and collection tombstones.
- `apps/server/lib/keepling/application/sync.ex` - Inward bootstrap port and distinct authenticated bootstrap cursor.
- `apps/server/lib/keepling/application/sync/cursor.ex` - Opaque feed-position codec and closed reset policy.
- `apps/server/test/keepling/adapters/postgres/sync_feed_test.exs` - PostgreSQL atomicity, replay, rollback, ordering, conflict, and tombstone evidence.
- `apps/server/test/keepling/application/sync/cursor_test.exs` - Namespace, tamper, epoch, compatibility, expiry, low-water, and monotonicity evidence.
- `apps/server/test/keepling/application/sync/bootstrap_test.exs` - High-water, keyset, race, Trash, local-intent, and fencing evidence.
- `apps/server/test/support/sync_scenario.ex` - Bounded bootstrap-page collector for recovery scenarios.

## Decisions Made

- Kept the durable order deliberately account-serialized with one locked clock, while ordinals preserve stable multi-envelope order inside a command transaction.
- Kept acknowledgement freshness separate from pulled coverage; only an explicit feed position advances global coverage.
- Used separate cursor codecs for feed positions and bootstrap keysets so Phase 1 view cursors and synchronization recovery cannot be confused.
- Froze pull limit 200, offline grace 30 days, pruning batch 1,000, and destructive pruning disabled pending measured low-water/reset evidence.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected the concurrent-bootstrap assertion to follow high-water semantics**
- **Found during:** Task 3 GREEN verification
- **Issue:** The initial test assumed a post-high-water random UUID must appear in later keyset pages, but it may sort before the saved keyset.
- **Fix:** Assert the required D-11 guarantee: the mutation appears strictly after high-water in feed catch-up, regardless of bootstrap keyset placement.
- **Files modified:** `apps/server/test/keepling/application/sync/bootstrap_test.exs`
- **Verification:** Combined bootstrap/feed suite passed 7/7.
- **Committed in:** `3e56e15`

**2. [Rule 2 - Missing critical functionality] Emitted canonical collection-removal tombstones**
- **Found during:** Final D-13 threat/requirement scan
- **Issue:** Storage admitted tombstone envelopes but the first-delivery path did not yet emit them for removed task organization memberships.
- **Fix:** Deterministically append project/tag membership tombstones after the authoritative task snapshot in the same receipt/feed transaction.
- **Files modified:** `apps/server/lib/keepling/adapters/postgres/sync_feed.ex`, `apps/server/test/keepling/adapters/postgres/sync_feed_test.exs`
- **Verification:** Full plan-level gate passed 29 tests including one property.
- **Committed in:** `72b31b0`

---

**Total deviations:** 2 auto-fixed (1 Rule 1, 1 Rule 2)
**Impact on plan:** Both changes were necessary to prove the locked high-water and tombstone semantics; neither expands the architecture or transport scope.

## Issues Encountered

- Context7 was unavailable through MCP and the approved `ctx7` CLI was not installed. Version-specific transaction behavior was therefore kept to the already pinned and exercised `Repo.transact/2`/SQL patterns established in the repository and proven against PostgreSQL 18.6.
- A first RED database cleanup callback used zsh's read-only `status` name; subsequent disposable test runs used a task-specific exit variable and completed normally.

## Known Stubs

None. The scan found no TODO/FIXME/placeholder path or empty value flowing to a UI, and destructive feed pruning remains explicitly disabled policy rather than an incomplete runtime path.

## User Setup Required

None - transport wiring, restore epoch rotation, and deployment operations consume these inward seams in later Phase 2 plans.

## Next Phase Readiness

- Plan 02-11 and sync transport work can expose the authenticated namespace without accepting client-asserted authority.
- Compatibility work can freeze the feed/bootstrap codecs and advertised retention behavior for supported protocol trains.
- Restore work can rotate `sync_epochs` and force the closed reset/bootstrap path before readiness.

---
*Phase: KPL-02-synchronization-and-replaceable-server*
*Completed: 2026-09-01*

## Self-Check: PASSED

- All seven created implementation/proof artifacts, both modified seams, and this summary exist on disk.
- All seven RED/GREEN/deviation commits are present in Git history.
- Coverage metadata parsed successfully with all three deliverables backed by passing automated evidence.
