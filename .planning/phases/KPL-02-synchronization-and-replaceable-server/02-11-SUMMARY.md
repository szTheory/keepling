---
phase: KPL-02-synchronization-and-replaceable-server
plan: 11
subsystem: authentication
tags: [elixir, phoenix, oauth-public-client, pkce, bearer-auth, openapi]

requires:
  - phase: KPL-02-synchronization-and-replaceable-server
    plan: 03
    provides: hash-only public-client grants, rotating refresh lineage, replay fencing, and server-authoritative namespace construction
  - phase: KPL-01-one-trustworthy-task
    provides: browser session authorization, closed Problem Details, and contract generation/drift tooling
provides:
  - Executable external-user-agent PKCE authorization and opaque token lifecycle for native public clients
  - Bearer-only installation inventory and idempotent installation-family revocation
  - Router-level authenticated grant identity and server-derived five-field synchronization namespace
  - Closed generated OpenAPI operations and schemas for all native grant lifecycle actions
affects: [sync-http-transport, desktop-authentication, ios-authentication, native-client-generation]

actuals:
  tokens: 11677
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns: [thin grant transport adapter, exact Bearer parsing, server-only namespace assignment, closed public-client DTOs]

key-files:
  created:
    - apps/server/lib/keepling_web/controllers/device_grant_controller.ex
    - apps/server/test/keepling_web/device_grant_controller_test.exs
  modified:
    - apps/server/lib/keepling/accounts.ex
    - apps/server/lib/keepling/accounts/device_grant.ex
    - apps/server/lib/keepling_web/auth.ex
    - apps/server/lib/keepling_web/router.ex
    - packages/contracts/openapi/keepling.yaml
    - packages/contracts/generated/keepling.ts

key-decisions:
  - "Native client_id is closed to electron or iphone and maps only to the application-owned client kind; no secret or namespace assertion enters issuance."
  - "Both OAuth grant types execute through POST /oauth/token, while /oauth/token/refresh is an exact documented alias that gives refreshNativeGrant its required generated operation identity."
  - "The bearer pipeline assigns only current_device_grant_id and the five-field server namespace returned by the account application; downstream transports never reconstruct authority from request data."

patterns-established:
  - "Native authorization: an authenticated external user agent issues an exact redirect/state/S256-bound one-use code, while token operations never consume browser authentication."
  - "Device boundary: exactly one case-sensitive Authorization: Bearer credential is hash-authenticated before a protected controller receives grant or namespace assigns."

requirements-completed: [SRV-04, QUAL-05]

coverage:
  - id: D1
    description: "A native public client completes exact redirect/state/S256 authorization, one-use exchange, refresh rotation, replay fencing, installation visibility, and idempotent revocation over HTTP."
    requirement: SRV-04
    verification:
      - kind: integration
        ref: "apps/server/test/keepling_web/device_grant_controller_test.exs#native public client completes exact PKCE exchange, rotation, listing, and revocation"
        status: pass
      - kind: other
        ref: "pnpm contracts:check#five closed native grant operations and generated TypeScript"
        status: pass
    human_judgment: false
  - id: D2
    description: "Bearer-protected requests receive only the server-authenticated grant identity and issuer/origin/server-instance/subject/generation namespace, with cookies and stale or malformed credentials denied."
    requirement: QUAL-05
    verification:
      - kind: integration
        ref: "apps/server/test/keepling_web/device_grant_controller_test.exs#bearer pipeline assignment and denial cases"
        status: pass
      - kind: integration
        ref: "apps/server mix test#137 passed including 1 property"
        status: pass
    human_judgment: false

duration: 10min
completed: 2026-09-01
status: complete
---

# Phase KPL-02 Plan 11: Native Grant Transport and Bearer Namespace Summary

**External-user-agent PKCE acquisition, rotating opaque credentials, installation revocation, and a server-derived bearer namespace now form one executable native-client boundary.**

## Performance

- **Duration:** 10 min
- **Started:** 2026-09-01T06:41:58Z
- **Completed:** 2026-09-01T06:51:29Z
- **Tasks:** 2
- **Files modified:** 8 implementation, contract, generated, and proof files

## Accomplishments

- Added exact external-user-agent authorization with registered redirects, preserved unpredictable state, S256 PKCE, one-use codes, and no native client secret.
- Added closed code exchange and refresh rotation transport with opaque 15-minute Bearer access, stable replay fencing, separate installation inventory, and idempotent revocation.
- Added a distinct router authentication pipeline that accepts exactly one standard Bearer header and assigns only the account application's authenticated grant identity and five-field namespace.
- Added and regenerated all five required OpenAPI operations without exposing stored hashes, raw credential material, browser cookies, passwords, deployment credentials, or client-asserted namespace authority.

## Task Commits

Each TDD task was committed as a RED test followed by its GREEN implementation:

1. **Task 1 RED: failing native grant transport proof** - `933acd5` (test)
2. **Task 1 GREEN: native grant lifecycle transport and contracts** - `43d34a6` (feat)
3. **Task 2 RED: failing bearer namespace proof** - `a641da7` (test)
4. **Task 2 GREEN: server-derived bearer namespace boundary** - `9d49c54` (feat)

## Files Created/Modified

