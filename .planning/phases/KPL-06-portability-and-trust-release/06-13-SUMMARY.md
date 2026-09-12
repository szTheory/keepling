---
phase: KPL-06-portability-and-trust-release
plan: 13
subsystem: testing
tags: [ci, github-actions, release-engineering, provenance, supply-chain, macos, evidence]

requires:
  - phase: KPL-06 plan 02
    provides: tooling/verify-release.mjs, the lane-inventory exactly-once assertion, the vanished-lane fixture
  - phase: KPL-06 plan 10
    provides: the signing/notarization path and the attestation + SBOM steps in desktop-promote
  - phase: KPL-06 plan 12
    provides: the trust-soak oracle and its evidence file
provides:
  - "A closed 39-lane inventory covering every evidence lane the project has, each with its authority and, where applicable, a named physical blocker"
  - "A retained, independently verifiable release manifest for one revision at .planning/releases/candidate-1/"
  - "A committed evidence bundle: both full CI logs, a per-lane evidence log, five artefact records"
  - "A requirement ledger in which every claim is either backed by a passing positive-count lane at this revision or disclosed with a blocker, a closing command and a real owner"
  - "Thirteen new WINDOWS.md rows (83-95), every one owned"
affects: [release, ship, supply-chain, ci-wiring, backlog]

actuals:
  tokens: 513000
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Absence records: an artefact that was NOT produced still gets a manifest entry, because an omitted artefact reads as satisfied"
    - "Source-tree artefact entry: source-only lanes bind to the tree they ran against rather than to a packaged application they never opened"
    - "Observed capability boundaries: requiresLiveAppearanceSession, recorded from measurement rather than prediction"

key-files:
  created:
    - .planning/releases/candidate-1/release-manifest.json
    - .planning/releases/candidate-1/artifacts/ (five artefact records)
    - .planning/releases/candidate-1/evidence/ (two CI logs, 21 per-lane logs, trust-soak evidence)
    - tooling/fixtures/release-manifest.not-produced-artifact.json
  modified:
    - tooling/release-lanes.json
    - tooling/verify-release.mjs
    - tooling/verify-macos-integration.mjs
    - .github/workflows/desktop.yml
    - .github/workflows/repository-integrity.yml
    - .planning/REQUIREMENTS.md
    - .planning/WINDOWS.md
    - KNOWN-LIMITATIONS.md

key-decisions:
  - "The manifest verifies NON-ZERO and that is the correct outcome. 28 of 39 lanes are BLOCKED, each with a stated reason. A pass would require a release claim this revision's evidence does not support."
  - "Row A14 was split out as its own local-attested lane with an observed physical blocker, rather than being recorded as a failing lane or quietly dropped."
  - "QUAL-03 was UNCHECKED: its second clause is now a tested absence rather than an untested one."
  - "The CI-built application is recorded as UNSIGNED. The signed, notarized, stapled build exists but is local, and nothing local may bind to locally built bytes."
  - "A fifth source-tree artefact entry was added beyond D-12's four, so that source-only lanes' bindings are true rather than merely well-formed."
  - "Every BLOCKED lane owned by KPL-06 was moved to backlog: the final phase of a milestone may not own a lane still blocked at its end."

patterns-established:
  - "Absence record + produced:false guard: a manifest must name what it did not build, and the verifier must refuse a lane that binds to it"
  - "Disclosure replacement: a stale disclosure is deleted and rewritten, never appended to, so the current state is the only state a reader sees"

requirements-completed: []

