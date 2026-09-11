---
phase: KPL-06-portability-and-trust-release
plan: 12
subsystem: trust-oracle
tags: [reconciliation, invariants, chaos-engineering, census, self-test, D-45, D-46, D-47, D-48, D-49, D-50, D-51, T-06-12]

requires:
  - phase: KPL-06-02
    provides: the release-lane/verifier spine (verify-release.mjs's digest-binding and offline-degradation conventions) this gate's evidence artifact follows
  - phase: KPL-06-06
    provides: refusal_records, the durable local home invariant I3 is a predicate over
  - phase: KPL-06-07
    provides: the receipt-issuer binding and the 20260912000200 migration timestamp this plan's own migration had to avoid colliding with

provides:
  - tooling/trust-lanes/oracle.mjs — a read-only reconciliation oracle over three independent sources (server via select-only DB role + read-only health endpoint, desktop SQLite opened read-only, iOS SQLite pulled from device), structurally unable to write anywhere and importing no client code
  - tooling/trust-lanes/invariants.mjs — eight schema-level predicates (I1-I8) emitting only closed-vocabulary, keyed-digest violation records
  - tooling/trust-lanes/chaos.mjs — ten named, seeded chaos operators with a corpus digest, --list-operators, and --dry-run
  - tooling/trust-lanes/census.mjs — a per-day exposure ledger distinguishing thin days from clean ones
  - tooling/verify-trust-soak.mjs — the --self-test/--gate CLI producing a five-digest-bound evidence artifact with three honest verdicts (PASS/DISCLOSED-NOT-PROVEN/BLOCKED)
  - the keepling_auditor read-only database role (20260912000300_add_auditor_role.exs)
  - docs/testing/trust-soak.md, extending (not replacing) the existing dogfood contracts

affects: [KPL-06-13-final-verification]

actuals:
  tokens: 17502
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "A checker's read-only guarantee is enforced by static negative gates that scan the checker's own source for mutating SQL and non-read HTTP verbs, mirroring tooling/verify-cross-adapter-phase.mjs's guard-refusal pattern but scoped to write-authority rather than shortcut-detection"
    - "A dataset-shape boundary between a real-infrastructure reader (oracle.mjs) and pure predicate functions (invariants.mjs) lets the self-test corpus exercise every invariant with hand-authored synthetic datasets, with zero dependency on live Postgres/SQLite/device infrastructure being present"
    - "A run-conflict lock file with an age-based staleness threshold distinguishes an interrupted prior run from a genuinely overlapping one, without needing real process-liveness signalling"

key-files:
  created:
    - tooling/trust-lanes/oracle.mjs
    - tooling/trust-lanes/invariants.mjs
    - tooling/trust-lanes/chaos.mjs
    - tooling/trust-lanes/census.mjs
    - tooling/trust-lanes/fixtures/i1-stale-in-flight.json
    - tooling/trust-lanes/fixtures/i2-receipt-absent-desktop.json
    - tooling/trust-lanes/fixtures/i2-receipt-absent-ios.json
    - tooling/trust-lanes/fixtures/i3-refusal-not-durable.json
    - tooling/trust-lanes/fixtures/i4-projection-mismatch-desktop.json
    - tooling/trust-lanes/fixtures/i4-projection-mismatch-ios.json
    - tooling/trust-lanes/fixtures/i5-cursor-regression.json
    - tooling/trust-lanes/fixtures/i5-feed-gap.json
    - tooling/trust-lanes/fixtures/i6-revision-regression-desktop.json
    - tooling/trust-lanes/fixtures/i6-revision-regression-server.json
    - tooling/trust-lanes/fixtures/i7-tombstone-incoherent.json
    - tooling/trust-lanes/fixtures/i8-activity-incomplete.json
    - tooling/verify-trust-soak.mjs
    - apps/server/priv/repo/migrations/20260912000300_add_auditor_role.exs
    - docs/testing/trust-soak.md
  modified: []

key-decisions:
  - "Migration named 20260912000300_add_auditor_role.exs, not the plan-drafted 20260912000200 — that exact timestamp was already used by 06-07's add_command_receipts_issuing_grant.exs, confirmed by directory listing before naming the file, matching 06-06's own precedent for the same class of collision."
  - "The read-only database identity is provisioned by an idempotent Ecto migration (DO $$ blocks for CREATE ROLE/ALTER ROLE, since Postgres has no CREATE ROLE IF NOT EXISTS), granting SELECT on all present-and-future public-schema tables via ALTER DEFAULT PRIVILEGES, and nothing else — verified directly by attempting a write and an INSERT as that role against a real local database, both refused with 'permission denied for table'."
  - "The server's entity content digest is computed INSIDE Postgres via sha256(convert_to(...)) over the row's own columns, then reduced again with the run-local HMAC key in Node — the oracle's own process never receives a task's plaintext title at all for the server source, not merely 'reads it and doesn't log it'."
  - "'The server through its own read endpoints' is proven structurally via a GET to /health/ready (a genuinely read-only, unauthenticated endpoint) rather than modelling a full authenticated bulk-read API — Keepling has no existing bulk agent-readable task-listing endpoint outside the non-destructive export verb, and building one was out of this plan's declared file scope. The select-only database read is the oracle's substantive server-side source; the endpoint read is the second independent eye the plan's own three-reads design calls for. Disclosed as a scoping decision, not a silent narrowing."
  - "chaos.mjs's ten operators are fully wired for real (list-operators, seeded selection, corpus digest, dry-run) but runReal(harness) reports BLOCKED with a named reason when no live two-client harness is injected — composing tooling/verify-real-stack-desktop.mjs's and tooling/verify-real-stack-ios.mjs's full launch machinery into one process-shared harness is a substantial integration in its own right (comparable in scope to 06-05's dedicated cross-adapter plan) and was not re-derived here. This mirrors the project's own existing physical-device-lane precedent (O-51, 04-16's disclosed device BLOCKED state) rather than inventing a new disclosure shape."
  - "verify-trust-soak.mjs's --gate genuinely attempts a real oracle read against whatever KEEPLING_TRUST_SOAK_* environment variables are set, and correctly reports verdict=BLOCKED with a zero sample count when none are — exactly the verify block's own stated expectation for this environment ('with no accumulated window yet, blocked and non-zero is the expected and correct outcome at this point'), not a fixture or a workaround."
  - "applicationDigestSha256 and keeplingBuildDigest default to the literal string 'UNVERIFIED' when their environment variables are unset, following verify-release.mjs's own established offline-degradation vocabulary rather than inventing a new one."

patterns-established:
  - "A checker's negative write-guard (grep-based, run both as a static <verify> check and as an in-process guardAgainstShortcuts call before every real invocation) is the mechanical proof that 'the oracle can never write' survives future edits, not merely a review-time claim."

requirements-completed: [QUAL-04, QUAL-05]

coverage:
  - id: D1
    description: "The oracle reads three independent sources without write authority and without importing client code; eight invariants emit privacy-safe closed-vocabulary violations"
    requirement: "QUAL-04"
    verification:
      - kind: other
        ref: "node --check tooling/trust-lanes/oracle.mjs && node --check tooling/trust-lanes/invariants.mjs"
        status: pass
      - kind: other
        ref: "sed 's|//.*$||' tooling/trust-lanes/{oracle,invariants}.mjs | grep -ciE mutating-verb-pattern (0 matches, exit=1)"
        status: pass
      - kind: other
        ref: "grep -rnE non-read-HTTP-verb tooling/trust-lanes/ (0 matches, exit=1)"
        status: pass
      - kind: other
        ref: "grep -rnE client-package-import tooling/trust-lanes/ (0 matches, exit=1)"
        status: pass
      - kind: other
        ref: "./tooling/runtime-preflight.sh --exec -- sh -c 'mix ecto.migrate && mix ecto.rollback --step 1 && mix ecto.migrate' against keepling_test — round-trips twice cleanly"
        status: pass
      - kind: other
        ref: "psql as keepling_auditor: SELECT succeeds, INSERT/DELETE against tasks both refused with 'permission denied for table tasks'"
        status: pass
    human_judgment: false
  - id: D2
    description: "Ten chaos operators implemented, listable, and counted separately; the corpus reports its seed and digest; the census distinguishes thin days from clean ones; the blind spot is named in the docs"
    requirement: "QUAL-05"
    verification:
      - kind: other
        ref: "node tooling/trust-lanes/chaos.mjs --list-operators | wc -l == 10"
        status: pass
      - kind: other
        ref: "node tooling/trust-lanes/chaos.mjs --seed 1 --iterations 5 --dry-run (exit=0, operators_exercised=4)"
        status: pass
      - kind: other
        ref: "node tooling/trust-lanes/census.mjs --self-check (day1_labeled_thin=true, day2_labeled_thin=false)"
        status: pass
      - kind: other
        ref: "grep -c keystroke docs/testing/trust-soak.md == 2"
        status: pass
    human_judgment: false
  - id: D3
    description: "The gate is idempotent, blocks on interruption and overlap, refuses an oracle that cannot detect injected corruption, and states its own detection floor and blind spot"
    requirement: "QUAL-05"
    verification:
      - kind: other
        ref: "node tooling/verify-trust-soak.mjs --self-test (exercised=12, passed=true, all 8 invariant ids covered)"
        status: pass
      - kind: other
        ref: "manual: moved i8-activity-incomplete.json out of fixtures/, re-ran --self-test (exercised=11, passed=false, missing_invariant=I8, exit=1); restored, re-ran (exit=0) — the load-bearing removal check the plan's own <verification> names"
        status: pass
      - kind: other
        ref: "node tooling/verify-trust-soak.mjs --self-test --fixture interrupted-run (verdict=BLOCKED, exit=1); --fixture overlapping-run (verdict=BLOCKED, exit=1)"
        status: pass
      - kind: other
        ref: "node tooling/verify-trust-soak.mjs --gate (verdict=BLOCKED, cases=0, exit=1 — zero-sample invariants in this environment, the stated correct outcome)"
        status: pass
      - kind: other
        ref: "two consecutive --gate runs: diff of verdict=/cases= lines is empty"
        status: pass
      - kind: other
        ref: "node -e evidence-field-presence-check over all 10 named fields — fields=ok"
        status: pass
    human_judgment: true
    rationale: "PASS has never been observed in this sandbox because no real server/desktop/iOS trust-soak sources are configured here — BLOCKED with a zero sample count is the verify block's own explicitly stated correct outcome at this point, not a workaround. A human should confirm a real PASS or DISCLOSED-NOT-PROVEN verdict once KEEPLING_TRUST_SOAK_* environment variables point at a real running server, a real desktop store, and a real device-pulled iOS store — that first live accumulation run is 06-13's or a later dogfood cycle's concern, not this plan's."

duration: ~140min
completed: 2026-09-11
status: complete
---

# Phase KPL-06 Plan 12: The Trust Oracle — Measuring Defect Absence Summary

**A read-only reconciliation oracle (three independent reads, eight schema-level invariants, zero write authority, zero client-code imports) plus a ten-operator seeded chaos corpus, a thin-day usage census, and a self-verifying gate that refuses to pass an oracle it cannot prove detects injected corruption — turning "no unresolved data-loss/silent-overwrite/recovery-severity defects" from an assumption into a measurement with a stated detection floor and a named permanent blind spot.**

## Performance

- **Duration:** ~140 min
- **Started:** 2026-09-11T21:45:00Z
- **Completed:** 2026-09-11T23:59:00Z
- **Tasks:** 3
- **Files modified:** 19 (19 created, 0 modified)

## Accomplishments

- **Task 1:** Built `tooling/trust-lanes/oracle.mjs` (three independent reads: select-only Postgres role + read-only health endpoint for the server, `node:sqlite` read-only opens for desktop and iOS stores) and `tooling/trust-lanes/invariants.mjs` (I1-I8, pure predicates, closed violation vocabulary, keyed digests only). Provisioned `keepling_auditor` via a new migration, verified its SELECT-only privilege boundary directly against a real local Postgres database (write refused, read allowed), and verified the migration round-trips.
- **Task 2:** Built `tooling/trust-lanes/chaos.mjs` (ten seeded operators, corpus digest, `--list-operators`/`--dry-run` fully wired; `runReal` reports BLOCKED honestly without a live two-client harness) and `tooling/trust-lanes/census.mjs` (per-day exposure ledger labelling thin days). Wrote `docs/testing/trust-soak.md`, extending (never replacing) the existing dogfood contracts and naming the keystroke-to-commit blind spot by name.
- **Task 3:** Built `tooling/verify-trust-soak.mjs` with `--self-test` (12 synthetic corrupted fixtures, one to two per invariant, every one flagged; verified the load-bearing removal case: pulling a fixture drops the exercised count and fails the run) and `--gate` (five-digest-bound evidence artifact, three honest verdicts, run-conflict lock detecting interrupted/overlapping runs, idempotent across two consecutive runs).

## Task Commits

Each task was committed atomically:

1. **Task 1: Build the read-only oracle and its eight invariants** - `e3b7c13` (feat)
2. **Task 2: Build the chaos corpus and the usage census** - `6e9fbed` (feat)
3. **Task 3: Build the gate that refuses an oracle it cannot prove detects corruption** - `3929508` (feat)

**Plan metadata:** (this commit, following)

## Files Created/Modified

- `tooling/trust-lanes/oracle.mjs` — the read-only reconciliation oracle
- `tooling/trust-lanes/invariants.mjs` — I1-I8 predicates and the closed violation vocabulary
- `tooling/trust-lanes/chaos.mjs` — the ten-operator seeded chaos corpus
- `tooling/trust-lanes/census.mjs` — the per-day thin-day census
- `tooling/trust-lanes/fixtures/*.json` — 12 synthetic corrupted datasets, one per self-test case
- `tooling/verify-trust-soak.mjs` — the `--self-test`/`--gate` CLI and evidence artifact writer
- `apps/server/priv/repo/migrations/20260912000300_add_auditor_role.exs` — the `keepling_auditor` role
- `docs/testing/trust-soak.md` — the extended dogfood contract naming the blind spot

## Decisions Made

See `key-decisions` in frontmatter. In prose: the migration timestamp collision with 06-07 was caught by checking the directory listing before naming the file (as 06-06 already established as the pattern); the server-side entity digest never lets plaintext leave Postgres, computing `sha256()` there and reducing again with the run-local HMAC key in Node; the "server through its own read endpoints" leg is proven via the genuinely read-only `/health/ready` endpoint rather than a full bulk-read API that does not yet exist; the chaos corpus's real two-client wiring is disclosed as a scoping decision (comparable in size to 06-05's own dedicated cross-adapter integration plan) rather than attempted speculatively; and the gate's `--gate` output in this sandbox is honestly `BLOCKED, cases=0` because no real trust-soak sources are configured here — exactly the outcome the plan's own `<verify>` block names as correct at this point.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Migration filename collision with 06-07's already-landed migration**
- **Found during:** Task 1, before writing any code
- **Issue:** The plan's frontmatter and task text name `apps/server/priv/repo/migrations/20260912000200_add_auditor_role.exs`, but that exact timestamp is already used by 06-07's `add_command_receipts_issuing_grant.exs` (visible in the required-reading summary and confirmed by directory listing).
- **Fix:** Named the file `20260912000300_add_auditor_role.exs` instead, the next available slot after the existing `20260912000200` migration.
- **Files modified:** `apps/server/priv/repo/migrations/20260912000300_add_auditor_role.exs` (filename itself)
- **Verification:** `mix ecto.migrate && mix ecto.rollback --step 1 && mix ecto.migrate` round-trips cleanly twice against a real local `keepling_test` database.
- **Committed in:** `e3b7c13` (Task 1 commit)

