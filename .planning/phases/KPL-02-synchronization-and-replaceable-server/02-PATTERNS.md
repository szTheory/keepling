# Phase 2: Synchronization and Replaceable Server - Pattern Map

**Mapped:** 2026-09-01
**Files analyzed:** 31 new/modified file targets (some research paths are directory-level and are represented by planner-ready proposed filenames)
**Primary analog families found:** 5 / 5 application families; infrastructure is intentionally greenfield

All analog paths below were verified with `git ls-files`. No ignored runtime mirror path is used.

## Scope Interpretation

`02-CONTEXT.md` locks behavior but usually does not prescribe filenames. `02-RESEARCH.md` prescribes ownership directories and several planned test/tool names. The filenames below therefore use:

- exact existing files where Phase 2 modifies an established seam;
- exact planned names from the validation map where supplied;
- minimal proposed names inside research-prescribed directories where only a capability was named.

Final splitting is planner discretion, but moving a capability across these repository boundaries is not.

## File Classification

| New/Modified File | Role | Data Flow | Closest Tracked Analog | Match Quality |
|---|---|---|---|---|
| `packages/contracts/openapi/keepling.yaml` | config / wire contract | request-response | same file; existing `/api/v1` schemas | exact extension |
| `packages/contracts/generated/keepling.ts` | generated config | transform | same generated file via `tooling/check-contracts.mjs` | exact extension |
| `packages/contracts/schemas/sync-state-machine.schema.json` | config / schema | event-driven | `packages/contracts/vectors/conflicts.json` | format/contract match |
| `packages/contracts/vectors/sync.json` | test fixture | event-driven | `packages/contracts/vectors/conflicts.json` | exact role |
| `packages/contracts/vectors/account-lifecycle.json` | test fixture | event-driven | `packages/contracts/vectors/conflicts.json` | exact role |
| `packages/contracts/vectors/compatibility.json` | test fixture | request-response | `packages/contracts/vectors/conflicts.json` | role match |
| `packages/contracts/vectors/recovery.json` | test fixture | batch | `packages/contracts/vectors/conflicts.json` | role match |
| `packages/contracts/vectors/redaction.json` | test fixture | transform | `packages/contracts/vectors/conflicts.json` | role match |
| `apps/server/lib/keepling/application/sync.ex` | service / provider | event-driven | `apps/server/lib/keepling/application/task_views.ex` | exact layer, data-flow partial |
| `apps/server/lib/keepling/application/sync/reference_model.ex` | service / utility | event-driven | `apps/server/lib/keepling/application/task_views.ex` | layer match |
| `apps/server/lib/keepling/application/sync/cursor.ex` | utility | transform | `apps/server/lib/keepling/application/task_views.ex` | exact cursor role |
| `apps/server/lib/keepling/application/compatibility.ex` | service | request-response | `apps/server/lib/keepling/application/task_views.ex` | exact layer |
| `apps/server/lib/keepling/application/ops.ex` and `application/ops/*` | service / provider | request-response + batch | `apps/server/lib/keepling/accounts/security_audit.ex` | layer/health match |
| `apps/server/lib/keepling/adapters/postgres/command_store.ex` | service / persistence adapter | CRUD + event-driven | same file | exact extension |
| `apps/server/lib/keepling/adapters/postgres/sync_feed.ex` | service / persistence adapter | event-driven + batch | `apps/server/lib/keepling/adapters/postgres/command_store.ex` | exact layer |
| `apps/server/lib/keepling/adapters/postgres/ops_store.ex` | service / persistence adapter | CRUD | `apps/server/lib/keepling/adapters/postgres/command_store.ex` | exact layer |
| `apps/server/lib/keepling/accounts.ex`, `accounts/session.ex` and proposed grant modules | service / model | CRUD + request-response | existing account/session modules and `CommandStore` receipt pattern | role match |
| `apps/server/priv/repo/migrations/20260901*_add_sync_*.exs` | migration | CRUD | `20260830000100_create_core_task_command_tables.exs` | exact role |
| `apps/server/lib/keepling_web/controllers/sync_controller.ex` | controller | request-response | `task_view_controller.ex` | exact role and flow |
| `apps/server/lib/keepling_web/controllers/compatibility_controller.ex` | controller | request-response | `task_view_controller.ex` | exact role and flow |
| `apps/server/lib/keepling_web/controllers/health_controller.ex` | controller | request-response | `task_view_controller.ex` | exact role and flow |
| `apps/server/lib/keepling_web/router.ex` | route | request-response | same file | exact extension |
| `apps/server/lib/keepling/release.ex` | utility / release entry | batch | `lib/mix/tasks/keepling.recover.ex` | partial; release-safe boot is new |
| `apps/server/lib/mix/tasks/keepling.ops.ex` | utility / CLI adapter | request-response + batch | `lib/mix/tasks/keepling.recover.ex` | exact role |
| `apps/server/test/keepling/application/{sync,ops}/**/*_test.exs` | test | event-driven + batch | `telemetry_redaction_test.exs`, `concurrency_case.ex` | test conventions match |
| `apps/server/test/keepling/adapters/postgres/sync_feed_test.exs` | test | event-driven + CRUD | `test/keepling/adapters/postgres/conflict_test.exs` plus `concurrency_case.ex` | exact layer |
| `apps/server/test/keepling_web/health_test.exs` | test | request-response | existing controller/ConnCase tests | exact role |
| `apps/server/test/support/sync_scenario.ex` | test utility | event-driven | `test/support/concurrency_case.ex` | role match |
| `infra/images/server/Dockerfile`, `infra/compose/compose.yml`, `infra/caddy/Caddyfile` | config | batch / request-response | none in source tree | no analog |
| `infra/backup/*` and `infra/tofu/hetzner/*` | config / provider | file-I/O + batch | none in source tree | no analog |
| `tooling/keepling-ops`, `test-phase-2.sh`, and `verify-{contracts,image,restore,privacy,compose,deploy,host-replacement}.*` | utility / test | batch + file-I/O | `tooling/test-phase-1.sh` | exact orchestration role |
| `.github/workflows/repository-integrity.yml` or new Phase 2 workflow | config | event-driven + batch | same workflow and `tooling/test-phase-1.sh` lane vocabulary | role match |

