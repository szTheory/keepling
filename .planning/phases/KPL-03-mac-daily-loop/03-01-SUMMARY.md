---
phase: KPL-03-mac-daily-loop
plan: 01
subsystem: desktop-offline-runtime
tags: [electron, node-sqlite, sqlite-wal, react, zod, playwright, forge]

requires:
  - phase: KPL-03-mac-daily-loop
    plan: 07
    provides: Pinned four-process Electron workspace and Forge build boundaries
  - phase: KPL-03-mac-daily-loop
    plan: 12
    provides: Package-once manifest, external smoke consumer, and anti-vacuous test harness
provides:
  - Main-owned DesktopApplication with narrow local-store, synchronization, credential, clock, and identity ports
  - Worker-owned node:sqlite store with atomic projection, journal, immutable command, and outbox acceptance
  - Checksum-ledgered STRICT migration with WAL, synchronous FULL, foreign keys, and finite busy handling
  - Hardened named preload capture/snapshot bridge and calm Inbox renderer
  - Digest-bound packaged hard-kill, relaunch, exact-settlement, and same-profile ownership proof
affects: [KPL-03-02, KPL-03-03, KPL-03-04, KPL-03-05, desktop-sync, desktop-recovery]

actuals:
  tokens: 57900
  tasks: 3
  commits: 8

tech-stack:
  added: [electron@44.1.1, zod@4.5.4]
  patterns: [post-COMMIT local success, worker-owned synchronous SQLite, exact mutation settlement, package-once external smoke]

key-files:
  created:
    - apps/desktop/main/application/DesktopApplication.ts
    - apps/desktop/main/index.ts
    - apps/desktop/migrations/0001_initial.sql
    - apps/desktop/preload/index.ts
    - apps/desktop/renderer/main.tsx
    - apps/desktop/store-worker/index.ts
    - apps/desktop/store-worker/local-store.ts
    - apps/desktop/test/application/offline-capture.test.ts
    - apps/desktop/test/packaged/offline-capture.spec.ts
    - apps/desktop/test/store/offline-capture.test.ts
  modified:
    - apps/desktop/forge.config.ts
    - tooling/package-desktop.mjs
    - tooling/smoke-desktop-packaged.mjs
    - pnpm-lock.yaml

key-decisions:
  - "D-03 remains a one-way trust contract: drafts make no durability claim, Saved on this Mac follows atomic local COMMIT, and Synced follows only an exact mutation identity and fingerprint acknowledgement."
  - "electron@44.1.1 and zod@4.5.4 were installed only after explicit provenance approval; better-sqlite3 remains absent because packaged node:sqlite passed."
  - "The selected user-data profile owns Electron's single-instance lock before bootstrap, so isolated profiles remain independent while duplicate ownership of one profile is rejected."
  - "All runtime dependencies are bundled into the four process outputs, so Forge excludes node_modules and packages only those outputs plus migrations."

patterns-established:
  - "Durability boundary: DesktopApplication returns local_saved only after the worker's BEGIN IMMEDIATE transaction commits projection, immutable command, journal, and outbox."
  - "Settlement boundary: mutation identity and SHA-256 fingerprint must both match before one exact outbox row is removed and the projection becomes synced."
  - "Artifact evidence: Forge builds once, copies the application outside source with verbatim framework symlinks, hashes it, and smoke never rebuilds."

requirements-completed: [MAC-01, MAC-03, MAC-05, QUAL-03]

coverage:
  - id: D1
    description: Offline capture reports Saved on this Mac only after atomic SQLite COMMIT and reconstructs the task after hard process loss.
    requirement: MAC-03
    verification:
      - kind: integration
        ref: apps/desktop/test/store/offline-capture.test.ts#atomically restores projection and immutable outbox after close and reopen
        status: pass
      - kind: e2e
        ref: apps/desktop/test/packaged/offline-capture.spec.ts#offline capture survives hard kill and exact acknowledgement
        status: pass
    human_judgment: false
  - id: D2
    description: Exact acknowledgement settles one immutable mutation while mismatch and repeated evidence preserve correct state and identity.
    requirement: MAC-01
    verification:
      - kind: unit
        ref: apps/desktop/test/application/offline-capture.test.ts#settles only an acknowledgement matching immutable mutation identity and fingerprint
        status: pass
      - kind: e2e
        ref: pnpm smoke:desktop:packaged -- offline-capture
        status: pass
    human_judgment: false
  - id: D3
    description: Exact external packaged bytes reject duplicate profile ownership and report source revision, digest, executable path, and embedded runtime versions.
    requirement: QUAL-03
    verification:
      - kind: e2e
        ref: PACKAGED_PROFILE_OWNERSHIP accepted_instances=1 rejected_instances=1; PACKAGED_OFFLINE_CAPTURE passed=1
        status: pass
    human_judgment: false

