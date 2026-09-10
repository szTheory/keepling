---
phase: KPL-05-safe-agent-access
plan: 05
subsystem: mcp
tags: [mcp, json-rpc, elixir, phoenix, openapi, json-schema, contracts]

# Dependency graph
requires:
  - phase: KPL-05-01
    provides: The `mcp` device-grant client kind, the D-06 scope vocabulary, the hand-rolled MCP JSON-RPC/Streamable HTTP endpoint at POST /mcp/v1, KeeplingWeb.MCP.Pipeline's bearer authentication, Keepling.Application.AgentScope, KeeplingWeb.MCP.Tools's capture_task tool and Errors module
provides:
  - "Six MCP tool component schemas (capture/update/complete/reopen + preview/commit bulk-change, the latter pair declared for 05-07) generated into packages/contracts/generated/mcp-tools.schema.json, closed (additionalProperties:false) and CI-gated by pnpm contracts:check"
  - "keepling.update_task, keepling.complete_task, keepling.reopen_task implemented in KeeplingWeb.MCP.Tools, dispatching through the same Commands.dispatch/3 every adapter uses, with idempotent mutation-identity replay and expected-revision conflict shapes identical to the HTTP path"
  - "KeeplingWeb.MCP.ToolSchemas -- compile-time schema load via @external_resource"
  - "KeeplingWeb.MCP.Errors's closed @mcp_error_codes vocabulary (14 members) with golden vectors in packages/contracts/vectors/mcp-tools.json"
affects: [KPL-05-06, KPL-05-07, KPL-05-08, KPL-05-09, KPL-05-10, KPL-05-11, KPL-05-12]

actuals:
  tokens: 25095
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Generated JSON Schema mcp-tools.schema.json is loaded at Elixir compile time via @external_resource, so a regenerated (but not yet source-edited) schema still forces a recompile -- the adapter and the contract cannot silently drift apart."
    - "Every MCP tool call runs the published-schema check (KeeplingWeb.MCP.ToolSchemas.validate/2) AND the independent Enum.sort(Map.keys(params)) == allowed_keys exact-key decode -- both always run, a disagreement between them is a test failure, not a runtime surprise."
    - "port.execute/3 returns every domain refusal (task not found, a revision conflict, ...) as {:ok, %{status:, body:}} -- the same shape the HTTP problem+json body renders -- so KeeplingWeb.MCP.Errors.from_problem/2 maps that one shape into the JSON-RPC error envelope for every adapter refusal, reusing the shared command store's own fixed literal strings rather than inventing a second error vocabulary."
    - "An MCP write with no retained draft (update_task) reads the task fresh immediately before dispatch to build a correct base_values for the shared narrow three-way merge, and checks expected_revision explicitly before dispatch -- but checks Commands.lookup_result/3 for an existing mutation receipt FIRST, so a legitimate replay of a since-advanced task is never mistaken for a stale write."

key-files:
  created:
    - tooling/generate-mcp-tool-schemas.mjs
    - packages/contracts/generated/mcp-tools.schema.json
    - packages/contracts/vectors/mcp-tools.json
    - apps/server/lib/keepling_web/mcp/tool_schemas.ex
    - apps/server/test/keepling_web/mcp/tools_test.exs
    - apps/server/test/keepling_web/mcp/errors_test.exs
  modified:
    - packages/contracts/openapi/keepling.yaml
    - packages/contracts/generated/keepling.ts
    - packages/contracts/vectors/manifest.json
    - tooling/check-contracts.mjs
    - package.json
    - apps/server/lib/keepling_web/mcp/tools.ex
    - apps/server/lib/keepling_web/mcp/errors.ex
    - apps/server/test/keepling_web/mcp/tracer_capture_test.exs

