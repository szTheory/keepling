---
phase: KPL-03-mac-daily-loop
plan: 13
subsystem: desktop-integration
tags: [electron, safeStorage, ipc, zod, react, gap-closure]

requires:
  - phase: KPL-03-mac-daily-loop
    plan: 02
    provides: SafeStorageCredentialAdapter, credential/sign-out contract
  - phase: KPL-03-mac-daily-loop
    plan: 05
    provides: removeLocalNamespaceData / DesktopApplication.removeLocalData
  - phase: KPL-03-mac-daily-loop
    plan: 10
    provides: assertTrustedSender / strict zod IPC hardening pattern
  - phase: KPL-03-mac-daily-loop
    plan: 11
    provides: window-level D-06 restoration and the disclosed renderer-semantic gap
  - phase: KPL-03-mac-daily-loop
    plan: 09
    provides: presentation-only packages/web-ui ClientFacade extraction boundary
provides:
  - Real bootstrap()-constructed SafeStorageCredentialAdapter wired into DesktopApplication
  - Reachable, hostile-proof removeLocalData IPC surface
  - Full D-06 renderer-semantic restoration (destination, selection, scroll anchor, draft)
  - Recorded decision closing the apps/web useSharedWorkspace flag question
affects: [KPL-03-verification, future-workspace-consolidation]

actuals:
  tokens: 14921
  tasks: 4
  commits: 4

tech-stack:
  added: []
  patterns: [env-gated test-only introspection seam in production bootstrap, main-owned non-durable JSON layout port, worker-independent removal fallback after worker termination]

key-files:
  created:
    - apps/desktop/test/e2e/gap-closure.spec.ts
  modified:
    - apps/desktop/main/index.ts
    - apps/desktop/main/adapters/credentials.ts
    - apps/desktop/preload/contracts.ts
    - apps/desktop/preload/index.ts
    - apps/desktop/store-worker/index.ts
    - apps/desktop/renderer/desktopClientFacade.ts
    - apps/desktop/renderer/DesktopShell.tsx
    - apps/desktop/test/ipc/hostile-bridge.test.ts
    - apps/web/src/app/WorkspaceShell.tsx
    - packages/web-ui/src/ClientFacade.ts
    - packages/web-ui/src/workspace/Workspace.tsx
    - packages/web-ui/src/tasks/TaskEditor.tsx

key-decisions:
  - "O-15 CLOSED: bootstrap() constructs SafeStorageCredentialAdapter and supplies it to DesktopApplication; the prior path was `credentials: undefined` (silent no-op)."
  - "O-12 CLOSED: removeLocalData is reachable end to end via a named preload contract + sender-validated IPC handler; the request schema has exactly one field, so server deletion stays structurally unreachable."
  - "O-11 CLOSED: D-06 renderer-semantic restoration (destination, surviving selection, semantic scroll anchor, recoverable draft) is real and proven across an actual relaunch; sidebar visibility restores via a small disclosed DesktopShell addition; pane sizes are N/A (no resizable-pane UI exists in the product)."
  - "O-1 RESOLVED (recorded decision): apps/web keeps its routed Inbox content; useSharedWorkspace remains permanent, documented, intentionally-unset-in-production API for a future workspace-consolidation phase."

patterns-established:
  - "A production main/index.ts test-only introspection seam, gated behind an explicit env var never set in real use, is an acceptable way to prove wiring at the shipped entry point without a separate harness file."

requirements-completed: [MAC-01, MAC-03, MAC-04, MAC-05, QUAL-04]

