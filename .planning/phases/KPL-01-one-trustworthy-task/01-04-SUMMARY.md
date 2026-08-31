---
phase: KPL-01-one-trustworthy-task
plan: 04
subsystem: testing-and-contracts
tags: [vitest, playwright, openapi, typescript, postgresql, phoenix, deterministic-tooling]

requires:
  - phase: KPL-01-01
    provides: Exact runtime gate and human-approved browser/test dependency pins
  - phase: KPL-01-02
    provides: Runnable standalone Mix/Ecto core for the initial phase-runner compile lane
provides:
  - Deterministic Vitest/jsdom and Playwright discovery before feature specs exist
  - Loopback-only owned PostgreSQL/Phoenix/Vite real-stack orchestration
  - Checked-in OpenAPI 3.1 source, immutable TypeScript transport, and drift enforcement
  - Fail-fast local-stack and currently-available Phase 1 lane runners
affects: [KPL-01-03, KPL-01-05, browser-verification, transport-contracts, phase-1-testing]

actuals:
  tokens: 22272
  tasks: 2
  commits: 4

tech-stack:
  added: [Vitest 4.1.11, jsdom 30.0.1, Playwright 1.62.1, Testing Library, axe Playwright 4.13.0, openapi-typescript 7.13.0, TypeScript 5.9.3 generator peer]
  patterns: [checked-in generated contract, byte-for-byte drift gate, owned process groups, loopback-only disposable stack, native fail-fast root scripts]

key-files:
  created:
    - apps/web/vitest.config.ts
    - apps/web/playwright.config.ts
    - apps/web/e2e/support/stack.ts
    - packages/contracts/openapi/keepling.yaml
    - packages/contracts/generated/keepling.ts
    - tooling/check-contracts.mjs
    - tooling/run-local-stack.sh
    - tooling/test-phase-1.sh
  modified:
    - apps/web/package.json
    - apps/web/README.md
    - package.json
    - pnpm-lock.yaml

key-decisions:
  - "The Playwright harness uses one loopback reverse proxy for browser traffic while Phoenix, Vite, and disposable PostgreSQL remain separately owned child process groups."
  - "The approved openapi-typescript 7.13.0 generator receives a root-only TypeScript 5.9.3 peer; the browser retains its independent TypeScript 6 toolchain."
  - "Phase 1's consolidated runner names and executes only lanes that exist now; later plans extend it when their tests become real."

patterns-established:
  - "Browser harness: Vitest runs once with jsdom cleanup and deterministic browser shims; Playwright discovery includes an infrastructure contract before feature specs."
  - "Real-stack ownership: every PostgreSQL/Phoenix command crosses runtime-preflight, services bind to loopback, and cleanup targets only spawned process groups and their disposable data directory."
  - "Contract truth: edit OpenAPI source, regenerate the checked-in immutable TypeScript output, and require contracts:check to reject drift."

requirements-completed: [QUAL-01, WEB-01, WEB-02, SRV-02]

coverage:
  - id: D1
    description: "Vitest/jsdom loads Testing Library matchers, cleanup, and deterministic browser helpers with no watch default."
    requirement: WEB-02
    verification:
      - kind: unit
        ref: "pnpm --filter @keepling/web test --run --passWithNoTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "Playwright discovers its loopback-only owned real-stack harness and per-run test-fault credential contract before feature specs exist."
    requirement: WEB-01
    verification:
      - kind: integration
        ref: "pnpm --filter @keepling/web exec playwright test --list"
        status: pass
      - kind: other
        ref: "./tooling/run-local-stack.sh --check-config"
        status: pass
    human_judgment: false
  - id: D3
    description: "OpenAPI 3.1 transport truth produces deterministic immutable TypeScript and fails on checked-in output drift."
    requirement: SRV-02
    verification:
      - kind: integration
        ref: "pnpm contracts:check"
        status: pass
    human_judgment: false
  - id: D4
    description: "The root Phase 1 runner fails fast across repository integrity, server compile, contract, Vitest, and Playwright discovery lanes that exist today."
    requirement: QUAL-01
    verification:
      - kind: integration
        ref: "./tooling/test-phase-1.sh --run"
        status: pass
    human_judgment: false

duration: 10min
completed: 2026-08-30
status: complete
---

# Phase KPL-01 Plan 04: Browser, Contract, and Stack Harness Summary

**Exact-pinned Vitest and Playwright foundations with a loopback-only PostgreSQL/Phoenix/Vite stack, checked-in OpenAPI transport generation, and fail-fast native Phase 1 commands**

## Performance

- **Duration:** 10 min
- **Started:** 2026-08-31T01:07:04Z
- **Completed:** 2026-08-31T01:17:05Z
- **Tasks:** 2
- **Files modified:** 13

## Accomplishments

- Installed the exact approved Vitest, Testing Library, jsdom, Playwright, and axe versions and proved both test runners load before feature specs exist.
- Added an owned real-stack launcher that initializes disposable PostgreSQL 18.6, migrates/seeds through the exact runtime wrapper, starts Phoenix and Vite behind one origin, and cleans only its own process groups.
- Established OpenAPI 3.1 as checked-in transport truth with immutable generated TypeScript and executable drift enforcement.
- Added root-aware local-stack and Phase 1 commands whose listed and executed lanes match the artifacts currently present.

## Task Commits

Each task was committed atomically:

1. **Task 1: Install executable Vitest and Playwright orchestration** - `2cd01dd` (chore)
2. **Task 2: Establish generated-contract and local-stack commands** - `68cac08` (chore)
3. **Security hardening deviation: Keep the disposable test stack loopback-only** - `20dc92b` (fix)