key-decisions:
  - "keepling.update_task's schema deliberately omits base_values (unlike the HTTP edit-task/assign-organizations/edit-task-dates endpoints), since an MCP round trip carries no retained draft to rebase against. The tool reads the task fresh immediately before dispatch and uses those current values as base_values, guaranteeing the shared narrow merge accepts a genuinely new value; expected_revision is checked explicitly against that same fresh read before dispatch, rendering the exact conflict body (code/title/detail/retryable/recovery_action/affected_fields/current_revision) the shared command store's own semantic_rejection/2 produces for an :edit_task/:edit_task_dates/:assign_task_organizations conflict on the HTTP path -- proven byte-identical to a real HTTP 409 in tools_test.exs."
  - "keepling.update_task determines which single field group (title/notes, project/tags, or the v1 temporal fields) a call touches and dispatches exactly one underlying domain command (:edit_task, :assign_task_organizations, or :edit_task_dates); a call spanning more than one group is rejected as invalid_command. Combining multiple field groups atomically in one MCP call was not required by the plan's <behavior> block and each underlying domain command already requires its own single matching base_values/fields key set."
  - "The closed @mcp_error_codes vocabulary is 14 members, not a single generic 'revision conflict' string: it reuses the shared command store's own four distinct conflict codes (task_edit_conflict, task_assignment_conflict, task_lifecycle_conflict, task_trash_conflict) verbatim, because Task 2's own acceptance criterion demands the MCP conflict body be byte-identical to the real HTTP problem body for the same situation -- collapsing them into one generic code would have broken that already-proven equality. 'Unknown tool' also became its own member (previously folded into invalid_command in 05-01's capture-only tools.ex)."
  - "Task 3's five not-yet-reachable-by-any-live-code-path members (ambiguous_match, no_match, too_many_matches, preview_stale, rate_limited -- MCP-03/05-07 concepts this plan does not implement) are still declared, vector-pinned, and directly tested by calling their builder function with a fixed vector-matched input, proving the FUNCTION is correct and stable ahead of the plan that wires it into a live scenario."
  - "tracer_capture_test.exs's 05-01-era 'tools/list returns exactly one tool' assertion was updated to find capture_task by name among the now-larger list, rather than destructuring a single-element list -- the assertion's own intent (capture_task's schema is closed and correct) is unchanged; only the now-stale 'exactly one tool exists' premise was corrected."

patterns-established:
  - "MCP tool schemas generated by reading the OpenAPI contract's YAML, resolving every $ref into a fully self-contained JSON Schema tree (no runtime resolver needed), and diffing a fresh generation against the committed output in --check mode -- mirrors generate-ios-client.mjs's scratch-then-diff idiom exactly."
  - "A generated schema loaded via @external_resource at Elixir compile time is the concrete mechanism that makes 'changing the wire contract without regenerating fails CI rather than at runtime' true: a stale committed schema fails pnpm contracts:check's --check diff; a regenerated-but-uncommitted schema forces an Elixir recompile that a CI diff also catches."

requirements-completed: []  # MCP-02 is declared by five plans in this phase (05-01, 05-02, 05-05, 05-10, 05-11); requirements.ready-ids confirmed 0/1 ready from this plan alone -- correctly deferred until the last declaring plan's SUMMARY exists.