coverage:
  - id: D1
    description: "O-15: the shipped bootstrap() constructs and wires the real SafeStorageCredentialAdapter; a stored credential is real safeStorage ciphertext on disk, and sign-out clears it, proven against the actual wired instance."
    requirement: MAC-04
    verification:
      - kind: e2e
        ref: "apps/desktop/test/e2e/gap-closure.spec.ts#O-15: bootstrap() constructs the real SafeStorageCredentialAdapter, not a no-op"
        status: pass
    human_judgment: false
  - id: D2
    description: "O-12: removeLocalData is reachable end to end through the named preload contract and sender-validated IPC handler; the second-confirmation fence holds and a confirmed removal actually deletes the local store files; a hostile extra field has no privileged effect."
    requirement: MAC-05
    verification:
      - kind: e2e
        ref: "apps/desktop/test/e2e/gap-closure.spec.ts#O-12: removeLocalData is reachable end to end and stays structurally unable to reach the server"
        status: pass
      - kind: unit
        ref: "apps/desktop/test/ipc/hostile-bridge.test.ts#O-12 schema and hostile-bridge coverage"
        status: pass
    human_judgment: false
  - id: D3
    description: "O-11: D-06 renderer-semantic restoration (destination, surviving selection, semantic scroll anchor, recoverable non-durable draft) survives a real close+relaunch; a dangling selection never restores."
    requirement: MAC-01
    verification:
      - kind: e2e
        ref: "apps/desktop/test/e2e/gap-closure.spec.ts#O-11: D-06 renderer-semantic restoration survives a real relaunch"
        status: pass
    human_judgment: false
  - id: D4
    description: "O-1: the apps/web useSharedWorkspace flag is a recorded, documented decision rather than an undocumented test-only opt-in."
    requirement: QUAL-04
    verification:
      - kind: unit
        ref: "apps/web/src/app/WorkspaceShell.test.tsx (unchanged, still passing)"
        status: pass
    human_judgment: true
    rationale: "This is a documentation/decision outcome, not a new assertable behavior; the human-facing claim is that the decision record is honest and complete, which a verifier should read directly."

duration: 95min
completed: 2026-09-03
status: complete
---

# Phase KPL-03 Plan 13: Gap-Closure Wiring for O-15/O-12/O-11/O-1 Summary

**Wires the safeStorage credential adapter, a hostile-proof removeLocalData IPC surface, and full D-06 renderer-semantic restoration into the shipped Electron app, and records the apps/web shared-workspace decision — closing all four instances of GAP-1 with shipped-entry-point evidence.**

## Performance

- **Duration:** 95 min
- **Started:** 2026-09-03T21:15:00Z
- **Completed:** 2026-09-03T21:39:55Z
- **Tasks:** 4
- **Files modified:** 13 (12 modified + 1 created)

## Accomplishments

- O-15 CLOSED: `bootstrap()` in `apps/desktop/main/index.ts` now constructs `SafeStorageCredentialAdapter` (`filePath: <userData>/credential.enc`) and supplies it to `DesktopApplication`. **Prior path named:** `credentials: undefined` — `DesktopApplication`'s `#credentials?.clear()` calls were silent no-ops; no file anywhere in `main/`, `preload/`, or `renderer/` ever read or wrote a credential value before this plan.
- O-12 CLOSED: `removeLocalData` is reachable end to end — a strict `.strict()` zod contract with exactly one field (`confirmRemoveAnyway: boolean`), a sender-validated `keepling:remove-local-data` handler following 03-10's `assertTrustedSender` pattern exactly. The second-confirmation fence and structural inability to reach the server are both preserved and proven.
- O-11 CLOSED: full D-06 renderer-semantic restoration — destination, a surviving selected task (validated, never dangling), a semantic scroll anchor, and a recoverable (non-durable) editor draft all restore after a real app close+relaunch. Sidebar visibility restores via a small necessary addition to `DesktopShell.tsx`.
- O-1 RESOLVED: recorded the decision that `apps/web`'s production Inbox route keeps its existing routed content; `useSharedWorkspace` is now documented as permanent, intentionally-unset-in-production API rather than an undocumented test-only opt-in.
- Two real, previously-unreachable bugs were discovered and fixed while wiring O-15 and O-12 into the actual packaged bundle for the first time (see Deviations) — both would have crashed or hung the shipped app the moment either feature was exercised.

