# Requirements: Keepling

**Defined:** 2026-08-28  
**Core Value:** Jon can trust Keepling as his daily task system on Mac and iPhone: capture is immediate, accepted changes are never silently lost or overwritten, and both human and agent actions remain inspectable and recoverable.

## v1 Requirements

### Personal GTD domain

- [x] **GTD-01**: User can capture a task with a title into Inbox and immediately receive a stable task identity.
- [x] **GTD-02**: User can clarify a task by editing its title, notes, project membership, tags, and temporal fields supported by v1.
- [x] **GTD-03**: User can deliberately place or remove a task in Today without conflating that choice with its deadline.
- [x] **GTD-04**: User can inspect upcoming scheduled tasks and deadlines using explicit timezone-aware semantics.
- [x] **GTD-05**: User can complete and reopen a task as idempotent domain transitions.
- [x] **GTD-06**: User can trash and restore a task without immediate hard deletion.
- [x] **GTD-07**: User can undo supported consequential mutations using a bounded, revision-aware handle.

### Identity and server authority

- [x] **SRV-01**: User can authenticate a personal account and authorize multiple owned devices without exposing server credentials to clients or agents.
- [ ] **SRV-02**: User receives the same domain invariants through web, desktop, iPhone, API, and MCP entry points.
- [x] **SRV-03**: User-visible mutations are idempotent by mutation identity and return stable result or error contracts.
- [x] **SRV-04**: User can synchronize through an ordered, account-scoped change feed with opaque durable cursors and tombstones.
- [x] **SRV-05**: User sees a structured conflict instead of a silent overwrite when concurrent edits cannot be safely merged.
- [x] **SRV-06**: User can continue using a supported released client after a compatible server deployment without a coordinated forced upgrade.

### Browser tracer

- [x] **WEB-01**: User can use an online browser interface to capture, view Inbox and Today, edit, complete, and reopen tasks against the real Phoenix/PostgreSQL system.
- [x] **WEB-02**: User sees clear empty, loading, validation, authentication-expired, stale, conflict, and retry states wherever those states apply.

### Mac desktop

- [ ] **MAC-01**: User can capture, view Inbox and Today, edit, complete, reopen, trash, restore, and undo from the Electron Mac client.
- [ ] **MAC-02**: User can perform the supported daily loop with complete keyboard navigation and quick entry.
- [ ] **MAC-03**: User can mutate tasks while offline, quit or lose the process, relaunch, and later reconcile without losing or duplicating accepted intent.
- [ ] **MAC-04**: User can inspect offline, syncing, conflict, authentication-expired, and unrecoverable states without reading logs.
- [ ] **MAC-05**: User receives proof that the packaged installed application—not only a development renderer—preserves and synchronizes the local store.

### Native iPhone

- [ ] **IOS-01**: User can capture, view Inbox and Today, edit, complete, reopen, trash, restore, and undo in a native SwiftUI iPhone client.
- [ ] **IOS-02**: User can mutate tasks without connectivity, terminate the app, relaunch, and later reconcile without losing or duplicating accepted intent.
- [ ] **IOS-03**: User receives a platform-native touch, accessibility, Dynamic Type, and Reduce Motion experience for the supported daily loop.
- [ ] **IOS-04**: User can distinguish local, syncing, conflict, authentication-expired, and unrecoverable states on a physical iPhone.

### Agent and MCP access

- [ ] **MCP-01**: Authorized agent can read bounded, paginated Inbox, Today, Upcoming, project, task, and search views without direct database access.
- [ ] **MCP-02**: Authorized agent can capture, update, complete, and reopen a single task through closed semantic schemas, least-privilege scopes, idempotency, expected revisions, and stable errors.
- [ ] **MCP-03**: Ambiguous agent requests return candidate objects and perform no mutation.
- [ ] **MCP-04**: User can see which agent action occurred, its affected identities/revisions, and an available undo path without exposing private chain of thought.
- [ ] **MCP-05**: Bulk or destructive agent changes require an exact bound preview and explicit commit; stale commits fail atomically with zero partial writes.

### Data ownership and recovery

- [ ] **DATA-01**: User can export all personal Keepling data in a versioned, documented, neutral format without needing internal database knowledge.
- [ ] **DATA-02**: Operator can create a portable PostgreSQL backup, restore it into a disposable environment, and automatically verify schema, representative task/history consistency, login, read, and safe write/undo behavior.
- [ ] **DATA-03**: Operator can determine every durable state location and replace the application host without repairing a snowflake machine.

### Self-hosting and operations

