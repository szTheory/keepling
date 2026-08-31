---
phase: KPL-01-one-trustworthy-task
plan: 07
subsystem: authentication
tags: [elixir, phoenix, postgresql, argon2id, hammer, csrf, openapi, sessions]

requires:
  - phase: KPL-01-06
    provides: Closed singleton account setup, Argon2id credential, canonical timezone, and privacy-safe security audit table
provides:
  - Password login with opaque hash-stored tracked sessions, idle and absolute expiry, reauthentication, rotation, logout, labeling, and revocation
  - Operator-issued short-lived one-use browser recovery with serialized consumption and password replacement
  - Supervised Hammer abuse limits with isolated setup, login, and recovery account/source buckets
  - Versioned authentication/session OpenAPI and generated TypeScript transport contracts
affects: [KPL-01-08, KPL-01-09, KPL-01-10, KPL-01-14, authentication, native-grants]

actuals:
  tokens: 28540
  tasks: 2
  commits: 5

tech-stack:
  added: []
  patterns: [hash-only session credentials, one-use recovery capability, recent-auth rotation, supervised dual-bucket limiting, identifier-free security facts]

key-files:
  created:
    - apps/server/lib/keepling/accounts/session.ex
    - apps/server/lib/keepling/accounts/rate_limit.ex
    - apps/server/lib/mix/tasks/keepling.recover.ex
    - apps/server/priv/repo/migrations/20260830000210_expand_auth_lifecycle.exs
    - apps/server/test/keepling/security_audit_test.exs
    - apps/server/test/keepling/telemetry_redaction_test.exs
  modified:
    - apps/server/lib/keepling/accounts.ex
    - apps/server/lib/keepling_web/auth.ex
    - apps/server/lib/keepling_web/controllers/auth_controller.ex
    - apps/server/lib/keepling_web/router.ex
    - packages/contracts/openapi/keepling.yaml
    - packages/contracts/generated/keepling.ts

key-decisions:
  - "Browser sessions use opaque random credentials persisted only as SHA-256 hashes; successful login, recovery, and recent reauthentication rotate both the cookie credential and CSRF state."
  - "Recovery is an operator-issued, short-lived, one-use browser capability whose raw token is never persisted and whose database-serialized consumption replaces the password and revokes prior sessions."
  - "Authentication abuse control uses supervised Hammer ETS buckets with closed flow/key-class namespaces, a sole-account digest, coarsened source digests, and identifier-free allow-listed audit and telemetry facts."
  - "A storage-neutral GrantPort preserves the future authorization-code, PKCE, and scoped-grant boundary without implementing deferred native or MCP grant flows."

patterns-established:
  - "Tracked browser principal: the cookie carries only an opaque credential; every request resolves a server-side session and enforces idle, absolute, revocation, and recent-auth state."
  - "Recovery serialization: issue and consume paths lock the sole recovery row so races have exactly one winner and prior browser sessions are invalidated."
  - "Authentication diagnostics: low-cardinality closed atoms and event versions are retained, while passwords, bearer values, raw/coarsened sources, task content, and account identifiers are excluded."

requirements-completed: [SRV-01, SRV-03, QUAL-01]

coverage:
  - id: D1
    description: "Password login, reauthentication, logout, labeling, revocation, idle expiry, absolute expiry, and CSRF/session rotation form one tracked browser-session lifecycle."
    requirement: SRV-01
    verification:
      - kind: integration
        ref: "apps/server/test/keepling_web/auth_test.exs#login, session lifecycle, and expiry tests"
        status: pass
    human_judgment: false
  - id: D2
    description: "Operator recovery issues a hash-only short-lived link whose serialized one-use consumption has exactly one winner, replaces the password, and revokes older sessions."
    requirement: SRV-03
    verification:
      - kind: integration
        ref: "apps/server/test/keepling_web/auth_test.exs#operator recovery and independent-connection race tests"
        status: pass
    human_judgment: false
  - id: D3
    description: "Setup, login, and recovery are admitted through supervised isolated account/source buckets before credential work, with bounded backoff and generic public failures."
    requirement: SRV-03
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/security_audit_test.exs#rate_limit-tagged supervision, isolation, backoff, generic-response, and audit tests"
        status: pass
    human_judgment: false
  - id: D4
    description: "Authentication diagnostics exclude credentials, bearer tokens, task content, sources, and arbitrary identifiers, while all cookie-authenticated mutations enforce CSRF and trusted origin."
    requirement: QUAL-01
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/telemetry_redaction_test.exs and apps/server/test/keepling/security_audit_test.exs#CSRF/origin test"
        status: pass
    human_judgment: false
  - id: D5
    description: "Versioned login, recovery, and session contracts remain synchronized with generated TypeScript transport and the full server regression suite."
    requirement: QUAL-01
    verification:
      - kind: other
        ref: "pnpm contracts:check"
        status: pass
      - kind: integration
        ref: "mix test on existing and freshly migrated PostgreSQL databases (36/36 each)"
        status: pass
    human_judgment: false

duration: 31min
completed: 2026-08-30
status: complete
---

# Phase KPL-01 Plan 07: Trustworthy Authentication Lifecycle Summary