- `apps/server/lib/keepling_web/controllers/device_grant_controller.ex` - Thin authorize, exchange, refresh, inventory, and revocation adapter with closed problems.
- `apps/server/test/keepling_web/device_grant_controller_test.exs` - ConnCase proof for PKCE, rotation, replay, revocation, exact Bearer parsing, and namespace authority.
- `apps/server/lib/keepling_web/auth.ex` - Dedicated device-grant authentication plug and closed server-derived assigns.
- `apps/server/lib/keepling_web/router.ex` - Public OAuth routes plus Bearer-protected installation routes and reusable pipeline.
- `apps/server/lib/keepling/accounts/device_grant.ex` - Application-owned idempotent installation-family revocation under row locks.
- `apps/server/lib/keepling/accounts.ex` - Inward delegate for installation-identity revocation.
- `packages/contracts/openapi/keepling.yaml` - Five closed lifecycle operations, security scheme, requests, responses, and identities.
- `packages/contracts/generated/keepling.ts` - Regenerated TypeScript transport types.

## Decisions Made

- Kept authorization approval on the existing browser session but made token exchange, refresh, inventory, revocation, and downstream native access independent of browser cookies and CSRF state.
- Closed `client_id` to `electron` and `iphone`, matching the already-proven application client kinds without adding a separate public-client registry or shared secret.
- Exposed refresh through the required `/oauth/token` grant-type dispatch and also documented `/oauth/token/refresh` as an exact alias so the generated contract carries the distinct `refreshNativeGrant` operation ID.
- Assigned the namespace map exactly as returned by `Keepling.Accounts.DeviceGrant`; controllers convert its server-derived subject only when calling account-scoped inward functions.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] Added application-owned idempotent revocation by installation identity**
- **Found during:** Task 1 GREEN implementation
- **Issue:** The existing inward application seam revoked only an internal grant UUID and returned not-found on repetition, while the closed path names an installation and requires stable idempotent family revocation. Implementing that lookup in Phoenix would violate the plan's transport-boundary prohibition.
- **Fix:** Added a row-locked account-and-installation revocation function that advances only active matching families, records the bounded audit fact once, and returns the same terminal result on repetition.
- **Files modified:** `apps/server/lib/keepling/accounts.ex`, `apps/server/lib/keepling/accounts/device_grant.ex`
- **Verification:** The transport test revokes the same installation twice through another live installation and then proves the revoked installation remains denied.
- **Committed in:** `43d34a6`

**2. [Rule 1 - Bug] Preserved the successful transaction envelope for installation revocation**
- **Found during:** Task 1 GREEN verification
- **Issue:** The first adapter implementation unwrapped the successful `Repo.transact/2` result one level too far, causing the thin controller to render a 401 after a successful revocation.
- **Fix:** Returned the expected `{:ok, result}` application shape and reran the complete HTTP lifecycle.
- **Files modified:** `apps/server/lib/keepling/accounts/device_grant.ex`
- **Verification:** Focused transport proof passed 1/1 before the Task 1 commit and 3/3 at the final gate.
- **Committed in:** `43d34a6`

**3. [Rule 1 - Bug] Returned the account identity from the new ConnCase fixture**
- **Found during:** Task 2 GREEN verification
- **Issue:** The new fixture initially returned the Postgrex insert result instead of the created account UUID, preventing the server-subject assertion from evaluating.
- **Fix:** Returned the generated account identity after insertion so the test could compare the assigned subject to independent server fixture state.
- **Files modified:** `apps/server/test/keepling_web/device_grant_controller_test.exs`
- **Verification:** The namespace and denial suite passed 3/3.
- **Committed in:** `9d49c54`

---

**Total deviations:** 3 auto-fixed (2 Rule 1 bugs, 1 Rule 2 missing critical functionality)
**Impact on plan:** The fixes keep revocation semantics inward and make the proof trustworthy; no new dependency or architectural boundary was introduced.

## Issues Encountered

- The repository's runtime guard correctly rejected the first RED command without `KEEPLING_TEST_DATABASE_URL`. Verification continued against an owned disposable PostgreSQL 18.6 database initialized and migrated for this plan.
- The full suite intentionally logged its bounded database-timeout and degraded-audit test signals while still completing successfully with 137 passing tests.

## Known Stubs

None. The scan found no TODO/FIXME/placeholder path or hardcoded empty value flowing to a user surface.

## User Setup Required

None - native client packaging will supply the already-required issuer, origin, server-instance, and registered redirect configuration in later platform plans.

## Next Phase Readiness

- Plan 02-05 already depends on 02-11 and can attach synchronization routes to `device_grant_authenticated`, consuming only `current_device_grant_id` and `device_grant_namespace`.
- Desktop and iPhone clients can implement external-user-agent acquisition without embedding a password, browser cookie, deployment credential, or shared client secret.
- No claim is made yet about packaged-platform credential storage or lifecycle protection; those remain platform-adapter evidence.

---
*Phase: KPL-02-synchronization-and-replaceable-server*
*Completed: 2026-09-01*

## Self-Check: PASSED

- Both created artifacts, all modified implementation/contract artifacts, and this summary exist on disk.
- All four RED/GREEN task commits are present in Git history.
- Coverage metadata parsed successfully with both deliverables backed entirely by passing automated evidence.
