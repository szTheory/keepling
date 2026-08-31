---
phase: KPL-01-one-trustworthy-task
plan: 12
subsystem: canonical-task-temporal-model
tags: [elixir, phoenix, postgresql, civil-date, timezone, openapi, react, typescript]

requires:
  - phase: KPL-01-11
    provides: Canonical accepted task activity, exact acknowledgements, and account-timezone presentation seam
provides:
  - Separate nullable planned and deadline civil dates with deterministic account-day classification
  - Revision-safe edit, plan-for-Today, and unplan commands across domain, PostgreSQL, Phoenix, and generated contracts
  - Explicit Quick Capture Today intent and accessible browser date editing with exact acknowledgement reconciliation
affects: [KPL-01-13, KPL-01-16, KPL-01-17, sync, mcp, desktop-offline, iphone-offline]

actuals:
  tokens: 27578
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns: [server-resolved account day, independent civil-date fields, semantic command composition, exact multi-command acknowledgement chaining]

key-files:
  created:
    - apps/server/lib/keepling/domain/task_dates.ex
    - apps/server/priv/repo/migrations/20260830000600_add_task_dates.exs
    - apps/server/test/keepling/domain/task_dates_test.exs
    - packages/contracts/vectors/task-dates.json
  modified:
    - apps/server/lib/keepling/domain/task.ex
    - apps/server/lib/keepling/application/commands.ex
    - apps/server/lib/keepling/adapters/postgres/command_store.ex
    - apps/server/lib/keepling_web/controllers/command_controller.ex
    - apps/server/lib/keepling_web/router.ex
    - packages/contracts/openapi/keepling.yaml
    - packages/contracts/generated/keepling.ts
    - apps/web/src/api/keepling.ts
    - apps/web/src/features/capture/QuickCapture.tsx
    - apps/web/src/features/tasks/TaskEditor.tsx
    - apps/web/src/features/tasks/task-editor.test.tsx

key-decisions:
  - "Planned placement and deadline remain independent nullable civil dates; Today intent changes only planned_on and a planned-after-deadline combination is accepted with an exact non-blocking warning."
  - "The server resolves Plan for Today from the validated account IANA timezone and an injected acceptance instant; stored civil dates remain unchanged by later timezone changes."
  - "Active unfinished task classification preserves every applicable planned and deadline reason while deriving Today and Upcoming membership from the canonical account day."
  - "Browser flows compose semantic commands with stable identities and acknowledged revisions, retaining the draft until the terminal command returns its exact receipt."

patterns-established:
  - "Temporal truth: compare ISO civil dates only after validating them, and resolve relative intent such as Today exclusively at the server acceptance boundary."
  - "Composed mutations: create the next command only from the prior exact acknowledgement, persist its identity through retry/status checks, and reconcile the UI only after the terminal receipt."

requirements-completed: [GTD-02, GTD-03, GTD-04, SRV-02, SRV-03, WEB-01, WEB-02]

coverage:
  - id: D1
    description: "Nullable planned_on and deadline_on round-trip independently through domain state, PostgreSQL, Phoenix, OpenAPI, generated TypeScript, and storage-neutral vectors."
    requirement: GTD-02
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/domain/task_dates_test.exs"
        status: pass
      - kind: integration
        ref: "packages/contracts/vectors/task-dates.json and pnpm contracts:check"
        status: pass
    human_judgment: false
  - id: D2
    description: "Plan for Today resolves the account day at acceptance using the canonical account timezone and injected instant, including DST boundaries without rewriting stored dates."
    requirement: GTD-03
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/domain/task_dates_test.exs#account day is deterministic across timezone and DST boundaries"
        status: pass
    human_judgment: false
  - id: D3
    description: "Past, equal, future, combined, and planned-after-deadline states preserve independent reasons and the exact accepted warning."
    requirement: GTD-04
    verification:
      - kind: unit
        ref: "apps/server/test/keepling/domain/task_dates_test.exs"
        status: pass
      - kind: integration
        ref: "packages/contracts/vectors/task-dates.json"
        status: pass
    human_judgment: false
  - id: D4
    description: "Quick Capture visibly defaults to Inbox, optionally chains a semantic Today command, and clears only after its exact terminal acknowledgement."
    requirement: WEB-01
    verification:
      - kind: automated_ui
        ref: "apps/web/src/features/tasks/task-editor.test.tsx#keeps Inbox explicit and plans an opted-in capture only after exact capture acknowledgement"
        status: pass
    human_judgment: false
  - id: D5
    description: "TaskEditor exposes separate planned and deadline fields, canonical timezone help, invalid civil-date preservation, warning copy, and revision-safe detail/date command composition."
    requirement: WEB-02
    verification:
      - kind: automated_ui
        ref: "apps/web/src/features/tasks/task-editor.test.tsx"
        status: pass
      - kind: e2e
        ref: "pnpm --filter @keepling/web test:e2e"
        status: pass
    human_judgment: false