**Hash-only tracked sessions and serialized one-use recovery with supervised abuse limits, generic failures, CSRF rotation, and identifier-free diagnostics**

## Performance

- **Duration:** 31 min
- **Started:** 2026-08-31T02:37:35Z
- **Completed:** 2026-08-31T03:08:15Z
- **Tasks:** 2
- **Files modified:** 15

## Accomplishments

- Added measured Argon2id password login and a complete server-tracked browser lifecycle: opaque hash-only credentials, idle/absolute expiry, recent-auth checks, credential/CSRF rotation, labeling, revocation, and logout.
- Added operator-issued short-lived recovery links with hash-only storage, independent-connection one-winner consumption, password replacement, and revocation of every older session.
- Added application-supervised Hammer 7 limiting before setup/login/recovery credential work, with six isolated account/source namespaces, bounded backoff, generic missing/invalid/limited responses, and restart proof.
- Kept authentication audit and telemetry facts closed and identifier-free, proved every cookie-authenticated mutation requires CSRF plus trusted origin, and synchronized OpenAPI with generated TypeScript.

## Task Commits

Each task followed the required TDD gates and was committed atomically:

1. **Task 1 RED: Add failing authentication lifecycle proof** - `2532fc5` (test)
2. **Task 1 RED: Add failing browser recovery proof** - `c322b72` (test)
3. **Task 1 GREEN: Implement tracked authentication lifecycle** - `e2aaa5c` (feat)
4. **Task 2 RED: Add failing abuse and redaction proof** - `15b7b1a` (test)
5. **Task 2 GREEN: Bound authentication abuse and diagnostics** - `98919b6` (feat)

## Files Created/Modified

- `apps/server/lib/keepling/accounts.ex` - Closed login, recovery, tracked-session, rotation, expiry, revocation, logout, and security-audit application API.
- `apps/server/lib/keepling/accounts/session.ex` - Separate session persistence representation plus the future authorization-code/PKCE/scoped-grant port.
- `apps/server/lib/keepling/accounts/rate_limit.ex` and `apps/server/lib/keepling/application.ex` - Supervised Hammer ETS limiter with isolated dual buckets and bounded policies.
- `apps/server/lib/keepling_web/auth.ex`, `apps/server/lib/keepling_web/controllers/auth_controller.ex`, and `apps/server/lib/keepling_web/router.ex` - Versioned cookie/CSRF authentication and recovery/session transports.
- `apps/server/lib/mix/tasks/keepling.recover.ex` - Operator recovery-link issuance without password arguments, environment input, or token persistence.
- `apps/server/priv/repo/migrations/20260830000210_expand_auth_lifecycle.exs` - Expand-compatible tracked-session columns, recovery lifecycle, constraints, and identifier-free audit support.
- `apps/server/test/keepling_web/auth_test.exs` - Login, recovery race, rotation, expiry, revocation, and operator lifecycle evidence.
- `apps/server/test/keepling/security_audit_test.exs` and `apps/server/test/keepling/telemetry_redaction_test.exs` - Supervision, isolation, generic-response, CSRF/origin, audit, and hostile-value disclosure evidence.
- `packages/contracts/openapi/keepling.yaml` and `packages/contracts/generated/keepling.ts` - Versioned authentication, recovery, session, and problem transport truth.

## Decisions Made

- Keep the browser cookie as an opaque lookup credential rather than a self-contained principal. Server state remains authoritative for expiry, revocation, labeling, recent authentication, and recovery invalidation.
- Rotate the raw credential and CSRF state after login, recovery, and password reauthentication; ordinary task commands require authentication but do not require recent authentication.
- Keep recovery operator-initiated and browser-consumed. The operator task accepts no password or raw secret through arguments/environment, stores only a digest, and emits only generic surrounding output.
- Preserve a future grant abstraction as callbacks only. No deferred native session, passkey, authorization-code implementation, MCP grant, or scope model was invented in this plan.
- Use a single sole-account digest plus a coarsened network-source digest for each flow. Audit records retain only event type/version/time, and telemetry retains only flow/outcome/count.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Removed account identifiers from authentication and timezone security facts**
- **Found during:** Task 2 privacy-boundary review
- **Issue:** The inherited audit table required `account_id`, conflicting with the plan's prohibition on arbitrary identifiers in authentication security records.
- **Fix:** Expanded the audit schema to allow identifier-free facts, omitted account IDs from authentication, throttling, and timezone audit inserts, and updated cleanup/evidence for the new lifecycle.
- **Files modified:** `apps/server/lib/keepling/accounts.ex`, `apps/server/lib/keepling/accounts/rate_limit.ex`, migration and focused tests
- **Verification:** Hostile-value redaction test passes; audit assertions prove `account_id IS NULL`; all 36 server tests pass from a fresh migration.
- **Committed in:** `98919b6`

