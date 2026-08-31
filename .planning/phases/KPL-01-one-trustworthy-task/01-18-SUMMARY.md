---
phase: KPL-01-one-trustworthy-task
plan: 18
subsystem: semantic-recovery
tags: [elixir, phoenix, postgresql, react, openapi, idempotency, semantic-undo]

requires:
  - phase: KPL-01-17
    provides: Immutable browser command identities, exact acknowledgement reconciliation, and honest unknown/authentication recovery
provides:
  - Bounded 24-hour account-bound hash-only one-shot semantic undo for the supported task command matrix
  - Exact-revision atomic compensation with linked activity, handle consumption, and durable receipt replay
  - Persistent latest-action browser recovery with same-identity retry and explicit terminal/uncertain/authentication states
affects: [phase-1-verification, sync, mcp, desktop-offline, iphone-offline]

actuals:
  tokens: 21097
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns: [typed semantic inverse, hash-only one-shot capability, exact-revision compensation, latest-action recovery strip]

key-files:
  created:
    - apps/server/lib/keepling/application/undo.ex
    - apps/server/priv/repo/migrations/20260830000900_add_undo_handles.exs
    - apps/server/test/keepling/application/undo_test.exs
    - packages/contracts/vectors/undo.json
    - apps/web/src/features/recovery/RecoveryStrip.tsx
    - apps/web/src/features/recovery/recovery-strip.test.tsx
  modified:
    - apps/server/lib/keepling/adapters/postgres/command_store.ex
    - apps/server/lib/keepling_web/controllers/command_controller.ex
    - packages/contracts/openapi/keepling.yaml
    - apps/web/src/api/keepling.ts
    - apps/web/src/app/AppShell.tsx

key-decisions:
  - "Undo capabilities are 32-byte URL-safe values derived from a server-secret HMAC over a random UUID; PostgreSQL and durable receipts retain only the SHA-256 hash or derivation identity, never the raw handle."
  - "The v1 matrix is closed to task details, clarify/return, plan/unplan, complete/reopen, and Trash/restore; organization, reorder, date, conflict-resolution, capture, and undo commands do not mint nested undo."
  - "An undo consumes the exact produced revision under account-scoped row locks and commits inverse state, linked activity, original recovery state, consumption, and mutation receipt in one transaction."
  - "The browser retains only the latest offered recovery action across routes and reuses one fixed mutation identity for uncertain retries without registering a Cmd/Ctrl-Z handler."

patterns-established:
  - "Closed compensation: persisted inverse_type and inverse_payload are validated by Keepling.Application.Undo before the PostgreSQL adapter may apply them."
  - "Hash-only capability replay: first responses expose a reconstructed request-only capability while stored results, activity projections, and diagnostics remain handle-free."
  - "Latest-action recovery: ordinary acknowledgements publish precise undo availability to AppShell, which owns persistence and composes one accessible RecoveryStrip across routes."

requirements-completed: [GTD-07, SRV-02, SRV-03, WEB-02, QUAL-01]

coverage:
  - id: D1
    description: "Supported consequential task commands issue a 24-hour high-entropy account-bound hash-stored capability whose typed inverse applies only at the exact produced revision."
    requirement: GTD-07
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/application/undo_test.exs#supported matrix, hash storage, expiry, and exact revision"
        status: pass
      - kind: other
        ref: "pnpm contracts:check"
        status: pass
    human_judgment: false
  - id: D2
    description: "Independent concurrent consumers produce one accepted inverse, one linked activity, one consumed handle, and one replay-safe already-applied result."
    requirement: SRV-03
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/application/undo_test.exs#independent PostgreSQL consumer race"
        status: pass
    human_judgment: false
  - id: D3
    description: "Authentication, malformed/unknown capability, expiry, stale revision, applied state, and uncertain inverse outcomes are explicit and cannot apply an unauthorized or ambiguous inverse."
    requirement: SRV-02
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/application/undo_test.exs#closed route and no-change outcomes"
        status: pass
    human_judgment: false
  - id: D4
    description: "Only the latest precise recovery action persists across browser routes, keeps its raw handle request-only, retries with the original mutation identity, and leaves native text Cmd/Ctrl-Z untouched."
    requirement: WEB-02
    verification:
      - kind: automated_ui
        ref: "apps/web/src/features/recovery/recovery-strip.test.tsx"
        status: pass
    human_judgment: false
  - id: D5
    description: "Raw undo capabilities never enter durable result JSON, activity reads, rendered text, or diagnostics, and all planned high-severity mitigations are closed."
    requirement: QUAL-01
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/application/undo_test.exs#storage, receipt, activity, and read non-disclosure assertions"
        status: pass
      - kind: automated_ui
        ref: "apps/web/src/features/recovery/recovery-strip.test.tsx#handle non-rendering"
        status: pass
    human_judgment: false