duration: 12h 11m
completed: 2026-09-02
status: complete
---

# Phase KPL-03 Plan 01: Packaged Offline Capture Tracer Summary

**A hardened Electron capture path commits locally through worker-owned SQLite, survives packaged hard kill, rejects duplicate profile ownership, and settles only an exact acknowledgement**

## Performance

- **Duration:** 12h 11m including blocking-human review checkpoints
- **Started:** 2026-09-02T06:10:36Z
- **Completed:** 2026-09-02T18:21:36Z
- **Tasks:** 3
- **Files modified:** 16

## Accomplishments

- Implemented `DesktopApplication` and the strict renderer → preload → main → worker path so `Saved on this Mac` is earned only after SQLite COMMIT.
- Added the immutable desktop schema, exact mutation fingerprinting, retained outbox, terminal journal settlement, checksum drift refusal, and no-auto-reset behavior.
- Proved the exact external `.app` survives hard kill and relaunch with one retained task, rejects a second same-profile process, and transitions to `Synced` only after exact acknowledgement.
- Bound evidence to source revision `16c4ab80a3d1e809684da039ad83dc637d10ee17`, application digest `ece00dc650277128e9f01248c6a01614d9e130bc2fd79a14758ff2402e60d9ba`, Electron `44.1.1`, Node `24.19.0`, and the external tested executable.

## Task Commits

1. **Task 3 RED: Add failing offline-capture tracer** - `15365ce` (test)
2. **Task 3 GREEN: Implement durable offline-capture architecture** - `c596d47` (feat)
3. **Task 3 fix: Make Forge packaging pnpm-compatible** - `bd5c436` (fix)
4. **Task 3 fix: Package only bundled runtime assets** - `3634c22` (fix)
5. **Task 3 fix: Omit nonexistent packaged asset root** - `47e3cf2` (fix)
6. **Task 3 fix: Preserve copied application identity** - `a540316` (fix)
7. **Task 3 fix: Resolve packaged process resources** - `4f0f803` (fix)
8. **Task 3 fix: Reject concurrent profile ownership** - `16c4ab8` (fix)

Tasks 1 and 2 were blocking-human approval/decision gates and intentionally created no commits.

## Files Created/Modified

- `apps/desktop/main/application/DesktopApplication.ts` - Owns capture preparation, D-03 local acceptance, and exact sync settlement.
- `apps/desktop/main/index.ts` - Composes profile ownership, worker storage, narrow IPC, hardened window policy, and packaged resource paths.
- `apps/desktop/store-worker/local-store.ts` - Runs synchronous node:sqlite only in the worker and owns transactions, migrations, replay, and settlement.
- `apps/desktop/store-worker/index.ts` - Provides the bounded worker request/response protocol.
- `apps/desktop/migrations/0001_initial.sql` - Creates the checksum-ledgered STRICT local schema.
- `apps/desktop/preload/index.ts` - Validates named capture/snapshot requests and responses with Zod and exposes no generic IPC.
- `apps/desktop/renderer/main.tsx` - Presents the Inbox capture tracer and the distinct local/synced trust states.
- `apps/desktop/test/application/offline-capture.test.ts` - Pins post-store local success and mismatch refusal.
- `apps/desktop/test/store/offline-capture.test.ts` - Pins real SQLite relaunch durability and checksum-drift retention.
- `apps/desktop/test/packaged/offline-capture.spec.ts` - Pins exact packaged capture, duplicate ownership rejection, hard kill, relaunch, and acknowledgement.
- `tooling/package-desktop.mjs` - Preserves symlinks, hashes exact copied bytes, and records the latest immutable manifest locator.
- `tooling/smoke-desktop-packaged.mjs` - Runs the named Playwright scenario against only the manifest-selected external executable.

## Decisions Made

- The developer explicitly approved only `electron@44.1.1` and `zod@4.5.4`; their npm/source provenance is Electron's official repository and Zod's `colinhacks/zod` repository. The conditional `better-sqlite3@13.0.3` fallback was not approved or installed.
- The developer explicitly confirmed D-03 with no alternate wording: draft has no durability claim, `Saved on this Mac` follows atomic local projection/outbox COMMIT, and `Synced` follows exact immutable identity/fingerprint acknowledgement.
- node:sqlite is selected for the desktop store because the exact Electron artifact passed stability, worker loading, WAL/FULL/foreign-key, crash recovery, exact settlement, and latency-bounded smoke predicates.
- Profile selection precedes `requestSingleInstanceLock()`, preserving independent disposable profiles while rejecting concurrent ownership of one profile.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Made Forge compatible with pnpm workspace layout**
- **Found during:** Task 3 package-once build
- **Issue:** Forge required a hoisted pnpm linker, and stale modules metadata exposed a malformed existing Tailwind/Vite peer snapshot.
- **Fix:** Added repository-owned `node-linker=hoisted`, regenerated the lockfile from unchanged manifests after explicit approval, and included `.npmrc` in artifact provenance.
- **Files modified:** `.npmrc`, `pnpm-lock.yaml`, `tooling/package-desktop.mjs`
- **Verification:** Frozen install, desktop typecheck, 4 focused tests, and 66 harness invariants passed.
- **Committed in:** `bd5c436`

