---
phase: KPL-01-one-trustworthy-task
plan: 02
subsystem: server-foundation
tags: [phoenix, ecto, postgresql, hammer, otp, runtime-configuration]

requires:
  - phase: KPL-01-01
    provides: Exact runtime gate and human-approved Hammer 7.4.1 package disposition
provides:
  - Standalone Phoenix/Ecto Mix core with a committed exact dependency lock
  - Repo-only OTP supervision root preserving inward dependency direction
  - Fail-closed development, test, and production runtime configuration seams
affects: [KPL-01-03, KPL-01-07, server-web-runtime, server-test-support]

actuals:
  tokens: 5270
  tasks: 2
  commits: 3

tech-stack:
  added: [Phoenix 1.8.13, Ecto 3.14.2, Ecto SQL 3.14.0, Postgrex 0.22.4, Hammer 7.4.1, Bandit 1.12.5]
  patterns: [standalone Mix application, exact lockfile resolution, repo-only supervision root, environment-scoped runtime secrets]

key-files:
  created:
    - apps/server/mix.exs
    - apps/server/mix.lock
    - apps/server/lib/keepling/application.ex
    - apps/server/lib/keepling/repo.ex
    - apps/server/config/runtime.exs
  modified:
    - apps/server/README.md

key-decisions:
  - "Keepling.Application supervises only Keepling.Repo until Plan 01-03 adds the transport runtime, keeping the core free of Phoenix web dependencies."
  - "Database URLs and endpoint signing secrets are environment-scoped runtime inputs; production additionally requires PHX_HOST, while fixed safe host/port defaults never derive from a developer device."

patterns-established:
  - "Server commands: run all Elixir, OTP, Mix, and PostgreSQL operations through tooling/runtime-preflight.sh from the repository root."
  - "Runtime configuration: fail with the missing key and Mix environment, never the secret value, and expose explicit endpoint/database IPv6 and port seams."

requirements-completed: [QUAL-01, SRV-02]

coverage:
  - id: D1
    description: "The standalone server has a complete locked Hex graph with exact Hammer 7.4.1 manifest and lock entries."
    requirement: QUAL-01
    verification:
      - kind: integration
        ref: "./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && mix deps.get --check-locked && mix deps.unlock --check-unused && mix compile --warnings-as-errors'"
        status: pass
    human_judgment: false
  - id: D2
    description: "The Repo-only OTP core and repository layout establish the inward semantic boundary without an umbrella or nested Git metadata."
    requirement: SRV-02
    verification:
      - kind: other
        ref: "./tooling/check-repository-integrity.sh plus inward-core forbidden-reference scan"
        status: pass
    human_judgment: false
  - id: D3
    description: "All five environment configurations compile, require runtime credentials by named environment, and expose Sandbox, host/port, IPv6, and endpoint-start seams."
    requirement: QUAL-01
    verification:
      - kind: integration
        ref: "./tooling/runtime-preflight.sh --exec -- sh -c 'cd apps/server && MIX_ENV=test mix compile --warnings-as-errors && MIX_ENV=prod mix compile --warnings-as-errors'"
        status: pass
      - kind: integration
        ref: "mix run --no-start runtime configuration probes for missing production keys and valid test/production settings"
        status: pass
    human_judgment: false

duration: 8min
completed: 2026-08-30
status: complete
---

# Phase KPL-01 Plan 02: Standalone Server Core Summary

**Phoenix 1.8.13 and Ecto 3.14 core with an exact Hammer 7.4.1 lock, Repo-only supervision, and credential-free fail-closed runtime configuration**

## Performance

- **Duration:** 8 min
- **Started:** 2026-08-31T00:54:41Z
- **Completed:** 2026-08-31T01:01:56Z
- **Tasks:** 2
- **Files modified:** 13

## Accomplishments

- Materialized the seven-file standalone Mix/OTP core and committed the complete resolved Hex graph, including the human-approved Hammer 7.4.1 release and official checksum.
- Kept `Keepling.Application` transport-neutral and supervising only `Keepling.Repo`, with no umbrella, nested repository, submodule, or generated Git metadata.
- Added explicit development, test, production, and runtime configuration with SQL Sandbox, required secret/database inputs, production host validation, and endpoint/database IPv4/IPv6 and port seams.

## Task Commits

Each task was committed atomically:

1. **Task 1: Materialize the exact standalone Mix and OTP core** - `479e55a` (feat)
2. **Task 2: Own every server environment configuration** - `0b20da3` (feat)

## Files Created/Modified

- `apps/server/.formatter.exs` - Generated Elixir/Ecto/Phoenix formatting inputs.
- `apps/server/.gitignore` - Application build, dependency, coverage, documentation, and crash-artifact exclusions.
- `apps/server/mix.exs` - Standalone application manifest pinned to Elixir 1.20.2 with exact Hammer 7.4.1.
- `apps/server/mix.lock` - Exact complete Hex dependency resolution.
- `apps/server/lib/keepling.ex` - Inward-facing domain/application namespace statement.
- `apps/server/lib/keepling/application.ex` - Repo-only OTP supervision root.
- `apps/server/lib/keepling/repo.ex` - PostgreSQL Ecto repository adapter root.
- `apps/server/config/config.exs` - Shared Repo, generator, endpoint, logging, and JSON configuration.
- `apps/server/config/dev.exs` - Development diagnostics and code-reload policy without embedded credentials.
- `apps/server/config/test.exs` - SQL Sandbox and non-serving test endpoint policy.
- `apps/server/config/prod.exs` - Production SSL enforcement and logging policy.
- `apps/server/config/runtime.exs` - Required environment validation and runtime database/endpoint seams.
- `apps/server/README.md` - Boundary rules, required environment keys, and exact preflight/setup/compile/test commands.

## Decisions Made

- Deferred Endpoint, router, telemetry, seeds, and ExUnit support exactly to Plan 01-03; the current application starts only the Repo and does not depend on absent transport modules.
- Required environment-specific database URLs and signing secrets for every application-starting environment, eliminating committed development/test credentials while keeping compile-only validation deterministic.
- Interpreted `PHX_SERVER`, `PHX_IPV6`, and `ECTO_IPV6` as closed boolean inputs (`true`/`false` or `1`/`0`) so typos fail instead of silently changing runtime exposure.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Hex reported an expired user authentication session, then successfully resolved, fetched, and rechecked every public locked dependency without private-resource access. No authentication gate blocked the plan.
- Dependency compilation emitted upstream Elixir 1.20 type/deprecation warnings, but the plan's `--warnings-as-errors` application compilation commands exited successfully; no Keepling source warning remained.

## Known Stubs

None - no stub, placeholder, skipped test, or unrun verification remains in the plan-owned files. The configured web module atoms are an explicit Plan 01-03 integration seam, not placeholder implementation.

## User Setup Required

None for dependency or compile verification. Starting a development, test, or production runtime requires the environment-specific database URL and signing-secret keys documented in `apps/server/README.md`; production also requires `PHX_HOST`.

## Next Phase Readiness

- Plan 01-03 can add Endpoint, router, telemetry, migrations/seeds, and ExUnit support onto a compiling locked core without regenerating or replacing these files.
- Plan 01-07 can add the application-owned Hammer ETS limiter child and D-53 policy without changing the approved dependency version.
- No high-severity dependency tampering, runtime configuration disclosure, or core dependency-direction mitigation remains open for this plan.

## Self-Check: PASSED

- All 13 implementation files and this summary exist on disk.
- Task commits `479e55a` and `0b20da3` exist in Git history.
- Required `actuals`, `coverage`, `requirements-completed`, and `status: complete` metadata are present.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-30*
