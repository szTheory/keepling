---
gsd_state_version: 1.0
milestone: v1.0
current_phase: 03
current_phase_name: Mac Daily Loop
status: executing
stopped_at: Completed KPL-03-27-PLAN.md -- VERIFICATION.md Gap 2 closed, all 27 KPL-03 plans now have summaries
last_updated: "2026-09-04T19:22:59.190Z"
last_activity: 2026-09-04
last_activity_desc: Completed 03-27-PLAN.md -- closed VERIFICATION.md Gap 2 (desktop visual-snapshot evidence)
state_head: fddc8e390d3adb3eba86765b33874be927a87242
progress:
  total_phases: 6
  completed_phases: 1
  total_plans: 65
  completed_plans: 65
milestone_name: milestone
---

# Project State

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-08-31)

**Core value:** Jon can trust Keepling as his daily task system on Mac and iPhone: capture is immediate, accepted changes are never silently lost or overwritten, and both human and agent actions remain inspectable and recoverable.  
**Current focus:** Phase KPL-03 — Mac Daily Loop

## Current Position

Phase: KPL-03 (Mac Daily Loop) — ALL 27 PLANS COMPLETE (VERIFICATION.md gaps closed by 03-25/03-26/03-27)
Plan: 27 of 27
Total Plans in Phase: 27
Status: Executing Phase KPL-03
Last activity: 2026-09-04 — Completed 03-27-PLAN.md (VERIFICATION.md Gap 2 closed)
Last Activity Description: 03-27 built appearance-matrix.spec.ts (5 sizes x 2 themes) and amended 03-UI-SPEC.md's evidence contract, correcting the erroneous visual-dimension sign-off
Progress: [██████████] 100%

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

**Last session:** 2026-09-04T19:22:59.102Z
**Stopped at:** Completed KPL-03-27-PLAN.md -- VERIFICATION.md Gap 2 closed, all 27 KPL-03 plans now have summaries
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

### Blockers

- O-21: prior-application focus return after Quick Entry is unimplemented in the shipped app -- QuickEntryWindowController calls an optional foregroundApp port that has no implementation and is never passed in main/index.ts#bootstrap(). Found by row A9; a fifth GAP-1 instance. Blocks the macos-integration lane going green.
- O-22: Cmd-1/Cmd-2 route through facade.setRoute in DesktopShell.tsx and bypass the unsaved-changes guard that mouse navigation goes through.
- O-51: undo is now unavailable on a Mac with no server configured — a disclosed cost of closing O-45; decide it together with O-43, not separately
