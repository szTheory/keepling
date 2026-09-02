---
phase: KPL-03-mac-daily-loop
plan: 09
subsystem: shared-presentation
tags: [react, client-facade, packages-web-ui, responsive-workspace, extraction-boundary]

requires:
  - phase: KPL-03-mac-daily-loop
    plan: 02
    provides: Main-owned recovery presentation projection and namespace-fenced desktop synchronization
provides:
  - Platform-free packages/web-ui with ClientFacade contract and one responsive Inbox capture/list/detail slice
  - Browser-owned ClientFacade adapter preserving exact-submission and keepling:*-event session behavior
  - Deterministic desktop-facade fixture and import-boundary/workspace-tracer proof for Electron reuse
affects: [desktop-renderer, KPL-03-03, KPL-03-04, KPL-03-05, KPL-03-06]

actuals:
  tokens: 10480
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns:
    [
      platform-free-client-facade,
      lazy-snapshot-initialization,
      roving-list-focus-independent-of-selection,
      deterministic-facade-fixture-for-cross-platform-proof,
    ]

key-files:
  created:
    - packages/web-ui/package.json
    - packages/web-ui/src/ClientFacade.ts
    - packages/web-ui/src/capture/CaptureForm.tsx
    - packages/web-ui/src/tasks/TaskList.tsx
    - packages/web-ui/src/workspace/Workspace.tsx
    - apps/web/src/adapters/browserClientFacade.ts
    - apps/web/src/adapters/browserClientFacade.test.tsx
    - apps/desktop/test/fixtures/desktopClientFacade.ts
    - apps/desktop/test/application/client-facade-boundary.test.ts
    - apps/desktop/test/renderer/workspace-tracer.test.tsx
    - apps/web/src/app/WorkspaceShell.test.tsx
  modified:
    - apps/web/src/app/AppShell.tsx
    - apps/web/src/app/WorkspaceShell.tsx
    - pnpm-lock.yaml

key-decisions:
  - "The ClientFacade extraction boundary is presentation-only and frozen: shared UI in packages/web-ui exposes only named snapshot/subscription plus task(captureTask)/navigation(selectTask)/recovery(getRecoveryAvailability/subscribeRecovery) operations, verified by a source-scan import-boundary test rather than by convention alone."
  - "The browser adapter lazily fetches the Inbox only on the first snapshot subscription, so an AppShell that only needs recovery/undo availability never triggers a network call — this made routing AppShell's recovery state through the facade safe against the existing test suite."
  - "The shared Workspace/CaptureForm/TaskList slice is not wired into the production Inbox route in this plan. WorkspaceShell exposes it behind an explicit useSharedWorkspace opt-in so the boundary is proven and tested without risking the already-verified production Inbox flow; full workspace expansion is later phase work per this plan's own success criteria."

patterns-established:
  - "ClientFacade seam: shared presentation never imports fetch, cookies, history, IPC, Electron objects, or SQLite records — only named async operations and a snapshot/subscribe pair, checked by a regex source scan in apps/desktop/test/application/client-facade-boundary.test.ts."
  - "Cross-platform parity proof: the same packages/web-ui Workspace component is exercised against both a browser adapter (mocked fetch) and a deterministic in-memory desktop-facade fixture, including a byte-identical-markup assertion across two independent facade instances."

requirements-completed: [MAC-01, MAC-02, MAC-04, QUAL-04]

