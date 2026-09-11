# Phase 6: Portability and Trust Release - Pattern Map

**Mapped:** 2026-09-11
**Files analyzed:** 27 (new + modified, across export, CI/release, signing, governance, SRV-02, data-loss, oracle)
**Analogs found:** 24 / 27 (3 have no in-repo analog — new-territory tools/docs, listed in "No Analog Found")

All analog paths below were verified tracked with `git ls-files -- <path>` before being recorded.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `apps/server/lib/keepling/application/export.ex` (new) | service (application/inward) | streaming | `apps/server/lib/keepling/application/ops.ex` (verb dispatch) + `apps/server/lib/keepling/adapters/postgres/preview.ex` (only `Repo.transaction` call site) | role-match, new data-flow (no `Repo.stream` precedent) |
| `apps/server/lib/keepling/adapters/postgres/export.ex` (new) | service (Postgres `Ops.Port` impl) | streaming | `apps/server/lib/keepling/application/ops.ex`'s `Port` behaviour + `apps/server/lib/keepling/adapters/postgres/task_views.ex:685-697` (timeout-handling shape to NOT copy verbatim) | role-match |
| `apps/server/lib/keepling/application/ops.ex` (modified: add `export` verb) | config/service | CRUD | itself, lines 10-11 | exact (in-place edit) |
| `apps/server/lib/mix/tasks/keepling.ops.ex` (modified: no change expected — verb list is data-driven) | route/CLI | request-response | itself | exact |
| `apps/server/test/keepling/application/export_test.exs` (new) | test | streaming/integration | `apps/server/test/keepling/application/ops/restore_test.exs` | exact |
| `apps/server/priv/repo/migrations/<ts>_add_device_grant_last_used_at.exs` (new) | migration | CRUD | `apps/server/priv/repo/migrations/20260911000300_add_task_search_index.exs` (most recent tracked migration) | role-match (simple additive column, not the closest thematically but most recent/idiomatic `up/down` style) |
| `apps/server/lib/keepling/accounts/device_grant.ex` (modified: `last_used_at` field + write path) | model | CRUD | itself, lines 1-50 (schema field block) | exact (in-place edit) |
| `apps/server/lib/keepling_web/controllers/device_grant_controller.ex` (modified: `grant_response/1`) | controller | request-response | itself, lines 150-175 (`token_response/1`, `grant_response/1`) | exact (in-place edit) |
| `apps/server/lib/keepling_web/auth.ex` (modified: bind receipt reads to issuing grant, D-39) | middleware | request-response | itself, lines 185-209 (`agent_authority/2` closed match list + `insufficient_scope/1`) | exact (in-place edit) |
| `packages/contracts/openapi/keepling.yaml` (modified: widen `DeviceGrantSummary`) | config (schema) | request-response | itself, `DeviceGrantSummary` block (~lines 1831-1867) | exact (in-place edit) |
| `packages/contracts/schemas/export/*.schema.json` (new) | config (schema) | file-I/O | `packages/contracts/schemas/*` sibling schemas (e.g. `sync-state-machine.schema.json`) referenced by `packages/contracts/vectors/manifest.json` | role-match |
| `packages/contracts/vectors/export-golden.json` (new) | test fixture | file-I/O | `packages/contracts/vectors/mcp-injection.json` (multi-consumer precedent: `["elixir", "tooling"]`) | exact (named precedent) |
| `packages/contracts/vectors/manifest.json` (modified: register export vector) | config | CRUD | itself, `files` map (add `"export-golden.json": {"consumers": ["elixir", "tooling"]}` entry) | exact (in-place edit) |
| `tooling/verify-export-reader.mjs` (new) | utility (independent verifier) | file-I/O | `tooling/verify-ios-phase.mjs` (lane-report shape) + a from-scratch Node reader skeleton in RESEARCH.md | role-match |
| `tooling/verify-release.mjs` (new) | utility (CI gate) | batch | `tooling/verify-cross-adapter-phase.mjs` (guard-refusal + tracked-input-digest + BLOCKED-never-vacuous shape) and `tooling/verify-ios-phase.mjs` (per-lane name/positive-count/duration/digest report) | exact (both named as models) |
| `tooling/release-lanes.json` (new) | config | batch | `packages/contracts/vectors/manifest.json` (closed inventory checked for completeness) | role-match |
| `tooling/trust-lanes/oracle.mjs` (new) | utility (read-only checker) | event-driven | `tooling/verify-cross-adapter-phase.mjs` (independent-read discipline, BLOCKED semantics) | role-match |
| `tooling/trust-lanes/invariants.mjs`, `chaos.mjs`, `census.mjs` (new) | utility | event-driven/batch | same as `oracle.mjs` | role-match |
| `tooling/verify-trust-soak.mjs` (new) | utility (CI gate) | batch | `tooling/verify-ios-phase.mjs` (`--self-test`/lane-report shape) + `tooling/verify-macos-integration.mjs` (`--self-test-restore` precedent for D-49) | exact (both named as models) |
| `tooling/cross-adapter/legs.mjs` (modified: `runElectronLeg`/`runIphoneLeg`, ID-minting refactor) | utility (test driver) | request-response | itself, lines 60-180 (`runSharedScenarioSet`, the shared driver contract) and lines 291-348 (the two BLOCKED stubs being replaced) | exact (in-place edit) |
| `tooling/verify-cross-adapter-phase.mjs` (modified: extend `GUARDED_FILES`) | utility (CI gate) | request-response | itself, lines 1-47 | exact (in-place edit) |
| `apps/desktop/test/real-stack/real-stack-sync.spec.ts` (read as model, not modified) | test | request-response | — (this **is** the model for the electron leg driver, per D-36) | exact |
| `tooling/ios-device/server-driven-run.mjs` (read as model, not modified) | utility (device driver) | request-response | — (this **is** the model for the iphone leg driver, per D-36) | exact |
| `apps/desktop/forge.config.ts` (modified: `osxSign`/`osxNotarize`) | config | file-I/O | itself, full file (12-27) | exact (in-place edit) |
| `tooling/package-desktop.mjs` (modified: add `archiveDigestSha256`, `codeDirectoryHash`, `ditto` transport) | utility (build tooling) | file-I/O | itself, lines 140-149 (`hashDirectory`), 320-327 (`applicationDigestSha256` computation site) | exact (in-place edit) |
| `.github/workflows/desktop.yml` (modified: `id-token`/`attestations` permissions, `ditto` transport, `attest-build-provenance` step) | config (CI) | event-driven | itself, lines 1-15 (permissions block), 60-95 (artifact upload/retention), 180-230 (`desktop-packaged` job, TCC report step) | exact (in-place edit) |
| `apps/server/mix.exs` (modified: `package/0` license, `sbom` dep) | config | CRUD | itself | exact (in-place edit) |
| root `package.json`, `packages/*/package.json`, `apps/web/package.json`, `apps/desktop/package.json` (modified: `"license": "Apache-2.0"`) | config | CRUD | itself | exact (in-place edit) |
| `LICENSE`, `NOTICE`, `SECURITY.md`, `SUPPORT.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `PRIVACY.md`, `KNOWN-LIMITATIONS.md` (new, repo root) | config (governance docs) | file-I/O | author's own `szTheory/sigra/SECURITY.md` (named house style for SECURITY.md), `szTheory/exifcleaner/CONTRIBUTING.md` — **external repos, not in this git tree; cite by URL/description only, never as an in-repo path** | analog exists but is out-of-repo — see note below |
| `tooling/check-repository-integrity.sh` (modified: add `governance` lane) | utility (CI gate) | batch | itself, full file (35 lines) | exact (in-place edit) |
| `apps/desktop/store-worker/local-store.ts` (modified: durable refusal record for every outcome, migration) | service (storage layer) | event-driven | itself, lines 700-750 (`#replayVisible()`, the O-43 comment and existing title-only conflict-record `INSERT`) | exact (in-place edit) |
| `apps/desktop/migrations/000X_<refusal-durability>.sql` (new) | migration | CRUD | `apps/desktop/migrations/0002_outbox_state.sql` (most relevant sibling desktop migration; read for shape, not modified) | role-match |
| `packages/web-ui/src/tasks/ConflictResolver.tsx` (modified: per-field, lifecycle-aware) | component | CRUD | itself, full file (56 lines — the single-field, single-choice shape being widened) | exact (in-place edit) |
| `apps/desktop/renderer/DesktopShell.tsx` (modified: route keyboard commands through `attemptNavigation`) | component | event-driven | itself, lines 40-70 (`dispatch` switch calling `facade.setRoute` directly) | exact (in-place edit) |
| `packages/web-ui/src/workspace/Workspace.tsx` (read as target, not modified — `attemptNavigation`/`commitNavigation`) | component | event-driven | itself, lines 253-266 | exact (this **is** the guard `DesktopShell.tsx` must call into) |
| `apps/web/src/features/agents/AgentGrantList.tsx` (modified: real `scope`/`authorizedAt`/`lastUsedAt` rendering) | component | request-response | itself, lines 260-300+ (existing absent/empty/present ternary for `scope`) | exact (in-place edit) |

