---
phase: KPL-03-mac-daily-loop
plan: 10
subsystem: desktop-security-boundary
tags: [electron, ipc, zod, csp, custom-protocol, sender-validation, sequence-contract]

requires:
  - phase: KPL-03-mac-daily-loop
    plan: 03
    provides: The desktop main/index.ts, preload/index.ts, preload/contracts.ts surface this plan hardens (edit/lifecycle/undo/conflict IPC channels)
provides:
  - A privileged custom app://renderer/... local protocol that serves only packaged renderer assets, confining path-traversal/wrong-scheme/wrong-host requests to the renderer root by construction
  - Session-wide CSP, deny-all Electron permission request/check handlers, and navigation/window-open policy restricted to the same-origin app:// content, applied at the Electron session level so any future utility window inherits the same defaults without per-window wiring
  - Centralized, strict, .strict() zod request/response schemas (preload/contracts.ts) parsed on BOTH the preload side and, newly, the main-process side -- main no longer trusts preload's validation, since a compromised renderer can call ipcRenderer.invoke directly and bypass preload entirely
  - Sender/frame-bound IPC trust (main/protocol.ts#isTrustedIpcSender) consulted by every ipcMain.handle before any DesktopApplication call
  - The D-29 presentation sequence contract: preload's push listener is registered at module load (before any subscriber can exist), and missing/out-of-order/duplicate sequences trigger an opaque presentation-snapshot refetch rather than an unsafe increment
  - A 46-case hostile two-sided bridge and sequence proof (test/ipc/hostile-bridge.test.ts) covering strict-schema hostile fields, forged sender/frame, packaged content/navigation/permission policy, sequence gaps, and reload/crash reconstruction
affects: [KPL-03-11, KPL-03-05, KPL-03-06, KPL-03-08, ship-readiness]

actuals:
  tokens: 15200
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    [
      session-level-security-policy-not-per-window,
      main-process-revalidates-every-ipc-request,
      always-on-preload-listener-before-any-subscriber,
      opaque-sequence-gap-refetch,
      pure-testable-security-decision-functions,
    ]

key-files:
  created:
    - apps/desktop/main/protocol.ts
    - apps/desktop/test/ipc/hostile-bridge.test.ts
  modified:
    - apps/desktop/main/index.ts
    - apps/desktop/preload/contracts.ts
    - apps/desktop/preload/index.ts

key-decisions:
  - "Registered a privileged custom `app://renderer/...` scheme (via `protocol.registerSchemesAsPrivileged` + `protocol.handle`) instead of continuing to `loadFile` a plain `file://` path. `protocol.handle` resolves requests through a pure, unit-tested `resolvePackagedAssetPath` function before ever touching the filesystem, so content substitution and directory-traversal navigation fail closed structurally, not by convention."
  - "Moved every request/response schema out of `preload/index.ts` into `preload/contracts.ts` and now parse incoming IPC requests a SECOND time on the main-process side inside every `ipcMain.handle`. Preload-only validation is not a real security boundary -- a compromised/hostile renderer can call `ipcRenderer.invoke('keepling:capture', anything)` directly, skipping the preload bridge module entirely. The main-side parse (via `parseTrustedRequest`, which converts any Zod failure into a bounded `IpcSecurityError` rather than leaking raw Zod internals across the boundary) is the actual enforcement point."
  - "All security policy (permission handler, CSP header, custom-protocol registration) is installed at `session.defaultSession`, not per-`BrowserWindow`. This was a deliberate choice so that Plan 03-04's already-built-but-unwired utility windows (Quick Entry/Settings, `preload/utility-preload.ts`) inherit the exact same restrictive defaults the moment a later plan constructs them -- without this plan needing to touch `main/windows/*.ts` or `preload/utility-preload.ts` at all."
  - "The D-29 sequence contract is implemented entirely inside `preload/index.ts`, transparent to the renderer facade (`apps/desktop/renderer/desktopClientFacade.ts`, out of this plan's scope). The `ipcRenderer.on('keepling:presentation-changed', ...)` listener is registered unconditionally at preload module load -- before any renderer script runs, and before any caller ever calls `subscribePresentation` -- so there is never a window in which a push can arrive unobserved. `subscribePresentation` itself just adds a subscriber and requests one authoritative baseline; a detected sequence gap always triggers a fresh `keepling:presentation-snapshot` refetch rather than trying to reconstruct what was skipped."
  - "Kept the external-link allowlist (`EXTERNAL_LINK_ALLOWED_ORIGINS`) explicit and empty rather than allowing any `https:` origin. The app has no external links today; `setWindowOpenHandler` always denies window creation and only calls `shell.openExternal` for an allowlisted origin, so adding a real external link later is a one-line addition to a reviewed set, never a blanket allow."

patterns-established:
  - "Session-level, not window-level, security policy: permission handling, CSP, and custom-protocol registration are installed once on `session.defaultSession` so every current and future renderer surface (main window, Quick Entry, Settings) is covered without re-wiring."
  - "Pure, testable security decision functions: every hostile-input decision (`resolvePackagedAssetPath`, `isAllowedNavigationTarget`, `isAllowedExternalLinkTarget`, `shouldGrantPermission`, `isTrustedIpcSender`, `decideSequenceOutcome`) is a pure function taking plain data, not a live Electron object -- so the entire hostile-bridge suite runs in plain Node/vitest without a live Electron process, and the exact function main/preload actually calls is what gets exercised."

requirements-completed: [MAC-03, MAC-04, MAC-05, QUAL-04]

coverage:
  - id: D1
    description: "Hostile renderer requests (extra/deep fields, malformed unions, prototype-pollution shapes, wrong-typed clone-unsafe values) fail closed on BOTH the preload and main-process schema parse, and a hostile preload call never reaches ipcRenderer.invoke -- proven both by direct schema tests and by a mocked-electron preload integration test asserting the invoke mock is never called for a malformed request."
    requirement: MAC-05
    verification:
      - kind: unit
        ref: "apps/desktop/test/ipc/hostile-bridge.test.ts (preload/main strict request and response schemas + preload bridge hostile-call suites, 28 cases)"
        status: pass
    human_judgment: false
  - id: D2
    description: "A forged sender id, a subframe injection, or a frame whose URL escaped the packaged app:// origin all fail the sender/frame trust check every ipcMain.handle consults before touching DesktopApplication; a static source scan additionally proves every registered handler actually calls that check first, and that the preload bridge exposes no generic invoke/send escape hatch."
    requirement: MAC-05
    verification:
      - kind: unit
        ref: "apps/desktop/test/ipc/hostile-bridge.test.ts (sender/frame trust + static-scan suites, 9 cases)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Packaged content substitution, directory-traversal navigation, unexpected external navigation, unexpected window creation, and every Electron permission request all fail closed -- the renderer only ever loads content from, and only ever navigates within, the packaged app://renderer origin."
    requirement: MAC-03
    verification:
      - kind: unit
        ref: "apps/desktop/test/ipc/hostile-bridge.test.ts (packaged content and navigation policy suite, 8 cases)"
        status: pass
      - kind: e2e
        ref: "apps/desktop/test/e2e/daily-loop.spec.ts (2 cases, real Electron app now loading app://renderer/index.html through the new custom protocol)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Missing/out-of-order/duplicate presentation sequences trigger an opaque refetch rather than an unsafe increment, proven as a pure decision function and through the real preload bridge (mocked electron): a gap triggers exactly one keepling:presentation-snapshot refetch and delivers only the refetched value, never the gapped push."
    requirement: MAC-04
    verification:
      - kind: unit
        ref: "apps/desktop/test/ipc/hostile-bridge.test.ts (D-29 sequence suites, 8 cases)"
        status: pass
    human_judgment: false
  - id: D5
    description: "A renderer that reloads or crashes after a local COMMIT reconstructs the committed task from a fresh, opaque snapshot fetch -- accepted intent is never lost."
    requirement: QUAL-04
    verification:
      - kind: unit
        ref: "apps/desktop/test/ipc/hostile-bridge.test.ts#a fresh (post-reload/crash) subscriber snapshot still contains the task committed before the renderer failure, via a fresh opaque fetch"
        status: pass
    human_judgment: false

duration: ~45min
completed: 2026-09-02
status: complete
---

# Phase KPL-03 Plan 10: Hostile Renderer and Packaged-Content Boundary Summary

**A custom `app://renderer/...` protocol replaces `file://` loading, every IPC request is re-validated on the main-process side (not just preload), sender/frame trust and the D-29 sequence contract are pure/testable, and a 46-case hostile-bridge suite proves every hostile field/sender/navigation/permission/sequence case fails closed without a privileged effect**

## Performance

- **Duration:** ~45 min
- **Tasks:** 2
- **Files modified:** 5 (2 created, 3 modified)

## Accomplishments

- Registered a privileged custom `app://renderer/...` local protocol (`main/protocol.ts` + `main/index.ts`) that serves only packaged renderer assets through a pure, unit-tested `resolvePackagedAssetPath` resolver; the main window now loads `app://renderer/index.html` instead of a plain `file://` path.
- Installed session-wide CSP (`default-src 'self'`, no `unsafe-eval`, `object-src 'none'`, `frame-ancestors 'none'`), a deny-all Electron permission request/check handler, and navigation/window-open policy restricted to same-origin `app://` content (with an explicit, currently-empty external-link allowlist routed through `shell.openExternal`) -- all installed at `session.defaultSession`, not per-window, so future utility windows inherit the same defaults for free.
- Centralized every request/response schema into `preload/contracts.ts` and now parse every incoming IPC request a second time inside `main/index.ts`'s `ipcMain.handle` callbacks -- the preload parse is defense in depth; the main-process parse (via `parseTrustedRequest`, converting any Zod failure into a bounded `IpcSecurityError`) is the real enforcement boundary, since a compromised renderer can call `ipcRenderer.invoke` directly and skip preload.
- Added sender/frame-bound trust (`isTrustedIpcSender`/`assertTrustedIpcSender`) consulted by every handler; forged sender id, subframe injection, and off-origin frame URLs all fail closed.
- Implemented the D-29 presentation sequence contract entirely inside preload: the push listener is registered at module load (before any subscriber exists), and missing/out-of-order/duplicate sequences trigger an opaque `keepling:presentation-snapshot` refetch instead of an unsafe increment.
- Wrote `test/ipc/hostile-bridge.test.ts`: 46 passing cases spanning strict-schema hostile fields (extra/deep/prototype-pollution/wrong-typed), sender/frame forgery, a static source scan proving every handler is actually wired to the trust check and the preload exposes no generic IPC, packaged content/navigation/permission policy, the D-29 sequence contract (pure function and live mocked-preload integration), and reload/crash reconstruction from an opaque snapshot.
- Re-ran the full existing desktop suite (95 unit/integration tests) and the real Electron E2E specs (`daily-loop.spec.ts`, `real-stack-sync.spec.ts`, and 03-04's `keyboard-menus.spec.ts`/`keyboard-quick-entry.spec.ts`) against the hardened app -- all still pass, confirming the new protocol/CSP/validation layer does not regress any existing behavior.

## Task Commits

1. **Task 1: Harden packaged content, BrowserWindow privileges, and named preload contracts** - `a1e874c` (feat)
2. **Task 2: Prove hostile schemas, senders, cloning, sequence gaps, reload, and crash** - `4d751c6` (test)

_Note: Both tasks carried `tdd="true"`. See "TDD Gate Compliance" below._

## Files Created/Modified

- `apps/desktop/main/protocol.ts` - Pure, testable security-decision functions: packaged-asset resolution, navigation/external-link allowlisting, permission deny-all, sender/frame trust, bounded request parsing.
- `apps/desktop/main/index.ts` - Registers the `app://` scheme, installs session-wide CSP/permission policy, serves packaged assets through `protocol.handle`, validates every IPC request's sender AND schema before touching `DesktopApplication`, restricts navigation/window-open.
- `apps/desktop/preload/contracts.ts` - Centralized every request/response zod schema (moved from `preload/index.ts`); added the pure `decideSequenceOutcome` D-29 sequence-gap decision function.
- `apps/desktop/preload/index.ts` - Imports centralized schemas; implements the always-on presentation-sequence listener and opaque-refetch-on-gap logic; `subscribePresentation` now delivers an immediate authoritative baseline to each new subscriber.
- `apps/desktop/test/ipc/hostile-bridge.test.ts` - 46-case hostile two-sided bridge and sequence proof.

## Decisions Made

See `key-decisions` in frontmatter.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `resolvePackagedAssetPath`'s traversal-denial test assumption was wrong; fixed the test, not the implementation**
- **Found during:** Task 2, first `pnpm test:desktop:ipc` run.
- **Issue:** My initial test asserted `resolvePackagedAssetPath` returns `null` for a `..`-laden traversal URL. It does not need to -- Node's/Electron's WHATWG `URL` parser already collapses dot-segments in the *pathname* for a "standard" (host-bearing) custom scheme before `resolvePackagedAssetPath` ever sees it, clamping the result at the URL's own root. `resolve(rendererRoot, '.' + alreadyClampedPathname)` can therefore never escape `rendererRoot` -- the implementation was already correct; my test's expected outcome (`null`) was wrong for that specific input shape.
- **Fix:** Rewrote the test to assert containment (`resolved === rendererRoot || resolved.startsWith(rendererRoot + '/')`) and that the literal attacker-intended target (`/etc/passwd`) is never what gets resolved, rather than asserting `null`. Kept the genuine-denial cases (wrong scheme, wrong host, malformed URL) which correctly return `null`.
- **Files modified:** `apps/desktop/test/ipc/hostile-bridge.test.ts` (test-only; no implementation change was needed).
- **Verification:** `pnpm test:desktop:ipc` — all 46 cases pass.
- **Committed in:** `4d751c6` (Task 2 commit; the corrected version was what was committed, not a follow-up fix).

**2. [Rule 1 - Bug] Mock response shape mismatch in a well-formed-request smoke test**
- **Found during:** Task 2, first `pnpm test:desktop:ipc` run.
- **Issue:** The default `ipcRendererMock.invoke` mock returned a bare `{ tasks: [...] }` snapshot for every channel; `keepling.capture()` parses its response against `localAcceptanceSchema` (a different shape: `fingerprint`/`mutationId`/`snapshot`/`status`), so the "well-formed request reaches invoke" smoke test failed with a schema mismatch, not the hostile-input rejection it was meant to prove.
- **Fix:** Mocked `ipcRendererMock.invoke` to return a valid `localAcceptanceSchema`-shaped response for that specific test.
- **Files modified:** `apps/desktop/test/ipc/hostile-bridge.test.ts` (test-only).
- **Verification:** `pnpm test:desktop:ipc` — all 46 cases pass.
- **Committed in:** `4d751c6`.

---

**Total deviations:** 2 auto-fixed, both test-only corrections found and fixed during the first real test run, before committing. **Impact:** No implementation change was required for either; both confirm the implementation (`resolvePackagedAssetPath`, `localAcceptanceSchema` usage) was already correct.

## TDD Gate Compliance

Both tasks carry `tdd="true"`, but Task 1's own `<verify>` command (`pnpm test:desktop:ipc -- protocol-contract`) targets the `ipc` vitest project lane, which had zero matching files (`test/ipc/**`) before Task 2's test file existed -- `passWithNoTests: false` means Task 1 could not be independently verified with a real RED-then-GREEN sequence; verifying it required Task 2's suite to exist first. Implementation (Task 1) and test (Task 2) were therefore authored together and committed in the plan's stated order (`feat` then `test`), not a strict test-first RED/GREEN sequence with a separate `test(KPL-03-10): add failing test for ...` commit preceding the `feat` commit. This mirrors the same disclosed pattern in `03-03-SUMMARY.md` for tightly-coupled boundary work. Both the implementation and the test were fully verified together (`pnpm test:desktop:ipc`, `pnpm typecheck:desktop`, `pnpm --dir apps/desktop build`, and real Electron E2E all pass) before either commit; recorded here per the plan's gate-enforcement instruction rather than silently omitted.

## Issues Encountered

None beyond the two test-only deviations above.

## User Setup Required

None.

## Known Stubs

None. `EXTERNAL_LINK_ALLOWED_ORIGINS` is an intentionally empty `Set` (deny-all-external-links-by-default), not a stub -- the app has no external links today, and the allowlist mechanism is real, tested (`isAllowedExternalLinkTarget`), and ready for a future explicit, reviewed addition rather than a placeholder awaiting implementation.

## Threat Flags

None new beyond this plan's own threat register (T-KPL03-10-01/02/03), all mitigated as designed:
- **T-KPL03-10-01 (Elevation of privilege, preload/main IPC):** strict `.strict()` schemas parsed on both preload and main; sender/frame-bound trust on every handler; no generic `invoke`/`send` surface (proven by static scan).
- **T-KPL03-10-02 (Spoofing, local protocol/navigation):** packaged-asset-only custom protocol with pure containment resolution; navigation restricted to same-origin `app://`; window creation always denied; permission requests always denied.
- **T-KPL03-10-03 (Tampering, sequence mirror):** D-29 sequence contract implemented and tested; opaque refetch on any gap, never an unsafe increment.

## Next Phase Readiness

- `main/index.ts`, `preload/index.ts`, `preload/contracts.ts`, and `main/protocol.ts` are now the frozen, hardened surface for this wave. Plan 03-11 (wave 8, `depends_on: [03-04]`) is expected to wire Plan 03-04's already-built `menu.ts`/`windows/main-window.ts`/`windows/quick-entry-window.ts`/`windows/settings-window.ts` into `main/index.ts`'s `bootstrap()` (see `.continue-here.md` O-9) -- when it does, those utility windows automatically inherit this plan's session-level CSP/permission/navigation policy without any change needed here, since none of that policy is per-`BrowserWindow`.
- The custom `app://` protocol and the main-side request re-validation are both new load-bearing production behavior in the shipped app, not test-only scaffolding -- verified by the real, unmodified-entry-point `daily-loop.spec.ts` E2E passing against them.
- `03-11` should be aware that `main/index.ts` now imports from `./protocol.ts` and `../preload/contracts.ts`; any restructuring of `bootstrap()` should preserve the `protocol.registerSchemesAsPrivileged` call happening before `app.whenReady()` (Electron requires this at module-evaluation time) and the `protocol.handle`/session-policy installation happening after it.

## Self-Check: PASSED

- Both created files exist on disk: `apps/desktop/main/protocol.ts`, `apps/desktop/test/ipc/hostile-bridge.test.ts`.
- Both commits (`a1e874c`, `4d751c6`) resolve in `git log --oneline --all`.
- `pnpm test:desktop:ipc -- protocol-contract` (Task 1's literal verify command) — 1 file, 46 tests pass (not lane-filtered by the trailing positional, consistent with the project's documented pnpm/vitest passthrough quirk; the full `ipc` lane is what ran, and it is non-vacuous).
- `pnpm test:desktop:ipc` (Task 2's literal verify command) — 1 file, 46 tests pass.
- `pnpm typecheck:desktop` — clean.
- `pnpm --dir apps/desktop build` — all four bundles (main/preload/utility-preload/renderer/worker) build clean.
- `pnpm test:desktop` (full pre-existing suite) — 12 files, 95 tests pass, unaffected.
- Real Electron E2E against the hardened, unmodified shipped entry point: `daily-loop.spec.ts` (2/2), `real-stack-sync.spec.ts` (3/3), and 03-04's `keyboard-menus.spec.ts`/`keyboard-quick-entry.spec.ts` (10/10, unaffected harness) all pass.
- Working tree clean after both commits; no preserved untracked path (`.gsd/`, `.planning/milestone.lock`, `.planning/research/.cache/`, `.tool-versions`, `apps/desktop/test-results/`) staged or deleted.

---
*Phase: KPL-03-mac-daily-loop*
*Completed: 2026-09-02*