**2. [Rule 3 - Blocking] Packaged only bundled runtime assets**
- **Found during:** Task 3 Forge dependency walk and resource finalization
- **Issue:** Forge attempted to traverse hoisted React dependencies even though runtime dependencies were already bundled, then referenced a nonexistent assets directory.
- **Fix:** Disabled dependency pruning, excluded node_modules, retained explicit process/migration resources, and removed the nonexistent assets entry.
- **Files modified:** `apps/desktop/forge.config.ts`
- **Verification:** Forge produced one `.app` and ZIP successfully.
- **Committed in:** `3634c22`, `47e3cf2`

**3. [Rule 1 - Bug] Preserved Electron framework symlink identity when copying**
- **Found during:** Task 3 artifact digest comparison
- **Issue:** Node's default recursive copy rewrote framework symlink targets, so the copied `.app` digest differed from the built application.
- **Fix:** Enabled verbatim symlink copying and ignored generated Forge output.
- **Files modified:** `tooling/package-desktop.mjs`, `.gitignore`
- **Verification:** Built and external copied application digests matched.
- **Committed in:** `a540316`

**4. [Rule 1 - Bug] Corrected packaged process resource paths and smoke selection**
- **Found during:** Task 3 first packaged launch
- **Issue:** Main looked below `Resources/dist/*` while Forge installed explicit resources at `Resources/{worker,preload,renderer}`; the smoke CLI also placed the filename where Playwright parsed it as another project.
- **Fix:** Added packaged/development-aware resource resolution and placed the optional test filename before project selection.
- **Files modified:** `apps/desktop/main/index.ts`, `tooling/smoke-desktop-packaged.mjs`
- **Verification:** The exact packaged app created its renderer window and executed the named Playwright case.
- **Committed in:** `4f0f803`

**5. [Rule 2 - Missing Critical] Enforced same-profile process ownership**
- **Found during:** Task 3 must-have audit after the first hard-kill smoke passed
- **Issue:** Two exact packaged processes could open the same disposable profile concurrently.
- **Fix:** Acquired Electron's single-instance lock after selecting userData and added a packaged duplicate-process rejection assertion.
- **Files modified:** `apps/desktop/main/index.ts`, `apps/desktop/test/packaged/offline-capture.spec.ts`
- **Verification:** `PACKAGED_PROFILE_OWNERSHIP accepted_instances=1 rejected_instances=1` appeared in two consecutive smokes of the same artifact.
- **Committed in:** `16c4ab8`

---

**Total deviations:** 5 auto-fixed (3 Rule 1/2 correctness fixes, 2 Rule 3 blocking build fixes)
**Impact on plan:** Every deviation was required to make the planned exact-artifact predicates executable; no product feature or dependency scope was added.

## Issues Encountered

- Package provenance, D-03 wording, lockfile regeneration, packaged resource correction, and ownership correction were each held at explicit human checkpoints before their authorized action.
- Forge required network access to fetch the approved Electron runtime material; the same command succeeded once run with authorized network access.

## User Setup Required

None. The artifact is an unsigned dogfood build; this plan makes no update-stable Keychain, public-distribution, notarization, or cryptographic-erasure claim.

## Known Stubs

None. Empty arrays and nulls found by the scan are bounded initial/test/protocol states; the renderer placeholder is actual input guidance, not unfinished behavior.

## Threat Surface Review

No unplanned trust boundary was introduced. Renderer IPC, worker persistence, profile ownership, and package evidence are all covered by the plan's threat register and executable verification.

## Next Phase Readiness

- Plans 03-02 through 03-06 can build synchronization, recovery, workspace, and resident lifecycle behavior on the proven D-03 worker/store/package boundary.
- The unsigned artifact limitation remains explicit and intentionally belongs to later release/signing work.

## Self-Check: PASSED

All ten implementation/test artifacts, this summary, and commits `15365ce`, `c596d47`, `bd5c436`, `3634c22`, `47e3cf2`, `a540316`, `4f0f803`, and `16c4ab8` were found after summary creation.

---
*Phase: KPL-03-mac-daily-loop*
*Completed: 2026-09-02*
