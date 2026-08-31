---
phase: KPL-01-one-trustworthy-task
plan: 16
subsystem: conflict-resolution
tags: [elixir, phoenix, postgresql, openapi, react, accessibility, idempotency, semantic-merge]

requires:
  - phase: KPL-01-15
    provides: Exact-revision task lifecycle commands, durable receipts/activity, retained canonical task rows, and acknowledgement-gated browser reconciliation
provides:
  - Pure closed three-way detail merge with invariant rerun and committed affected-field conflict truth
  - Account-scoped revision-aware explicit resolution with fresh identities, stable replay, and auditable linkage
  - Route-reachable accessible inline resolver that preserves drafts, renders values as text, and retries exact submissions honestly
affects: [KPL-01-17, sync, mcp, desktop-offline, iphone-offline, undo]

actuals:
  tokens: 20242
  tasks: 2
  commits: 5

tech-stack:
  added: []
  patterns: [server-owned narrow semantic merge, committed conflict result, fresh-identity explicit resolution, acknowledgement-gated conflict reconciliation]

key-files:
  created:
    - apps/server/lib/keepling/domain/merge.ex
    - apps/server/priv/repo/migrations/20260830000800_add_persisted_conflicts.exs
    - apps/server/test/keepling/adapters/postgres/conflict_test.exs
    - packages/contracts/vectors/conflicts.json
    - apps/web/src/features/tasks/ConflictResolver.tsx
    - apps/web/src/features/tasks/conflict-resolver.test.tsx
  modified:
    - apps/server/lib/keepling/domain/task.ex
    - apps/server/lib/keepling/application/commands.ex
    - apps/server/lib/keepling/adapters/postgres/command_store.ex
    - apps/server/lib/keepling_web/controllers/command_controller.ex
    - apps/server/lib/keepling_web/router.ex
    - packages/contracts/openapi/keepling.yaml
    - packages/contracts/generated/keepling.ts
    - apps/web/src/api/keepling.ts
    - apps/web/src/features/tasks/TaskEditor.tsx

key-decisions:
  - "A detail field rebases only when canonical truth still equals the submitted base or already equals the requested value; all merge rules and invariant checks remain server/domain-owned."
  - "Unmergeable results are committed account-scoped conflict rows linked to the original receipt; replay returns the same conflict, while resolution uses a fresh mutation identity against the stored latest revision."
  - "The browser submits only closed mine/current selections, retains the exact resolution body through uncertainty, and reconciles only an acknowledgement matching mutation, task, and conflict identities."

patterns-established:
  - "Committed conflict truth: persist base/requested/current affected-field values in the same transaction as the terminal conflict receipt, then replay that stable result rather than recomputing it."
  - "Resolver continuity: preserve unaffected drafts and focus, render hostile values as text, and expose pending, authentication, unknown, stale, and generic failure states without optimistic overwrite."

requirements-completed: [SRV-03, WEB-02, QUAL-01]

coverage:
  - id: D1
    description: "Disjoint task-detail edits merge narrowly, while overlapping and lifecycle-incompatible edits persist a stable affected-field conflict without applying the losing draft."
    requirement: SRV-03
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/adapters/postgres/conflict_test.exs"
        status: pass
      - kind: other
        ref: "packages/contracts/vectors/conflicts.json"
        status: pass
    human_judgment: false
  - id: D2
    description: "Explicit resolution is latest-revision-aware, account-scoped, idempotent, auditable, and carried through the shared application, PostgreSQL, Phoenix, OpenAPI, and generated-client boundaries."
    requirement: SRV-03
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/adapters/postgres/conflict_test.exs#overlap persists one stable conflict and explicit resolution uses a fresh identity"
        status: pass
      - kind: integration
        ref: "apps/server/test/keepling/adapters/postgres/conflict_test.exs#stale and cross-account conflict resolution disclose and mutate nothing"
        status: pass
      - kind: other
        ref: "pnpm contracts:check"
        status: pass
    human_judgment: false
  - id: D3
    description: "The inline browser resolver shows only affected Your/Current values, keeps nonconflicting drafts, provides accessible six-line disclosure and non-color choices, restores focus, and retries exact identities honestly."
    requirement: WEB-02
    verification:
      - kind: automated_ui
        ref: "apps/web/src/features/tasks/conflict-resolver.test.tsx"
        status: pass
    human_judgment: false
  - id: D4
    description: "Conflict migrations, closed vectors, static checks, production artifacts, full suites, and the real PostgreSQL/Phoenix/Chromium stack pass together."
    requirement: QUAL-01
    verification:
      - kind: integration
        ref: "disposable PostgreSQL forward/rollback/forward migration proof"
        status: pass
      - kind: e2e
        ref: "pnpm --filter @keepling/web test:e2e"
        status: pass
      - kind: other
        ref: "pnpm test:phase-1"
        status: pass
    human_judgment: false