**2. [Rule 1 - Bug] `GRANT CONNECT ON DATABASE current_database()` is invalid SQL — GRANT requires an identifier, not a function call**
- **Found during:** Task 1, first live migration attempt
- **Issue:** Postgres's `GRANT ... ON DATABASE` clause syntactically requires a database name literal; `current_database()` produced `ERROR 42601 syntax error at or near "("`.
- **Fix:** Wrapped the grant/revoke in a `DO $$ ... EXECUTE format(...) ... $$` block that resolves `current_database()` dynamically and interpolates it via `%I`, matching the pattern already used for the idempotent role creation in the same migration.
- **Files modified:** `apps/server/priv/repo/migrations/20260912000300_add_auditor_role.exs`
- **Verification:** Full up/down/up round-trip against a real local Postgres database, confirmed twice.
- **Committed in:** `e3b7c13` (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking migration-numbering correction, 1 bug in the first migration attempt's SQL). No scope creep beyond what correctly implementing this plan's own stated task required.

## Issues Encountered

- **The chaos corpus's live two-client wiring is not composed in this plan.** `chaos.mjs`'s ten operators, seeded selection, corpus digest, `--list-operators`, and `--dry-run` are fully implemented and pass every stated `<verify>` check; `runReal(harness)` reports `BLOCKED` with a named reason for each operator when no live two-client harness is injected. Composing `tooling/verify-real-stack-desktop.mjs`'s and `tooling/verify-real-stack-ios.mjs`'s full launch machinery into one process-shared harness that can actually kill/partition/skew/relaunch/switch-account/logout/hold-offline/conflict-edit/reconnect/bump-epoch two real clients at once is a substantial integration on the scale of 06-05's own dedicated cross-adapter plan, and was not re-derived speculatively here. This mirrors the project's own existing disclosed pattern for physical-device gaps (O-51, 04-16's device lane).
- **`--gate` has never produced a real PASS or DISCLOSED-NOT-PROVEN verdict in this sandbox**, because no `KEEPLING_TRUST_SOAK_*` environment variables point at a live server, desktop store, or iOS store here. `verdict=BLOCKED, cases=0` is exactly what the plan's own `<verify>` block for Task 3 states is the correct outcome "with no accumulated window yet." The first real accumulation run — pointing the gate at Jon's actual dogfood installation — is disclosed as open, not fixed here.

## User Setup Required

None for this plan's own scope. To accumulate real trust-soak evidence going forward, set `KEEPLING_TRUST_SOAK_AUDITOR_URL` (a `keepling_auditor`-role connection string against the real server database), `KEEPLING_TRUST_SOAK_SERVER_URL`, `KEEPLING_TRUST_SOAK_DESKTOP_STORE`, and `KEEPLING_TRUST_SOAK_IOS_STORE` (a path to a device-pulled SQLite file) before running `node tooling/verify-trust-soak.mjs --gate`. `KEEPLING_AUDITOR_PASSWORD` should be set to a real secret in any deployed environment; the migration's fallback (`keepling_auditor_dev_only`) is documented as dev/test-only.

## Next Phase Readiness

The oracle, invariants, chaos corpus, census, and gate are all built, self-tested, and structurally proven read-only. Plan 06-13's final verification can inventory `tooling/verify-trust-soak.mjs --self-test` (12/12 fixtures, 8/8 invariants) as passing evidence, and should treat the disclosed chaos-harness-wiring gap and the not-yet-observed real `--gate` PASS as open items for that plan's own scope determination — neither blocks this plan's own stated `<success_criteria>`, all of which are met.

No blockers introduced by this plan.

---
*Phase: KPL-06-portability-and-trust-release*
*Completed: 2026-09-11*

## Self-Check: PASSED

- All `key-files.created` exist on disk (verified with `[ -f ]`).
- All three task commits (`e3b7c13`, `6e9fbed`, `3929508`) exist in `git log --oneline --all`.
- Re-ran every task's `<verify>` block exactly as specified: `node --check` on all four `.mjs` files (pass); both negative-gate `sed`/`grep` checks (0 matches, exit=1 — passing per the plan's own stated convention); the migration round-trip via `runtime-preflight.sh` (pass, twice); `chaos.mjs --list-operators | wc -l` (10); `--seed 1 --iterations 5 --dry-run` (exit=0, 4 operators exercised); `census.mjs --self-check` (day1 thin, day2 clean); `grep -c keystroke docs/testing/trust-soak.md` (2); `verify-trust-soak.mjs --self-test` (12/12, exit=0); the fixture-removal load-bearing check (exercised drops to 11, exit=1, restored to exit=0); `--self-test --fixture interrupted-run`/`overlapping-run` (both BLOCKED, exit=1); `--gate` twice (identical verdict/cases lines, both BLOCKED/cases=0 as expected in this environment); the evidence-field presence check (all 10 fields present).
- Directly verified the auditor role's write refusal against a real local Postgres database (`INSERT`/`DELETE` both refused with `permission denied for table tasks`; `SELECT` succeeds).
