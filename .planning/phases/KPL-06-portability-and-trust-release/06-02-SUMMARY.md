---
phase: KPL-06-portability-and-trust-release
plan: 02
subsystem: ci-release-evidence
tags: [release-manifest, github-actions, asdf, postgresql, ditto, artifact-transport, D-09, D-10, D-11, D-13, D-15, T-06-02-01]

requires:
  - phase: KPL-06-01
    provides: an honest QUAL-02 disclosure naming this plan as CI-repair owner, and a corrected WINDOWS.md/REQUIREMENTS.md ledger
provides:
  - tooling/verify-release.mjs — offline-capable, third-party-checkable proof that a named revision's artifacts and lanes are the ones actually tested
  - tooling/release-lanes.json — the committed lane inventory a vanished lane is checked against
  - a first committed release-manifest.json under .planning/releases/candidate-0/
  - asdf plugin registration, a grep-based count_tests(), a runtime-relative D-06 window-bounds assertion, and a new ubuntu-24.04 phase2-linux job for the four D-10 root causes
  - the all-required-passed aggregator and check-ci-contract.mjs's if:/cache bans closing D-15(a)/(b)
  - a ditto-based lossless artifact transport (archiveDigestSha256) for T-06-02-01/D-11, with expansion+re-verify in both packaged-smoke consumers
affects: [KPL-06-05-cross-adapter, KPL-06-10-sign-notarize-attest, KPL-06-13-final-verification]

actuals:
  tokens: 11857
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Release-evidence spine: committed lane inventory + recomputed artifact digests + exact-set lane comparison, never trusting a manifest's own claim about itself"
    - "ditto -c -k --sequesterRsrc --keepParent for the transport archive; ditto -x -k plus a directory-digest re-verify at every consumer, so the binding never loosens even when the pipe changes"

key-files:
  created:
    - tooling/release-lanes.json
    - tooling/verify-release.mjs
    - tooling/fixtures/release-manifest.vanished-lane.json
    - .planning/releases/candidate-0/release-manifest.json
    - .planning/releases/candidate-0/artifact/PACKAGED-APPLICATION.md
  modified:
    - .github/workflows/repository-integrity.yml
    - .github/workflows/desktop.yml
    - tooling/runtime-preflight.sh
    - tooling/test-phase-2.sh
    - tooling/check-ci-contract.mjs
    - tooling/package-desktop.mjs
    - tooling/smoke-desktop-packaged.mjs
    - tooling/verify-macos-integration.mjs
    - tooling/verify-package-reproducibility.mjs
    - apps/desktop/test/e2e/lifecycle.spec.ts
    - .planning/REQUIREMENTS.md

key-decisions:
  - "verify-release.mjs's tracer artifact is a small committed placeholder (.planning/releases/candidate-0/artifact/), not the real multi-hundred-megabyte macOS .app, because the ci-contract job this tracer's lane runs in is ubuntu-24.04 and does not build the desktop package -- the tracer proves the WIRING end-to-end; the real macOS artifact digest is Task 3's and a later plan's concern."
  - "server/sync-property/backup-restore moved to a new ubuntu-24.04 job provisioning PostgreSQL via apt/PGDG, not a GitHub Actions services: container, because backup-restore drives pg_ctl/initdb/WAL/PITR directly against the data directory -- a black-box service container does not expose that control."
  - "check-ci-contract.mjs's if: ban is job-level-scoped (4-space indent) so it does not false-positive on step-level if: keys, and carries one explicit exception (all-required-passed's own if: always()), which is verified present rather than merely excluded."
  - "The packaged-artifact transport fix followed T-06-02-01's own instruction literally: fix the pipe (ditto archive), never the binding (applicationDigestSha256 stays exactly as strict). Both smoke-desktop-packaged.mjs and verify-macos-integration.mjs fall back to archive expansion only when the raw directory is absent, so the local dev flow (no CI transport) is unchanged."
  - "QUAL-02 was left UNCHECKED and QUAL-03 kept its existing checked-with-disclosure state (only appended an addendum), rather than mechanically running requirements.mark-complete, because this sandbox has no live GitHub Actions runner or verified network path to apt.postgresql.org -- claiming a passing CI run without ever seeing one would violate this project's own no-overclaim discipline (CLAUDE.md, D-41's exact prior lesson)."

patterns-established:
  - "A tracer task's artifact can be a deliberately small, honestly-labeled placeholder scoped to the ONE lane it wires, rather than forcing the full production artifact into the tracer slice."
  - "A shell script that must run identically on brew-provisioned macOS and apt-provisioned Linux selects its toolchain root via `uname -s`, keeping the exact-version assertion contract identical on both branches."

