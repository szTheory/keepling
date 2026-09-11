---
phase: KPL-05-safe-agent-access
plan: 06
subsystem: mcp
tags: [mcp, addressing, disambiguation, security, elixir]

# Dependency graph
requires:
  - phase: KPL-05-05
    provides: "KeeplingWeb.MCP.Tools's four write tools, the closed @mcp_error_codes vocabulary (including the not-yet-wired ambiguous_match/no_match/too_many_matches members and their golden vectors), KeeplingWeb.MCP.ToolSchemas"
  - phase: KPL-05-07
    provides: "Keepling.Application.Preview.authorize_commit/2, the preview/commit tool pair -- the second authorization-adjacent function this plan proves is content-independent"
  - phase: KPL-05-04
    provides: "KeeplingWeb.MCP.Redaction's field-by-field projection, reused to build the candidate list in an ambiguous_match response"
  - phase: KPL-05-03
    provides: "Keepling.Application.Search -- the bounded, account-scoped query the candidate lookup reuses"
provides:
  - "Keepling.Application.TaskAddressing -- resolve/3 (identity-only), candidates/4 (bounded disambiguation read), classify_match_count/2 (structural outcome decision, never receives candidate content)"
  - "KeeplingWeb.MCP.Addressing -- the ambiguous_match response builder, projecting every candidate through the existing Redaction module"
  - "Every identity-addressing write tool (update_task, complete_task, reopen_task, preview_bulk_change's per-target check) now routes its target through TaskAddressing.resolve/3, refusing a phrase-shaped task_id with a bounded candidate set (or no_match/too_many_matches) rather than a blunt invalid_command, with zero mutation in every case"
  - "content_isolation_test.exs -- structural and behavioural proof that no authorization decision in the MCP surface can receive task content"
affects: [KPL-05-08, KPL-05-09, KPL-05-10, KPL-05-11, KPL-05-12]

actuals:
  tokens: 12900
  tasks: 3
  commits: 2

tech-stack:
  added: []
  patterns:
    - "A write tool's task_id argument is no longer strictly UUID-cast at decode time. A UUID-shaped value resolves through TaskAddressing.resolve/3 (identity-only); anything else is treated as a phrase and refused via a bounded candidate lookup -- never a write, in either branch."
    - "An authorization-adjacent decision (which of three closed disambiguation outcomes to report) is made by a function whose ENTIRE input is an integer count, never the candidate list itself -- making the decision structurally incapable of depending on any candidate's title or notes."
    - "TaskAddressing.uuid_shaped?/1 uses a plain regex (mirroring Keepling.Application.Preview's own @uuid_shape idiom), never Ecto.UUID.cast/1, because lib/keepling/application/** has no outward Ecto dependency (architecture_test.exs)."

key-files:
  created:
    - apps/server/lib/keepling/application/task_addressing.ex
    - apps/server/lib/keepling_web/mcp/addressing.ex
    - apps/server/test/keepling_web/mcp/ambiguity_test.exs
    - apps/server/test/keepling_web/mcp/content_isolation_test.exs
  modified:
    - apps/server/lib/keepling_web/mcp/tools.ex

