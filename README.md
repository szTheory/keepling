# Keepling

Keepling is a calm, open-source, AI-native personal GTD system for people who want Things-quality direct use and trustworthy programmatic access. The project is personal-first: it succeeds when Jon can depend on it on Mac and iPhone, including through network loss, while external agents use the same safe domain commands as the human interfaces.

This repository is the coordinating monorepo. It owns the product context, cross-client contracts, implementation applications, infrastructure, and release evidence.

## Start here

1. Read [`.planning/PROJECT.md`](.planning/PROJECT.md) for the product thesis and constraints.
2. Read [`.planning/STATE.md`](.planning/STATE.md) for the current GSD position and next action.
3. Use [`.planning/knowledge/INDEX.md`](.planning/knowledge/INDEX.md) to navigate the retained exploratory research and provenance.
4. Read [`docs/brand/BRAND-SEED.md`](docs/brand/BRAND-SEED.md) for the provisional identity.
5. Read [`docs/architecture/REPOSITORY.md`](docs/architecture/REPOSITORY.md) before adding a new app or shared package.

## Intended repository shape

```text
apps/
  server/      Phoenix/PostgreSQL modular monolith
  web/         online-first React browser client
  desktop/     Electron desktop client; macOS is the initial target
  ios/         native SwiftUI iPhone client
  android/     deferred until demand justifies it
packages/
  contracts/   wire schemas and cross-runtime golden vectors
  design-tokens/
  api-client-ts/
  client-core-ts/
  web-ui/
infra/         reference self-hosting and recovery automation
tooling/       deterministic generators and repository automation
docs/          durable product, architecture, brand, and decision docs
.planning/     GSD project state and retained second-brain knowledge
```

The folders document intended ownership; they are not permission to scaffold every runtime at once. Each application starts when its vertical tracer phase begins.

## Project posture

- Complete open-source personal product first; optional hosted operations later.
- One person and multiple devices, not collaboration or enterprise work management.
- Phoenix/PostgreSQL modular monolith; no microservices without measured need.
- Durable native/offline clients on Mac and iPhone; online-first browser access.
- Semantic, reversible MCP tools over the same application boundary as the UI.
- One excellent, replaceable Hetzner reference deployment with verified recovery.
- High test confidence, fast CI, native platform feel, restrained dependencies, and privacy-safe observability.

## Current status

Greenfield planning is initialized. No application framework has been scaffolded yet.

Run:

```text
$gsd-discuss-phase 1
```

