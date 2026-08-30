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
```