coverage:
  - id: D1
    description: "The lane inventory is closed over every lane the project has, each with authority and named physical blockers"
    verification:
      - kind: automated
        ref: "node -e '...release-lanes.json...' -> lanes=39; blocked=5 named physical blockers"
        status: pass
      - kind: automated
        ref: "node tooling/check-ci-contract.mjs"
        status: pass
    human_judgment: false
  - id: D2
    description: "One revision's artefacts and every lane's evidence are bound into a retained, independently verifiable manifest"
    requirement: "QUAL-03"
    verification:
      - kind: automated
        ref: "node -e '...exactly-once...' -> lanes=39 missing=0 dupes=0"
        status: pass
      - kind: automated
        ref: "node tooling/verify-release.mjs --manifest .planning/releases/candidate-1/release-manifest.json --offline | grep -c attestation=UNVERIFIED -> 5"
        status: pass
      - kind: automated
        ref: "git ls-files --error-unmatch .planning/releases/candidate-1/release-manifest.json"
        status: pass
      - kind: automated
        ref: "node tooling/verify-release.mjs --manifest ... (exits non-zero: 28 BLOCKED lanes, each with a stated reason)"
        status: fail
    human_judgment: false
    rationale: "The non-zero exit is the designed and correct outcome, not a regression; see Issues Encountered."
  - id: D3
    description: "Every requirement claim is disposed against evidence and nothing is unowned"
    requirement: "QUAL-02"
    verification:
      - kind: automated
        ref: "awk/grep unowned-open-row gate over .planning/WINDOWS.md -> 0"
        status: pass
      - kind: automated
        ref: "node tooling/generate-known-limitations.mjs && git diff --exit-code -- KNOWN-LIMITATIONS.md"
        status: pass
      - kind: automated
        ref: "./tooling/check-repository-integrity.sh -> 13 governance assertions"
        status: pass
      - kind: automated
        ref: "verify-release --offline | grep status=BLOCKED -> 28 lanes, all owner=backlog"
        status: pass
    human_judgment: false

duration: 95min
completed: 2026-09-12
status: complete
---

# Phase KPL-06 Plan 13: Release Evidence and Requirement Disposition Summary

**One revision's release claim is now checkable by a third party: 39 lanes bound to two real CI runs, 11 passing with positive case counts, 28 blocked with stated reasons and real owners, and five requirement claims re-decided against that evidence rather than against anyone's judgement.**

## Performance

- **Duration:** ~95 min
- **Tasks:** 2 of 2 in scope (Task 1 was already complete at `7352607`)
- **Files modified:** 39 across two commits

## Accomplishments

- **`.planning/releases/candidate-1/` exists, is committed, and verifies.** Every value in it is copied from the two real CI runs at `26628e1` (desktop.yml `34668212473`, repository-integrity.yml `34668212479`). Nothing in it was measured locally.
- **The manifest exits non-zero, which is the point.** 11 PASSED lanes each carry a positive case count and an artefact digest that resolves; 28 BLOCKED lanes each carry a reason and an owner. Online and offline runs produce identical lane verdicts.
- **Row A14 got an honest home.** It is now the `macos-integration-live-appearance` lane: `local-attested`, with a physical blocker recorded from measurement (FAIL on `macos-15`, PASS on a real logged-in session), emitting an explicit zero-case BLOCKED entry rather than vanishing.
- **QUAL-03 was unchecked** because its second clause now has a tested absence behind it rather than an untested one. Clause 1 is recorded as still proven, and re-proven at this revision by CI.
- **Nothing is unowned.** Thirteen ledger rows (83-95), all with a named blocker, a named closing command and an owner. All 28 BLOCKED lanes report `owner=backlog`.

## Task Commits

1. **Task 1: Close the lane inventory** - `7352607` (pre-existing, not this session)
2. **Task 2: Produce, verify and retain the release evidence** - `e1e4958` (feat)
3. **Task 3: Dispose every requirement claim against the evidence** - `ca9e73c` (docs)

## Manifest outcome

