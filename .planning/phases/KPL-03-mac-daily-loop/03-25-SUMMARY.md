---
phase: KPL-03-mac-daily-loop
plan: 25
subsystem: infra
tags: [electron-forge, packaging, reproducible-builds, node:crypto, asar, gate-lane]

# Dependency graph
requires:
  - phase: KPL-03-mac-daily-loop (03-01..03-24)
    provides: tooling/package-desktop.mjs, tooling/verify-desktop-phase.mjs, tooling/verify-macos-integration.mjs
provides:
  - A standalone reproducibility comparator (tooling/verify-package-reproducibility.mjs) with a self-proving self-test
  - A measured, documented finding that packaging at this revision is byte-reproducible across separate invocations (no non-determinism source needed removal)
  - --reuse-if-unchanged on tooling/package-desktop.mjs: re-hash-verified artifact reuse
  - A package-reproducible gate lane in tooling/verify-desktop-phase.mjs that re-measures reproducibility on every gate run
affects: [03-26, 03-27, phase-6-ci]

# Actuals (#2632)
actuals:
  tokens: 6870
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Digest-bound artifact reuse: never trust a manifest's recorded digest alone -- re-hash the artifact bytes on disk at reuse time and refuse loudly on any mismatch (mirrors the existing package-once -> promotion idiom, D-47)."
    - "Self-proving comparator: a self-test that mutates synthetic input by exactly one byte/mode-bit/symlink-target and asserts the comparator names each entry, run before the comparator is ever trusted on real input (same idiom as verify-macos-integration.mjs's SELF-TEST-EVIDENCE)."

key-files:
  created:
    - tooling/verify-package-reproducibility.mjs
  modified:
    - tooling/package-desktop.mjs
    - tooling/verify-desktop-phase.mjs
    - package.json

key-decisions:
  - "Measured (not assumed) that at HEAD e7b6789/e9cebb5, three separate `pnpm package:desktop` invocations produce one identical applicationDigestSha256 with zero differing entries across 1198 compared bundle entries -- run twice independently (6 total separate builds), never retried after a failure. No non-determinism source needed to be removed at this revision; whatever produced the historical O-40 divergence at fc3ac82 is not reproducible here today, and Task 2's comment in package-desktop.mjs states that rather than speculating on a cause."
  - "The package-reproducible gate lane runs --builds 2 (not the standalone command's 3) because the gate pays for every build on every invocation; the fixed 3-build measurement stays available as `pnpm verify:desktop:reproducible` for citation."
  - "--reuse-if-unchanged locates a prior manifest via the existing locator file, falling back to scanning sibling tmpdir manifest directories if the locator is missing or stale -- but either path is subjected to the identical re-hash-at-reuse-time checks, so a spoofed or stale locator can only ever fall through to a full rebuild, never a false reuse."

requirements-completed: [QUAL-03, MAC-05]

coverage:
  - id: D1
    description: "A reproducibility comparator that builds the desktop artifact N times in separate processes, names every differing bundle entry (descending into app.asar for the differing member), and proves by self-test that it can detect an injected content/mode/symlink difference"
    requirement: QUAL-03
    verification:
      - kind: other
        ref: "node tooling/verify-package-reproducibility.mjs --self-test"
        status: pass
      - kind: other
        ref: "node tooling/verify-package-reproducibility.mjs --builds 3"
        status: pass
    human_judgment: false
  - id: D2
    description: "Packaging is measured byte-reproducible across three separate invocations at one clean revision (zero differing entries, one digest)"
    requirement: MAC-05
    verification:
      - kind: other
        ref: "node tooling/verify-package-reproducibility.mjs --builds 3 (run twice independently, 6 total separate builds, same digest both times)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Deterministic packaging plus verified reuse of an already-built artifact whose tracked-input digest is unchanged, re-hashed at reuse time"
    requirement: QUAL-03
    verification:
      - kind: other
        ref: "node tooling/package-desktop.mjs --reuse-if-unchanged (run twice in a row: second run reused; artifact-deleted and byte-altered cases each refused by name and fell through to a full rebuild)"
        status: pass
    human_judgment: false
  - id: D4
    description: "The phase gate no longer manufactures a new application digest on every invocation, and a package-reproducible lane guards reproducibility permanently"
    requirement: MAC-05
    verification:
      - kind: other
        ref: "node tooling/verify-desktop-phase.mjs (run twice consecutively: lanes=11 failed=0 both times, macos-integration reused valid digest-bound evidence both times, same applicationDigestSha256 both times)"
        status: pass
    human_judgment: false