coverage:
  - id: D1
    description: "Six MCP tool schemas (capture/update/complete/reopen + preview/commit, the latter pair declared not implemented) are generated from the OpenAPI contract, closed to additionalProperties:false, and a schema drift or missed regeneration fails pnpm contracts:check rather than surfacing at runtime."
    requirement: "MCP-02"
    verification:
      - kind: integration
        ref: "pnpm contracts:generate:mcp && git diff --exit-code -- packages/contracts/generated/mcp-tools.schema.json"
        status: pass
      - kind: integration
        ref: "pnpm contracts:check"
        status: pass
    human_judgment: false
  - id: D2
    description: "An agent holding tasks.write can update (title, notes, project/tags, or v1 temporal fields -- one group per call), complete, and reopen exactly one task through the closed tools, with a payload carrying an unlisted property rejected and zero writes performed."
    requirement: "MCP-02"
    verification:
      - kind: integration
        ref: "test/keepling_web/mcp/tools_test.exs#keepling.update_task edits title and returns the new revision"
        status: pass
      - kind: integration
        ref: "test/keepling_web/mcp/tools_test.exs#keepling.update_task edits project/tags via one call touching only that group"
        status: pass
      - kind: integration
        ref: "test/keepling_web/mcp/tools_test.exs#keepling.complete_task and keepling.reopen_task are idempotent domain transitions matching GTD-05"
        status: pass
      - kind: integration
        ref: "test/keepling_web/mcp/tools_test.exs#a payload carrying an unlisted property is rejected with a closed argument error and performs no write"
        status: pass
    human_judgment: false
  - id: D3
    description: "Every write except capture requires expected_revision; a stale expected_revision returns the same conflict shape (code/title/detail/retryable/recovery_action/affected_fields/current_revision) the real HTTP path returns for the identical situation, and replaying a mutation_id returns the original stored result without a second write."
    requirement: "MCP-02"
    verification:
      - kind: integration
        ref: "test/keepling_web/mcp/tools_test.exs#a payload omitting expected_revision on update, complete, or reopen is rejected; capture does not require one"
        status: pass
      - kind: integration
        ref: "test/keepling_web/mcp/tools_test.exs#a stale expected_revision returns the conflict shape byte-identical to the HTTP path for the same setup"
        status: pass
      - kind: integration
        ref: "test/keepling_web/mcp/tools_test.exs#replaying a mutation_id returns the original stored result and the task revision does not advance"
        status: pass
    human_judgment: false
  - id: D4
    description: "Every error a tool can return is drawn from a closed 14-member vocabulary (KeeplingWeb.MCP.Errors.mcp_error_codes/0), is byte-identical across two calls of the same failing tool, is pinned by a golden vector two-way, and an unexpected internal failure maps to the single infrastructure member with no stack trace or internal detail."
    requirement: "MCP-02"
    verification:
      - kind: integration
        ref: "test/keepling_web/mcp/errors_test.exs#every member of @mcp_error_codes has a vector entry, and every vector entry is a real member"
        status: pass
      - kind: integration
        ref: "test/keepling_web/mcp/errors_test.exs#every closed error member renders byte-for-byte identical to the vector"
        status: pass
      - kind: integration
        ref: "test/keepling_web/mcp/errors_test.exs#a call carrying an unknown property produces the same error body across two calls"
        status: pass
      - kind: integration
        ref: "test/keepling_web/mcp/errors_test.exs#an unexpected internal failure maps to the single infrastructure member and exposes no internal detail"
        status: pass
    human_judgment: false
  - id: D5
    description: "Every activity fact written through the MCP write tools names the agent grant as actor (type agent, principal authorized_grant, client_kind mcp)."
    requirement: "MCP-04"
    verification:
      - kind: integration
        ref: "test/keepling_web/mcp/tools_test.exs#every tool call is attributed in activity to the agent grant, with client_kind of mcp"
        status: pass
    human_judgment: false

duration: ~85min
completed: 2026-09-10
status: complete
---

# Phase 5 Plan 05: Closed MCP Tool Schemas, Write Surface, and Error Vocabulary Summary

**Four task-shaped MCP write tools (capture/update/complete/reopen) dispatch through the same
`Commands.dispatch/3` every adapter uses, gated by a contract-generated closed JSON Schema and a
14-member closed error vocabulary, with expected-revision conflicts proven byte-identical to the
real HTTP path.**

## Performance

- **Duration:** ~85 min
- **Started:** 2026-09-10T21:00:00Z (approximate)
- **Completed:** 2026-09-10T21:51:55Z
- **Tasks:** 3 (all `type="auto"`, two `tdd="true"`)
- **Files created:** 6
- **Files modified:** 8

## Accomplishments

- `packages/contracts/openapi/keepling.yaml` gained six MCP tool component schemas
  (`McpCaptureTaskParams`, `McpUpdateTaskParams`, `McpCompleteTaskParams`, `McpReopenTaskParams`,
  `McpPreviewBulkChangeParams`, `McpCommitBulkChangeParams`), each `additionalProperties: false`
  with an explicit `required` list, reusing existing field-type schemas
  (`MutationIdentity`, `TaskIdentity`, `Revision`, `NullableOrganizationIdentity`,
  `OrganizationIdentity`, `NullableCivilDate`) rather than restating shapes.
- `tooling/generate-mcp-tool-schemas.mjs` resolves every `$ref` into a fully self-contained JSON
  Schema per tool and writes `packages/contracts/generated/mcp-tools.schema.json`; `--check` mode
  regenerates into a scratch directory, diffs against the committed output, and cleans up in a
  `finally` block, mirroring `generate-ios-client.mjs`'s idiom exactly.
- `packages/contracts/vectors/mcp-tools.json` carries one accepted and multiple rejected payloads
  (unknown property, missing required property, wrong type, absent `expected_revision`) per tool,
  plus a 14-member `errors` map with the exact JSON-RPC rendering of every closed error code.
  Registered in `packages/contracts/vectors/manifest.json`; `tooling/check-contracts.mjs`'s
  hardcoded vector-file count was bumped from 13 to 14.
