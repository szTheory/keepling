---
phase: KPL-06-portability-and-trust-release
plan: 04
subsystem: data-portability
tags: [export, ndjson, json-schema, streaming, sql-stream, security-audit, D-01, D-02, D-03, D-04, D-05, D-06, T-06-04]

requires:
  - phase: KPL-06-01
    provides: an honest, correction-first record before new Phase 6 feature work builds on it
provides:
  - packages/contracts/schemas/export/ — the versioned export bundle format (manifest + 8 entity schemas), the checked-in IN/OUT classification.json, and FORMAT.md
  - a registered, non-destructive "export" verb in Keepling.Application.Ops, structurally unreachable from any agent scope
  - Keepling.Application.Export — storage-neutral bundle writer (manifest.json written last)
  - Keepling.Adapters.Postgres.Export — the streaming, transactionally-coherent Ops.Port implementation
  - "export_performed" added to the closed security_audit event vocabulary
affects: [KPL-06-08-completeness-lane, KPL-06-11-governance-lane]

actuals:
  tokens: 19093
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Ecto.Adapters.SQL.stream/4 with an explicit :max_rows chunk size, yielding one %Postgrex.Result{} per chunk — every consumer must Stream.flat_map the .rows out, never Stream.map the chunk directly"
    - "Write-order-as-correctness: every content file first, the manifest that vouches for them written last, so an interrupted writer leaves an unmanifested, non-validating directory rather than a falsely-complete one"
    - "Jason.OrderedObject-based recursive canonical (sorted-key) JSON encoding, rather than relying on Erlang's undocumented flat-map key order"

key-files:
  created:
    - packages/contracts/schemas/export/manifest.schema.json
    - packages/contracts/schemas/export/task.schema.json
    - packages/contracts/schemas/export/project.schema.json
    - packages/contracts/schemas/export/tag.schema.json
    - packages/contracts/schemas/export/task-activity.schema.json
    - packages/contracts/schemas/export/conflict.schema.json
    - packages/contracts/schemas/export/today-order.schema.json
    - packages/contracts/schemas/export/account-settings.schema.json
    - packages/contracts/schemas/export/access-inventory.schema.json
    - packages/contracts/schemas/export/classification.json
    - packages/contracts/schemas/export/FORMAT.md
    - apps/server/lib/keepling/application/export.ex
    - apps/server/lib/keepling/adapters/postgres/export.ex
    - apps/server/test/keepling/application/export_test.exs
    - apps/server/priv/repo/migrations/20260911000400_add_export_performed_audit_event.exs
  modified:
    - apps/server/lib/keepling/application/ops.ex
    - apps/server/lib/keepling/accounts/security_audit.ex
    - apps/server/config/config.exs
    - apps/server/config/test.exs

key-decisions:
  - "Task 1's checkpoint:decision auto-confirmed Option A (zip + NDJSON + standalone schema set + integer export_format_version) exactly as 06-CONTEXT.md D-02/D-03/D-04 specify, per yolo/auto-mode config — the plan text already recorded full rationale for the recommended, one-way-door option."
  - "Added \"export_performed\" to SecurityAudit's closed event vocabulary (plus its DB CHECK constraint migration) even though neither security_audit.ex nor a new migration was in Task 3's declared files_modified — the plan's own behavior spec (\"An export emits exactly one security_audit event\") and T-06-04-06's threat mitigation cannot be satisfied by any existing vocabulary member. Documented as a Rule 2 deviation."
  - "The Postgres.Export adapter resolves account_id internally (SELECT ... WHERE singleton_key = TRUE) rather than accepting it as CLI input, since the product is genuinely single-account; every entity query is still explicitly scoped and ordered by that resolved id, matching the plan's own instruction to scope even though the product is single-account."
  - "destination_dir defaults to System.tmp_dir!() when absent from input, since Keepling.Release/Mix.Tasks.Keepling.Ops CLI argument parsing was out of this task's declared files_modified — this mirrors the pre-existing, accepted gap where backup/restore's own OpsStore.execute/3 also returns :operation_adapter_unavailable rather than doing real work; the export path is proven correct end-to-end via Ops.run + the real Postgres.Export port in export_test.exs, not via the mix CLI wrapper."
  - "canonical_json/1 explicitly sorts map keys via Jason.OrderedObject rather than relying on Erlang's flat-map iteration order, so the byte-identical-two-exports guarantee does not depend on an unspecified runtime detail."

