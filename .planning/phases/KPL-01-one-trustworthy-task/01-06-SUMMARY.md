---
phase: KPL-01-one-trustworthy-task
plan: 06
subsystem: closed-account-setup
tags: [elixir, ecto, postgresql, argon2id, tzdata, openapi, concurrency]

requires:
  - phase: KPL-01-05
    provides: Singleton account table, Phoenix JSON/session boundary, independent PostgreSQL race harness, and generated OpenAPI transport
provides:
  - Operator-issued 60–3600 second setup capability stored only as a SHA-256 hash
  - One-transaction sole-account creation with Argon2id credential, explicit IANA timezone, and permanent setup disablement
  - Shared serialized account-timezone command with Today, Upcoming, and activity-view invalidation
  - Closed privacy-safe account-security audit facts and account-day conversion using vendored IANA data
affects: [KPL-01-07, KPL-01-08, KPL-01-12, KPL-01-13, authentication, temporal-projections]

actuals:
  tokens: 12736
  tasks: 2
  commits: 6

tech-stack:
  added: [argon2_elixir 4.1.3, tzdata 1.1.4]
  patterns: [database singleton lock, hash-only bearer capability, closed account-setting command, revision invalidation, separate security audit]

key-files:
  created:
    - apps/server/lib/keepling/accounts.ex
    - apps/server/lib/keepling/accounts/account.ex
    - apps/server/lib/keepling_web/controllers/auth_controller.ex
    - apps/server/lib/mix/tasks/keepling.setup_token.ex
    - apps/server/lib/mix/tasks/keepling.timezone.ex
    - apps/server/priv/repo/migrations/20260830000200_add_closed_setup_and_timezone.exs
    - apps/server/test/keepling/accounts/setup_timezone_test.exs
  modified:
    - apps/server/lib/keepling_web/router.ex
    - apps/server/mix.exs
    - apps/server/mix.lock
    - packages/contracts/openapi/keepling.yaml
    - packages/contracts/generated/keepling.ts

key-decisions:
  - "Setup capabilities are 32 random bytes, valid for 60–3600 seconds, persisted only as SHA-256 hashes, and serialized through one locked account_setup singleton row."
  - "Account timezone changes update only the account setting and three affected view revisions, while closed timezone_changed facts remain separate from task activity."
  - "tzdata uses its pinned vendored IANA snapshot with automatic network updates disabled; Keepling starts no remote timezone updater and has no Hackney call path."

patterns-established:
  - "Closed bootstrap: operator issuance and browser consumption share Keepling.Accounts, with account creation and setup consumption committed under the same row lock."
  - "Canonical account day: server-side DateTime conversion reads the sole validated IANA timezone; device/deployment zones and fixed offsets never enter the seam."
  - "Projection invalidation: each accepted timezone change atomically increments Today, Upcoming, and activity view revisions before returning."

requirements-completed: [SRV-01, SRV-02, SRV-03, QUAL-01]

coverage:
  - id: D1
    description: "An operator can issue one short-lived hashed setup capability, and one transaction creates the sole Argon2id account with explicit IANA timezone while permanently disabling setup."
    requirement: SRV-01
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/accounts/setup_timezone_test.exs#setup-tagged issuance, consumption, endpoint, TTL, and independent race tests"
        status: pass
    human_judgment: false
  - id: D2
    description: "The shared account command serializes valid timezone changes, preserves task acceptance time, records separate closed audit, and invalidates all affected views."
    requirement: SRV-02
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/accounts/setup_timezone_test.exs#timezone-tagged DST, no-op, operator, and concurrent serialization tests"
        status: pass
    human_judgment: false
  - id: D3
    description: "Setup transport and generated TypeScript contract remain versioned and drift-free while full server regression tests pass."
    requirement: QUAL-01
    verification:
      - kind: other
        ref: "pnpm contracts:check"
        status: pass
      - kind: integration
        ref: "mix test (22/22)"
        status: pass
    human_judgment: false

duration: 17min
completed: 2026-08-30
status: complete
---

# Phase KPL-01 Plan 06: Closed Setup and Canonical Timezone Summary

**Hash-only one-shot account bootstrap and a serialized IANA timezone command with Argon2id credentials, closed audit, and deterministic projection invalidation**

## Performance

- **Duration:** 17 min
- **Started:** 2026-08-31T02:14:21Z
- **Completed:** 2026-08-31T02:31:11Z
- **Tasks:** 2
- **Files modified:** 16

## Accomplishments

