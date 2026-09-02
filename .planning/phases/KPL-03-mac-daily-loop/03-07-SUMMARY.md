---
phase: KPL-03-mac-daily-loop
plan: 07
subsystem: desktop-build
tags: [electron, vite, forge, typescript, macos]

requires:
  - phase: KPL-02-synchronization-and-replaceable-server
    provides: Released synchronization contracts and native-client authority boundaries
provides:
  - Seven locked root desktop commands delegated to one workspace package
  - Direct main, preload, renderer, and worker Vite build boundaries
  - Forge ZIP/resource configuration and a restrictive local renderer entry
affects: [KPL-03-12, KPL-03-01, desktop-packaging, desktop-testing]

actuals:
  tokens: 2331
  tasks: 2
  commits: 3

tech-stack:
  added: []
  patterns: [direct per-process Vite builds, packaged relative renderer assets, Forge ZIP without experimental Vite plugin]

key-files:
  created:
    - apps/desktop/package.json
    - apps/desktop/forge.config.ts
    - apps/desktop/tsconfig.json
    - apps/desktop/vite.main.config.ts
    - apps/desktop/vite.preload.config.ts
    - apps/desktop/vite.renderer.config.ts
    - apps/desktop/vite.worker.config.ts
    - apps/desktop/renderer/index.html
  modified:
    - package.json

key-decisions:
  - "Use direct Vite builds for all four Electron process roles and keep the experimental Forge Vite plugin out of the package path."
  - "Use CommonJS Node 24 outputs for main, preload, and worker while keeping renderer output browser-only with relative packaged assets."
  - "Declare the audited Electron, Forge, and Zod pins without installing packages or changing pnpm-lock.yaml before the provenance gate."

patterns-established:
  - "Process isolation: main, preload, renderer, and worker use distinct source entries and output directories."
  - "Packaged renderer: relative URLs and a deny-by-default CSP prevent a production dependency on a development server."

requirements-completed: [MAC-01, MAC-02, MAC-03, MAC-04, MAC-05, QUAL-03, QUAL-04, SRV-02]

coverage:
  - id: D1
    description: Root desktop commands resolve through one workspace package to explicit build, test, package-once, and smoke entry points.
    requirement: QUAL-03
    verification:
      - kind: other
        ref: node static root/desktop command and exact-pin verification
        status: pass
    human_judgment: false
  - id: D2
    description: Four process builds use distinct entries and outputs, and the renderer has a local relative entry with restrictive CSP.
    requirement: MAC-05
    verification:
      - kind: other
        ref: node static process-boundary, CSP, and TypeScript-transpilation verification
        status: pass
    human_judgment: false

duration: 4min
completed: 2026-09-02
status: complete
---

# Phase KPL-03 Plan 07: Desktop Build Foundation Summary

**A pinned Electron workspace with direct four-process Vite builds, Forge ZIP resources, and a dev-server-free local renderer entry**

## Performance

- **Duration:** 4 min
- **Started:** 2026-09-02T05:44:27Z
- **Completed:** 2026-09-02T05:48:37Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments

- Added all seven locked root desktop commands and grounded them in the desktop workspace.
- Declared the audited Electron 44.1.1, Forge 7.11.2, and Zod 4.5.4 pins without installing or changing the lockfile.
- Added deterministic main, preload, renderer, and worker build inputs plus a packaged renderer document with restrictive CSP and relative assets.

## Task Commits

Each task was committed atomically:

1. **Task 1: Ground root commands, desktop metadata, Forge inputs, and TypeScript boundaries** - `716866f` (chore)
2. **Task 2: Create direct Vite process builds and renderer HTML entry** - `55a9a4c` (chore)

## Files Created/Modified

- `package.json` - Exposes the seven locked desktop commands.
- `apps/desktop/package.json` - Owns direct build, test, package, smoke, and typecheck scripts plus audited dependency pins.
- `apps/desktop/forge.config.ts` - Configures the macOS ZIP maker and explicit packaged process/migration/asset resources.
- `apps/desktop/tsconfig.json` - Covers all four desktop process source roots and their configuration inputs.
- `apps/desktop/vite.main.config.ts` - Builds the Electron main entry as Node-targeted CommonJS.
- `apps/desktop/vite.preload.config.ts` - Builds the sandbox preload entry as Node-targeted CommonJS.
- `apps/desktop/vite.renderer.config.ts` - Builds browser-only renderer assets with relative packaged paths.
- `apps/desktop/vite.worker.config.ts` - Builds the supervised store worker as Node-targeted CommonJS.
- `apps/desktop/renderer/index.html` - Provides the local renderer root and deny-by-default CSP.

## Decisions Made

- Direct Vite configs remain ordinary build inputs; Forge consumes their output resources without the experimental Forge Vite plugin.
- Main, preload, and worker externalize only Node/Electron built-ins so application dependencies can be bundled deliberately later.
- Renderer HMR exists only through the development command; packaged configuration contains no development-server address or fallback.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - dependency installation remains intentionally blocked until Plan 03-01's package-provenance checkpoint.

## Known Stubs

None. The source entries and test/package harnesses named by this foundation are owned by dependent Plans 03-01 and 03-12 rather than placeholder implementations in this plan.

## Threat Surface Review

No unplanned trust boundary was introduced. The build-entry tampering surface is covered by explicit role inputs/outputs and resource declarations; package installation and executable smoke remain gated by the planned provenance and exact-artifact work.

## Next Phase Readiness

Plan 03-12 can now add isolated Vitest/Playwright discovery plus package-once and external-smoke tooling without changing process ownership or command names. No blocker remains in this plan.

## Self-Check: PASSED

All nine implementation artifacts and both atomic task commits were found after summary creation.

---
*Phase: KPL-03-mac-daily-loop*
*Completed: 2026-09-02*