duration: 37min
completed: 2026-08-31
status: complete
---

# Phase KPL-01 Plan 16: Persisted Semantic Conflict Resolution Summary

**Committed narrow semantic conflicts with account-scoped revision-aware resolution and an accessible draft-preserving inline browser resolver**

## Performance

- **Duration:** 37 min
- **Started:** 2026-08-31T12:31:47Z
- **Completed:** 2026-08-31T13:08:27Z
- **Tasks:** 2
- **Files modified:** 15

## Accomplishments

- Added a pure closed three-way merge that safely rebases disjoint task-detail edits, reruns existing domain invariants, and turns overlaps or lifecycle incompatibility into structured affected-field decisions instead of overwrites.
- Persisted conflict base, requested, current, revision, command, account, task, receipt, and resolution linkage in PostgreSQL; original identities replay stable terminal conflicts, while fresh resolution identities are exact, idempotent, auditable, and account-scoped.
- Exposed a closed authenticated Phoenix/OpenAPI/generated contract that accepts only mine/current selections and always applies server-held values through the same application and domain rules.
- Composed an inline TaskEditor resolver that shows only affected values as text, preserves unaffected drafts, discloses long values accessibly, represents selection beyond color, restores predictable focus, and retains exact bodies through auth, unknown, stale, and error states.
- Proved the slice with dedicated conflict vectors, PostgreSQL interleavings, cross-account and route tests, browser interaction tests, reversible migration evidence, full server/browser/static/build lanes, and the real stack.

## Task Commits

Each planned TDD task has an explicit RED commit followed by its GREEN commit:

1. **Task 1 RED: Add failing persisted conflict proof** - `a980aec` (test)
2. **Task 1 GREEN: Persist and resolve semantic conflicts** - `dd73021` (feat)
3. **Task 2 RED: Add failing inline conflict resolver proof** - `bd6ad98` (test)
4. **Task 2 GREEN: Compose inline conflict resolution** - `edae65d` (feat)
5. **Post-task correction: Preserve empty clarify transitions** - `3e94ac0` (fix)

## Files Created/Modified

- `apps/server/lib/keepling/domain/merge.ex` and `apps/server/lib/keepling/domain/task.ex` - Pure closed merge decisions, lifecycle collision detection, invariant rerun, and explicit resolution application.
- `apps/server/lib/keepling/application/commands.ex` and `apps/server/lib/keepling/adapters/postgres/command_store.ex` - Shared dispatch, stable conflict receipt/row transaction, account-scoped locks, exact replay, resolution acknowledgement, and audit linkage.
- `apps/server/lib/keepling_web/controllers/command_controller.ex` and `apps/server/lib/keepling_web/router.ex` - Authenticated closed conflict-resolution decoding and problem/acknowledgement mapping.
- `apps/server/priv/repo/migrations/20260830000800_add_persisted_conflicts.exs` - Composite account/task/receipt integrity, closed command/field checks, revision checks, and complete resolution metadata.
- `apps/server/test/keepling/adapters/postgres/conflict_test.exs` and `packages/contracts/vectors/conflicts.json` - Storage-neutral decisions plus real interleaving, replay, lifecycle, account-scope, stale, and transport proof.
- `packages/contracts/openapi/keepling.yaml` and `packages/contracts/generated/keepling.ts` - Closed persisted-conflict, selection, resolution, problem, and acknowledgement schemas.
- `apps/web/src/api/keepling.ts` - Generated-contract facade mapping with exact resolution POST and typed persisted conflict/result identities.
- `apps/web/src/features/tasks/TaskEditor.tsx` and `apps/web/src/features/tasks/ConflictResolver.tsx` - Route-reachable inline composition, draft preservation, accessible choices/disclosure, recovery states, and focus reconciliation.
- `apps/web/src/features/tasks/conflict-resolver.test.tsx` - Hostile text, affected-only presentation, draft, selection, identity, acknowledgement, retry, stale, and focus evidence.