patterns-established:
  - "A tdd=\"true\" task on genuinely new machinery (Ecto.Adapters.SQL.stream/4, zero prior call sites) gets a real RED confirmation: the implementation was authored, then temporarily reverted via git checkout / file moves, the test suite run to confirm 5/6 failures, then restored for GREEN — rather than trusting chronological authoring order alone."

requirements-completed: [DATA-01]

coverage:
  - id: D1
    description: "The export bundle format (manifest + 8 entity schemas), IN/OUT classification, and FORMAT.md are published under packages/contracts/schemas/export/ and pass the contracts gate"
    requirement: "DATA-01"
    verification:
      - kind: other
        ref: "node -e '...parsed=10' schema-parse check (Task 2 <verify>)"
        status: pass
      - kind: other
        ref: "pnpm contracts:check"
        status: pass
    human_judgment: false
  - id: D2
    description: "export is a registered, non-destructive Ops verb; @destructive does not contain it"
    requirement: "DATA-01"
    verification:
      - kind: other
        ref: "sed -n '/@verbs/p;/@destructive/p' apps/server/lib/keepling/application/ops.ex"
        status: pass
      - kind: unit
        ref: "apps/server/test/keepling/application/ops/ (15 tests)"
        status: pass
    human_judgment: false
  - id: D3
    description: "The writer is transactionally coherent, deterministic, streaming, and owner-only; empty/adjacency/ordering/truncation behaviours proven by tests"
    requirement: "DATA-01"
    verification:
      - kind: unit
        ref: "apps/server/test/keepling/application/export_test.exs (6 tests: empty account, distinct-identical records, byte-identical re-export, interrupted-before-manifest, no agent export scope, richly-populated round trip + exactly-one security_audit event)"
        status: pass
      - kind: unit
        ref: "apps/server/test/keepling/application/ (100 tests, full application suite, no regression)"
        status: pass
    human_judgment: false
  - id: D4
    description: "export remains structurally unreachable from any agent scope; no MCP adapter routes to it"
    requirement: "DATA-01"
    verification:
      - kind: unit
        ref: "export_test.exs: \"the agent scope list contains no export scope\""
        status: pass
      - kind: other
        ref: "git grep -n 'Phoenix|KeeplingWeb|MCP' apps/server/lib/keepling/application/export.ex (no match)"
        status: pass
    human_judgment: false
  - id: D5
    description: "mix keepling.ops export writes a coherent bundle end-to-end via Ops.run + the real Postgres.Export port"
    verification:
      - kind: unit
        ref: "export_test.exs richly-populated test invokes Ops.run(\"export\", input, PostgresExport, %{}) directly"
        status: pass
    human_judgment: true
    rationale: "The literal mix keepling.ops export CLI invocation was not exercised — Mix.Tasks.Keepling.Ops / Keepling.Release argument parsing (which hardcodes OpsStore as the single port for every operation) was not in this task's declared files_modified, so the CLI cannot yet route the export operation to Keepling.Adapters.Postgres.Export. The application-layer path (Ops.run + the real port) is fully proven; a human should confirm whether CLI wiring is this phase's scope or a later plan's (see Next Phase Readiness)."

duration: ~90min
completed: 2026-09-11
status: complete
---

# Phase KPL-06 Plan 04: Publish the export format and build the non-destructive export verb Summary

