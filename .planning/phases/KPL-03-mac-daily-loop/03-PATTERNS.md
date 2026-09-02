# Phase 3: Mac Daily Loop - Pattern Map

**Mapped:** 2026-09-02
**Files analyzed:** 26 proposed new/modified file groups
**Analogs found:** 19 / 26

Phase 3 names directory roots rather than every leaf filename. The file names below freeze the smallest planning-level decomposition implied by `03-CONTEXT.md` D-26–D-38 and `03-RESEARCH.md`'s recommended project structure. A planner may combine adjacent leaves, but must preserve the process, representation, and authority boundaries shown here.

## File Classification

| New/Modified File | Role | Data Flow | Closest Tracked Analog | Match Quality |
|---|---|---|---|---|
| `package.json` | config | batch | `package.json` | exact (modify) |
| `apps/desktop/package.json` | config | batch | `apps/web/package.json` | role-match |
| `apps/desktop/forge.config.ts` | config | batch | `apps/web/vite.config.ts` | partial; no Electron packaging analog |
| `apps/desktop/vite.*.config.ts` | config | transform | `apps/web/vite.config.ts` | role-match |
| `apps/desktop/vitest.config.ts` | config | batch | `apps/web/vitest.config.ts` | exact role |
| `apps/desktop/playwright.config.ts` | config | batch | `apps/web/playwright.config.ts` | role-match |
| `apps/desktop/main/index.ts` | controller/composition | event-driven | none | no Electron lifecycle analog |
| `apps/desktop/main/application/DesktopApplication.ts` | service | request-response + event-driven | `apps/server/lib/keepling/application/sync/reference_model.ex` | data-flow/core-match |
| `apps/desktop/main/application/ports.ts` | provider/model | request-response | `apps/web/src/commands/submission.ts` | partial; ports are new |
| `apps/desktop/main/application/presentation.ts` | model/utility | transform + event-driven | `apps/web/src/commands/submission.ts` | state-machine match |
| `apps/desktop/main/adapters/sync.ts` | service | request-response + batch | `apps/web/src/api/keepling.ts` | role/data-flow match |
| `apps/desktop/main/adapters/credentials.ts` | service | request-response + file-I/O | none | no credential adapter analog |
| `apps/desktop/main/windows/main-window.ts` | controller | event-driven | `apps/web/src/app/AppShell.tsx` | behavior match only |
| `apps/desktop/main/windows/quick-entry-window.ts` | controller | event-driven | `apps/web/src/features/capture/QuickCapture.tsx` | behavior match only |
| `apps/desktop/main/menu.ts` | controller | event-driven | `apps/web/src/app/AppShell.tsx` | semantic-command match only |
| `apps/desktop/preload/contracts.ts` | model/middleware | transform | `packages/contracts/schemas/sync-state-machine.schema.json` | closed-shape match |
| `apps/desktop/preload/index.ts` | middleware/provider | request-response + pub-sub | none | no IPC/preload analog |
| `apps/desktop/renderer/main.tsx` | component/bootstrap | event-driven | `apps/web/src/app/AppShell.tsx` | role-match |
| `apps/desktop/renderer/quick-entry.tsx` | component/bootstrap | request-response | `apps/web/src/features/capture/QuickCapture.tsx` | close behavior match |
| `packages/web-ui/src/ClientFacade.ts` | provider/model | request-response + pub-sub | `apps/web/src/app/AppShell.tsx` props seam | partial; new shared seam |
| `packages/web-ui/src/{workspace,capture,tasks,recovery}/**` | component | request-response + event-driven | `apps/web/src/app/WorkspaceShell.tsx`, `apps/web/src/features/capture/QuickCapture.tsx` | exact presentation role |
| `apps/desktop/store-worker/index.ts` | service/provider | event-driven | none | no worker protocol analog |
| `apps/desktop/store-worker/local-store.ts` | service | CRUD + batch | `apps/server/lib/keepling/application/sync/reference_model.ex` | semantic match; persistence differs |
| `apps/desktop/migrations/0001_initial.sql` + manifest | migration/config | CRUD | none | PostgreSQL migrations are deliberately not reusable |
| `apps/desktop/test/{application,store,ipc}/**` | test | transform + CRUD + request-response | `apps/server/test/keepling/application/sync/reference_model_test.exs`, `apps/web/src/commands/submission.test.ts` | scenario/data-flow match |
| `apps/desktop/test/e2e/**` + `packaged/**` | test | event-driven + file-I/O | `apps/web/e2e/phase1.spec.ts`, `apps/web/playwright.config.ts` | role-match; packaged lane new |