## Decisions Made

- Kept merge authority in `Keepling.Domain.Merge` and `Keepling.Domain.Task`. The browser never computes a patch or submits arbitrary replacement values; it chooses between the immutable values already held by the server conflict record.
- Stored every unmergeable outcome beside its original command receipt rather than reconstructing it later. This makes retry deterministic even if canonical task state advances after the original conflict.
- Required the stored latest revision for explicit resolution and locked the account-scoped conflict and task together. A stale resolver must review again; an opaque conflict ID from another account cannot disclose or mutate state.
- Preserved editor draft dates and unaffected detail fields during reconciliation. Only accepted title/notes truth is updated from the exact acknowledgement, so resolving one affected field cannot erase unrelated local work.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Normalized resolution selection keys before exact field comparison**
- **Found during:** Task 1 focused GREEN run
- **Issue:** Decoded selection keys arrived as strings while persisted affected fields were normalized as atoms, causing a valid closed resolution to return 422.
- **Fix:** Normalized closed selection keys before comparing them with persisted affected fields and applying server-held values.
- **Files modified:** `apps/server/lib/keepling/adapters/postgres/command_store.ex`
- **Verification:** Dedicated conflict suite passed 5/5, including fresh identity and exact replay.
- **Committed in:** `dd73021`

**2. [Rule 2 - Missing Critical Functionality] Persisted lifecycle-incompatible edit conflicts**
- **Found during:** Task 1 threat/coverage audit
- **Issue:** Detail overlap was covered, but Edit-versus-Trash also needed a committed conflict with truthful current lifecycle value and no losing-draft application to satisfy D-33..D-36.
- **Fix:** Added closed lifecycle conflict persistence, problem transport, contract field vocabulary, and a real Edit-versus-Trash interleaving proof.
- **Files modified:** `apps/server/lib/keepling/adapters/postgres/command_store.ex`, `packages/contracts/openapi/keepling.yaml`, `packages/contracts/generated/keepling.ts`, `apps/server/test/keepling/adapters/postgres/conflict_test.exs`
- **Verification:** Dedicated server suite passed 5/5 and contract drift passed.
- **Committed in:** `dd73021`

**3. [Rule 1 - Bug] Restored the closed activity-text contract after generation exposed accidental widening**
- **Found during:** Task 2 typecheck
- **Issue:** A Task 1 OpenAPI edit had also added lifecycle instant fields to `ActivityTextChange`, making the generated activity union incompatible with the browser's closed change model.
- **Fix:** Kept `completed_at` and `trashed_at` exclusively in `ActivityInstantChange`, regenerated TypeScript, and left the persisted-conflict field vocabulary separate.
- **Files modified:** `packages/contracts/openapi/keepling.yaml`, `packages/contracts/generated/keepling.ts`
- **Verification:** Contract drift, browser typecheck, lint, focused tests, full tests, and build passed.
- **Committed in:** `edae65d`

**4. [Rule 1 - Bug] Preserved lifecycle-only clarify behavior through the pure merge**
- **Found during:** Full server verification after both tasks
- **Issue:** The first pure merge required at least one detail field, so an existing valid clarify command with matched empty base/field maps returned `base_values_mismatch` before applying its Inbox lifecycle transition.
- **Fix:** Accepted equal empty closed maps as a no-detail merge while retaining Task.edit's existing touched-field guard and every key/field validation.
- **Files modified:** `apps/server/lib/keepling/domain/merge.ex`
- **Verification:** Combined domain/conflict tests passed 10/10 and the full server suite passed 80/80.
- **Committed in:** `3e94ac0`

---

**Total deviations:** 4 auto-fixed (3 Rule 1 bugs, 1 Rule 2 missing critical functionality)
**Impact on plan:** Every change was necessary for closed contract correctness, lifecycle collision safety, or backwards-compatible domain behavior; no unrelated feature or dependency was added.

## Issues Encountered

