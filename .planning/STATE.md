---
gsd_state_version: 1.0
milestone: v1.0
current_phase: 02
current_phase_name: Synchronization and Replaceable Server
status: executing
stopped_at: Completed 02-04-PLAN.md
last_updated: "2026-09-01T07:14:04.064Z"
last_activity: 2026-09-01
last_activity_desc: Phase KPL-02 execution started
state_head: cbc3c56234bbb3af65515a1f5bd6fdbf2b12fa59
progress:
  total_phases: 6
  completed_phases: 1
  total_plans: 38
  completed_plans: 32
milestone_name: milestone
---

# Project State

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-08-31)

**Core value:** Jon can trust Keepling as his daily task system on Mac and iPhone: capture is immediate, accepted changes are never silently lost or overwritten, and both human and agent actions remain inspectable and recoverable.  
**Current focus:** Phase KPL-02 — Synchronization and Replaceable Server

## Current Position

Phase: KPL-02 (Synchronization and Replaceable Server) — EXECUTING
Plan: 6 of 11
Total Plans in Phase: 11
Status: Executing Phase KPL-02
Last activity: 2026-09-01 — Phase KPL-02 execution started
Last Activity Description: Phase KPL-02 execution started
Progress: [██████████] 100%

## Accumulated Context

### Decisions

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

Run `$gsd-discuss-phase 2` from the repository root.

---
*State initialized: 2026-08-28*

## Session

**Last session:** 2026-09-01T07:14:03.972Z
**Stopped at:** Completed 02-04-PLAN.md
**Resume file:** None

## Performance Metrics

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
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
