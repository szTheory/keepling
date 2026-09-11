---
phase: KPL-06-portability-and-trust-release
plan: 01
subsystem: planning-records
tags: [ledger-correction, requirements-traceability, ci-disclosure, D-41, D-35, D-40, D-53]

requires: []
provides:
  - QUAL-02 unchecked with a current, non-flattering CI disclosure
  - Every open WINDOWS.md row carries a real owner (phase number or BACKLOG)
  - O-22 (keyboard-nav data-loss bypass) tracked as WINDOWS.md #78
  - Phase 5's SRV-02 deferred disposition corrected from "Unowned" to Phase 6
  - Three stale WINDOWS.md/STATE.md entries corrected against source (O-21, O-45/O-51 closed; row 69 path fixed)
  - ROADMAP.md Phase 6 SC3/SC5 amended with dated, measurable wording (D-40, D-53)
  - REQUIREMENTS.md traceability table split to one row per requirement ID
affects: [KPL-06-02-tracer, KPL-06-05-cross-adapter, KPL-06-09-o22-fix, KPL-06-13-final-verification]

actuals:
  tokens: 46750
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Planning-ledger correction as its own gated plan before any feature work in a phase (D-54(1))"

key-files:
  created: []
  modified:
    - .planning/REQUIREMENTS.md
    - .planning/ROADMAP.md
    - .planning/WINDOWS.md
    - .planning/STATE.md
    - .planning/phases/KPL-05-safe-agent-access/05-VERIFICATION.md

key-decisions:
  - "QUAL-02 is unchecked rather than re-disclosed in place, because the new fact (CI runs and fails 17/17) is strictly worse than the old fact (CI never ran), and a still-checked box would misstate that direction."
  - "WINDOWS.md gained an owner column (last column, all 78 rows) rather than repurposing the existing phase column, so historical phase attribution and current ownership stay independently readable."
  - "The traceability table's automated gate treats any residual comma or '..' on an ID-prefixed line as evidence of grouping, so all carried-forward status prose was mechanically de-commafied (commas to semicolons/dashes) without changing any verdict."

patterns-established:
  - "Broken-windows-style planning documents (WINDOWS.md, REQUIREMENTS.md, ROADMAP.md) get an explicit, prohibition-gated correction plan (no strengthening allowed) before new phase work builds on them."

requirements-completed: []

coverage:
  - id: D1
    description: "QUAL-02 unchecked with a dated, factually-current disclosure naming Phase 6 plan 06-02 as CI-repair owner"
    requirement: "QUAL-02"
    verification:
      - kind: other
        ref: "grep -n '^- \\[ \\] \\*\\*QUAL-02\\*\\*' .planning/REQUIREMENTS.md"
        status: pass
    human_judgment: false
  - id: D2
    description: "Every open WINDOWS.md row names a real owner; O-22 filed as row 78 with owner Phase 6"
    verification:
      - kind: other
        ref: "awk/grep empty-owner gate over .planning/WINDOWS.md (Task 2 <verify>)"
        status: pass
      - kind: other
        ref: "grep -n 'O-22' .planning/WINDOWS.md"
        status: pass
    human_judgment: false
  - id: D3
    description: "REQUIREMENTS.md traceability table has one row per requirement ID, no grouped/ranged rows remain"
    verification:
      - kind: other
        ref: "grep -E '^\\| [A-Z]+-[0-9]+' .planning/REQUIREMENTS.md | grep -cE '\\.\\.|,'"
        status: pass
    human_judgment: false
  - id: D4
    description: "ROADMAP.md Phase 6 SC3/SC5 carry dated amendments matching D-40/D-53 wording"
    verification:
      - kind: other
        ref: "grep -c 'SC3 narrowing (2026-09-11)' / 'SC5 replacement (2026-09-11)' .planning/ROADMAP.md, plus SC5 literal-substring checks"
        status: pass
    human_judgment: false
  - id: D5
    description: "No claim in this plan was strengthened, re-checked, or had its disclosure softened"
    verification:
      - kind: other
        ref: "git diff on REQUIREMENTS.md shows zero '[ ]' -> '[x]' transitions across all three commits"
        status: pass
    human_judgment: false

duration: 24min
completed: 2026-09-11
status: complete
---

# Phase KPL-06 Plan 01: Correct the record before new Phase 6 work runs Summary

**Unchecked QUAL-02 with an honest CI-fails-17/17 disclosure, gave every open WINDOWS.md row a real owner (filing the O-22 keyboard-nav data-loss defect as row 78), and split REQUIREMENTS.md's grouped traceability rows to one row per ID — a pure ledger-correction plan with no feature work, exactly as D-54(1) requires before 06-02's tracer runs.**

## Performance

- **Duration:** 24 min
- **Started:** 2026-09-11T18:00:00Z (approx, reconstructed from git commit timestamps)
- **Completed:** 2026-09-11T18:24:00Z (approx)
- **Tasks:** 3
- **Files modified:** 5 (`.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/WINDOWS.md`, `.planning/STATE.md`, `.planning/phases/KPL-05-safe-agent-access/05-VERIFICATION.md`)

## Accomplishments