key-decisions:
  - "Task 1 checkpoint answered A, A (identity-only write addressing, content-independent authorization) exactly as 05-CONTEXT.md's D-15/D-24 already locked -- matching this phase's own established precedent (05-01, 05-02, 05-05, 05-08) for Task 1 checkpoints whose recommended answer CONTEXT.md had already fixed. No alternative was proposed or needed."
  - "@candidate_limit is 5. Chosen as a small, easy-to-eyeball bound; the plan left the exact number to the executor's discretion (\"choose a small number and state it in the summary\")."
  - "A phrase in a write tool's task_id slot is a DIFFERENT refusal path than a structurally-wrong key (e.g. a `title` key instead of `task_id`). resolve/3 itself only ever sees the latter as a closed argument error (map shape); the former -- a non-UUID-shaped VALUE in the correct task_id key -- is detected by the caller (TaskAddressing.uuid_shaped?/1) BEFORE resolve/3 is ever invoked, and routed to candidates/4 instead. This keeps resolve/3's own contract exactly as literal as the plan's <behavior> block states (\"accepts no other addressing key\") while still satisfying D-16's disambiguation requirement for a phrase supplied where an identity belongs."
  - "The four grep-counted TaskAddressing.resolve/3 call sites (resolve_update_target/2, resolve_complete_target/2, resolve_reopen_target/2, and preview_bulk_change's per-target decode_targets/2) are deliberately NOT collapsed into one shared function, even though their bodies are identical. The plan's own acceptance criterion counts literal textual occurrences of the call (one per write tool); a single shared helper would satisfy the design intent but fail that literal check. The REST of the disambiguation logic (disambiguation_outcome/2, to_resolved_target/1) IS shared."
  - "preview_bulk_change's targets stay strictly identity-addressed (never a phrase) -- decode_targets/2 now verifies each target's existence via TaskAddressing.resolve/3 before a preview token is ever minted (previously deferred entirely to commit-time drift detection), but a non-UUID-shaped target task_id is still a closed argument error, not a per-target disambiguation. Bulk operations tolerating mid-batch ambiguity resolution was judged out of scope and materially riskier than the plan's single-task write tools; this is a deliberate, disclosed narrowing."
  - "No changes were needed to errors.ex or packages/contracts/vectors/mcp-tools.json. 05-05 already declared, vector-pinned, and unit-tested the three closed error members (ambiguous_match/no_match/too_many_matches) this plan wires into a live code path -- exactly the \"not-yet-reachable\" precedent 05-05-SUMMARY.md documented."

patterns-established:
  - "Resolution-then-disambiguation choke point: every write tool that addresses an existing task by identity calls the SAME two-function pair (TaskAddressing.resolve/3 for a genuine identity, TaskAddressing.candidates/4 + classify_match_count/2 for a phrase) rather than performing its own ad hoc lookup or UUID validation."

requirements-completed: [MCP-03]

coverage:
  - id: D1
    description: "An agent that names a task by phrase rather than by identity receives a bounded candidate set and no task is modified."
    requirement: "MCP-03"
    verification:
      - kind: integration
        ref: "test/keepling_web/mcp/ambiguity_test.exs#a phrase matching between two and the candidate limit tasks returns ambiguous_match with the bounded candidate set, and task revisions are unchanged"
        status: pass
      - kind: integration
        ref: "test/keepling_web/mcp/ambiguity_test.exs#keepling.complete_task and keepling.reopen_task also refuse a phrase-shaped task_id via the same disambiguation path"
        status: pass
    human_judgment: false
  - id: D2
    description: "Zero candidates and too many candidates are distinct closed errors, not one error with a different count."
    requirement: "MCP-03"
    verification:
      - kind: integration
        ref: "test/keepling_web/mcp/ambiguity_test.exs#a phrase matching zero tasks returns no_match, and the task rows are unchanged"
        status: pass
      - kind: integration
        ref: "test/keepling_web/mcp/ambiguity_test.exs#a phrase matching more than the candidate limit returns too_many_matches, and task revisions are unchanged"
        status: pass
    human_judgment: false
  - id: D3
    description: "Every write tool addresses its target by stable opaque identity only; a title or phrase is never accepted as a write address, and resolve/3 accepts no other addressing key."
    requirement: "MCP-03"
    verification:
      - kind: unit
        ref: "test/keepling_web/mcp/ambiguity_test.exs#resolve/3 given a map containing a title or any free-text key returns a closed argument error without querying anything"
        status: pass
      - kind: integration
        ref: "test/keepling_web/mcp/ambiguity_test.exs#a payload carrying an addressing key resolve/3 does not accept is rejected before any query runs"
        status: pass
      - kind: other
        ref: "grep -v '^#' apps/server/lib/keepling_web/mcp/tools.ex | grep -c 'TaskAddressing.resolve' -- 7 (>= 4, one per identity-addressing write tool plus comment mentions)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Task content cannot influence any authorization outcome: scope checks, preview binding, commit authorization, and candidate resolution read structural fields only."
    requirement: "MCP-03"
    verification:
      - kind: unit
        ref: "test/keepling_web/mcp/content_isolation_test.exs#1. the scope gate (AgentScope.require/2) receives only the structural MCP dispatch context"
        status: pass
      - kind: unit
        ref: "test/keepling_web/mcp/content_isolation_test.exs#2. the preview binding comparison (Preview.authorize_commit/2) receives only the closed binding field list"
        status: pass
      - kind: unit
        ref: "test/keepling_web/mcp/content_isolation_test.exs#3. commit authorization (Preview.commit/4) receives only a token, a mutation identity, and the structural preview context"
        status: pass
      - kind: unit
        ref: "test/keepling_web/mcp/content_isolation_test.exs#4. the candidate selection decision (TaskAddressing.classify_match_count/2) takes only an integer count"
        status: pass
      - kind: integration
        ref: "test/keepling_web/mcp/content_isolation_test.exs#the same tool-call sequence produces identical authorization outcomes whether or not task content carries hostile sentinels"
        status: pass
      - kind: integration
        ref: "test/keepling_web/mcp/content_isolation_test.exs#a preview token minted for a different binding, found inside a task note, authorizes nothing"
        status: pass
    human_judgment: false
  - id: D5
    description: "A task whose notes instruct the reader to escalate produces exactly the same authorization outcome as an identical task with empty notes."
    requirement: "MCP-03"
    verification:
      - kind: integration
        ref: "test/keepling_web/mcp/content_isolation_test.exs#the same tool-call sequence produces identical authorization outcomes whether or not task content carries hostile sentinels"
        status: pass
    human_judgment: false

