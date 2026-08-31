---
phase: KPL-01-one-trustworthy-task
plan: 09
subsystem: semantic-task-editing
tags: [elixir, phoenix, postgresql, openapi, react, typescript, accessibility]

requires:
  - phase: KPL-01-08
    provides: Authenticated browser shell, generated DTO facade, exact reauthentication recovery, and reachable Inbox
provides:
  - Versioned title/notes edit, clarification, and return-to-Inbox semantic commands
  - Account-scoped PostgreSQL three-way rebase with replay-stable conflicts and exact acknowledgements
  - Canonical routed browser task editor with explicit save, dirty-navigation recovery, and acknowledgement-safe Inbox removal
affects: [KPL-01-10, KPL-01-11, KPL-01-12, KPL-01-16, KPL-01-17, task-contracts, browser-editor]

actuals:
  tokens: 24798
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns: [touched-field base-value commands, server-owned semantic rebase, explicit Inbox processing state, routed shared editor]

key-files:
  created:
    - apps/server/priv/repo/migrations/20260830000300_add_task_details.exs
    - apps/server/test/keepling/domain/edit_task_test.exs
    - packages/contracts/vectors/editing.json
    - apps/web/src/features/tasks/TaskEditor.tsx
    - apps/web/src/features/tasks/task-editor.test.tsx
  modified:
    - apps/server/lib/keepling/domain/task.ex
    - apps/server/lib/keepling/application/commands.ex
    - apps/server/lib/keepling/adapters/postgres/command_store.ex
    - apps/server/lib/keepling_web/controllers/command_controller.ex
    - packages/contracts/openapi/keepling.yaml
    - packages/contracts/generated/keepling.ts
    - apps/web/src/api/keepling.ts
    - apps/web/src/app/routes.tsx
    - apps/web/src/App.tsx

key-decisions:
  - "Task detail contract version 1 trims outer title whitespace, bounds titles at 512 Unicode scalar values, and preserves plain-text notes up to 50000 scalar values."
  - "Edit and clarify requests carry only touched fields plus matching base values; PostgreSQL locks the account-scoped task and the pure domain owns rebase and conflict decisions."
  - "Inbox membership remains explicit as inbox or clarified: ordinary edit preserves it, clarify is the only removal command, and return_to_inbox is the only inverse."
  - "The canonical /tasks/:id editor retains drafts and a fixed mutation identity until an exact acknowledgement, including authentication and unknown-delivery recovery."

patterns-established:
  - "Semantic update DTO: fields and base_values have identical title/notes keys; controllers reject open or mismatched shapes before receipts."
  - "Acknowledgement-safe membership: the editor and Inbox projection do not remove a clarified row until the returned mutation identity matches the submission."
  - "Shared routed editor: narrow view renders the canonical route as a full page while wide view composes the same component over the retained Inbox workspace."

requirements-completed: [GTD-02, SRV-02, SRV-03, WEB-01, WEB-02]

coverage:
  - id: D1
    description: "Title and notes edits preserve unrelated accepted fields, enforce versioned bounds, and persist exact changed-field activity through the shared semantic boundary."
    requirement: GTD-02
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/domain/edit_task_test.exs#title and notes cross Phoenix and PostgreSQL with rebase, clarify, and return"
        status: pass
      - kind: unit
        ref: "packages/contracts/vectors/editing.json consumed by Keepling.Domain.EditTaskTest"
        status: pass
    human_judgment: false
  - id: D2
    description: "Overlapping edits return one persisted structured conflict while same-identity replay returns the original terminal result and malformed shapes create no receipt."
    requirement: SRV-03
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/domain/edit_task_test.exs#overlap conflict and structural failure are stable and do not bypass receipts"
        status: pass
      - kind: integration
        ref: "apps/server/test/keepling/adapters/postgres/idempotency_test.exs"
        status: pass
    human_judgment: false
  - id: D3
    description: "The canonical browser editor uses explicit Save/Cancel and atomic Save & move, preserves drafts, validates with linked focus, and guards dirty navigation."
    requirement: WEB-02
    verification:
      - kind: automated_ui
        ref: "apps/web/src/features/tasks/task-editor.test.tsx#canonical task editor"
        status: pass
      - kind: e2e
        ref: "pnpm --filter @keepling/web test:e2e (3 real-stack tests)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Task content stays plain text and title/notes fields are bounded without introducing temporal controls or diagnostic content leakage."
    requirement: SRV-02
    verification:
      - kind: automated_ui
        ref: "apps/web/src/features/tasks/task-editor.test.tsx#renders task title and notes as plain text without creating hostile markup"
        status: pass
      - kind: unit
        ref: "apps/server/test/keepling/domain/edit_task_test.exs#title is trimmed, notes are preserved, and validation is versioned"
        status: pass
    human_judgment: false

