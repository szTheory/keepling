# Phase 4: Native iPhone Daily Loop - Pattern Map

**Mapped:** 2026-09-04
**Files analyzed:** 34 (new Swift/tooling/contract files implied by CONTEXT.md + RESEARCH.md)
**Analogs found:** 34 / 34 (all cross-language/cross-tool; no exact-language match exists since `apps/ios` currently contains only `README.md`)

**Tracked-source verification:** every analog path below was confirmed with `git ls-files -- <path>` (non-empty output) before being named. No path under `apps/desktop/out/`, `apps/desktop/dist/`, or `apps/desktop/dist-harness/` (all git-ignored build mirrors) is used as an analog anywhere in this document — those directories exist on disk but are NOT tracked; the tracked precedent for everything they contain is the corresponding source under `apps/desktop/main/`, `apps/desktop/renderer/`, `apps/desktop/store-worker/`, `apps/desktop/preload/`, and `apps/desktop/migrations/`.

## Cross-Language Mapping Caveat

`apps/ios` is a **new Swift target outside the pnpm workspace**. There is no Swift precedent in this repository — every analog below is the Phase 3 Electron/TypeScript desktop client (`apps/desktop/`), the Elixir reference model (`apps/server/`), or the Node-based tooling (`tooling/`). The planner and executor must treat every excerpt as **pattern-to-reimplement**, never **code-to-port**: same invariant, same transaction shape, same state vocabulary, same evidence-gate structure — expressed in GRDB/Swift/XCTest idiom instead of `node:sqlite`/TypeScript/Vitest idiom. Where GRDB's own idiom differs materially from the desktop's raw-SQL wrapper (transaction API, PRAGMA hook, migrator), that difference is called out explicitly per file below.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `apps/ios/project.yml` (XcodeGen manifest) | config | batch (codegen) | `apps/desktop/package.json` + `apps/desktop/vite.*.config.ts` (multi-target build manifest set) | role-match (build/target config, no direct XcodeGen precedent) |
| `apps/ios/Package.swift` (KeeplingCore SPM package) | config | batch | `apps/desktop/package.json` (dependency + target declaration) | role-match |
| `apps/ios/Sources/KeeplingCore/Storage/Migrations/0001_initial.sql` (or Swift-embedded DDL) | migration | CRUD | `apps/desktop/migrations/0001_initial.sql` | exact (same 11-table schema, same STRICT/DDL text to mirror line-for-line) |
| `apps/ios/Sources/KeeplingCore/Storage/Migrations/0002_outbox_state.sql` | migration | CRUD | `apps/desktop/migrations/0002_outbox_state.sql` | exact (same monotonic 3-state outbox column) |
| `apps/ios/Sources/KeeplingCore/Storage/LocalStorePort.swift` (protocol) | service (port/interface) | CRUD | `apps/desktop/store-worker/local-store.ts` (its public method surface: `acceptMutation`, `applyPull`, `acknowledge`, `readyMutations`, `undoLastLocalAction`, `resolveConflict`, `snapshot`, `syncState`) | exact (same port surface, reimplemented as a Swift `protocol`) |
| `apps/ios/Sources/KeeplingCore/Storage/GRDBLocalStore.swift` (adapter) | service | CRUD + transaction | `apps/desktop/store-worker/local-store.ts` (`NodeSqliteLocalStore` class, its `BEGIN IMMEDIATE`/`COMMIT`/`ROLLBACK` blocks, `#applyMigration`, `#assertNotFenced`) | exact (same transaction shape; GRDB replaces manual `BEGIN IMMEDIATE` text with `db.write { }` / `Database.TransactionKind.immediate`) |
| `apps/ios/Sources/KeeplingCore/Storage/RawSQLite3LocalStore.swift` (D-05 fallback, built only if triggered) | service | CRUD + transaction | same as above | role-match (fallback path only; do not pre-build) |
| `apps/ios/Sources/KeeplingCore/Sync/SyncReducer.swift` (pure state machine) | service (reducer) | event-driven | `apps/server/lib/keepling/application/sync/reference_model.ex` (`ReferenceModel.local_accept/2`, `.new/0`, terminal-outcome/dependency handling) | exact (this IS the third independent implementation of the same reducer contract) |
| `apps/ios/Sources/KeeplingCore/Sync/SyncPort.swift` (protocol) | service (port) | request-response | `apps/desktop/main/adapters/sync.ts` (`SyncPort` interface consumed by `DesktopApplication`, declared in `apps/desktop/main/application/DesktopApplication.ts`) | exact |
| `apps/ios/Sources/KeeplingCore/Transport/KeeplingSyncAdapter.swift` (generated client + hand mappers) | service (adapter) | request-response | `apps/desktop/main/adapters/sync.ts` (`KeeplingSyncAdapter` class: `pull`, `push`, `bootstrap`, `acknowledge` mapping, `settleClassified`/`settleRefusal`, `mapAcknowledgement`, `mapUndoAvailability`) | exact |
| `apps/ios/Sources/KeeplingCore/Transport/Generated/*.swift` (swift-openapi-generator committed output) | generated DTO | transform | `packages/contracts/generated/keepling.ts` (committed `openapi-typescript` output) | exact (same "commit generated output" precedent, different generator) |
| `apps/ios/Sources/KeeplingCore/Application/KeeplingApplication.swift` (orchestrator: pull→push→ack loop, ScenePhase-driven) | controller/orchestrator | event-driven | `apps/desktop/main/application/DesktopApplication.ts` (`runSyncPass`, `beginTransmission`/`abandonTransmission` sequencing) | exact |
| `apps/ios/Sources/KeeplingCore/Application/OutboundCommands.swift` | service | CRUD | `apps/desktop/main/application/outbound-commands.ts` | exact |
| `apps/ios/Sources/KeeplingCore/Presentation/SyncPresentation.swift` (single authoritative projection, D-41) | service (presentation projection) | transform | `apps/desktop/main/application/presentation.ts` (`deriveDesktopPresentation`, `DesktopPresentationKind` union, `GRACE_PERIOD_MS`) | exact |
| `apps/ios/Sources/KeeplingCore/AppIntents/CaptureTaskIntent.swift` | controller (App Intent) | request-response | `apps/desktop/renderer/quick-entry.tsx` + `apps/desktop/main/windows/quick-entry-window.ts` (capture entry point, draft handling) | role-match (different platform surface, same capture-then-mutate flow) |
| `apps/ios/Sources/KeeplingCore/AppIntents/CompleteTaskIntent.swift` | controller (App Intent) | request-response | `apps/desktop/main/application/outbound-commands.ts` (lifecycle command shape) | role-match |
| `apps/ios/Sources/Keepling/Today/TodayView.swift` | component (SwiftUI view) | request-response | `apps/desktop/renderer/DesktopShell.tsx` (list rendering, row semantics) | role-match |
| `apps/ios/Sources/Keepling/Inbox/InboxView.swift` | component | request-response | `apps/desktop/renderer/DesktopShell.tsx` | role-match |
| `apps/ios/Sources/Keepling/Detail/TaskDetailView.swift` | component | request-response | `apps/web/src/features/tasks/ConflictResolver.tsx` (structured conflict presentation semantics to re-express, not port) | partial-match (semantics only) |
| `apps/ios/Sources/Keepling/Capture/CaptureSheet.swift` | component | request-response | `apps/desktop/renderer/quick-entry.tsx` (durable draft, discard-confirmation flow) + `apps/web/src/features/capture/QuickCapture.tsx` | role-match |
| `apps/ios/Sources/Keepling/SyncRecovery/BottomAccessoryView.swift` | component | event-driven | `apps/desktop/renderer/SyncStatusRow.tsx` (hierarchical priority rendering of presentation summary) | exact (same priority-ordering consumer of the presentation projection) |
| `apps/ios/Sources/Keepling/SyncRecovery/SyncRecoverySheet.swift` | component | request-response | `apps/web/src/features/recovery/RecoveryStrip.tsx` (persistent recovery-action presentation semantics) | partial-match (semantics only, per canonical_refs "worth reading, not porting") |
| `apps/ios/Sources/Keepling/DesignTokens/GeneratedTokens.swift` (D-46 emitter output) | config (generated) | transform | `packages/design-tokens/css.css` (committed generated CSS output from `tokens.json`) | exact (same source-of-truth-to-platform-emission precedent; the emitter script itself has no committed analog — see "No Analog Found") |
| `apps/ios/Tests/KeeplingCoreTests/VectorConformanceTests.swift` | test | batch | `apps/desktop/test/application/sync-vectors.test.ts` | exact |
| `apps/ios/Tests/KeeplingCoreTests/DecodeRoundTripTests.swift` (D-14) | test | transform | `apps/desktop/test/application/sync-vectors.test.ts` (vector-driven fixture loop) + `tooling/check-contracts.mjs` (`validateMutation`/`validateAcknowledgement` structural validation) | role-match |
| `apps/ios/Tests/KeeplingCoreTests/UndoReconciliationTests.swift` | test | event-driven | `apps/desktop/test/application/undo-reconciliation.test.ts` | exact |
| `apps/ios/Tests/StorageTests/CrashRecoveryTests.swift` (G3 SIGKILL injection) | test | file-I/O | `apps/desktop/test/store/migrations-faults.test.ts` (fault-injection fixture pattern) + `apps/desktop/test/store/outbox-transmission.test.ts` (monotonic-state assertions) | role-match |
| `apps/ios/Tests/StorageTests/MigrationLedgerTests.swift` (G4) | test | file-I/O | `apps/desktop/test/store/outbox-state-migration.test.ts` (checksum-drift-style migration fixture) | role-match |
| `apps/ios/Tests/KeeplingUITests/CoreLoopTests.swift` | test | request-response | `apps/desktop/test/e2e/daily-loop.spec.ts` | exact (Playwright→XCUITest re-expression) |
| `apps/ios/Tests/KeeplingUITests/AccessibilityAuditTests.swift` | test | request-response | `apps/desktop/test/e2e/accessibility.spec.ts` + `apps/desktop/test/e2e/appearance-matrix.spec.ts` | exact |
| `apps/ios/Tests/KeeplingUITests/SyncStateMatrixTests.swift` | test | request-response | `apps/desktop/test/application/state-matrix.test.tsx` + `apps/desktop/test/e2e/sync-recovery.spec.ts` | exact |
| `apps/ios/Tests/AppIntentsTests/CaptureIntentTests.swift` | test | request-response | `apps/desktop/test/application/quick-entry-draft.test.ts` (draft/capture behavioral assertions, different entry surface) | role-match |
| `tooling/verify-ios-phase.mjs` (phase-gate entry point) | utility/config | batch | `tooling/verify-desktop-phase.mjs` | exact |
| `tooling/verify-real-stack-ios.mjs` or the physical-device sub-lane | utility | request-response | `tooling/verify-real-stack-desktop.mjs` | exact |
| `packages/contracts/vectors/manifest.json` (D-15 cross-consumer gate) | config | CRUD | `packages/contracts/schemas/sync-state-machine.schema.json` (closed-vocabulary precedent) + `tooling/check-contracts.mjs` (`validateSyncVectors`, set-equality-of-case-names style checks) | role-match (new file, but the enforcing-script pattern is exact) |
| `package.json` (root — new `ios:*` script names) | config | batch | root `package.json`'s existing `*:desktop` script family (`dev:desktop`, `test:desktop`, `verify:desktop:real-stack`, `package:desktop`) | exact |