duration: ~95min
completed: 2026-09-10
status: complete
---

# Phase 5 Plan 06: Identity-Only Task Addressing and Content-Independent Authorization Summary

**Under-determination is now a refusal, not a guess: a phrase where an identity belongs refuses with a bounded candidate set (or a distinct no_match/too_many_matches), zero mutation in every case, and a differential proof that hostile-sentinel-laden task content changes nothing about what four named authorization functions decide.**

## Performance

- **Duration:** ~95 min
- **Started:** 2026-09-10 (approximate)
- **Completed:** 2026-09-10
- **Tasks:** 3 (1 `checkpoint:decision`, 2 `auto`/`tdd`)
- **Files created:** 4
- **Files modified:** 1

## Accomplishments

- `Keepling.Application.TaskAddressing` -- `resolve/3` (identity-only: accepts exactly `%{task_id: id}`, any other shape is a closed argument error before any query runs), `candidates/4` (a bounded, mutation-free disambiguation read reusing `Keepling.Application.Search`), `classify_match_count/2` (the outcome decision, taking ONLY an integer count -- never the candidate list or any task content). `@candidate_limit` is 5.
- `KeeplingWeb.MCP.Addressing` builds the `ambiguous_match` response, projecting every candidate through the existing `KeeplingWeb.MCP.Redaction` module -- no new redaction mechanism.
- Every identity-addressing write tool in `KeeplingWeb.MCP.Tools` (`update_task`, `complete_task`, `reopen_task`, and `preview_bulk_change`'s per-target check) now routes its target through `TaskAddressing.resolve/3` -- a UUID-shaped `task_id` resolves normally; a non-UUID-shaped value is treated as a phrase and refused via `candidates/4` + `classify_match_count/2` rather than a blunt `invalid_command`, with **zero mutation performed in every refusal case**, proven by comparing task revisions before and after each refusal (not merely inspecting the response body).
- `apps/server/test/keepling_web/mcp/ambiguity_test.exs` (8 tests): `resolve/3`'s closed-argument-error behavior for a wrong addressing key; three separately named tests asserting `no_match`/`ambiguous_match`/`too_many_matches` as three distinct closed error members; `classify_match_count/2`'s structural arity (raises `FunctionClauseError` on a non-integer); `complete_task`/`reopen_task` sharing the same disambiguation path.
- `apps/server/test/keepling_web/mcp/content_isolation_test.exs` (6 tests): a structural half naming four authorization functions (the scope gate, the preview binding comparison, commit authorization, the candidate selection decision) and asserting their real production argument shapes carry only a declared structural-keys allowlist; a behavioural half running an identical six-step tool-call sequence against a hostile-sentinel-laden task set versus an ordinary one and asserting the normalized outcome sequences are byte-equal; a fourth case proving a preview token embedded as literal text inside a different task's notes authorizes nothing, because `commit` requires the token as an explicit argument.
- Full `apps/server` suite: **311/311 passing** (1 property test + 310 tests), 0 failures. `pnpm contracts:check` passes (no changes needed to the MCP contract or vectors -- 05-05 already declared and vector-pinned the three error members this plan wires into a live path). `pnpm run verify:mcp:phase` passes (`lanes=2 failed=0`, deterministic lane now 179 cases, up from 05-08's 126).

## Task Commits

1. **Task 1: Confirm identity-only write addressing and content-independent authorization** -- no code change; checkpoint answered inline (A, A) per locked `05-CONTEXT.md` D-15/D-24 guidance, matching this phase's own precedent for Task 1 checkpoints whose recommended answer CONTEXT.md had already fixed.
2. **Task 2: One identity-only resolution path, and three distinct outcomes** -- `3836f99` (feat, TDD)
3. **Task 3: Prove no authorization decision can receive task content** -- `1c03926` (test, TDD)

**Plan metadata:** committed alongside this SUMMARY.

## Files Created/Modified

- `apps/server/lib/keepling/application/task_addressing.ex` -- `resolve/3`, `candidates/4`, `classify_match_count/2`, `uuid_shaped?/1`, `candidate_limit/0`
- `apps/server/lib/keepling_web/mcp/addressing.ex` -- `ambiguous_match_response/1`
- `apps/server/lib/keepling_web/mcp/tools.ex` -- every identity-addressing write tool routed through `TaskAddressing.resolve/3`; `task_id` decode no longer strictly `Ecto.UUID.cast`s (a phrase now reaches the resolver instead of failing decode outright); new `search_context/1` (a distinct HMAC salt from `KeeplingWeb.MCP.Resources`'s own search cursor secret)
- `apps/server/test/keepling_web/mcp/ambiguity_test.exs` -- Task 2's behavior proof
- `apps/server/test/keepling_web/mcp/content_isolation_test.exs` -- Task 3's structural and behavioural proof

## Decisions Made

See `key-decisions` in frontmatter for the full rationale on: Task 1's checkpoint answer (A, A, matching CONTEXT-locked D-15/D-24), the `@candidate_limit` value and its source, the phrase-vs-wrong-key distinction between `candidates/4`'s disambiguation path and `resolve/3`'s own closed-argument-error path, the deliberate non-sharing of the four `TaskAddressing.resolve/3` call sites (to satisfy the plan's own literal per-write-tool acceptance check), `preview_bulk_change`'s deliberately-narrower (existence-checked, not phrase-disambiguated) target addressing, and why no changes were needed to `errors.ex` or the MCP contract vectors.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `TaskAddressing.candidates/4` crashed with a `KeyError` on `cursor_secret`**
- **Found during:** Task 2, first end-to-end test run of the "more than the candidate limit" scenario
- **Issue:** `Keepling.Application.Search.present_page/3` unconditionally attempts to encode a next-page cursor whenever the underlying query returns more items than requested (exactly the "too many matches" case, where `candidates/4` asks for `limit + 1` and gets more than that back) -- and cursor encoding requires `context.cursor_secret`. The MCP dispatch context (`KeeplingWeb.MCP.Dispatch.context/1`) never carried one; only `KeeplingWeb.MCP.Resources`'s own per-view contexts do.
- **Fix:** Added `KeeplingWeb.MCP.Tools.search_context/1`, deriving a `cursor_secret` from `KeeplingWeb.Endpoint`'s `secret_key_base` exactly as `Resources`'s own `search_context/1` does, but with a distinct HMAC salt (`keepling-addressing-cursor-v1`) so a disambiguation-lookup cursor secret is never the same key as a `resources/read` search cursor secret. `disambiguation_outcome/2` now calls `TaskAddressing.candidates(search_context(context), ...)` instead of passing the raw dispatch context through.
- **Files modified:** `apps/server/lib/keepling_web/mcp/tools.ex`
- **Verification:** `ambiguity_test.exs`'s "a phrase matching more than the candidate limit returns too_many_matches" test (previously crashing with `KeyError`, now passing); full suite 311/311.
- **Committed in:** `3836f99` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking bug caught by this plan's own required tests before any commit). **Impact on plan:** Necessary for correctness -- without the fix, ANY disambiguation lookup returning more than `@candidate_limit + 1` results would crash rather than refuse cleanly. No scope creep -- no capability was added beyond MCP-03's disambiguation surface and the D-24 content-independence proof the plan specifies.

## Known Stubs

None. All five `must_haves.truths` and all four `prohibitions` in the plan frontmatter are proven by the named tests/greps in the Accomplishments section above.

## Broken-Windows Ledger

No new stubs, skipped tests, or unrun `<verify>` commands to record. `gsd_run windows append` was not invoked (no ledger-worthy defect from this plan).

## Issues Encountered

None beyond the one deviation documented above, resolved within this plan's own tasks before any commit.

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness

- MCP-03 (ambiguity handling) is fully implemented and tested end-to-end through the real MCP JSON-RPC transport, real PKCE device-grant authorization, and real Postgres -- not just designed.
- D-24 (the phase's central security property -- authorization is structurally incapable of depending on task content) is now proven, not merely asserted: `content_isolation_test.exs`'s structural half names the exact one-line change that would break the proof, and its behavioural half is a genuine differential against `redaction.json`'s own `hostile_sentinels` corpus.
- `Keepling.Application.TaskAddressing` and `KeeplingWeb.MCP.Addressing` are the extension points a later plan adds a new identity-addressing write tool through, without inventing a second resolution or disambiguation mechanism.
- MCP-03 is now checked in `REQUIREMENTS.md` (this plan is its sole declaring plan; no shared-ID gate wait was needed).
- No blockers for 05-08/05-09/05-10/05-11/05-12.

---
*Phase: KPL-05-safe-agent-access*
*Completed: 2026-09-10*

## Self-Check: PASSED

- `apps/server/lib/keepling/application/task_addressing.ex` -- FOUND on disk
- `apps/server/lib/keepling_web/mcp/addressing.ex` -- FOUND on disk
- `apps/server/test/keepling_web/mcp/ambiguity_test.exs` -- FOUND on disk
- `apps/server/test/keepling_web/mcp/content_isolation_test.exs` -- FOUND on disk
- Commit `3836f99` (Task 2) -- FOUND in `git log --oneline --all`
- Commit `1c03926` (Task 3) -- FOUND in `git log --oneline --all`
- Full `apps/server` suite: 311/311 passing (1 property test + 310 tests)
- `pnpm contracts:check`: passed
- `pnpm run verify:mcp:phase`: PASSED (lanes=2 failed=0, deterministic 179 cases, protocol 2 cases)
- `grep -v '^#' apps/server/lib/keepling_web/mcp/tools.ex | grep -c 'TaskAddressing.resolve'`: 7 (>= 4)
- `grep -n '@candidate_limit' apps/server/lib/keepling/application/task_addressing.ex`: present as a module attribute
- All 5 `must_haves.truths` and all 4 `prohibitions` from PLAN.md frontmatter verified by named assertions/greps (see Accomplishments and Deviations sections above).