requirements-completed: []

coverage:
  - id: D1
    description: "node tooling/verify-release.mjs proves one revision's artifacts and lanes end-to-end, offline, and fails when a lane vanishes"
    requirement: "QUAL-02"
    verification:
      - kind: other
        ref: "node tooling/verify-release.mjs --manifest .planning/releases/candidate-0/release-manifest.json --offline"
        status: pass
      - kind: other
        ref: "node tooling/verify-release.mjs --manifest tooling/fixtures/release-manifest.vanished-lane.json --offline (exit=1, stderr names ci-contract)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Every CI lane can physically execute on its assigned runner; a skipped required job can no longer read as satisfied"
    requirement: "QUAL-02"
    verification:
      - kind: other
        ref: "sh -n tooling/runtime-preflight.sh; grep -c 'asdf plugin add' == 3"
        status: pass
      - kind: other
        ref: "grep -rnE count_tests uses no rg; ./tooling/test-phase-2.sh --list == 9 lanes"
        status: pass
      - kind: other
        ref: "node tooling/check-ci-contract.mjs (passes; also fails a fixture carrying an if: on a required job)"
        status: pass
    human_judgment: true
    rationale: "The new ubuntu-24.04 phase2-linux job's apt/PGDG PostgreSQL provisioning and the D-06 window-bounds fix in a real CI environment could not be exercised from this sandbox (no live GitHub Actions runner, no verified network reachability to apt.postgresql.org). Structural checks all pass; a human must confirm the next real push produces a green run."
  - id: D3
    description: "Packaged-artifact transport survives an artifact round trip with its measured digest intact"
    requirement: "QUAL-03"
    verification:
      - kind: other
        ref: "pnpm package:desktop && pnpm smoke:desktop:packaged (11/11 packaged specs pass)"
        status: pass
      - kind: other
        ref: "Manual simulation: raw .app removed, only manifest+ditto archive present -- smoke-desktop-packaged.mjs expanded and re-verified, 11/11 pass"
        status: pass
    human_judgment: true
    rationale: "The actual cross-runner GitHub Actions upload/download round trip (the real O-40 failure mode) has never executed in this sandbox (no live runner). The local simulation reproduces the same post-download shape (manifest + archive, no raw directory) and passed, but a human should confirm the next real desktop.yml run against a genuine actions/upload-artifact -> actions/download-artifact hop."

duration: unknown
completed: 2026-09-11
status: complete
---

# Phase KPL-06 Plan 02: Green CI, lossless artifact transport, and an end-to-end release manifest Summary

**A one-lane one-artifact release-manifest tracer (`tooling/verify-release.mjs`) proves the release-evidence spine end-to-end; the four D-10 CI root causes (asdf plugins, ripgrep, a display-geometry-fixed test, and macOS-stranded Elixir/PostgreSQL lanes) are fixed along with D-15's skipped-check aggregator hole; and the packaged desktop artifact now crosses the CI transport boundary as a `ditto`-archived single file with its `applicationDigestSha256` re-verified at every consumer, closing T-06-02-01 without loosening the binding that caught it.**

## Performance

- **Duration:** unknown (session-reconstructed; no wall-clock timer was started)
- **Tasks:** 3 (tracer + 2 expansion tasks)
- **Files modified:** 15 (5 created, 10 modified, excluding STATE.md/ROADMAP.md housekeeping)

## Accomplishments

