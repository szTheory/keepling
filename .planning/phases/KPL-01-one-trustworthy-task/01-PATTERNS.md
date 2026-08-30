# Phase 1: One Trustworthy Task - Pattern Map

**Mapped:** 2026-08-30
**Target files/families classified:** 15
**Code/config analogs found:** 5 / 15
**Boundary-document precedents:** 4 target families

## Scope Interpretation

`01-CONTEXT.md` locks the top-level boundaries (`apps/server`, `apps/web`, initial contracts, semantic tokens, and test tooling), but it does not lock individual implementation filenames. `01-RESEARCH.md:278-302` proposes directory families and names explicit Wave 0 config/test paths at `01-RESEARCH.md:639-717`. The table below therefore classifies exact files where research names them and glob families where the planner must choose the concrete module split.

The repository has an initialized React/Vite styling shell, but no server runtime, feature implementation, contract implementation, or test harness. `apps/server/README.md`, `apps/web/README.md`, `packages/README.md`, and `docs/architecture/REPOSITORY.md` are valid ownership/boundary precedents; they are not implementation analogs and must not be copied as if they demonstrated Phoenix, Ecto, transaction, command, or test behavior.

## File Classification

| New/Modified File or Family | Role | Data Flow | Closest Existing Analog | Match Quality |
|---|---|---|---|---|
| `apps/server/mix.exs`, `config/**/*`, generated runtime scaffold | config | request-response | `apps/server/README.md:3-8` | boundary-doc only; use Phoenix generator guidance in research |
| `apps/server/lib/keepling/domain/**/*.ex` | model/service | transform, event-driven | `apps/server/README.md:6-8` | boundary-doc only; no implementation analog |
| `apps/server/lib/keepling/application/**/*.ex` | service | request-response, event-driven | `apps/server/README.md:6-8` | boundary-doc only; no implementation analog |
| `apps/server/lib/keepling/adapters/postgres/**/*.ex`, `priv/repo/migrations/*.exs` | service/model/migration | CRUD, batch | none | no implementation analog |
| `apps/server/lib/keepling_web/**/*` | controller/route/middleware | request-response | none | no implementation analog |
| `apps/server/test/test_helper.exs`, `test/support/{data_case,conn_case}.ex` | config/test | CRUD, request-response | none | no implementation analog |
| `apps/server/test/{keepling,keepling_web}/**/*_test.exs` | test | transform, CRUD, request-response, event-driven | none | no implementation analog |
| `apps/web/src/main.tsx`, `App.tsx`, `app/**/*` | provider/route/component | request-response, event-driven | `apps/web/src/main.tsx:1-10`, `apps/web/src/App.tsx:1-5` | exact scaffold pattern |
| `apps/web/src/features/**/*.{ts,tsx}` | component/hook | event-driven, request-response | `apps/web/src/components/ui/button.tsx:1-56` | role-match only; no feature behavior analog |
| `apps/web/src/commands/**/*.{ts,tsx}` | service/store | event-driven, request-response | none | no implementation analog |
| `apps/web/src/api/**/*.{ts,tsx}` | service | request-response, transform | `apps/web/vite.config.ts:1-14` | config seam only; no API implementation analog |
| `apps/web/vitest.config.ts`, `playwright.config.ts`, `src/test/**/*` | config/test | event-driven, request-response | `apps/web/vite.config.ts:1-14`, `apps/web/package.json:6-12` | config-role match; no test implementation analog |
| `packages/contracts/{openapi,schemas,vectors,generated}/**/*` | model/config/test | transform | `packages/README.md:1-4` | boundary-doc only; no implementation analog |
| `packages/design-tokens/**/*`, `apps/web/src/index.css` | config | transform | `apps/web/src/index.css:1-130` | exact existing token-consumer pattern |
| root `package.json`, `pnpm-workspace.yaml`, `tooling/**/*` | config/utility/test | batch, file-I/O | `package.json:1-11`, `pnpm-workspace.yaml:1-5`, `tooling/check-repository-integrity.sh:1-26` | exact coordination pattern |

## Pattern Assignments

### `apps/server/mix.exs`, `config/**/*`, generated runtime scaffold (config, request-response)

**Boundary precedent:** `apps/server/README.md:3-8`

```markdown
**Technology:** standalone Phoenix application with Ecto/PostgreSQL; not an umbrella

This boundary will own domain/application modules, canonical persistence,
authentication/authorization, command/query/synchronization adapters, release
migrations, and the MCP adapter. Domain rules must remain independent of Phoenix
transport, MCP, and client implementations.
```

