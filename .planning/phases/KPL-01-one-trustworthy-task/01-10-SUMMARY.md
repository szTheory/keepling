---
phase: KPL-01-one-trustworthy-task
plan: 10
subsystem: stable-organization-management
tags: [elixir, phoenix, postgresql, openapi, react, typescript, accessibility]

requires:
  - phase: KPL-01-09
    provides: Versioned task snapshots, account-scoped semantic command receipts, and the routed browser task editor
provides:
  - Stable account-scoped project and tag identities with rename, archive, unarchive, and collision semantics
  - Atomic project/tag assignment through the shared domain, PostgreSQL, Phoenix, and generated-contract boundaries
  - Accessible routed browser management and assignment controls that preserve archived historical labels
affects: [KPL-01-11, KPL-01-12, KPL-01-16, KPL-01-17, organization-contracts, browser-task-management]

actuals:
  tokens: 35018
  tasks: 2
  commits: 5

tech-stack:
  added: []
  patterns: [stable opaque organization IDs, versioned Unicode name keys, typed composite foreign keys, acknowledgement-safe assignment forms]

key-files:
  created:
    - apps/server/lib/keepling/domain/organization.ex
    - apps/server/priv/repo/migrations/20260830000400_add_organizations.exs
    - apps/server/test/keepling/domain/organization_test.exs
    - packages/contracts/vectors/organizations.json
    - apps/web/src/features/organizations/OrganizationFields.tsx
    - apps/web/src/features/organizations/organization-fields.test.tsx
  modified:
    - apps/server/lib/keepling/application/commands.ex
    - apps/server/lib/keepling/adapters/postgres/command_store.ex
    - apps/server/lib/keepling_web/controllers/command_controller.ex
    - apps/server/lib/keepling_web/router.ex
    - packages/contracts/openapi/keepling.yaml
    - packages/contracts/generated/keepling.ts
    - apps/web/src/api/keepling.ts
    - apps/web/src/app/routes.tsx

key-decisions:
  - "Projects and tags use caller-created opaque IDs; display names may change while a versioned NFC/trim/casefold name key enforces active account-and-kind uniqueness."
  - "Task assignment commands submit only project and tag IDs plus matching base values; the locked server snapshot owns validation, narrow merge, revision advancement, and exact acknowledgement."
  - "Archived organizations remain hydrated in historical task snapshots and removable from assignment forms, but cannot receive new assignments; project archive additionally blocks while unfinished tasks reference it."
  - "Account scope is represented in every organization and assignment persistence key, predicate, receipt, and composite foreign key instead of being inferred from an opaque identifier."

patterns-established:
  - "Stable reference data: mutable display labels are projected from account-scoped stable IDs and never copied into task canonical state."
  - "Typed relational ownership: project and tag discriminators participate in PostgreSQL composite foreign keys so a tag cannot occupy a project slot or vice versa."
  - "Archived-history UI: assigned archived values stay visible and removable, while archived unassigned values are absent from new-choice controls."

requirements-completed: [GTD-02, SRV-02, SRV-03, WEB-01, WEB-02]

coverage:
  - id: D1
    description: "Project and tag creation, rename, archive, unarchive, collision, and normalization preserve stable identities under versioned business rules."
    requirement: GTD-02
    verification:
      - kind: unit
        ref: "apps/server/test/keepling/domain/organization_test.exs#names are normalized with stable identities and versioned constraints"
        status: pass
      - kind: integration
        ref: "apps/server/test/keepling/domain/organization_test.exs#rename, archive, unarchive, and blocker semantics cross Phoenix and PostgreSQL"
        status: pass
    human_judgment: false
  - id: D2
    description: "Organization reads, writes, receipts, and task assignments remain account-scoped and reject cross-account, stale, future-revision, wrong-kind, archived-new-assignment, and malformed requests."
    requirement: SRV-03
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/domain/organization_test.exs#cross-account organization and receipt access is isolated"
        status: pass
      - kind: integration
        ref: "apps/server/test/keepling/domain/organization_test.exs#task organization assignment rejects stale and future revisions with replay-stable results"
        status: pass
    human_judgment: false
  - id: D3
    description: "PostgreSQL persists typed stable references and task snapshots hydrate current and archived names without rewriting or revising tasks when a label changes."
    requirement: SRV-02
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/domain/organization_test.exs#organization rename projects through task snapshots without task revision advancement"
        status: pass
      - kind: integration
        ref: "20260830000400 migration down/up against disposable PostgreSQL 18.6"
        status: pass
    human_judgment: false
  - id: D4
    description: "Projects, tags, and task assignment are reachable as routed accessible native forms that submit stable IDs and update only after exact acknowledgement."
    requirement: WEB-02
    verification:
      - kind: automated_ui
        ref: "apps/web/src/features/organizations/organization-fields.test.tsx"
        status: pass
      - kind: other
        ref: "pnpm typecheck:web, lint:web, and build:web"
        status: pass
    human_judgment: false