## Pattern Assignments

### `apps/ios/Sources/KeeplingCore/Storage/Migrations/0001_initial.sql` (migration, CRUD)

**Analog:** `apps/desktop/migrations/0001_initial.sql` (tracked; verified via `git ls-files`)

**Full DDL to mirror line-for-line** (11 `CREATE TABLE ... STRICT` statements — RESEARCH.md's Open Question 2 already flags that D-35's prose "nine tables" undercounts the actual desktop schema by 2; carry all 11 unless the planner explicitly re-scopes `last_local_action` for iOS's different undo-persistence shape per D-30):

```sql
CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY,
  checksum TEXT NOT NULL CHECK (length(checksum) = 64),
  applied_at TEXT NOT NULL
) STRICT;

CREATE TABLE namespace_metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
) STRICT;

CREATE TABLE canonical_shadow (
  entity_id TEXT PRIMARY KEY,
  snapshot_json TEXT NOT NULL CHECK (json_valid(snapshot_json))
) STRICT;

CREATE TABLE visible_projection (
  task_id TEXT PRIMARY KEY,
  title TEXT NOT NULL CHECK (length(title) > 0),
  sync_status TEXT NOT NULL CHECK (sync_status IN ('saved_on_this_mac', 'synced')),
  notes TEXT NOT NULL DEFAULT '',
  completed_at TEXT,
  trashed_at TEXT,
  planned INTEGER NOT NULL DEFAULT 0 CHECK (planned IN (0, 1))
) STRICT;
-- ... immutable_commands, mutation_journal, mutation_dependencies, outbox,
-- sync_cursor, conflicts, last_local_action follow identically; see the
-- source file for the remaining 7 tables.
```

**What carries over:** every table name, column, `CHECK` constraint, and foreign key exactly as written (this is the entire point of D-03 "mirror verbatim"). The `sync_status` enum value `'saved_on_this_mac'` must be renamed for iOS copy purposes only in the *presentation* layer (D-43's `this Mac`→`this iPhone` substitution is a copy-layer concern, not a schema concern) — do **not** rename the stored enum value itself unless the planner explicitly decides the stored string should read `saved_on_this_iphone`; either is defensible, but it must be a stated decision, not a silent copy/schema conflation.

**What must differ (Swift/GRDB):** GRDB's `DatabaseMigrator.registerMigration(_:)` takes a closure, not a bare `.sql` file the way `NodeSqliteLocalStore` does — so the DDL text above is either embedded as a Swift multi-line string per migration or read from a bundled resource *at test/build time only* via the same `#filePath`-relative resolution D-15 mandates for vectors (never a SwiftPM `.copy` resource, per Pattern 1 in RESEARCH.md). GRDB's migrator itself tracks applied versions in its own internal bookkeeping table by default; because D-04 G4 requires an **app-owned** `schema_migrations(version, checksum, applied_at)` ledger with checksum-drift rejection (not GRDB's default), the checksum-and-ledger logic in `#applyMigration` below must be reimplemented on top of GRDB's raw `Database` access inside each `registerMigration` closure — GRDB's own migrator is used for *ordering and idempotent apply*, not as the source of truth for the checksum contract.

---

### `apps/ios/Sources/KeeplingCore/Storage/Migrations/0002_outbox_state.sql` (migration, CRUD)

**Analog:** `apps/desktop/migrations/0002_outbox_state.sql`

**Pattern to copy — the WHY-comment convention and the monotonic-state contract itself:**
```sql
-- WHY THIS EXISTS
--   queued     The bytes have never been handed to the transport. This is
--              the ONLY state an undo may drop.
--   in_flight  ... Not droppable, and not re-selected for push while a
--              request is live.
--   uncertain  ... Not droppable, but still pushable: a retransmission
--              carries the SAME immutable bytes under the same mutation
--              identity and fingerprint, and the server answers
--              `already_satisfied` if the first attempt landed.
--
-- The transitions are deliberately MONOTONIC. A row that leaves `queued`
-- never returns to it...

ALTER TABLE outbox
  ADD COLUMN state TEXT NOT NULL DEFAULT 'queued'
  CHECK (state IN ('queued', 'in_flight', 'uncertain'));

UPDATE outbox SET state = 'uncertain';
```
**What carries over:** the exact three-state vocabulary, the monotonicity rule, and — critically — the doc-comment style explaining *why* a design choice exists inline in the migration file. This monotonic outbox state is exactly what D-34's "compensating action, never local retraction" undo semantics depends on; reimplement the state machine identically in GRDB, asserted structurally (a test that tries an illegal `uncertain`→`queued` transition and asserts it is rejected), per RESEARCH.md's "Correctness properties are made structural where possible."
**What must differ:** none — this is schema and policy, entirely language-neutral.

---

### `apps/ios/Sources/KeeplingCore/Storage/GRDBLocalStore.swift` (service, CRUD + transaction)

**Analog:** `apps/desktop/store-worker/local-store.ts` (`NodeSqliteLocalStore` class)

**Imports/setup pattern** (`local-store.ts:172-185`):
```typescript
class NodeSqliteLocalStore {
  ...
  constructor(options: LocalStoreOptions) {
    ...
    this.#database.exec('PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA synchronous = FULL;')
    this.#applyMigration(options.migrationPath)
```
**What carries over:** open the connection, set every PRAGMA (`foreign_keys`, `journal_mode=WAL`, `synchronous=FULL`) **before** running migrations, and run the migration ledger inline in the constructor so a store can never be used un-migrated. GRDB's `Configuration.prepareDatabase` closure is the direct equivalent hook (per RESEARCH.md's Open Question 3) and per-`DatabasePool`-connection PRAGMA application must be verified for every reader connection, not just the writer, to satisfy D-04 G1 "verified per connection."

**Single-transaction acceptance pattern** (`local-store.ts:791-814`, the `editTask` method — this is the canonical shape every mutating method in the file repeats):
```typescript
editTask(command: EditTaskCommand, outbound?: SyncMutation): WorkspaceSnapshot {
  this.#assertNotFenced()
  ...
  this.#database.exec('BEGIN IMMEDIATE')
  try {
    const before = this.#requireProjectionRow(command.taskId)
    this.#recordLastAction(command.taskId, before, outbound?.mutationId ?? null)
    this.#database.prepare(`UPDATE visible_projection SET title = ?, notes = ? WHERE task_id = ?`)
      .run(title, command.notes, command.taskId)
    // O-41: the outbound intent joins the SAME transaction as the local
    // projection write. Two transactions in a row would satisfy neither
    // D-03 nor the person, who has already been told the change is safe.
    if (outbound) this.#enqueueOutbound(outbound)
    this.#database.exec('COMMIT')
  } catch (error) {
    this.#database.exec('ROLLBACK')
    throw error
  }
  return this.snapshot()
}
```
**What carries over:** the invariant, not the syntax — every local mutation (edit/lifecycle/moveToday/captureTask) is `assertNotFenced → BEGIN IMMEDIATE → write projection + journal + dependency edges + enqueue outbox row (same transaction) → COMMIT`, with `ROLLBACK` on any thrown error, and `local_saved` is reported to the caller only after `COMMIT` returns (D-36 inherited as D-03/D-36 here). This is D-04 G2's exact acceptance gate.
**What must differ:** GRDB replaces the bare `exec('BEGIN IMMEDIATE')`/`try`/`catch`/`ROLLBACK` idiom with `try dbPool.write { db in ... }` (GRDB wraps `BEGIN`/`COMMIT`/`ROLLBACK` and re-throws automatically on any thrown error inside the closure) — but D-04 G2 explicitly requires this be **asserted through commit/rollback hooks, not inferred**, so the executor must additionally register `db.afterNextTransaction(onCommit:onRollback:)` (or equivalent) in the adversarial test suite to prove the single-transaction claim structurally, exactly as G2 demands, rather than trusting GRDB's closure semantics silently.

**Settlement / terminal-acknowledgement pattern (G8)** (`local-store.ts:633-696`):
```typescript
acknowledge(acknowledgement: SyncAcknowledgement): WorkspaceSnapshot {
  this.#database.exec('BEGIN IMMEDIATE')
  try {
    const pending = this.#database.prepare(`
      SELECT immutable_commands.fingerprint, immutable_commands.task_id
      FROM outbox JOIN immutable_commands USING (mutation_id)
      WHERE outbox.mutation_id = ?
    `).get(acknowledgement.mutationId)
    if (pending === undefined) {
      const terminal = this.#database.prepare(`SELECT outcome FROM mutation_journal WHERE mutation_id = ?`)
        .get(acknowledgement.mutationId)
      if (terminal?.outcome === acknowledgement.outcome) { this.#database.exec('COMMIT'); return this.snapshot() }
      throw new Error('unknown acknowledgement mutation')
    }
    if (pending.fingerprint !== acknowledgement.fingerprint) throw new Error('acknowledgement fingerprint mismatch')
    // ... upsert canonical_shadow + projection only on accepted/already_satisfied,
    // retain undo availability, write terminal outcome to mutation_journal,
    // DELETE FROM outbox WHERE mutation_id = ? (terminal for every outcome)
    this.#database.exec('COMMIT')
  } catch (error) { this.#database.exec('ROLLBACK'); throw error }
  return this.snapshot()
}
```
**What carries over exactly:** this is D-04 G8 verbatim — verify mutation identity + fingerprint match, apply canonical/conflict state only on a successful outcome (never blank fields from a partial conflict/rejection body), terminalize the journal, delete the exact outbox row, and treat a duplicate replay (row already absent from outbox, terminal outcome already matches) as a **no-op**, not an error. This is the single most load-bearing excerpt for D-09's replay-no-op proof and IOS-02.
**What must differ:** none structurally — GRDB transaction wrapping only; the SQL and the branching logic port as-is.

---

### `apps/ios/Sources/KeeplingCore/Storage/GRDBLocalStore.swift` — migration ledger (G4)

**Analog:** `apps/desktop/store-worker/local-store.ts:1130-1220` (`#collectMigrations`, `#applyMigration`)

```typescript
#applyMigration(migrationPath: string | URL): void {
  const migrations = this.#collectMigrations(migrationPath)
  for (const migration of migrations) {
    const contents = readFileSync(migration.path, 'utf8')
    const checksum = createHash('sha256').update(contents).digest('hex')
    if (ledgerPresent()) {
      const applied = this.#database.prepare(`SELECT checksum FROM schema_migrations WHERE version = ?`)
        .get(migration.version)
      if (applied !== undefined) {
        if (applied.checksum !== checksum) {
          throw new Error(`migration checksum mismatch for version ${migration.version}`)
        }
        continue
      }
    }
    this.#database.exec('BEGIN IMMEDIATE')
    try {
      this.#database.exec(contents)
      this.#database.prepare(`INSERT INTO schema_migrations(version, checksum, applied_at) VALUES (?, ?, ?)`)
        .run(migration.version, checksum, new Date().toISOString())
      this.#database.exec('COMMIT')
    } catch (error) { this.#database.exec('ROLLBACK'); throw error }
  }
  // ahead-of-ledger check: a version the CURRENT build carries no migration
  // for means a NEWER Keepling wrote this database — refuse to open it.
}
```
**What carries over:** forward-only, checksum-bound, contiguous-from-1 migration ledger; a checksum mismatch **throws and halts** rather than repairing or resetting (this is exactly D-04 G4's "reject checksum drift and never auto-resets," and RESEARCH.md's build-time test proving `eraseDatabaseOnSchemaChange` appears nowhere in the tree targets this exact function). The "ahead of ledger" check (a version this build has no migration file for) is a defect class Swift must also guard against — a store migrated by a newer Keepling build must refuse to open on an older one.
**What must differ:** GRDB's `DatabaseMigrator.registerMigration(_:)` API does not naturally expose "read the file, hash it, compare against a stored checksum, then apply" as a single primitive — the executor must write this checksum-comparison logic explicitly inside each migration closure (or in a thin wrapper around `DatabaseMigrator`), because GRDB's own internal migration-tracking table is not the D-37 `schema_migrations(version, checksum, applied_at)` ledger this phase requires as its externally-provable contract.

---

### `apps/ios/Sources/KeeplingCore/Sync/SyncReducer.swift` (service/reducer, event-driven)

**Analog:** `apps/server/lib/keepling/application/sync/reference_model.ex`

**Imports/module-doc pattern** (`reference_model.ex:1-28`):
```elixir
defmodule Keepling.Application.Sync.ReferenceModel do
  @moduledoc """
  Persistence-neutral reference reducer for Keepling offline synchronization.
  The reducer keeps canonical shadow, visible optimistic projection, mutation
  journal, dependency metadata, and outbox as separate durable values. It uses
  JSON-compatible string-keyed maps so the same vectors can be implemented by
  the later desktop and iPhone stores without sharing persistence records.
  """
  @terminal_outcomes ~w(accepted already_satisfied rejected stale conflict)
  @successful_outcomes ~w(accepted already_satisfied)
  @maximum_pull_changes 50
  @maximum_ready_pushes 25

  def local_accept(state, mutation) when is_map(state) and is_map(mutation) do
    with :ok <- validate_mutation(mutation),
         :ok <- validate_dependencies_exist(state, mutation["dependencies"]),
         false <- Map.has_key?(state["journal"], mutation["mutation_id"]) do
      ...
      {:ok, "local_saved", next}
    else
      true -> {:error, :mutation_identity_reused, state}
      {:error, reason} -> {:error, reason, state}
    end
  end
```
**What carries over:** the state shape (`canonical_shadow`, `visible`, `journal`, `dependencies`, `outbox`, `cursor`, `fence` as separate named values, never one opaque blob), the terminal-outcome closed set, the pull/push bound constants (`@maximum_pull_changes 50`, `@maximum_ready_pushes 25` — these numeric bounds are contract-level and must match exactly, not be re-derived), and the `{:ok, ...}`/`{:error, reason, state}` idempotent-and-total function shape (a Swift `Result<T, SyncReducerError>` return, never a thrown error, keeps the reducer pure and directly comparable state-for-state against the Elixir and TypeScript implementations for the same vector). This is literally D-10's requirement: the Swift reducer is not "inspired by" this file, it must **agree with it** on every vector case, which is what `VectorConformanceTests.swift` proves.
**What must differ:** Elixir's `with`/tagged-tuple idiom becomes Swift's `Result`/`throws` idiom; Elixir's structural map (`state["journal"]`) becomes a Swift `struct SyncReducerState` with named, typed fields — the mapping should be 1:1 field-for-field, not restructured, so a vector fixture can be traced through both implementations by eye during debugging.

---

### `apps/ios/Sources/KeeplingCore/Transport/KeeplingSyncAdapter.swift` (service/adapter, request-response)

**Analog:** `apps/desktop/main/adapters/sync.ts` (`KeeplingSyncAdapter` class)

**Imports pattern** (`sync.ts:1-19`):
```typescript
import { createHash } from 'node:crypto'
import type { components } from '../../../../packages/contracts/generated/keepling.ts'
import type { PullPage, SyncAcknowledgement, SyncNamespace, SyncPort, SyncSnapshot, SyncUndoAvailability } from '../application/DesktopApplication.ts'
import { SYNC_FAILURE_AUTHENTICATION_REQUIRED, SyncUnreachableError } from '../application/sync-reachability.ts'
import { classifyServerRefusal, type ServerRefusal } from './server-refusal.ts'
```
**Core pattern — classifying a server ANSWER vs. an unreachable transport** (`sync.ts:339-384`, `#json`):
```typescript
let response: Response
try {
  response = await this.#fetch(url, { ...init, headers, signal: controller.signal })
} catch (error) {
  // O-30: THIS is the only line that can tell "unreachable" from "rejected"
  throw new SyncUnreachableError('the Keepling server could not be reached', { cause: error })
}
// Everything below ran because the server ANSWERED.
const value = await response.json()
if (!response.ok) {
  throw new SyncRefusedError(problem.code ?? `server_${response.status}`, response.status, value)
}
return value
```
**Refusal-to-acknowledgement classification** (`sync.ts:76-113`, `settleClassified`/`settleRefusal`):
```typescript
const settleClassified = (refusal, identity) => {
  if (refusal === null || refusal.kind === 'authentication_required') return null
  if (identity.taskId === null && refusal.kind === 'conflict') return null
  if (refusal.kind === 'rejected') return { fingerprint, mutationId, outcome: 'rejected', snapshot: { id, rejection_code: refusal.code } }
  return { fingerprint, mutationId, outcome: 'conflict', snapshot: { affected_fields, conflict_id, id, ...revision, ...title } }
}
```
**What carries over:** the entire "a thrown-fetch is unreachable, a non-2xx response is a decided refusal, and a decided refusal (409 conflict, 422 rejection, even the 200 undo-no-change special case) is mapped into the SAME `SyncAcknowledgement` shape the reducer already understands" architecture. This is the exact mechanism that fixes O-38/O-30-class bugs (infinite retry of a decided command). The `push`/`pull`/`bootstrap`/`lookup`/`revoke` method surface maps directly onto the generated Swift client's operations plus one hand-written mapper layer per D-12.
**What must differ:** `URLSession` + `async`/`await` replaces `fetch`; the generated Swift DTOs (from `swift-openapi-generator`) replace `components['schemas'][...]` type imports from `keepling.ts`; HTTPS-only enforcement (`sync.ts:216-219`, rejecting non-HTTPS unless `127.0.0.1`/`localhost`) must be reimplemented identically in the Swift transport's initializer — do not silently drop this guard.

---

### `apps/ios/Sources/KeeplingCore/Presentation/SyncPresentation.swift` (service, transform)

**Analog:** `apps/desktop/main/application/presentation.ts`

**Core pattern — one pure function deriving the whole presentation summary** (`presentation.ts:97-153`):
```typescript
type DesktopPresentationInput =
  | { kind: 'healthy'; lastSuccessfulContact?: string }
  | { kind: 'updating'; startedAt: number }
  | { kind: 'retryable_failure'; pendingCount?: number }
  | { kind: 'conflict'; affectedCount?: number }
  ... // closed union, one variant per D-43 state

const GRACE_PERIOD_MS = 3_000
const MAXIMUM_PRESENTED_COUNT = 99

const deriveSummary = (input, nowMs) => {
  switch (input.kind) {
    case 'updating':
      if (nowMs - input.startedAt < GRACE_PERIOD_MS) {
        return { kind: 'healthy', ... } // absorbed into healthy before the grace period elapses
      }
      return { actions: [action('inspect', 'Sync & Recovery')], copy: 'Updating…', ... }
    case 'conflict':
      return { actions: [action('review_conflict', 'Review Conflict')], copy: 'This task changed somewhere else. Choose what to keep. Other tasks can continue.', ... }
    ...
  }
}

const deriveDesktopPresentation = (input, sequence, nowMs = Date.now()) => {
  if (!Number.isSafeInteger(sequence) || sequence < 0) throw new Error('presentation sequence is invalid')
  const summary = deriveSummary(input, nowMs)
  return { sequence, summary, surfaces: { panel: summary, row: summary, shell: summary } }
}
```
**What carries over:** this IS D-41's "single authoritative presentation projection" — a closed, exhaustive input union (one variant per D-43 state), a pure deriving function with an injectable clock (`nowMs`), the grace-period-absorption rule (an `updating` state younger than `GRACE_PERIOD_MS` presents as `healthy`), bounded counts (`MAXIMUM_PRESENTED_COUNT = 99`), and every surface (`panel`/`row`/`shell` on desktop; the iOS equivalents are the bottom accessory, per-task inline row, and `Sync & Recovery` sheet) deriving from the SAME summary object rather than each surface computing its own truth. The exact copy strings (`'Couldn't reach the server. Your changes stay on this Mac.'`) are the direct source for D-43's iPhone copy table, substituting `this Mac`→`this iPhone` per the locked substitution.
**What must differ:** the Swift version becomes an `enum SyncPresentationInput` with associated values (Swift's closed-union idiom), and the `AccessibilityNotification.Announcement` emission (D-42) is a new iOS-specific consumer of this same summary that has no desktop analog — debounce it at this projection layer, not per-view, exactly as D-42 specifies, using the desktop's "derive once, distribute to every surface" shape as the template for "derive once, announce once."

---

### `apps/ios/Sources/Keepling/SyncRecovery/BottomAccessoryView.swift` (component, event-driven)

**Analog:** `apps/desktop/renderer/SyncStatusRow.tsx`

**What carries over:** `SyncStatusRow.tsx` is the desktop consumer of exactly the presentation summary produced above — it renders `summary.copy`, `summary.actions`, and `summary.count` without inferring any synchronization truth of its own (D-41's UI-infers-nothing rule already proven on desktop). Read this file for the consumption pattern (how a dumb view renders a summary object) before writing `BottomAccessoryView.swift`; do not re-derive priority ordering in SwiftUI — the priority ordering (actionable exception > undoable action > transient work) belongs entirely in `SyncPresentation.swift`, matching D-38's requirement and the desktop's existing division of labor.
**What must differ:** the RESEARCH.md Pitfall 1 constraint — `tabViewBottomAccessory` cannot currently be made visually absent via conditional content (Apple DTS-confirmed regression as of iOS 26.1) — has **no desktop analog** at all, because desktop chrome has no equivalent reserved-space problem. This view must resolve Open Question 1 from RESEARCH.md (spike `isEnabled:` vs. conditional content, assert on frame/hit-test region, not content) before the "absent when healthy" claim can be trusted; do not assume the desktop's simpler "render nothing" pattern transfers unchanged.

---

### `apps/ios/Tests/KeeplingCoreTests/VectorConformanceTests.swift` (test, batch)

**Analog:** `apps/desktop/test/application/sync-vectors.test.ts`

**Full pattern to mirror** (`sync-vectors.test.ts:1-96`):
```typescript
import vectors from '../../../../packages/contracts/vectors/sync.json'

describe('Phase 2 synchronization vectors', () => {
  for (const vector of vectors.cases) {
    it(`matches ${vector.name}`, async () => {
      const root = mkdtempSync(...)
      let store = openStore(databasePath)
      const observedReady: string[] = []
      for (const action of vector.actions) {
        switch (action.type) {
          case 'local_accept': store.acceptMutation(vectorMutation(action.mutation)); break
          case 'pull': store.applyPull({...}); break
          case 'ready_pushes': observedReady.push(...store.readyMutations().map(m => m.mutationId)); break
          case 'acknowledge': store.acknowledgeSync({...}); break
          case 'fence': store.setSyncFence(action.reason); break
          case 'relaunch': store.close(); store = openStore(databasePath); break
        }
      }
      expect(store.syncState()).toMatchObject({ cursor: vector.expect.cursor, outbox: vector.expect.outbox })
      expect(observedReady).toEqual(vector.expect.ready_pushes)
      store.close()
    })
  }
})
```
**What carries over exactly:** load the vector file directly from the source tree (here via a relative import; for Swift use the `#filePath`-derived repo-root walk from RESEARCH.md Pattern 1, never a `.copy` resource per D-15), drive a real store instance (not a mock) through every action type in a per-case `switch`, and assert against `vector.expect` structurally. Critically: **the `relaunch` action closes and reopens the real store** — this is the crash/relaunch durability proof riding inside the vector harness itself, which the Swift `StorageTests` should reuse rather than reinvent as a separate mechanism. D-15 additionally requires `Set(executedCaseNames) == Set(json.cases)` — the desktop file doesn't currently assert that explicitly (its `for` loop happens to cover every case since it iterates `vectors.cases` directly), but the Swift harness must add the explicit set-equality assertion per D-15, which is a **strengthening**, not a straight port.
**What must differ:** `vitest`'s `describe`/`it`/`expect` becomes XCTest's `XCTestCase`/`func test...()`/`XCTAssertEqual`; the switch-per-action-type shape is identical in Swift.

---

### `tooling/verify-ios-phase.mjs` (utility/config, batch)

**Analog:** `tooling/verify-desktop-phase.mjs`

**Core pattern — `runLane`, the anti-vacuous fail-fast contract** (`verify-desktop-phase.mjs:53-95`):
```javascript
/**
 * Runs one lane's command, then hands raw stdout/stderr to `parse` to
 * extract a positive case count. `parse` MUST throw or return a
 * non-positive count for output it cannot make sense of -- there is no
 * "assume it passed" fallback anywhere in this file.
 */
const runLane = ({ command, args, cwd, env, name, parse, seed, trackedInputPaths }) => {
  const result = spawnSync(command, args, { cwd: cwd ?? repositoryRoot, encoding: 'utf8', env: { ...process.env, ...env } })
  const inputDigest = trackedInputPaths ? inputDigestFor(trackedInputPaths) : 'n/a'
  let cases = 0, parseError = null
  try { cases = parse(stdout, stderr, result.status) } catch (error) { parseError = error.message }
  const passed = result.status === 0 && !result.error && parseError === null && Number.isFinite(cases) && cases > 0
  results.push({ cases, durationMs, inputDigest, name, passed, seed: seed ?? 'n/a' })
  console.log(`LANE name=${name} status=${passed ? 'PASS' : 'FAIL'} cases=${cases} duration_ms=${durationMs} input_digest=${inputDigest} seed=${seed ?? 'n/a'}`)
  if (!passed) { anyFailed = true; /* surface stdout/stderr tail */ }
}
```
**Input-digest provenance binding** (`verify-desktop-phase.mjs:31-51`):
```javascript
const gitLsFiles = (paths) => {
  const result = spawnSync('git', ['-C', repositoryRoot, 'ls-files', '-z', ...paths], { encoding: 'utf8' })
  return result.stdout.split('\0').filter(Boolean).sort()
}
const inputDigestFor = (paths) => {
  const files = gitLsFiles(paths)
  const digest = createHash('sha256')
  for (const relativePath of files) { digest.update(`${relativePath}\0`); digest.update(readFileSync(...)); digest.update('\0') }
  return digest.digest('hex').slice(0, 16)
}
```
**What carries over exactly:** every lane must report a name, a positive case count, a duration, and a `git ls-files`-derived input digest; a lane that cannot report a positive count is a **FAILURE**, never a silently-skipped green — this is precisely the discipline D-24 demands ("nothing in Phase 4 may depend on CI existing," so this script IS the CI). Reuse `spawnSync` to invoke `xcodebuild test`/`devicectl`, parse XCTest's own summary line the way `vitestSummary`/`playwrightSummary` parse theirs, and use `gitLsFiles` for the same tracked-input digest binding — this is also the direct mechanical precedent for D-21's provenance-plus-attestation requirement (the digest concept generalizes to `KeeplingBuildDigest`).
**What must differ:** the parse functions need an `xcodebuildSummary`-equivalent (XCTest's `** TEST SUCCEEDED **` / `Executed N tests` output format) alongside `vitestSummary`/`playwrightSummary`; the physical-device sub-lane additionally needs the `devicectl`-vs-`xcodebuild` UDID resolution RESEARCH.md Pitfall 3 warns about, which has no desktop equivalent (desktop has no second identifier space).

---

### `package.json` (root, config, batch) — new `ios:*` scripts

**Analog:** the existing `*:desktop` script family (`package.json:5-19`)

```json
"dev:desktop": "pnpm --dir apps/desktop dev",
"test:desktop": "pnpm --dir apps/desktop test",
"test:desktop:e2e": "pnpm --dir apps/desktop test:e2e",
"verify:desktop:real-stack": "node tooling/verify-real-stack-desktop.mjs",
"package:desktop": "pnpm --dir apps/desktop package",
```
**What carries over:** the naming convention `<verb>:<platform>[:<qualifier>]` and the "desktop tooling scripts call `node tooling/*.mjs` directly, not through a workspace filter" pattern for cross-cutting phase gates (`verify:desktop:real-stack`, `verify:desktop:reproducible`). For iOS: `verify:ios:phase` → `node tooling/verify-ios-phase.mjs`, `verify:ios:real-stack` → `node tooling/verify-real-stack-ios.mjs` mirror this exactly.
**What must differ:** `apps/ios` is explicitly **outside the pnpm workspace graph** (RESEARCH.md, CONTEXT.md Integration Points) — so unlike `dev:desktop`/`test:desktop`, there must be **no** `pnpm --dir apps/ios ...` delegation. Every iOS script invokes `xcodebuild`/`xcodegen`/`devicectl` directly via `spawnSync` inside a `tooling/*.mjs` wrapper, never `pnpm --filter`/`pnpm --dir`. This is a deliberate divergence from the desktop convention, not an oversight — name it explicitly in the plan so the executor doesn't "fix" it by adding a phantom `apps/ios/package.json`.

## Shared Patterns

### One-transaction local acceptance (D-03/D-04 G2)
**Source:** `apps/desktop/store-worker/local-store.ts` — every mutating method (`editTask:791`, `applyLifecycle:816`, `applyMoveToday:847`, `acknowledge:633`, `undoLastLocalAction:901`, `resolveConflict:947`)
**Apply to:** every method on `GRDBLocalStore.swift`
```typescript
this.#database.exec('BEGIN IMMEDIATE')
try {
  // read-before-write, then every write (projection + journal + dependencies + outbox), same transaction
  this.#database.exec('COMMIT')
} catch (error) {
  this.#database.exec('ROLLBACK')
  throw error
}
```
In GRDB: `try dbPool.write { db in ... }`, with G2's commit/rollback-hook assertion added in tests, not inferred from the closure's absence of a thrown error.

### Fencing check before any local write (D-03 namespace fencing)
**Source:** `apps/desktop/store-worker/local-store.ts:1102-1107` (`#assertNotFenced`)
```typescript
#assertNotFenced(): void {
  const fenced = this.#database.prepare(`SELECT value FROM namespace_metadata WHERE key = 'sync_fence'`).get()
  if (fenced) throw new Error(`local writes are fenced: ${fenced.value}`)
}
```
**Apply to:** every write-path method in `GRDBLocalStore.swift`, called first, before the transaction opens.

### Transport unreachable-vs-refused classification (O-30/O-38)
**Source:** `apps/desktop/main/adapters/sync.ts:339-384` (`#json`)
**Apply to:** `KeeplingSyncAdapter.swift` — a thrown `fetch`/`URLSession` error is `unreachable` (offline row); a non-2xx **answered** response is a decided refusal, classified through one function (`settleClassified`) into the same `SyncAcknowledgement` shape the reducer consumes, so a 409/422 stops being retried forever.

### Terminal-acknowledgement idempotent settlement (D-04 G8/D-09 replay-no-op)
**Source:** `apps/desktop/store-worker/local-store.ts:633-745` (`acknowledge`)
**Apply to:** the Swift store's equivalent settlement method — verify mutation identity + fingerprint, apply canonical state only on success, delete the exact outbox row, treat "row already gone + terminal outcome already matches" as a no-op success, never an error. This IS the D-09 adversarial fixture's proof mechanism.

### Single authoritative presentation projection (D-41)
**Source:** `apps/desktop/main/application/presentation.ts` (`deriveDesktopPresentation`)
**Apply to:** `SyncPresentation.swift`, consumed identically by `BottomAccessoryView`, per-task inline rows, and `SyncRecoverySheet` — one pure function, one summary object, no view infers its own truth.

### Phase-gate anti-vacuous lane contract (D-45/D-46 desktop; carries to iOS D-20/D-24)
**Source:** `tooling/verify-desktop-phase.mjs` (`runLane`, `inputDigestFor`)
**Apply to:** `tooling/verify-ios-phase.mjs` — every lane reports name/cases/duration/digest, a lane reporting zero or unparseable output is a FAILURE, and tracked-input digests bind evidence to source per `git ls-files`.

### Committed-generated-output precedent (D-12/D-46)
**Source:** `packages/contracts/generated/keepling.ts` (openapi-typescript, committed) and `packages/design-tokens/css.css` (tokens.json, committed CSS emission)
**Apply to:** `apps/ios/Sources/KeeplingCore/Transport/Generated/*.swift` (swift-openapi-generator, committed) and `apps/ios/Sources/Keepling/DesignTokens/GeneratedTokens.swift` (new Swift emitter, committed) — generated output is diff-reviewable, deterministic, and regenerated-and-diffed in CI (`tooling/check-contracts.mjs`'s `--check` flag on `openapi-typescript` is the direct model for a `swift build`-time or phase-gate diff check on the Swift generator's output).

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `apps/ios/Sources/Keepling/DesignTokens/TokenEmitter` (the Swift-emission script itself, not its output) | utility | transform | No committed script produces `packages/design-tokens/css.css` from `tokens.json` in this repository — it appears to have been hand-authored or generated by a since-removed tool. RESEARCH.md's own `Standard Stack`/`Don't Hand-Roll` sections do not name a solution either. The planner should treat this as a small new utility (JSON→Swift-`enum`/`struct` emitter) with `check-contracts.mjs`'s `--check`-and-diff pattern as its only precedent, not the emission logic itself. |
| `apps/ios/Sources/KeeplingCore/AppIntents/*` (App Intent declaration + `AppIntentsTesting` harness) | controller/test | request-response | No native-target App Intent, Siri, or Shortcuts surface exists anywhere in this repository (desktop and web have no equivalent OS-level intent surface). RESEARCH.md's own Code Example (Pattern 3, citing `developer.apple.com/documentation/AppIntentsTesting`) is the only guidance; there is no in-repo behavioral precedent beyond the capture-then-mutate *semantics* already proven in `apps/desktop/renderer/quick-entry.tsx`. |
| `apps/ios/project.yml` (XcodeGen manifest itself) | config | batch | No XcodeGen/Tuist/`.xcodeproj` precedent exists in this repository at all — `apps/desktop`'s `vite.*.config.ts` family and `forge.config.ts` are the closest role-match (declarative multi-target build config) but are a completely different toolchain with no transferable syntax, only the "one declarative, diffable, committed manifest per build concern" philosophy. |
| Physical-device UDID/`devicectl`-identifier resolution logic | utility | request-response | RESEARCH.md's own Pitfall 3 confirms this is a genuinely new problem with no desktop analog — desktop's Electron packaging/signing lane (`tooling/package-desktop.mjs`, `tooling/smoke-desktop-packaged.mjs`) has no second-identifier-space problem to mirror. |

## Metadata

**Analog search scope:** `apps/desktop/` (all tracked source: `main/`, `renderer/`, `store-worker/`, `preload/`, `migrations/`, `test/`), `apps/server/lib/keepling/application/sync/`, `packages/contracts/` (openapi, generated, schemas, vectors), `packages/design-tokens/`, `tooling/` (all `.mjs`/`.sh` phase-gate and packaging scripts), root `package.json`, `apps/web/src/features/{recovery,tasks,capture}/` (semantics-only, per canonical_refs), `apps/ios/README.md`.
**Files scanned (read in full or by targeted excerpt):** `apps/desktop/migrations/0001_initial.sql`, `0002_outbox_state.sql`, `apps/desktop/store-worker/local-store.ts` (full, 1374 lines), `apps/desktop/main/adapters/sync.ts` (full, 388 lines), `apps/desktop/main/application/presentation.ts` (full, 187 lines), `apps/desktop/test/application/sync-vectors.test.ts` (full, 176 lines), `apps/server/lib/keepling/application/sync/reference_model.ex` (excerpt), `tooling/verify-desktop-phase.mjs` (excerpt, lines 1-120), `tooling/check-contracts.mjs` (full, 263 lines), `tooling/package-desktop.mjs` (excerpt), root `package.json` (full), `packages/design-tokens/tokens.json` + `css.css` (excerpt), `apps/ios/README.md` (full).
**Tracked-source verification command used:** `git ls-files apps/desktop | grep -v '^apps/desktop/\(dist\|out\|dist-harness\)/'` — confirmed every named analog path is tracked source, not a build mirror.
**Pattern extraction date:** 2026-09-04
