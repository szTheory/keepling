# Repository Architecture

Keepling is one coordinating monorepo. The root `.planning/` directory is the only GSD authority, and root Git history is the default home for all product code, contracts, infrastructure, and evidence.

## Intended tree

```text
keepling/
├── apps/
│   ├── server/          # Phoenix modular monolith
│   ├── web/             # browser bootstrap and browser adapters
│   ├── desktop/         # Electron main/preload/renderer
│   ├── ios/             # Xcode project and Swift packages
│   └── android/         # deferred
├── packages/
│   ├── contracts/       # OpenAPI, JSON Schemas, golden vectors
│   ├── design-tokens/   # semantic source and generated outputs
│   ├── api-client-ts/   # generated transport only
│   ├── client-core-ts/  # pure client orchestration where genuinely shared
│   └── web-ui/          # React presentation; no platform APIs
├── infra/               # portable container and Hetzner reference deployment
├── tooling/             # deterministic generation, drift, and release tools
├── docs/                # durable brand/product/architecture/decision docs
└── .planning/           # GSD lifecycle and retained project knowledge
```

## Create now versus later

The root repository, planning, knowledge, brand seed, boundary READMEs, and CI conventions exist now. Runtime scaffolds are created only in their delivery phase:

- Phase 1 creates `apps/server`, `apps/web`, initial contracts, tokens, and test tooling.
- Phase 2 creates `infra` implementation and sync vectors.
- Phase 3 creates `apps/desktop` and desktop-specific client/store packages.
- Phase 4 creates `apps/ios`.
- `apps/android` remains documentation-only until a roadmap explicitly promotes it.

## Dependency direction

- Server domain → nothing outward.
- Server application → domain plus declared ports.
- Adapters → application/domain contracts.
- Generated clients → checked-in wire contract only.
- Shared React UI → narrow `ClientFacade`, never Electron/browser implementation details.
- Electron renderer → shared UI; preload → narrow semantic IPC; main → storage/sync/credentials/OS.
- SwiftUI → Swift client orchestration and native adapters; generated DTOs never become persistence records.
- Infrastructure → portable image/health/migration/backup contracts; product code never imports provider details.

## Shared deliberately

- Wire schemas, compatibility metadata, stable error envelopes, golden behavior vectors.
- Semantic design-token values/names and generated platform representations.
- React presentation and TypeScript transport between browser and Electron.
- Release-evidence vocabulary and contract/token drift checks.

## Duplicated deliberately

- PostgreSQL, desktop SQLite, browser cache, and iPhone local schemas/migrations.
- React versus SwiftUI views and platform-specific interaction.
- Credential storage, lifecycle, menus, shortcuts, notifications, recovery UI.
- Cross-language orchestration code where sharing would require a framework or lowest-common-denominator abstraction.

## Git and subproject rules

- Do not initialize nested `.git` directories under `apps/`, `packages/`, `infra/`, or `tooling/`.
- Do not use Git submodules for first-party Keepling code.
- External experiments live outside this repository until adopted; adoption copies the minimal owned result with provenance.
- A component becomes a separate repository only after it has independent consumers, ownership, release cadence, and a concrete reason worth losing atomic changes.
- Root commits may span multiple boundaries when a contract requires coordinated change; CI fans out based on affected shared inputs.

## Build orchestration

Use native tools first: Mix for Phoenix, pnpm workspaces for TypeScript, Xcode/SwiftPM for iOS, OpenTofu/Compose for infrastructure. Root scripts may coordinate deterministic common tasks, but do not add Nx, Turborepo, or a universal build graph until measured CI pain earns it.

## Context discoverability

- `AGENTS.md` tells agents to read PROJECT, STATE, roadmap/requirements, research summary, and this document before material edits.
- `.planning/knowledge/INDEX.md` is the only navigation entry for retained second-brain material.
- Dated snapshots remain immutable evidence; current conclusions live in PROJECT/decisions/research synthesis.
- Each future app README states ownership, local commands, tests, and cross-boundary contracts without copying the entire project thesis.