duration: 23min
completed: 2026-08-31
status: complete
---

# Phase KPL-01 Plan 10: Stable-ID Project and Tag Management Summary

**Account-scoped stable project/tag identities with typed PostgreSQL references, replay-safe semantic assignment, and accessible routed React management controls**

## Performance

- **Duration:** 23 min
- **Started:** 2026-08-31T04:01:02Z
- **Completed:** 2026-08-31T04:24:29Z
- **Tasks:** 2
- **Files modified:** 14

## Accomplishments

- Added pure project/tag creation, rename, archive, unarchive, and task-assignment decisions with opaque stable IDs, versioned Unicode name normalization, deterministic tag ordering, narrow three-way merge, and explicit conflict/problem results.
- Added reversible PostgreSQL storage with account-and-kind composite keys, active-name uniqueness, typed task project and tag foreign keys, transaction-scoped validation, exact command receipts, and snapshots that resolve renamed or archived labels without rewriting task history.
- Extended Phoenix routes, closed request decoders, OpenAPI, generated TypeScript, and storage-neutral vectors so every write carries IDs rather than display names and every accepted mutation returns its exact identity and resulting snapshot.
- Added native Project select/tag checkbox assignment controls plus `/projects` and `/tags` management forms with inline rename, exact archive confirmation, project blocker feedback, unarchive collision handling, fixed assignment identities, linked errors, and 44px interaction targets.
- Proved normalization, stable rename, blocker and archived-history behavior, cross-account isolation, stale/future revision handling, contract drift, the 48-test server suite, 18 browser component tests, typecheck, lint, production build, migration reversal, and the existing 3-test real-stack browser suite.

## Task Commits

Each TDD task was committed with explicit RED and GREEN gates; the plan-wide revision audit produced one additional focused bug-fix commit:

1. **Task 1 RED: Add failing organization semantics proof** - `e09f462` (test)
2. **Task 1 GREEN: Implement stable organization commands** - `28635d5` (feat)
3. **Task 2 RED: Add failing organization UI proof** - `c2e3848` (test)
4. **Task 2 GREEN: Route stable organization assignment** - `782acff` (feat)
5. **Plan verification fix: Reject future assignment revisions** - `8129e1b` (fix)

## Files Created/Modified

- `apps/server/lib/keepling/domain/organization.ex` - Stable project/tag rules, versioned display-name normalization, archive decisions, and narrow assignment merge.
- `apps/server/lib/keepling/application/commands.ex` and `apps/server/lib/keepling/adapters/postgres/command_store.ex` - Shared semantic dispatch, account-scoped locks and receipts, relational validation, exact acknowledgements, and hydrated task snapshots.
- `apps/server/lib/keepling_web/controllers/command_controller.ex` and `apps/server/lib/keepling_web/router.ex` - Authenticated organization listing and closed create/rename/archive/unarchive/assignment command routes.
- `apps/server/priv/repo/migrations/20260830000400_add_organizations.exs` - Reversible organization, task project, and task tag schema with active-name uniqueness and typed composite foreign keys.
- `packages/contracts/openapi/keepling.yaml`, `packages/contracts/generated/keepling.ts`, and `packages/contracts/vectors/organizations.json` - Wire and behavior truth for stable organizations, assignment requests, problems, mutation results, and enriched task snapshots.
- `apps/web/src/api/keepling.ts` - Generated DTO facade for organization management, assignment, named archived references, and exact mutation results.
- `apps/web/src/features/organizations/OrganizationFields.tsx` and `apps/web/src/app/routes.tsx` - Routed accessible management and assignment forms with acknowledgement-safe state transitions.
- Focused ExUnit and Testing Library suites - Pure semantics, PostgreSQL/Phoenix boundaries, account isolation, revision conflicts, stable IDs, archived history, collision feedback, route reachability, and accessible interaction evidence.

## Decisions Made

