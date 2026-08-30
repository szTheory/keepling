# Roadmap: Keepling

## Overview

Keepling is built as six vertical proof increments. Each phase produces observable user value and durable evidence while delaying additional client/runtime complexity until the shared semantics have survived the preceding slice.

### Phase 1: One Trustworthy Task
**Goal:** A user can authenticate and complete the core task lifecycle through a real React → Phoenix → PostgreSQL browser slice.
**Mode:** mvp
**Requirements:** GTD-01..07, SRV-01, SRV-02 (semantic boundary + web/API proof), SRV-03, WEB-01..02, QUAL-01
**UI hint:** yes
**Success Criteria**:
1. A user can capture, edit, place in Today, complete, reopen, trash, restore, and undo a task through the browser against PostgreSQL.
2. Planned/Today intent remains distinct from deadline semantics and all temporal values have explicit timezone rules.
3. Duplicate mutation submission produces one durable effect and the same stable result.
4. Browser tests exercise real Phoenix/PostgreSQL happy, validation, stale, conflict, authentication-expired, empty, and retry states.
5. Domain/application modules have no dependency on React, HTTP transport, MCP, or client persistence.
6. Phase 1 proves the shared semantic boundary and web/API adapters for SRV-02; Electron, iPhone, and MCP adapter proofs remain assigned to Phases 3, 4, and 5.
**Plans:** 17 plans

Plans:
- [ ] 01-01-PLAN.md — Verify dependencies and gate the exact researched server runtimes.
- [ ] 01-02-PLAN.md — Execute server/ExUnit/concurrency Wave 0.
- [ ] 01-03-PLAN.md — Execute browser/contracts/Playwright Wave 0.
- [ ] 01-04-PLAN.md — Prove the authenticated capture Walking Skeleton and exact replay.
- [ ] 01-05-PLAN.md — Implement closed server authentication, recovery, sessions, and abuse controls.
- [ ] 01-06-PLAN.md — Make login, recovery, reauthentication, logout, and Sessions reachable.
- [ ] 01-07-PLAN.md — Deliver title/notes editing and explicit Inbox clarification.
- [ ] 01-08-PLAN.md — Deliver stable-ID project/tag management and assignment.
- [ ] 01-09-PLAN.md — Deliver safe, exact, paginated task activity.
- [ ] 01-10-PLAN.md — Own temporal storage/contracts and date editing once.
- [ ] 01-11-PLAN.md — Deliver timezone-correct lists, cursors, and Today ordering.
- [ ] 01-12-PLAN.md — Deliver complete/reopen as a dedicated vertical slice.
- [ ] 01-13-PLAN.md — Deliver Trash/restore as a dedicated vertical slice.
- [ ] 01-14-PLAN.md — Deliver persisted semantic conflict resolution.
- [ ] 01-15-PLAN.md — Deliver exact uncertain-delivery and auth-interruption recovery.
- [ ] 01-16-PLAN.md — Deliver bounded semantic undo and persistent recovery.
- [ ] 01-17-PLAN.md — Seal responsive/a11y and adversarial full-phase evidence.

### Phase 2: Synchronization and Replaceable Server
**Goal:** Keepling has a formally tested offline synchronization contract and an always-on, recoverable reference deployment.
**Mode:** mvp
**Requirements:** SRV-04..06, DATA-02..03, OPS-01..05, QUAL-02, QUAL-05
**UI hint:** no
**Success Criteria**:
1. Golden cross-runtime vectors prove accepted, duplicate, rejected, stale, conflict, tombstone, cursor, logout/account-switch, reconnect, and relaunch semantics.
2. The server atomically records idempotent mutation results, canonical snapshots, ordered scoped changes, and tombstones without relying on sockets for correctness.
3. A pinned app-plus-PostgreSQL topology reaches readiness locally and on a replaceable Hetzner VM provisioned from source.
4. Backup automation restores into a disposable environment and proves schema, representative data/history, login, read, and safe write/undo behavior.
5. Privacy tests reject raw task content and unsafe identifiers from logs, metrics, traces, and diagnostic bundles.