## Pattern Assignments

### Application sync, cursor, compatibility, and reference-model modules

**Targets:** `application/sync.ex`, `application/sync/reference_model.ex`, `application/sync/cursor.ex`, `application/compatibility.ex`

**Analog:** `apps/server/lib/keepling/application/task_views.ex`

Use an inward application module with a nested persistence port. Pass the adapter explicitly; do not alias PostgreSQL, Phoenix, Ecto schema structs, or generated DTOs into application code.

**Port and orchestration pattern** (lines 15-29):

```elixir
defmodule Port do
  @moduledoc "Persistence port for task-list reads and scoped Today moves."

  @callback list_tasks(map(), atom(), map()) :: {:ok, map()} | {:error, atom()}
  @callback lookup_today_result(map(), String.t()) :: {:ok, map()} | {:error, atom()}
  @callback move_today(map(), map()) :: {:ok, map()} | {:error, atom()}
end

def list(view, context, options, port) when view in @views do
  with {:ok, limit} <- limit(options),
       {:ok, cursor} <- cursor(options, context, view),
       {:ok, page} <- port.list_tasks(context, view, %{cursor: cursor, limit: limit}) do
    {:ok, present_page(page, context, view)}
  end
end
```

For sync, define closed return variants for valid page/bootstrap and every reset condition. The controller maps those atoms; it does not decode cursor internals.

**Authenticated opaque cursor pattern** (lines 63-97):

```elixir
payload =
  :erlang.term_to_binary(
    {@cursor_version, context.account_id, view, keyset},
    [:deterministic]
  )

mac = :crypto.mac(:hmac, :sha256, context.cursor_secret, payload)
Base.url_encode64(payload <> mac, padding: false)
```

```elixir
with {:ok, signed} <- Base.url_decode64(cursor, padding: false),
     true <- byte_size(signed) > @cursor_mac_bytes,
     <<payload::binary-size(^payload_size), supplied_mac::binary-size(@cursor_mac_bytes)>> <- signed,
     expected_mac = :crypto.mac(:hmac, :sha256, context.cursor_secret, payload),
     true <- :crypto.hash_equals(supplied_mac, expected_mac),
     decoded <- :erlang.binary_to_term(payload, [:safe]) do
  # validate every closed namespace/protocol/epoch/position field
else
  _ -> {:error, :invalid_cursor}
end
```

Extend the payload to the locked sync namespace: server instance, account subject, sync epoch, protocol/codec train, sequence, and ordinal. Unlike the view analog, distinguish tampered, unsupported, expired, below-low-water, and namespace mismatch results where recovery differs. Never turn them into an empty page.

### Atomic command outcome and ordered feed persistence

**Targets:** modify `command_store.ex`; add `postgres/sync_feed.ex` and migrations.

**Analog:** `apps/server/lib/keepling/adapters/postgres/command_store.ex`

**Imports and behavior pattern** (lines 9-17):