## Pattern Assignments

### `apps/desktop/main/application/DesktopApplication.ts` and `apps/desktop/store-worker/local-store.ts`

**Role/data flow:** service; local CRUD, deterministic transform, batch synchronization.

**Primary analog:** `apps/server/lib/keepling/application/sync/reference_model.ex`

**Separated representation pattern** (lines 1-29):

```elixir
@moduledoc """
Persistence-neutral reference reducer for Keepling offline synchronization.

The reducer keeps canonical shadow, visible optimistic projection, mutation
journal, dependency metadata, and outbox as separate durable values. It uses
JSON-compatible string-keyed maps so the same vectors can be implemented by
the later desktop and iPhone stores without sharing persistence records.
"""

def new do
  %{
    "canonical_shadow" => %{},
    "visible" => %{},
    "journal" => %{},
    "dependencies" => %{},
    "outbox" => [],
    "cursor" => nil,
    "fence" => nil
  }
end
```

Copy the separation and closed vocabulary, not the Elixir representation. `DesktopApplication` uses storage-neutral models; the worker owns distinct SQLite records and explicit mappers.

**Local acceptance pattern** (lines 31-59):

```elixir
with :ok <- validate_mutation(mutation),
     :ok <- validate_dependencies_exist(state, mutation["dependencies"]),
     false <- Map.has_key?(state["journal"], mutation["mutation_id"]) do
  mutation_id = mutation["mutation_id"]
  journal_entry = %{
    "accepted_at" => mutation["accepted_at"],
    "command_bytes" => mutation["command_bytes"],
    "fingerprint" => mutation["fingerprint"],
    "outcome" => "pending",
    "resource_keys" => mutation["resource_keys"]
  }

  next =
    state
    |> put_in(["journal", mutation_id], journal_entry)
    |> put_in(["dependencies", mutation_id], mutation["dependencies"])
    |> Map.update!("outbox", &(&1 ++ [mutation]))
    |> replay_visible()

  {:ok, "local_saved", next}
end
```

The SQLite implementation must put projection, immutable bytes/fingerprint, journal, dependency edges, and outbox into one `BEGIN IMMEDIATE` transaction and emit `local_saved` only after `COMMIT`.

**Exact acknowledgement and error-preserves-state pattern** (lines 96-110, 132-169):

```elixir
case Enum.find(state["outbox"], &(&1["mutation_id"] == mutation_id)) do
  nil -> {:error, :unknown_mutation, state}
  mutation -> settle_acknowledgement(state, mutation, acknowledgement)
end

with true <- exact_match?(mutation, acknowledgement),
     true <- acknowledgement["outcome"] in @terminal_outcomes,
     {:ok, shadow} <- apply_acknowledgement_snapshot(state, mutation, acknowledgement) do
  # terminalize journal, remove the exact queued row, replay visible
else
  false -> {:error, :acknowledgement_mismatch, state}
  {:error, reason} -> {:error, reason, state}
end

defp exact_match?(mutation, acknowledgement) do
  mutation["mutation_id"] == acknowledgement["mutation_id"] and
    secure_equal?(mutation["fingerprint"], acknowledgement["fingerprint"])
end
```

Never delete an outbox entry on unknown/mismatched acknowledgement. The worker transaction must either settle all terminal state or retain the prior state unchanged.

**Bounded scheduling pattern** (lines 80-94, 242-257): preserve fence-first behavior, dependency satisfaction, resource-lane ordering, and the 25-ready-push bound. Connectivity and timers only request another bounded pass.

---

### `apps/desktop/main/application/presentation.ts` and `packages/web-ui/src/ClientFacade.ts`

**Role/data flow:** model/provider; closed state transform plus semantic subscription.

**Primary analog:** `apps/web/src/commands/submission.ts`

**Closed state union** (lines 17-42):

```typescript
type ExactSubmissionState<Request, Acknowledgement, Rejection> =
  | { kind: 'not_submitted'; request: Request }
  | { kind: 'in_flight'; operation: RecoveryOperation; request: Request }
  | { kind: 'unknown'; request: Request }
  | {
      kind: 'authentication_required'
      authentication: AuthenticationRecovery
      operation: RecoveryOperation
      request: Request
    }
  | { acknowledgement: Acknowledgement; kind: 'acknowledged'; request: Request }
  | { kind: 'rejected'; rejection: Rejection; request: Request }
  | { kind: 'conflict'; rejection: Rejection; request: Request }
```

