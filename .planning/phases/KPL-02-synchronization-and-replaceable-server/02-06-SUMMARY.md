---
phase: KPL-02-synchronization-and-replaceable-server
plan: 06
subsystem: operations
tags: [elixir, phoenix, postgres, health, readiness, release-cli, recovery]

requires:
  - phase: KPL-02-synchronization-and-replaceable-server
    plan: 04
    provides: authoritative release, OCI digest, protocol, schema, and compatibility policy
  - phase: KPL-02-synchronization-and-replaceable-server
    plan: 05
    provides: finalized restore epoch, privacy-safe diagnostics, and authenticated transport boundaries
provides:
  - Closed inward operational policy for all nine D-40 verbs with stable result and exit classes
  - Process-only liveness, bounded serving readiness, and separately authenticated operator status
  - Equivalent source and packaged-release CLI with JSON, human, no-color, remediation, and redaction proof
  - Singleton operations state and digested restore-verification evidence
affects: [backup, restore, deployment, host-replacement, compose-health, release-automation]

actuals:
  tokens: 12851
  tasks: 3
  commits: 6

tech-stack:
  added: []
  patterns: [inward operations policy, closed result envelope, bounded readiness, hash-only operator authorization, release-safe with_repo]

key-files:
  created:
    - apps/server/lib/keepling/application/ops.ex
    - apps/server/lib/keepling/adapters/postgres/ops_store.ex
    - apps/server/lib/keepling_web/controllers/health_controller.ex
    - apps/server/lib/keepling/release.ex
    - apps/server/lib/mix/tasks/keepling.ops.ex
    - apps/server/priv/repo/migrations/20260901000400_add_ops_state.exs
    - tooling/keepling-ops
    - tooling/test-ops-cli.sh
  modified:
    - apps/server/config/runtime.exs
    - apps/server/lib/keepling_web/router.ex

key-decisions:
  - "Operational exit classes are frozen as success 0, usage 2, safety refusal 10, dependency 20, compatibility 30, recovery 40, and execution 50."
  - "Public readiness excludes backup and WAL freshness; those facts degrade operator status and refuse deploy preflight instead."
  - "Operator HTTP status uses a distinct minimum-32-byte credential retained only as a SHA-256 hash in application configuration."
  - "Source and release commands share one Elixir parser, renderer, policy, and exit contract; release inspection starts only Ecto and Repo through Ecto.Migrator.with_repo/3."

patterns-established:
  - "Closed ops result: version, operation, status, code, exit_code, retryable, allow-listed facts, and copyable remediation are the only serialized fields."
  - "Health separation: liveness is process-only, readiness is minimal and serving-specific, and full recovery facts require operator authentication."
  - "Release-safe operations: shell transports arguments and selects the runtime; ordinary Elixir owns parsing, safety decisions, rendering, and exits."

requirements-completed: [OPS-04, OPS-05, QUAL-05]

coverage:
  - id: D1
    description: "All nine operator verbs produce closed human/JSON results, stable exit classes, bounded facts, and inward-owned refusals/remediation."
    requirement: OPS-04
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/application/ops/status_test.exs#6 status, refusal, exit, and persistence tests"
        status: pass
      - kind: other
        ref: "tooling/test-ops-cli.sh#9 source/release verb pairs"
        status: pass
    human_judgment: false
  - id: D2
    description: "Public liveness is process-only, readiness checks bounded serving dependencies without backup freshness, and full status is separately operator-authorized."
    requirement: OPS-05
    verification:
      - kind: integration
        ref: "apps/server/test/keepling_web/health_test.exs#5 liveness, readiness, dependency, authorization, and privacy tests"
        status: pass
    human_judgment: false
  - id: D3
    description: "Diagnostics and CLI streams exclude raw content, credentials, identifiers, arguments, provider bodies, and framework log contamination."
    requirement: QUAL-05
    verification:
      - kind: integration
        ref: "tooling/test-ops-cli.sh#closed JSON, hostile sentinel, no-color, and release equivalence proof"
        status: pass
      - kind: unit
        ref: "apps/server/test/keepling/application/ops/status_test.exs#bounded D-43 facts and digested restore proof"
        status: pass
    human_judgment: false

duration: 17min
completed: 2026-09-01
status: complete
---

# Phase KPL-02 Plan 06: Stable Operations and Truthful Health Summary

**One inward operations policy now drives privacy-bounded health, authenticated status, and equivalent source/release automation for all nine operator verbs.**