## Files Created/Modified

- `apps/web/vitest.config.ts` - jsdom test configuration with deterministic setup and no-test bootstrap support.
- `apps/web/src/test/setup.ts` - Testing Library matchers, explicit cleanup, and deterministic media/scroll shims.
- `apps/web/playwright.config.ts` - single-worker real-stack discovery, trace/screenshot retention, and per-run fault credential.
- `apps/web/e2e/support/stack.ts` - disposable PostgreSQL/Phoenix/Vite orchestration, same-origin proxy, and owned cleanup.
- `packages/contracts/openapi/keepling.yaml` - initial OpenAPI 3.1 semantic transport primitives.
- `packages/contracts/generated/keepling.ts` - deterministic immutable generated transport types.
- `tooling/check-contracts.mjs` - generated-output drift enforcement through the exact local generator.
- `tooling/run-local-stack.sh` - root-aware preflight/configuration/start command for the owned stack.
- `tooling/test-phase-1.sh` - fail-fast list/run command for currently available Phase 1 lanes.
- `apps/web/package.json`, `package.json`, and `pnpm-lock.yaml` - exact test/generator pins and native scripts.
- `apps/web/README.md` - browser test and stack ownership guidance.

## Decisions Made

- Used a small Node reverse proxy inside the test launcher so browser requests have one origin without expanding this task into Vite application configuration.
- Bound PostgreSQL, Phoenix, Vite, and the public proxy exclusively to `127.0.0.1`; environment attempts to widen the bind fail before any process starts.
- Kept `openapi-typescript` on its declared TypeScript 5 peer through a root-only exact pin rather than changing the web application's TypeScript 6 toolchain.
- Made the Playwright support module double as a small infrastructure contract so the plan's exact `--list` command succeeds before feature specs are added.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Made empty-feature Playwright discovery executable**
- **Found during:** Task 1 verification
- **Issue:** Playwright 1.62 returns exit code 1 for `test --list` when it discovers zero tests, contradicting the plan's required pre-feature discovery command.
- **Fix:** Added a focused harness contract in `e2e/support/stack.ts` and included it in `testMatch` without inventing a product feature spec.
- **Files modified:** `apps/web/playwright.config.ts`, `apps/web/e2e/support/stack.ts`
- **Verification:** `pnpm --filter @keepling/web exec playwright test --list` lists one harness contract and exits 0.
- **Committed in:** `2cd01dd`

**2. [Rule 3 - Blocking] Satisfied the exact generator's supported TypeScript peer**
- **Found during:** Task 2 dependency installation
- **Issue:** `openapi-typescript@7.13.0` declares TypeScript `^5.x`, while pnpm initially paired it with the web workspace's TypeScript 6.0.3 and emitted an unresolved peer warning.
- **Fix:** Added a root-only exact `typescript@5.9.3` peer for contract generation; the web package remains independently on TypeScript 6.
- **Files modified:** `package.json`, `pnpm-lock.yaml`
- **Verification:** `pnpm install --frozen-lockfile`, `pnpm list --depth 0`, and `pnpm contracts:check` pass without the unresolved generator peer.
- **Committed in:** `68cac08`

**3. [Rule 2 - Missing Critical] Prevented public binding of the disposable trust-auth database**
- **Found during:** Overall threat-surface review
- **Issue:** A caller could override the harness host and bind temporary PostgreSQL outside loopback, contrary to the repository's database exposure rule.
- **Fix:** Reject every host other than `127.0.0.1` and validate all configured ports before process launch.
- **Files modified:** `apps/web/e2e/support/stack.ts`
- **Verification:** TypeScript syntax, ESLint, Playwright discovery, and local-stack configuration checks all pass after the guard.
- **Committed in:** `20dc92b`

---

**Total deviations:** 3 auto-fixed (1 Rule 1 bug, 1 Rule 2 missing critical control, 1 Rule 3 blocking dependency issue)
**Impact on plan:** The fixes preserve the planned architecture and exact approved package versions while making discovery, generation, and local database exposure fail closed.

## Issues Encountered

- Context7 tooling was unavailable in this runtime. Implementation was grounded in the installed exact-version CLI help and type definitions, then verified by executing every planned command.
- The full migrated Phoenix browser stack is intentionally not started in this plan because Plan 01-03 owns the Endpoint and seed entry. This plan proves the orchestration/configuration boundary required before later E2E specs invoke it; no full-stack behavior claim is made here.

## Known Stubs

None - the intentionally empty OpenAPI `paths` object declares no route that does not yet exist, and no placeholder, skipped test, or unrun plan verification remains.

## User Setup Required

None - exact dependencies and runtime configuration checks are repository-owned.

## Next Phase Readiness

- Plan 01-03 can supply the Phoenix Endpoint and deterministic seed entry consumed by the already-checked stack launcher.
- Plan 01-05 and later browser slices can add feature specs without creating test configs, transport generation, or process orchestration first.
- No high-severity test-fault, contract-tampering, process-cleanup, or database-exposure mitigation remains open in this plan.

## Self-Check: PASSED

- All nine key created artifacts and this summary exist on disk.
- Task/deviation commits `2cd01dd`, `68cac08`, and `20dc92b` exist in Git history.
- Required `actuals`, coverage, requirements, and `status: complete` metadata are present.

---
*Phase: KPL-01-one-trustworthy-task*
*Completed: 2026-08-30*