duration: 16min
completed: 2026-08-30
status: complete
---

# Phase KPL-01 Plan 09: Trustworthy Task Editing and Inbox Clarification Summary

**Versioned touched-field title/notes commands with PostgreSQL-owned rebase and a single routed React editor that clarifies Inbox tasks only after exact acknowledgement**

## Performance

- **Duration:** 16 min
- **Started:** 2026-08-31T03:40:00Z
- **Completed:** 2026-08-31T03:55:55Z
- **Tasks:** 2
- **Files modified:** 15

## Accomplishments

- Added pure edit, clarify, and return-to-Inbox decisions with versioned title/notes normalization, touched-field three-way merge, exact changed-field activity, and no temporal-field overlap with Plan 01-12.
- Extended the account-scoped transaction kernel, migration, Phoenix controller/routes, OpenAPI, generated types, and storage-neutral vectors so accepted effects, conflicts, and exact mutation results remain atomic and replayable.
- Added one `/tasks/:id` editor for wide detail and narrow full-page layouts with explicit Save/Cancel, Inbox-only Save & move, keyboard submission/cancellation, field-preserving validation, dirty navigation recovery, fixed mutation identity, and acknowledgement-before-removal.
- Proved plain-text hostile content, migration rollback/forward, the full 41-test server suite, 14 browser component tests, contract drift, lint, typecheck, production build, and the 3-test real PostgreSQL/Phoenix/Chromium suite.

## Task Commits

Each TDD task was committed with explicit RED and GREEN gates:

1. **Task 1 RED: Add failing edit semantics proof** - `80d16f1` (test)
2. **Task 1 GREEN: Implement edit and Inbox semantics** - `31c07a1` (feat)
3. **Task 2 RED: Add failing routed editor proof** - `f79416e` (test)
4. **Task 2 GREEN: Route explicit task editing** - `a445435` (feat)

## Files Created/Modified

- `apps/server/lib/keepling/domain/task.ex` - Pure version-1 detail bounds, touched-field merge, explicit clarification, and return semantics.
- `apps/server/lib/keepling/application/commands.ex` and `apps/server/lib/keepling/adapters/postgres/command_store.ex` - Shared semantic dispatch, account-scoped row locking, stable receipts/conflicts, exact snapshots, and activity persistence.
- `apps/server/lib/keepling_web/controllers/command_controller.ex` and `apps/server/lib/keepling_web/router.ex` - Closed edit/clarify/return DTO decoding and authenticated semantic routes.
- `apps/server/priv/repo/migrations/20260830000300_add_task_details.exs` - Reversible notes expansion, explicit Inbox-state expansion, and versioned database bounds.
- `packages/contracts/openapi/keepling.yaml`, `packages/contracts/generated/keepling.ts`, and `packages/contracts/vectors/editing.json` - Wire and behavior truth for detail edits, conflicts, and snapshots.
- `apps/web/src/api/keepling.ts` - Generated DTO-to-semantic facade mapping for edit, clarify, return, task snapshots, and exact acknowledgements.
- `apps/web/src/features/tasks/TaskEditor.tsx` and `apps/web/src/app/routes.tsx` - Canonical routed editor, validation/focus, dirty-navigation decisions, and honest command recovery.
- `apps/web/src/App.tsx` - Selectable Inbox rows plus acknowledgement-driven projection reconciliation.
- Focused ExUnit and Testing Library suites - Domain/vector, PostgreSQL/Phoenix, routing, keyboard, focus, draft, acknowledgement, and hostile-content evidence.

## Decisions Made

- Kept the already-shipped capture title limit as detail-contract version 1 and resolved notes at 50000 scalar values, matching the phase research. Notes preserve outer whitespace and newlines because they are plain user-authored text.
- Represented updates with closed `fields` and `base_values` objects whose keys must match. This keeps untouched fields absent from the request and makes server-owned non-overlapping rebase inspectable.
- Modeled clarification as the same atomic detail decision plus an explicit `inbox_state` transition. Ordinary Save cannot accidentally process Inbox, and date/project/tag changes remain unable to do so later.
- Kept browser draft and submission state separate from generated DTOs. The editor creates mutation identity before delivery and retains it through authentication interruption and result lookup.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Wired Inbox rows and acknowledgement reconciliation into the existing application composition root**
- **Found during:** Task 2 route composition
- **Issue:** The plan's browser file list omitted `apps/web/src/App.tsx`; without a selectable Inbox row and acknowledgement callback, `/tasks/:id` would be technically routable but unreachable from the product, and clarification would leave a stale row visible.
- **Fix:** Linked each stable task identity to the canonical route and reconciled ordinary edits or clarification only from the exact acknowledged snapshot.
- **Files modified:** `apps/web/src/App.tsx`
- **Verification:** Full 14-test browser suite, production build, and real-stack Playwright suite pass.
- **Committed in:** `a445435`