## Performance

- **Duration:** 17 min
- **Started:** 2026-09-01T07:33:39Z
- **Completed:** 2026-09-01T07:50:24Z
- **Tasks:** 3
- **Files modified:** 12 implementation, migration, configuration, wrapper, and proof files

## Accomplishments

- Implemented all nine D-40 verbs through one closed inward result envelope with stable exit classes, allow-listed facts, copyable remediation, and fail-closed destructive target validation.
- Added singleton traffic/backup/WAL state plus SHA-256-only restore-source proof metadata, bounded restore-verification status, migration state, schema/protocol ranges, release revision, tested digest, and restore epoch.
- Exposed process-only `/health/live`, bounded `/health/ready`, and separately authenticated `/ops/status`, proving that backup lag degrades operator health without taking a serving-correct server out of readiness.
- Added one repository-root CLI whose source Mix task and packaged release eval path produce semantically identical JSON/human results and exact exit codes without booting the endpoint or other production side effects.
- Kept the full server suite green at 163 tests including one property.

## Task Commits

Each TDD task was committed as a RED test followed by its GREEN implementation:

1. **Task 1 RED: closed operator result and proof contract** - `95d877c` (test)
2. **Task 1 GREEN: inward operations policy and PostgreSQL proof store** - `f2ed0df` (feat)
3. **Task 2 RED: truthful public/operator health boundaries** - `8154140` (test)
4. **Task 2 GREEN: liveness, readiness, and operator status** - `c789467` (feat)
5. **Task 3 RED: source/release black-box CLI contract** - `9f5da6b` (test)
6. **Task 3 GREEN: release-safe shared operations CLI** - `db1b1bc` (feat)

## Files Created/Modified

- `apps/server/lib/keepling/application/ops.ex` - Closed inward operations policy, readiness semantics, stable exits, target checks, bounded facts, and remediation.
- `apps/server/lib/keepling/adapters/postgres/ops_store.ex` - Bounded PostgreSQL inspection and SHA-256-only restore-verification persistence.
- `apps/server/priv/repo/migrations/20260901000400_add_ops_state.exs` - Additive singleton operations state and closed restore proof schema.
- `apps/server/lib/keepling_web/controllers/health_controller.ex` - Minimal public probes and separately authenticated operator projection.
- `apps/server/lib/keepling_web/router.ex` - Public health and operator status routes.
- `apps/server/config/runtime.exs` - Minimum-length operator credential validation and hash-only runtime configuration.
- `apps/server/lib/keepling/release.ex` - Shared parser, renderer, with-repo invocation, and stable process exit.
- `apps/server/lib/mix/tasks/keepling.ops.ex` - Source-time adapter that explicitly loads runtime configuration.
- `tooling/keepling-ops` - Thin repository-root source/release selector and argument transport.
- `tooling/test-ops-cli.sh` - Packaged release build plus nine-verb equivalence, exit, JSON, no-color, and redaction proof.
- `apps/server/test/keepling/application/ops/status_test.exs` - Inward result, policy, privacy, exit, and restore-proof tests.
- `apps/server/test/keepling_web/health_test.exs` - Liveness, readiness, dependency, authorization, and public-privacy tests.

## Decisions Made

- Froze exact exit numbers by failure class because OPS-04/OPS-05 left the numbers to planner discretion and CI/release callers require a durable automation contract.
- Kept public serving readiness deliberately independent of backup age and WAL lag while making both visible in operator status and blocking deploy/upgrade/host-replacement preflight.
- Used a distinct operator credential rather than browser sessions or native device grants; runtime configuration retains only its SHA-256 hash and comparisons are constant-time.
- Used `Application.ensure_loaded/1` and `Ecto.Migrator.with_repo/3` for source/release inspection so an ops command does not start Phoenix, PubSub, DNS, rate limiting, or background telemetry.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Advanced the ops migration timestamp**
- **Found during:** Task 1 context inspection
- **Issue:** The planned `20260901000300_add_ops_state.exs` path collided with plan 02-05's existing `20260901000300_initialize_sync_epoch.exs` migration.
- **Fix:** Used the next free additive timestamp, `20260901000400`, without rewriting or renumbering the prior migration.
- **Files modified:** `apps/server/priv/repo/migrations/20260901000400_add_ops_state.exs`
- **Verification:** Fresh migrations and the 163-test server suite passed.
- **Committed in:** `f2ed0df`