- `package.json` gained `contracts:generate:mcp`/`contracts:check:mcp`; `contracts:check` now
  runs both the existing OpenAPI/vector gate and the new MCP schema `--check`.
- `KeeplingWeb.MCP.ToolSchemas` loads the generated schema at Elixir compile time via
  `@external_resource` (forcing a recompile on any regeneration) and exposes `validate/2` --
  the PUBLISHED contract check, run before each tool's own independent exact-key decode (the
  ENFORCEMENT check); both always run.
- `keepling.update_task`, `keepling.complete_task`, `keepling.reopen_task` implemented in
  `KeeplingWeb.MCP.Tools`, all dispatching through the same `Commands.dispatch/3` every other
  adapter uses. `update_task` determines which single field group (title/notes, project/tags, or
  the v1 temporal fields) a call touches, reads the task fresh to build a correct `base_values`
  for the shared narrow three-way merge (no retained draft exists in an MCP round trip), checks
  `Commands.lookup_result/3` for an existing mutation receipt FIRST (so replay of a
  since-advanced task is never mistaken for a stale write), then checks `expected_revision`
  explicitly before dispatch.
- `KeeplingWeb.MCP.Errors` gained a closed 14-member `@mcp_error_codes` vocabulary
  (`insufficient_scope`, `invalid_command`, `unknown_tool`, `task_not_found`,
  `task_edit_conflict`, `task_assignment_conflict`, `task_lifecycle_conflict`,
  `task_trash_conflict`, `ambiguous_match`, `no_match`, `too_many_matches`, `preview_stale`,
  `rate_limited`, `service_unavailable`), every member fixed-literal (no interpolation --
  `grep -cE '#\{' errors.ex` is 0) and pinned to the golden vector two-way.
- 15 new integration tests across `tools_test.exs` (10) and `errors_test.exs` (4) plus 1 updated
  pre-existing tracer test; full `apps/server` suite: **229/229 passing, 0 failures.**
- `pnpm contracts:check` passes (14 vector files, 16 consumer entries proven executed);
  `pnpm contracts:generate && git diff --exit-code -- keepling.ts` passes (no drift).

## Task Commits

1. **Task 1: Generate closed MCP tool schemas from the contract, and gate the drift** --
   `204c9d2` (feat)
2. **Task 2: The four write tools, with idempotency and expected revisions unrelaxed** --
   `afe47e8` (test/feat, TDD)
3. **Task 3: A closed, fixed-string, model-correctable error vocabulary** -- `a21a40f` (feat, TDD)

**Plan metadata:** committed alongside this SUMMARY.

## Files Created/Modified

- `tooling/generate-mcp-tool-schemas.mjs` -- resolves the six MCP tool schemas' `$ref`s into a
  self-contained JSON document; `--check` scratch-then-diff idiom
- `packages/contracts/generated/mcp-tools.schema.json` -- the generated, committed output
- `packages/contracts/vectors/mcp-tools.json` -- tool payload vectors plus the 14-member error
  rendering vector
- `apps/server/lib/keepling_web/mcp/tool_schemas.ex` -- compile-time schema load, `validate/2`
- `apps/server/test/keepling_web/mcp/tools_test.exs` -- 10 tests for the four write tools
- `apps/server/test/keepling_web/mcp/errors_test.exs` -- 4 tests for the closed error vocabulary
- `packages/contracts/openapi/keepling.yaml`, `packages/contracts/generated/keepling.ts`,
  `packages/contracts/vectors/manifest.json`, `tooling/check-contracts.mjs`, `package.json` --
  contract/tooling extensions for the new tool schemas and vector file
- `apps/server/lib/keepling_web/mcp/tools.ex` -- `update_task`/`complete_task`/`reopen_task`
  added to the 05-01 `capture_task`-only module
- `apps/server/lib/keepling_web/mcp/errors.ex` -- the closed `@mcp_error_codes` vocabulary,
  `from_problem/2`, and per-member builder functions
- `apps/server/test/keepling_web/mcp/tracer_capture_test.exs` -- `tools/list` assertion updated
  for the now-larger tool set

## Decisions Made