- Kept display labels separate from identity and uniqueness. Opaque project/tag IDs are stable; a version-1 normalized name key uses NFC, outer trimming, and Unicode casefolding for active uniqueness without changing the user-visible label.
- Stored `account_id` and organization kind in relational keys instead of trusting globally opaque IDs. Composite foreign keys make account ownership and project-versus-tag type enforceable at the database boundary.
- Kept assignments in the existing task revision stream. A command submits requested/base stable IDs and expected revision, then the pure domain merges only this narrow field group against a locked current snapshot.
- Kept archived assignments inspectable. Existing task snapshots continue to resolve their current display labels and archived status; UI controls permit removal but not a new assignment to an archived value.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Rejected task-assignment revisions ahead of the current server revision**
- **Found during:** Plan-wide revision-boundary audit after Task 2
- **Issue:** The narrow merge correctly rejected ordinary stale overlap, but a request with a future `expected_revision` could be accepted when its base assignments matched the current state.
- **Fix:** Added an explicit future-revision conflict before merge evaluation and a Phoenix/PostgreSQL regression assertion proving the task remains unchanged.
- **Files modified:** `apps/server/lib/keepling/domain/organization.ex`, `apps/server/test/keepling/domain/organization_test.exs`
- **Verification:** Focused organization suite 7/7, complete server suite 48/48, and contract drift check pass.
- **Committed in:** `8129e1b`

---

**Total deviations:** 1 auto-fixed (1 Rule 1 bug)
**Impact on plan:** The fix closes a required revision boundary without changing the architecture, contract shape, or dependency set.

## Issues Encountered

- The server integration suite requires an explicit database URL and secret key base. Execution used a disposable PostgreSQL 18.6 database selected by the repository runtime preflight, ran the migration down/up proof, and removed no project or user data.
- A final verification invocation initially called `mise`, which is not installed on the execution PATH. No test ran or project file changed in that attempt; the repository-owned `runtime-preflight.sh --exec` selector then ran every check with pinned Elixir 1.20.2, OTP 29.0.5, PostgreSQL 18.6, Node 22.14.0, and pnpm 10.33.0.

## TDD Gate Compliance

- Task 1 RED commit `e09f462` failed because organization semantics, routes, schema, contracts, and vectors did not exist; GREEN commit `28635d5` made the complete stable-identity boundary pass.
- Task 2 RED commit `c2e3848` failed because the routed organization fields and management UI did not exist; GREEN commit `782acff` made the stable-ID, archive, collision, acknowledgement, and routing proof pass.
- Plan verification added a failing future-revision assertion before commit `8129e1b` fixed it. No separate refactor commit was necessary.

## Known Stubs

None - no TODO, FIXME, skipped test, placeholder implementation, mock production data source, or empty rendered data seam remains in the changed files. Empty arrays and maps in the organization UI and adapter are real initial collection/accumulator states populated from the API, not hardcoded UI data.

## Threat Surface

- T-KPL01-21 is mitigated by caller-stable opaque IDs, closed versioned schemas, normalized active-name uniqueness, positive revision validation, exact mutation fingerprints, and server-owned assignment decisions.
- T-KPL01-22 is mitigated by authenticated account predicates on every organization/task/receipt query, composite ownership foreign keys, kind discriminators, cross-account integration proof, and privacy-safe problem results.
- No security-relevant endpoint, authentication path, file access pattern, or trust-boundary schema outside the plan threat model was introduced.

## Verification Evidence

- `runtime-preflight.sh --exec -- sh -c 'cd apps/server && MIX_ENV=test mix format --check-formatted && mix test'`: 48/48 server tests passed against disposable PostgreSQL 18.6.
- `mix test test/keepling/domain/organization_test.exs`: 7/7 focused organization domain, PostgreSQL, Phoenix, isolation, and revision tests passed.
- Migration `20260830000400` down then up: passed against disposable PostgreSQL 18.6.
- `pnpm contracts:check`: OpenAPI and checked-in generated TypeScript agree.
- `pnpm --filter @keepling/web test`: 3 files and 18/18 browser component tests passed.
- `pnpm typecheck:web`, `pnpm lint:web`, and `pnpm build:web`: all passed; Vite transformed 59 modules.
- `tooling/check-repository-integrity.sh`: passed with no nested repository or planning root.
- `pnpm --filter @keepling/web test:e2e`: 3/3 existing real PostgreSQL/Phoenix/Chromium tests passed.

## User Setup Required

None. The migration runs through the existing release migration path and no dependency, credential, or external service was added.

## Next Phase Readiness

- Plan 01-11 can render the stable organization and assignment activities/labels persisted through the shared command stream.
- Plan 01-12 can add planned/deadline semantics without coupling temporal fields to project/tag identity or assignment.
- Plan 01-17 can reuse fixed mutation identities and result lookup for unknown-delivery management actions.
- No high-severity mitigation assigned to Plan 01-10 remains open.

## Self-Check: PASSED

- All six created implementation/test/vector/migration artifacts and the canonical summary exist on disk.
- Task commits `e09f462`, `28635d5`, `c2e3848`, `782acff`, and `8129e1b` exist in Git history.
- Coverage metadata classifies all four deliverables as fully automated with no schema errors.
- Required actuals, requirements, TDD evidence, stub scan, threat mitigations, migration proof, and fresh executable verification are present.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-31*