### Phase 3: Mac Daily Loop
**Goal:** Jon can dogfood the core loop in an always-open Electron Mac client, including durable offline work and process relaunch.
**Mode:** mvp
**Requirements:** MAC-01..05, QUAL-03..04, SRV-02 (Electron adapter proof)
**UI hint:** yes
**Success Criteria**:
1. The packaged Mac application supports quick capture, Inbox, Today, edit, complete/reopen, trash/restore, and undo with complete keyboard navigation.
2. Local projection and outbox commit atomically before the UI reports success; kill/relaunch retains every accepted local intent.
3. Reconnect acknowledges each mutation exactly by identity, never silently duplicates it, and shows structured conflicts rather than overwriting.
4. The renderer has no raw database, filesystem, credential, or unrestricted IPC access; packaged-artifact tests prove the actual installed boundary.
5. Jon can use the supported Mac loop daily without opening Things for those actions.

### Phase 4: Native iPhone Daily Loop
**Goal:** Jon can dogfood the same trustworthy core loop through a native, platform-integrated SwiftUI iPhone client.
**Mode:** mvp
**Requirements:** IOS-01..04, SRV-02 (iPhone adapter proof)
**UI hint:** yes
**Success Criteria**:
1. A physical iPhone supports capture, Inbox, Today, edit, complete/reopen, trash/restore, and undo with native touch and accessibility behavior.
2. Offline mutation, termination, relaunch, expired authentication, account fencing, duplicate replay, and structured conflict scenarios preserve intent and account isolation.
3. Background execution is only an acceleration; foreground launch/resume/reconnect always restores correctness from the durable outbox.
4. Dynamic Type, VoiceOver semantics, touch targets, and Reduce Motion alternatives pass the supported user flows.
5. Jon can use the supported iPhone loop daily without opening Things for those actions.

### Phase 5: Safe Agent Access
**Goal:** External AI tools can use Keepling meaningfully without bypassing its authorization, domain rules, or recovery model.
**Mode:** mvp
**Requirements:** MCP-01..05, SRV-02 (MCP adapter proof)
**UI hint:** yes
**Success Criteria**:
1. Representative MCP hosts can read bounded Inbox, Today, Upcoming, project, task, and search resources using least-privilege authorization.
2. A direct user request can capture, update, complete, or reopen exactly one task through closed schemas and stable, model-correctable errors.
3. Ambiguous matches mutate nothing; bulk/high-impact changes require a bound exact preview and explicit commit; stale previews fail atomically.
4. User-visible history shows typed actions, affected identities/revisions, result, actor, and recovery without exposing private chain of thought.
5. Deterministic, protocol, simulated-client, representative-model, and adversarial suites score final state and forbidden side effects.

### Phase 6: Portability and Trust Release
**Goal:** The dogfood product is portable, diagnosable, release-ready, and supported by exact cross-client evidence.
**Mode:** mvp
**Requirements:** DATA-01 and final verification of QUAL-03..05 across the released system
**UI hint:** yes
**Success Criteria**:
1. A versioned neutral export contains the complete supported user history and can be inspected without Keepling internals.
2. Exact server, web, packaged Electron, native archive, migration, backup, restore, and compatibility evidence is bound to one revision and retained.
3. Upgrade preflight, migrations, readiness, rollback guidance, doctor output, and host-replacement recovery succeed from documented operator commands.
4. Security policy, supported-version policy, SBOM/checksum/signing posture appropriate to distributed artifacts, privacy disclosures, and bounded support contract are public.
5. Jon has completed a sustained Mac+iPhone dogfood period with no unresolved data-loss, silent-overwrite, or recovery-severity defects in the supported loop.

## Progress

| Phase | Status | Requirements | Progress |
|-------|--------|--------------|----------|
| 1. One Trustworthy Task | ○ Pending | 13 | 0% |
| 2. Synchronization and Replaceable Server | ○ Pending | 12 | 0% |
| 3. Mac Daily Loop | ○ Pending | 7 | 0% |
| 4. Native iPhone Daily Loop | ○ Pending | 4 | 0% |
| 5. Safe Agent Access | ○ Pending | 5 | 0% |
| 6. Portability and Trust Release | ○ Pending | 1 + cross-cutting verification | 0% |

---
*Roadmap created: 2026-08-28 after project initialization*