This establishes placement and dependency direction only. There is no Mix/Phoenix implementation to copy. Generate the standalone, non-LiveView server in place without nested Git, then follow `01-RESEARCH.md:180-219` for the stack and generator baseline. Preserve the existing boundary README rather than treating generation as permission to replace it blindly.

---

### `apps/server/lib/keepling/domain/**/*.ex` (model/service, transform/event-driven)

**Boundary precedent:** `apps/server/README.md:6-8`

There is no domain implementation analog. Use the pure-decision contract in `01-RESEARCH.md:304-311`: canonical state plus a closed semantic command produces new state/effects or a typed semantic rejection. Domain modules must not read the clock, database, HTTP connection, or Ecto schema. The application edge injects account day and acceptance time.

Use storage-neutral vectors in `packages/contracts/vectors/` for date truth tables, merge/lifecycle rules, warnings, and closed outcomes. Do not use Ecto changesets as the public domain API.

---

### `apps/server/lib/keepling/application/**/*.ex` (service, request-response/event-driven)

**Boundary precedent:** `docs/architecture/REPOSITORY.md:38-44`

```text
Server domain → nothing outward.
Server application → domain plus declared ports.
Adapters → application/domain contracts.
```

No application-service code exists. Route implementation design to:

- `01-RESEARCH.md:304-321` for pure decisions and the account-scoped idempotency gate.
- `01-RESEARCH.md:322-337` for optimistic revision/merge and canonical account day.
- `01-RESEARCH.md:354-365` for closed bootstrap/recovery and append-only activity.

The application command boundary is semantic, not CRUD or JSON Patch. Every transport must invoke it rather than duplicating invariants.

---

### `apps/server/lib/keepling/adapters/postgres/**/*.ex`, `priv/repo/migrations/*.exs` (service/model/migration, CRUD/batch)

**Implementation analog:** none.

Use the transaction skeleton from `01-RESEARCH.md:473-493` as the starting primitive:

```elixir
multi =
  Ecto.Multi.new()
  |> Ecto.Multi.insert(:receipt, receipt_changeset)
  |> Ecto.Multi.run(:decision, fn repo, %{receipt: receipt} ->
    apply_semantic_command(repo, receipt, command)
  end)
  |> Ecto.Multi.insert(:activity, fn %{decision: decision} ->
    activity_changeset(decision)
  end)
  |> Ecto.Multi.update(:terminal_receipt, fn %{decision: decision} ->
    terminal_receipt_changeset(decision)
  end)

Repo.transact(multi)
```

Refine it so authenticated terminal semantic rejections/conflicts are committed with their receipts; only infrastructure failures roll back. Use database uniqueness as the concurrent first-delivery arbiter and explicit row/scope locking for task, account-setup, and Today-order invariants. Keep separate persistence representations for task snapshots, receipts, structured conflicts, undo handles, activity, and session/security state (`01-RESEARCH.md:312-321`, `399-418`).

---

### `apps/server/lib/keepling_web/**/*` (controller/route/middleware, request-response)

**Implementation analog:** none.

Use `01-RESEARCH.md:346-357` for the same-origin session and closed bootstrap patterns and `01-RESEARCH.md:495-510` for JSON CSRF delivery. The required client call shape is:

```javascript
await fetch("/api/commands", {
  method: "POST",
  credentials: "same-origin",
  headers: {
    "content-type": "application/json",
    "x-csrf-token": csrfToken,
  },
  body: JSON.stringify(command),
})
```

Controllers decode/version a closed command DTO, derive account/principal from the authenticated session, invoke the shared application boundary, and map the stored terminal result to the versioned RFC 9457 envelope. Do not place product invariants, client-authored merge logic, raw patch endpoints, or direct Ecto access in controllers.

---

### Server test support and `*_test.exs` files (test, all server flows)

**Implementation analog:** none.

Create the exact Wave 0 support paths named at `01-RESEARCH.md:643-653`:

- `apps/server/test/test_helper.exs`
- `apps/server/test/support/data_case.ex`
- `apps/server/test/support/conn_case.ex`

Use the behavior/file mapping at `01-RESEARCH.md:655-673`; treat its filenames as recommended unless a vertical slice produces a clearer module boundary. Concurrency tests must use independent database connections/processes and explicit barriers. The required fault assertions are in `01-RESEARCH.md:675-691`; sequential requests are not a valid analog for duplicate-first-delivery, response-loss, undo races, or reorder collisions.

