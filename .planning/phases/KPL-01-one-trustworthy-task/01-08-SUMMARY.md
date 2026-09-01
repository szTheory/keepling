---
phase: KPL-01-one-trustworthy-task
plan: 08
subsystem: browser-authentication
tags: [react, typescript, playwright, authentication, recovery, sessions, accessibility]

requires:
  - phase: KPL-01-07
    provides: Hash-only tracked browser sessions, one-use setup/recovery capabilities, recent authentication, CSRF rotation, and generated transport DTOs
provides:
  - Closed setup, login, one-use recovery, and inline reauthentication routes in Keepling Web
  - Reachable Settings/Sessions inventory with label editing, exact revocation confirmation, current-session logout, and coarse activity
  - Draft- and mutation-identity-preserving authentication recovery for not-submitted and submitted-unknown browser commands
  - Real operator-link Playwright proof against disposable PostgreSQL, Phoenix, and Chromium
affects: [KPL-01-09, KPL-01-14, KPL-01-17, browser-auth, session-management]

actuals:
  tokens: 19354
  tasks: 2
  commits: 5

tech-stack:
  added: []
  patterns: [generated DTO to semantic facade mapping, retained interruption intent, query-and-path capability routing, dirty-aware destructive confirmation]

key-files:
  created:
    - apps/web/src/app/AuthProvider.tsx
    - apps/web/src/app/AppShell.tsx
    - apps/web/src/app/routes.tsx
    - apps/web/src/features/auth/LoginForm.tsx
    - apps/web/src/features/auth/SetupForm.tsx
    - apps/web/src/features/auth/RecoveryReset.tsx
    - apps/web/src/features/auth/Reauthenticate.tsx
    - apps/web/src/features/sessions/SessionList.tsx
    - apps/web/src/features/auth/auth.test.tsx
    - apps/web/e2e/auth-recovery.spec.ts
  modified:
    - apps/web/src/App.tsx
    - apps/web/src/api/keepling.ts
    - apps/web/src/features/capture/QuickCapture.tsx

key-decisions:
  - "The browser accepts both the plan's /setup/:token and /recover/:token routes and the existing operator commands' /setup?token= and /recover?token= links, while submitting the same generated DTOs."
  - "Reauthentication retains a fixed interrupted-intent object plus a resume continuation; rotated CSRF state is supplied to the resumed delivery while the original mutation identity remains unchanged."
  - "Session activity remains deliberately coarse and visible as Active now, Today, or Earlier; the UI never presents it as trusted-device fingerprinting."

patterns-established:
  - "Closed auth routing: public browser entry is limited to operator capability URLs and /login; no registration route or account-creation shortcut exists."
  - "Exact auth recovery: authenticated content stays mounted beneath inline reauthentication so drafts survive, and resume callbacks reuse the original request identity."
  - "Session administration: current-session revocation is logout, while other-session revocation requires an exact named confirmation whose safe action receives initial focus."

requirements-completed: [SRV-01, WEB-02, QUAL-01]

coverage:
  - id: D1
    description: "Closed setup, password-manager-friendly login, and one-use recovery are reachable through browser routes with honest terminal states."
    requirement: SRV-01
    verification:
      - kind: unit
        ref: "apps/web/src/features/auth/auth.test.tsx#closed browser authentication"
        status: pass
      - kind: e2e
        ref: "apps/web/e2e/auth-recovery.spec.ts#real operator setup and recovery links"
        status: pass
    human_judgment: false
  - id: D2
    description: "Settings/Sessions lists current state, client kind, exact creation time, coarse activity, editable labels, and named revocation/logout actions."
    requirement: WEB-02
    verification:
      - kind: unit
        ref: "apps/web/src/features/auth/auth.test.tsx#session administration"
        status: pass
      - kind: e2e
        ref: "apps/web/e2e/auth-recovery.spec.ts#session labeling and revocation"
        status: pass
    human_judgment: false
  - id: D3
    description: "Authentication interruption preserves the draft and exact original mutation identity for both pre-acceptance and submitted-unknown recovery."
    requirement: QUAL-01
    verification:
      - kind: unit
        ref: "apps/web/src/features/auth/auth.test.tsx#capture authentication recovery"
        status: pass
    human_judgment: false
  - id: D4
    description: "Login, recovery, reauthentication, and session confirmations use native labels, named controls, safe initial focus, and password-manager autocomplete contracts."
    requirement: WEB-02
    verification:
      - kind: automated_ui
        ref: "apps/web/src/features/auth/auth.test.tsx#focus, labels, autocomplete, paste, and reveal assertions"
        status: pass
    human_judgment: false

duration: 20min
completed: 2026-08-30
status: complete
---

# Phase KPL-01 Plan 08: Reachable Browser Authentication and Sessions Summary