- Made closed setup operational through `mix keepling.setup_token` and `POST /api/v1/setup`, without public registration, first-request ownership, raw-token persistence, or account identifiers in responses.
- Proved on independent PostgreSQL backends that concurrent issuance leaves one usable capability and concurrent consumption creates exactly one account and permanently disables setup.
- Made the canonical account timezone explicit at setup and changeable only through one serialized application seam that records closed account audit and advances Today, Upcoming, and activity view revisions without touching task time.
- Added versioned OpenAPI/TypeScript setup DTOs and a focused 13-test setup/timezone suite covering DST interpretation, invalid no-ops, operator output, hash storage, expiry, and races.

## Task Commits

Each task followed the required TDD gates and was committed atomically:

1. **Task 1 RED: Add failing closed setup proof** - `4e12ec2` (test)
2. **Task 1 GREEN: Close first-account setup** - `7058686` (feat)
3. **Task 2 RED: Add failing timezone command proof** - `0d6da5d` (test)
4. **Task 2 GREEN: Serialize canonical timezone changes** - `92f71d9` (feat)
5. **Rule 2 fix: Enforce durable setup boundaries** - `17a3571` (fix)
6. **Security evidence: Prove timezone updater stays offline** - `3e1c7c8` (test)

## Files Created/Modified

- `apps/server/lib/keepling/accounts.ex` - Shared setup, account-day, and timezone-setting application seam with PostgreSQL row locking.
- `apps/server/lib/keepling/accounts/account.ex` - Separate Ecto persistence representation for the sole account.
- `apps/server/lib/keepling_web/controllers/auth_controller.ex` and `apps/server/lib/keepling_web/router.ex` - Closed version 1 setup consumption transport.
- `apps/server/lib/mix/tasks/keepling.setup_token.ex` - Generic one-time setup URL issuance with bounded expiry.
- `apps/server/lib/mix/tasks/keepling.timezone.ex` - Operator caller of the shared timezone-setting command.
- `apps/server/priv/repo/migrations/20260830000200_add_closed_setup_and_timezone.exs` - Setup singleton, account credential/timezone fields, view revisions, constraints, and separate audit table.
- `apps/server/test/keepling/accounts/setup_timezone_test.exs` - Independent-connection setup/timezone race, DST, privacy, lifecycle, and operator evidence.
- `packages/contracts/openapi/keepling.yaml` and `packages/contracts/generated/keepling.ts` - Versioned setup request/response transport truth.

## Decisions Made

- Bound setup capability lifetime to 60–3600 seconds and retain a single active hash; expired capability replacement is serialized by the database singleton lock.
- Added an expand-compatible `NOT VALID` check so historical rows remain migratable while every future account insert must carry credential and timezone fields.
- Keep timezone audit content closed to `timezone_changed` version 1 plus acceptance time; old/new zone names and account IDs never enter operator output or diagnostic telemetry.
- Disable `tzdata` automatic remote updates and use the pinned IANA snapshot so the transitive Hackney advisory has no updater or Keepling call path.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added exact reviewed password/timezone dependencies and runtime configuration**
- **Found during:** Task 1 GREEN
- **Issue:** The planned Argon2id credential and IANA validation APIs were not present in the existing server dependency set or configuration.
- **Fix:** Added exactly `argon2_elixir 4.1.3` and `tzdata 1.1.4`, configured explicit Argon2id costs, and registered the Tzdata time-zone database.
- **Files modified:** `apps/server/mix.exs`, `apps/server/mix.lock`, `apps/server/config/config.exs`, `apps/server/config/test.exs`
- **Verification:** Setup hashes begin with `$argon2id$`; valid IANA zones pass; fixed/invalid zones are exact no-ops; 13/13 focused tests pass.
- **Committed in:** `7058686`

**2. [Rule 2 - Missing Critical] Enforced bounded lifetime and permanent setup disablement for all singleton-account states**
- **Found during:** Post-Task 2 invariants review
- **Issue:** Positive but unbounded operator TTLs were not necessarily short-lived, and a pre-existing singleton account returned disabled without durably consuming setup state.
- **Fix:** Bounded TTLs to 60–3600 seconds, durably disabled setup for an existing singleton, and added an expand-compatible database constraint requiring credential/timezone fields on future account rows. Updated test-only fixtures to honor the invariant.
- **Files modified:** `apps/server/lib/keepling/accounts.ex`, `apps/server/lib/mix/tasks/keepling.setup_token.ex`, migration, seed, and focused/idempotency tests
- **Verification:** 9/9 setup-tagged tests and 3/3 idempotency tests pass after applying the migration from scratch.
- **Committed in:** `17a3571`