- **Task 1 (tracer):** `tooling/release-lanes.json` (the committed lane inventory) and `tooling/verify-release.mjs` (recomputes every artifact digest, degrades attestation to `attestation=UNVERIFIED` when offline, does an exact-set lane comparison, and asserts every PASSED lane's `ranAgainstArtifactDigest`/`cases`) wire the `ci-contract` lane and one committed placeholder artifact through the full spine. A first `.planning/releases/candidate-0/release-manifest.json` is committed, the `ci-contract` job now writes and self-verifies a manifest, and `tooling/fixtures/release-manifest.vanished-lane.json` proves the gate fails in the stated direction.
- **Task 2:** Registered the `erlang`/`elixir`/`postgres` asdf plugins before `asdf install` (D-10 root cause 1); replaced `count_tests()`'s `rg` dependency with `grep -rnE` (root cause 2); rewrote the D-06 window-bounds E2E test to derive its target from `screen.getPrimaryDisplay().workArea` at runtime instead of a fixed literal (root cause 3, verified: 3/3 D-06 tests pass locally); moved the `server`/`sync-property`/`backup-restore` lanes to a new `ubuntu-24.04` `phase2-linux` job provisioning PostgreSQL via apt/PGDG (root cause 4), narrowing the macOS job to `contracts-compatibility`/`privacy`. Closed D-15(a)/(b): `check-ci-contract.mjs` now bans a job-level `if:` on any required job except the new `all-required-passed` aggregator (which must carry `if: always()`), and bans a restored cache in an artifact-producing job; the aggregator asserts every `needs.*.result` is `success`.
- **Task 3:** `tooling/package-desktop.mjs` produces a `ditto -c -k --sequesterRsrc --keepParent` archive of the copied application right after `applicationDigestSha256` is verified, recording `archiveDigestSha256` alongside it. `tooling/smoke-desktop-packaged.mjs` and `tooling/verify-macos-integration.mjs` fall back to expanding that archive with `ditto -x -k` (verifying `archiveDigestSha256` first) when the raw directory is absent locally — the post-CI-download shape. `desktop.yml`'s `desktop-package` job now stages only the manifest and the archive (a single regular file) rather than the raw `.app` directory tree; `desktop-packaged`/`desktop-macos-integration` rebase only `archivePath`. `verify-package-reproducibility.mjs`'s header now states its claim as one-machine, one-revision.

## Task Commits

Each task was committed atomically:

1. **Task 1: End-to-end "one lane, one artifact, one revision" release manifest** - `fd129a6` (feat)
2. **Task 2: Make every CI lane physically able to run, and close the skipped-counts-as-success hole** - `7287245` (fix)
3. **Task 3: Make the packaged-artifact transport lossless so a real digest survives it** - `149e3a6` (fix)

## Files Created/Modified

- `tooling/release-lanes.json` — committed one-entry lane inventory (`ci-contract`)
- `tooling/verify-release.mjs` — recomputes artifact digests, exact-set lane compare, attestation degrade, guarded/tracked-input self-check
- `tooling/fixtures/release-manifest.vanished-lane.json` — proves the vanished-lane gate fails in the stated direction
- `.planning/releases/candidate-0/release-manifest.json` — first committed manifest, D-13 retention
- `.planning/releases/candidate-0/artifact/PACKAGED-APPLICATION.md` — tracer's committed placeholder artifact, with a disclosed rationale for not being the real macOS `.app`
- `.github/workflows/repository-integrity.yml` — release-manifest write+verify step, new `phase2-linux` ubuntu job, narrowed `phase2-runtime` matrix, `all-required-passed` aggregator
- `.github/workflows/desktop.yml` — stages/uploads/downloads only the manifest + ditto archive; rebase steps rewrite only `archivePath`
- `tooling/runtime-preflight.sh` — asdf plugin registration; Linux branch selecting apt/PGDG PostgreSQL instead of brew
- `tooling/test-phase-2.sh` — `count_tests()` uses `grep -rnE`, not `rg`
- `tooling/check-ci-contract.mjs` — job-level `if:` ban (with the aggregator exception), artifact-producing-job cache ban
- `tooling/package-desktop.mjs` — `ditto` transport archive + `archiveDigestSha256`
- `tooling/smoke-desktop-packaged.mjs` — archive-expansion fallback + re-verify
- `tooling/verify-macos-integration.mjs` — same archive-expansion fallback (Rule 1 fix for a regression my Task 3 transport change would otherwise have introduced)
- `tooling/verify-package-reproducibility.mjs` — header states the one-machine, one-revision claim precisely
- `apps/desktop/test/e2e/lifecycle.spec.ts` — D-06 bounds-restore test target derived from the runner's own work area
- `.planning/REQUIREMENTS.md` — QUAL-02 partial-progress disclosure (left unchecked); QUAL-03 addendum documenting the local transport proof

## Decisions Made

See `key-decisions` in frontmatter. In prose: the tracer's artifact is an honestly-labeled placeholder scoped to the wiring it proves, not the real desktop `.app`; the Elixir/PostgreSQL lane relocation uses apt/PGDG rather than a GH Actions `services:` container because `backup-restore` needs direct `pg_ctl`/WAL/PITR control a service container does not expose; the transport fix followed the plan's own instruction to fix the pipe and never the binding; and QUAL-02/QUAL-03 were deliberately NOT mechanically marked complete because this sandbox cannot produce a real CI run as evidence.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `count_tests()`'s `grep` replacement needed `-r` to match `rg`'s recursive directory behavior**
- **Found during:** Task 2
- **Issue:** A first pass replaced `rg -n '...'` with `grep -nE '...'`, but plain `grep` does not recurse into directory arguments the way `rg` does by default; `count_tests apps/server/test` would have errored ("Is a directory") instead of counting.
- **Fix:** Used `grep -rnE` instead.
- **Files modified:** `tooling/test-phase-2.sh`
- **Verification:** `grep -rnE '^[[:space:]]*(test|property) "' apps/server/test | wc -l` returns 324; the plan's own no-`rg` regex check returns 0.
- **Committed in:** `7287245` (Task 2 commit)

**2. [Rule 1 - Regression] `verify-macos-integration.mjs` would have broken by Task 3's transport change**
- **Found during:** Task 3
- **Issue:** Changing `desktop.yml` to stop shipping the raw `.app` directory (only the manifest + `ditto` archive travel) would silently break `verify-macos-integration.mjs`, which is not in this task's declared `files_modified` list but directly consumes the same manifest shape and unconditionally required `copiedApplicationPath` to exist on disk.
- **Fix:** Applied the identical archive-expansion-and-re-verify fallback already built for `smoke-desktop-packaged.mjs`.
- **Files modified:** `tooling/verify-macos-integration.mjs`
- **Verification:** `node --check tooling/verify-macos-integration.mjs`; the fallback logic mirrors the tested `smoke-desktop-packaged.mjs` path exactly.
- **Committed in:** `149e3a6` (Task 3 commit)

**3. [Rule 4 - Protocol deviation, disclosed] Did not mechanically run `requirements.mark-complete` for QUAL-02/QUAL-03**
- **Found during:** close-out (state/requirements update step)
- **Issue:** The standard executor workflow calls `gsd_run query requirements.mark-complete` for every requirement ID in the plan's frontmatter. Doing so here would have flipped QUAL-02 to checked, but no real GitHub Actions run has ever executed the fixes in this plan — this sandbox has no live CI runner and no verified network path to the PGDG apt repository the new Linux lane depends on.
- **Fix:** Manually appended dated, honest disclosure addenda to `.planning/REQUIREMENTS.md` instead — QUAL-02 stays unchecked with a "PARTIAL PROGRESS" note naming exactly what is proven locally vs. unverified on a real runner; QUAL-03 (already checked-with-disclosure from Phase 3) got an addendum documenting the new local transport proof without changing its checked state's meaning.
- **Files modified:** `.planning/REQUIREMENTS.md`
- **Verification:** Manual read-through; `grep -c QUAL-02`/`QUAL-03` confirms no duplicate or malformed lines.
- **Committed in:** will be included in this plan's metadata commit.

---

**Total deviations:** 3 (2 auto-fixed bugs/regressions, 1 disclosed protocol deviation for honesty).
**Impact on plan:** All three are corrections in the direction of correctness or honesty; none expand scope beyond what Task 3's own transport change required, and the requirements deviation is exactly the kind of overclaim-refusal this project's CLAUDE.md and D-41's prior lesson both mandate.

## Issues Encountered

- **Unverifiable in this sandbox:** the new `phase2-linux` ubuntu-24.04 job's apt/PGDG PostgreSQL provisioning, and the real GitHub Actions `actions/upload-artifact`/`actions/download-artifact` round trip for the `ditto` archive, could not be exercised here — there is no live GitHub Actions runner and no confirmed network reachability to `apt.postgresql.org` from this environment. Every structural/local check in this plan's own `<verify>` blocks passes; the runtime behavior on a real push remains open until the next actual CI run. This is disclosed rather than assumed, per the project's own D-41/O-35 precedent for exactly this class of gap.

## User Setup Required

None - no external service configuration required. (The next real `git push` to `origin` will be the first live exercise of these fixes; no local action is needed to enable that.)

## Next Phase Readiness

The release-evidence spine (`verify-release.mjs`/`release-lanes.json`) is proven end-to-end for the one lane/artifact this tracer wired, and the artifact-transport binding is fixed at the pipe rather than loosened at the digest. Plan 06-03 and later plans in this phase may proceed. Before any release claim citing "green CI" is made, a real push to `origin` should be observed to confirm: (1) the `phase2-linux` job's apt/PGDG provisioning actually succeeds on a live `ubuntu-24.04` runner, (2) the D-06 window-bounds test passes against the runner's actual (not assumed) display geometry, and (3) the `ditto` archive genuinely survives a real `actions/upload-artifact`/`download-artifact` round trip (not just this sandbox's manual simulation of the same shape).

---
*Phase: KPL-06-portability-and-trust-release*
*Completed: 2026-09-11*

## Self-Check: PASSED