**Closed operator setup and one-use recovery, password-manager-friendly login, exact reauthentication recovery, and revocable browser sessions through a real React–Phoenix–PostgreSQL flow**

## Performance

- **Duration:** 20 min
- **Started:** 2026-08-31T03:13:57Z
- **Completed:** 2026-08-31T03:34:31Z
- **Tasks:** 2
- **Files modified:** 13

## Accomplishments

- Added routed closed setup, login, recovery, and reauthentication forms backed by the checked-in generated authentication DTOs, with explicit IANA timezone validation, AutoFill/reveal controls, and honest one-use terminal states.
- Added reachable Settings/Sessions navigation and inventory with all D-50 fields, editable labels, named other-session revocation, current-session logout, dirty-work confirmation support, and coarse non-fingerprint activity language.
- Preserved browser drafts and the exact originally submitted mutation identity through pre-acceptance authentication expiry and submitted-unknown result recovery, including rotated CSRF state on resumed delivery.
- Proved real operator-issued setup and recovery links, second-use denial, login, session labeling/revocation, logout, and the existing capture skeleton against disposable PostgreSQL/Phoenix/Chromium.

## Task Commits

Each task followed TDD gates and was committed atomically:

1. **Task 1 RED: Add failing browser authentication proof** - `29bfeed` (test)
2. **Task 1 GREEN: Route closed browser authentication** - `08dd520` (feat)
3. **Task 2 RED: Add failing session and operator-link proof** - `a8fad37` (test)
4. **Task 2 RED: Add failing interruption recovery proof** - `3c06b88` (test)
5. **Task 2 GREEN: Compose sessions and exact auth recovery** - `3b294e7` (feat)

## Files Created/Modified

- `apps/web/src/api/keepling.ts` - Generated DTO-backed semantic facade for setup, login, recovery, reauthentication, logout, and session inventory/mutations.
- `apps/web/src/app/AuthProvider.tsx` and `apps/web/src/app/routes.tsx` - Session bootstrap, closed route selection, interruption retention, rotated-CSRF resume, and path/query capability compatibility.
- `apps/web/src/features/auth/*.tsx` - Setup, login, recovery, and reauthentication forms with accessible labels, focus, progress, validation, and terminal copy.
- `apps/web/src/app/AppShell.tsx` and `apps/web/src/features/sessions/SessionList.tsx` - Reachable Settings/Sessions shell, D-50 inventory, label editing, and exact destructive confirmations.
- `apps/web/src/features/capture/QuickCapture.tsx` - Draft- and fixed-mutation-identity retention across authentication-required and submitted-unknown states.
- `apps/web/src/features/auth/auth.test.tsx` and `apps/web/e2e/auth-recovery.spec.ts` - Component evidence plus real operator-link and session lifecycle proof.

## Decisions Made

- Accept both capability URL shapes at the browser boundary. Existing operator tasks issue query tokens, while the plan standardizes path tokens; both map to the same token-only form and wire request.
- Keep reauthentication inline while authenticated content remains mounted. This preserves live browser drafts rather than reconstructing or pretending to persist unsubmitted text.
- Resume interrupted commands through an owned continuation supplied with the rotated CSRF token, never through a fresh mutation-identity allocation.
- Display only the server's coarse session activity enum and explicit client kind. Neither is described as a trusted device or fingerprint.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Wired the new auth routes into the existing application composition root**
- **Found during:** Task 1 route composition
- **Issue:** The plan's file list omitted `apps/web/src/App.tsx`; creating route/provider files without changing the composition root would leave every auth form unreachable.
- **Fix:** Wrapped the existing authenticated Inbox in `AuthProvider` and `AppRoutes` while preserving the shipped capture skeleton.
- **Files modified:** `apps/web/src/App.tsx`
- **Verification:** Auth component suite, production build, real login flow, and full Playwright suite pass.
- **Committed in:** `08dd520`

**2. [Rule 2 - Missing Critical] Accepted real operator query-token links alongside planned path-token routes**
- **Found during:** Task 2 real operator-link test design
- **Issue:** `mix keepling.setup_token` and `mix keepling.recover` emit `/setup?token=` and `/recover?token=`, while the plan required `/setup/:token` and `/recover/:token`; supporting only either shape would break a required entry point.
- **Fix:** Routed both shapes to the same closed token forms without modifying OpenAPI, generated output, or server behavior.
- **Files modified:** `apps/web/src/app/routes.tsx`, `apps/web/e2e/auth-recovery.spec.ts`
- **Verification:** Actual operator task output is consumed once in the passing real-stack Playwright test; component tests retain path-token coverage.
- **Committed in:** `3b294e7`

