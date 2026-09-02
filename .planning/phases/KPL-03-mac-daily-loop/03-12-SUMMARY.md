---
phase: KPL-03-mac-daily-loop
plan: 12
subsystem: desktop-testing
tags: [electron, vitest, playwright, packaging, artifact-provenance]

requires:
  - phase: KPL-03-mac-daily-loop
    plan: 07
    provides: Desktop workspace, direct process builds, Forge ZIP configuration, and locked root commands
provides:
  - Anti-vacuous named Vitest and Playwright desktop test discovery
  - Disposable Electron profile allocation with normal-profile rejection
  - Package-once manifest binding source inputs, embedded runtime, application, executable, and ZIP digests
  - External manifest-only packaged smoke with app.isPackaged and exact-byte checks
  - Dependency-free focused and aggregate Wave-0 completeness verification
affects: [KPL-03-01, desktop-packaging, desktop-testing, release-evidence]

actuals:
  tokens: 6072
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns: [anti-vacuous named test projects, disposable profile guards, package-once immutable manifest, external exact-executable smoke]

key-files:
  created:
    - apps/desktop/vitest.config.ts
    - apps/desktop/playwright.config.ts
    - tooling/package-desktop.mjs
    - tooling/smoke-desktop-packaged.mjs
    - tooling/verify-desktop-harness.mjs
  modified: []

key-decisions:
  - "Keep application, renderer, store, worker, and hostile IPC discovery in explicit non-watch Vitest projects that fail when their selected lane has zero tests."
  - "Allocate every Electron test profile below a system-temporary root and reject the normal Keepling Application Support path before launch."
  - "Run Forge make once, copy the resulting application outside the repository, and make smoke consume only the manifest-selected copied executable without any build fallback."

patterns-established:
  - "Desktop evidence: every named lane has explicit discovery, finite execution, failure artifacts, and zero-case refusal."
  - "Artifact handoff: package produces immutable provenance; smoke verifies digests and packaged runtime without rebuilding."

requirements-completed: [MAC-01, MAC-02, MAC-03, MAC-04, MAC-05, QUAL-03, QUAL-04, SRV-02]

coverage:
  - id: D1
    description: "Named desktop test projects provide non-watch, zero-case-refusing discovery with disposable Electron profiles."
    requirement: QUAL-04
    verification:
      - kind: other
        ref: node tooling/verify-desktop-harness.mjs --all
        status: pass
    human_judgment: false
  - id: D2
    description: "Package-once records exact source, input, runtime, application, executable, and ZIP identity while copying the application outside source."
    requirement: QUAL-03
    verification:
      - kind: other
        ref: node tooling/verify-desktop-harness.mjs --all
        status: pass
    human_judgment: false
  - id: D3
    description: "Packaged smoke accepts only an explicit manifest and exact copied executable, verifies app.isPackaged, and has no build or development-server path."
    requirement: MAC-05
    verification:
      - kind: other
        ref: node tooling/verify-desktop-harness.mjs --all
        status: pass
    human_judgment: false

duration: 7min
completed: 2026-09-02
status: complete
---

# Phase KPL-03 Plan 12: Desktop Harness and Package Provenance Summary

**Anti-vacuous desktop test discovery with disposable profiles and a digest-bound package-once to external packaged-smoke handoff**

## Performance

- **Duration:** 7 min
- **Started:** 2026-09-02T05:54:31Z
- **Completed:** 2026-09-02T06:01:25Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Added five named Vitest projects plus serial Electron and packaged Playwright projects with explicit non-watch discovery and zero-test refusal.
- Added disposable system-temporary profile allocation and guards that reject Jon's normal Keepling application-data path.
- Added one-build Forge packaging that records exact tracked inputs, source revision, embedded runtime versions, application/executable/ZIP digests, and an outside-source copy.
- Added a manifest-only smoke consumer that verifies copied bytes and `app.isPackaged` without any build or development-server path.
- Added a dependency-free static verifier whose aggregate run reports 66 passing Wave-0 invariants.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create the dependency-free Wave-0 completeness verifier** - `8d91e7f` (test)
2. **Task 2: Create isolated test discovery plus package-once and external-smoke contracts** - `2f0c3eb` (test)
3. **Plan verification fix: Scope package cleanliness to artifact inputs** - `8a909a6` (fix)

## Files Created/Modified

- `apps/desktop/vitest.config.ts` - Names application, renderer, store, worker, and IPC discovery with explicit zero-case refusal.
- `apps/desktop/playwright.config.ts` - Defines serial Electron/package projects, failure evidence, and disposable profile helpers.
- `tooling/package-desktop.mjs` - Builds once, hashes inputs and outputs, captures embedded versions, and copies the application outside source.
- `tooling/smoke-desktop-packaged.mjs` - Requires an explicit manifest, verifies copied bytes, launches the exact executable, and asserts packaged runtime.
- `tooling/verify-desktop-harness.mjs` - Checks root/process/test/package/smoke contracts in focused or aggregate mode.

## Decisions Made

- Kept Plan 03-07's script-facing project names while making each discovery category explicit and independently invokable.
- Made the copied `.app` and manifest live under a unique system-temporary artifact root so smoke cannot accidentally exercise source-tree bytes.
- Scoped source cleanliness to the files contributing to the input digest, preserving unrelated user and planning changes without weakening provenance.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Scoped package cleanliness to artifact inputs**
- **Found during:** Overall plan verification after Task 2
- **Issue:** The initial package script rejected any dirty tracked repository file, so unrelated planning state could block a valid package even though it did not contribute to the recorded artifact.
- **Fix:** Restricted the cleanliness query to the exact tracked input list used for `inputDigestSha256`.
- **Files modified:** `tooling/package-desktop.mjs`
- **Verification:** Aggregate verifier passed 66 invariants, and an explicit status check proved dirty `.planning/state.json` is ignored while package inputs remain clean.
- **Committed in:** `8a909a6`

---

**Total deviations:** 1 auto-fixed (1 Rule 1 bug)
**Impact on plan:** The fix preserves exact artifact provenance while avoiding an unrelated-work blocker; no scope expansion was introduced.

## Issues Encountered

- Context7 was unavailable locally, so current official Vitest, Playwright, and Electron Forge documentation was consulted for project configuration, zero-test behavior, executable launch, and Forge make semantics.
- Desktop dependencies remain intentionally uninstalled until Plan 03-01's provenance checkpoint; this plan's required dependency-free static gate is complete without changing the lockfile.

## User Setup Required

None - package installation remains owned by Plan 03-01's explicit provenance checkpoint.

## Known Stubs

None. Discovery globs intentionally point to the production and adversarial cases owned by subsequent Phase 3 plans; zero-case refusal prevents those future lanes from passing before their tests exist.

## Threat Surface Review

No unplanned trust boundary was introduced. Test-profile access and package-to-smoke file access are the two threat-modelled boundaries, and both are enforced by system-temporary containment, normal-profile rejection, exact digests, outside-repository validation, and manifest-only launch.

## Next Phase Readiness

Plan 03-01 can install the human-approved exact desktop dependencies, add the packaged tracer sources/tests, and execute the already-defined package-once and external-smoke boundary. Until those cases are added, selected test lanes intentionally fail rather than report vacuous success.

## Self-Check: PASSED

All five implementation artifacts, this summary, and commits `8d91e7f`, `2f0c3eb`, and `8a909a6` were found. Coverage metadata classified all three deliverables as automatically evidenced by the passing aggregate verifier.

---
*Phase: KPL-03-mac-daily-loop*
*Completed: 2026-09-02*
