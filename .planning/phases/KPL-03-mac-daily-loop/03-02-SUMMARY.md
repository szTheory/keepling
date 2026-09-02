---
phase: KPL-03-mac-daily-loop
plan: 02
subsystem: desktop-synchronization
tags: [electron, sqlite, synchronization, safeStorage, openapi, phoenix, recovery]

requires:
  - phase: KPL-03-mac-daily-loop
    plan: 01
    provides: Main-owned durable application/store boundary and packaged offline capture tracer
  - phase: KPL-02-synchronization-and-replaceable-server
    plans: [01, 05, 11]
    provides: Storage-neutral vectors, released sync transport, and native grant authority
provides:
  - Durable vector-compatible desktop synchronization reducer with bounded pull-first passes and exact immutable retries
  - Five-part server-derived namespace fencing and fence-before-revoke sign-out
  - Generated-contract HTTPS adapter and asynchronous safeStorage credential adapter
  - One closed sequence-tagged recovery projection shared byte-equivalently by renderer surfaces
affects: [KPL-03-03, KPL-03-04, KPL-03-05, KPL-03-09, KPL-03-10, desktop-recovery]

actuals:
  tokens: 18077
  tasks: 3
  commits: 10

tech-stack:
  added: []
  patterns: [pull-before-push bounded sync, exact receipt settlement, server-derived namespace activation, async encrypted credential port, main-owned presentation projection]

key-files:
  created:
    - apps/desktop/main/adapters/sync.ts
    - apps/desktop/main/adapters/credentials.ts
    - apps/desktop/main/application/presentation.ts
    - apps/desktop/preload/contracts.ts
    - apps/desktop/test/application/sync-vectors.test.ts
    - apps/desktop/test/application/recovery-presentation.test.ts
    - apps/desktop/test/e2e/real-stack-sync.spec.ts
  modified:
    - apps/desktop/main/application/DesktopApplication.ts
    - apps/desktop/store-worker/local-store.ts
    - apps/desktop/migrations/0001_initial.sql
    - apps/desktop/preload/index.ts
    - apps/server/lib/keepling_web/controllers/device_grant_controller.ex
    - packages/contracts/openapi/keepling.yaml
    - packages/contracts/generated/keepling.ts

key-decisions:
  - "Desktop synchronization always performs one bounded pull before interleaving at most 25 ready pushes, and exact serialized command bytes remain the retry authority."
  - "The local store activates only a complete five-field namespace returned by native token exchange/refresh; installation IDs, URLs, tokens, and client inputs never reconstruct authority."
  - "Sign-out fences local intent and clears local credentials before best-effort remote revocation, so network failure cannot drain work across identities."
  - "Renderer synchronization truth is one monotonic main-owned projection; healthy state is quiet and actionable states use exact closed copy and actions."

patterns-established:
  - "Settlement transaction: identity plus SHA-256 fingerprint gates canonical shadow/conflict update, journal terminalization, projection replay, and exact outbox removal."
  - "Presentation boundary: main derives a closed summary once and sends the same value to shell, row, and recovery panel through validated named preload operations."

requirements-completed: [MAC-03, MAC-04, SRV-02]

coverage:
  - id: D1
    description: "Desktop durable synchronization matches every Phase 2 vector across pull, lane ordering, terminal outcomes, relaunch, response loss, and fencing."
    requirement: MAC-03
    verification:
      - kind: integration
        ref: "apps/desktop/test/application/sync-vectors.test.ts#10 passing desktop cases"
        status: pass
      - kind: integration
        ref: "tooling/test-phase-2.sh --lane sync-property#20 passing cases"
        status: pass
    human_judgment: false
  - id: D2
    description: "Native authorization, released sync operations, exact lookup replay, server-derived namespace authority, and encrypted credential storage are executable across desktop and Phoenix boundaries."
    requirement: SRV-02
    verification:
      - kind: e2e
        ref: "apps/desktop/test/e2e/real-stack-sync.spec.ts#3 passing cases"
        status: pass
      - kind: integration
        ref: "tooling/test-phase-2.sh --lane server#175 passing cases"
        status: pass
      - kind: other
        ref: "pnpm contracts:check#OpenAPI agrees"
        status: pass
    human_judgment: false
  - id: D3
    description: "Every synchronization and recovery condition is renderer-reachable through exact calm copy, bounded counts, coarse contact state, and closed recovery actions."
    requirement: MAC-04
    verification:
      - kind: unit
        ref: "apps/desktop/test/application/recovery-presentation.test.ts#15 exact state rows within 26 passing tests"
        status: pass
      - kind: unit
        ref: "pnpm test:desktop -- privacy#26 passing tests"
        status: pass
    human_judgment: false