**2. [Rule 1 - Performance Bug] Avoided duplicate Argon2 work on ordinary wrong passwords**
- **Found during:** Task 2 expensive-work admission review
- **Issue:** A real account's wrong password ran both `verify_pass/2` and the missing-user dummy verification, doubling CPU after one admitted attempt.
- **Fix:** Retained dummy verification only for missing accounts and structurally invalid password values; a valid-shape wrong password performs one real Argon2 verification and returns the same generic failure.
- **Files modified:** `apps/server/lib/keepling/accounts.ex`
- **Verification:** Authentication/security suite passes with identical missing, wrong, and limited public login responses.
- **Committed in:** `98919b6`

**3. [Rule 2 - Missing Critical] Closed malformed-login and malformed-recovery disclosure differences**
- **Found during:** Task 2 generic-response proof
- **Issue:** Missing request fields returned a distinct `invalid_request` problem while wrong, expired, and limited attempts used generic authentication/recovery problems.
- **Fix:** Mapped malformed login and recovery attempts to their respective generic public failure shapes while retaining closed invalid telemetry.
- **Files modified:** `apps/server/lib/keepling_web/controllers/auth_controller.ex`, `apps/server/test/keepling/security_audit_test.exs`
- **Verification:** The regression tests failed first with HTTP 400, then passed with byte-identical missing/invalid/limited response bodies.
- **Committed in:** `98919b6`

---

**Total deviations:** 3 auto-fixed (2 Rule 2 missing critical controls, 1 Rule 1 performance bug)
**Impact on plan:** Each fix directly enforces the plan's abuse and privacy boundaries; no unrelated product capability was added.

## Issues Encountered

- Context7 MCP and CLI were unavailable, so the exact pinned Hammer 7.4.1 `use Hammer, backend: :ets`, child-spec, and `hit/3` behavior was verified against installed source before implementation and then exercised through forced-supervisor-restart tests.
- The lifecycle migration had already been applied to the executor test database before its identifier-free audit expansion. The exact column expansion was applied there for focused iteration, then a separate disposable database was created, migrated from zero, tested 36/36, and dropped to prove the checked-in migration independently.

## TDD Gate Compliance

- Task 1 RED commits `2532fc5` and `c322b72` captured failing login/session and recovery/browser contracts before production lifecycle code; GREEN commit `e2aaa5c` made all eight focused authentication tests and contract drift pass.
- Task 2 RED commit `15b7b1a` captured missing limiter supervision/API and telemetry behavior; GREEN commit `98919b6` made the focused limiter and redaction gates pass.
- The malformed login/recovery response regression was run failing first at HTTP 400, then fixed to the generic HTTP 401/422 shapes before Task 2 GREEN was committed.
- No refactor-only commit was needed after GREEN.

## Known Stubs

None - no placeholder, TODO, skipped test, mock data source, empty rendered value, or unrun verification remains in the files changed by this plan. The `GrantPort` callbacks are the explicitly required D-54 compatibility seam, not a reachable implementation stub.

## Threat Surface

- T-KPL01-13 is mitigated by measured Argon2id verification, generic failures, opaque hash-only credential storage, server-side rotation, idle/absolute expiry, and revocation tests.
- T-KPL01-14 is mitigated by CSPRNG recovery material, hash-only persistence, bounded expiry, serialized one-use consumption, prior-session revocation, and independent-connection race proof.
- T-KPL01-15 is mitigated by allow-listed low-cardinality telemetry and closed identifier-free audit facts plus hostile password, token, task-content, and identifier negative tests.
- T-KPL01-16 is mitigated by pre-KDF dual-bucket admission, distinct setup/login/recovery account/source namespaces, bounded backoff, permanent OTP supervision, and restart/reuse proof.
- No additional unmodeled network endpoint, file-access path, schema trust boundary, native grant, or passkey flow was introduced.

## Verification Evidence

- Focused authentication lifecycle: 8/8 tests passed during Task 1 GREEN.
- Final authentication/security/redaction run: 14/14 tests passed.
- Exact Task 2 gate: 4/4 rate-limit-tagged tests and 1/1 telemetry-redaction test passed.
- Strict server compile and full existing-database suite: 36/36 tests passed.
- Fresh-schema proof: all three migrations applied to a new PostgreSQL 18.6 database and the full suite passed 36/36; the disposable database was then dropped.
- `pnpm contracts:check`: OpenAPI and generated TypeScript agree.

## User Setup Required

None for verification. A production operator can explicitly run `mix keepling.recover --base-url https://their-host` when recovery is needed; normal deployment does not issue recovery material or accept a password through operator inputs.

## Next Phase Readiness

- Plan 01-08 can build calm browser login, recovery, reauthentication, and session-management UI against checked-in versioned DTOs without inventing another auth path.
- Later Mac/iPhone and MCP phases can implement the preserved authorization-code/PKCE/scoped-grant port while keeping the browser cookie lifecycle separate.
- No high-severity mitigation assigned to Plan 01-07 remains open.

## Self-Check: PASSED

- All 15 authentication, recovery, limiter, migration, contract, generated transport, test, and summary files exist on disk.
- Task commits `2532fc5`, `c322b72`, `e2aaa5c`, `15b7b1a`, and `98919b6` exist in Git history.
- Required actuals, coverage, requirement IDs, TDD evidence, stub scan, threat mitigations, fresh-schema proof, and `status: complete` metadata are present.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-30*