**2. [Rule 1 - Bug] Normalized raw SQL timestamps before bounded rendering**
- **Found during:** Task 1 GREEN verification
- **Issue:** PostgreSQL raw SQL returned `utc_datetime_usec` fields as `NaiveDateTime`, while the adapter initially formatted only `DateTime` values.
- **Fix:** Normalize both timestamp representations to UTC and truncate operator output to stable second precision.
- **Files modified:** `apps/server/lib/keepling/adapters/postgres/ops_store.ex`
- **Verification:** Focused ops suite passed 6/6.
- **Committed in:** `f2ed0df`

**3. [Rule 3 - Blocking] Loaded runtime configuration for the source Mix adapter**
- **Found during:** Task 3 packaged black-box verification
- **Issue:** Arbitrary Mix tasks do not automatically require `app.config`, so the source path reached `with_repo` with compile-time Repo configuration and no database URL.
- **Fix:** Declared the Mix task's `app.config` requirement; the release path continues to use release runtime configuration directly.
- **Files modified:** `apps/server/lib/mix/tasks/keepling.ops.ex`
- **Verification:** All nine source/release verb pairs produced identical JSON.
- **Committed in:** `db1b1bc`

**4. [Rule 1 - Bug] Kept automation stdout machine-readable**
- **Found during:** Task 3 JSON verification
- **Issue:** Runtime-preflight banners, Ecto debug logs, a stray Mix `--` argument, and OptionParser's boolean negation convention could contaminate JSON or misclassify valid `--no-color` requests.
- **Fix:** Strip only the known preflight banner while preserving the command exit, temporarily suppress framework logging during the short-lived invocation, pass task arguments exactly, and parse `--no-color` through the `color: :boolean` switch.
- **Files modified:** `apps/server/lib/keepling/release.ex`, `tooling/keepling-ops`
- **Verification:** Black-box proof passed closed JSON, exact exits, no-color, hostile-value redaction, and semantic source/release equality.
- **Committed in:** `db1b1bc`

**5. [Rule 3 - Blocking] Built the packaged proof under the pinned runtime**
- **Found during:** Task 3 release-build verification
- **Issue:** The first black-box harness invoked `mix release` outside the repository runtime selector, so asdf correctly refused an implicit version.
- **Fix:** Run database preparation and release assembly through `tooling/runtime-preflight.sh`.
- **Files modified:** `tooling/test-ops-cli.sh`
- **Verification:** The packaged release built and all nine release eval commands passed.
- **Committed in:** `db1b1bc`

---

**Total deviations:** 5 auto-fixed (2 Rule 1 bugs, 3 Rule 3 blockers)
**Impact on plan:** Every fix was required for migration safety, runtime correctness, or trustworthy automation output; no new dependency, canonical store, provider coupling, or domain-layer outward dependency was introduced.

## Issues Encountered

- The literal focused Mix commands require the repository's explicit test database environment. Verification used an isolated PostgreSQL 18.6 cluster under `/tmp` with all migrations applied.
- Context7 was unavailable through MCP and the approved `ctx7` CLI fallback was not installed. Release-safe behavior was therefore verified against the checked-out Ecto SQL 3.14.0 `Ecto.Migrator` source and exercised through an actual packaged release.
- The full suite emitted its expected bounded security-audit degradation and database-timeout signals while completing successfully.

## Known Stubs

None. The scan found no TODO/FIXME/placeholder path, skipped test, hardcoded empty value flowing to a product surface, or unwired data source.

## User Setup Required

Production releases must set `KEEPLING_OPERATOR_TOKEN` to a random value of at least 32 bytes. The application stores only its SHA-256 hash in runtime configuration; later infrastructure plans own secret placement and rotation.

## Next Phase Readiness

- Backup, restore, deployment, and host-replacement adapters can implement outward execution behind the frozen inward policy without moving safety rules into shell or infrastructure code.
- Compose, image, and deploy plans can use `/health/live`, `/health/ready`, and the stable CLI exit vocabulary without parsing human prose.
- Restore work can persist a digested proof, finalize the synchronization epoch, and expose the bounded verification result without representative task content.

---
*Phase: KPL-02-synchronization-and-replaceable-server*
*Completed: 2026-09-01*

## Self-Check: PASSED

- All eight created implementation, migration, wrapper, and proof artifacts plus this summary exist on disk.
- All six RED/GREEN task commits are present in Git history.
- Coverage metadata parsed successfully with all three deliverables backed entirely by passing automated evidence.