duration: 26min
completed: 2026-09-02
status: complete
---

# Phase KPL-03 Plan 02: Exact Desktop Synchronization and Recovery Summary

**A pull-first durable Electron synchronizer now replays immutable intent through released Phoenix operations, fences exact server namespaces, protects credentials with asynchronous safeStorage, and publishes one calm recovery projection.**

## Performance

- **Duration:** 26 min across initial execution and the approved namespace-contract continuation
- **Started:** 2026-09-02T18:28:22Z
- **Completed:** 2026-09-02T18:53:50Z
- **Tasks:** 3
- **Files modified:** 18

## Accomplishments

- Drove all Phase 2 vectors through real SQLite state, including ready-lane ordering, failed dependencies, relaunch, exact terminal settlement, authentication fencing, and namespace mismatch isolation.
- Added bounded generated-contract transport for compatibility, authorization exchange/refresh, feed/bootstrap, semantic command delivery, exact mutation lookup, and revocation without cloning server merge authority.
- Expanded the authenticated native token response with the five server-derived namespace dimensions and proved native request DTOs cannot assert them.
- Added asynchronous safeStorage credential persistence with atomic ciphertext replacement and no renderer or diagnostic exposure.
- Published every UI-SPEC recovery state through one monotonic main-owned projection with exact copy, bounded counts, closed actions, and identical shell/row/panel summaries.

## Task Commits

1. **Task 1 RED: Desktop synchronization vectors** - `2d33006` (test)
2. **Task 1 RED: Namespace fence proof** - `34910da` (test)
3. **Task 1 GREEN: Durable bounded synchronization reducer** - `22c3a82` (feat)
4. **Task 2 RED: Native sync and namespace boundary proof** - `756db86` (test)
5. **Task 2 RED: Fence-before-revoke sign-out proof** - `ce2c4e3` (test)
6. **Task 2 GREEN: Native sync and credential boundaries** - `994d40b` (feat)
7. **Task 3 RED: Closed recovery projection matrix** - `f3c3525` (test)
8. **Task 3 GREEN: Main-owned recovery presentation** - `a19352d` (feat)
9. **Acceptance RED: Unsigned-build credential continuity disclosure** - `0a461ef` (test)
10. **Acceptance GREEN: Settings-facing credential continuity disclosure** - `bcbaf53` (fix)

## Verification

- `pnpm typecheck:desktop` — passed.
- `pnpm --dir apps/desktop build` — main, preload, renderer, and worker bundles passed.
- `pnpm test:desktop -- sync-vectors` — 26 tests passed, including all 10 synchronization cases.
- `pnpm test:desktop -- recovery-presentation` — 26 tests passed, including every exact state row.
- `pnpm test:desktop -- privacy` — 26 tests passed with forbidden diagnostic fields rejected.
- `pnpm test:desktop:e2e -- real-stack` — 3 tests passed.
- `pnpm contracts:check` — OpenAPI and generated client agree; all vector/compatibility/redaction checks passed.
- `./tooling/test-phase-2.sh --lane server` — 175 cases passed with warnings treated as errors.
- `./tooling/test-phase-2.sh --lane sync-property` — 20 seeded reference/feed cases passed.

## Deviations from Plan

### Approved Architectural Change

**1. [Rule 4 - Architecture] Exposed server-derived namespace authority in native token responses**
- **Found during:** Task 2 pre-implementation boundary audit
- **Issue:** The server constructed the required five-part namespace internally but no released authenticated response exposed it, making safe desktop store selection impossible without client reconstruction.
- **Decision:** The developer explicitly authorized a compatible additive contract expansion.
- **Fix:** Added closed `NativeSyncNamespace` to authorization-code and refresh token responses, sourced only from the locked server grant/configuration; request DTOs remain closed and namespace-free.
- **Files modified:** `device_grant_controller.ex`, its controller test, `keepling.yaml`, generated TypeScript, and `check-contracts.mjs`.
- **Verification:** 175-case server lane, generated-contract drift check, and desktop E2E all passed.
- **Committed in:** `756db86`, `ce2c4e3`, `994d40b`