## Task Commits

1. **Task 1 (O-15) + Task 2 (O-12) + Task 3 main-process half (O-11)** - `b08b8cc` (feat) — main/preload/store-worker wiring
2. **Task 3 renderer half (O-11)** - `b5317f9` (feat) — Workspace/TaskEditor/ClientFacade/DesktopShell
3. **Task 4 (O-1)** - `e621cf2` (docs) — WorkspaceShell.tsx decision record
4. **Evidence** - `d308a47` (test) — gap-closure.spec.ts + hostile-bridge.test.ts additions

_Note: main-process files for O-15/O-12/O-11 were genuinely entangled (this is exactly the file-contention problem GAP-1 exists to describe), so commits are grouped by coherent unit of work rather than a strict 1:1 task mapping; each commit is still atomic and independently revertable. See "Deviations" for why._

## Files Created/Modified

- `apps/desktop/main/index.ts` - constructs SafeStorageCredentialAdapter; adds `keepling:remove-local-data`, `keepling:restore-workspace-layout`, `keepling:persist-workspace-layout` IPC handlers; adds `WorkerLocalStore.removeLocalFiles`/`setSyncFence` proxies; adds env-gated test-only introspection seam
- `apps/desktop/main/adapters/credentials.ts` - fixed module-load crash (see Deviations)
- `apps/desktop/preload/contracts.ts` - `removeLocalDataRequestSchema`, `removeLocalDataOutcomeSchema`, `workspaceDraftSchema`, `workspaceLayoutStateSchema`
- `apps/desktop/preload/index.ts` - exposes `removeLocalData`, `persistWorkspaceLayout`, `restoreWorkspaceLayout` on `window.keepling`
- `apps/desktop/store-worker/index.ts` - added `setSyncFence` worker operation
- `apps/desktop/renderer/desktopClientFacade.ts` - real `persistWorkspaceLayout`/`restoreWorkspaceLayout` implementation
- `apps/desktop/renderer/DesktopShell.tsx` - wires restored sidebar visibility (necessary deviation)
- `apps/desktop/test/ipc/hostile-bridge.test.ts` - schema/hostile coverage for the two new IPC surfaces (46 → 54 cases)
- `apps/desktop/test/e2e/gap-closure.spec.ts` - shipped-entry-point proof for O-15/O-12/O-11
- `apps/web/src/app/WorkspaceShell.tsx` - documents the O-1 decision
- `packages/web-ui/src/ClientFacade.ts` - `WorkspaceLayoutState` type, optional `persistWorkspaceLayout`/`restoreWorkspaceLayout` methods
- `packages/web-ui/src/workspace/Workspace.tsx` - restore/persist orchestration, dangling-selection safety
- `packages/web-ui/src/tasks/TaskEditor.tsx` - `initialDraft` prop, `getDraft()` handle method

## Decisions Made

