---
phase: KPL-01-one-trustworthy-task
plan: 01
subsystem: tooling
tags: [supply-chain, asdf, elixir, erlang, postgresql, runtime-gate]

requires: []
provides:
  - Human-approved exact pins for all eight research-flagged Hex/npm packages
  - Executable runtime gate for Elixir 1.20.2, OTP 29.0.5, and PostgreSQL 18.6
  - Stable runtime wrapper that preserves the user-owned untracked .tool-versions
affects: [KPL-01-02, KPL-01-03, KPL-01-04, dependency-installation, server-tooling]

actuals:
  tokens: 5827
  tasks: 2
  commits: 3

tech-stack:
  added: [Elixir 1.20.2, Erlang/OTP 29.0.5, PostgreSQL 18.6]
  patterns: [exact-version manifest, fail-closed runtime preflight, environment-scoped asdf selection, absolute Homebrew keg selection]

key-files:
  created:
    - .planning/phases/KPL-01-one-trustworthy-task/01-PACKAGE-APPROVAL.md
    - tooling/runtime-versions.env
    - tooling/runtime-preflight.sh
  modified: []

key-decisions:
  - "The blanket approval applies only to the eight inspected exact package versions; any version change requires a new provenance review and disposition."
  - "Runtime selection is repository-owned through asdf environment variables and the absolute Homebrew postgresql@18 keg, without modifying .tool-versions."

patterns-established:
  - "Supply-chain gate: retain official registry/source/provenance evidence alongside an explicit exact-version human disposition."
  - "Runtime gate: provision exact versions, verify every required executable, and run downstream commands only after the same fail-closed check."

requirements-completed: [QUAL-01]

coverage:
  - id: D1
    description: "Official provenance evidence and an explicit user approval are recorded for all eight exact dependency pins."
    requirement: QUAL-01
    verification:
      - kind: manual_procedural
        ref: "User response `approved` at the KPL-01-01 blocking-human package-legitimacy checkpoint"
        status: pass
      - kind: other
        ref: "01-PACKAGE-APPROVAL.md required-field and no-PENDING verification"
        status: pass
    human_judgment: false
  - id: D2
    description: "Repository tooling selects and verifies Elixir 1.20.2, OTP 29.0.5, and PostgreSQL 18.6 while preserving .tool-versions."
    requirement: QUAL-01
    verification:
      - kind: integration
        ref: "./tooling/runtime-preflight.sh --check"
        status: pass
      - kind: integration
        ref: "./tooling/runtime-preflight.sh --exec -- sh -c 'elixir --version; erl ...; postgres --version; psql --version; pg_config --version'"
        status: pass
      - kind: other
        ref: "SHA-256 and git-state comparison for .tool-versions"
        status: pass
    human_judgment: false

duration: 16min
completed: 2026-08-30
status: complete
---

# Phase KPL-01 Plan 01: Dependency Approval and Runtime Gate Summary

**Exact supply-chain approvals plus a fail-closed Elixir 1.20.2 / OTP 29.0.5 / PostgreSQL 18.6 selector for every downstream Phase 1 command**

## Performance

- **Duration:** 16 min
- **Started:** 2026-08-31T00:35:00Z
- **Completed:** 2026-08-31T00:51:00Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Recorded the user's blanket approval against each of the eight inspected exact package versions, retaining registry, repository, lifecycle, and provenance evidence.
- Added a committed manifest for Elixir 1.20.2, asdf Elixir 1.20.2-otp-29, Erlang/OTP 29.0.5, and PostgreSQL 18.6.
- Provisioned and verified the exact runtime, including downstream `--exec` selection, without changing or staging the user's untracked `.tool-versions`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Verify and pin every suspicious package** - `78d133d` (docs)
2. **Task 2: Pin and gate the researched server runtimes** - `8d747b7` (chore)

## Files Created/Modified

- `.planning/phases/KPL-01-one-trustworthy-task/01-PACKAGE-APPROVAL.md` - Exact registry/source evidence and recorded human disposition for all eight flagged packages.
- `tooling/runtime-versions.env` - Canonical exact runtime version manifest.
- `tooling/runtime-preflight.sh` - POSIX check, provision, and command-execution gate with `.tool-versions` integrity protection.

## Decisions Made

- Approval is version-scoped: only the eight exact versions in the dossier are approved, and substitutions or upgrades require a new review.
- asdf selection uses `ASDF_ERLANG_VERSION` and `ASDF_ELIXIR_VERSION`; PostgreSQL selection uses Homebrew's absolute `postgresql@18` keg path so the linked PostgreSQL 14 installation cannot leak into Phase 1 commands.
- `--exec` reruns the exact version gate before invoking its command, preventing a later keg or installation drift from silently selecting a different patch.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected exact OTP patch verification**
- **Found during:** Task 2 post-provision check
- **Issue:** `erlang:system_info(otp_release)` reports major release `29`, so directly comparing it to manifest patch `29.0.5` rejected the correctly installed runtime.
- **Fix:** Verify the live release probe against major `29` and independently verify exact patch `29.0.5` from the selected asdf installation's OTP metadata.
- **Files modified:** `tooling/runtime-preflight.sh`
- **Verification:** `--check` and `--exec` both report the exact manifest versions.
- **Committed in:** `8d747b7`

**2. [Rule 1 - Bug] Made the POSIX root-resolution assignment shellcheck-clean**
- **Found during:** Task 2 static verification
- **Issue:** The initial empty `CDPATH` assignment contained spacing that ShellCheck treated as ambiguous.
- **Fix:** Use the explicit POSIX `CDPATH=''` assignment and scope the dynamic manifest-source suppression to SC1091.
- **Files modified:** `tooling/runtime-preflight.sh`
- **Verification:** `sh -n` and ShellCheck both exit successfully.
- **Committed in:** `8d747b7`

---

**Total deviations:** 2 auto-fixed (2 Rule 1 bugs)
**Impact on plan:** Both fixes make the runtime gate accurately fail closed; neither changes the approved versions or expands scope.

## Issues Encountered

- The researched runtimes were absent or stale exactly as expected: Homebrew exposed Elixir 1.19.5 / OTP 28 and PostgreSQL 14.17. The planned provisioning installed the exact pins, after which the gate passed.
- Homebrew kept PostgreSQL 18 keg-only because PostgreSQL 14 remains linked. The runtime wrapper intentionally selects the 18.6 keg by absolute prefix, so no global link change was needed.

## Known Stubs

None - no stub, placeholder, skipped test, or unrun verification remains in the plan-owned files.

## User Setup Required

None - the plan's asdf and Homebrew provisioning completed automatically.

## Next Phase Readiness

- Plans 01-02 through 01-04 may use only the approved exact dependency pins recorded in the dossier.
- Downstream Mix and PostgreSQL commands can run through `./tooling/runtime-preflight.sh --exec -- COMMAND...` and will fail before execution if any exact runtime drifts.
- No high-severity supply-chain or runtime-toolchain mitigation remains open for this plan.

## Self-Check: PASSED

- All three plan-owned artifacts and this summary exist on disk.
- Task commits `78d133d` and `8d747b7` exist in Git history.
- Required `actuals`, `coverage`, `requirements-completed`, and `status: complete` metadata are present.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-30*