duration: 45min
completed: 2026-09-04
status: complete
---

# Phase KPL-03 Plan 25: Reproducible Desktop Packaging Summary

**Built a self-proving reproducibility comparator, measured that desktop packaging is already byte-identical across separate invocations at this revision, and added re-hash-verified artifact reuse so the phase gate stops manufacturing a new application digest on every run.**

## Performance

- **Duration:** 45 min
- **Started:** 2026-09-04T16:40:00Z
- **Completed:** 2026-09-04T17:25:00Z
- **Tasks:** 3
- **Files modified:** 4 (1 created, 3 modified)

## Accomplishments

- `tooling/verify-package-reproducibility.mjs`: builds the desktop artifact N times (default 3) in separate `pnpm package:desktop` processes, compares the resulting bundles entry-by-entry using the exact same traversal rule `hashDirectory` uses (sorted path + octal mode + symlink target + file content), and descends into differing `.asar` archives to name the differing member rather than just the archive. A `--self-test` mode proves on synthetic input (a mutated file byte, mode bit, and symlink target) that the comparator actually detects each class of difference by name — deliberately breaking the mode check makes `--self-test` fail, confirming the self-test is load-bearing, not decorative.
- Measured (not assumed) that at this revision, three separate packaging invocations produce one identical `applicationDigestSha256` across 1198 compared bundle entries with zero differences. Ran the fixed 3-build measurement twice independently (6 total separate builds) — both times zero differing entries, same digest (`8058ed13b8b4d96897e159b369e771e8ff654313765b82772ad931eff9e5a3d3`). Documented this finding, and the fact that no non-determinism source needed removal, in a comment block at the top of `tooling/package-desktop.mjs`.
- `--reuse-if-unchanged` on `tooling/package-desktop.mjs`: locates a prior manifest (via the existing `keepling-desktop-latest-manifest-<hash>.txt` locator, falling back to scanning sibling tmpdir manifest directories), and reuses it ONLY after re-hashing the artifact and executable bytes on disk right now and confirming they still match the manifest's recorded digests, plus confirming `inputDigestSha256`/`sourceRevision` are unchanged. Verified all five refusal paths independently: a second consecutive run reuses; deleting the artifact directory produces a named refusal and falls through to a full rebuild; altering one byte inside the executable produces a named digest-mismatch refusal and falls through to a full rebuild.
- `tooling/verify-desktop-phase.mjs`: `package-once` now forwards `--reuse-if-unchanged`; a new `package-reproducible` lane runs a cheaper fixed `--builds 2` reproducibility check on every gate invocation. Ran the full gate twice consecutively: `lanes=11 failed=0` both times, with `macos-integration` reusing valid digest-bound evidence both times and the packaged artifact reporting the identical `applicationDigestSha256` both times — the structural cause of VERIFICATION.md Gap 1 (the gate manufacturing a fresh digest on every invocation, so `macos-integration`'s evidence cache could never find a match) is closed.
- `tooling/verify-macos-integration.mjs` is byte-for-byte unchanged (`git diff --stat` empty) — the digest binding it enforces was not touched, weakened, or given an escape hatch.

## Task Commits

1. **Task 1: Build the artifact three times and name every byte that moves** - `a768b6b` (feat)
2. **Task 2: Eliminate every named non-determinism source until three builds agree** - `e7b6789` (docs — no code change was needed; see Deviations)
3. **Task 3: Stop the gate churning the digest, and gate reproducibility permanently** - `e9cebb5` (feat)

**Plan metadata:** committed alongside this SUMMARY.

## Files Created/Modified

- `tooling/verify-package-reproducibility.mjs` - New standalone comparator: N-build reproducibility measurement, `.asar`-descending diff reporting, `--self-test` proving detection capability on synthetic input.
- `tooling/package-desktop.mjs` - Added a comment block recording the O-40 measurement, and `--reuse-if-unchanged`: locate-a-prior-manifest + re-hash-at-reuse-time verified reuse.
- `tooling/verify-desktop-phase.mjs` - `package-once` now forwards `--reuse-if-unchanged`; added the `package-reproducible` lane (fixed `--builds 2`) immediately after it.
- `package.json` - Added `verify:desktop:reproducible` script.

## Decisions Made

- Measured reproducibility twice (fixed build count each time, never retried after a failure) rather than trusting a single run, given the historical O-40 divergence report; both measurements agreed, so packaging was NOT modified to remove any non-determinism source — there was none to find at this revision. This is recorded, not silently assumed, in a durable comment in `package-desktop.mjs` and via the permanent `package-reproducible` gate lane that re-measures on every future run.
- The gate's `package-reproducible` lane uses `--builds 2` rather than the standalone command's default `--builds 3`, because the gate pays for every build's cost (tens of seconds each) on every invocation; the fixed three-build measurement remains available as `pnpm verify:desktop:reproducible` for the number this project cites as proof.
- `--reuse-if-unchanged`'s manifest lookup checks both the fast-path locator file and a fallback scan of sibling tmpdir manifest directories, since the locator alone is a spoofable convenience (T-03-25-02) — but both paths funnel into the identical re-hash-at-reuse-time checks, so neither can produce a false reuse.

## Deviations from Plan

**1. [Rule 4 pattern, but resolved by measurement rather than architecture] Task 2 found nothing to fix**

- **Found during:** Task 2
- **Context:** Task 2's action text assumed `apps/desktop/out/reproducibility-report.json` (Task 1's output) would name specific differing entries to eliminate at their producer (vite build, asar packing, or ad-hoc signing). Task 1's actual measurement, run twice independently with a fixed build count each time, reported `differing_entries=0` both times — there was nothing named to fix.
- **Resolution:** Per the design guidance ("measure it" / "do not build a hypothesis on that asymmetry"), this is reported as the measured finding rather than papered over. `package-desktop.mjs` gained a comment block stating the two clean measurements, the digest they agreed on, and that the historical O-40 divergence (recorded at revision fc3ac82) does not reproduce at this revision — without speculating on why. `hashDirectory`'s traversal (path + mode + symlink target + full content) was not touched, and nothing was excluded from hashing. The `package-reproducible` gate lane (Task 3) makes this an ongoing, re-measured guarantee rather than a one-time claim.
- **Files modified:** `tooling/package-desktop.mjs` (comment only)
- **Verification:** `node tooling/verify-package-reproducibility.mjs --builds 3` exits 0 with `differing_entries=0` both before and after the comment was added (comment-only change, no traversal logic touched); `git diff -- tooling/package-desktop.mjs`'s `hashDirectory` function is unchanged from before Task 2.
- **Committed in:** `e7b6789`