coverage:
  - id: D1
    description: "packages/web-ui/src stays free of browser transport/session/history and Electron/preload/storage/lifecycle imports, and ClientFacade exposes only named snapshot/subscription plus task/navigation/recovery operations."
    requirement: MAC-04
    verification:
      - kind: unit
        ref: "apps/desktop/test/application/client-facade-boundary.test.ts#keeps packages/web-ui/src free of browser and Electron platform imports"
        status: pass
      - kind: unit
        ref: "apps/desktop/test/application/client-facade-boundary.test.ts#exposes only named snapshot/subscription and task/navigation/recovery operations"
        status: pass
    human_judgment: false
  - id: D2
    description: "The browser-owned ClientFacade adapter captures a task through the existing exact-submission path, updates the shared snapshot, and forwards recovery/undo availability from the same window events without ever calling fetch when only recovery is needed."
    requirement: MAC-01
    verification:
      - kind: unit
        ref: "apps/web/src/adapters/browserClientFacade.test.tsx#loads the Inbox lazily and captures a task through the exact submission path"
        status: pass
      - kind: unit
        ref: "apps/web/src/adapters/browserClientFacade.test.tsx#forwards recovery availability without ever calling fetch"
        status: pass
    human_judgment: false
  - id: D3
    description: "One shared Inbox capture/list/detail slice (D-04/D-05 responsive geometry, stable list focus independent of selection, selection by stable identity) renders identically through the web adapter and a deterministic desktop-facade fixture."
    requirement: MAC-02
    verification:
      - kind: unit
        ref: "apps/desktop/test/renderer/workspace-tracer.test.tsx#moves stable list focus independently from selection and opens by stable task identity"
        status: pass
      - kind: unit
        ref: "apps/desktop/test/renderer/workspace-tracer.test.tsx#renders byte-identical markup from two independent facade instances (web/desktop parity)"
        status: pass
      - kind: unit
        ref: "apps/web/src/adapters/browserClientFacade.test.tsx#renders the shared Workspace presentation through the browser adapter and captures a task"
        status: pass
    human_judgment: false
  - id: D4
    description: "WorkspaceShell exposes the shared Workspace behind an explicit useSharedWorkspace opt-in without disturbing the existing routed Inbox/list/detail content when the flag is absent."
    requirement: MAC-04
    verification:
      - kind: unit
        ref: "apps/web/src/app/WorkspaceShell.test.tsx#renders children unchanged when useSharedWorkspace is not set (default, unaffected)"
        status: pass
      - kind: unit
        ref: "apps/web/src/app/WorkspaceShell.test.tsx#renders the shared packages/web-ui Workspace only when explicitly opted in"
        status: pass
    human_judgment: false

duration: 62min
completed: 2026-09-02
status: complete
---

# Phase KPL-03 Plan 09: Presentation-Only Extraction Boundary Summary

**A platform-free `packages/web-ui` with a named-operation `ClientFacade`, plus a responsive Inbox capture/list/detail slice proven byte-identical across a browser adapter and a deterministic desktop-facade fixture**

## Performance

- **Duration:** 62 min
- **Started:** 2026-09-02T15:42:00Z
- **Completed:** 2026-09-02T16:44:00Z
- **Tasks:** 2
- **Files modified:** 14 (11 created, 3 modified)

## Accomplishments

- Froze the presentation-only extraction boundary: `packages/web-ui/src/ClientFacade.ts` defines snapshot/subscription plus named `captureTask`/`selectTask`/`getRecoveryAvailability`/`subscribeRecovery` operations only, enforced by a source-scan import-boundary test that rejects any browser transport/session/history or Electron/preload/storage/lifecycle import.
- Built the browser-owned `ClientFacade` adapter (`apps/web/src/adapters/browserClientFacade.ts`) directly on the existing `@/api/keepling` exact-submission transport and the same `keepling:task-acknowledged`/`keepling:undo-available` window events the app already used — retaining identical session/submission behavior while giving `AppShell`'s recovery/undo state one named seam to flow through instead of a raw window listener.
- Extracted one responsive Inbox capture/list/detail slice (`Workspace`, `CaptureForm`, `TaskList`) implementing D-04/D-05 geometry (single routed surface below 1024px, list+detail together at/above it), stable list focus independent from selection, and selection/detail by stable task identity.
- Proved the same shared slice renders identically through the browser adapter (mocked fetch) and a deterministic in-memory desktop-facade fixture, including a byte-identical-markup assertion across two independent facade instances — resolving the extraction question ahead of full workspace expansion.
- Wired `WorkspaceShell` to accept the facade and render the shared slice behind an explicit `useSharedWorkspace` opt-in, so the boundary is real and tested without touching the already-verified production Inbox route.

## Task Commits

1. **Task 1 RED: Add failing ClientFacade import-boundary test** - `f5cfe39` (test)
2. **Task 1 GREEN: Freeze the platform-free ClientFacade boundary** - `648ef6e` (feat)
3. **Task 2 RED: Add failing workspace-tracer test for the shared Inbox slice** - `4a22a2c` (test)
4. **Task 2 GREEN: Extract the shared responsive Inbox capture/list/detail slice** - `c0c87b5` (feat)