- [ ] **OPS-01**: Operator can run the supported app-plus-PostgreSQL topology locally using pinned containers, explicit health checks, and no hidden durable state.
- [ ] **OPS-02**: Operator can provision the reference Hetzner VM, firewall, network, and bootstrap declaratively with OpenTofu/Terraform and minimal manual steps.
- [ ] **OPS-03**: Operator can deploy an immutable tested image, run explicit migrations, wait for readiness, and execute a user-level smoke with honest short-interruption semantics.
- [ ] **OPS-04**: Operator can use documented preflight, doctor, backup, restore, restore-verify, upgrade, and disaster-recovery commands with stable actionable errors.
- [ ] **OPS-05**: Operator can inspect liveness, readiness, version, schema compatibility, backup age, last restore verification, and privacy-safe diagnostics without default-on remote telemetry.

### Quality and delivery

- [x] **QUAL-01**: Contributor receives deterministic tests for domain rules, long mutation sequences, persistence/migrations, API/contracts, adapters, browser behavior, Electron boundaries, native orchestration, and deployment recovery at the layer best able to catch each failure.
- [ ] **QUAL-02**: Contributor receives fast required CI lanes with parallelism, dependency caching, slow-test visibility, flake accountability, and cross-consumer fan-out for contract/token changes.
- [ ] **QUAL-03**: Release promotion uses the exact revision and artifact previously tested; distribution jobs do not silently rebuild different bytes.
- [ ] **QUAL-04**: Important screens have representative user-level coverage for meaningful populated, empty, loading, offline, denied, stale, conflict, partial, retry, and unrecoverable states.
- [x] **QUAL-05**: Diagnostic logs and traces are structured, bounded, correlated, and tested not to emit task titles, notes, prompts, tokens, or arbitrary high-cardinality identifiers.

## v2 Requirements

### Native leverage

- **IOS-05**: User can capture or act through App Intents, Shortcuts, share extensions, widgets, and carefully scoped notifications where dogfooding proves value.
- **MAC-06**: User can use signed-build-dependent Keychain, launch-at-login, and automatic-update behavior when distribution requirements justify Apple credentials.

### Platform expansion

- **WEB-03**: User can perform durable browser-offline mutations if browser dogfooding demonstrates a need after Mac and iPhone synchronization is proven.
- **AND-01**: User can use a native-quality Android client after real demand justifies a fourth client and distribution lane.
- **DESK-01**: User can install Windows and Linux Electron artifacts after demand justifies their packaging, signing, and support matrix.

### Product expansion

- **REC-01**: User can define and complete recurring tasks using explicitly researched recurrence and exception semantics.
- **REM-01**: User can configure native reminders without creating a general notification orchestration product.
- **CAL-01**: User can use narrowly justified calendar integration without turning Keepling into a calendar or time-blocking suite.
- **ATT-01**: User can attach files after object storage, backup consistency, quotas, and privacy are designed.
- **HOST-01**: User can purchase an official hosted Keepling instance after self-host retention and demand validate the operational product.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Collaboration and team workspaces | Changes the personal-product identity, authorization, conflicts, support, and UX |
| Enterprise SSO, SCIM, roles, policy, and administration | No enterprise product is planned |
| General AI chat, embedded model hosting, RAG, or agent memory | Keepling is a deterministic capability provider for external models |
| Arbitrary agent SQL, raw patching, URL fetching, or unconstrained export | Violates domain invariants, privacy, and least privilege |
| Full event sourcing | Snapshot persistence plus typed facts/change feed provides required value with lower cost |
| CRDTs | Structured conflicts and narrow safe merges are easier to reason about for this domain |
| Microservices, Kubernetes, Redis, Elasticsearch | Unnecessary operational and dependency surface for the initial product |
| Equal support for every self-host platform | One portable contract and one excellent reference deployment bound support load |
| Feature-by-feature parity with Todoist, TickTick, or OmniFocus | Breadth would destroy the focused Things-like experience |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| GTD-01..07, SRV-01, SRV-03, WEB-01..02, QUAL-01 | Phase 1 | Gaps Found |
| SRV-02 shared semantic boundary + web/API adapter proof | Phase 1 | Pending partial proof |
| SRV-04..06, DATA-02..03, OPS-01..05, QUAL-02, QUAL-05 | Phase 2 | Pending |
| MAC-01..05, QUAL-03..04, SRV-02 Electron adapter proof | Phase 3 | Pending |
| IOS-01..04, SRV-02 iPhone adapter proof | Phase 4 | Pending |
| MCP-01..05, SRV-02 MCP adapter proof and cross-adapter completion | Phase 5 | Pending |
| DATA-01, QUAL-03..05 and cross-client release evidence | Phase 6 | Pending |

Some quality requirements intentionally receive initial implementation in an earlier phase and final cross-product verification in Phase 6; the canonical ownership phase is the first listed phase. SRV-02 is intentionally proven incrementally: Phase 1 establishes the invariant-owning semantic boundary and web/API adapter, while Phases 3–5 add Electron, iPhone, and MCP adapter proofs. It is not complete until the Phase 5 cross-adapter proof passes.

**Coverage:**

- v1 requirements: 42 total
- Mapped to phases: 42
- Unmapped: 0 ✓

---
*Requirements defined: 2026-08-28*
*Last updated: 2026-08-28 after initial roadmap creation*