See `key-decisions` in frontmatter for the full rationale on: `update_task`'s fresh-read
`base_values` construction and pre-dispatch `expected_revision` check (with `lookup_result/3`
replay-check ordered first), the single-field-group-per-call design, the 14-member (not
single-generic-code) error vocabulary reusing the shared command store's own conflict codes
verbatim, the five not-yet-reachable members still being declared/tested/vector-pinned ahead of
the plans that wire them in, and the `tracer_capture_test.exs` correction.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Extended `apps/server/lib/keepling_web/mcp/errors.ex` during Task 2**
- **Found during:** Task 2 implementation
- **Issue:** `update_task`'s pre-dispatch `expected_revision` conflict check and the `task_not_found`
  mapping needed a way to render a JSON-RPC error body from an arbitrary HTTP-problem-shaped map
  (the same shape every `port.execute/3` refusal already returns), but `errors.ex` (Task 3's own
  file) did not yet exist in its Task-3 form when Task 2 needed it.
- **Fix:** Added `from_problem/2` to `errors.ex` during Task 2 as a generic passthrough mapper;
  Task 3 (the very next task, same execution) then formalized the full closed `@mcp_error_codes`
  vocabulary around it without changing `from_problem/2`'s signature or behavior, so Task 2's
  already-passing tests kept passing unmodified through Task 3.
