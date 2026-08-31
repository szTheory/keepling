---
phase: KPL-01-one-trustworthy-task
plan: 13
subsystem: deterministic-task-list-projections
tags: [elixir, phoenix, postgresql, keyset-pagination, hmac, timezone, openapi, react, accessibility]

requires:
  - phase: KPL-01-12
    provides: Canonical planned/deadline civil dates, account-day classification, and projection revisions
provides:
  - Account-scoped Inbox, Today, Upcoming, and Completed projections with deterministic complete keysets
  - Opaque HMAC cursors bound to account, view, full tuple, view revision, and Today order revision
  - Server-arbitrated Today order with exact replay receipts and semantic earlier/later commands
  - Accessible routed browser lists with honest loading, empty, stale, authentication, retry, and ambiguous-delivery states
affects: [KPL-01-14, KPL-01-16, KPL-01-17, sync, mcp, desktop-offline, iphone-offline]

actuals:
  tokens: 26723
  tasks: 2
  commits: 6

tech-stack:
  added: []
  patterns: [account-timezone projections, revision-bound opaque keysets, scoped reorder lock, exact mutation replay, acknowledged list reconciliation]

key-files:
  created:
    - apps/server/lib/keepling/application/task_views.ex
    - apps/server/lib/keepling/adapters/postgres/task_views.ex
    - apps/server/lib/keepling_web/controllers/task_view_controller.ex
    - apps/server/priv/repo/migrations/20260830000650_add_task_view_projections.exs
    - apps/server/test/keepling/adapters/postgres/task_views_test.exs
    - apps/web/src/features/lists/TaskList.tsx
    - apps/web/src/features/lists/TodayList.tsx
    - apps/web/src/features/lists/UpcomingList.tsx
    - apps/web/src/features/lists/task-lists.test.tsx
  modified:
    - apps/server/lib/keepling/adapters/postgres/command_store.ex
    - apps/server/lib/keepling_web/router.ex
    - packages/contracts/openapi/keepling.yaml
    - packages/contracts/generated/keepling.ts
    - apps/web/src/api/keepling.ts
    - apps/web/src/app/routes.tsx
    - apps/web/src/App.tsx
    - apps/web/src/app/AppShell.tsx
    - apps/web/src/features/auth/auth.test.tsx

key-decisions:
  - "The existing /api/v1/inbox editor snapshot remains compatible; paginated Inbox projection reads use /api/v1/views/inbox alongside Today, Upcoming, and Completed view routes."
  - "Every cursor authenticates the account, named view, complete unique keyset, view revision, and Today order revision; a relevant accepted change returns an explicit stale result rather than continuing a mixed snapshot."
  - "Today order is server-owned, section-scoped, dense, and account-lock serialized; clients send only earlier/later intent plus expected order revision and stable mutation identity."
  - "Ambiguous Today delivery is never reported as failure: the browser retains the original submission and retries the exact identity until the server returns its durable terminal receipt."
  - "Completed projection storage is expanded now with nullable completed_at while lifecycle Plan 01-14 remains the owner of completion command semantics."

patterns-established:
  - "Projection truth: derive membership and visible reasons from the account civil day at request acceptance, sort by a complete unique tuple, and bind cursors to the projection revision that produced them."
  - "Reorder truth: serialize at the account order revision, persist dense section positions and the exact terminal receipt atomically, and apply browser movement only after acknowledgement."

requirements-completed: [GTD-03, GTD-04, SRV-02, WEB-01, WEB-02]