| | count |
|---|---|
| Lanes in inventory / in manifest | 39 / 39 (exactly once each) |
| PASSED with positive case count | 11 |
| BLOCKED with a stated reason | 28 |
| FAILED | 0 (the verifier's vocabulary has no FAILED; a lane that did not pass is BLOCKED with its reason) |
| Artefacts | 5 (1 produced, 3 absence records, 1 source-tree) |

**PASSED:** `ci-contract` (5), `repository-integrity` (3), `phase2-contracts-compatibility` (30), `phase2-privacy` (17), `opentofu-host-fixtures` (8), `desktop-units` (381), `desktop-package` (1), `desktop-packaged` (11), `desktop-e2e` (65), `macos-integration-no-grant` (9), `hosted-runner-tcc-report` (1).

## Requirement dispositions

| Requirement | Before | After | Basis |
|---|---|---|---|
| QUAL-02 | unchecked | unchecked, disclosure **replaced** | `all-required-passed` BLOCKED; rows 85, 86, 87 |
| QUAL-03 | checked | **unchecked** | `desktop-promote` skipped; clause 1 still proven; row 88 |
| QUAL-04 | checked | checked, narrowed | `desktop-units` 381 + `desktop-e2e` 65; contrast rows BLOCKED |
| QUAL-05 | checked | checked, tension named | `phase2-privacy` 17 cases; row 85 must be cited alongside |
| DATA-01 | unchecked | unchecked, disclosed | both export lanes BLOCKED; rows 83, 85 |
| DATA-03, OPS-02 | unchecked, **no disclosure at all** | unchecked, disclosed | D-40 carried forward unchanged; row 43 |
| SRV-02 | checked | unchanged, gap recorded | row 92 (see Issues Encountered) |

## Ledger rows added

All thirteen are `status: open`, `owner: BACKLOG`, and were hand-edited into **both** the rendered markdown table and the canonical fenced JSON block, because `gsd-tools windows` cannot write to this file (window 79).

| # | Row |
|---|---|
| 83 | `export-reader` is unwired — no committed job invokes it, yet DATA-01 and the public PRIVACY.md both lean on it |
| 84 | Row A14's physical blocker, measured both ways; not a product defect |
| 85 | `phase2-server` fails its post-run privacy scan: a hostile sentinel in the lane's diagnostic log, cause not isolated |
| 86 | hackney 1.25.0 carries four open advisories (one HIGH) and fails the server image build's audit |
| 87 | `Install asdf` is not idempotent against its own cache; two Phase 2 jobs die before any project code runs |
| 88 | QUAL-03's clause 2 has no passing lane at any revision; no promotion has ever run |
| 89 | The hosted-runner TCC report says `accessibility_trusted: true`, contradicting the full-grant lane's recorded blocker |
| 90 | Release evidence is committed but not attached as non-expiring release assets |
| 91 | CI has no signing identity, so every CI artefact at every revision is unsigned and unnotarized |
| 92 | `cross-adapter-phase` is unwired, so SRV-02 has no CI-authoritative evidence |
| 93 | `phase-1-desktop`, `mcp-gate-selftest`, `mcp-phase-non-model` are required on paper and run nowhere |
| 94 | The trust-soak measurement window has not accumulated; zero samples, verdict BLOCKED |
| 95 | Scheduled recovery drills cannot bind to a release revision (no `workflow_dispatch`) |

## Decisions Made

- **The manifest's non-zero verdict is the deliverable, not a defect to engineer around.** Every mechanism that could have produced a green verdict — counting a declared case count as a passing one, letting a local run stand in for a CI run, omitting a lane that could not run — was available and refused.
- **`macos-integration-no-grant` was narrowed to the three rows a hosted runner can physically drive**, in `--without-accessibility-trust`, in `ROW_REGISTRY` via a new `requiresLiveAppearanceSession` capability, and in the workflow step name. A14 still runs under `--all` and `--rows A14`; it was moved, not dropped.
- **A fifth `source-tree` artefact entry** was added so that `ci-contract`, `repository-integrity`, the Phase 2 lanes, `desktop-units` and `desktop-e2e` bind to the tree they actually ran against. The four-artefact schema would otherwise have forced them to name the packaged application's digest, claiming they tested bytes they never opened.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] The absence record was itself a loophole**
- **Found during:** Task 2
- **Issue:** A manifest must carry an entry for an artefact that was not produced, or the omission reads as satisfied. But such an entry carries a digest, and a digest is a binding target — a lane could name it and claim PASSED, thereby claiming to have tested bytes that were never built.
- **Fix:** `tooling/verify-release.mjs` now refuses a PASSED lane binding to an artefact with `produced: false`, naming the absence in the failure message.
- **Verification:** New fixture `tooling/fixtures/release-manifest.not-produced-artifact.json`, wired into the existing guard self-test in `repository-integrity.yml` alongside the vanished-lane and local-unattested fixtures. All three refuse.
- **Committed in:** `e1e4958`

**2. [Rule 2 - Missing critical functionality] DATA-03 and OPS-02 had no disclosure at all**
- **Found during:** Task 3
- **Issue:** Both were bare unchecked boxes with no comment. D-35 makes an unowned claim illegal, and the plan's own gate requires every unchecked requirement to name a blocker, a closing command and an owner.
- **Fix:** Both now carry the D-40 protected-outer-lane disclosure, carried forward unchanged, naming ledger row 43 and owner `BACKLOG/999.2`.
- **Committed in:** `ca9e73c`

**3. [Rule 2 - Missing critical functionality] KPL-06 owned 18 lanes that stay BLOCKED at its end**
- **Found during:** Task 3
- **Issue:** D-35's corollary forbids a verifier passing a phase while recording a BLOCKED lane whose owner is not another named, existing phase. KPL-06 is the final phase of this milestone, so its ownership of a still-blocked lane is the unowned pattern wearing a phase number.
- **Fix:** Every BLOCKED lane owned by `KPL-06` moved to `backlog`, with the rule stated in the inventory's own `$comment`, and each covered by a ledger row.
- **Verification:** All 28 BLOCKED lanes now report `owner=backlog`.
- **Committed in:** `ca9e73c`

---

**Total deviations:** 3 auto-fixed (3 x Rule 2). **Impact:** all three close honesty loopholes the plan's own prohibitions imply. No scope creep.

## Issues Encountered

**The macOS integration cached evidence could NOT be regenerated.** Two full `--all` runs against the current local signed artefact were aborted by the lane's own focus guard: `FOCUS_STOLEN by_pid=3761 by_bundle=dev.playstead.mac during=shift+tab` at row A4, then again at row A1. The lane correctly refuses to claim a row it could not drive. I did not kill the interfering process, because that is the owner's running session. Two things make this less costly than it looks: the local artefact is at `a25fa91`, not `26628e1`, so its evidence could not have supported any claim in this manifest anyway; and `macos-integration-full-grant` binds to locally built bytes and is therefore BLOCKED regardless. **To finish it:** quit `dev.playstead.mac` and run `node tooling/verify-macos-integration.mjs --all --manifest apps/desktop/out/keepling-package-manifest.json`.

**The release-asset half of retention is not done** (row 90). Attaching non-expiring assets requires pushing and creating a release; this revision has been neither pushed nor tagged, per instruction. The repository copy is committed and does not expire, so nothing is currently at risk.

**SRV-02 could not be disposed without an owner decision.** Its 06-05 evidence is real — all four cross-adapter legs passed and the run found and fixed a genuine cross-client contract bug — but it was a *local* run, and `cross-adapter-phase` is unwired in CI, so the lane is BLOCKED here. Unchecking it would reverse another plan's finding on a scope this plan was not given; leaving it checked without saying so would be the disclosure-on-a-checked-box pattern D-41 condemned. I left the box as 06-05 set it and filed row 92 so the gap is owned, and I am flagging it as a decision the owner should make explicitly.

**The hosted-runner TCC report contradicts a recorded physical blocker** (row 89). `accessibility_trusted: true` on `macos-15` is in direct tension with `macos-integration-full-grant`'s blocker text, which says a hosted runner cannot be given a non-interactive Accessibility grant. Neither has been falsified — the report describes the probe process at probe time, and no run has attempted the full-grant rows on a hosted runner. This was surfaced by the "report what TCC this runner actually grants" step doing exactly the job it was added to do. It is recorded, not reconciled by assertion.

## Adoption

Reported as an outcome, never as a gate, and given no evidence row (D-52). The only quantitative accompaniment permitted is the accumulated census, and at this revision `dailyUsageCensus` is empty — the trust-soak window has not accumulated (row 94). There is therefore nothing to report, and nothing is inferred from that absence. The single permitted path from informal feedback to evidence remains: feedback becomes a new invariant or a new chaos operator and the corpus is re-run. Feedback itself never becomes an evidence row.

## Known Stubs

None. No placeholder, empty-value or "not available" construct was introduced. The absence records are the opposite of stubs: each is an explicit, reasoned statement that a named artefact was not produced, and the verifier refuses to let one be used as a binding target.

## Self-Check: PASSED

- `.planning/releases/candidate-1/release-manifest.json` — FOUND, tracked
- `.planning/releases/candidate-1/artifacts/` (5 records) — FOUND, tracked
- `.planning/releases/candidate-1/evidence/` (2 CI logs, 21 lane logs, trust-soak) — FOUND, tracked
- `tooling/fixtures/release-manifest.not-produced-artifact.json` — FOUND, tracked
- Commit `e1e4958` — FOUND
- Commit `ca9e73c` — FOUND