---

**Total deviations:** 1 auto-fixed (1 Rule 2 missing critical integration)
**Impact on plan:** The change was required to make the planned editor reachable and its Inbox-removal claim honest; it introduced no new dependency, endpoint, or state authority.

## Issues Encountered

- The plan's focused server command initially lacked the required test database environment. Execution used a disposable PostgreSQL 18.6 database selected through the repository runtime preflight, then proved the migration down/up path and the complete server suite.
- Dirty navigation driven by the editor's own acknowledged route change initially shared the same `popstate` guard as user navigation. A one-use internal navigation allowance now prevents the guard from reopening after an exact acknowledgement while keeping Back and same-origin link interception active for unsaved work.

## TDD Gate Compliance

- Task 1 RED commit `80d16f1` failed because the task aggregate had no notes field or edit semantics; GREEN commit `31c07a1` made the vector, domain, PostgreSQL, Phoenix, migration, and contract evidence pass.
- Task 2 RED commit `f79416e` failed because the canonical `TaskEditor` did not exist; GREEN commit `a445435` made all routed editor, validation, focus, dirty-navigation, acknowledgement, and hostile-content tests pass.
- No separate refactor commits were necessary.

## Known Stubs

None - no TODO, FIXME, skipped test, mock production data source, placeholder implementation, or empty rendered data seam remains in the changed files. Local empty objects in `TaskEditor` are transient accumulators for touched fields and validation errors, not UI data stubs.

## Threat Surface

- T-KPL01-18 is mitigated by authenticated account scope, CSRF/origin enforcement, closed DTO keys, positive expected revisions, locked task reads, matching touched/base keys, pure server merge rules, database constraints, and replay-stable conflict receipts.
- T-KPL01-19 is mitigated by plain-text inputs/rendering, hostile-markup component proof, exact changed-field activity only, and the existing privacy-safe telemetry boundary; no raw task content is logged by the new path.
- T-KPL01-20 is mitigated by versioned 512/50000 scalar bounds in domain, OpenAPI, browser fields, vectors, and PostgreSQL constraints plus the existing bounded Plug parser.
- No security-relevant surface outside the plan's threat model was introduced.

## Verification Evidence

- `mix test test/keepling/domain/edit_task_test.exs test/keepling/adapters/postgres/idempotency_test.exs`: 8/8 passed against disposable PostgreSQL.
- `mix test`: 41/41 server tests passed with warnings-as-errors compilation.
- Migration `20260830000300` down then up: passed against disposable PostgreSQL 18.6.
- `pnpm contracts:check`: OpenAPI and checked-in generated TypeScript agree.
- `pnpm --filter @keepling/web test --run src/features/tasks/task-editor.test.tsx`: 6/6 passed.
- `pnpm --filter @keepling/web test --run`: 14/14 passed.
- `pnpm --filter @keepling/web typecheck`, `lint`, and `build`: all passed; Vite transformed 58 modules.
- `tooling/check-repository-integrity.sh`: passed.
- `pnpm --filter @keepling/web test:e2e`: 3/3 existing real-stack PostgreSQL/Phoenix/Chromium tests passed.

## User Setup Required

None. The migration runs through the existing release migration path and no dependency or external service was added.

## Next Phase Readiness

- Plan 01-10 can extend the same touched-field/base-value contract to stable project and tag identities without changing Inbox semantics.
- Plan 01-11 can render the exact `task_details_updated`, `task_clarified`, and `task_returned_to_inbox` activities already persisted here.
- Plan 01-12 retains sole ownership of planned/deadline storage and controls; this plan introduced no temporal field.
- No high-severity mitigation assigned to Plan 01-09 remains open.

## Self-Check: PASSED

- All five created implementation/test/vector/migration artifacts and the canonical summary exist on disk.
- Task commits `80d16f1`, `31c07a1`, `f79416e`, and `a445435` exist in Git history.
- Coverage metadata classifies all four deliverables as fully automated with no schema errors.
- Required actuals, requirements, TDD evidence, stub scan, threat mitigations, migration proof, and fresh executable verification are present.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-30*