```elixir
@behaviour Keepling.Application.Commands.Port

alias Ecto.Adapters.SQL
alias Keepling.Application.{Activity, Undo}
alias Keepling.Domain.{Organization, Task, TaskDates}
alias Keepling.Repo
```

**Transaction and infrastructure-error boundary** (lines 19-32):

```elixir
case Repo.transact(fn repo ->
       {:ok, first_delivery_or_replay(repo, command, context, fingerprint, decide)}
     end) do
  {:ok, result} -> result
  {:error, _reason} -> {:error, :infrastructure_failure}
end
rescue
  _error in [DBConnection.ConnectionError, Postgrex.Error] ->
    {:error, :infrastructure_failure}
end
```

**Idempotent receipt arbitration** (lines 373-391):

```elixir
INSERT INTO command_receipts (
  account_id, mutation_id, fingerprint, terminal, inserted_at, updated_at
)
VALUES ($1, $2, $3, FALSE, $4, $4)
ON CONFLICT (account_id, mutation_id) DO NOTHING
RETURNING mutation_id
```

The first-delivery branch at lines 420-458 performs semantic decision/persistence and only then finalizes the receipt. Add canonical resource-key sorting and lock acquisition before mutation; reserve the account feed clock and append deterministic `(sequence, ordinal)` envelopes before `finalize_receipt/4`. Replay must not append a second feed entry.

**Persisted conflict pattern** (lines 680-725):

```elixir
%{num_rows: 1} =
  SQL.query!(repo, """
  INSERT INTO persisted_conflicts (
    account_id, id, task_id, original_mutation_id, command_type,
    expected_revision, latest_revision, affected_fields, base_values,
    requested_values, current_values, inserted_at, updated_at
  )
  VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb, $10::jsonb,
          $11::jsonb, $12, $12)
  """, values)
```

Emit the conflict envelope in this same transaction. Keep the persisted conflict separate from the task snapshot and receipt representations.

**Terminal exact-result and fingerprint replay** (lines 1729-1771):

```elixir
UPDATE command_receipts
SET response_status = $3, response = $4::jsonb, terminal = TRUE, updated_at = NOW()
WHERE account_id = $1 AND mutation_id = $2
```

```elixir
if Plug.Crypto.secure_compare(stored_fingerprint, fingerprint) do
  {:ok, stored_result}
else
  {:ok, problem(409, "mutation_identity_reused", ...)}
end
```

Do not advance global feed coverage from an acknowledgement. Acknowledgement snapshot freshness and pulled cursor coverage remain separate fields.

### Database migrations for clocks, envelopes, epochs, grants, and restore proof

**Target:** one or more additive `20260901*_*.exs` migrations.

**Analog:** `apps/server/priv/repo/migrations/20260830000100_create_core_task_command_tables.exs`

**Compound account-scoped identity** (lines 29-44, 46-63):

```elixir
create table(:tasks, primary_key: false) do
  add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all),
    primary_key: true
  add :id, :uuid, primary_key: true
  add :revision, :bigint, null: false
end

create constraint(:tasks, :tasks_revision_positive, check: "revision >= 1")
```

Use compound account keys for clock/feed/grant state, explicit positive/nonnegative checks, and unique `(account_id, sequence, ordinal)` feed positions. Do not use a database sequence as the durable feed order.

**Cross-table invariant pattern** (lines 88-107):

```elixir
execute(
  """
  ALTER TABLE task_activities
  ADD CONSTRAINT task_activities_receipt_fk
  FOREIGN KEY (account_id, mutation_id)
  REFERENCES command_receipts (account_id, mutation_id)
  ON DELETE CASCADE
  """,
  "ALTER TABLE task_activities DROP CONSTRAINT task_activities_receipt_fk"
)
```

Prefer database-enforced account scoping and receipt/feed linkage. Follow expand-first compatibility: new nullable/defaulted structures, compatible code/backfill/validation, read switch, then later contraction after the support window.

### Sync, compatibility, and health HTTP adapters

**Targets:** `sync_controller.ex`, `compatibility_controller.ex`, `health_controller.ex`, and router changes.

**Analog:** `apps/server/lib/keepling_web/controllers/task_view_controller.ex`

**Thin adapter pattern** (lines 41-51):

```elixir
with {:ok, options} <- options(params),
     {:ok, page} <- TaskViews.list(view, view_context(conn), options, PostgresTaskViews) do
  json(conn, page)
else
  {:error, :invalid_cursor} -> invalid_query(conn)
  {:error, :stale_cursor} -> stale_cursor(conn)
  {:error, :infrastructure_failure} -> infrastructure_problem(conn)
end
```