- QUAL-02 unchecked with a dated 2026-09-11 correction: the prior "CI has never executed" disclosure was itself now false in the project's favour — CI executes and fails 17/17 jobs — and the correction names Phase 6 plan 06-02 as the owner of the repair.
- Phase 5's `05-VERIFICATION.md` SRV-02 deferred disposition corrected from the D-35-invalid `"Unowned"` value to Phase 6, without reopening Phase 5's own (unchanged) verification outcome.
- `WINDOWS.md` gained a new trailing `owner` column across all 78 rows (77 existing + 1 new); every open row now names a phase number or `BACKLOG`. Filed row #78 for O-22 (keyboard command dispatch bypasses the unsaved-changes guard — a data-loss defect in the supported daily loop), owner Phase 6, referencing plan 06-09.
- Corrected three verified-stale WINDOWS.md/STATE.md entries against source: row 59 (O-45/O-51 undo reconciliation) closed with a citation to `DesktopApplication.ts:466-517`; row 69's cited driver path corrected from the nonexistent `test/packaged/` to the real `test/real-stack/real-stack-sync.spec.ts`; STATE.md's stale O-21 and O-51 blocker prose replaced with dated verified-closed notes.
- `ROADMAP.md` Phase 6 gained dated SC3 (D-40, hermetic host-replacement rehearsal as the gate) and SC5 (D-53, measured trust-soak criteria with explicit sample/duration/machine-hour floors) amendments.
- `REQUIREMENTS.md`'s traceability table expanded from 11 grouped/ranged rows to 49 single-ID rows, closing the structural cause of window #75 (per-ID matching finding no row and `phase complete` falling back to the wrong ROADMAP citation).

## Task Commits

Each task was committed atomically:

1. **Task 1: Uncheck QUAL-02 and reject the invalid Phase 5 disposition** - `29f9f85` (docs)
2. **Task 2: Make the open-item ledger complete and owned** - `06a3105` (docs)
3. **Task 3: Amend SC3 and SC5 and split the grouped traceability rows** - `c8558dd` (docs)

_This plan is documentation-only; every task used the `docs({phase}-{plan})` commit type per the plan's own scope (no code symbols created or renamed)._

## Files Created/Modified

- `.planning/REQUIREMENTS.md` — QUAL-02 unchecked with dated correction; traceability table split to one row per requirement ID (49 rows, up from 11 grouped/ranged rows).
- `.planning/ROADMAP.md` — Phase 6 gained dated SC3 narrowing and SC5 replacement amendment blocks.
- `.planning/WINDOWS.md` — added `owner` column to all rows; filed row #78 (O-22); resolved row #59 (fixed, source-cited); corrected row #69's driver path; updated frontmatter counts (open_count 15, fixed_count 14, total_count 78).
- `.planning/STATE.md` — replaced stale O-21 and O-51 blocker prose with dated verified-closed notes; O-22 blocker line annotated with its WINDOWS.md tracking reference.
- `.planning/phases/KPL-05-safe-agent-access/05-VERIFICATION.md` — SRV-02 deferred entry's `addressed_in` corrected from `"Unowned"` to `"Phase 6"`, with an explanatory dated comment.

## Decisions Made

- QUAL-02's checkbox goes to unchecked, not "checked with a new disclosure," because the new CI-fails fact is a regression relative to the old CI-never-ran fact, and leaving it checked would misrepresent that direction (the plan's own prohibition forbids softening a disclosure).
- `owner` was added as a new trailing column in WINDOWS.md rather than overloading the existing `phase` column, so a row's historical phase-of-origin and its current accountable owner remain independently legible (a row can be owned by a different phase than the one that recorded it, as with rows 43/63/69/78 here).
- All carried-forward WINDOWS.md/REQUIREMENTS.md status prose had commas mechanically converted to semicolons/dashes (and the two `IOS-01..03` prose mentions spelled out as "IOS-01 through IOS-03") to satisfy the traceability table's automated no-comma/no-range gate, without altering any verdict's substance.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] REQUIREMENTS.md's Phase 6 traceability row needed manual expansion beyond the automated range-regex**
- **Found during:** Task 3 (splitting grouped traceability rows)
- **Issue:** The row `DATA-01, QUAL-03..05 and cross-client release evidence | Phase 6 | Pending` didn't match the simple `PREFIX-NN..MM` range pattern because of its trailing descriptive text, so an automated expansion script skipped it.
- **Fix:** Manually expanded to `DATA-01`, `QUAL-03`, `QUAL-04`, `QUAL-05`, each on its own row, folding the "cross-client release evidence" context into each status cell as "Pending — final cross-client release evidence" rather than dropping it.
- **Files modified:** `.planning/REQUIREMENTS.md`
- **Verification:** `grep -E '^\| [A-Z]+-[0-9]+' .planning/REQUIREMENTS.md | grep -cE '\.\.|,'` returns 0.
- **Committed in:** `c8558dd` (Task 3 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking — mechanical edge case in an automated transform, not a substantive plan deviation).
**Impact on plan:** None on scope or claims; purely a completeness fix for the split-traceability transform.

## Issues Encountered

None beyond the deviation above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

The record is now honest: QUAL-02 is unchecked with a current disclosure, every open WINDOWS.md row has a real owner, O-22 is tracked, three stale entries are corrected against source, SC3/SC5 carry dated amendments, and the traceability table supports per-ID tooling matches. Plan 06-02 (the phase tracer: green CI, lossless artifact transport, release manifest) may now proceed per its `depends_on: [01]` — its own scope explicitly includes fixing the CI failures this plan just disclosed (owner assignment for QUAL-02's correction).

No blockers introduced by this plan. O-22 remains an open defect (now tracked, owner Phase 6, referenced to plan 06-09) and is not expected to be fixed here — this plan's scope was record-correction only, per its own prohibition against feature work.

---
*Phase: KPL-06-portability-and-trust-release*
*Completed: 2026-09-11*