- **Files modified:** `apps/server/lib/keepling_web/mcp/errors.ex`
- **Verification:** `mix test test/keepling_web/mcp/` (30/30 passing after Task 2; still 30/30
  after Task 3's extension)
- **Committed in:** `afe47e8` (Task 2 commit)

**2. [Rule 1 - Bug] `tools/list` assertion in the 05-01 tracer test assumed a single tool**
- **Found during:** Task 2, full-suite run
- **Issue:** `tracer_capture_test.exs`'s "tools/list ... lists keepling.capture_task" test
  destructured `[tool] = response["result"]["tools"]`, correct only while `capture_task` was the
  only implemented tool. Task 2 makes `tools/list` advertise four tools, breaking the
  destructuring match.
- **Fix:** Changed the assertion to `Enum.find(tools, &(&1["name"] == "keepling.capture_task"))`
  and kept asserting that specific tool's schema is closed and correct -- the test's actual intent
  (capture_task's schema is right) is unchanged; only the stale "exactly one tool" premise was
  corrected.
- **Files modified:** `apps/server/test/keepling_web/mcp/tracer_capture_test.exs`
- **Verification:** Full `mix test` suite, 225/225 (then 229/229 after Task 3) passing
- **Committed in:** `afe47e8` (Task 2 commit)

**3. [Rule 1 - Bug] Naive `base_values = fields` design would have rejected every genuine edit**
- **Found during:** Task 2 implementation, before writing tests
- **Issue:** An initial design set `update_task`'s `base_values` equal to the requested `fields`
  (reasoning: "the agent's request is authoritative"). Reading `Keepling.Domain.Merge.three_way/4`
  directly showed this is backwards: the three-way merge only ACCEPTS a field when
  `canonical == base_values[field] OR canonical == requested`; with `base_values == fields`, that
  collapses to `canonical == requested`, meaning the merge would REJECT every genuine change and
  only "succeed" as a no-op.
- **Fix:** `update_task` reads the task fresh (`Commands.get_task/3`) immediately before dispatch
  and uses those CURRENT values as `base_values`, so the merge's `canonical == base_values` branch
  is trivially satisfied and a genuine field change is accepted. `expected_revision` is checked
  explicitly against that same fresh read.
- **Files modified:** `apps/server/lib/keepling_web/mcp/tools.ex`
- **Verification:** `test/keepling_web/mcp/tools_test.exs#keepling.update_task edits title and
  returns the new revision` (and the project/tags and dates-conflict tests)
- **Committed in:** `afe47e8` (Task 2 commit)

**4. [Rule 1 - Bug] `update_task`'s own pre-check broke mutation_id replay**
- **Found during:** Task 2, first test run of the replay test
- **Issue:** The pre-dispatch `expected_revision` check (deviation #3 above) ran unconditionally
  BEFORE any replay lookup. Replaying the exact same `update_task` call after it had already
  succeeded (advancing the task's revision) meant the replay's own (now-outdated)
  `expected_revision` no longer matched the fresh-read current revision, so the SECOND call was
  incorrectly treated as a stale write instead of a legitimate replay.
- **Fix:** `update_task` now checks `Commands.lookup_result/3` for an existing terminal receipt
  FIRST -- exactly as `CommandController.mutation/2` does -- and only runs the fresh-read/
  expected_revision gate when no existing receipt is found.
- **Files modified:** `apps/server/lib/keepling_web/mcp/tools.ex`
- **Verification:** `test/keepling_web/mcp/tools_test.exs#replaying a mutation_id returns the
  original stored result and the task revision does not advance`
- **Committed in:** `afe47e8` (Task 2 commit)

---

**Total deviations:** 4 auto-fixed (1 blocking file-ordering, 1 pre-existing-test bug, 2 design
bugs found and fixed before ever committing broken behavior). **Impact on plan:** All four were
necessary for correctness; the two design bugs (deviations 3 and 4) were caught by this plan's
own required tests before any commit, not discovered later. No scope creep -- no capability was
added beyond MCP-02's four verbs and the closed error vocabulary this plan specifies.

## Known Stubs

- `keepling.preview_bulk_change` and `keepling.commit_bulk_change` are declared in the generated
  tool schema (Task 1) but deliberately absent from `tools/list` and `call/2` -- plan 05-07
  implements them. Matches the plan's own explicit scope.
- Five error vocabulary members (`ambiguous_match`, `no_match`, `too_many_matches`,
  `preview_stale`, `rate_limited`) have no live code path producing them yet in this plan (no
  ambiguity resolution exists until MCP-03's plan; no preview/commit exists until 05-07; no
  rate-limiting plug is applied to the `:mcp` pipeline, matching 05-01's already-disclosed gap).
  Each is declared, vector-pinned, and directly unit-tested via its own builder function so the
  rendering is proven correct and stable ahead of the plan that wires it into a live scenario --
  not silently invented, and named here per the plan's own text ("Later plans add members").

## Broken-Windows Ledger

Recorded to `.planning/WINDOWS.md` (if the ledger is present in this project):

- stub: `apps/server/lib/keepling_web/mcp/tools.ex` -- `keepling.preview_bulk_change`/
  `keepling.commit_bulk_change` declared in the schema, not yet implemented (05-07's scope)
- stub: `apps/server/lib/keepling_web/mcp/errors.ex` -- five closed vocabulary members
  (`ambiguous_match`, `no_match`, `too_many_matches`, `preview_stale`, `rate_limited`) have no
  live production code path reaching them yet (MCP-03/05-07/rate-limiting scope, carried forward
  from 05-01's disclosed rate-limiting gap)

## Issues Encountered

None beyond the four deviations documented above, all resolved within this plan's own tasks
before any commit.

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness

- MCP-02's four task-shaped write verbs (capture/update/complete/reopen) are now fully
  implemented and tested end-to-end through the real MCP JSON-RPC transport, the real PKCE
  device-grant authorization, and real Postgres -- not just designed.
- `KeeplingWeb.MCP.ToolSchemas`, the closed `@mcp_error_codes` vocabulary, and the
  `Commands.get_task`-then-`dispatch` pattern `update_task` establishes are the extension points
  plan 05-07 (preview/commit) and MCP-03's ambiguity-handling plan build on without altering any
  module boundary this plan introduced.
- The five not-yet-reachable error members and the two not-yet-implemented tools are explicitly
  named as open items above, not silently absent -- 05-07 and the MCP-03 plan close them.
- MCP-02 remains unchecked in `REQUIREMENTS.md`, correctly: `requirements.ready-ids` confirmed
  0/1 ready from this plan alone (05-01, 05-02, 05-10, 05-11 also declare it and have not all
  produced a SUMMARY yet).

---
*Phase: KPL-05-safe-agent-access*
*Completed: 2026-09-10*

## Self-Check: PASSED

- `.planning/phases/KPL-05-safe-agent-access/05-05-SUMMARY.md` exists on disk.
- `packages/contracts/generated/mcp-tools.schema.json` exists on disk.
- `apps/server/lib/keepling_web/mcp/tool_schemas.ex` exists on disk.
- `apps/server/test/keepling_web/mcp/tools_test.exs` exists on disk.
- `apps/server/test/keepling_web/mcp/errors_test.exs` exists on disk.
- Commits `204c9d2`, `afe47e8`, `a21a40f` all found in `git log --oneline --all`.
- All 6 `must_haves.truths` and all 4 `prohibitions` from PLAN.md frontmatter verified by named
  assertions (see Accomplishments and Deviations sections above).
- Full `apps/server` suite: 229/229 passing. `pnpm contracts:check` passes.