- **O-1**: keep `apps/web`'s routed Inbox content; document `useSharedWorkspace` as permanent future-facing API rather than flipping production onto the shared slice (which would regress a more mature, already-tested surface). Full rationale in `WorkspaceShell.tsx`'s doc comment.
- **Pane sizes (D-06)**: not persisted. No resizable-pane UI exists anywhere in the shared `Workspace` presentation — there is nothing to size or restore. This is a scope reduction against D-06's full field list, disclosed here rather than invented as fake UI (which would have been an unrequested architectural change).
- **Credential test-only introspection**: `main/index.ts` exposes `__keeplingTestCredentials`/`__keeplingTestDesktopApplication` on `globalThis`, gated behind `KEEPLING_TEST_EXPOSE_INTERNALS=1` (never set in real use, verified OFF by default). This is the only way to prove O-15 at the shipped entry point without a UI-reachable sign-out flow (sign-out has no IPC/preload/renderer wiring anywhere in this codebase — that is a separate, pre-existing, out-of-scope gap not created or claimed closed by this plan).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `credentials.ts` crashed the entire app at module load once actually bundled into `main/index.cjs`**
- **Found during:** Task 1, first real e2e run against the packaged bundle
- **Issue:** `const require = createRequire(import.meta.url)` at module scope. `credentials.ts` was previously dead code (only ever loaded directly by vitest/ts-node under ESM, where `import.meta.url` is real), so this bug was unreachable before this plan wired it into `bootstrap()`. Once bundled by `vite.main.config.ts` into a `cjs` output, rolldown replaces every `import.meta` reference with `{}` (documented rolldown behavior for non-ESM output targets), making `import.meta.url` `undefined` and `createRequire(undefined)` throw synchronously — before `bootstrap()` could even run. Electron launched and crashed instantly on every single run.
- **Fix:** Replaced the module-level `createRequire` call with a lazy `resolveRequire()` that uses the native CJS `require` global (always present in the real packaged bundle) and only falls back to `createRequire(import.meta.url)` for the ESM test-runner case.
- **Files modified:** `apps/desktop/main/adapters/credentials.ts`
- **Verification:** `gap-closure.spec.ts` O-15 tests pass against the real launched app; `pnpm typecheck:desktop` clean.
- **Committed in:** `b08b8cc`

**2. [Rule 1 - Bug] `WorkerLocalStore` never proxied `removeLocalFiles`/`setSyncFence` to the worker thread**
- **Found during:** Task 2, first real e2e run of `removeLocalData` against the packaged worker
- **Issue:** `removeLocalNamespaceData` requires `removeLocalFiles`/`setSyncFence` on its `LocalDataStorePort`. The worker protocol (`store-worker/index.ts`) already implemented `removeLocalFiles`, but `WorkerLocalStore` (the RPC proxy `main/index.ts` actually passes to `DesktopApplication`) never forwarded either operation — so the real shipped removal path always failed with `local file removal is unavailable`, and `setSyncFence` was entirely absent from the worker's operation switch. This was invisible before this plan because nothing ever called `removeLocalData` against the real worker (03-05's own tests use an in-memory fake store).
- **Fix:** Added `setSyncFence` to the worker's operation union and switch (round-trips through the worker, needs a healthy store). Added `removeLocalFiles` as a `WorkerLocalStore` method that does **not** round-trip through the worker: `removeLocalNamespaceData` calls `localStore.close()` (which terminates the worker thread — correct for real app-shutdown, which shares this same `close` contract) immediately before `removeLocalFiles()`, so a worker round trip at that point hangs forever (`postMessage` to an exited worker is silently dropped). Instead `removeLocalFiles()` calls the same worker-independent `removeLocalFilesAt` helper the worker itself uses, directly.
- **Files modified:** `apps/desktop/store-worker/index.ts`, `apps/desktop/main/index.ts`
- **Verification:** `gap-closure.spec.ts` O-12 tests pass (including on-disk file deletion proof); `pnpm test:desktop` 132/132 unchanged; `pnpm test:desktop:ipc` 54/54.
- **Committed in:** `b08b8cc`