Use discriminated unions for renderer-visible state. Phase 3's union must use the exact UI-SPEC meanings (opening, preparing, updating, offline, retryable failure, local saved, uncertain, rejected, conflict, authentication fence, namespace mismatch, local save/store failure) and bounded counts/times/actions. Do not expose transport or database details.

**Fence/stale-result pattern** (lines 75-100):

```typescript
fence(): void {
  this.#epoch += 1
  this.#setState({ kind: 'not_submitted', request: this.#options.request })
}

const epoch = ++this.#epoch
this.#setState({ kind: 'in_flight', operation, request: this.#options.request })
// ... await adapter ...
if (epoch !== this.#epoch) return
if (!this.#options.matchesAcknowledgement(acknowledgement)) {
  this.#setState({ kind: 'unknown', request: this.#options.request })
  return
}
```

Apply this to namespace switch, logout, window recreation, and async sync results. A stale result cannot mutate the active namespace projection.

**Error classification pattern** (lines 147-159):

```typescript
if (!(error instanceof KeeplingApiError)) return { kind: 'unknown' }
if (error.problem.status >= 500) return { kind: 'unknown' }
const authentication = authenticationRecoveryFor(error.problem.code)
if (authentication) return { authentication, kind: 'authentication_required' }
if (error.problem.code === 'mutation_not_found') return { kind: 'not_found' }
if (error.conflict || error.problem.code.endsWith('_conflict')) {
  return { kind: 'conflict', rejection: error }
}
return { kind: 'rejected', rejection: error }
```

Classification belongs in the application layer. Shell, row, and recovery panel receive the same already-classified projection.

For the facade, expose named async methods and `subscribe(listener): unsubscribe`; subscription is established before `getWorkspaceSnapshot()`. Each update carries a monotonic presentation sequence; any gap causes an opaque snapshot refetch.

---

### `apps/desktop/main/adapters/sync.ts` and transport/record/view mappers

**Role/data flow:** service/utility; request-response, batch, transform.

**Primary analog:** `apps/web/src/api/keepling.ts`

**Generated wire type stays separate from presentation model** (lines 1-58):

```typescript
import type { components } from '../../../../packages/contracts/generated/keepling'

type WireCaptureTaskCommand = components['schemas']['CaptureTaskCommand']

type BrowserTask = {
  capturedAt: string
  completedAt: string | null
  deadlineOn: string | null
  id: string
  inboxState: 'clarified' | 'inbox'
  notes: string
  plannedOn: string | null
  revision: number
  title: string
  trashedAt: string | null
}
```

**Explicit mapper pattern** (lines 549-562):

```typescript
const mapTask = (task: components['schemas']['TaskSnapshot']): BrowserTask => ({
  capturedAt: task.captured_at,
  completedAt: task.completed_at,
  deadlineOn: task.deadline_on,
  id: task.id,
  inboxState: task.inbox_state,
  notes: task.notes,
  plannedOn: task.planned_on,
  project: task.project == null ? null : { ...task.project },
  revision: task.revision,
  tags: task.tags?.map((tag) => ({ ...tag })) ?? [],
  title: task.title,
  trashedAt: task.trashed_at,
})
```

Phase 3 needs three explicit conversion steps around this existing wire boundary: generated DTO ↔ storage-neutral sync model; sync model ↔ SQLite record; sync/application model → renderer view model. Never pass generated DTOs or SQLite rows directly to React.

**Immutable prepared command pattern** (lines 301-306, 893-910):

```typescript
type PreparedTaskCommand = {
  readonly body: string
  readonly mutationId: string
  readonly path: string
  readonly taskId: string
}

const submitPreparedTaskCommand = async (request: PreparedTaskCommand, csrfToken: string) =>
  mapAcknowledgement(await readJson(await fetch(request.path, {
    body: request.body,
    credentials: 'same-origin',
    headers: {
      accept: 'application/json',
      'content-type': 'application/json',
      'x-csrf-token': csrfToken,
    },
    method: 'POST',
  })))
```

Desktop differs critically: immutable command bytes are created and persisted before delivery, and retries reuse those exact bytes. The adapter receives prepared bytes from the application/store; it must not serialize a fresh object for retry.

---

### `packages/web-ui/src/{workspace,capture,tasks,recovery}/**` and desktop renderer bootstraps

**Role/data flow:** components/bootstrap; semantic request-response and event-driven presentation.

**Primary analogs:** `apps/web/src/app/WorkspaceShell.tsx`, `apps/web/src/features/capture/QuickCapture.tsx`, and `apps/web/src/app/AppShell.tsx`.

**Platform-free composition props** (`WorkspaceShell.tsx` lines 16-30):