## Pattern Assignments

### `apps/server/lib/keepling/application/export.ex` (service, streaming) — NEW

**Analog:** `apps/server/lib/keepling/application/ops.ex` for the verb/port contract shape; `apps/server/lib/keepling/adapters/postgres/preview.ex:70` for the only existing `Repo.transaction` call site in the codebase.

**IMPORTANT — do not describe this as reusing an existing streaming pattern.** RESEARCH.md's own correction: `Repo.stream` has **zero** existing call sites anywhere in `apps/server/lib`. This is new machinery on a documented Ecto primitive, not a reused pattern, and needs its own test coverage rather than inheriting proof from a sibling.

**Port/behaviour pattern to copy** (`ops.ex`):
```elixir
defmodule Port do
  @moduledoc "Outward port for bounded inspection and admitted operational execution."

  @callback inspect(map() | keyword()) :: {:ok, map()} | {:error, atom()}
  @callback execute(String.t(), map(), map() | keyword()) ::
              :ok | {:ok, map()} | {:error, atom()}
end
```

**Verb registration** (`ops.ex` lines 10-11):
```elixir
@verbs ~w(preflight status doctor backup restore restore-verify deploy upgrade replace-host)
@destructive ~w(restore restore-verify deploy upgrade replace-host)
```
Add `export` to `@verbs` only — never to `@destructive` (D-05).