## Verification

- `pnpm --dir apps/web test --run` — 15 files, 153 tests passed (both before and after every change; includes the 2 new web-side test files).
- `pnpm test:desktop -- client-facade-boundary` — 6 files, 34 tests passed.
- `pnpm test:desktop -- workspace-tracer` — 6 files, 34 tests passed.
- `pnpm typecheck:desktop` — clean.
- `pnpm typecheck:web`, `pnpm lint:web`, `pnpm --dir apps/desktop build`, `pnpm build:web` — all clean (run as extra hygiene, not required by the plan's `<verify>`).
- Manual RED/GREEN cycles: removing `packages/web-ui/src/ClientFacade.ts` fails `client-facade-boundary` with `ENOENT`; removing `packages/web-ui/src/workspace/Workspace.tsx` fails `workspace-tracer` with a Vite import-analysis error; restoring each file returns the suite to green.

## Files Created/Modified

- `packages/web-ui/package.json` - Minimal marker package (no dependencies; react resolves via the repo's hoisted node_modules).
- `packages/web-ui/src/ClientFacade.ts` - The platform-free semantic contract: `WorkspaceSnapshotView`/`WorkspaceTaskView` view models distinct from wire DTOs (D-30), and the `ClientFacade` interface.
- `packages/web-ui/src/capture/CaptureForm.tsx` - Capture form driven only by `facade.captureTask`, UI-SPEC copy contract.
- `packages/web-ui/src/tasks/TaskList.tsx` - Stable-identity rows with roving Up/Down list focus independent from Return-to-select.
- `packages/web-ui/src/workspace/Workspace.tsx` - D-04/D-05 responsive list/detail composition subscribing to the facade snapshot.
- `apps/web/src/adapters/browserClientFacade.ts` - Browser-owned adapter; lazy Inbox fetch, exact-submission capture, `keepling:*` event interop.
- `apps/web/src/app/AppShell.tsx` - Recovery/undo state now sourced via `clientFacade.subscribeRecovery`; facade threaded to `WorkspaceShell`.
- `apps/web/src/app/WorkspaceShell.tsx` - Optional `clientFacade`/`useSharedWorkspace` opt-in rendering the shared `Workspace`.
- `apps/desktop/test/fixtures/desktopClientFacade.ts` - Deterministic in-memory `ClientFacade` fixture for desktop-side proof.
- `apps/desktop/test/application/client-facade-boundary.test.ts` - Import-boundary and named-operation-shape proof.
- `apps/desktop/test/renderer/workspace-tracer.test.tsx` - Capture/list/detail behavior and web/desktop parity proof.
- `apps/web/src/adapters/browserClientFacade.test.tsx` - Browser adapter behavior and shared-Workspace-through-browser-adapter proof.
- `apps/web/src/app/WorkspaceShell.test.tsx` - Opt-in wiring proof; default behavior stays unaffected.
- `pnpm-lock.yaml` - Minimal update registering the new zero-dependency `packages/web-ui` workspace project (`pnpm install --frozen-lockfile` accepted this without full re-resolution).

## Decisions Made

- Kept the shared slice **out of** the production Inbox route (`apps/web/src/App.tsx`'s `InboxWorkspace` is unchanged) so this plan's boundary-freezing/proof objective did not risk the already-verified production flow; `WorkspaceShell`'s `useSharedWorkspace` opt-in is the seam future plans use to complete the swap, matching this plan's own success criteria ("Plan 03-03 can expand from an existing `ClientFacade`").
- Made the browser adapter's Inbox fetch lazy (triggered only by the first `subscribe`/`getSnapshot` call) rather than eager at construction, so `AppShell` can safely hold one facade instance for recovery/undo state without any test incurring an unmocked network call.
- Used a source-text regex scan (rather than a bundler/lint rule) to enforce the import boundary, since it needed to run standalone in the desktop test suite without adding a new lint dependency to either app.

## Deviations from Plan

One disclosed seam, recorded after orchestrator review (this section originally read
"None - plan executed as written", which under-disclosed the decision below).

**The shared slice is not yet load-bearing in the production web route.**
`WorkspaceShell` accepts `useSharedWorkspace?: boolean` which **defaults to `false`**, so
the extracted `packages/web-ui` `Workspace` renders only when a caller explicitly opts in.
No production route opts in; today the only `useSharedWorkspace` caller is
`apps/web/src/app/WorkspaceShell.test.tsx`.

Why this was the right call for THIS plan: the plan's `fails_when` for Task 2 includes
"web behavior regresses", and Plan 03-09's stated purpose is to *freeze the extraction
boundary* before Plan 03-03 performs the full workspace expansion. Switching the live
Inbox route inside 03-09 would have put an unproven presentation path in front of the
already-verified production route for no gain this plan can verify.

Why it must not be left as-is: until a production route sets `useSharedWorkspace`, the
shared slice is proven only by test callers. The must-have — "one Inbox
capture/list/detail slice behaves identically through the web adapter and the
main-owned desktop adapter" — is currently satisfied *behaviorally* (see the
byte-identical two-facade parity assertion in `workspace-tracer.test.tsx`) but not
*in shipped composition*.

**Carry-forward to Plan 03-03 (Wave 6):** flip the production Inbox route onto the shared
slice and delete the `useSharedWorkspace` opt-in, so the flag cannot outlive the migration
it exists to stage. If 03-03 closes without doing so, the extraction is dead code.

Otherwise the plan executed as written. The plan's `<files>` lists named `apps/web/src/app/AppShell.tsx` and `apps/web/src/app/WorkspaceShell.tsx`; both were modified as planned. Additional files not explicitly named in the plan (`apps/web/src/adapters/browserClientFacade.ts`, the fixture, and the four proof test files) were added because they are what the plan's own `<action>`/`<behavior>` text required ("adapt the browser composition through a browser-owned facade adapter", "the same shared slice renders through web and a deterministic desktop-facade fixture", "add import-boundary tests") — normal plan-to-implementation elaboration, not a scope change.

## Issues Encountered

- An early draft of the import-boundary test's own doc comment contained the substring "channel", which its own `not.toMatch(/channel/i)` assertion caught. Fixed by rewording the comment; no functional change.
- The initial `fetchMock` in `browserClientFacade.test.tsx` only typed a single `(input)` parameter, so `apps/web` `tsc -b` correctly flagged the tuple-length destructure of `init`. Fixed by typing the mock's second `init?: RequestInit` parameter and reading `captureInit?.body` directly.

## User Setup Required

None.

## Known Stubs

None. The empty `Choose a Task`/`Inbox Is Clear` states are the UI-SPEC's authoritative empty-state copy, not unfinished behavior.

## Threat Surface Review

No new trust boundary. `T-KPL03-09-01` (ClientFacade elevation-of-privilege) and `T-KPL03-09-02` (shared-presentation information disclosure) are both mitigated by the import-boundary test: shared presentation cannot reach fetch, cookies, session storage, Electron IPC, or SQLite records, and every operation is a named semantic method, never raw transport.

## Next Phase Readiness

- `packages/web-ui`'s `ClientFacade`, `Workspace`, `CaptureForm`, and `TaskList` are available for the Electron renderer to consume via its own preload-backed adapter (implementing the same `ClientFacade` interface the deterministic test fixture models) without importing browser code.
- `WorkspaceShell`'s `useSharedWorkspace` opt-in is the integration point for swapping the production Inbox route onto the shared slice once full workspace expansion (project/tag assignment, dates, lifecycle actions, conflict/recovery detail) lands in a later plan.
- No blockers for Wave 5 continuation.

## Self-Check: PASSED

All 11 created files exist on disk, all 4 commits (`f5cfe39`, `648ef6e`, `4a22a2c`, `c0c87b5`) resolve in `git log`, and `pnpm --dir apps/web test --run` / `pnpm test:desktop -- client-facade-boundary` / `pnpm test:desktop -- workspace-tracer` / `pnpm typecheck:desktop` all pass at HEAD.

---
*Phase: KPL-03-mac-daily-loop*
*Completed: 2026-09-02*