**3. [Rule 2 - Missing Critical] Closed the transitive timezone HTTP update surface**
- **Found during:** Task 1 dependency resolution
- **Issue:** Hex reported high/moderate advisories in Hackney 1.25.0, a transitive dependency of the exact approved Tzdata version.
- **Fix:** Disabled Tzdata automatic network updates, retained only its pinned IANA snapshot, verified no remote updater process starts, and confirmed Keepling source has no Hackney call.
- **Files modified:** `apps/server/config/config.exs`, `apps/server/test/keepling/accounts/setup_timezone_test.exs`
- **Verification:** The security-negative setup test passes and `:tzdata_release_updater` is absent.
- **Committed in:** `7058686`, `3e1c7c8`

---

**Total deviations:** 3 auto-fixed (2 Rule 2 missing critical controls, 1 Rule 3 blocking dependency/config gap)
**Impact on plan:** Every deviation is required to make the planned credential, timezone, and setup-lifecycle claims executable and secure; no unrelated product capability was added.

## Issues Encountered

- Context7 MCP and CLI were unavailable, so exact API behavior was checked against the installed pinned Argon2/Tzdata/Ecto source and then exercised against PostgreSQL 18.6.
- Hex reported advisories in Tzdata's Hackney 1.25.0 transitive dependency. The package remains compile-time transitive to the approved Tzdata version, but Keepling disables the only updater that calls it and contains no direct call path; the negative runtime test prevents silent re-enablement.
- The migration changed after its first disposable test application. Ecto correctly refused a mismatched rollback, so only the executor-owned `keepling_test` database was recreated and the current migrations were applied from scratch.

## TDD Gate Compliance

- Task 1 RED commit `4e12ec2` recorded 0/6 passing before the setup schema/API/endpoint existed; GREEN commit `7058686` made the planned slice pass.
- Task 2 RED commit `0d6da5d` recorded 0/4 passing before timezone commands existed; GREEN commit `92f71d9` made the DST, audit, invalid no-op, operator, and race behaviors pass.
- Rule 2 regression tests failed first on unbounded TTL, missing account-field constraint, and active remote-updater conditions before their fixes were applied.
- No refactor-only commit was needed after GREEN.

## Known Stubs

None - no placeholder, TODO, skipped test, mock data source, or unrun verification remains in the files changed by this plan.

## Threat Surface

- T-KPL01-11 is mitigated by operator-only issuance, 32-byte CSPRNG capability, hash-only storage, bounded expiry, generic output, and one-shot consumption.
- T-KPL01-12 is mitigated by the singleton account constraint plus locked setup row and one transaction for account creation/permanent disablement.
- T-KPL01-13 is mitigated by IANA validation, sole-account row locking, account-only update SQL, closed audit, and three view-revision increments.
- T-KPL01-14 is mitigated by closed operator/browser responses and audit facts containing no raw token, password, account identifier, task content, IP, or fingerprint.
- No additional unmodeled reachable endpoint, file-access, or schema trust boundary was introduced.

## Verification Evidence

- Focused setup/timezone file: 13/13 tests pass against PostgreSQL 18.6.
- Full server suite: 22/22 tests pass.
- `pnpm contracts:check`: OpenAPI and generated TypeScript agree.
- `./tooling/test-phase-1.sh --run`: repository integrity, server compile, contracts, web-unit discovery, and Playwright real-stack discovery pass.
- Fresh migration application: both Phase 1 migrations applied successfully to a newly created executor-owned PostgreSQL database.

## User Setup Required

None for verification. Production operators explicitly run `mix keepling.setup_token --base-url https://their-host` and complete the returned one-time setup link; no deployment default creates an account or timezone.

## Next Phase Readiness

- Plan 01-07 can add password login, recovery, sessions, and abuse controls against the durable Argon2id account created here.
- Plan 01-08 can make the setup and authentication screens reachable without inventing another registration or account-setting path.
- Plans 01-12 and 01-13 can use `account_date_at/1` and the three view revisions while retaining exclusive ownership of task civil-date columns and temporal projections.
- No high-severity mitigation assigned to Plan 01-06 remains open.

## Self-Check: PASSED

- All required setup, timezone, migration, contract, generated transport, test, and summary files exist on disk.
- Task and deviation commits `4e12ec2`, `7058686`, `0d6da5d`, `92f71d9`, `17a3571`, and `3e1c7c8` exist in Git history.
- Required actuals, coverage, requirement IDs, TDD evidence, stub scan, threat mitigations, and `status: complete` metadata are present.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-30*