**Exit-code contract to reuse verbatim** (`ops.ex` lines 12-18):
```elixir
@exit_codes %{
  ok: 0, usage: 2, refusal: 10, dependency: 20,
  compatibility: 30, recovery: 40, execution: 50
}
```

**New transactional/streaming pattern (from RESEARCH.md, built on official Ecto docs, not an in-repo precedent):**
```elixir
Repo.transaction(
  fn ->
    Task
    |> where([t], t.account_id == ^account_id)
    |> order_by([t], asc: t.id)
    |> Repo.stream(max_rows: chunk_size)
    |> Stream.each(&write_ndjson_line(&1, tasks_file))
    |> Stream.run()
  end,
  timeout: export_timeout(),
  isolation_level: :repeatable_read
)
```

**Timeout pitfall — do NOT copy this pattern** (`apps/server/lib/keepling/adapters/postgres/task_views.ex:691-697`, verified):
```elixir
defp query_options do
  timeout = Application.fetch_env!(:keepling, :task_view_query_timeout_ms)

  if is_integer(timeout) and timeout > 0 do
    [timeout: timeout]
  else
    raise ArgumentError, "task-view query timeout must be a positive integer"
  end
end
```
This helper structurally cannot express `:infinity`. Define a distinct `:export_query_timeout_ms` accessor for export that permits `:infinity` — never reuse this one (D-08b).

---

### `apps/server/lib/keepling/adapters/postgres/export.ex` (service, Postgres port impl) — NEW

**Analog:** `Ops.Port` behaviour in `ops.ex`, implemented by whichever existing adapter backs `backup`/`restore` (same directory `apps/server/lib/keepling/adapters/postgres/`). Follow the `inspect/1` (readiness) + `execute/3` (admitted execution) two-callback shape.

---

### `apps/server/test/keepling/application/export_test.exs` (test, streaming/integration) — NEW

**Analog:** `apps/server/test/keepling/application/ops/restore_test.exs`

**Imports/module shape** (lines 1-14):
```elixir
defmodule Keepling.Application.Ops.RestoreTest do
  use ExUnit.Case, async: true

  alias Keepling.Application.Ops.Restore

  @source "sha256:" <> String.duplicate("a", 64)
  @image "sha256:" <> String.duplicate("b", 64)
  @target "recovery-target-alpha"
  @now ~U[2026-09-01 12:00:00.000000Z]
```

**Fake-port-as-Agent test double pattern** (lines 11-54) — define an in-memory `Store` module implementing the real `@behaviour`, backed by an `Agent`, rather than mocking:
```elixir
defmodule Store do
  @behaviour Keepling.Application.Ops.Restore.Port

  def start_link, do: Agent.start_link(fn -> %{completed: %{}, leases: %{}, runs: %{}} end)
  def state(store), do: Agent.get(store, & &1)

  @impl true
  def lookup_completed(key, store), do: Agent.get(store, &Map.fetch(&1.completed, key))
  # ...
end
```

**Golden-vector-driven refusal test pattern** (lines 61-73) — apply this directly to D-07's schema-driven-completeness lane and golden export vector:
```elixir
test "fixed vectors refuse every unsafe source or target before mutation", %{store: store} do
  vectors = recovery_vectors()

  for vector <- vectors["refusals"] do
    input = Map.merge(valid_input(), vector["input"])
    expected = vector["outcome"]

    assert {:refused, ^expected} =
             Restore.begin(input, Store, store, random_bytes: fn _ -> <<1::128>> end)

    assert Store.state(store) == %{completed: %{}, leases: %{}, runs: %{}}
  end
end
```
For export's D-07 lane 1 (schema-driven completeness), add the `information_schema.columns` pattern from RESEARCH.md:
```elixir
{:ok, %{rows: rows}} =
  Ecto.Adapters.SQL.query(
    Repo,
    "SELECT table_name, column_name FROM information_schema.columns WHERE table_schema = 'public'",
    []
  )
# Compare `rows` against the checked-in IN/OUT classification manifest (D-01);
# fail the test if any column is absent from that manifest.
```

---

### `apps/server/priv/repo/migrations/<ts>_add_device_grant_last_used_at.exs` (migration) — NEW

**Analog:** `apps/server/priv/repo/migrations/20260911000300_add_task_search_index.exs` (most recent tracked migration — copy its `up/down` reversible-SQL style, not necessarily its generated-column mechanism, which is unrelated to a plain nullable timestamp column):
```elixir
defmodule Keepling.Repo.Migrations.AddTaskSearchIndex do
  use Ecto.Migration

  def up do
    execute(
      """
      ALTER TABLE tasks
      ADD COLUMN search_document tsvector ...
      """,
      "ALTER TABLE tasks DROP COLUMN search_document"
    )
  end

  def down do
    execute(
      "DROP INDEX tasks_search_document_gin",
      """..."""
    )
  end
end
```
For `last_used_at`, a plain `add :last_used_at, :utc_datetime_usec` inside a `create table`-style block (see the column list precedent in `apps/server/priv/repo/migrations/20260901000200_add_device_grants.exs`) is sufficient — no generated column or reversible-`execute` needed. **Before writing this migration, resolve the RESEARCH.md Open Question #1 checkpoint:decision** on what event advances `last_used_at` (every authenticated request vs. mutations only vs. MCP calls only) — this changes whether a companion hot-path write lands in `auth.ex`/`device_grant.ex` or only in the MCP tool-call path.