coverage:
  - id: D1
    description: "Inbox, Today, Upcoming, and Completed memberships, reasons, equal-key tie breakers, and pagination remain deterministic and account-scoped."
    requirement: GTD-03
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/adapters/postgres/task_views_test.exs"
        status: pass
    human_judgment: false
  - id: D2
    description: "Today and Upcoming resolve from the account IANA timezone and accepted instant while preserving all planned/deadline reasons."
    requirement: GTD-04
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/adapters/postgres/task_views_test.exs#projects account-timezone Inbox Today Upcoming and Completed memberships"
        status: pass
    human_judgment: false
  - id: D3
    description: "Opaque cursors bind account, view, full keyset, and revision; relevant changes stale the cursor and pages remain bounded by indexed queries."
    requirement: SRV-02
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/adapters/postgres/task_views_test.exs#binds an opaque cursor to account view full keyset and revisions"
        status: pass
    human_judgment: false
  - id: D4
    description: "Routed list views expose semantic lists, visible reasons, populated and empty states, explicit pagination, stable focus, and accessible stale/background recovery."
    requirement: WEB-01
    verification:
      - kind: automated_ui
        ref: "apps/web/src/features/lists/task-lists.test.tsx"
        status: pass
    human_judgment: false
  - id: D5
    description: "Today movement uses accessible earlier/later controls, waits for acknowledgement, and retries an ambiguous response with the exact original identity."
    requirement: WEB-02
    verification:
      - kind: automated_ui
        ref: "apps/web/src/features/lists/task-lists.test.tsx#treats a lost Today move response as unknown and retries the original identity"
        status: pass
      - kind: integration
        ref: "apps/server/test/keepling/adapters/postgres/task_views_test.exs#Today move identity replays one stored result and rejects changed semantics"
        status: pass
    human_judgment: false

duration: 24min
completed: 2026-08-31
status: complete
---

# Phase KPL-01 Plan 13: Deterministic Task Views and Routed List States Summary

**Account-timezone task projections with revision-bound opaque keysets, exactly replayable Today ordering, and accessible browser states that never overstate freshness**

## Performance

- **Duration:** 24 min
- **Started:** 2026-08-31T05:21:56Z
- **Completed:** 2026-08-31T05:46:17Z
- **Tasks:** 2
- **Files modified:** 18

## Accomplishments

- Added account-scoped Inbox, Today, Upcoming, and Completed PostgreSQL projections with canonical account-day evaluation, complete deterministic tie breakers, explicit visible reasons, bounded keyset pages, and purpose-built indexes.
- Added authenticated opaque cursor encoding that binds the account, view, full keyset, view revision, and Today order revision; changed projections reject old pages explicitly instead of mixing snapshots.
- Added server-owned Today section order with dense positions, account-scoped locking, optimistic order revisions, durable terminal receipts, one-winner race behavior, and rejection of changed commands that reuse a mutation identity.
- Exposed the projections and semantic Today movement through Phoenix, OpenAPI, checked-in generated TypeScript, and a typed browser facade without altering the existing full Inbox editor snapshot route.
- Routed Inbox, Today, Upcoming, and Completed into the browser shell with semantic list markup, visible reasons, exact loading/empty/updating/error/stale/authentication copy, explicit Load more, deterministic focus restoration, and keyboard-operable movement.
- Proved the full boundary with a reversible fresh PostgreSQL 18.6 migration, 66 server tests, contract drift checks, 32 browser component tests, lint, typecheck, production build, Phase 1 lanes, repository integrity, and 3 real-stack Chromium tests.

## Task Commits

Each planned TDD task has explicit RED and GREEN commits, followed by verified correctness fixes:

1. **Task 1 RED: Add failing task view proof** - `95134f8` (test)
2. **Task 1 GREEN: Expose deterministic task views** - `f9b5c5a` (feat)
3. **Task 2 RED: Add failing routed list proof** - `09551a9` (test)
4. **Task 2 GREEN: Route honest task list states** - `00eaf05` (feat)
5. **Architecture fix: Keep task views persistence-neutral** - `2caa30c` (fix)
6. **Trust-boundary fix: Make Today moves exactly replayable** - `0b3859b` (fix)

## Files Created/Modified