duration: 22min
completed: 2026-08-31
status: complete
---

# Phase KPL-01 Plan 12: Canonical Task Dates and Today Intent Summary

**Server-resolved account-day semantics with independent planned/deadline civil dates, revision-safe semantic commands, and acknowledgement-gated Today and editor flows**

## Performance

- **Duration:** 22 min
- **Started:** 2026-08-31T04:54:48Z
- **Completed:** 2026-08-31T05:16:41Z
- **Tasks:** 2
- **Files modified:** 15

## Accomplishments

- Added the single Phase 1 temporal model and migration for independent nullable `planned_on` and `deadline_on` civil dates, with pure edit, Today, unplan, account-day, classification, reason-preservation, and warning behavior.
- Persisted temporal changes atomically with revision checks, receipts, canonical activity, and Today/Upcoming projection revision advancement; exposed closed authenticated Phoenix commands and exact snapshots/warnings.
- Expanded OpenAPI, checked-in generated TypeScript, and storage-neutral vectors with one closed temporal vocabulary and a complete account-day/date truth table.
- Added an explicit unchecked “Add to Today” option to Quick Capture. Capture remains an Inbox action, while opted-in Today placement is a second semantic command created from the exact capture acknowledgement and cleared only after the terminal receipt.
- Added separate planned and deadline editor fields, canonical account-timezone help, real civil-date validation that preserves invalid typed text, non-blocking planned-after-deadline copy, and exact detail-to-date revision chaining.
- Proved the complete boundary with 61 server tests, a reversible PostgreSQL 18.6 migration, contract drift/vector checks, 26 browser component tests, lint, typecheck, production build, repository integrity, and 3 real-stack Chromium tests.

## Task Commits

Each TDD task was committed with explicit RED and GREEN gates:

1. **Task 1 RED: Add failing temporal model proof** - `63dccd2` (test)
2. **Task 1 GREEN: Expose canonical task dates** - `4148236` (feat)
3. **Task 2 RED: Add failing task date UI proof** - `78861d6` (test)
4. **Task 2 GREEN: Compose Today intent and task dates** - `edc07a8` (feat)

## Files Created/Modified

- `apps/server/lib/keepling/domain/task_dates.ex` and `apps/server/lib/keepling/domain/task.ex` - Storage-independent civil-date editing, Today resolution, unplanning, truth classification, and canonical aggregate fields.
- `apps/server/lib/keepling/application/commands.ex` and `apps/server/lib/keepling/adapters/postgres/command_store.ex` - Semantic dispatch plus account-scoped, revision-checked, atomic temporal persistence, receipts, activity, and projection changes.
- `apps/server/lib/keepling_web/controllers/command_controller.ex` and `apps/server/lib/keepling_web/router.ex` - Closed authenticated edit-dates, plan-for-Today, and unplan command endpoints.
- `apps/server/priv/repo/migrations/20260830000600_add_task_dates.exs` - Reversible nullable date-column expansion with no competing canonical storage.
- `packages/contracts/openapi/keepling.yaml`, `packages/contracts/generated/keepling.ts`, and `packages/contracts/vectors/task-dates.json` - Shared closed date command/snapshot schemas and complete portable examples.
- `apps/web/src/api/keepling.ts` - Generated DTO mapping and semantic date/Today/unplan command facade.
- `apps/web/src/features/capture/QuickCapture.tsx` - Explicit Inbox destination, default-off Today intent, stable two-command delivery, recovery, and terminal acknowledgement reconciliation.
- `apps/web/src/features/tasks/TaskEditor.tsx` - Separate date drafts, account-zone help, civil-date validation, warning, dirty-navigation protection, and revision-safe multi-command composition.
- Focused ExUnit and Testing Library suites - DST/account-day boundaries, date truth table, persistence and HTTP round trips, exact warning/activity, capture sequencing, field semantics, invalid draft preservation, and acknowledged revision chaining.

## Decisions Made

