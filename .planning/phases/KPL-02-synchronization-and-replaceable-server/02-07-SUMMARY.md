---
phase: KPL-02-synchronization-and-replaceable-server
plan: 07
subsystem: infrastructure
tags: [docker, compose, caddy, phoenix-release, postgres, oci-digest, deployment]

requires:
  - phase: KPL-02-synchronization-and-replaceable-server
    plan: 06
    provides: stable release operations, semantic health, authenticated status, and schema/protocol compatibility facts
provides:
  - Exact-digest non-root Phoenix release image with tested runtime and metadata contract
  - Caddy-only public edge with private PostgreSQL and host-backed recoverable state
  - Full digest-to-migration-to-user-smoke deployment rehearsal with interruption and rollback gates
affects: [host-replacement, backup-restore, release-automation, self-hosting, compatibility]

actuals:
  tokens: 8291
  tasks: 3
  commits: 5

tech-stack:
  added: [Docker Compose, Caddy]
  patterns: [exact-digest promotion, explicit one-shot migration, private database network, host-backed named volumes, edge-held retry guidance]

key-files:
  created:
    - infra/images/server/Dockerfile
    - infra/images/server/image-metadata.schema.json
    - infra/compose/compose.yml
    - infra/caddy/Caddyfile
    - tooling/verify-image.sh
    - tooling/verify-compose.sh
    - tooling/verify-deploy.sh
  modified:
    - tooling/run-local-stack.sh

key-decisions:
  - "The reference topology promotes only an exact tested OCI digest; mutable tags are accepted only as local build inputs before their immutable image identity is resolved."
  - "PostgreSQL has no published port and all PostgreSQL/Caddy durable paths are bind-backed named volumes rooted outside containers and build directories."
  - "Caddy keeps an explicit HTTP listener for local proof while automatic HTTPS remains enabled without forced redirects, allowing real hosts to obtain certificates and failed upstreams to return bounded 503 retry guidance."
  - "Rollback is eligible only when the prior tested digest declares schema and protocol ranges containing the migrated target; otherwise deployment requires a forward fix."

patterns-established:
  - "Artifact promotion: build once, inspect the immutable manifest identity, migrate explicitly, replace only the app, then wait for semantic readiness."
  - "Interruption proof: hold the edge, return 503 plus Retry-After, replay the exact mutation after recovery, require a stable receipt, and prove undo."

requirements-completed: [OPS-01, OPS-03]

coverage:
  - id: D1
    description: "A non-root Phoenix release image with exact base-image digests, OCI compatibility labels, no source-time Mix requirement, and packaged health/status proof."
    requirement: OPS-01
    verification:
      - kind: integration
        ref: "./tooling/verify-image.sh"
        status: pass
    human_judgment: false
  - id: D2
    description: "A Caddy/Phoenix/PostgreSQL topology with private PostgreSQL, external secret files, host-backed durable state, semantic readiness, graceful stop, and edge-held 503 guidance."
    requirement: OPS-01
    verification:
      - kind: integration
        ref: "docker compose -f infra/compose/compose.yml config && ./tooling/verify-compose.sh"
        status: pass
    human_judgment: false
  - id: D3
    description: "Exact-digest deployment runs migration and readiness gates, survives honest app/database interruption, proves login/read/write/exact-retry/undo, and rejects incompatible rollback metadata."
    requirement: OPS-03
    verification:
      - kind: e2e
        ref: "./tooling/verify-deploy.sh --local"
        status: pass
    human_judgment: false

duration: 37min
completed: 2026-09-01
status: complete
---

# Phase KPL-02 Plan 07: Immutable Single-Host Deployment Summary

**An exact-digest Phoenix release now deploys behind Caddy with private PostgreSQL, recoverable host state, semantic health gates, honest interruption behavior, and compatibility-aware rollback refusal.**

## Performance

- **Duration:** 37 min
- **Started:** 2026-09-01T07:57:23Z
- **Completed:** 2026-09-01T08:34:11Z
- **Tasks:** 3
- **Files modified:** 8 infrastructure and proof files

## Accomplishments

- Built and inspected a production Phoenix release as non-root UID 10001 from exact Elixir/OTP and Debian base digests, with release/protocol/schema labels and no test-only control surface.
- Defined a Caddy-only public topology whose PostgreSQL network is internal, whose secrets arrive through external files, and whose PostgreSQL and Caddy durable state is recoverable from explicit host paths.
- Proved the full immutable digest `sha256:3df6e26b590ea322aafabf116d39014717f629d859283b82c139cd62f6e2be10` through migration, readiness, app-only recreation, database outage, setup/login, capture/read, interrupted exact retry, stable replay receipt, and undo.
- Enforced rollback eligibility against both immutable artifact identity and declared schema/protocol ranges, returning forward-fix guidance for incompatible candidates.

## Task Commits

1. **Task 1: Build the tested Phoenix release image and run one health-to-command path** - `d0d229c` (feat)
2. **Task 2: Compose Caddy, app, and private PostgreSQL with explicit ownership** - `5af0254` (feat)
3. **Task 3 RED: Add the failing exact-digest deployment rehearsal contract** - `35407e6` (test)
4. **Task 3 GREEN: Deploy exact digest through smoke and rollback gates** - `821e49f` (feat)
5. **Task 3 evidence: Record the final packaged-tested digest** - `8e4aef8` (chore)

## Files Created/Modified