**Closed input validation** (lines 54-72): accept only named query keys and bounded page sizes before invoking application code.

**Stable Problem Details** (lines 209-221):

```elixir
conn
|> put_status(status)
|> put_resp_content_type("application/problem+json")
|> json(%{
  code: code,
  detail: detail,
  recovery_action: recovery_action,
  retryable: retryable,
  status: status,
  title: title,
  type: "/problems/#{code}"
})
```

Router authentication must follow `apps/server/lib/keepling_web/router.ex:4-20,50-117`: public liveness and unversioned compatibility are separate scopes; sync/bootstrap require authenticated account context; operator-only status must not be placed in the public health scope. Readiness is bounded PostgreSQL + schema/protocol + finalized restore epoch, while backup lag belongs to status/preflight.

### Operations semantics and thin command wrappers

**Targets:** `application/ops.ex`, `application/ops/*`, `postgres/ops_store.ex`, `release.ex`, `mix/tasks/keepling.ops.ex`, `tooling/keepling-ops`.

**Application-health analog:** `apps/server/lib/keepling/accounts/security_audit.ex`

Use closed state/result maps and allow-listed telemetry. The analog exposes a bounded health value (lines 28-45), maps persistence failure to a closed rollback reason (lines 47-62), and logs only a closed event type and policy (lines 121-135):

```elixir
Logger.error("security audit persistence degraded",
  event_type: event_type,
  persistence_policy: policy
)

:telemetry.execute(
  [:keepling, :security_audit, :persistence],
  %{failure_count: 1},
  %{event_type: event_type, persistence_policy: policy, status: :degraded}
)
```

Operations results should likewise use a closed code, bounded facts, remediation, and stable exit status. Never include raw source/target identifiers, task content, secrets, provider response bodies, or unbounded exception inspection.

**Thin Mix-task analog:** `apps/server/lib/mix/tasks/keepling.recover.ex:10-48`

```elixir
{options, positional, invalid} = OptionParser.parse(args, strict: [...])

if positional != [] or invalid != [] do
  Mix.raise("usage: ...")
end

with {:ok, value} <- InwardApplicationOperation.call(options) do
  Mix.shell().info(render(value))
else
  {:error, reason} -> Mix.raise(stable_message(reason))
end
```

Unlike that source-time task, `Keepling.Release` must use `Application.ensure_loaded/1` plus `Ecto.Migrator.with_repo/2` so production releases do not depend on Mix or boot the endpoint/background side effects. Shell owns parsing/formatting/exit only; restore refusal and verification semantics stay in Elixir application modules.

### Contract schemas and golden vectors

**Targets:** OpenAPI, generated TypeScript, schema, and vector files.

**Analog:** `packages/contracts/vectors/conflicts.json`

**Fixture shape** (lines 1-46):

```json
{
  "version": 1,
  "fields": ["notes", "title"],
  "cases": [
    {
      "name": "overlapping title edit reports only the affected field",
      "current": {"notes": "", "title": "Current title"},
      "base_values": {"title": "Base title"},
      "requested_values": {"title": "My title"},
      "result": {"outcome": "conflict", "affected_fields": ["title"]}
    }
  ]
}
```

Keep fixed identities/clocks, named adversarial cases, explicit expected outcomes, and a top-level schema version. Freeze protocol-train fixtures rather than mutating them in place. Vector runners must reject vacuous/unknown cases.

Generation remains source-to-output drift checking per `tooling/check-contracts.mjs:6-41`: resolve paths from repository root, verify readable inputs, run the generator with `--check`, inherit output, and return its exact nonzero status.

### Phase runner, CI, and infrastructure verification

**Targets:** `tooling/test-phase-2.sh`, verify scripts, Phase 2 CI lanes.

**Analog:** `tooling/test-phase-1.sh`

**Repository-root and lane vocabulary** (lines 1-18):

```sh
#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH='' cd -P "$(dirname "$0")" && pwd)
repository_root=$(git -C "$script_dir" rev-parse --show-toplevel)
cd "$repository_root"

list_lanes() {
  echo "repository-integrity  tooling/check-repository-integrity.sh"
  echo "server-tests          complete ExUnit suite against disposable PostgreSQL"
  echo "contracts             checked-in OpenAPI generation drift"
}
```

**Disposable state and cleanup** (lines 20-51): use a task-specific `mktemp -d`, trap cleanup, pin runtime commands through `runtime-preflight.sh`, expose only test-specific environment variables, and stop owned PostgreSQL before removing the exact temporary directory.

**Single run entry** (lines 68-80):

