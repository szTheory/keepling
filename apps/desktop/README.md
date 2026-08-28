# Keepling Desktop

**Planned phase:** Phase 3  
**Technology:** Electron; macOS is the first supported target

The main process will own SQLite, the durable outbox, synchronization, credentials, migrations, lifecycle, and OS integration. Preload exposes a narrow validated semantic bridge. The renderer uses shared React presentation but never receives raw database, filesystem, credential, or unrestricted IPC access.

