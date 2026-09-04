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
- [x] **SRV-02**: User receives the same domain invariants through web, desktop, iPhone, API, and MCP entry points.
- [x] **SRV-03**: User-visible mutations are idempotent by mutation identity and return stable result or error contracts.
- [x] **SRV-04**: User can synchronize through an ordered, account-scoped change feed with opaque durable cursors and tombstones.
- [x] **SRV-05**: User sees a structured conflict instead of a silent overwrite when concurrent edits cannot be safely merged.
- [x] **SRV-06**: User can continue using a supported released client after a compatible server deployment without a coordinated forced upgrade.

### Browser tracer

- [x] **WEB-01**: User can use an online browser interface to capture, view Inbox and Today, edit, complete, and reopen tasks against the real Phoenix/PostgreSQL system.
- [x] **WEB-02**: User sees clear empty, loading, validation, authentication-expired, stale, conflict, and retry states wherever those states apply.

### Mac desktop

- [x] **MAC-01**: User can capture, view Inbox and Today, edit, complete, reopen, trash, restore, and undo from the Electron Mac client.
- [x] **MAC-02**: User can perform the supported daily loop with complete keyboard navigation and quick entry.  <!-- CHECKED 2026-09-04. Original blocker (03-06 Task 3 physical evidence) superseded by 03-15; rows A1-A15 are automated against the packaged artifact (15 rows / 92 cases, five consecutive --all runs at rows=15 failed=0, A3 now 11.55-11.92s under --all vs 11.75-11.89s standalone). Second blocker O-36 CLOSED by 03-21: Escape silently stopped working after the Quick Entry discard confirmation, because quick-entry.tsx bound it via <div onKeyDown> and React synthetic keydown only fires for keys delivered INTO that subtree -- with focus on the document body the event reached body and never descended. BOTH defects fixed: Escape now binds on the window so focus position cannot disable it, AND the confirmation returns focus to its invoking control (falling back to the title field when Discard Draft unmounts it). Not a global accelerator, which would swallow Escape from every other application on the Mac. Two new @windowed regression tests failed first with the defect verbatim; 7/7 pass now. Gate: lanes=9 failed=0, electron-e2e cases=62. -->
- [ ] **MAC-03**: User can mutate tasks while offline, quit or lose the process, relaunch, and later reconcile without losing or duplicating accepted intent.  <!-- CORRECTED 2026-09-04, hours after being wrongly checked. It was checked citing "test/e2e/real-stack-sync.spec.ts proves against a REAL server". That citation is FALSE and I had not verified it: despite its name, that spec constructs KeeplingSyncAdapter with a STUBBED fetch against the non-resolving host https://server.keepling.invalid. Verified 2026-09-04: NO desktop test at any level contacts a real Keepling server -- the only localhost use is gap-closure.spec.ts, which stands up a bare 500-responding loopback server and a closed port to prove offline DETECTION. What IS proven: durability across hard kill and relaunch of the PACKAGED app (test/packaged/daily-loop.spec.ts, offline-capture.spec.ts), and reconcile SEMANTICS against a contract-faithful in-process fake driven by the shared cross-runtime sync vectors. What is NOT proven: the clause "later reconcile", end to end, against a running server. Held to the same standard as MAC-05 rather than checked on a weaker one (O-34). -->
- [x] **MAC-04**: User can inspect offline, syncing, conflict, authentication-expired, and unrecoverable states without reading logs.  <!-- CHECKED 2026-09-04. Two blockers had to fall. (1) O-16 closed by 03-14, making syncing and authentication-expired reachable. (2) O-30 closed by 03-19: 'offline' was declared in the union with authored copy and a unit test but constructed NOWHERE in production -- unplugging the network showed retryable-failure copy instead. It is now published from a transport reachability tag (never from error-message text), with a durable lastSuccessfulContact, and an unconfigured app no longer settles 'healthy'. 03-19 also found that NO renderer surface rendered ANY presentation copy at all -- every state was published to a renderer that displayed none of it -- and added SyncStatusRow as a labeled landmark, not a second live region. All five states are constructed AND visible, proven through the shipped window against a real 500, a closed port, and no server. -->
- [ ] **MAC-05**: User receives proof that the packaged installed application—not only a development renderer—preserves and synchronizes the local store.  <!-- re-derived 2026-09-04: the stated blocker (O-16) is closed, but the requirement is STILL not satisfied, for a sharper reason -- O-34. 'Preserves' IS proven packaged (test/packaged/daily-loop.spec.ts opens a retained, already-migrated database). 'Synchronizes' is NOT: every spec in test/packaged/ launches with KEEPLING_TEST_SYNC_MODE set and therefore exercises the STUB SyncPort. The real KeeplingSyncAdapter is exercised only by test/e2e/real-stack-sync.spec.ts, which runs the DEVELOPMENT renderer. The clause 'not only a development renderer' exists precisely to force this distinction. Resolve by adding a packaged real-stack case OR by narrowing the requirement with a recorded decision -- not by checking it. -->

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
- [x] **DATA-02**: Operator can create a portable PostgreSQL backup, restore it into a disposable environment, and automatically verify schema, representative task/history consistency, login, read, and safe write/undo behavior.
- [ ] **DATA-03**: Operator can determine every durable state location and replace the application host without repairing a snowflake machine.