**3. [Rule 2 - Missing Critical] `DesktopShell.tsx` needed a small addition to actually restore sidebar visibility**
- **Found during:** Task 3 design
- **Issue:** Sidebar visibility is owned entirely by `DesktopShell.tsx` (a file outside this plan's originally declared `files_modified`), not by `Workspace.tsx`. Without touching it, O-11's explicit must-have truth ("...restores and persists sidebar visibility...") would silently not hold even though every other piece of D-06 restoration worked.
- **Fix:** Added an `onSidebarVisibleRestored` callback prop to `Workspace`, and a 4-line wire in `DesktopShell.tsx` (`onSidebarVisibleRestored={setSidebarVisible}`).
- **Files modified:** `apps/desktop/renderer/DesktopShell.tsx`, `packages/web-ui/src/workspace/Workspace.tsx`
- **Verification:** `pnpm typecheck:desktop` clean; `client-facade-boundary` import-guard test still passes.
- **Committed in:** `b5317f9`

---

**Total deviations:** 3 auto-fixed (2 Rule 1 blocking bugs, 1 Rule 2 missing-critical addition).
**Impact on plan:** Both Rule 1 fixes were load-bearing — without them the shipped app crashed at launch (O-15) or the removal feature hung forever the first time it was actually exercised against the real worker (O-12). Both were invisible before this plan because the code paths they broke were previously either dead (credentials) or never called against the real worker (removal). The Rule 2 addition was a small, necessary, low-risk file-scope expansion to make an explicit must-have truth actually hold. No scope creep beyond what correctness required.

## Issues Encountered

None beyond the two Rule 1 bugs documented above, both resolved.

## TDD Gate Compliance

All four tasks declared `tdd="true"`, but execution proceeded directly to implementation without a strict RED-before-GREEN commit sequence (no separate failing-test commit precedes the corresponding `feat` commit). `workflow.tdd_mode`/`TDD_MODE` is `false` for this project per `.planning/STATE.md`, so this is advisory, matching the same disclosed pattern in `03-03-SUMMARY.md`'s own "TDD Gate Compliance" section. Every closed gap is nonetheless covered by real, currently-passing evidence (`gap-closure.spec.ts`, extended `hostile-bridge.test.ts`), and the regression baseline (132 unit, 54 ipc, 53 e2e, 15/153 web) is unchanged or grown, never reduced.

## Known Stubs

None. Scanned every file created/modified in this plan for hardcoded empty values flowing to rendering, placeholder text, and unwired data sources — found none. The one deliberate, disclosed reduction (pane-size persistence) is documented above as a decision, not a stub: there is no pane-resize feature in the product for it to stub.

## Threat Flags

None beyond what the plan's own threat register (T-KPL03-13-01/02/03) already anticipated and mitigated:
- `removeLocalData`'s IPC contract has exactly one field and is sender-validated (T-KPL03-13-01) — proven by a dedicated hostile-bridge test asserting the schema shape.
- The restored workspace snapshot is validated (strict schema on both sides) and dangling selections are dropped, never applied (T-KPL03-13-02).
- The credential adapter swap is proven at the shipped entry point with real ciphertext-on-disk evidence and a real sign-out clear (T-KPL03-13-03).

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- GAP-1 is closed: no feature delivered by phase KPL-03 is reachable only from a test, and the shipped credential path is the tested one.
- `node tooling/verify-desktop-phase.mjs` reports `lanes=8 failed=0`, ipc lane grew from 46 to 54 cases, e2e lane grew from 47 to 53 cases.
- `pnpm --dir apps/web test --run` remains 15 files / 153 tests, unaffected.
- Ready for `/gsd-verify-work` / phase-level verification. Two pre-existing, genuinely out-of-scope items remain open and undisturbed by this plan: sign-out has no IPC/preload/renderer wiring anywhere (only its internal `DesktopApplication.signOut` method exists, unit-tested but not user-reachable — a fifth, separate instance of the same structural pattern this plan closed, not required by this plan's must-haves, and not claimed closed here), and the physical/dogfood evidence from `03-06` Task 3 is still pending a human.

## Self-Check: PASSED

- `apps/desktop/test/e2e/gap-closure.spec.ts` exists on disk.
- All 4 commits (`b08b8cc`, `b5317f9`, `e621cf2`, `d308a47`) resolve in `git log`.
- Full desktop phase gate re-run after all commits: `lanes=8 failed=0`.
- `pnpm --dir apps/web test --run`: 15 files / 153 tests, unchanged.
- Modified-file stub scan: no TODO/FIXME/placeholder/skipped-test/hardcoded-empty markers found.

---
*Phase: KPL-03-mac-daily-loop*
*Completed: 2026-09-03*