duration: 63min
completed: 2026-08-31
status: complete
---

# Phase KPL-01 Plan 18: Bounded Semantic Undo Summary

**Hash-only 24-hour semantic undo with exact-revision atomic compensation and persistent latest-action browser recovery**

## Performance

- **Duration:** 63 min
- **Started:** 2026-08-31T14:13:39Z
- **Completed:** 2026-08-31T15:16:51Z
- **Tasks:** 2
- **Files modified:** 14

## Accomplishments

- Added a closed, typed undo application boundary and additive PostgreSQL capability store for the resolved nine-command matrix, with 24-hour expiry, account/hash lookup, exact produced-revision validation, one-shot row locking, and no raw capability persistence.
- Made accepted compensation atomic across task inverse, revision increment, linked `task_undo_applied` activity, original activity recovery state, handle consumption, and durable mutation receipt; replay and independent concurrent consumption return stable results without a second inverse.
- Exposed an authenticated versioned Phoenix/OpenAPI/generated DTO path with explicit expired, stale, already-applied, unknown, authentication-required, and uncertain behavior.
- Composed one accessible latest-action `RecoveryStrip` in `AppShell`, preserving it across routes, retaining exact retry identity after uncertainty, never rendering the capability, and leaving native text undo untouched.

## Task Commits

Each planned TDD task has an explicit RED commit followed by its GREEN commit:

1. **Task 1 RED: Add failing bounded undo proof** - `867fa8e` (test)
2. **Task 1 GREEN: Implement bounded semantic undo** - `a05bacf` (feat)
3. **Task 2 RED: Add failing persistent recovery proof** - `00a9b9e` (test)
4. **Task 2 GREEN: Compose persistent semantic recovery** - `890fdc5` (feat)

## Files Created/Modified

- `apps/server/lib/keepling/application/undo.ex` - Closed typed inverse validation and activity construction for the supported compensation kinds.
- `apps/server/lib/keepling/adapters/postgres/command_store.ex` - Capability issuance/reconstruction, account/hash locking, exact-revision consumption, atomic inverse/activity/receipt persistence, and stable replay.
- `apps/server/lib/keepling_web/controllers/command_controller.ex` and `apps/server/lib/keepling_web/router.ex` - Strict authenticated v1 undo command transport.
- `apps/server/priv/repo/migrations/20260830000900_add_undo_handles.exs` - Additive account-bound undo capability relation, checks, indexes, and lifecycle state.
- `apps/server/test/keepling/application/undo_test.exs` - Matrix, storage privacy, replay, expiry/staleness, transport, and independent-connection race proof.
- `apps/server/test/keepling/application/activity_test.exs` - Correct recovery-state expectation for newly undo-eligible edit activity.
- `packages/contracts/openapi/keepling.yaml`, `packages/contracts/generated/keepling.ts`, and `packages/contracts/vectors/undo.json` - Versioned availability, command, acknowledgement, no-change, and supported-matrix contracts.
- `apps/web/src/api/keepling.ts` - Generated DTO mapping, request-only capability facade, and exact same-identity undo submission.
- `apps/web/src/app/AppShell.tsx` - Latest availability ownership and cross-route recovery composition.
- `apps/web/src/features/recovery/RecoveryStrip.tsx` and `apps/web/src/features/recovery/recovery-strip.test.tsx` - Accessible explicit-state recovery UI and executable browser proof.

## Decisions Made

