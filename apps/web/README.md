# Keepling Web

**Planned phase:** Phase 1  
**Technology:** online-first React/TypeScript browser client

This boundary bootstraps the browser application and browser-specific adapters. Presentation intended for reuse belongs in `packages/web-ui` only after both browser and Electron have proven the shared seam. The browser is not a durable offline synchronization client in v1.

Run commands from the repository root:

```bash
pnpm dev:web
pnpm build:web
pnpm lint:web
pnpm typecheck:web
pnpm --filter @keepling/web test
pnpm --filter @keepling/web test:e2e
```

Unit and component tests run once in Vitest/jsdom with deterministic browser
shims. Playwright starts an isolated PostgreSQL 18.6 database, migrates and
seeds it, then runs Phoenix and Vite behind one local origin. The harness owns
and stops only the process groups it starts, and test-fault controls receive a
new high-entropy credential for each run unless the caller supplies one.