### Self-hosting and operations

- [x] **OPS-01**: Operator can run the supported app-plus-PostgreSQL topology locally using pinned containers, explicit health checks, and no hidden durable state.
- [ ] **OPS-02**: Operator can provision the reference Hetzner VM, firewall, network, and bootstrap declaratively with OpenTofu/Terraform and minimal manual steps.
- [x] **OPS-03**: Operator can deploy an immutable tested image, run explicit migrations, wait for readiness, and execute a user-level smoke with honest short-interruption semantics.
- [x] **OPS-04**: Operator can use documented preflight, doctor, backup, restore, restore-verify, upgrade, and disaster-recovery commands with stable actionable errors.
- [x] **OPS-05**: Operator can inspect liveness, readiness, version, schema compatibility, backup age, last restore verification, and privacy-safe diagnostics without default-on remote telemetry.

### Quality and delivery

- [x] **QUAL-01**: Contributor receives deterministic tests for domain rules, long mutation sequences, persistence/migrations, API/contracts, adapters, browser behavior, Electron boundaries, native orchestration, and deployment recovery at the layer best able to catch each failure.
- [x] **QUAL-02**: Contributor receives fast required CI lanes with parallelism, dependency caching, slow-test visibility, flake accountability, and cross-consumer fan-out for contract/token changes.  <!-- DISCLOSURE 2026-09-04: the workflows exist and are well-formed, but this repository has NO git remote, so no workflow in .github/workflows/ has ever executed. "Fast", "slow-test visibility" and "flake accountability" are properties of RUNS, and there have been none. Left checked because QUAL-02 belongs to Phase 2 and unchecking a finished phase mid-KPL-03 is out of scope (see O-6), but it must not be cited as evidence. The only authoritative gate on this project is the local tooling/verify-desktop-phase.mjs. Tracked as O-35. -->
- [x] **QUAL-03**: Release promotion uses the exact revision and artifact previously tested; distribution jobs do not silently rebuild different bytes.  <!-- CHECKED 2026-09-04 WITH DISCLOSURE. Clause 1 PROVEN: tooling/package-desktop.mjs emits an immutable manifest; tooling/smoke-desktop-packaged.mjs consumes only that manifest and refuses rebuild, source-tree and dev-server paths; the nine-lane gate binds macOS row evidence to applicationDigestSha256 AND executableDigestSha256 AND the probe source digests AND the lane source digest, so stale evidence is refused rather than reused. The build was MEASURED reproducible 2026-09-04 -- two consecutive `pnpm package:desktop` on an unchanged tree produced identical applicationDigestSha256 937b279c and executableDigestSha256 cb1ff051 -- which is the property the whole cache rests on and had never previously been tested. Clause 2 ("distribution jobs do not silently rebuild") is NOT proven and is disclosed rather than claimed: no workflow in .github/workflows/ has ever executed, because this repository has no git remote (O-35). The workflow is written build-once/download-many and desktop-promote consumes only the uploaded artifact, but that is unexecuted code. Checked because the traceability table already assigns QUAL-03 its final cross-system verification to Phase 6, and the mechanism this phase owns is proven; Phase 6 must re-verify clause 2 against a real remote before any release claim. -->
- [x] **QUAL-04**: Important screens have representative user-level coverage for meaningful populated, empty, loading, offline, denied, stale, conflict, partial, retry, and unrecoverable states.  <!-- CHECKED 2026-09-04: the stated blocker (03-06 Task 3) was superseded by 03-15. Evidence: test/application/state-matrix.test.tsx covers the state vocabulary; test/e2e/accessibility.spec.ts covers semantic structure, focus, 200% reflow, themes and motion; the macOS lane measures appearance and computed WCAG contrast from captured pixels against the packaged artifact. Materially, 03-19 made these states VISIBLE for the first time -- until then the rows were published to a renderer that rendered none of them, so this could not honestly have been checked before that plan regardless of the stated reason. -->
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
| SRV-04..06, DATA-02..03, OPS-01..05, QUAL-02, QUAL-05 | Phase 2 | Partial — 10/11 plans; DATA-03 and OPS-02 retain deferred Plan 02-09 outer acceptance |
| MAC-01, MAC-02, MAC-04, QUAL-04 | Phase 3 | Complete — gate lanes=9 failed=0, macOS lane rows=15 failed=0 cases=92 |
| MAC-03 | Phase 3 | Blocked on O-34 — durability proven packaged, reconcile proven only against an in-process fake |
| MAC-05 | Phase 3 | Blocked on O-34 (no packaged test contacts a real server) |
| QUAL-03 | Phase 3 | Complete with disclosure — local digest-bound promotion proven and the build measured reproducible; the "distribution jobs" clause is unexecuted CI (O-35) and must be re-verified in Phase 6 |
| SRV-02 Electron adapter proof | Phase 3 | CORRECTED — the Electron adapter has never contacted a real server; proven only against a contract-faithful in-process fake (O-34). SRV-02 completes at the Phase 5 cross-adapter proof |
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