- `apps/server/lib/keepling/application/task_views.ex` - Persistence-neutral list and move application port plus authenticated cursor encoding/decoding.
- `apps/server/lib/keepling/adapters/postgres/task_views.ex` - Account-scoped projections, complete keysets, revision validation, Today ordering, locks, and exact move replay.
- `apps/server/priv/repo/migrations/20260830000650_add_task_view_projections.exs` - Reversible projection revisions, completion timestamp seam, keyset indexes, dense Today positions, and reorder receipts.
- `apps/server/lib/keepling/adapters/postgres/command_store.ex` - Relevant accepted task changes advance the affected projection revisions.
- `apps/server/lib/keepling_web/controllers/task_view_controller.ex`, `apps/server/lib/keepling_web/router.ex`, `packages/contracts/openapi/keepling.yaml`, and `packages/contracts/generated/keepling.ts` - Closed authenticated read/move transport and generated DTOs.
- `apps/web/src/api/keepling.ts` and `apps/web/src/app/routes.tsx` - Typed facade calls and authenticated list routing.
- `apps/web/src/features/lists/TaskList.tsx`, `TodayList.tsx`, and `UpcomingList.tsx` - Shared honest state machine, semantic lists, explicit pagination, grouped reasons, focus recovery, and acknowledged Today moves.
- `apps/web/src/App.tsx` and `apps/web/src/app/AppShell.tsx` - Reachable native list navigation in both setup and authenticated shells.
- Focused ExUnit and Testing Library suites - Timezone boundaries, all four memberships, cursor tamper/account/revision behavior, reorder races and replay, routed accessibility, stale refresh, pagination focus, and ambiguous delivery.

## Decisions Made

- Preserved the full Inbox editor endpoint for supported-client compatibility and introduced a distinct paginated Inbox view endpoint. Generated contracts retain both semantic shapes.
- Made cursor validity an explicit projection contract. Cursors are opaque durable tokens, but deliberately expire when their bound view or order revision changes.
- Kept all storage mechanics in the PostgreSQL adapter. The application module contains only semantic commands and portable cursor/authentication logic, satisfying the inward dependency rule.
- Treated reorder uncertainty exactly like other accepted mutations: the browser holds the stable command and makes an exact retry, while the server returns the original stored terminal result without applying the order twice.
- Added the nullable completion timestamp only as an expand-compatible projection seam. Plan 01-14 will define and prove lifecycle writes rather than this read plan inventing completion semantics.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] Added projection schema and revision advancement**
- **Found during:** Task 1
- **Issue:** The planned seven server/contract files could not provide durable view/order revisions, complete keyset indexes, Completed membership, or dense Today positions without a migration and relevant command-store revision bumps.
- **Fix:** Added an expand-compatible reversible migration and advanced only affected projection revisions from accepted commands.
- **Files modified:** `apps/server/priv/repo/migrations/20260830000650_add_task_view_projections.exs`, `apps/server/lib/keepling/adapters/postgres/command_store.ex`
- **Commit:** `f9b5c5a`

**2. [Rule 2 - Missing Critical Functionality] Wired authenticated shell reachability**
- **Found during:** Task 2
- **Issue:** Route definitions alone left the four daily lists undiscoverable from the browser shell; the additional visible navigation also exposed an ambiguous legacy auth-test selector.
- **Fix:** Added list navigation to both application shells and scoped the legacy assertion to its definition-list value without weakening behavior.
- **Files modified:** `apps/web/src/App.tsx`, `apps/web/src/app/AppShell.tsx`, `apps/web/src/features/auth/auth.test.tsx`
- **Commit:** `00eaf05`

**3. [Rule 1 - Bug] Removed persistence dependency from the application boundary**
- **Found during:** Overall server verification
- **Issue:** Initial cursor UUID validation imported `Ecto.UUID` into the application module, violating the repository architecture test and inward dependency direction.
- **Fix:** Kept opaque UUID values portable in the application layer and left validated transport/storage decoding at the outer adapters.
- **Files modified:** `apps/server/lib/keepling/application/task_views.ex`
- **Commit:** `2caa30c`

**4. [Rule 2 - Missing Critical Functionality] Closed ambiguous Today move delivery**
- **Found during:** Final trust review
- **Issue:** The first Today move implementation accepted a mutation identity but did not store its result, and the browser described network uncertainty as “Nothing was changed.” A lost accepted response could therefore invite a different retry and silently double-apply intent.
- **Fix:** Persisted account-scoped fingerprinted Today move receipts inside the reorder transaction, replayed exact terminal outcomes, rejected changed identity reuse, and made the browser retain/retry the byte-equivalent original submission while showing an honest unknown state.
- **Files modified:** `apps/server/lib/keepling/application/task_views.ex`, `apps/server/lib/keepling/adapters/postgres/task_views.ex`, `apps/server/lib/keepling_web/controllers/task_view_controller.ex`, `apps/server/priv/repo/migrations/20260830000650_add_task_view_projections.exs`, `apps/server/test/keepling/adapters/postgres/task_views_test.exs`, `apps/web/src/features/lists/TaskList.tsx`, `apps/web/src/features/lists/task-lists.test.tsx`
- **Commit:** `0b3859b`

