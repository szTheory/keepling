# Keepling Server

**Planned phase:** Phase 1  
**Technology:** standalone Phoenix application with Ecto/PostgreSQL; not an umbrella

This boundary will own domain/application modules, canonical persistence, authentication/authorization, command/query/synchronization adapters, release migrations, and the MCP adapter. Domain rules must remain independent of Phoenix transport, MCP, and client implementations.

No framework has been scaffolded yet. Phase 1 research and discussion choose current supported versions before `mix phx.new` or equivalent initialization.