- The initial focused server verification used the production-style database variable and was rejected by Keepling's runtime guard. It was rerun with the required test-only variables and passed 5/5.
- A PostgreSQL test helper initially used unsupported `max(uuid)` aggregation. Reading the single scoped conflict row directly made the proof database-correct before GREEN.
- The first browser GREEN run used an exact multiline string matcher that Testing Library normalizes and asserted focus before deferred reconciliation. The proof was corrected to inspect exact `textContent`, and focus restoration was made immediate after exact acknowledgement.

## TDD Gate Compliance

- Task 1 RED commit `a980aec` reached 0/4 with the merge module, persisted conflict DTO, resolution path, and route absent. GREEN commit `dd73021` made the expanded 5/5 dedicated server cases and contract drift pass.
- Task 2 RED commit `bd6ad98` failed because `ConflictResolver` did not exist. GREEN commit `edae65d` made 4/4 dedicated browser cases, typecheck, lint, and contracts pass.
- Both RED commits precede their matching GREEN commits. The post-GREEN compatibility correction is isolated in `3e94ac0` and has full regression evidence.

## Known Stubs

None - no TODO, FIXME, skipped test, placeholder production behavior, mock production data source, hardcoded empty rendered data, or unrun verification remains in the 15 realized files.

## Threat Surface

- T-KPL01-33 is mitigated by a closed server-owned merge, expected/latest revision checks, stored base/requested/current values, invariant rerun, terminal receipt persistence, and explicit overlap/lifecycle tests.
- T-KPL01-34 is mitigated by composite account-scoped foreign keys and predicates, account-scoped row locks, opaque cross-account behavior, and proof that foreign conflict IDs neither disclose nor mutate state.
- T-KPL01-35 is mitigated by React text rendering, hostile markup fixtures, no HTML injection path, bounded six-line disclosure, and accessible affected-field choices.
- The planned resolution route and persisted conflict table are the only new trust-boundary surfaces. No additional network, authentication, file-access, telemetry, or schema surface outside the plan threat model was introduced, and no high-severity mitigation remains open.

## Verification Evidence

- Focused conflict ExUnit suite: 5/5 passed against PostgreSQL 18.6; storage-neutral vectors, stable overlap/replay, fresh resolution identity, stale/cross-account opacity, Edit-versus-Trash, and Phoenix transport all passed.
- Focused conflict browser suite: 4/4 passed, including hostile text, disclosure, affected-only values, unaffected draft retention, selection state, fresh identity, exact acknowledgement, same-body retry, stale state, and focus.
- Disposable PostgreSQL migration: all migrations forward, Plan 01-16 rollback, table-absence check, Plan 01-16 forward, and table-presence check passed; the disposable database was removed afterward.
- `pnpm contracts:check`: OpenAPI and checked-in generated TypeScript agree.
- Full `mix test`: 80/80 server tests passed.
- Full web Vitest suite: 8 files and 52/52 tests passed.
- Web typecheck, ESLint, and production Vite build passed; Vite transformed 64 modules.
- `pnpm test:phase-1`: repository integrity, runtime preflight, warnings-as-errors compilation, contract drift, full browser unit suite, and real-stack discovery passed.
- `pnpm --filter @keepling/web test:e2e`: 3/3 real PostgreSQL/Phoenix/Chromium tests passed.

## User Setup Required

None. No dependency, external credential, service, operator migration step, or environment change was added.

## Next Phase Readiness

- Plan 01-17 can build bounded recovery/undo behavior on stable accepted activity and conflict-resolution audit linkage without introducing another merge authority.
- Later MCP and offline clients can consume the same closed resolution command and storage-neutral conflict vectors; no client needs to reimplement the server merge rules.
- No high-severity mitigation assigned to Plan 01-16 remains open.

## Self-Check: PASSED

- All 15 realized domain, application, PostgreSQL, transport, migration, contract, vector, facade, component, and test files exist on disk.
- Commits `a980aec`, `dd73021`, `bd6ad98`, `edae65d`, and `3e94ac0` exist in Git history in the documented RED/GREEN/correction order.
- Required actuals, requirements, coverage metadata, deviation records, TDD gates, stub scan, threat mitigations, and fresh cross-boundary verification are present.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-31*