```typescript
type WorkspaceShellProps = {
  children: ReactNode
  detailContent?: ReactNode
  detailSelected?: boolean
  listContent?: ReactNode
  onNavigate?: (event: MouseEvent<HTMLAnchorElement>, href: string) => void
  pathname: string
}

export type WorkspaceLayoutContent = {
  detailContent?: ReactNode
  detailSelected?: boolean
  listContent?: ReactNode
  mainContent?: ReactNode
}
```

Extract presentation through facade/semantic callbacks. Do not move `window.history`, browser session, fetch, Electron, IPC, or persistence ownership into `packages/web-ui`.

**Semantic landmark/list/detail pattern** (`WorkspaceShell.tsx` lines 112-142):

```tsx
<aside data-workspace-region="navigation">...</aside>
<main id="main-content" tabIndex={-1}>
  <div data-workspace-region="list">{listContent}</div>
  <div data-workspace-region="detail">{detailContent}</div>
</main>
```

Reuse semantics and focusability while adapting the breakpoints to the Phase 3 UI-SPEC: persistent 224/360–440/flexible layout at 1064px+, collapsed navigation at 1024–1063px, then one routed surface.

**Capture form semantics and bounded validation** (`QuickCapture.tsx` lines 189-249):

```tsx
<form className="mt-4 space-y-4" onSubmit={handleSubmit}>
  <label htmlFor={fieldId}>What do you want to keep?</label>
  <textarea
    aria-describedby={message ? errorId : undefined}
    aria-invalid={message ? true : undefined}
    maxLength={512}
    value={draft}
  />
  <p>Destination: Inbox</p>
  <label><input checked={addToToday} type="checkbox" />Add to Today</label>
  <Button type="submit">Add task</Button>
</form>
```

Replace browser delivery state with `ClientFacade.capture`; preserve the form, plain-text bound, labels, destination visibility, and optional Today intent. `Command-Return` must additionally ignore composition.

**Dirty-work safe-default pattern** (`AppShell.tsx` lines 223-290):

```tsx
const keepEditing = {
  label: 'Keep editing',
  onClick: () => setPendingAction(null),
  ref: stayButtonRef,
  variant: 'outline',
}

<AlertDialog
  finalFocus={confirmationTriggerRef}
  initialFocus={stayButtonRef}
  onCancel={() => setPendingAction(null)}
  open={pendingAction !== null}
/>
```

Reuse focus return and safe initial action. Phase 3 exact casing/copy comes from `03-UI-SPEC.md`, not the browser's older strings.

---

### Desktop build/test configuration and evidence files

**Role/data flow:** config/test; batch, event-driven, file-I/O.

**Primary analogs:** `apps/web/package.json`, `apps/web/vite.config.ts`, `apps/web/vitest.config.ts`, `apps/web/playwright.config.ts`, `apps/web/e2e/phase1.spec.ts`.

**Workspace-local scripts pattern** (`apps/web/package.json` lines 1-14):

```json
{
  "name": "@keepling/web",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "test": "vitest run",
    "test:e2e": "playwright test",
    "typecheck": "tsc -b --pretty false"
  }
}
```

Desktop owns analogous local commands. Root `package.json` follows its existing `pnpm --filter` pattern (lines 5-13) to expose the locked names `dev:desktop`, `typecheck:desktop`, `test:desktop`, `test:desktop:ipc`, `test:desktop:e2e`, `package:desktop`, and `smoke:desktop:packaged`.

**Deterministic unit-test isolation** (`apps/web/vitest.config.ts` lines 10-26): use `clearMocks`, `mockReset`, `restoreMocks`, explicit includes/setup, and unstubbed globals/env. Desktop must split pure/jsdom tests from real worker/SQLite tests rather than making jsdom the universal environment.

**Serial stateful E2E evidence** (`apps/web/playwright.config.ts` lines 13-26):

```typescript
export default defineConfig({
  fullyParallel: false,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  workers: 1,
  reporter: process.env.CI ? 'github' : 'list',
  use: { screenshot: 'only-on-failure', trace: 'retain-on-failure' },
})
```

Retain evidence on failure and serialize tests that share an application profile. Every desktop test gets an isolated temporary user-data directory; never point at the real Keepling profile.

**User-visible end-to-end assertions** (`apps/web/e2e/phase1.spec.ts` lines 29-67, 99-137): the existing test drives capture → edit → undo → Today → complete/reopen → Trash/restore through roles and labels and asserts response identity/revisions. Reuse that supported-loop ordering, but invoke the Electron UI/menu/facade and assert durable local state after hard kill/relaunch.