```sh
run_lanes() {
  trap cleanup_phase_database EXIT HUP INT TERM
  ./tooling/check-repository-integrity.sh
  start_phase_database
  MIX_ENV=test ./tooling/runtime-preflight.sh --exec -- sh -c \
    'cd apps/server && mix ecto.migrate && mix compile --warnings-as-errors && mix test'
  pnpm contracts:check
}
```

Phase 2 should keep independent named fast/slow lanes, deterministic seeds, timing artifacts, and contract-triggered fan-out. CI should call committed tooling rather than duplicate semantics in YAML. Pin actions by commit before merge; the current workflow's `actions/checkout@v4` is a baseline to tighten, not the final Phase 2 pin.

## Shared Patterns

### Authentication and route ownership

**Source:** `apps/server/lib/keepling_web/router.ex:4-20,50-117`

- `:api` accepts JSON and fetches session.
- `:authenticated` loads/requires session and enables CSRF protection.
- mutation routes add trusted-origin enforcement.
- test-only controls remain guarded by `Mix.env() == :test` and are absent from production routes.

Sync pulls/bootstrap use authenticated scope. Compatibility and liveness may be public but contain no account/operator/private values. Operator status and destructive actions require a distinct operator authorization boundary.

### Stable errors

**Sources:** `command_store.ex:2125-2137`; `task_view_controller.ex:209-221`

Use stable `code`, `status`, `title`, `detail`, `retryable`, `recovery_action`, and `/problems/<code>` fields. Cursor reset, client upgrade, server upgrade, retryable outage, and restore refusal are distinct closed results.

### Real concurrency proof

**Source:** `apps/server/test/support/concurrency_case.ex:1-49`

Use `Sandbox.unboxed_run/2`, assert distinct PostgreSQL backend PIDs, and synchronize competing tasks through the reusable barrier. This is required for account-clock/resource-lock ordering; a single sandbox connection cannot prove absence of deadlock or feed-order gaps.

### Privacy-safe telemetry and hostile sentinels

**Sources:** `apps/server/lib/keepling_web/telemetry.ex:19-59`; `apps/server/test/keepling/telemetry_redaction_test.exs:10-15,44-119,122-158`

- Metric tags are fixed, low-cardinality keys.
- Tests attach to the exact event, require exact metadata keys, and scan captured logs plus telemetry.
- Hostile password, token, task-title, and identifier sentinels must be absent.
- Extend scanning to sync/grant/ops/backup/restore stdout, stderr, JSON, manifests, traces, and diagnostic bundles.

### Compatibility-safe persistence

Add fields/tables first, deploy code capable of old/new representations, backfill and validate, switch reads, age out supported clients and rollback images, then contract. Frozen codecs, receipts, cursors, and vectors live for the advertised support and retained-receipt window.

## No Analog Found

| File / Area | Role | Data Flow | Reason / Planner Direction |
|---|---|---|---|
| `infra/images/server/Dockerfile` | config | batch | No OCI build exists. Use research's digest-pinned, packaged-tested release contract. |
| `infra/compose/compose.yml` | config | batch / request-response | `infra/` currently contains only a README. Follow the research Compose shape: Caddy edge, app, private DB network, named DB volume, explicit health, graceful stop. |
| `infra/caddy/Caddyfile` | config | request-response | No edge config exists. Keep Caddy alive through app replacement and proxy stable `503`/`Retry-After`. |
| `infra/backup/*` | config / adapter | file-I/O + batch | No backup implementation exists. Use pinned pgBackRest plus `pg_dump -Fc`; credentials remain host/scheduler-owned, never app-container inputs. |
| `infra/tofu/hetzner/*` | provider / config | CRUD + batch | No OpenTofu exists. Use official hcloud provider with `location`, remote encrypted locked state, minimal cloud-init, and no canonical product state. |
| live DNS/provider adapters | provider | request-response | Provider and credential authority remain unresolved. Preserve a port/checkpoint; do not invent a provider in planning. |

## Metadata

**Analog search scope:** tracked files under `apps/server`, `packages/contracts`, `tooling`, `.github/workflows`, and the currently empty `infra` implementation boundary.

**Tracked files scanned:** 179 tracked product/contract/infrastructure/tooling/workflow files; detailed excerpts taken from 12 relevant tracked files and one targeted large-file scan.

**Primary analog families:** inward application port (`Application.TaskViews`), atomic PostgreSQL adapter (`CommandStore` + core migration), thin Phoenix adapter (`TaskViewController` + router), frozen contract/vector tooling, and disposable phase runner/privacy/concurrency tests.

**Pattern extraction date:** 2026-09-01