---

### `apps/server/lib/keepling/accounts/device_grant.ex` (model) — MODIFIED

**Analog:** itself. Existing `scope` field is already real and requires no schema change:
```elixir
field :scope, {:array, :string}, default: []
```
Add `field :last_used_at, :utc_datetime_usec` alongside the existing `last_refreshed_at` field. Do **not** conflate the two — `last_refreshed_at` only advances on OAuth refresh-token rotation (Pitfall 5), not on ordinary authenticated calls.

---

### `apps/server/lib/keepling_web/controllers/device_grant_controller.ex` (controller) — MODIFIED

**Analog:** itself, `grant_response/1` (lines 167-175):
```elixir
defp grant_response(grant) do
  %{
    client_kind: grant.client_kind,
    generation: grant.generation,
    id: grant.id,
    installation_id: grant.installation_id,
    label: grant.label,
    revoked: grant.revoked?
  }
end
```
Widen to add `scope: grant.scope`, `authorized_at: grant.inserted_at`, `last_used_at: grant.last_used_at` — preserving the absent-vs-empty rule: `scope` is `[]` not `nil` once wired (D-38); `last_used_at` stays `nil` until the write path exists (maps to UI's "Not yet reported").

---

### `apps/server/lib/keepling_web/auth.ex` (middleware, D-39 receipt-scope inversion) — MODIFIED

**Analog:** itself, `agent_authority/2` (lines 190-209) — a closed method+path match list, one clause per authority:
```elixir
defp agent_authority("GET", ["api", "v1", "search"]), do: {:ok, "tasks.read"}
defp agent_authority("GET", ["api", "v1", "mutations", _id]), do: {:ok, "tasks.write"}

defp agent_authority("POST", ["api", "v1", "commands", command])
     when command in @agent_writable_commands,
     do: {:ok, "tasks.write"}

defp agent_authority(_method, _path_info), do: :no_agent_authority
```
The comment above the `mutations/:id` clause already states the intended fix's rationale verbatim: *"the receipt WITH the write: it is the stored result of a mutation, readable by the authority that could have issued it."* D-39's fix binds the receipt lookup (`Commands.lookup_result/3`) to the grant that issued the mutation, not merely to `tasks.write` scope in general — extend this match/dispatch shape, do not introduce a new middleware layer.

**403 discipline to preserve** (`insufficient_scope/1`, referenced immediately after):
constant body, names neither the missing scope nor route existence.

---

### `packages/contracts/vectors/manifest.json` + `export-golden.json` (D-07 lane 2, registration) — NEW/MODIFIED

**Analog:** the `mcp-injection.json` multi-consumer precedent, verbatim from the manifest's own `_comment` and `files` map:
```json
"mcp-injection.json": {
  "consumers": ["elixir", "tooling"]
}
```
The `_comment` field states the rule this phase must follow: *"mcp-injection.json (05-11-PLAN.md) is the only file whose 'tooling' consumer is proven by a static executed-file report at tooling/vector-conformance-reports/tooling.json rather than a regenerated one."* Register `export-golden.json` the same way — `["elixir", "tooling"]` — since both `export_test.exs` (Elixir) and `verify-export-reader.mjs` (tooling) are independent consumers per D-07's four-part lane design. Enforced by `tooling/check-contracts.mjs`'s cross-consumer gate — do not hand-add without confirming that gate recognizes the new file.

---

### `tooling/verify-export-reader.mjs` (independent reader, D-07 lane 3) — NEW

**Analog:** shape follows `tooling/verify-ios-phase.mjs`'s lane-report discipline (name, positive case count, duration, tracked-input digest — see Shared Patterns below) but the reader itself is a from-scratch Node script. RESEARCH.md's skeleton (already written against real project conventions, safe to copy near-verbatim):
```js
// tooling/verify-export-reader.mjs — Node-only, no import from apps/server
import { createHash } from 'node:crypto'
import { readFileSync, readdirSync } from 'node:fs'
import Ajv from 'ajv' // or a hand-rolled minimal validator if a new dep is undesirable

const manifest = JSON.parse(readFileSync('manifest.json', 'utf8'))
for (const file of manifest.files) {
  const bytes = readFileSync(file.path)
  const digest = createHash('sha256').update(bytes).digest('hex')
  if (digest !== file.sha256) throw new Error(`${file.path}: digest mismatch`)
  const lines = bytes.toString('utf8').trim().split('\n').filter(Boolean)
  if (lines.length !== file.rowCount) throw new Error(`${file.path}: row count mismatch`)
  for (const line of lines) {
    const record = JSON.parse(line) // throws on malformed NDJSON — that's the point
    // validate `record` against packages/contracts/schemas/export/<entity>.schema.json
  }
}
// no-secrets assertion: grep every file for known credential-fixture substrings
```

---

### `tooling/verify-release.mjs` + `tooling/release-lanes.json` (D-12) — NEW

**Analog:** `tooling/verify-cross-adapter-phase.mjs`, full pattern to copy:

**Header/purpose-comment discipline** (lines 1-20) — state exactly what one run proves and what "BLOCKED" means, in-file, before any code:
```js
/**
 * A leg that cannot run throws a `BLOCKED:`-prefixed error and BLOCKS the
 * lane -- never substituted with a fixture, a cached artifact, or another
 * leg's evidence (the fourth vacuity mode research named). This command can
 * never exit 0 while any leg is blocked or while cross-leg evidence
 * disagrees.
 */
```

**Guard-refusal list pattern** (lines 22-31) — apply this exact shape to guard `verify-release.mjs` and every file it reads against shortcut injection:
```js
// Guard-refusal: this lane's own leg modules must never take a shortcut
// (a stubbed fetch, a non-resolving placeholder host, a hand-injected
// bearer, or a test-only sync mode). Checked at every invocation, not just
// once at authoring time
const GUARDED_FILES = [
  join(repositoryRoot, 'tooling', 'cross-adapter', 'legs.mjs'),
  join(repositoryRoot, 'tooling', 'verify-cross-adapter-phase.mjs'),
]
```

**Tracked-input digest list** (lines 33-42) — `verify-release.mjs` should build its own analogous `TRACKED_INPUT_PATHS` array naming every source file whose content the manifest's lanes are evidence over:
```js
const TRACKED_INPUT_PATHS = [
  'tooling/verify-cross-adapter-phase.mjs',
  'tooling/cross-adapter/legs.mjs',
  // ...
]
```

**Positive-case-count / BLOCKED-exits-nonzero discipline** — from `tooling/verify-ios-phase.mjs`'s header comment, apply verbatim to every new lane in this phase:
```
Every lane reports a name, a positive case count, a duration, and a
tracked-input digest -- a lane that cannot report a positive count is a
FAILURE of the gate, never a silently-skipped green.
...
A lane may report `BLOCKED` (never PASS, never silently absent)... BLOCKED
still fails the overall run (exit code stays non-zero).
```

**Lane-inventory hard-compare pattern to reuse for D-12's "exactly once" assertion:** `tooling/check-ci-contract.mjs:50` compares a committed lane list against reality with an exact-set comparison (read that line range at implementation time — same shape `release-lanes.json` needs).

---

### `tooling/trust-lanes/{oracle,invariants,chaos,census}.mjs` + `tooling/verify-trust-soak.mjs` (D-45..D-51) — NEW

**Analog:** same lane conventions as `verify-release.mjs` above (`verify-ios-phase.mjs`, `verify-cross-adapter-phase.mjs`), plus `tooling/verify-macos-integration.mjs`'s `--self-test-restore` flag precedent for D-49's mandatory `--self-test` (12 synthetic corrupted fixtures, one per invariant). Read `verify-macos-integration.mjs`'s `--self-test-restore` implementation at plan time for the exact CLI-flag/fixture-loading shape — not excerpted here to avoid re-reading a large file without a concrete task driving it yet.

**No-INSERT/UPDATE/DELETE discipline** — model on `verify-cross-adapter-phase.mjs`'s BLOCKED-never-substituted rule; the oracle's three independent reads (server GET + `keepling_auditor` PG role, desktop SQLite `mode=ro`, iOS `devicectl device copy from`) must import **no client code**, mirroring `verify-cross-adapter-phase.mjs`'s own "imports no shared implementation, invariants sit on the schema" design already proven for cross-adapter.

---

### `tooling/cross-adapter/legs.mjs` (modified: wire electron + iphone legs) — SRV-02

**Analog:** itself. The shared driver contract every leg must satisfy (lines 60-72, `runSharedScenarioSet` calling convention):
```js
async function runSharedScenarioSet(legName, adapter, { inputDigest, origin, runId, sessionCookie }) {
  // capture_one_task / complete_task / reopen_task / update_stale_expected_revision
  // each calls adapter.capture/complete/reopen, then reads final state from the
  // SERVER's APIs (never the adapter's self-report) via readFinalState(...)
}
```
**Current BLOCKED stubs being replaced** (lines 291-348, verbatim — this is exactly what the new drivers must stop doing):
```js
export async function runElectronLeg() {
  const outRoot = join(repositoryRoot, 'apps', 'desktop', 'out')
  if (!existsSync(outRoot)) {
    throw blocked(`no packaged Electron build found at apps/desktop/out ...`)
  }
  // A packaged build exists, but this lane has not yet been given a live
  // IPC driver against it ...
  throw blocked('a packaged Electron build exists ... but this leg has no live IPC driver wired to it yet ...')
}

export async function runIphoneLeg() {
  const bootedList = spawnSync('xcrun', ['simctl', 'list', 'devices', 'booted'], { encoding: 'utf8' })
  // ... booted-simulator + installed-app checks ...
  throw blocked(`Keepling is installed ... but this leg has no live UI driver wired to it yet ...`)
}
```
**Driver model for the electron leg (per D-36):** `apps/desktop/test/real-stack/real-stack-sync.spec.ts` — packaged app, disposable profile, real adapter, no stubbed fetch. **Note the WINDOWS.md row 69 path correction:** the file lives at `test/real-stack/`, not `test/packaged/`.

**Driver model for the iphone leg (per D-36):** `tooling/ios-device/server-driven-run.mjs:214-266` — read for its device-vs-simulator platform-selection discipline and its locked-device BLOCKED detection pattern:
```js
if (/could not be, unlocked|FBSOpenApplicationErrorDomain error 7|BSErrorCodeDescription = Locked/i.test(output)) {
  const blocked = new Error(
    'the iPhone is LOCKED, so no app could be launched and this lane could learn nothing. ...',
  )
```

**Required extension:** `tooling/verify-cross-adapter-phase.mjs`'s `GUARDED_FILES` array (lines 26-29) must add the two new driver files, or the lane loses its anti-vacuity teeth (explicit instruction in 06-CONTEXT.md D-36).

---

### `apps/desktop/forge.config.ts` + `tooling/package-desktop.mjs` (D-16/D-17 signing) — MODIFIED

**Analog:** itself, current full `forge.config.ts` (no `osxSign`/`osxNotarize` today):
```ts
packagerConfig: {
  appBundleId: 'dev.keepling.desktop',
  appCategoryType: 'public.app-category.productivity',
  appCopyright: 'Copyright © Keepling contributors',
  asar: true,
  extraResource: [ /* dist/main, dist/preload, dist/renderer, dist/worker, migrations */ ],
  ignore: [/node_modules/],
  name: 'Keepling',
  prune: false,
},
plugins: [],
```
Add `osxSign`/`osxNotarize` per RESEARCH.md Pattern 3's skeleton (per-helper entitlements via `optionsForFile`, never `codesign --deep`).

**The digest-computation site that makes ordering load-bearing** (`tooling/package-desktop.mjs:320-327`, verified verbatim):
```js
const applicationDigestSha256 = hashDirectory(applicationPath)
if (hashDirectory(copiedApplicationPath) !== applicationDigestSha256) fail('the copied application digest differs from the built application')
```
**The mode-bit hashing that the `ditto` fix (D-11) must preserve** (`tooling/package-desktop.mjs:142-145`):
```js
const relativePath = relative(root, path)
const metadata = lstatSync(path)
digest.update(`${relativePath}\0${metadata.mode.toString(8)}\0`)
```
Signing MUST run inside Forge's `package` step (via `packagerConfig.osxSign`), so this `hashDirectory` call observes the *signed* bundle — never bolt signing on as a later CI step.

---

### `.github/workflows/desktop.yml` (D-15, D-22 permissions/attestation) — MODIFIED

**Analog:** itself, top-level permissions block (verified, lines 6-8):
```yaml
permissions:
  contents: read
```
**Existing retention + artifact-upload pattern to extend, not replace** (lines ~60-72):
```yaml
- uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2
  with:
    name: ${{ env.KEEPLING_DESKTOP_ARTIFACT_ROOT }}
    path: ${{ runner.temp }}/${{ env.KEEPLING_DESKTOP_ARTIFACT_ROOT }}
    if-no-files-found: error
    retention-days: 14
```
**Existing TCC-report step to keep unchanged** (`desktop-packaged` job, ~lines 195-210) — converts the hosted-runner Accessibility-grant impossibility into published evidence; do not remove:
```yaml
- name: Report what TCC this hosted runner actually grants
  run: |
    swiftc -O -swift-version 5 -o "$RUNNER_TEMP/TccProbe" tooling/macos-integration/TccProbe.swift
    "$RUNNER_TEMP/TccProbe" | tee "$RUNNER_TEMP/tcc-report.json"
```
**Action pinning convention** (visible throughout — every `uses:` is pinned to a full commit SHA with a version comment) — the new `actions/attest-build-provenance` and `sigstore/cosign-installer` steps must follow the identical pinning style.

---

### `tooling/check-repository-integrity.sh` (D-32 governance lane) — MODIFIED

**Analog:** itself, full 35-line file — copy its `set -eu`, single-purpose check + explicit failure message + final success echo shape:
```sh
#!/usr/bin/env sh
set -eu

repository_root=$(git rev-parse --show-toplevel)
cd "$repository_root"

# ... one check block per concern, each with `exit 1` and a stated reason ...

echo "Repository integrity checks passed."
```
Add a `governance` check block in the same style: assert each root policy file exists/non-empty, `LICENSE` hashes to canonical Apache-2.0, every `package.json`/`mix.exs` declares `Apache-2.0`, SECURITY.md's table byte-matches a render from `/compatibility`, every PRIVACY.md claim row's evidence path exists. Per D-32, if `/compatibility` cannot be read, this lane must report **BLOCKED**, not pass — follow the same non-zero-exit-on-uncertainty discipline the rest of this script already uses.

---

### `apps/desktop/store-worker/local-store.ts` (O-43/O-44 refusal durability) — MODIFIED

**Analog:** itself, lines 700-743 — the existing (currently title-only) conflict-record write on refusal:
```ts
if (current !== null && mine !== null) {
  this.#database.prepare(`
    INSERT INTO conflicts(conflict_id, mutation_id, details_json) VALUES (?, ?, ?)
    ON CONFLICT(conflict_id) DO UPDATE SET details_json = excluded.details_json
  `).run(
    `conflict:${acknowledgement.mutationId}`,
    acknowledgement.mutationId,
    JSON.stringify({ current, mine }),
  )
}
```
**The exact defect comment in shipped code that D-37 requires fixing** (lines 727-743, verbatim):
```ts
// KNOWN LIMIT, recorded in 03-22-SUMMARY.md rather than papered over:
// the refused command is terminal and is gone from the outbox, so the
// NEXT pull replays the shadow and the local value is lost. Giving a
// refused local change a durable home is a product decision this plan
// did not carry authority to make.
if (acknowledgement.outcome === 'accepted' || acknowledgement.outcome === 'already_satisfied') {
  this.#replayVisible()
}
```
Fix pattern: widen the `INSERT` condition to cover **every** refusal outcome (not just `current !== null && mine !== null`, i.e. not just title divergence — this is O-44's coupling requirement), and make `#replayVisible()`'s pull-path refuse to overwrite an unresolved refusal row.

---

### `packages/web-ui/src/tasks/ConflictResolver.tsx` (O-44 per-field widening) — MODIFIED

**Analog:** itself, the full current single-field component (56 lines) being widened:
```tsx
function ConflictResolver({ conflict, facade }: ConflictResolverProps) {
  const choose = async (choice: 'current' | 'mine') => {
    const outcome = await facade.resolveConflict(choice)
    if (outcome.kind === 'rejected') setProblem(outcome.message)
  }
  return (
    <section aria-labelledby={...} role="region">
      <h2 ref={headingRef} tabIndex={-1}>This task changed somewhere else.</h2>
      <p>Your draft is still here. Choose which title Keepling should keep.</p>
      <div>
        <p><strong>Your version:</strong> {conflict.mine}</p>
        <p><strong>Current version:</strong> {conflict.current}</p>
      </div>
      <button onClick={() => void choose('mine')}>Use mine</button>
      <button onClick={() => void choose('current')}>Use current</button>
    </section>
  )
}
```
Focus-on-mount and inline (never overlay) discipline, the `busy`/`problem` state shape, and the `aria-labelledby` heading pattern all carry over verbatim per the UI-SPEC. Widen to one `<fieldset>`/`role="group"` row per affected field (title, notes, planned date, deadline, project, tags, lifecycle/Trash), each with its own `Your version`/`Current version` and independent `Use mine`/`Use current` radio-style choice — staged, not submitted, until one `Save`-equivalent point (per 06-UI-SPEC.md's contract).

---

### `apps/desktop/renderer/DesktopShell.tsx` + `packages/web-ui/src/workspace/Workspace.tsx` (O-22) — MODIFIED

**Analog:** itself for the defect, `Workspace.tsx` for the target pattern to route through.

**Current defect** (`DesktopShell.tsx` lines 48-68, verbatim):
```tsx
const dispatch = (command: SemanticCommand) => {
  const snapshot = facade.getSnapshot()
  switch (command) {
    case 'new-task': {
      facade.setRoute('inbox')  // <-- bypasses the dirty-state guard
      ...
    }
    case 'go-inbox':
      facade.setRoute('inbox')  // <-- bypasses the dirty-state guard
      break
    case 'go-today':
      facade.setRoute('today')  // <-- bypasses the dirty-state guard
      break
```
**The guard being bypassed** (`Workspace.tsx` lines 253-266, verbatim — this is the function every keyboard command must call instead):
```tsx
const attemptNavigation = async (navigation: PendingNavigation) => {
  if (!dirty) {
    commitNavigation(navigation)
    return
  }
  setPendingNavigation(navigation)
}

const commitNavigation = (navigation: PendingNavigation) => {
  if (navigation.kind === 'route') facade.setRoute(navigation.route)
  else facade.selectTask(navigation.taskId)
}
```
Fix pattern: `DesktopShell.tsx`'s keyboard dispatch must call something equivalent to `attemptNavigation({ kind: 'route', route: 'inbox' })` — reachable from `DesktopShell` (which currently holds only the `facade`, not `Workspace`'s local `attemptNavigation`/`dirty` state) — rather than `facade.setRoute` directly. This likely requires exposing `attemptNavigation` (or an equivalent guarded-navigate callback) from `Workspace` up to `DesktopShell`, or moving keyboard-command handling down into `Workspace`'s own scope. Zero new dialog copy — the existing `Discard Unsaved Changes?` dialog (already specified in 01/03-UI-SPEC.md) is reused unchanged.

---

### `apps/web/src/features/agents/AgentGrantList.tsx` (D-38 absent-vs-empty) — MODIFIED

**Analog:** itself, the existing `scope` ternary (lines ~275-289, verbatim) — this is the exact pattern D-38 requires extending to `authorizedAt`/`lastUsedAt`:
```tsx
<dd>
  {grant.scope === null ? (
    'Not yet reported'
  ) : grant.scope.length === 0 ? (
    'No scopes granted'
  ) : (
    <span className="flex flex-wrap gap-2">
      {grant.scope.map((scope) => (
        <code className="rounded border border-border px-2 py-1" key={scope}>
          {scope}
        </code>
      ))}
    </span>
  )}
</dd>
```
Apply the identical `=== null ? 'Not yet reported' : ...` shape to `lastUsedAt`, but per 06-UI-SPEC.md's contract, **do not** collapse `null` into `'Not yet used'` — that copy is reserved for a future genuine zero-activity state once the write path exists. Today, `lastUsedAt: null` always renders `'Not yet reported'`.

## Shared Patterns

### Anti-vacuity lane report (name, positive case count, duration, tracked-input digest, BLOCKED-is-non-zero)
**Source:** `tooling/verify-ios-phase.mjs` (header comment, lines 1-25), `tooling/verify-cross-adapter-phase.mjs` (guard-refusal + `TRACKED_INPUT_PATHS`, lines 1-47)
**Apply to:** `tooling/verify-release.mjs`, `tooling/release-lanes.json`, `tooling/trust-lanes/*.mjs`, `tooling/verify-trust-soak.mjs`, and the extended `tooling/check-repository-integrity.sh` governance lane.
```js
// A lane may report `BLOCKED` (never PASS, never silently absent) ...
// BLOCKED still fails the overall run (exit code stays non-zero).
```

### Closed vocabulary / exhaustive match list
**Source:** `apps/server/lib/keepling/application/ops.ex` (`@verbs`), `apps/server/lib/keepling/application/agent_scope.ex` (`@agent_scopes`), `apps/server/lib/keepling_web/auth.ex` (`agent_authority/2`'s exhaustive clause list)
**Apply to:** the export entity list, the oracle's I1-I8 violation-reason vocabulary, any new closed set this phase introduces.
```elixir
@agent_scopes ~w(tasks.read tasks.write tasks.bulk)

def require(%{scope: granted}, scope) when is_list(granted) and scope in @agent_scopes do
  if scope in granted, do: :ok, else: {:error, :insufficient_scope}
end
def require(_context, _scope), do: {:error, :insufficient_scope}
```

### Absent ≠ empty
**Source:** `apps/web/src/features/agents/AgentGrantList.tsx` (existing `scope` ternary, established by 05-UI-REVIEW)
**Apply to:** the widened `AgentGrantList.tsx` fields (`authorizedAt`, `lastUsedAt`), the export manifest's optional fields, and `ConflictResolver.tsx`'s "absent fields are not rendered as empty rows."
```tsx
{grant.scope === null ? 'Not yet reported' : grant.scope.length === 0 ? 'No scopes granted' : /* chips */}
```

### Digest-bound evidence, computed at the right moment
**Source:** `tooling/package-desktop.mjs:320-327` (`applicationDigestSha256`), `tooling/smoke-desktop-packaged.mjs:64-77` (recomputation)
**Apply to:** `tooling/verify-release.mjs`'s `release-manifest.json` (`artifacts[].digestSha256`, `archiveDigestSha256`), `tooling/verify-trust-soak.mjs`'s evidence bundle (`applicationDigestSha256` + `keeplingBuildDigest` + `gitRevision` + source digests).
```js
const applicationDigestSha256 = hashDirectory(applicationPath)
if (hashDirectory(copiedApplicationPath) !== applicationDigestSha256) fail('...')
```

### GitHub Actions pinning convention
**Source:** `.github/workflows/desktop.yml` (every `uses:` pinned to a full commit SHA with a version comment)
**Apply to:** the new `actions/attest-build-provenance`, `sigstore/cosign-installer` steps.
```yaml
- uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2
```

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `LICENSE`, `NOTICE`, `SECURITY.md`, `SUPPORT.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `PRIVACY.md`, `KNOWN-LIMITATIONS.md` | config (governance docs) | file-I/O | No governance documents exist in this repo today (verified: none of these files exist at root). The named house-style analog (`szTheory/sigra/SECURITY.md`, `szTheory/exifcleaner/CONTRIBUTING.md`) is a **different, external repository** — not git-tracked source in `keepling` and must not be cited as an in-repo path. Planner should reference RESEARCH.md/CONTEXT.md's D-27/D-31/D-32 prose directly, and treat the author's other repos as external reading material, never as a `git ls-files`-verifiable analog. |
| `apps/server/lib/keepling/adapters/postgres/export.ex`'s streaming internals | service | streaming | RESEARCH.md's own correction: `Repo.stream` has zero existing call sites in this codebase. No in-repo analog exists for the chunked-read mechanics themselves (only the Ecto official docs, cited in RESEARCH.md Pattern 1). |
| Cosign/SBOM CI step bodies (`cosign sign`, `mix sbom.cyclonedx`, `@cyclonedx/cyclonedx-npm` invocations) | config (CI) | event-driven | No existing signing or SBOM step exists anywhere in `.github/workflows/`; these are genuinely new tool invocations with no in-repo precedent — RESEARCH.md's Pattern 4/5 (official-docs-cited) is the correct reference, not a codebase analog. |

## Metadata

**Analog search scope:** `apps/server/lib/keepling/{application,adapters/postgres,accounts}`, `apps/server/lib/keepling_web/{controllers,auth.ex}`, `apps/server/test/keepling/application`, `apps/server/priv/repo/migrations`, `packages/contracts/{vectors,openapi}`, `tooling/` (top-level scripts, `cross-adapter/`, `ios-device/`), `apps/desktop/{forge.config.ts,store-worker,renderer,migrations}`, `packages/web-ui/src/{tasks,workspace}`, `apps/web/src/features/agents`, `.github/workflows/desktop.yml`, `.github/workflows/repository-integrity.yml`
**Files scanned:** ~30 read directly (targeted ranges via `sed -n`/`Read` offsets, no re-reads of the same range)
**Pattern extraction date:** 2026-09-11