The packaged lane has no analog. It must package once, hash the exact `.app`/ZIP, copy/launch the executable outside the source tree, assert `app.isPackaged`, local packaged content/CSP/sandbox/worker/runtime, hard-kill/relaunch, reconnect exactly once, and retain the same digest with results.

## Shared Patterns

### Authority and Dependency Direction

**Source:** `apps/desktop/README.md:1-6`, `docs/architecture/REPOSITORY.md:37-60`

Apply to every file:

```text
React presentation
  -> ClientFacade
  -> validated preload bridge
  -> DesktopApplication
  -> LocalStorePort / SyncPort / CredentialPort
```

The renderer is a disposable mirror. SQLite is a local projection/outbox, not canonical storage. Phoenix/PostgreSQL remains canonical and owns authorization, invariants, revisions, idempotency, and merge/conflict decisions.

### Validation and Least Privilege

Apply to `preload/contracts.ts`, `preload/index.ts`, main IPC registration, and worker protocol:

- Parse strict clone-safe request and response shapes on both sides.
- Reject unknown operations/fields and invalid senders.
- Expose one named async method per semantic capability; never expose channel strings, raw `ipcRenderer`, Electron events, fetch, SQL, paths, credentials, database handles, or filesystem APIs.
- Renderer uses packaged local content, context isolation, sandboxing, no Node integration, restrictive CSP, and denied unexpected navigation/window creation/permissions.

There is no tracked local IPC analog; use the research code skeleton plus official Electron guidance cited there.

### Error Handling and Honest Trust Copy

**Sources:** `apps/web/src/commands/submission.ts:80-134`, `apps/web/src/app/AppShell.tsx:117-177`

- Async errors become closed application outcomes; stale/fenced results do nothing.
- Local commit failure preserves the draft and cannot produce `Saved on this Mac`.
- Unknown server delivery preserves immutable intent and offers lookup/check-again.
- Unknown/mismatch acknowledgements leave the outbox unchanged.
- Migration/open/integrity failure renders the recovery shell; never delete/recreate or render a false empty state.
- Renderer copy comes exactly from `03-UI-SPEC.md`; diagnostics use closed codes, bounded counts, coarse timing, and process role only.

### Deterministic Test Inputs

Use injected clocks, IDs, network, credentials, and fault ports. Consume `packages/contracts/vectors/sync.json` and validate the desktop reducer/store results against `packages/contracts/schemas/sync-state-machine.schema.json`. Scenario fixtures must be privacy-safe and named by behavior, not real task content or identifiers.

## No Analog Found

| File | Role | Data Flow | Reason / Planner Direction |
|---|---|---|---|
| `apps/desktop/main/index.ts` | controller/composition | event-driven | No Electron lifecycle exists. Follow the research lifecycle skeleton: explicit single-instance lock, resident close, Dock recreation, bounded quit; lifecycle is never commit authority. |
| `apps/desktop/main/adapters/credentials.ts` | service | request-response + file-I/O | No client credential port exists. Define async `CredentialPort`; implement `safeStorage` only in the adapter and test unsigned limitations. |
| `apps/desktop/preload/index.ts` | middleware/provider | request-response + pub-sub | No IPC exists. Use the research narrow-bridge example and hostile sender/schema tests. |
| `apps/desktop/store-worker/index.ts` | service/provider | event-driven | No Node worker protocol exists. Use a bounded validated request/response protocol and one owned connection; never import `node:sqlite` in main/window modules. |
| `apps/desktop/migrations/0001_initial.sql` + manifest | migration/config | CRUD | Existing Ecto migrations represent PostgreSQL canonical state and must not be copied. Implement desktop-only STRICT tables, checksum ledger, transactional forward migration, retained lineages, WAL/FULL/foreign-key assertions. |
| `apps/desktop/forge.config.ts` | config | batch | No packaged app exists. Follow research's Forge/direct-Vite recommendation and exact-artifact gate. |
| `apps/desktop/test/packaged/**` | test | file-I/O + event-driven | Web E2E is development-server evidence only. Build/package once and test the exact external executable/digest. |

## Metadata

**Analog search scope:** tracked files under `apps/web`, `apps/server/lib/keepling/application/sync`, `apps/server/test/keepling/application/sync`, root workspace manifests, and contract schemas/vectors.

**Tracked-source gate:** Every analog named above returned non-empty output from `git ls-files -- <path>`. No plugin cache, dependency, build, runtime mirror, or ignored path is referenced.

**Files scanned:** 187 tracked project files listed; 16 candidate analog files checked for size/tracking; 11 analog/config files read for concrete patterns.

**Pattern extraction date:** 2026-09-02