### Auto-fixed Issues

**2. [Rule 2 - Missing Critical] Persisted storage-neutral synchronization metadata**
- **Found during:** Task 1 vector implementation
- **Issue:** The tracer schema retained capture fields but not resource keys or optimistic effect snapshots needed for dependency/lane replay after relaunch.
- **Fix:** Expanded the unreleased initial desktop migration and worker transaction to retain exact resource keys and effect snapshots independently from wire DTOs.
- **Files modified:** `apps/desktop/migrations/0001_initial.sql`, `apps/desktop/store-worker/local-store.ts`
- **Verification:** All 10 desktop synchronization cases and the packaged store regression suite passed.
- **Committed in:** `22c3a82`

**3. [Rule 3 - Blocking] Allowed type-only generated contract imports in desktop typechecking**
- **Found during:** Task 2 generated adapter typecheck
- **Issue:** The desktop TypeScript root excluded the repository-owned generated contract file.
- **Fix:** Broadened `rootDir` to the monorepo root while leaving Vite process build inputs and output boundaries unchanged.
- **Files modified:** `apps/desktop/tsconfig.json`
- **Verification:** Desktop typecheck and all four Vite builds passed.
- **Committed in:** `994d40b`

**4. [Rule 1 - Bug] Loaded Electron safeStorage lazily for adapter tests**
- **Found during:** Task 2 E2E GREEN verification
- **Issue:** Playwright's Node process cannot consume Electron's runtime export as an ESM named export, preventing injection-based credential proof.
- **Fix:** Resolved Electron through `createRequire` only when no safeStorage test port is supplied; packaged runtime behavior remains the native Electron API.
- **Files modified:** `apps/desktop/main/adapters/credentials.ts`
- **Verification:** Credential ciphertext test, typecheck, and main bundle passed.
- **Committed in:** `994d40b`

**5. [Rule 2 - Missing Critical] Disclosed unsigned-build credential continuity in Settings data**
- **Found during:** Final acceptance audit after Task 3
- **Issue:** The credential adapter safely encrypted refresh tokens but did not expose the required calm disclosure that unsigned dogfood app replacement may not preserve sign-in.
- **Fix:** Added a closed Settings disclosure value that distinguishes credential continuity from durable local task and pending-change safety without claiming signing, notarization, or update-stable Keychain behavior.
- **Files modified:** `apps/desktop/main/adapters/credentials.ts`, `apps/desktop/test/e2e/real-stack-sync.spec.ts`
- **Verification:** The real-stack E2E suite passed all 3 cases; desktop typecheck and all four bundles passed.
- **Committed in:** `0a461ef`, `bcbaf53`

---

**Total deviations:** 1 explicitly approved Rule 4 change and 4 auto-fixed issues (1 Rule 1, 2 Rule 2, 1 Rule 3).
**Impact on plan:** The approved additive response closes the only missing authority path; all other changes were required for correctness or buildability and added no dependency or canonical data service.

## Authentication Gates

None. All external boundaries used disposable local fixtures and generated test credentials.

## Known Stubs

None. The scan found no TODO/FIXME/placeholder path, skipped test, or hardcoded empty value flowing to a renderer surface.

## Threat Surface Review

The approved token-response expansion is the only new trust-boundary surface. It is covered by T-KPL03-02-01: every dimension comes from server configuration plus the locked grant row, request shapes reject namespace fields, and the desktop requires the complete closed response before store activation. Exact fingerprint settlement, safeStorage isolation, bounded scheduling, and renderer/diagnostic privacy mitigations all have passing negative tests.

## User Setup Required

None. The credential adapter now exposes the Settings-facing unsigned-build continuity disclosure while making no signed/notarized or update-stable Keychain claim.

## Next Phase Readiness

- Plan 03-09 can extract presentation-only facade components over the sequence-tagged recovery contract.
- Workspace and lifecycle plans can invoke one bounded `runSyncPass`, bind only token-returned namespace authority, and route recovery actions through the closed projection.
- No synchronization or credential state needs to move into the renderer.

## Self-Check: PASSED

All seven created files exist, all ten task and acceptance commits resolve, and the modified-file stub scan found no TODO, FIXME, placeholder, skipped-test, or unavailable-state markers.