---

**Total deviations:** 1 (a measured finding diverging from the plan's assumed starting point, not an auto-fix under Rules 1-3)
**Impact on plan:** None — Task 2's acceptance criteria (differing_entries=0, hashDirectory unchanged, comment block present, dirty-input refusal intact, smoke test passes) are all satisfied; the task's goal (three builds agree) was already true and is now durably documented and permanently gated.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- VERIFICATION.md Gap 1's packaging-non-reproducibility root cause is closed: `verify-desktop-phase.mjs` no longer manufactures a fresh application digest on every invocation, confirmed by two consecutive full-gate runs (`lanes=11 failed=0` both times, same digest both times, `macos-integration` reusing valid evidence both times).
- 03-26 (the other half of Gap 1 — diagnosing/fixing the `--all` recording run's cross-row interference) and 03-27 (Gap 2, desktop visual-snapshot evidence) remain and were explicitly out of scope for this plan.
- `tooling/verify-macos-integration.mjs` was not modified, confirmed by an empty `git diff --stat`.
- No new dependency was added anywhere in this plan (`git diff --stat -- package.json apps/desktop/package.json` shows only a new script entry, no dependency/devDependency change).

---
*Phase: KPL-03-mac-daily-loop*
*Completed: 2026-09-04*

## Self-Check: PASSED

- `tooling/verify-package-reproducibility.mjs` exists on disk: FOUND
- `.planning/phases/KPL-03-mac-daily-loop/03-25-SUMMARY.md` exists on disk: FOUND
- Commit `a768b6b` (Task 1) found in git log: FOUND
- Commit `e7b6789` (Task 2) found in git log: FOUND
- Commit `e9cebb5` (Task 3) found in git log: FOUND
- Re-ran plan-level `<verification>`: `--self-test` exits 0 (`failed=0`, 7 cases); `--builds 3` exits 0 (`differing_entries=0`, `compared_entries=1198`, one digest); `verify-desktop-phase.mjs` reports `package-reproducible status=PASS` with 599 cases, two consecutive runs same `applicationDigestSha256`; `git diff --stat -- tooling/verify-macos-integration.mjs` is empty.