- `infra/images/server/Dockerfile` - Exact-base, multi-stage, non-root Phoenix release image with OCI compatibility labels.
- `infra/images/server/image-metadata.schema.json` - Closed evidence schema for immutable digest, revision, platforms, release, and supported ranges.
- `infra/compose/compose.yml` - Digest-pinned Caddy/app/migration/PostgreSQL topology with private networking, external secrets, and host-backed named volumes.
- `infra/caddy/Caddyfile` - Public edge, automatic HTTPS policy, upstream proxying, structured access logs, and stable 503/Retry-After behavior.
- `tooling/verify-image.sh` - Packaged artifact build, identity, non-root, test-clean, health, and operator-status proof.
- `tooling/verify-compose.sh` - Static and live topology proof for privacy, durability, readiness, outage behavior, app recreation, and graceful stop.
- `tooling/verify-deploy.sh` - TDD black-box promotion, migration, user smoke, interruption replay, undo, and rollback-compatibility gate.
- `tooling/run-local-stack.sh` - Local stack entry point routed through the source-owned Compose topology.

## Decisions Made

- Recorded the locally tested image ID as the default deployment input so migration, application, and runtime status all name the same immutable artifact.
- Kept PostgreSQL entirely off host ports and separated the edge and database networks; only the application crosses both boundaries.
- Used bind-backed named volumes rather than anonymous/container storage so a replaceable host can identify, back up, restore, and remount every durable path.
- Disabled only automatic HTTP-to-HTTPS redirects, not certificate automation: local black-box proof remains reachable over explicit loopback HTTP while deployed hostnames retain automated HTTPS.
- Treated a rollback candidate outside the migrated schema or protocol range as ineligible and directed operators toward a forward fix rather than routine restore.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Preserved local HTTP proof without disabling production HTTPS automation**
- **Found during:** Task 3 GREEN deployment rehearsal
- **Issue:** Fully disabling Caddy automatic HTTPS prevented a usable local TLS policy, while enabling it with defaults redirected the explicit HTTP proof endpoint.
- **Fix:** Kept automatic certificate management enabled and disabled redirects only, with distinct explicit HTTP and HTTPS sites sharing the same proxy policy.
- **Files modified:** `infra/caddy/Caddyfile`, `infra/compose/compose.yml`
- **Verification:** Caddy configuration validation and the complete deploy verifier passed.
- **Committed in:** `821e49f`

**2. [Rule 1 - Bug] Emitted the setup capability from the running release node**
- **Found during:** Task 3 GREEN user-level smoke
- **Issue:** Release `rpc` executes the expression but does not print its return value, so the first harness could not capture the one-time setup token.
- **Fix:** Print only the issued token from inside the running node and parse its bounded token line while ignoring the runtime's optional socket warning.
- **Files modified:** `tooling/verify-deploy.sh`
- **Verification:** Packaged setup and login completed through the public edge.
- **Committed in:** `821e49f`

**3. [Rule 1 - Bug] Matched the direct task-read contract**
- **Found during:** Task 3 GREEN user-level smoke
- **Issue:** The verifier initially expected a nested `task` envelope although the established controller returns the task projection directly.
- **Fix:** Assert the direct response's `id` and `title`, preserving the public contract rather than changing the application.
- **Files modified:** `tooling/verify-deploy.sh`
- **Verification:** Capture/read, interrupted edit, stable replay receipt, and undo passed end to end.
- **Committed in:** `821e49f`

---

**Total deviations:** 3 auto-fixed Rule 1 bugs
**Impact on plan:** The fixes aligned the infrastructure proof with established Caddy and Keepling transport behavior; no architecture, canonical storage, dependency, or security boundary changed.

## Issues Encountered

- Docker Desktop's internal writable layer capacity was nearly exhausted. Disposable PostgreSQL proof clusters therefore used guarded temporary host bind paths, which also exercises the required host-recoverable storage model; no user Docker data was pruned.
- The BEAM runtime emits a bounded warning when optional SCTP support is absent from the slim runtime. Verification ignores only that known warning and still requires exact health, status, setup, and mutation outputs.

## Known Stubs

None. The scan found no TODO/FIXME/placeholder path, skipped test, hardcoded empty product surface, or unwired data source in the eight changed files.

## TDD Gate Compliance

- RED commit `35407e6` failed because the deployment contract functions did not yet exist.
- GREEN commit `821e49f` implemented the contract, and `./tooling/verify-deploy.sh --local` passed after the final immutable artifact build.

## User Setup Required

Production operators must supply host paths for the three external application secrets and PostgreSQL password, host-backed PostgreSQL/Caddy data directories, a real `KEEPLING_HOST`, and an exact tested server digest. No managed service or remote control plane is required.

## Next Phase Readiness

- Host replacement and backup/restore plans can rely on explicit host paths, immutable application identity, private database networking, semantic readiness, and stable operator status.
- Release automation can promote the tested digest, run the one-shot migration service, recreate only the application, and gate completion on the black-box user smoke.
- Incompatible rollback metadata now fails closed with forward-fix guidance; routine restore is not used as rollback.

---
*Phase: KPL-02-synchronization-and-replaceable-server*
*Completed: 2026-09-01*

## Self-Check: PASSED

- All seven created artifacts, the modified local-stack wrapper, and this summary exist on disk.
- All five task/TDD/evidence commits are present in Git history.
- Coverage metadata parsed successfully with all three deliverables backed entirely by passing automated evidence.