## Issues Encountered

- A disposable database had applied the pre-receipt version of the still-uncommitted migration, so reversing the edited file correctly found no receipt table. Final migration proof used a fresh database in the same disposable PostgreSQL cluster, then completed down/up and the full server suite successfully.
- Adding visible Today navigation made one legacy auth test's unscoped text query ambiguous. The assertion now targets the timezone definition value while product navigation remains intact.

## TDD Gate Compliance

- Task 1 RED commit `95134f8` failed because the application port, projections, order arbitration, Phoenix endpoints, generated contracts, and migration did not exist; GREEN commit `f9b5c5a` made the focused projection/reorder proof pass.
- Task 2 RED commit `09551a9` failed on missing routed list loading, reasons, pagination/focus, and Today controls; GREEN commit `00eaf05` made the browser slice pass.
- The final trust review added failing replay and lost-response proofs before commit `0b3859b`; they failed on stale replay and dishonest generic failure respectively, then passed with durable receipts and exact browser retry.
- Both planned RED commits precede their matching GREEN commits. No separate refactor commit was necessary.

## Known Stubs

None - no TODO, FIXME, skipped test, mock production data source, hardcoded empty rendered data, placeholder implementation, or unrun verification remains in the 18 changed files.

## Threat Surface

- T-KPL01-27 is mitigated by authenticated account/view/full-keyset cursors, strict account predicates, scoped account locks, view/order revisions, dense unique positions, exact move receipts, changed-identity rejection, and race/replay tests.
- T-KPL01-28 is mitigated by a hard page limit of 50, opaque keyset continuation rather than offsets, matching PostgreSQL indexes, bounded Today sections, and a server-owned maximum reorder section size.
- No high-severity mitigation remains open, and no security-relevant endpoint, authentication path, file access pattern, or trust-boundary schema outside the plan threat model was introduced.

## Verification Evidence

- Fresh disposable PostgreSQL 18.6 schema migration, `20260830000650` down one step, and migration up: passed.
- `mix format`, `MIX_ENV=test mix compile --warnings-as-errors`, focused task-view proof, and full `mix test`: 66/66 server tests passed through pinned runtime preflight.
- `pnpm contracts:check`: OpenAPI and checked-in generated TypeScript agree.
- `pnpm --filter @keepling/web test --run`: 5 files and 32/32 browser component tests passed, including all 6 focused list cases.
- `pnpm lint:web`, `pnpm typecheck:web`, and `pnpm build:web`: passed; Vite transformed 63 modules.
- `pnpm test:phase-1`: repository integrity, warnings-as-errors server compile, contract drift, browser unit configuration, and Playwright real-stack discovery passed.
- `pnpm --filter @keepling/web test:e2e`: 3/3 real PostgreSQL/Phoenix/Chromium tests passed.

## User Setup Required

None. No dependency, credential, external service, or manual data migration was added.

## Next Phase Readiness

- Plan 01-14 can add completion/reopen lifecycle writes against the existing nullable `completed_at` projection seam and advance Completed revisions without redefining read membership or cursor semantics.
- Desktop and iPhone offline engines can consume stable view reasons, exact projection revisions, semantic move identities, and terminal receipts without treating network delivery as success.
- No high-severity mitigation assigned to Plan 01-13 remains open.

## Self-Check: PASSED

- All 18 realized implementation, migration, contract, facade, routing, shell, UI, and test files exist on disk.
- Commits `95134f8`, `f9b5c5a`, `09551a9`, `00eaf05`, `2caa30c`, and `0b3859b` exist in Git history in the documented order.
- Required actuals, requirements, stub scan, threat mitigations, deviation records, migration reversal, and fresh cross-boundary verification are present.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-31*
