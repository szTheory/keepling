---
gsd_state_version: 1.0
milestone: v1.0
current_phase: 06
current_phase_name: Portability and Trust Release
status: executing
stopped_at: Completed 06-12-PLAN.md
last_updated: "2026-09-11T21:57:05.985Z"
last_activity: 2026-09-11
last_activity_desc: Phase KPL-06 execution started
state_head: 50827fc7c939ea25a51effb379b123629fb0146b
progress:
  total_phases: 6
  completed_phases: 4
  total_plans: 110
  completed_plans: 107
milestone_name: milestone
---

# Project State

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-08-31)

**Core value:** Jon can trust Keepling as his daily task system on Mac and iPhone: capture is immediate, accepted changes are never silently lost or overwritten, and both human and agent actions remain inspectable and recoverable.  
**Current focus:** Phase KPL-06 — Portability and Trust Release

## Current Position

Phase: KPL-06 (Portability and Trust Release) — EXECUTING
Plan: 12 of 13
Total Plans in Phase: 13
Status: Executing Phase KPL-06
Last activity: 2026-09-11 — Phase KPL-06 execution started
Last Activity Description: Phase KPL-06 execution started
Progress: [█████████░] 94%

## Accumulated Context

### Decisions

- [Phase 03]: D-49 — the device-grant credential class may mutate; the command surface is extended to accept it rather than forking a native API, because iPhone and MCP would inherit the same split and SRV-02 exists to keep one set of semantic invariants across adapters.
- [Phase 03]: A bearer-authenticated request requires no Origin, because CSRF rides ambient cookie authentication a browser attaches automatically; the browser posture is unchanged and pinned by tests rather than by comment.
- [Phase 03]: Durable command bytes carry an optional `type` discriminator that the server verifies against the endpoint and never routes on — an outbox that retries exact bytes has nothing else to route by after a relaunch.
- [Phase 03]: Outbound ordering is enforced by resource key (`task:<id>`), never by a journal dependency — a dependency only clears on an accepted outcome, so once conflicts became reachable it would strand a task's whole chain in the outbox forever with nothing able to settle it.
- [Phase 03]: The client settles a CLOSED list of server refusals (the four 409 conflict codes, every 422, `invalid_command`, `task_not_found`). A 401 is its own tagged state and is never collapsed into a per-mutation rejection, because every authentication problem carries `retryable: false`. Everything unlisted keeps throwing — an unheard answer is never a settled one.
- [Phase 03]: `CommandAcknowledgement.outcome` stays strict at `accepted`/`already_satisfied`, because that is what the contract publishes; a conflict arrives as a 409 problem, not as a 200. Widening the acknowledgement validator would convert a genuine contract violation into a silent one.
- [Phase 03]: A refusal never overwrites the local row from the server's answer and never replays the canonical shadow over it — a 409 carries only the affected fields, and replaying would erase the person's edit while the copy promises it is still there.
- [Phase 03]: Quick Entry binds Escape on the window, not on a React subtree, so no focus position can silently disable it; a global accelerator was rejected because it would swallow Escape from every other Mac application.
- [Phase 03]: The real-stack lane is its own directory and Playwright project, so the other packaged specs stay runnable without Elixir/PostgreSQL and a zero-case real-stack run cannot hide inside another lane’s count.
- Keepling is the confirmed working product and repository name; formal trademark/namespace clearance remains open.
- One coordinating monorepo owns planning, apps, shared contracts/tokens, infrastructure, and release evidence.
- Framework directories are documented now but scaffolded only when their vertical phase starts.
- Phoenix/PostgreSQL is canonical; React is shared by browser/Electron; iPhone remains native SwiftUI.
- Offline correctness comes from local durable projection/outbox plus idempotent server reconciliation, not background scheduling or WebSockets.
- The first milestone is personal dogfood, not commercial launch.
- GSD uses coarse phases, parallel execution, committed planning docs, research/plan-check/verifier quality gates, and no automatic continuation into Phase 1.
- [Phase 01]: The blanket approval applies only to the eight inspected exact package versions; any version change requires a new provenance review and disposition.
- [Phase 01]: Runtime selection is repository-owned through asdf environment variables and the absolute Homebrew postgresql@18 keg, without modifying .tool-versions.
- [Phase 01]: [Phase KPL-01]: Keepling.Application supervises only Keepling.Repo until Plan 01-03 adds the transport runtime, keeping the core free of Phoenix web dependencies.
- [Phase 01]: [Phase KPL-01]: Database URLs and endpoint signing secrets are environment-scoped runtime inputs; production additionally requires PHX_HOST.
- [Phase 01]: [Phase KPL-01]: Playwright uses one loopback reverse proxy while PostgreSQL, Phoenix, and Vite remain separately owned process groups.
- [Phase 01]: [Phase KPL-01]: openapi-typescript 7.13.0 uses a root-only TypeScript 5.9.3 peer without changing the web TypeScript 6 toolchain.
- [Phase 01]: [Phase KPL-01]: The consolidated Phase 1 runner lists and executes only lanes whose artifacts currently exist.
- [Phase 01]: The OTP composition root starts Repo first and Endpoint last, retaining DNSCluster and Phoenix.PubSub without outward imports in semantic domain/application roots.
- [Phase 01]: Concurrency tests use per-process unboxed SQL Sandbox checkouts, PostgreSQL backend PIDs, and an explicit reusable barrier.
- [Phase 01]: Deterministic command tests thread an immutable clock and preselected identities explicitly through each scenario.
- [Phase 01]: Capture fingerprints use canonical semantic fields, including the trimmed title, while mutation identity remains the account-scoped receipt key.
- [Phase 01]: Terminal acknowledgements and activity field deltas are persisted as native JSONB values so first delivery, lookup, and replay preserve one closed shape.
- [Phase 01]: Mutation lookup returns the original terminal HTTP status and the generated/browser contracts expose acknowledgement warnings and terminal problems.
- [Phase 01]: Setup capabilities are 32 random bytes, valid for 60–3600 seconds, persisted only as SHA-256 hashes, and serialized through one locked account_setup singleton row.
- [Phase 01]: Account timezone changes update only the account setting and three affected view revisions, while closed timezone_changed facts remain separate from task activity.
- [Phase 01]: Tzdata uses its pinned vendored IANA snapshot with automatic network updates disabled; Keepling starts no remote timezone updater and has no Hackney call path.
- [Phase 01]: Browser sessions use opaque random credentials stored only as SHA-256 hashes; login, recovery, and reauthentication rotate cookie and CSRF state.
- [Phase 01]: Recovery is an operator-issued hash-only one-use capability whose serialized consumption replaces the password and revokes prior sessions.
- [Phase 01]: Authentication limiting uses supervised isolated flow/account/source digests with identifier-free allow-listed audit and telemetry facts.
- [Phase KPL-01]: Browser capability routing accepts both path-token and existing operator query-token URLs through one closed DTO-backed form boundary.
- [Phase KPL-01]: Reauthentication retains the mounted draft and fixed interrupted identity, then supplies rotated CSRF state to the exact resume continuation.
- [Phase KPL-01]: Session activity remains coarse and is never presented as a trusted-device fingerprint.
- [Phase 01]: [Phase KPL-01]: Task detail contract v1 trims outer title whitespace, bounds titles at 512 Unicode scalar values, and preserves plain-text notes up to 50000 scalar values.
- [Phase 01]: [Phase KPL-01]: Edit and clarify send only touched fields with matching base values; the locked server task and pure domain own rebase and conflict decisions.
- [Phase 01]: [Phase KPL-01]: Inbox membership is explicit; only clarify_task removes it and only return_to_inbox restores it.
- [Phase 01]: [Phase KPL-01]: The routed browser editor retains drafts and a fixed mutation identity until exact acknowledgement.
- [Phase 01]: Projects and tags use stable opaque IDs with versioned normalized active-name uniqueness; display names remain mutable projections.
- [Phase 01]: Task organization writes carry stable IDs and base values; account-scoped server locks own validation, merge, revision, and exact acknowledgement.
- [Phase 01]: Archived organizations remain visible and removable in historical assignments but cannot receive new assignments.
- [Phase 01]: Accepted task activity is canonical account-lifetime user data committed atomically but represented separately from task state, receipts, recovery metadata, and telemetry.
- [Phase 01]: Activity cursors bind account, task, full newest-first keyset, and activity-view revision so projected-label changes fail explicitly stale.
- [Phase 01]: Task history renders generated closed DTOs as untrusted React text with exact account-zone time and technical identifiers only in disclosures.
- [Phase 01]: Planned placement and deadline remain independent nullable civil dates; Today intent changes only planned_on and planned-after-deadline is accepted with an exact warning.
- [Phase 01]: Plan for Today resolves from the validated account IANA timezone and an injected acceptance instant; later timezone changes never rewrite stored civil dates.
- [Phase 01]: Active unfinished task classification preserves every applicable planned and deadline reason while deriving Today and Upcoming from the canonical account day.
- [Phase 01]: Browser command composition uses stable mutation identities and acknowledged revisions, retaining drafts until the terminal exact receipt.
- [Phase 01]: Paginated Inbox projection uses /api/v1/views/inbox while the supported full Inbox editor snapshot remains compatible.
- [Phase 01]: Task-view cursors authenticate account, view, complete keyset, view revision, and Today order revision; relevant changes stale them explicitly.
- [Phase 01]: Today order is dense, section-scoped, server-owned, account-lock serialized, and changed only by semantic earlier/later commands.
- [Phase 01]: Ambiguous Today delivery retains and retries the exact original mutation identity against a durable terminal receipt.
- [Phase 01]: Plan 01-13 expands nullable completed_at only as a projection seam; Plan 01-14 owns completion lifecycle writes.
- [Phase 01]: Lifecycle staleness is scoped to the latest accepted complete/reopen revision, allowing unrelated-edit rebase while opposing lifecycle intent conflicts on completed_at.
- [Phase 01]: Completion preserves inbox_state and active projections filter completed_at so reopen can recompute visibility from canonical task fields.
- [Phase 01]: Browser lifecycle reconciliation requires exact task and mutation acknowledgement identities and reads reopen destinations from authoritative projections.
- [Phase 01]: Trash is retained canonical task state with an immutable accepted UTC instant and no purge or retention mechanism.
- [Phase 01]: Trash and restore require the exact current revision before already-satisfied intent; other writes conflict while trashed.
- [Phase 01]: Restore acknowledgements carry server-derived destinations so clients never predict projection visibility.
- [Phase 01]: Task detail fields rebase only when canonical truth equals submitted base or requested value; merge authority and invariant checks remain server/domain-owned.
- [Phase 01]: Unmergeable outcomes are committed account-scoped conflict rows linked to the original receipt; resolution uses a fresh mutation identity against the stored latest revision.
- [Phase 01]: The browser submits only closed mine/current selections and reconciles only acknowledgements matching mutation, task, and conflict identities.
- [Phase 01]: Prepare and retain immutable serialized command bytes before submission; every lookup, retry, and authentication resume uses the exact original identity.
- [Phase 01]: Authentication recovery resumes the interrupted lookup or send operation instead of minting or ambiguously replaying intent.
- [Phase 01]: Fault controls compile only in test, require a random per-run credential, and inject privacy-safe faults around the real acceptance/response boundary.
- [Phase 01]: Undo capabilities are 32-byte URL-safe values derived from a server-secret HMAC over a random UUID; PostgreSQL and durable receipts retain only the SHA-256 hash or derivation identity, never the raw handle.
- [Phase 01]: The v1 undo matrix is closed to task details, clarify/return, plan/unplan, complete/reopen, and Trash/restore; unsupported commands do not mint nested undo.
- [Phase 01]: Undo validates the exact produced revision under account-scoped locks and atomically commits inverse state, linked activity, consumption, and receipt.
- [Phase 01]: AppShell retains only the latest recovery action across routes and uncertain retries reuse one fixed mutation identity without intercepting native Cmd/Ctrl-Z.
- [Phase 01]: Phase 1 UI intent is canonical in one DTCG-compatible semantic-token source with checked-in CSS roles.
- [Phase 01]: The 1024–1063px compact-wide seam preserves 224px navigation and 480px detail while compressing the list to 320px.
- [Phase 01]: Mounted task views reconcile accepted semantic-command snapshots immediately through task-scoped acknowledgements.
- [Phase 01]: Authentication continuations are keyed by semantic intent and mutation identity, preserve insertion order, and are removed only after successful settlement.
- [Phase 01]: Authenticated route content remains mounted during recovery and is hidden accessibly without a layout-affecting DOM wrapper.
- [Phase 01]: The test environment permits full-suite successful sign-in volume while production authentication abuse limits remain unchanged.
- [Phase 01]: The exact submission snapshot locks conflict choices, Save resolution, and Keep editing through in-flight, unknown, and authentication-required states.
- [Phase 01]: Today ordering uses the exact submission snapshot as its global lock authority; transient progress presentation never decides whether another move may begin.
- [Phase 01]: Session administration reserves definitive changed, unchanged, revoked, active, and logged-out outcomes for authoritative inventory or authentication-probe evidence.
- [Phase 01]: The recent-auth session DELETE route gains the credentialed fault plug only in test and only after authentication, trusted-origin/CSRF, and recent-auth authorization have completed.
- [Phase 01]: Apply one explicit same-origin CSP before Plug.Static so the application shell and API share the same restrictive execution boundary.
- [Phase 01]: Route every TaskViews transaction and SQL call through wrappers consuming the same positive 10-second production timeout.
- [Phase 01]: Dispose authentication continuations by route owner while fencing authentication generation and owner liveness, including React Strict Mode rehearsal.
- [Phase 01]: Keep 1024–1063px on drawer navigation so the 360px list and 480px detail minimums remain intact.
- [Phase 01]: Begin the persistent 224px navigation region at exactly 1064px and cap lists at 440px.
- [Phase 01]: Use one shell-owned main landmark with embedded list and editor sections.
- [Phase 01]: Consequential browser choices use one Base UI Alert Dialog wrapper with explicit safe initial and trigger-return focus.
- [Phase 01]: Current-session removal delegates to AppShell logout; only another-session removal uses the revoke endpoint.
- [Phase 01]: Authentication-required during uncertain logout reconciliation proves the current browser session is signed out.
- [Phase 01]: Supporting shared colors remain semantic token roles without declaring a final brand palette.
- [Phase 01]: [Phase KPL-01]: Production UI drift is enforced by a TypeScript-AST scan of executable className regions, not raw comments or fixtures.
- [Phase 01]: [Phase KPL-01]: Arbitrary visual utilities require a named semantic reason and a declared token or UI-SPEC contract value.
- [Phase 01]: [Phase KPL-01]: Conflict and uncertain-delivery state machines remain unchanged by mechanical presentation normalization.
- [Phase 02]: [Phase KPL-02]: Reference synchronization state uses closed JSON-compatible string-keyed maps so clients share behavior without sharing persistence records.
- [Phase 02]: [Phase KPL-02]: Ready pushes are bounded to 25 and pulls to 50 changes; overlapping resource keys preserve FIFO while disjoint lanes progress.
- [Phase 02]: [Phase KPL-02]: Only accepted and already_satisfied outcomes satisfy durable dependencies.
- [Phase 02]: [Phase KPL-02]: Immutable command bytes must carry the same mutation identity as their durable envelope and SHA-256 fingerprint.
- [Phase 02]: Synchronization generation is installation-grant scoped so replay or revocation fences exactly one native installation without invalidating another.
- [Phase 02]: Issuer, origin, stable server instance, account subject, and generation come only from server configuration and locked rows; closed public-client requests reject extra authority fields.
- [Phase 02]: Consumed refresh hashes remain as lineage evidence, and the first replay revokes and advances the family fence exactly once.
- [Phase 02]: [Phase KPL-02]: Every first delivery reserves one account sequence before semantic resource locks; ordinal zero is the terminal command outcome and related canonical envelopes follow deterministically.
- [Phase 02]: [Phase KPL-02]: Feed cursors and bootstrap cursors are separate authenticated codecs bound to issuer, origin, server instance, account subject, installation generation, restore epoch, and protocol train.
- [Phase 02]: [Phase KPL-02]: Bootstrap keyset order need not contain every concurrent write; strict feed catch-up after the captured high-water is the gap-free authority.
- [Phase 02]: [Phase KPL-02]: Task organization removal emits membership tombstones while the owning task and Trash remain canonical snapshots.
- [Phase KPL-02]: Native client_id is closed to electron or iphone and maps only to the application-owned client kind; no secret or namespace assertion enters issuance.
- [Phase KPL-02]: Both OAuth grant types execute through POST /oauth/token, while /oauth/token/refresh is an exact documented alias that gives refreshNativeGrant its required generated operation identity.
- [Phase KPL-02]: The bearer pipeline assigns only current_device_grant_id and the five-field server namespace returned by the account application; downstream transports never reconstruct authority from request data.
- [Phase 02]: The active protocol floor comes only from server distribution state, the inclusive deprecation deadline, or a documented evidence-bearing security emergency; marketing/build versions remain metadata-only.
- [Phase 02]: The unversioned compatibility route accepts exactly one client min/max train range and publishes a closed release-only response without private state.
- [Phase 02]: Rollback eligibility requires an exact immutable OCI digest plus both schema and protocol inclusion.
- [Phase 02]: [Phase KPL-02]: Sync transport accepts namespace authority only from the authenticated DeviceGrant assign, enriched with finalized restore epoch and current protocol train.
- [Phase 02]: [Phase KPL-02]: Feed coverage advances only to the last returned ordered envelope and remains separate from acknowledgement settlement.
- [Phase 02]: [Phase KPL-02]: Sync diagnostics expose only closed operation and outcome metadata across success and failure paths.
- [Phase 02]: [Phase KPL-02]: D-49 trust states are generated wire vocabulary; D-50 through D-54 remain storage-neutral presentation and privacy vectors for platform clients.
- [Phase 02]: [Phase KPL-02]: Operational exit classes are frozen as success 0, usage 2, safety refusal 10, dependency 20, compatibility 30, recovery 40, and execution 50.
- [Phase 02]: [Phase KPL-02]: Public readiness excludes backup and WAL freshness; those facts degrade operator status and refuse deploy preflight instead.
- [Phase 02]: [Phase KPL-02]: Operator HTTP status uses a distinct minimum-32-byte credential retained only as a SHA-256 hash in application configuration.
- [Phase 02]: [Phase KPL-02]: Source and release commands share one Elixir parser, renderer, policy, and exit contract; release inspection starts only Ecto and Repo through Ecto.Migrator.with_repo/3.
- [Phase 02]: KPL-02-07 promotes only an exact tested OCI digest and names the same digest in migration, app, and operator metadata.
- [Phase 02]: KPL-02-07 keeps PostgreSQL private with all durable database and Caddy state in explicit host-backed named volumes.
- [Phase 02]: KPL-02-07 permits rollback only when the prior tested digest includes the migrated schema and protocol target; otherwise operators forward-fix.
- [Phase 02]: Recovery uses a parameterized encrypted S3-compatible primary and independently credentialed append-only dated mirror snapshots; recovery credentials never reach the app container, and mirror retention is activated only after restore proof.
- [Phase 02]: Restore readiness requires an exclusive target lease, complete semantic proof, and transactional finalization of a fresh synchronization epoch.
- [Phase 02]: Completed restore verification is idempotently keyed by source digest, digested target, and verifier version.
- [Phase 02]: Required CI invokes the same per-lane Phase 2 runner used locally, with positive case counts, seeds, timings, and tracked-input digests preventing vacuous success.
- [Phase 02]: Credentialed host replacement and DNS acceptance remains an explicit non-passing protected outer lane until deferred Plan 02-09 succeeds; schedules, skips, and missing credentials never count as green evidence.
- [Phase 02]: Novel live-boundary failures become hermetic fixtures first; real provider/DNS rehearsal is rare, single-attempt, change-triggered outer acceptance rather than a PR or debug loop.
- [Phase 03]: Use direct Vite builds for all four Electron process roles without the experimental Forge Vite plugin.
- [Phase 03]: Keep main, preload, and worker as Node 24 CommonJS outputs while the renderer uses browser-only relative packaged assets.
- [Phase 03]: Declare Electron 44.1.1, Forge 7.11.2, and Zod 4.5.4 without installing or changing the lockfile before provenance approval.
- [Phase 03]: Desktop test evidence uses named non-watch lanes with explicit zero-case refusal and disposable system-temporary profiles.
- [Phase 03]: Package-once binds committed inputs and exact application, executable, ZIP, and embedded-runtime identity before external manifest-only smoke.
- [Phase 03]: D-03 remains a one-way trust contract: drafts make no durability claim, Saved on this Mac follows atomic local COMMIT, and Synced follows only an exact mutation identity and fingerprint acknowledgement.
- [Phase 03]: electron@44.1.1 and zod@4.5.4 were installed only after explicit provenance approval; better-sqlite3 remains absent because packaged node:sqlite passed.
- [Phase 03]: The selected user-data profile owns Electron's single-instance lock before bootstrap, so isolated profiles remain independent while duplicate ownership of one profile is rejected.
- [Phase 03]: All runtime dependencies are bundled into the four process outputs, so Forge excludes node_modules and packages only those outputs plus migrations.
- [Phase 03]: Desktop sync performs bounded pull-before-push passes and preserves exact serialized command bytes for retry authority.
- [Phase 03]: Desktop storage activates only the complete five-field namespace returned by authenticated server token responses; client-derived authority is forbidden.
- [Phase 03]: Sign-out fences local intent and clears credentials before best-effort remote revocation.
- [Phase 03]: Synchronization and recovery UI consume one monotonic main-owned closed presentation projection.
- [Phase 03]: The ClientFacade extraction boundary is presentation-only and frozen: packages/web-ui exposes only named snapshot/subscription plus task/navigation/recovery operations, verified by a source-scan import-boundary test.
- [Phase 03]: The shared Workspace/CaptureForm/TaskList slice is proven via a browser adapter and a deterministic desktop-facade fixture but is not wired into the production Inbox route yet; WorkspaceShell exposes it behind an explicit useSharedWorkspace opt-in for future workspace expansion.
- [Phase 03]: Desktop edit/complete/reopen/trash/restore/moveToday/undo are local-only durable commits in this plan (no outbox mutation, never claims Synced); real desktop sync for these commands is deferred follow-on scope.
- [Phase 03]: Undo is single-level (latest supported change) via a last_local_action singleton, matching D-14; browser adapter extended for real (not stubbed) to satisfy the shared ClientFacade interface change without expanding apps/web's shipped surface.
- [Phase 03]: apps/desktop/main/index.ts now instantiates DesktopLifecycle plus Plan 03-04's native menu/Quick Entry/Settings against the real shipped entry point, closing O-9
- [Phase 03]: Close destroys the disposable main window; Dock activation and a second launch both recreate it via DesktopLifecycle.ensureWindow() from a persisted, display-clamped bounds/fullscreen snapshot
- [Phase 03]: D-06 renderer-semantic restoration (destination/selection/sidebar/draft) is a disclosed gap requiring a renderer<->main IPC channel outside this plan's authorized scope
- [Phase 03]: [Phase KPL-03]: Worker-thread store-open failures self-heal via transparent reopen on the next request instead of a dedicated retry operation, and never auto-reset the store.
- [Phase 03]: [Phase KPL-03]: removeLocalNamespaceData never receives a sync/network port as input, making server-deletion structurally unreachable from local-data removal; DesktopApplication.removeLocalData is implemented and tested but not yet wired into main/index.ts or preload/index.ts.
- [Phase KPL-03]: O-15 CLOSED: bootstrap() constructs SafeStorageCredentialAdapter; prior path was credentials: undefined.
- [Phase KPL-03]: O-12 CLOSED: removeLocalData reachable via named preload contract + sender-validated IPC; single-field request schema keeps server deletion structurally unreachable.
- [Phase KPL-03]: O-11 CLOSED: D-06 renderer-semantic restoration (destination, selection, scroll anchor, draft) proven across a real relaunch; pane sizes N/A (no resizable-pane UI exists).
- [Phase KPL-03]: O-1 RESOLVED: apps/web keeps routed Inbox content; useSharedWorkspace documented as permanent future-facing API.
- [Phase KPL-03]: Rows A1-A15 of the physical-accessibility checklist are automated at the macOS layer (AXUIElement tree, CGEvent keystrokes, real input sources, real system settings, WCAG contrast from rendered pixels); the dogfood contract keeps only informal feedback with no checklist, evidence record, or sign-off.
- [Phase KPL-03]: The macos-integration lane runs once per packaged artifact and the phase gate reuses evidence bound to that exact applicationDigestSha256 plus the Swift probe source digests; missing, stale, partial or failing evidence is a loud failure, never a skip.
- [Phase 03]: Quick Entry returns focus by hiding Keepling itself (app.hide()), which macOS turns into activation of the prior application with its caret intact — no TCC Automation prompt and no native module, at the cost of also hiding Keepling's main window (O-23).
- [Phase 03]: A settle predicate must be strictly weaker than the assertion it precedes, and quiescence is not universally valid — a pending macOS dead key is stable indefinitely.
- [Phase 03]: Undo of a mutation the server never acknowledged is REFUSED at the point of action with authored copy, not deferred and not accepted locally — deferring would need a second durability mechanism and a decision on O-47
- [Phase 03]: undo_uncertain is never settled by the client, because the server itself does not know whether the compensation applied; it stays loud and O-47 stays open
- [Phase 03]: D-52 implemented in 03-24 with a three-state outbox (queued | in_flight | uncertain): a transport failure yields uncertain, never queued, because a failed fetch cannot say whether the bytes left.
- [Phase 03]: Measured (not assumed) that desktop packaging at HEAD is byte-reproducible across separate invocations; no non-determinism source needed removal, documented in package-desktop.mjs and permanently re-checked by the package-reproducible gate lane.
- [Phase 03]: 03-26: machine-state census + focus-theft detection + seeded shuffle closes VERIFICATION.md Gap 1's remaining half — A9 previously blamed A8; today's failure was A1 (first row, no predecessor), falsifying the per-row-pair hypothesis. A class-level machine-state barrier (real reads, refuse loudly, restore between rows) plus mid-sequence FOCUS_STOLEN detection replaced row-by-row diagnosis. A Rule 1 regression the barrier's own teardown cleanup introduced (deleting A3's shared profile early) was found and fixed during this plan's own verification.
- [Phase 03]: [Phase KPL-03]: 03-27 closed VERIFICATION.md Gap 2 by amending 03-UI-SPEC.md's evidence contract (per-dimension table naming a test title or macOS row id, or NOT BUILT with evidence) and building appearance-matrix.spec.ts for the one genuinely uncovered dimension (five window sizes, both themes); the erroneous visual-dimension sign-off is corrected in a dated record beside the original, never rewritten.
- [Phase 04]: iOS carries all 11 desktop STRICT tables (D-35's 'nine tables' enumerates categories, not a literal count); visible_projection.sync_status keeps the desktop's literal 'saved_on_this_mac' stored value.
- [Phase 04]: Nullable references in the OpenAPI contract use a dedicated Nullable<Base> schema (type: [X,'null']) instead of a oneOf/anyOf-null wrapper, because the wrapper form silently deletes the property from swift-openapi-generator output.
- [Phase 04]: SyncFeedEnvelope.payload's oneOf is left without a formal discriminator after two real attempts proved broken/corrupting against the pinned swift-openapi-generator; disambiguation relies on disjoint required-field sets instead.
- [Phase 04]: Fence checks moved to a pre-write dbPool.read check so a fenced write is observably zero commits AND zero rollbacks, not a rollback inside an opened transaction.
- [Phase 04]: mutation_dependencies now receives real (often empty) writes inside acceptMutation's transaction as structural provenance only; ordering enforcement stays resource-key-based per the Phase 03 decision.
- [Phase 04]: 04-03: No sync-state-machine vocabulary change needed -- background execution already maps to v1's relaunch action; expired authentication and account-switch fencing belong to the separate account-lifecycle state machine, not SyncReducer
- [Phase 04]: 04-03: VectorConformanceTests.swift drives SyncReducer (Task 2's pure reducer), not GRDBLocalStore -- GRDBLocalStore lacks dependencies-aware readyMutations/applyPull/fence-reading, and extending it was out of this plan's authorized scope
- [Phase 04]: Accessory absence IS achievable on iOS SDK 26.5 via a conditionally-applied tabViewBottomAccessory modifier, contrary to the RESEARCH.md-era DTS finding; measured, not assumed
- [Phase 04]: The real bindNamespace/setSyncFence D-03 account-fencing trigger closes the gap 04-02's __test_setFence comment deferred to this plan; a hand-restored store now fences itself on account mismatch instead of only being simulatable via a test-only seam.
- [Phase 04]: The acknowledgement validator stays strict at accepted/already_satisfied for a 200 answer; the conflict path enters settlement from the refusal classifier, not a widened success validator, so a 409 problem cannot be silently reclassified as success.
- [Phase 04]: DurableUnit treats the db/-wal/-shm store files as one value with all-or-none move/copy/delete, preventing a partial filesystem operation from handing a restored store a database file with no matching WAL.
- [Phase KPL-04]: iOS registers its own ASWebAuthenticationSession callback scheme (keeplingios://auth/callback), distinct from desktop's keepling:// scheme — A private-use scheme is first-come per-OS; sharing one across native client kinds has no benefit and complicates future clients
- [Phase KPL-04]: GRDBLocalStore.snapshot()/syncState() are fence-gated but readyMutations() deliberately is not — Preserves 04-06's already-verified BackupReplayTests proof that reads ready rows to demonstrate the write path refuses per mutation
- [Phase 04]: KeeplingSyncAdapter.push and GRDBLocalStore.acceptMutation generalized beyond capture_task-only, since the plan's own objective (every command travels, joins one transaction) was unsatisfiable against the pre-existing tracer-only code.
- [Phase KPL-04]: A list row is a plain view with .onTapGesture navigating via NavigationPath.append, never NavigationLink(value:) -- NavigationLink's automatic accessibility grouping collapses a row's child text into one opaque Button element, making the title's own accessibility identifier unreachable.
- [Phase KPL-04]: Completion and trashing both remove a row from Today/Inbox in this phase (no recently-completed or Trash-browsing surface yet); Reopen/Restore stay reachable only through the task detail view, which remains pushed across the transition.
- [Phase 04]: IOS-04: one authoritative SyncPresentation.derive projection drives the accessory, Sync & Recovery sheet, and inline exceptions; exception-first accessory priority, .fullScreenCover for genuine full-screen presentation.
- [Phase 04]: 04-11: undo is a single-level, globally-scoped compensating semantic action -- CompensatingCommands mints undo_task with the server-retained handle; the client never client-settles an undo_uncertain answer.
- [Phase 04]: hasFocus cannot observe @AccessibilityFocusState in this harness; FocusSafetyTests verifies a plain @State mirror of the app's own focus decision instead, deferring OS-level VoiceOver confirmation to Plan 04-16
- [Phase 04]: New Task toolbar button's 42.67x36pt footprint at the largest accessibility category is a measured, disclosed system nav-bar layout floor, not a loosened threshold
- [Phase 04]: Discard changes dialog excluded from DynamicTypeSnapshotTests' largest-accessibility-category full-inventory sweep, a measured single-screen single-extreme gap tied to cumulative Simulator load
- [Phase 04]: State-injection seam construction-sites all thirteen presentation states, including .opening/.preparing/.offline/.localAcceptance which previously had derived copy but no render site anywhere in the app (Phase-3 O-46/O-47 lesson closed).
- [Phase 04]: Every UI-test-only fixture hook in KeeplingApp.swift is enclosed in #if DEBUG, compiled out of Release entirely -- not merely gated by an environment-variable check.
- [Phase 04]: ConflictResolverSection's unbounded .fixedSize(vertical: true) title-diff Text (no lineLimit) was a real overflow bug surfaced by the held-out 512-scalar fixture, fixed with an explicit lineLimit(6).
- [Phase 04]: 04-15: DiagnosticEvent is closed to UUID/enum fields only (no String), so a bad-day sync log is reconstructable over USB with no task content, credential, cursor, or fingerprint ever representable. — D-23 diagnosability and privacy halves are both satisfied structurally by the type, not by convention.
- [Phase 04]: 04-15: Diagnostic instrumentation lives at the same KeeplingApplication.runSyncPass/GRDBLocalStore call sites that already decide a transition, reusing IntentPrivacyTests' real-value (never pattern) leak-scan discipline for the log, export bundle, Inspect presentation, and announcements. — Avoids a parallel notion of what is 'sensitive'; keeps the diagnostic vocabulary keyed by real production decisions.
- [Phase 04]: Device lane reports BLOCKED honestly rather than being special-cased out; the aggregate iOS gate currently exits non-zero on purpose because Plan 04-16's physical-device evidence was never produced.
- [Phase 04]: IOS-04 unchecked (not 'complete with disclosure') because its own text names a physical iPhone and zero device evidence exists at all; IOS-01..03 checked with disclosure since their claims are comprehensively proven on the Simulator.
- [Phase KPL-05]: 05-01: Task 1's three one-way authorization doors answered Option A (D-06 three scope strings, D-07 PKCE-only, extend device_grants) exactly as CONTEXT-locked.
- [Phase KPL-05]: 05-01: D-30 live-host protocol-revision re-check could not be performed -- no MCP host or model credential reachable in this execution sandbox; 2025-06-18 pin implemented but not empirically verified against a live client.
- [Phase KPL-05]: 05-02: Task 1's scoped-DCR checkpoint confirmed Option A exactly as CONTEXT.md's D-29 locked it; day-one dogfood hosts are Claude Code and Cowork.
- [Phase KPL-05]: 05-02: mcp_token_audience_rejected renamed to mcp_audience_rejected -- the literal substring "token" is forbidden in security_audit.ex by the pre-existing telemetry_redaction_test.exs privacy invariant.
- [Phase 06]: WINDOWS.md gained a trailing owner column (all rows) instead of repurposing the phase column, so historical phase-of-record and current accountable owner stay independently readable — Rows 43/63/69/78 needed an owner different from their originating phase (BACKLOG or Phase 6), which the existing phase column could not express without losing history.
- [Phase 06]: QUAL-02 unchecked rather than re-disclosed in place, because CI now runs and fails 17/17, which is strictly worse than the prior never-ran state — Leaving the box checked would misstate the direction of the change; the plan's own prohibition forbids softening a disclosure.
- [Phase 06]: 06-02: T-06-02-01 fixed via ditto archive transport (mode-aware) instead of loosening the applicationDigestSha256 binding; smoke-desktop-packaged.mjs and verify-macos-integration.mjs expand and re-verify the archive rather than trusting the raw directory transport.
- [Phase 06]: 06-02: server/sync-property/backup-restore Phase 2 lanes moved to a new ubuntu-24.04 job (apt/PGDG PostgreSQL) rather than a GitHub Actions services: container, because backup-restore drives pg_ctl/WAL/PITR directly and a service container does not expose that.
- [Phase 06]: 06-03: Task 1's checkpoint:decision auto-confirmed the pre-answered D-24 owner decision (Apache-2.0, uniform monorepo licence) rather than re-litigating it, since the plan text itself already records the owner's confirmed answer and full rationale.
- [Phase 06]: 06-03: LICENSE's appendix placeholder left unfilled (not substituted with project name) so plan 06-11's governance lane can hash-compare it against the canonical upstream Apache-2.0 text.
- [Phase KPL-06]: 06-04: Added export_performed to SecurityAudit's closed event vocabulary and its DB constraint, even though neither file was in Task 3's declared scope, since the plan's own acceptance criteria require exactly one security_audit event per export and no existing vocabulary member fits.
- [Phase KPL-06]: 06-04: The literal mix keepling.ops export CLI command is not yet wired (Release.invoke hardcodes OpsStore as the sole port for every operation, mirroring the same pre-existing gap for backup/restore/deploy/upgrade/replace-host) -- the export path is proven correct at the application layer via Ops.run + the real Postgres.Export port, disclosed as open for a future plan.
- [Phase 06]: 06-06: kept the pre-existing title-only conflicts table unchanged and added refusal_records as an additive, broader durable record for every refusal outcome, rather than replacing the narrower table's write.
- [Phase 06]: 06-06: migration named 0003 (not the plan-drafted 0004) since only two migrations exist on disk and the runner requires contiguous version numbers.
- [Phase 06]: 06-07: only a first-delivered mutation advances last_used_at; a null value means not-yet-measured, never proven-zero.
- [Phase 06]: 06-07: Commands.lookup_result/3's public return shape stays byte-for-byte unchanged; a narrow CommandStore.receipt_issuer/2 companion carries the issuing-grant identity instead, so the widening does not break exact-equality callers.
- [Phase KPL-06]: 06-05: SRV-02 closed -- all four cross-adapter legs (web, MCP, Electron, iPhone) now PASS identically; a real cross-client ConflictField.field OpenAPI enum gap (missing completed_at/trashed_at) was found and fixed en route, since no lane had ever driven a genuine lifecycle conflict through a real Swift decode path before.
- [Phase 06]: [Phase KPL-06]: 06-08: classification.json had drifted against 5 columns/tables already landed earlier in this phase (device_grants.last_used_at, task_activities.actor_principal/actor_label/recovery_state/undone_activity_id, schema_migrations); the new completeness test found this on first run and closed it.
- [Phase 06]: [Phase KPL-06]: 06-08: the independent export reader shells to the system unzip binary and hand-rolls a narrow JSON Schema validator rather than adding any npm dependency.
- [Phase 06]: [Phase KPL-06]: 06-08: the golden vector is generated via a direct Export.write_bundle/4 call with hand-fixed entities and manifest_extra (never a live DB read), removing restore_epoch/feed_high_water_sequence as sources of environmental variance.
- [Phase 06]: [Phase KPL-06]: 06-08: closed 06-04's disclosed CLI wiring gap for the export verb only (release.ex + ops_store.ex), since Task 2's own verify required a real mix keepling.ops export bundle; backup/restore/deploy/upgrade/replace-host remain unwired.
- [Phase 06]: [Phase KPL-06]: 06-08: registering export-elixir/export-reader in release-lanes.json correctly makes verify-release.mjs fail against the pre-existing candidate-0 manifest -- the intended proof the exact-set detection works, disclosed as open CI-wiring follow-up.
- [Phase 06]: D-013 (06-11): recorded, not implemented, an RFC 8707 audience check at :client_authenticated -- it would buy no reduction in actual authority given this repo's single origin/authorization-server/account, and would invert the deliberate D-09 byte-identity assertion.
- [Phase 06]: 06-11: SECURITY.md's supported-version table renders from apps/server/config/config.exs's live :compatibility map, not the compatibility_test.exs fixture named in the plan's read_first -- the live config is what actually matches D-29's pre-release honesty line.
- [Phase 06]: 06-12: the trust oracle's server-side entity digest is computed inside Postgres via sha256(), never letting plaintext task content leave the database for that source
- [Phase 06]: 06-12: the chaos corpus's ten operators are fully wired (list/seed/digest/dry-run) but real two-client harness composition is disclosed as open follow-on integration, mirroring the project's existing physical-device-lane precedent

### Retained Research

- Navigation index: `.planning/knowledge/INDEX.md`
- Normalized project research: `.planning/research/SUMMARY.md`
- Brand seed: `docs/brand/BRAND-SEED.md`
- Repository boundaries: `docs/architecture/REPOSITORY.md`

### Open Decisions for Phase Discussion

- Exact v1 temporal model and minimum Things-parity loop.
- Initial iOS version floor and local persistence adapter.
- Authentication and device/session fencing.
- Electron SQLite implementation and migration fixture strategy.
- License and contributor governance.
- Backup RPO/RTO and whether PITR is required before sustained dogfood.
- Canonical domain and namespace acquisition; formal Keepling clearance.

### Quick Tasks Completed

| # | Description | Date | Commit | Status | Directory |
|---|-------------|------|--------|--------|-----------|
| 260831-wfy | Resolve Phase 1 API coverage gate and shift all feasible human UAT into deterministic integration and end-to-end automation | 2026-08-31 | beeb6cb | Verified | [260831-wfy-resolve-phase-1-api-coverage-gate-and-sh](./quick/260831-wfy-resolve-phase-1-api-coverage-gate-and-sh/) |

## Next Action

Re-derive MAC-03 and MAC-04 against the 03-22 evidence (O-17, D-50), reading `.planning/phases/KPL-03-mac-daily-loop/03-22-SUMMARY.md` — specifically its "What the tests actually exercised — honestly" section, which states which outcomes and command types were observed and which were not, rather than this line. Then run `pnpm test:phase-1` and proceed to phase verification for KPL-03. The desktop phase gate is green at `lanes=10 failed=0` with every lane at a positive case count. Read `.planning/phases/KPL-03-mac-daily-loop/.continue-here.md` first, and treat `open_items` as untrusted until verified against source (O-22).

CLOSED by 03-22: O-38, O-41, O-42, and the (a) half of O-31. Still open and relevant: O-39 (stale Settings account state after sign-in), O-40 (the packaged application digest is not reproducible across invocations, which the macOS evidence binding depends on — do NOT fix by loosening that binding; it behaved exactly as recorded during 03-22 and cost one re-record), O-43 (a refused local change has no durable home — the next pull reverts it), O-44 (the desktop conflict chooser is title-only), O-45 (undo is the same defect class as O-41 and needs server-issued undo handles), O-46/O-47 (`preparing` and `uncertain` still have no production construction site — reported for a recorded decision, deliberately not wired speculatively), O-48 (the requirement re-derivation itself).

---
*State initialized: 2026-08-28*

## Session

**Last session:** 2026-09-11T21:57:05.772Z
**Stopped at:** Completed 06-12-PLAN.md
**Previous session:** 2026-09-04T03:10:00.000Z — Completed 03-21-PLAN.md (O-36 closed with both halves; O-37 filed, decided as D-49 and closed; O-34 closed — the packaged app exchanged real bytes with real Phoenix on real PostgreSQL, settled=2, exact-bytes retry proven against what the server received, server-derived origin http://localhost:4102 differing from the client-configured 127.0.0.1:4103; three real client/server disagreements found and fixed; O-39 and O-40 newly filed; desktop phase gate lanes=10 failed=0)
**Resume file:** None

## Performance Metrics

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase KPL-03 P21 | ~3h | 3 tasks | 19 files |
| Phase KPL-03 P22 | ~4h | 4 tasks | 26 files |
| Phase KPL-01 P01 | 16min | 2 tasks | 3 files |
| Phase KPL-01 P02 | 8min | 2 tasks | 13 files |
| Phase KPL-01 P04 | 10min | 2 tasks | 13 files |
| Phase KPL-01 P03 | 8min | 2 tasks | 15 files |
| Phase KPL-01 P05 | 26min | 2 tasks | 20 files |
| Phase KPL-01 P06 | 17min | 2 tasks | 16 files |
| Phase KPL-01 P07 | 31min | 2 tasks | 15 files |
| Phase KPL-01 P08 | 20min | 2 tasks | 13 files |
| Phase KPL-01 P09 | 16min | 2 tasks | 15 files |
| Phase KPL-01 P10 | 23min | 2 tasks | 14 files |
| Phase KPL-01 P11 | 21min | 2 tasks | 13 files |
| Phase KPL-01 P12 | 22min | 2 tasks | 15 files |
| Phase KPL-01 P13 | 24min | 2 tasks | 18 files |
| Phase KPL-01 P14 | 18min | 2 tasks | 14 files |
| Phase KPL-01 P15 | 18min | 2 tasks | 15 files |
| Phase KPL-01 P16 | 37min | 2 tasks | 15 files |
| Phase KPL-01 P17 | 42min | 2 tasks | 10 files |
| Phase KPL-01 P18 | 63min | 2 tasks | 14 files |
| Phase KPL-01 P19 | 31min | 3 tasks | 13 files |
| Phase KPL-01 P20 | 30min | 3 tasks | 12 files |
| Phase KPL-01 P21 | 5min | 2 tasks | 3 files |
| Phase KPL-01 P22 | 5min | 2 tasks | 3 files |
| Phase KPL-01 P23 | 8min | 2 tasks | 5 files |
| Phase KPL-01 P24 | 20min | 3 tasks | 12 files |
| Phase KPL-01 P25 | 29min | 3 tasks | 14 files |
| Phase KPL-01-one-trustworthy-task P26 | 17min | 3 tasks | 14 files |
| Phase KPL-01 P27 | 16min | 3 tasks | 19 files |
| Phase KPL-02 P01 | 17min | 3 tasks | 8 files |
| Phase KPL-02 P03 | 12min | 2 tasks | 7 files |
| Phase KPL-02 P02 | 16min | 3 tasks | 9 files |
| Phase KPL-02 P11 | 10min | 2 tasks | 8 files |
| Phase KPL-02 P04 | 15min | 3 tasks | 13 files |
| Phase KPL-02 P05 | 13min | 2 tasks | 12 files |
| Phase KPL-02 P06 | 17min | 3 tasks | 12 files |
| Phase KPL-02 P07 | 37min | 3 tasks | 8 files |
| Phase KPL-02 P08 | 9min | 3 tasks | 8 files |
| Phase KPL-02 P10 | 18min | 2 tasks | 6 files |
| Phase KPL-03 P07 | 4min | 2 tasks | 9 files |
| Phase KPL-03 P12 | 7min | 2 tasks | 5 files |
| Phase KPL-03 P01 | 12h 11m | 3 tasks | 16 files |
| Phase KPL-03 P02 | 26min | 3 tasks | 18 files |
| Phase KPL-03 P09 | 62min | 2 tasks | 14 files |
| Phase KPL-03 P03 | ~100min | 2 tasks | 24 files |
| Phase KPL-03 P04 | 130 min | 2 tasks | 30 files |
| Phase KPL-03 P10 | 45min | 2 tasks | 5 files |
| Phase KPL-03 P11 | 150min | 2 tasks | 7 files |
| Phase KPL-03 P05 | 35min | 2 tasks | 6 files |
| Phase KPL-03 P08 | 105min | 2 tasks | 6 files |
| Phase KPL-03 P13 | 95min | 4 tasks | 13 files |
| Phase KPL-03 P14 | 46 min | 4 tasks | 16 files |
| Phase KPL-03 P15 | 2h 35m | 4 tasks | 11 files |
| Phase KPL-03 P16 | 75min | 2 tasks | 7 files |
| Phase KPL-03 P18 | 60min | 3 tasks | 3 files |
| Phase KPL-03 P20 | 75min | 3 tasks | 2 files |
| Phase KPL-03 P23 | ~2h | 3 tasks | 18 files |
| Phase KPL-03 P24 | 1h05m | 3 tasks | 22 files |
| Phase KPL-03 P25 | 45min | 3 tasks | 4 files |
| Phase KPL-03 P26 | 2h 30min | 3 tasks | 1 files |
| Phase KPL-03 P27 | 70min | 3 tasks | 2 files |
| Phase 04 P01 | 300min | 3 tasks | 36 files |
| Phase KPL-04 P02 | ~2h | 3 tasks | 15 files |
| Phase KPL-04 P03 | ~90 min | 3 tasks | 11 files |
| Phase KPL-04 P04 | ~2h | 2 tasks | 11 files |
| Phase KPL-04 P05 | ~3h | 3 tasks | 12 files |
| Phase KPL-04 P06 | ~2h | 2 tasks | 9 files |
| Phase KPL-04 P07 | 2h | 3 tasks | 14 files |
| Phase KPL-04 P08 | ~3h | 3 tasks | 18 files |
| Phase KPL-04 P09 | ~5h | 3 tasks | 22 files |
| Phase KPL-04 P10 | 2h30m | 3 tasks | 17 files |
| Phase KPL-04 P11 | 46min | 2 tasks | 17 files |
| Phase KPL-04-native-iphone-daily-loop P12 | 55min | 2 tasks | 10 files |
| Phase KPL-04 P13 | 195min | 3 tasks | 15 files |
| Phase KPL-04 P14 | 5h40m | 2 tasks | 12 files |
| Phase KPL-04 P15 | 65min | 2 tasks | 9 files |
| Phase KPL-04 P17 | ~3h10m | 2 tasks | 7 files |
| Phase 04 P16 | 165 | 3 tasks | 13 files |
| Phase KPL-05 P01 | ~80min | 3 tasks | 15 files |
| Phase KPL-05 P02 | 40min | 3 tasks | 13 files |
| Phase 06 P01 | 24min | 3 tasks | 5 files |
| Phase KPL-06 P02 | unknown | 3 tasks | 13 files |
| Phase KPL-06 P03 | 6min | 3 tasks | 8 files |
| Phase KPL-06 P04 | ~90min | 3 tasks | 19 files |
| Phase KPL-06 P06 | 70min | 2 tasks | 7 files |
| Phase KPL-06 P07 | ~70min | 4 tasks | 16 files |
| Phase KPL-06 P05 | 65min | 3 tasks | 13 files |
| Phase KPL-06 P08 | ~110min | 3 tasks | 10 files |
| Phase KPL-06 P09 | ~95min | 3 tasks | 16 files |
| Phase KPL-06 P11 | 50min | 4 tasks | 13 files |
| Phase KPL-06 P12 | ~140min | 3 tasks | 19 files |

### Blockers

- O-21: VERIFIED CLOSED 2026-09-11 (06-01) against source — `apps/desktop/main/index.ts:911-918` now constructs a real `ElectronForegroundApp` and wires it into `QuickEntryWindowController`, closing the prior-application focus-return gap.
- O-22: Cmd-1/Cmd-2 route through facade.setRoute in DesktopShell.tsx and bypass the unsaved-changes guard that mouse navigation goes through. Tracked as WINDOWS.md #78, owner Phase 6.
- O-51: VERIFIED CLOSED 2026-09-11 (06-01) against source — `DesktopApplication.ts` lines 465-511's own comment documents the decision made together with O-43: an undo with no server-issued handle is REFUSED loudly at the point of action rather than silently accepted or deferred; the disclosed cost (undo unavailable until the underlying change has synced) is the recorded decision, not an open blocker.
- 04-16: physical-device UI suites BLOCKED -- the iPhone is locked and iOS refuses to launch any app on a locked device. Unlock the phone and re-run 'node tooling/verify-ios-phase.mjs --lane device'.
- 04-16: the server-driven half of D-22 Criterion 2 is BLOCKED -- KeeplingSyncAdapter refuses non-HTTPS non-loopback base URLs and URLSession rejects the lane's self-signed cert, so the phone cannot reach a Mac-hosted recording proxy. Needs a decision: DEBUG-only lane CA via injected ClientTransport, vs widening the transport guard (refused), vs deferring.
- 05-01: No MCP host or model credential reachable in this environment -- blocks the phase's representative-model and adversarial evidence lanes (D-26) and the D-30 live-host protocol re-check.