- Treated planned placement, Today intent, and deadline as deliberately different concepts. Today is not inferred from deadline, and neither editing nor unplanning silently changes the other date.
- Resolved account-relative Today only on the server from the configured IANA zone and injected instant. Clients never send a proposed Today date, and timezone changes do not reinterpret stored civil dates.
- Preserved every due/planned reason in classification rather than collapsing combined states to a single explanation. Upcoming remains a separate derived membership from Today.
- Composed browser operations as multiple semantic commands instead of broad patches. Every later command uses the previous receipt revision, and user-visible completion waits for the final exact acknowledgement.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] Added canonical aggregate date fields**
- **Found during:** Task 1
- **Issue:** The plan named the temporal domain module and storage boundary but omitted `apps/server/lib/keepling/domain/task.ex` from its file list; without nullable aggregate fields, dates could not round-trip through the canonical task representation.
- **Fix:** Added separate nullable `planned_on` and `deadline_on` fields to the domain task struct without introducing transport or persistence dependencies.
- **Files modified:** `apps/server/lib/keepling/domain/task.ex`
- **Commit:** `4148236`

## Issues Encountered

- The Task 2 green run correctly required older editor tests to answer the newly consumed canonical account-timezone read. Their mocks were expanded to return the existing activity-page timezone without weakening production behavior.
- Civil-date validation renders the same actionable message in the linked summary and inline field help. The proof now intentionally asserts both accessible instances while retaining first-invalid-field focus.
- Final server verification used a disposable PostgreSQL 18.6 cluster, explicit test database URL and throwaway signing secret through the pinned runtime wrapper, then shut down and removed only that temporary cluster.

## TDD Gate Compliance

- Task 1 RED commit `63dccd2` failed because the pure date model, migration, commands, persistence, Phoenix transport, generated contract, and vectors did not exist; GREEN commit `4148236` made the full server/contract boundary pass.
- Task 2 RED commit `78861d6` retained all six existing passing editor cases while failing exactly three missing behaviors: Add to Today, separate date controls, and invalid civil-date preservation. GREEN commit `edc07a8` made those cases plus revision-chaining coverage pass.
- No separate refactor commit was necessary. Both RED commits precede their matching GREEN commits in Git history.

## Known Stubs

None - no TODO, FIXME, skipped test, mock production data source, hardcoded empty rendered data, or placeholder implementation remains in the 15 changed files. `YYYY-MM-DD` placeholders are intentional input-format guidance; empty maps/lists are typed command accumulators, conflict checks, or tests rather than product stubs.

## Threat Surface

- T-KPL01-25 is mitigated by server-owned validated account timezone, an injected acceptance instant, strict closed civil-date validation, client omission of a proposed Today date, and DST/account-day vectors and tests.
- T-KPL01-26 is mitigated by exact mutation identity, expected revision, base values, snapshot, structured warning, canonical activity, terminal-receipt reconciliation, and stable status checks for uncertain delivery.
- No security-relevant endpoint, authentication path, file access pattern, or trust-boundary schema outside the plan threat model was introduced.

## Verification Evidence

- Disposable PostgreSQL 18.6 migration `20260830000600` down one step then up: passed.
- `mix format --check-formatted`, `MIX_ENV=test mix compile --warnings-as-errors`, and `MIX_ENV=test mix test`: 61/61 server tests passed through the pinned runtime preflight.
- `pnpm contracts:check` and `jq empty packages/contracts/vectors/task-dates.json`: OpenAPI/generated TypeScript drift and vector syntax checks passed.
- `pnpm --filter @keepling/web test`: 4 files and 26/26 browser component tests passed, including all 10 focused TaskEditor/QuickCapture cases.
- `pnpm --filter @keepling/web lint`, `typecheck`, and `build`: passed; Vite transformed 60 modules.
- `tooling/check-repository-integrity.sh`: passed with no nested repository or planning root.
- `pnpm --filter @keepling/web test:e2e`: 3/3 real PostgreSQL/Phoenix/Chromium tests passed.

## User Setup Required

None. No dependency, credential, external service, or manual data migration was added.

## Next Phase Readiness

- Plan 01-13 can build Today and Upcoming reads from the canonical classification and projection revisions without redefining temporal semantics or wire shape.
- Later desktop/iPhone outboxes can use the versioned semantic commands, base values, stable mutation identities, and exact acknowledgements without treating transport delivery as success.
- No high-severity mitigation assigned to Plan 01-12 remains open.

## Self-Check: PASSED

- All 15 realized implementation, migration, contract, vector, facade, UI, and test files exist on disk.
- TDD commits `63dccd2`, `4148236`, `78861d6`, and `edc07a8` exist in Git history in RED/GREEN order.
- Required actuals, requirements, stub scan, threat mitigations, deviation record, migration reversal, and fresh cross-boundary verification are present.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-31*