- Raw capabilities are reconstructable only from the endpoint secret and stored random undo identity. Stored receipts retain public undo metadata but omit the raw handle, so replay can produce the same capability without persisting it.
- Unsupported command types do not emit a capability. The initial matrix is deliberately closed and versioned instead of treating arbitrary patches as reversible.
- Expired and stale handles become terminal unavailable states and update the originating activity recovery projection; unknown handles remain indistinguishable from wrong-account handles.
- The recovery strip reports success only after an accepted acknowledgement. Infrastructure and unmapped failures become a persistent uncertain state whose retry sends the exact same mutation identity.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated the existing activity recovery expectation for undo-eligible edits**
- **Found during:** Task 1 full server verification
- **Issue:** The established activity test still expected an accepted task edit to have `not_available` recovery even though the planned supported matrix now makes task detail edits recoverable.
- **Fix:** Changed only that assertion to require `available`, matching the issued handle and persisted activity metadata.
- **Files modified:** `apps/server/test/keepling/application/activity_test.exs`
- **Verification:** Focused undo tests passed 7/7 and the full server suite passed 93/93.
- **Committed in:** `a05bacf`

---

**Total deviations:** 1 auto-fixed Rule 1 bug
**Impact on plan:** The adjustment was directly required by the new supported matrix and introduced no additional production scope.

## Issues Encountered

- The first final parallel server invocation omitted the repository-required test database and endpoint secret environment variables. Rerunning sequentially with the existing local `keepling_test` database and a test-only secret produced 7/7 focused and 93/93 full passes.
- One full browser run under concurrent verification load produced transient timeouts and interleaved typing in three pre-existing tests. The affected trio immediately passed 26/26 in isolation and the complete suite then passed twice, including the final 70/70 run; no leaked listener, mock, or DOM state reproduced.

## TDD Gate Compliance

- Task 1 RED commit `867fa8e` failed because `Keepling.Application.Undo` and the capability storage/transport behavior did not exist. GREEN commit `a05bacf` made all seven focused undo cases and all 93 server tests pass.
- Task 2 RED commit `00a9b9e` failed because `RecoveryStrip` did not exist. GREEN commit `890fdc5` made all eight focused recovery cases and all 70 browser tests pass.
- Both RED commits precede their matching GREEN commits; no feature implementation was committed before its failing behavioral proof.

## Known Stubs

None - no TODO, FIXME, skipped test, placeholder production behavior, mock production data source, hardcoded empty rendered data, or unrun verification remains in the 14 realized files. Nullable DTO fields, empty query accumulators, and initial React state are deliberate closed state representations rather than stubs.

## Threat Surface

- T-KPL01-38 is mitigated by high-entropy request capabilities, SHA-256-only lookup storage, authenticated account predicates, strict capability decoding, expiry, exact produced-revision comparison, and one-shot locked consumption.
- T-KPL01-39 is mitigated by fixed mutation receipts and transaction-scoped row locks; independent PostgreSQL consumers prove one winner, one inverse, one linked activity, one consumption, and stable replay/no-change behavior.
- T-KPL01-40 is mitigated by separating internal handle reconstruction from stored public result JSON, omitting handles from activity/read contracts and diagnostics, and component assertions that rendered text never contains the capability.
- The planned authenticated undo command and additive capability relation are the only new trust-boundary surfaces. No unplanned endpoint, auth method, telemetry, or file-access surface was introduced, and no high-severity mitigation remains open.

## Verification Evidence

- `mix test test/keepling/application/undo_test.exs`: 7/7 focused server tests passed.
- `mix test`: 93/93 full server tests passed.
- `pnpm --filter @keepling/web test --run src/features/recovery/recovery-strip.test.tsx`: 8/8 focused browser tests passed.
- `pnpm --filter @keepling/web test --run`: 10 files and 70/70 browser tests passed.
- `pnpm --filter @keepling/web lint`: ESLint completed cleanly.
- `pnpm --filter @keepling/web build`: TypeScript and production Vite build passed; 67 modules transformed.
- `pnpm contracts:check`: OpenAPI and generated TypeScript agree.

## User Setup Required

None - no external service configuration is required. Runtime signing secrets remain environment-owned as established by prior plans.

## Next Phase Readiness

- Plan 01-19 can run the final Phase 1 verification over a complete trustworthy task loop whose consequential browser actions now have bounded semantic recovery.
- The closed inverse and hash-only capability patterns are ready for later client surfaces without coupling domain rules to Phoenix, React, or persistence DTOs.
- No blocker, stub, skipped verification, or open high-severity threat remains.

## Self-Check: PASSED

- All six created implementation/proof files and this summary exist at their recorded paths.
- Task commits `867fa8e`, `a05bacf`, `00a9b9e`, and `890fdc5` resolve to commits in repository history.
- Fresh focused/full server, browser, lint, build, and contract verification passed, and the realized implementation plus summary pass `git diff --check`.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-31*