---

### `apps/web/src/main.tsx`, `App.tsx`, `app/**/*` (provider/route/component, request-response/event-driven)

**Analog:** `apps/web/src/main.tsx:1-10`

**Imports and bootstrap pattern:**

```tsx
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
```

**Current semantic root:** `apps/web/src/App.tsx:1-5`

```tsx
function App() {
  return <main id="main-content" />
}

export default App
```

Keep `main.tsx` as a thin composition root: install router/query/theme/auth providers there or immediately below it, while route components remain under `app/` and features. Preserve the semantic `main` landmark; the UI contract adds semantic header/nav/main landmarks rather than replacing the root with anonymous wrapper divs.

---

### `apps/web/src/features/**/*.{ts,tsx}` (component/hook, event-driven/request-response)

**Analog:** `apps/web/src/components/ui/button.tsx:1-56`

**Import convention** (lines 1-4):

```tsx
import { Button as ButtonPrimitive } from "@base-ui/react/button"
import { cva, type VariantProps } from "class-variance-authority"

import { cn } from "@/lib/utils"
```

**Owned primitive wrapper** (lines 41-52):

```tsx
function Button({
  className,
  variant = "default",
  size = "default",
  ...props
}: ButtonPrimitive.Props & VariantProps<typeof buttonVariants>) {
  return (
    <ButtonPrimitive
      data-slot="button"
      className={cn(buttonVariants({ variant, size, className }))}
      {...props}
    />
  )
}
```

Copy the local ownership and `@/` alias conventions, not the button's generic visual defaults onto every component. Feature components should use native landmarks, lists, forms, labels, buttons, and `<time>` elements from `01-UI-SPEC.md:121-201`; task lists are `ul`/`li`, never custom ARIA grids. There is no feature-state, form, list, focus-restoration, or error-handling analog in the repository, so implement those from the approved UI contract and research rather than extrapolating from `Button`.

---

### `apps/web/src/commands/**/*.{ts,tsx}` (service/store, event-driven/request-response)

**Implementation analog:** none.

Use `01-RESEARCH.md:338-345` as the authoritative split: TanStack Query owns last-good reads/background refresh, while a Keepling command object owns the draft snapshot, original mutation identity, semantic request, delivery state, authentication interruption, lookup/retry, and exact reconciliation.

The identity is created before delivery (`01-RESEARCH.md:512-520`):

```typescript
const mutationId = crypto.randomUUID()
const submission = { mutationId, command }
```

Do not generate an identity inside each fetch attempt, clear a draft in `finally`, enable automatic write retries, or optimistically remove membership-changing rows. Model not-submitted, in-flight, acknowledged, unknown, authentication-required, stale, conflict, and unrecoverable states distinctly.

---

### `apps/web/src/api/**/*.{ts,tsx}` (service, request-response/transform)

**Config seam analog:** `apps/web/vite.config.ts:1-14`

```ts
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
})
```

Use the existing `@` alias and add the development `/api` same-origin proxy at this configuration boundary. API code should map generated transport types into a handwritten semantic facade; generated wire DTOs must not become browser view state or server domain objects. There is no existing fetch/error mapping implementation. Use the RFC 9457 and exact-acknowledgement rules in `01-RESEARCH.md:312-345` and the UI state/copy contract in `01-UI-SPEC.md:167-180,229-241`.

---

### `apps/web/vitest.config.ts`, `playwright.config.ts`, `src/test/**/*` (config/test, event-driven/request-response)

**Config analogs:** `apps/web/vite.config.ts:1-14`, `apps/web/package.json:6-12`

```json
"scripts": {
  "dev": "vite",
  "build": "tsc -b && vite build",
  "lint": "eslint .",
  "typecheck": "tsc -b --pretty false",
  "preview": "vite preview"
}
```

Extend this native per-app script style with test commands; do not introduce a universal build graph. No Vitest, Testing Library, Playwright, axe, fixture, or fault-control implementation exists. Follow the exact framework/config recommendations at `01-RESEARCH.md:643-653` and browser evidence matrix at `01-RESEARCH.md:693-700`. Tests must assert focus, keyboard behavior, draft/identity retention, exact trust-state copy, hostile text rendering, themes/viewports, Reduce Motion, forced colors, and real Phoenix/PostgreSQL response-loss behavior—not snapshots alone.

---

### `packages/contracts/{openapi,schemas,vectors,generated}/**/*` (model/config/test, transform)