**3. [Rule 2 - Missing Critical] Connected capture authentication expiry to identity-preserving reauthentication**
- **Found during:** Task 2 D-51 completion review
- **Issue:** The existing capture form preserved visible text after a 401 but treated it as an ordinary problem, discarded submission state, and could not resume an unknown-result lookup through inline reauthentication.
- **Fix:** Retained the exact submission, mounted draft, interruption kind, mutation identity, and resume continuation; reauthentication now supplies the rotated CSRF token before exact retry/query.
- **Files modified:** `apps/web/src/features/capture/QuickCapture.tsx`, `apps/web/src/app/AuthProvider.tsx`, `apps/web/src/app/routes.tsx`, `apps/web/src/App.tsx`, focused tests
- **Verification:** Two tests failed before implementation and now prove both pre-acceptance and submitted-unknown recovery reuse the original identity; 8/8 component tests pass.
- **Committed in:** `3c06b88`, `3b294e7`

---

**Total deviations:** 3 auto-fixed (3 Rule 2 missing critical integrations)
**Impact on plan:** Each deviation was necessary to make the specified browser capabilities reachable and trustworthy; no new external dependency, server contract, or canonical state was introduced.

## Issues Encountered

- The real-stack test needed to run operator Mix tasks through the repository runtime preflight with the isolated database URL and a separate test endpoint secret. This keeps the command real while preventing it from trying to bind another server.
- Early Playwright iterations exposed fuzzy accessible-name collisions between password fields and reveal buttons. Tests now use exact role/name locators; the controls retain explicit visible and accessible names.

## TDD Gate Compliance

- Task 1 RED commit `29bfeed` failed on the missing routed auth interface; GREEN commit `08dd520` made all five setup/login/recovery/reauthentication specifications pass.
- Task 2 RED commit `a8fad37` failed on the missing AppShell/Sessions interface; the later `3c06b88` RED micro-cycle captured the pre-existing auth-interruption defect before production recovery changes.
- Task 2 GREEN commit `3b294e7` made all eight component behaviors and the real operator-link Playwright flow pass. No separate refactor commit was needed.

## Known Stubs

None - no TODO, FIXME, skipped test, mock production data source, empty rendered data seam, or placeholder implementation remains. The setup timezone example uses the native input `placeholder` attribute as field guidance, not an implementation stub.

## Threat Surface

- T-KPL01-17 is mitigated by same-origin cookie requests, generated DTO-shaped facade calls, CSRF on authenticated mutations, no credential Web Storage, password-manager-compatible inputs, and session rotation consumption.
- T-KPL01-18 is mitigated by one-use setup/recovery terminal handling, exact named revocation confirmation, recent-auth server enforcement, account-scoped session IDs, and real second-consumption denial.
- T-KPL01-19 is mitigated by retained mounted drafts, closed interruption kinds, fixed mutation identities, explicit unknown-result lookup, and rotated-CSRF resume proof.
- No unmodeled network endpoint, schema, file-access boundary, credential store, or telemetry field was introduced.

## Verification Evidence

- `pnpm --filter @keepling/web test --run`: 1 file, 8/8 tests passed.
- `pnpm --filter @keepling/web typecheck`: passed with no TypeScript diagnostics.
- `pnpm --filter @keepling/web lint`: passed with no ESLint findings.
- `pnpm --filter @keepling/web build`: production TypeScript/Vite build passed (57 modules transformed).
- `pnpm contracts:check`: OpenAPI and generated TypeScript agree.
- `pnpm --filter @keepling/web test:e2e --grep @auth-recovery`: 1/1 real operator auth/session test passed.
- `pnpm --filter @keepling/web test:e2e`: 3/3 full real-stack tests passed, including the existing capture skeleton and fault-gating check.
- Actual password-manager and VoiceOver judgment remains part of end-of-phase human verification; automated tests prove paste, autocomplete, reveal, accessible names, safe initial focus, and keyboard-operable native controls.

## User Setup Required

None. Operators continue to issue setup and recovery links through the existing Mix tasks; the browser now consumes their exact output.

## Next Phase Readiness

- Plan 01-09 can add multi-field editing and Inbox clarification within the authenticated shell while reusing the fixed-identity reauthentication continuation.
- Later session-sensitive and uncertain-delivery plans can reuse the closed interruption kinds instead of adding redirects or a second credential path.
- No high-severity mitigation assigned to Plan 01-08 remains open.

## Self-Check: PASSED

- All ten created browser/auth/session/test artifacts and the canonical summary exist on disk.
- Task commits `29bfeed`, `08dd520`, `a8fad37`, `3c06b88`, and `3b294e7` exist in Git history.
- Coverage metadata classifies four deliverables without schema errors: three fully automated and one intentionally reserved for end-of-phase password-manager/VoiceOver judgment.
- Required actuals, requirements, TDD evidence, stub scan, threat mitigations, real-stack proof, and `status: complete` metadata are present.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-30*