**Published a versioned zip+NDJSON export bundle format (`manifest.schema.json` + 8 entity schemas + `classification.json` + `FORMAT.md`) under `packages/contracts/schemas/export/`, then built `Keepling.Application.Export`/`Keepling.Adapters.Postgres.Export` — a transactionally-coherent, `Ecto.Adapters.SQL.stream/4`-based writer registered as a new non-destructive `export` verb in `Keepling.Application.Ops`, proven by six tests covering the empty, adjacency, ordering, truncation, and agent-unreachability behaviours plus a fully-populated end-to-end round trip.**

## Performance

- **Duration:** ~90 min
- **Tasks:** 3 (1 checkpoint:decision auto-confirmed, 1 auto, 1 auto+tdd)
- **Files modified:** 19 (15 created, 4 modified)

## Accomplishments

- **Task 1 (checkpoint:decision):** Auto-confirmed Option A — zip + NDJSON + standalone `packages/contracts/schemas/export/` schema set + integer `export_format_version` starting at 1, decoupled from OpenAPI/protocol trains, additive-only, never ages out — exactly as 06-CONTEXT.md's D-02/D-03/D-04 specify. The plan's own text already carried the owner's full rationale; per yolo/auto-mode config, this was a re-confirmation of an already-recorded decision rather than a fresh choice.
- **Task 2:** Published `manifest.schema.json` (const `export_format_version: 1`, `feed_high_water_sequence`, `restore_epoch`, per-file `sha256`/`rowCount`), eight entity schemas (`task`, `project`, `tag`, `task-activity`, `conflict`, `today-order`, `account-settings`, `access-inventory`), the checked-in `classification.json` (per-table/per-column IN/OUT disposition matching D-01, feeding plan 06-08's completeness lane), and `FORMAT.md` (bundle layout, `export_format_version`-only compatibility contract, canonical ordering rule, encoding rules, and the explicit not-a-backup privacy statement). `pnpm contracts:check` passes unchanged (it validates unrelated OpenAPI/sync/compatibility/redaction contracts and does not touch the new export schema set).
- **Task 3 (TDD):** RED — `export_test.exs` written and confirmed failing (5/6 tests, `UndefinedFunctionError`/`invalid_operation`) by temporarily reverting the not-yet-committed implementation files and running the suite. GREEN — registered `export` in `Ops.@verbs` (never `@destructive`) with its own `decide/5` clause that surfaces `bundle_path`/`file_count` facts to the operator; built `Keepling.Application.Export` (storage-neutral, writes every `data/<entity>.ndjson` + `tasks.md` + `FORMAT.md` first, `manifest.json` LAST, then zips and `chmod 0600`s the bundle) and `Keepling.Adapters.Postgres.Export` (the `Ops.Port` implementation: one `Repo.transaction` at `REPEATABLE READ`, every entity streamed via `Ecto.Adapters.SQL.stream/4` with an explicit `:max_rows` chunk size — new machinery with zero prior call sites in `apps/server/lib`). Added the distinct `:export_query_timeout_ms` (permits `:infinity`, never reuses the mandatory-positive `task_view_query_timeout_ms` helper) and `:export_max_rows` config keys.

## Task Commits

Each task was committed atomically:

1. **Task 1: Confirm the published archive format and its version contract** — no commit (decision-only checkpoint; auto-confirmed the pre-answered D-02/D-03/D-04 decision, see Decisions Made)
2. **Task 2: Publish the export format contract and the IN/OUT classification** — `3ee9f64` (feat)
3. **Task 3, RED: add failing test for the export verb and streaming writer** — `971f09a` (test)
4. **Task 3, GREEN: add the non-destructive export verb and streaming coherent writer** — `0c51838` (feat)

**Plan metadata:** (this commit, following)

## Files Created/Modified

- `packages/contracts/schemas/export/manifest.schema.json` — the standalone, additive-only, never-ages-out archive format version contract
- `packages/contracts/schemas/export/{task,project,tag,task-activity,conflict,today-order,account-settings,access-inventory}.schema.json` — one NDJSON-line schema per entity
- `packages/contracts/schemas/export/classification.json` — checked-in per-table/per-column IN/OUT manifest (D-01), the input to plan 06-08's completeness lane
- `packages/contracts/schemas/export/FORMAT.md` — the bundle's own documentation for a reader with no Keepling internals knowledge
- `apps/server/lib/keepling/application/export.ex` — storage-neutral bundle writer; manifest-written-last correctness property
- `apps/server/lib/keepling/adapters/postgres/export.ex` — the streaming, transactional `Ops.Port` implementation
- `apps/server/lib/keepling/application/ops.ex` — registered `export` in `@verbs`; new `decide/5` clause and `export_facts/1` helper
- `apps/server/lib/keepling/accounts/security_audit.ex` — added `export_performed` to the closed event vocabulary
- `apps/server/priv/repo/migrations/20260911000400_add_export_performed_audit_event.exs` — the accompanying DB `CHECK` constraint expansion
- `apps/server/config/config.exs` / `apps/server/config/test.exs` — `:export_query_timeout_ms` (`:infinity` in dev/prod, `5_000` in test) and `:export_max_rows` (`500` / `50`)
- `apps/server/test/keepling/application/export_test.exs` — six tests proving the plan's `<behavior>` block

## Decisions Made

See `key-decisions` in frontmatter. In prose: Task 1's decision was a re-confirmation, not a fresh choice, since the plan text already carried the owner's D-02/D-03/D-04 answer; `export_performed` was added to the closed security-audit vocabulary despite `security_audit.ex` not being in Task 3's declared file list, because the plan's own acceptance criteria cannot be met without it (documented below as a deviation); `destination_dir` defaults to the system temp directory since CLI argument wiring through `Keepling.Release`/`Mix.Tasks.Keepling.Ops` was out of this task's declared scope; and the account is resolved internally by the adapter (never passed as CLI input) since the product is genuinely single-account, while every query still scopes and orders explicitly per the plan's own instruction.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added `export_performed` to the closed security-audit event vocabulary and its DB constraint**
- **Found during:** Task 3 (writing the export adapter's `security_audit` call)
- **Issue:** The plan's `<behavior>` block requires "An export emits exactly one `security_audit` event," and T-06-04-06's threat mitigation requires the same, but every existing member of `Keepling.Accounts.SecurityAudit`'s closed vocabulary is login/session/device-grant/MCP-specific — none fits "an export happened." Neither `apps/server/lib/keepling/accounts/security_audit.ex` nor a new migration was in Task 3's declared `files_modified`.
- **Fix:** Added `export_performed` to `@closed_event_types` in `security_audit.ex`, and a new migration (`20260911000400_add_export_performed_audit_event.exs`) expanding `account_security_audits_closed_type`'s `CHECK` constraint to include it, following the exact drop/recreate pattern every prior migration touching that constraint uses.
- **Files modified:** `apps/server/lib/keepling/accounts/security_audit.ex`, `apps/server/priv/repo/migrations/20260911000400_add_export_performed_audit_event.exs`
- **Verification:** `export_test.exs`'s richly-populated test asserts the `account_security_audits` row count for `event_type = 'export_performed'` increases by exactly 1 across the export call.
- **Committed in:** `0c51838` (Task 3 GREEN commit)

**2. [Rule 1 - Bug] `Ecto.Adapters.SQL.stream/4` yields one `%Postgrex.Result{}` per chunk, not one element per row**
- **Found during:** Task 3, first GREEN test run
- **Issue:** Every entity-stream helper originally did `SQL.stream(...) |> Stream.map(fn [col1, col2, ...] -> ... end)`, assuming each streamed element was already a single row list. In fact `SQL.stream/4` (bounded by `:max_rows`) yields one `%Postgrex.Result{rows: [...]}` struct per fetched chunk, causing an immediate `FunctionClauseError` the moment any row existed (or even for an empty result, a struct-shape mismatch).
- **Fix:** Added a `stream_rows/3` helper that wraps `SQL.stream/4` with `Stream.flat_map(fn %Postgrex.Result{rows: rows} -> rows end)`, and routed every entity helper through it.
- **Files modified:** `apps/server/lib/keepling/adapters/postgres/export.ex`
- **Verification:** All 6 `export_test.exs` tests pass after the fix; re-ran the full `apps/server/test/keepling/application/` (100 tests) and `apps/server/test/keepling/adapters/postgres/` (20 tests) suites with no regression.
- **Committed in:** `0c51838` (Task 3 GREEN commit)

---

**Total deviations:** 2 auto-fixed (1 missing-critical-functionality, 1 bug found during the task's own TDD GREEN cycle).
**Impact on plan:** Both are necessary for correctness; the security-audit vocabulary addition is the smallest change that satisfies the plan's own stated behavior and threat mitigation, and the stream-chunking fix is a genuine bug in the first implementation attempt, caught by the plan's own required test suite exactly as TDD is meant to catch it. No scope creep beyond what Task 3's own acceptance criteria required.

## Issues Encountered

- **CLI wiring gap (disclosed, not fixed):** `Mix.Tasks.Keepling.Ops` → `Keepling.Release.invoke/1` hardcodes `Keepling.Adapters.Postgres.OpsStore` as the single port for every operation (`Ops.run(parsed.operation, parsed.input, OpsStore, %{...})`). `OpsStore.execute/3` has no `"export"` clause and falls through to its default `{:error, :operation_adapter_unavailable}` — mirroring the pre-existing, already-accepted state of `backup`/`restore`'s own `OpsStore.execute/3`, which returns the same value for those operations too. `release.ex` and `ops_store.ex` were not in Task 3's declared `files_modified`, and routing a literal `mix keepling.ops export` invocation to the new `Postgres.Export` port would require changing one or both. This plan proves the export path fully and correctly at the application layer (`Ops.run/4` + the real `Postgres.Export` port, exercised end-to-end in `export_test.exs`'s richly-populated test) but does **not** make the literal CLI command functional yet. Flagged as `D5`'s `human_judgment: true` rationale above; a future plan (or an amendment to this one) should decide whether wiring `OpsStore`/`Release` to route `export` (and, symmetrically, `backup`/`restore`) to their real adapters is this phase's remaining scope or deferred.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

The export format is published and stable; the writer is proven transactionally coherent, deterministic, streaming, and owner-only at the application layer. Plan 06-08 (the four-part completeness/proof lane) can proceed against `classification.json` and the schema set. Before any user-facing claim that "you can run one documented operator command to export your data" is made, the CLI wiring gap above should be closed — either in a follow-up task of this plan's own scope or explicitly deferred to 06-08 alongside its golden-vector and independent-reader work.

No blockers introduced by this plan. `export` remains structurally unreachable from any agent scope (T-06-04-01, pinned by a regression test), and no MCP adapter routes to it.

---
*Phase: KPL-06-portability-and-trust-release*
*Completed: 2026-09-11*

## Self-Check: PASSED

- All key-files.created exist on disk (verified with `[ -f ]`).
- All three task commits (`3ee9f64`, `971f09a`, `0c51838`) exist in `git log --oneline --all`.
- Re-ran every task's `<verify>` block: schema-parse check, `pnpm contracts:check`, `mix test test/keepling/application/export_test.exs` (6 pass), `mix test test/keepling/application/ops/` (15 pass), `mix test test/keepling/application/` (100 pass), `@verbs`/`@destructive` grep, `task_view_query_timeout_ms` absence grep, and the plan-level inward-dependency `git grep` — all pass.