**Boundary precedent:** `packages/README.md:1-4`

```markdown
Only contracts, golden vectors, semantic design tokens, generated transport, and
presentation code proven to have multiple consumers belong here. Platform
persistence, lifecycle, recovery UI, and native interaction stay with their
application.
```

No contract or generator implementation exists. Use `01-RESEARCH.md:278-302` for placement and `01-RESEARCH.md:322-337` for required merge/date vectors. The OpenAPI source is transport truth; vectors are storage-neutral behavior truth; generated outputs are reproducible derivatives. Do not place Ecto schemas, domain structs, React state, platform persistence, or browser recovery orchestration here.

---

### `packages/design-tokens/**/*`, `apps/web/src/index.css` (config, transform)

**Analog:** `apps/web/src/index.css:7-48,50-69,86-104`

**Semantic mapping pattern** (lines 7-15):

```css
@theme inline {
    --font-heading: var(--font-sans);
    --font-sans: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    --color-sidebar-ring: var(--sidebar-ring);
    --color-sidebar-border: var(--sidebar-border);
    --color-sidebar-accent-foreground: var(--sidebar-accent-foreground);
    --color-sidebar-accent: var(--sidebar-accent);
    --color-sidebar-primary-foreground: var(--sidebar-primary-foreground);
    --color-sidebar-primary: var(--sidebar-primary);
```

**Light/dark role override pattern** (lines 57-69 and 86-104):

```css
:root {
    --primary: #6f4a63;
    --primary-foreground: #fff8e9;
    --ring: #6f4a63;
}

.dark {
    --primary: #d29abf;
    --primary-foreground: #201b22;
    --ring: #d29abf;
}
```

Keep semantic names as the consumption boundary. Generate CSS values from a small DTCG-compatible source rather than making Tailwind utility strings the shared truth. Complete the exact Phase 1 role values, focus-ring, motion, and forced-colors behavior from `01-UI-SPEC.md:27-93,197-201`.

---

### Root `package.json`, `pnpm-workspace.yaml`, `tooling/**/*` (config/utility/test, batch/file-I/O)

**Workspace analog:** `pnpm-workspace.yaml:1-5`

```yaml
packages:
  - "apps/*"
  - "packages/*"

onlyBuiltDependencies: []
```

**Root coordination analog:** `package.json:4-9`

```json
"packageManager": "pnpm@10.33.0",
"scripts": {
  "build:web": "pnpm --filter @keepling/web build",
  "dev:web": "pnpm --filter @keepling/web dev",
  "lint:web": "pnpm --filter @keepling/web lint",
  "typecheck:web": "pnpm --filter @keepling/web typecheck"
}
```

**Deterministic shell-tool pattern:** `tooling/check-repository-integrity.sh:1-15`

```sh
#!/usr/bin/env sh
set -eu

repository_root=$(git rev-parse --show-toplevel)
cd "$repository_root"

nested_git=$(find . -mindepth 2 \( -type d -o -type f \) -name .git -print -quit)
if [ -n "$nested_git" ]; then
  echo "Nested Git metadata is not allowed: $nested_git" >&2
  exit 1
fi
```

Add narrowly named root coordination and contract/drift/E2E scripts that delegate to Mix and pnpm. Follow the shell precedent: POSIX shell, `set -eu`, resolve repository root, fail with a specific diagnostic, and emit one concise success line. Do not add Nx/Turborepo or turn `tooling/` into an internal platform.

## Shared Patterns

### Dependency Direction

**Sources:** `docs/architecture/REPOSITORY.md:38-53`, `apps/server/README.md:6-8`, `packages/README.md:1-4`

Apply to every server, web, contract, and generator target:

```text
domain <- application <- adapters (Phoenix/PostgreSQL)
checked-in wire contract -> generated transport
React feature/view state -> handwritten semantic API facade -> generated transport
```

Arrows indicate dependency toward the left-hand authority. Domain/application values, Ecto schemas, wire DTOs, and React state remain explicit separate representations.

### Authentication and Authorization

**Source:** no implementation analog; `01-RESEARCH.md:346-357,495-510`

Apply to every cookie-authenticated server mutation and browser command. Derive account/principal server-side, validate session plus CSRF/origin/host, store only hashes of bearer secrets, rotate session/CSRF after authentication, and scope receipt/aggregate/handle/cursor lookups by authenticated account. Opaque identifier or handle possession never authorizes access.

### Stable Semantic Results and Error Handling

**Source:** no implementation analog; `01-RESEARCH.md:312-345,397-467`

Application results are closed, versioned semantic envelopes. Persist authenticated terminal accepted and rejected/conflict results. Controllers map them through RFC 9457; the browser maps them to distinct persistent states and recovery actions. A missing response is unknown delivery, not rejection.

### Validation

**Source:** no implementation analog; `01-RESEARCH.md:304-337`, `01-UI-SPEC.md:146-154,270-280`

Structural wire validation belongs at transport decoding, product invariants in pure domain decisions, persistence constraints/shape in Ecto/database, and form feedback in the browser. Validation errors preserve all entered fields, announce a linked summary, retain help/error associations through retries, and focus the first invalid field.

### Logging and Privacy

**Source:** no implementation analog; `01-RESEARCH.md:718-768`

Use explicit diagnostic field allow-lists. Never emit titles, notes, prompts, credentials, raw tokens, arbitrary task/activity/mutation identifiers, raw command bodies, or full user-agent/IP fingerprints. User-visible task activity is canonical content-bearing data and remains separate from receipts, security audit, and telemetry.

### Web Imports and Styling

**Sources:** `apps/web/src/components/ui/button.tsx:1-4`, `apps/web/src/lib/utils.ts:1-6`, `apps/web/vite.config.ts:9-12`

Use `@/` for source-root imports and the local `cn()` utility for class composition. Keep framework/vendor imports before a blank line and project-alias imports after it, matching the existing component. Consume semantic CSS roles; do not spread raw brand hex values through feature components.

### Testing

**Source:** no test implementation analog; `01-RESEARCH.md:639-717`, `01-UI-SPEC.md:313-320`

Keep each behavior at the cheapest layer that proves it, but exercise the trust boundary with real PostgreSQL and real-browser tests. Every consequential path needs happy, validation, boundary, conflict, retry, response-loss, auth-expiry, accessibility, and privacy-negative evidence in proportion to risk.

## No Implementation Analog Found

| Target | Role | Data Flow | Planner Source Instead |
|---|---|---|---|
| Server domain modules | model/service | transform, event-driven | `01-RESEARCH.md:304-337` |
| Application command dispatcher/result types/ports | service | request-response, event-driven | `01-RESEARCH.md:304-365` |
| PostgreSQL schemas, repositories, migrations, transaction kernel | service/model/migration | CRUD, batch | `01-RESEARCH.md:312-321,399-428,473-493` |
| Phoenix controllers/router/auth/session middleware | controller/route/middleware | request-response | `01-RESEARCH.md:346-357,439-448,495-510` |
| Server ExUnit/Sandbox/StreamData tests | test/config | transform, CRUD, concurrency | `01-RESEARCH.md:639-691` |
| Browser command state machine | service/store | event-driven, request-response | `01-RESEARCH.md:338-345,419-428,512-520` |
| Browser API facade/problem mapping | service | request-response, transform | `01-RESEARCH.md:312-345,379-395` |
| Vitest/Testing Library/Playwright/fault harness | test/config | event-driven, request-response | `01-RESEARCH.md:639-717` |
| OpenAPI/schema/vector generation and drift checks | model/config/test | transform | `01-RESEARCH.md:278-302,322-337,379-395` |
| Feature forms, lists, recovery, conflict, activity, and session UI | component/hook | event-driven, request-response | `01-UI-SPEC.md:95-201,259-320` |

## Metadata

**Analog search scope:** repository root; `apps/`, `packages/`, `tooling/`, root workspace config, and architecture/boundary documents; dependency/build directories excluded.

**Repository files inventoried:** 30 non-hidden, non-build files returned by the live source-file inventory; analog candidates were then read from the relevant app, package, tooling, root-config, and boundary-document subset.

**Strong code/config analogs read:** `apps/web/src/main.tsx`, `apps/web/src/App.tsx`, `apps/web/src/index.css`, `apps/web/src/components/ui/button.tsx`, `apps/web/src/lib/utils.ts`, `apps/web/vite.config.ts`, `apps/web/package.json`, root `package.json`, `pnpm-workspace.yaml`, and `tooling/check-repository-integrity.sh`.

**Boundary precedents read:** `apps/server/README.md`, `apps/web/README.md`, `packages/README.md`, `tooling/README.md`, and `docs/architecture/REPOSITORY.md`.

**Excluded as an analog:** `.tool-versions` is untracked user work and was neither read nor modified.

**Pattern extraction date:** 2026-08-30
