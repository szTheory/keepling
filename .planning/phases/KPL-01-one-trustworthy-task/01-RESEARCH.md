# Phase 1: One Trustworthy Task - Research

**Researched:** 2026-08-30
**Domain:** Trustworthy semantic task commands across React, Phoenix, Ecto, and PostgreSQL
**Confidence:** HIGH for project constraints and core transactional architecture; MEDIUM for current external-library guidance

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

### Repository and boundaries

- **D-01:** Keepling remains one coordinating monorepo. Phase 1 creates `apps/server`, `apps/web`, and only the initial shared contracts, tokens, and test tooling justified by the vertical slice. No nested Git repositories or submodules. The interrupted checkpoint's child-repository direction is superseded.
- **D-02:** The Phoenix server is a modular monolith. Domain and application modules do not depend on Phoenix transport, Ecto schemas, React, generated DTOs, MCP, or client persistence.
- **D-03:** React is the online-first browser surface. Presentation may be extracted into `packages/web-ui` only after browser and Electron prove a reusable seam.

### Temporal model

- **D-04:** Store nullable `planned_on` and `deadline_on` civil dates. Use UTC instants only for lifecycle, acceptance, and audit times. Do not persist `is_today`.
- **D-05:** One deliberately configured account IANA timezone defines the canonical account day. A plan-for-today command resolves to a concrete civil date when accepted. Device timezone never silently changes task membership, and changing account timezone never rewrites stored task dates.
- **D-06:** Active unfinished tasks appear in Today when `planned_on` or `deadline_on` is on or before the account day. Preserve both dates and expose planned, deadline, overdue, or combined membership reasons through text and semantics, not color alone.
- **D-07:** Allow `planned_on` later than `deadline_on`, preserve both values, and return a non-blocking `planned_after_deadline` warning.
- **D-08:** Defer availability/start dates, exact task times, reminders, recurrence, Someday, and This Evening.

### Capture and editing

- **D-09:** Use a Things-like list-and-detail workspace on wide screens and the same canonical routed task editor as a full page on narrow screens. Quick capture is separate from the full editor.
- **D-10:** Global quick capture visibly defaults to Inbox and offers an explicit optional Today control. Navigation context never silently changes capture destination.
- **D-11:** Preserve entered text through validation, authentication expiry, and uncertain network outcomes. Clear a draft only after exact acknowledgement of its mutation identity.
- **D-12:** Multi-field editing uses explicit Save and Cancel. Dirty navigation offers Save, Discard, or Stay. Never save on blur. Phase 1 does not claim durable recovery of an unsubmitted browser draft after process loss.
- **D-13:** Use native semantic keyboard behavior, logical Tab order, visible focus, focus restoration, Enter activation, Escape cancel/close, and Cmd/Ctrl-Enter submission. Defer global character shortcuts, J/K navigation, custom ARIA grids, and the full Things-like desktop shortcut layer to Electron.

### Inbox, projects, and tags

- **D-14:** Inbox membership is explicit canonical task state initialized by capture. Only `clarify_task` clears it and only `return_to_inbox` restores it. Ordinary edits, dates, project/tag assignment, and Today placement never change Inbox membership as a side effect. — **Reversibility:** costly — replacing explicit processing state with a derived cleanup rule would migrate stored tasks and change every command, client, and MCP contract.
- **D-15:** Completion and Trash exclude a task from the active Inbox query without erasing its Inbox state. Reopen and restore recompute visibility from preserved state.
- **D-16:** The Inbox editor offers distinct Save and atomic “Save & move out of Inbox” actions. Do not remove the row before exact server acknowledgement.
- **D-17:** A task has zero or one project and zero or many flat tags. A project is a named multi-action outcome/container; a tag is cross-cutting context.
- **D-18:** Phase 1 supports idempotent create, rename, archive, and unarchive commands for projects and tags. References use stable opaque IDs rather than mutable names. Renaming an organization object does not rewrite or revision-bump assigned tasks.
- **D-19:** Archived projects/tags disappear from new-assignment pickers but remain visibly named on existing and historical tasks. Reject project archive while it contains active unfinished tasks; tag archive preserves existing assignments. Unarchive fails explicitly on active-name collision.
- **D-20:** Defer areas, headings, checklists, nested projects/tags, project completion, organization hard deletion, tag inheritance, and name-addressed writes.

### List ordering and lifecycle visibility

- **D-21:** Inbox is a flat active queue ordered newest capture first with stable task identity as the final tie-breaker. It has no manual reorder.
- **D-22:** Today has fixed Overdue and Today sections. Users may manually order tasks within a section. New eligibility has a deterministic fallback position. Reordering uses semantic move-before/move-after commands with an expected scoped order revision; clients never write raw rank values or silently win reorder conflicts. — **Reversibility:** costly — the order contract must converge across later offline clients and becomes part of stored synchronization behavior.
- **D-23:** Upcoming is read-only, grouped by the next future relevant account-timezone civil date: future `planned_on` first, otherwise future `deadline_on`. A task may appear in Today for one reason and Upcoming for a later deadline, with both reasons explicit.
- **D-24:** On completion, move the task into an expanded Completed today section at the bottom of the current list, newest first. Older work lives in a dedicated Completed view grouped by completion date. Reopen preserves identity and fields and recomputes current derived membership.
- **D-25:** Trash is a dedicated secondary-navigation view ordered newest trashed first. Restore preserves fields, project/tags, dates, prior completion state, and usable ordering information; remain in Trash, remove the restored row, and announce its actual destinations.
- **D-26:** Use opaque account-bound keyset cursors over complete unique sort tuples plus relevant view/order revision. Use explicit Load more, not infinite scroll or offset pagination. Stale cursors fail explicitly and refresh.
- **D-27:** Initial loading cannot show Empty before an authoritative zero result. Background refresh keeps the last good rows visible with Updating, stale, failure, and Retry states. Initial, authentication, validation, conflict, and retry states remain distinct.
- **D-28:** Preserve focus by stable task identity. When an action removes the focused row, focus the next row, then previous row, then list heading. Loading more focuses the first appended row. Announce concise outcomes without stealing focus.
- **D-29:** Motion communicates state but never correctness. Honor Reduce Motion with an immediate update or restrained opacity change.
- **D-30:** Defer configurable sorts/grouping, manual order outside Today, dashboard/calendar views, search-driven history, and CRDT-like list ordering.

### Mutation identity, concurrency, and conflicts

- **D-31:** Every command carries a distinct client-generated mutation identity; target identity; closed versioned command arguments; and, except create, an expected aggregate revision. Scope the durable mutation key by account and fingerprint the semantic request.
- **D-32:** The same mutation identity and semantics always return the original stored result. Reuse with different semantics returns a stable `mutation_identity_reused` error. Persist the terminal semantic result atomically with the accepted effect or rejection.
- **D-33:** Use a narrow semantic three-way merge. Updates send only touched fields plus their base values. Rebase only when each touched current value equals its submitted base or requested value, then rerun all aggregate invariants. Non-overlapping changes may merge; overlapping or lifecycle-incompatible changes return a structured persisted conflict. — **Reversibility:** costly — these rules define compatibility vectors and the later offline/MCP mutation contract.
- **D-34:** Complete/reopen may rebase across unrelated edits and may return `already_satisfied`; complete versus reopen conflicts. Trash, restore, and undo require exact current revision. Edit/complete versus Trash conflicts rather than inferring intent.
- **D-35:** Conflict resolution creates a new mutation identity against the latest revision. Replaying the original mutation continues returning its original conflict.
- **D-36:** Conflict UI compares only affected fields, preserves nonconflicting edits, and offers Use mine, Use current, or continued editing as appropriate. It is persistent, keyboard-operable, non-color-dependent, and restores focus predictably.
- **D-37:** On timeout, connection loss, or authentication expiry, preserve the draft and original submitted mutation identity, distinguish unknown result from failure, and query or retry only with that identity. Never mint a replacement identity or infer failure from a missing response.
- **D-38:** Return exact acknowledgements with mutation identity, task identity, resulting revision/snapshot, warnings, and optional bounded undo handle. Use stable application error codes with retryability and recovery action, mapped through a versioned Problem Details envelope.
- **D-39:** Reject last-write-wins, timestamp concurrency tokens, generic JSON Patch, client-authored merge rules, editor leases, CRDTs, full event sourcing, and per-field revisions until measured need proves otherwise.

### Undo, Trash, and recovery

- **D-40:** Each supported consequential command may return an opaque, high-entropy, account-bound, one-shot semantic compensation handle valid for 24 hours. Surface the latest eligible browser action persistently with a precise label; a transient toast is never the only recovery path.
- **D-41:** Undo is a fresh idempotent semantic command. Validate current authentication, ownership, authorization, handle expiry/consumption, and exact equality with the revision produced by the original action. Apply the typed inverse, increment revision, append activity, consume the handle, and store its result atomically.
- **D-42:** Return explicit no-change outcomes for expired, stale, already-applied, authentication-required, and uncertain undo states. Handle possession is never authorization.
- **D-43:** Trash is durable canonical task state preserving stable identity and all task fields/history. Phase 1 has no hard-delete/purge UI or automatic retention timer.
- **D-44:** Keep native browser text-editing undo behavior; do not commandeer Cmd/Ctrl-Z for domain undo. Defer multi-level cross-device undo/redo and event-sourced time travel.

### Authentication and sessions

- **D-45:** Keepling has one personal account and closed registration. An operator command issues a short-lived, single-use, hashed setup token; one transaction creates the sole account and permanently consumes setup capability. Reject public registration and first-request ownership.
- **D-46:** Phase 1 uses password-manager-friendly password authentication with Argon2id and a measured work factor. Permit long values, paste, AutoFill, and reveal; do not impose composition rules, security questions, periodic forced rotation, CAPTCHA-first defenses, or attacker-triggerable permanent lockout.
- **D-47:** Operator recovery issues a short-lived, one-use link without accepting passwords through command arguments, environment variables, or logs. Passkeys are an additive later authenticator, not a Phase 1 prerequisite.
- **D-48:** Browser authentication uses an opaque random credential in a Secure, HttpOnly, host-only, SameSite=Lax cookie. Store only its hash and lifecycle metadata in PostgreSQL. Protect every cookie-authenticated mutation with CSRF and origin/host validation; rotate session and CSRF state after authentication.
- **D-49:** Initial dogfood defaults are configurable 30-day idle expiry, 180-day absolute expiry, and a 15-minute recent-auth window for credential, recovery, authenticator, and session-revocation changes only. Ordinary task editing never requires recent-auth elevation.
- **D-50:** Sessions are individually visible and revocable. Show current status, user-editable label, client kind, creation time, and coarsened recent activity. Do not treat fingerprints as trusted devices or retain raw IP/fingerprint data by default.
- **D-51:** Reauthentication preserves dirty drafts and the original mutation identity, distinguishes not-submitted from submitted-but-unknown, and then queries or retries with that identity. Never hard-redirect and discard text.
- **D-52:** Logout warns about dirty work, revokes server-side, fences in-flight work, clears account-scoped memory/cache and CSRF state, then reloads.
- **D-53:** Rate-limit setup, login, and recovery with independent account and source buckets, bounded backoff, generic responses, and privacy-safe security audit records.
- **D-54:** Preserve a future grant seam: Electron and iPhone will use an external user agent with authorization code plus PKCE and separately revocable device credentials; MCP receives distinct scoped grants. Native clients never copy browser cookies, passwords, deployment secrets, or shared permanent tokens.
- **D-55:** Reject mandatory email/magic-link infrastructure, passkey-only bootstrap, JWT/bearer credentials in browser storage, shared forever-tokens, and auth transitions that discard or ambiguously replay intent.

### User-visible activity and trust evidence

- **D-56:** Commit one append-only, versioned `task_activity` fact for every accepted semantic command atomically with the task snapshot, revision, mutation result, and undo metadata. This is canonical user data, not diagnostic telemetry. — **Reversibility:** costly — activity types and field-delta contracts become durable user history and later export/MCP compatibility inputs.
- **D-57:** Initial types include captured, details updated, planned/unplanned, clarified/returned to Inbox, completed/reopened, trashed/restored, and undo applied. Store server acceptance time, from/to revisions, mutation linkage, optional undone-activity linkage, server-derived actor/principal and client kind, and closed typed changed-field data.
- **D-58:** Store exact old/new canonical values only for changed fields. Never store HTML, prompts, model explanations, or chain of thought. Render all values as untrusted text.
- **D-59:** Show a compact newest-first per-task activity list with actor, semantic action, exact outcome, accepted time, and recovery state. Long title/note changes are collapsed. Revision and mutation identifiers appear only in copyable technical details or conflict/support views; never expose opaque undo handles.
- **D-60:** Display acceptance time in the account timezone with an exact machine-readable timestamp; relative language may supplement but never replace it. Paginate with an opaque keyset cursor and explicit Load earlier activity.
- **D-61:** Keep accepted task activity separate from idempotency receipts, sync feed, persisted conflicts, security audit, and diagnostic telemetry. Authentication failures do not enter task history. Telemetry contains no task content or task/activity/mutation identifiers.
- **D-62:** Later MCP actions reuse the activity envelope with server-derived agent/grant/client labels and structured outcomes, never client assertions or hidden reasoning. Defer a global Recent Changes UI, compliance reporting, failed-agent-attempt review, and cryptographic/WORM claims.
- **D-63:** Retain activity with the task through completion and Trash for the account lifetime in Phase 1. Any later permanent-purge policy must also remove content-bearing history, undo payloads, and stored response bodies with honest backup-expiry behavior.

### the agent's Discretion

- Exact current stable Elixir/OTP/Phoenix/Ecto/PostgreSQL/React/TypeScript versions after official-documentation verification.
- Exact stable opaque identifier encoding, provided clients can generate task and mutation identities before network delivery and identifiers are never treated as authorization.
- Internal schema/table names, index shapes, rank representation, cursor encoding, and Ecto adapter structure consistent with the locked semantics.
- Exact bounded password length limits and calibrated Argon2id/rate-limit parameters after deployment-hardware measurement and abuse tests.
- Exact compact activity copy, iconography, spacing, and motion values within the brand, accessibility, and trust rules.
- Whether the rare conflict resolver is inline, a dedicated routed panel, or a dialog, provided drafts, focus, and explicit choices are preserved.

### Deferred Ideas (OUT OF SCOPE)

- Durable browser-offline mutation/outbox behavior; owned by Electron/iPhone and the synchronization phase unless later browser dogfooding proves a need.
- Multi-level undo/redo, hard-delete retention, configurable list policies, manual ordering outside Today, areas, headings, checklists, nested organization, reminders, recurrence, Someday, and This Evening.
- Passkeys, native authorization-code/PKCE grant implementation, and platform credential storage; retain only the compatible seam in Phase 1.
- Global Recent Changes, MCP-specific history presentation, failed-agent-attempt review, bulk previews, and cryptographic audit guarantees; later phases own these capabilities.
- Calendar/dashboard views, full manual spatial ordering, and CRDT/per-field revision machinery pending measured dogfood need.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|---|---|---|
| GTD-01 | User can capture a task with a title into Inbox and immediately receive a stable task identity. | Client-generated UUIDv4 task/mutation identities, explicit Inbox state, transactional command receipt, and exact acknowledgement. |
| GTD-02 | User can clarify a task by editing its title, notes, project membership, tags, and temporal fields supported by v1. | Pure aggregate command rules, touched-field/base-value merge, atomic organization references, and civil-date storage. |
| GTD-03 | User can deliberately place or remove a task in Today without conflating that choice with its deadline. | Separate `planned_on` and `deadline_on`, account-day projection, semantic plan/unplan commands, and membership-reason DTOs. |
| GTD-04 | User can inspect upcoming scheduled tasks and deadlines using explicit timezone-aware semantics. | Configured IANA timezone database, civil-date queries, deterministic grouping, and storage-neutral golden vectors. |
| GTD-05 | User can complete and reopen a task as idempotent domain transitions. | Revision-aware command outcomes, `already_satisfied`, receipt replay, and lifecycle conflict vectors. |
| GTD-06 | User can trash and restore a task without immediate hard deletion. | Canonical Trash state, exact-revision transitions, retained task/activity data, and restoration destination projection. |
| GTD-07 | User can undo supported consequential mutations using a bounded, revision-aware handle. | Hashed one-shot compensation handle, exact produced-revision check, typed inverse, and atomic consumption/activity/result. |
| SRV-01 | User can authenticate a personal account and authorize multiple owned devices without exposing server credentials to clients or agents. | Closed setup/recovery, Argon2id password auth, hashed database sessions, revocation, CSRF/origin enforcement, and future grant seam. |
| SRV-02 | User receives the same domain invariants through web, desktop, iPhone, API, and MCP entry points. | Inward dependencies and one semantic application-command boundary shared by all adapters. |
| SRV-03 | User-visible mutations are idempotent by mutation identity and return stable result or error contracts. | Account-scoped unique receipts, semantic fingerprinting, persisted accepted/rejected outcomes, and OpenAPI/golden vectors. |
| WEB-01 | User can use an online browser interface to capture, view Inbox and Today, edit, complete, and reopen tasks against the real Phoenix/PostgreSQL system. | Same-origin React/Phoenix integration, routed workspace, query cache for reads, command adapter for writes, and real-stack E2E. |
| WEB-02 | User sees clear empty, loading, validation, authentication-expired, stale, conflict, and retry states wherever those states apply. | Explicit client state machine, retained last-good data, persisted conflict rendering, and UI contract tests. |
| QUAL-01 | Contributor receives deterministic tests for domain rules, long mutation sequences, persistence/migrations, API/contracts, adapters, browser behavior, Electron boundaries, native orchestration, and deployment recovery at the layer best able to catch each failure. | Layered ExUnit/StreamData/Sandbox/contract/Vitest/Playwright suite and deterministic response-loss/concurrency harness. |
</phase_requirements>

## Project Constraints (from AGENTS.md)

- Run Git and GSD commands from the repository root; research/planning must read PROJECT, STATE, REQUIREMENTS, ROADMAP, active context, retained knowledge routing, repository architecture, and brand seed before substantial work. [VERIFIED: AGENTS.md:104-107]
- Keep one coordinating monorepo; never create nested `.git`, submodules, or an application-level `.planning/`. [VERIFIED: AGENTS.md:104-105]
- Keep server business rules independent of Phoenix, MCP, generated clients, UI, Ecto schemas, and client persistence; every adapter invokes the same semantic application commands. [VERIFIED: AGENTS.md:107-109]
- Keep domain, Ecto, generated wire, desktop SQLite, and Swift persistence representations distinct. [VERIFIED: AGENTS.md:109-109]
- PostgreSQL remains the only canonical store; never expose it publicly or put irreplaceable state in containers/build directories. [VERIFIED: AGENTS.md:15-19,111-111]
- Offline clients may report mutation success only after an atomic local projection/outbox commit, but durable browser offline behavior is deferred from this phase. [VERIFIED: AGENTS.md:16-16; 01-CONTEXT.md D-11,D-37 and Deferred Ideas]
- Do not log task titles, notes, prompts, credentials, raw tokens, or arbitrary identifiers. [VERIFIED: AGENTS.md:20-20,112-112]
- Do not claim correctness, compatibility, data safety, restore health, or release readiness without fresh executable evidence at the relevant boundary. [VERIFIED: AGENTS.md:21-21,113-113]
- Prefer BEAM/OTP, Phoenix, Ecto, PostgreSQL, browser/OS facilities, local code, and shallow dependency trees; existing szTheory libraries require a concrete requirement. [VERIFIED: AGENTS.md:22-22,115-117]
- Prefer deliberate cross-platform duplication over a dependency/abstraction that couples platforms without proven leverage. [VERIFIED: AGENTS.md:114-114]
- Native conventions, accessibility, and Reduced Motion outrank pixel identity. [VERIFIED: AGENTS.md:23-23]
- Keep the product focused on personal GTD; macOS Electron and native iPhone remain required later platforms, while the Phase 1 web client is online-first. [VERIFIED: AGENTS.md:17-17,24-24]
- Stay within the one replaceable Hetzner VM, application + PostgreSQL operational ceiling; recovery/backup health requires a disposable restore and no irreplaceable container/build state. [VERIFIED: AGENTS.md:18-19]
- Phase 1 owns `apps/server`, `apps/web`, initial contracts, tokens, and test tooling; use Mix and pnpm workspaces without Nx/Turborepo. [VERIFIED: docs/architecture/REPOSITORY.md:29-35,70-72]
- The approved `01-UI-SPEC.md` is an implementation contract: preserve its responsive routes, registered primitives/states, exact trust-state copy, accessibility, theme, and evidence requirements. [VERIFIED: .planning/phases/KPL-01-one-trustworthy-task/01-UI-SPEC.md:97-320]

## Summary

Phase 1 should be planned as a vertical command/result system, not as CRUD screens followed by reliability work. A browser command enters through a Phoenix adapter, is authenticated and normalized, then reaches one application-command boundary. The PostgreSQL transaction must arbitrate mutation identity, lock the relevant task or Today-order scope, apply domain invariants, persist the snapshot and revision, append user-visible activity, create any undo metadata, and store the terminal response. Only after commit does the adapter return the exact acknowledgement. This shape directly realizes D-31 through D-38 and D-56 through D-61. [VERIFIED: 01-CONTEXT.md D-31..D-38,D-56..D-61] Ecto.Multi and `Repo.transact/2` are the standard mechanism for grouping repository operations atomically, but transaction construction must remain in the persistence/application edge rather than making the pure domain depend on Ecto. [CITED: https://hexdocs.pm/ecto/Ecto.Multi.html]

The highest-risk subtlety is persisted rejection. Once an authenticated, structurally valid command is bound to `(account_id, mutation_id)`, a semantic conflict or invariant rejection must be stored as a successful transaction value alongside its fingerprint; rolling the transaction back would delete the receipt and make replay unstable. [VERIFIED: 01-CONTEXT.md D-32,D-35] Structural decoding failures and unauthenticated requests can fail before receipt ownership is established. Concurrent first delivery must be decided by a unique database constraint, never by a read-before-insert check. PostgreSQL unique constraints arbitrate concurrent inserts; Read Committed is the default isolation level, so multi-row invariants also need explicit row locks or a serializable transaction with retry. [CITED: https://www.postgresql.org/docs/current/transaction-iso.html]

On the browser side, TanStack Query should own server reads and last-good query state, while a small Keepling command adapter owns writes, fixed mutation identity, dirty-draft preservation, acknowledgement lookup, and the distinct states “not submitted,” “submitted—checking,” “accepted,” “rejected,” and “unknown delivery.” TanStack mutations do not retry by default, which is a safe starting point; leave automatic write retries disabled and retry explicitly with the original mutation identity. [CITED: https://tanstack.com/query/latest/docs/framework/react/guides/query-retries] React Router supplies canonical routes and SPA navigation blocking, but `useBlocker` does not protect hard reloads or cross-origin navigation, so dirty-state handling also needs a narrowly enabled `beforeunload` guard. [CITED: https://reactrouter.com/api/hooks/useBlocker]

**Primary recommendation:** Plan one thin end-to-end tracer first—closed-account login, capture, Inbox read, edit/complete, exact replay, activity, and response-loss recovery—while establishing the transaction kernel, contract vectors, and fault harness that every remaining task/list/undo command extends.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|---|---|---|---|
| Task invariants and semantic merge | API / Backend | — | Pure domain/application code is the sole authority; transports cannot patch state. [VERIFIED: 01-CONTEXT.md D-02,D-33]
| Authentication/session authorization | API / Backend | Database / Storage | Phoenix verifies cookie/CSRF/origin; PostgreSQL stores only hashed credential state and lifecycle metadata. [VERIFIED: 01-CONTEXT.md D-45..D-53]
| Idempotency, revisions, activity, undo | Database / Storage | API / Backend | PostgreSQL constraints/transactions arbitrate races; the application defines semantic results and inverses. [VERIFIED: 01-CONTEXT.md D-31..D-42,D-56..D-61]
| Inbox/Today/Upcoming/Completed/Trash projections | API / Backend | Database / Storage | Server derives account-day membership and keyset ordering; clients render explicit reasons. [VERIFIED: 01-CONTEXT.md D-04..D-07,D-21..D-27]
| Routed workspace, drafts, focus, recovery UI | Browser / Client | API / Backend | React retains local intent and renders server truth without authoring invariants. [VERIFIED: 01-CONTEXT.md D-09..D-13,D-27..D-29,D-36..D-37]
| Wire contracts/golden vectors | Shared Contract Boundary | API / Backend | Checked-in OpenAPI/JSON schemas define cross-runtime transport truth without sharing persistence/domain objects. [VERIFIED: docs/architecture/REPOSITORY.md:42-53]
| Static delivery and same-origin routing | API / Backend | CDN / Static | Phoenix can serve the Vite build in production; development proxies `/api` to avoid inventing cross-origin cookie behavior. [ASSUMED]

## Standard Stack

### Core

| Library/runtime | Verified version | Purpose | Why standard |
|---|---:|---|---|
| Elixir | 1.20.2, published 2026-06-23 | Domain/application/runtime | Current stable release verified from the official release feed; use a pinned patch version. [CITED: https://github.com/elixir-lang/elixir/releases]
| Erlang/OTP | 29.0.5, published 2026-08-04 | BEAM runtime | Current OTP 29 patch; Phoenix 1.8 supports OTP 25+. [CITED: https://github.com/erlang/otp/releases] [CITED: https://hexdocs.pm/phoenix/1.8.13/overview.html]
| Phoenix | 1.8.13, published 2026-08-25 | HTTP/session/JSON adapter | Current official Hex release; generate a non-LiveView modular monolith and own the generated auth code. [CITED: https://hex.pm/packages/phoenix]
| Ecto / Ecto SQL / Postgrex | 3.14.2 (2026-08-14) / 3.14.0 (2026-05-19) / 0.22.4 (2026-08-07) | Persistence adapter and PostgreSQL driver | Official Hex releases; Multi/Sandbox provide transactional composition and tests. [CITED: https://hex.pm/packages/ecto] [CITED: https://hex.pm/packages/ecto_sql] [CITED: https://hex.pm/packages/postgrex]
| PostgreSQL | 18.6, published 2026-08-13 | Canonical data authority | Current supported major/minor; pin the production/container major and always apply current minor updates. [CITED: https://www.postgresql.org/support/versioning/]
| React / React DOM | 19.2.8, published 2026-07-21 | Browser UI | Already pinned in the web scaffold and current on npm. [VERIFIED: apps/web/package.json:18-19] [VERIFIED: npm registry]
| TypeScript / Vite | `~6.0.2` / `^8.2.2` | Typed browser code/build | Existing scaffold constraints; retain rather than respecifying Phase 1. [VERIFIED: apps/web/package.json:36-38]

### Supporting

| Library | Verified version | Purpose | When to use |
|---|---:|---|---|
| `argon2_elixir` | 4.1.3 (2025-04-27) | Argon2id password hashing | Use through generated/owned Phoenix auth; calibrate cost on the reference VM. [CITED: https://hex.pm/packages/argon2_elixir]
| `tzdata` | 1.1.4 (2026-06-22; IANA 2026b) | IANA time-zone database | Configure as Elixir's time-zone DB so account-day conversion is not limited to UTC. [CITED: https://hexdocs.pm/tzdata/Tzdata.TimeZoneDatabase.html] [CITED: https://hexdocs.pm/elixir/Calendar.html]
| `hammer` | 7.4.1 (2026-08-29) | ETS-backed auth/setup/recovery throttling | Use one-process-node ETS backend for independent source/account buckets; persist privacy-safe security audit separately. This patch was one day old when researched, so the planner must add `checkpoint:human-verify` before installation. [CITED: https://hex.pm/packages/hammer] [ASSUMED]
| `stream_data` | 1.4.0 (2026-07-14) | Generated/model-based domain sequences | Exercise long state-machine command histories and invariants. [CITED: https://hex.pm/packages/stream_data]
| `react-router` | 8.3.1 | Canonical list/task/session routes and blocking | Use data-mode routes matching UI-SPEC. `react-router` [WARNING: flagged as suspicious — verify before using.] [CITED: https://reactrouter.com/start/data/installation]
| `@tanstack/react-query` | 5.102.8 | Read cache/background refresh | Use for server reads, not as the mutation-identity authority. `@tanstack/react-query` [WARNING: flagged as suspicious — verify before using.] [CITED: https://tanstack.com/query/latest/docs/framework/react/overview]
| `openapi-typescript` | 7.13.0 | Generate runtime-free TypeScript transport types | Generate from checked-in OpenAPI 3.1 and fail drift in CI. [VERIFIED: npm registry] [CITED: https://openapi-ts.dev/introduction]
| Vitest / Testing Library / jsdom | 4.1.11 / 16.3.3 / 30.0.1 | Browser unit/component tests | Test state transitions through accessible user interaction. `vitest`, `@testing-library/react`, `@testing-library/user-event`, and `@testing-library/jest-dom` [WARNING: flagged as suspicious — verify before using.] [CITED: https://vitest.dev/guide/] [CITED: https://testing-library.com/docs/react-testing-library/intro/]
| Playwright / axe integration | 1.62.1 / 4.13.0 | Real-stack E2E, viewport/theme/a11y evidence | Run against Phoenix + PostgreSQL; supplement axe with keyboard/manual checks. `@axe-core/playwright` [WARNING: flagged as suspicious — verify before using.] [CITED: https://playwright.dev/docs/test-webserver] [CITED: https://playwright.dev/docs/accessibility-testing]

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|---|---|---|
| Same-origin cookie session | Browser JWT/localStorage | Rejected by D-48/D-55; bearer material in browser storage weakens revocation and XSS containment. [VERIFIED: 01-CONTEXT.md D-48,D-55]
| PostgreSQL transaction + snapshots | Full event sourcing | Rejected until measured need; activity is durable user history but not the state-reconstruction mechanism. [VERIFIED: 01-CONTEXT.md D-39,D-61]
| Semantic commands | JSON Patch/last-write-wins | Rejected because they cannot preserve intent-specific merge/conflict rules. [VERIFIED: 01-CONTEXT.md D-31..D-39]
| Phoenix/Plug session + owned auth generator output | A large external identity service | The one-account, self-hosted constraint does not justify another canonical/control-plane dependency. [VERIFIED: AGENTS.md:15-19; 01-CONTEXT.md D-45..D-55]
| Dense integer Today positions | Fractional/CRDT ranks | For one user and transactional scoped moves, renumbering the small affected section is simpler; benchmark before replacing it. [ASSUMED]

**Installation baseline:** Generate `apps/server` with current `phx_new`, add `argon2_elixir`, `tzdata`, `hammer`, and `stream_data`; add the verified npm packages with pnpm only after each SUS checkpoint. Use `mix phx.gen.auth Accounts User users --no-live --hashing-lib argon2 --binary-id` as a scaffold, remove public registration/email routes, and adapt the owned output to setup/recovery/session requirements. The generator supports these switches and produces scope/session machinery. [CITED: https://hexdocs.pm/phoenix/Mix.Tasks.Phx.Gen.Auth.html]

## Package Legitimacy Audit

The npm gate and `npm view` were run on 2026-08-30; all checked Node packages reported no postinstall script. [VERIFIED: npm registry]

| Package | Registry | Latest publish | Weekly downloads | Source repo | Verdict | Disposition |
|---|---|---:|---:|---|---|---|
| react / react-dom | npm | 2026-07-21 | 171.6M / 161.2M | github.com/react/react | OK | Approved; already in scaffold |
| react-router | npm | 2026-08-28 | 53.2M | github.com/remix-run/react-router | SUS: too-new | Planner adds `checkpoint:human-verify` |
| @tanstack/react-query | npm | 2026-08-27 | 65.7M | github.com/TanStack/query | SUS: too-new | Planner adds `checkpoint:human-verify` |
| @playwright/test | npm | 2026-07-30 | 58.4M | github.com/microsoft/playwright | OK | Approved |
| vitest | npm | 2026-08-18 | 99.9M | github.com/vitest-dev/vitest | SUS: too-new | Planner adds `checkpoint:human-verify` |
| @testing-library/react | npm | 2026-08-27 | 57.1M | github.com/testing-library/react-testing-library | SUS: too-new | Planner adds `checkpoint:human-verify` |
| @testing-library/dom | npm | 2025-07-27 | 69.8M | github.com/testing-library/dom-testing-library | OK | Approved |
| @testing-library/user-event | npm | 2026-08-22 | 51.0M | github.com/testing-library/user-event | SUS: too-new | Planner adds `checkpoint:human-verify` |
| @testing-library/jest-dom | npm | 2026-08-09 | 63.2M | github.com/testing-library/jest-dom | SUS: too-new | Planner adds `checkpoint:human-verify` |
| jsdom | npm | 2026-07-29 | 98.8M | github.com/jsdom/jsdom | OK | Approved |
| @axe-core/playwright | npm | 2026-08-11 | 9.6M | github.com/dequelabs/axe-core-npm | SUS: too-new | Planner adds `checkpoint:human-verify` |
| openapi-typescript | npm | 2026-02-11 | 7.0M | github.com/openapi-ts/openapi-typescript | OK | Approved |

**Packages removed due to SLOP verdict:** none.

**Packages flagged as suspicious [SUS]:** `react-router`, `@tanstack/react-query`, `vitest`, `@testing-library/react`, `@testing-library/user-event`, `@testing-library/jest-dom`, `@axe-core/playwright`. Their registry/repository signals are strong; the seam flagged only release recency, so pin the inspected version and require the human verification checkpoint before installation.

Hex packages were confirmed through official Hex pages and registry queries. The seam has no Hex legitimacy classifier, so they do not receive an npm-style verdict. `hammer` 7.4.1 was published 2026-08-29 and is separately flagged for a human checkpoint due to release recency. [CITED: https://hex.pm]

## Architecture Patterns

### System Architecture Diagram

```text
Browser route / quick capture
        │
        ├─ local draft + fixed UUIDv4 mutation identity
        ▼
Phoenix router → session + origin/CSRF → JSON decoder / command DTO
        │                       └─ auth/structural failure → Problem Details (not receipted)
        ▼
Application command dispatcher (semantic command, injected clock/account day)
        │
        ▼
PostgreSQL transaction
  mutation receipt unique insert / replay decision
        ├─ same identity, different fingerprint → stored mutation_identity_reused result
        ├─ same identity, same fingerprint → stored original result
        └─ first delivery → lock task/order scope → pure domain decision
                              ├─ accepted → snapshot + activity + optional undo
                              └─ semantic rejection/conflict → conflict/result record
                         → store terminal command response → COMMIT
        │
        ▼
Exact acknowledgement / RFC 9457 error
        │
        ├─ received → reconcile query cache, clear only matching draft
        └─ response lost → retain draft/identity → result lookup or same-ID retry
```

This diagram is the required correctness path; sockets/background delivery are optional latency tools and are not correctness assumptions. [VERIFIED: AGENTS.md:110-110; 01-CONTEXT.md D-31..D-38]

### Recommended Project Structure

The repository boundary paths are locked; the internal module/file names below are a recommended starting shape. [VERIFIED: docs/architecture/REPOSITORY.md:7-24] [ASSUMED]

```text
apps/server/
├── lib/keepling/domain/             # pure task, organization, activity decisions
├── lib/keepling/application/        # semantic commands, ports, result types
├── lib/keepling/adapters/postgres/  # Ecto schemas/repos/transaction kernel
├── lib/keepling_web/                # router, auth/session, JSON controllers
├── priv/repo/migrations/
└── test/{domain,application,adapters,keepling_web}/
apps/web/src/
├── app/                 # providers and data-mode router
├── features/            # capture, task editor, lists, sessions, activity
├── commands/            # fixed-ID submission/recovery state machine
├── api/                 # generated types and handwritten semantic facade
└── test/                # fixtures, a11y and fault helpers
packages/contracts/
├── openapi/             # OpenAPI 3.1 source
├── schemas/             # non-HTTP closed schemas where required
├── vectors/             # storage-neutral domain/command/error vectors
└── generated/           # reproducible outputs or drift manifests
tooling/                 # contract generation/drift and cross-stack test orchestration
```

### Pattern 1: Pure Decision, Transactional Interpretation

**What:** The domain receives canonical current state plus a closed command and returns either a new canonical state/effects or a typed semantic rejection. It never reads the clock, database, HTTP connection, or Ecto schema itself. The application layer supplies account day and acceptance time through declared ports, while the PostgreSQL adapter interprets effects in one transaction. [VERIFIED: AGENTS.md:13-16,107-109]

**When to use:** Every task, project, tag, reorder, conflict-resolution, and undo command.

**Planning implication:** Build the first vertical command through all layers before filling out horizontal repositories/controllers. Keep Ecto changesets for persistence shape/constraints and domain validation for product invariants; do not make a changeset the public domain API. [ASSUMED]

### Pattern 2: Account-Scoped Idempotency Receipt as Transaction Gate

**What:** Canonicalize the authenticated semantic command, compute a server-side cryptographic fingerprint with the standard library, and insert an account-scoped receipt under a unique constraint. The winning transaction evaluates and records the command. A replay either returns the stored terminal envelope or, if its fingerprint differs, the stored stable error whose locked code is quoted verbatim as `mutation_identity_reused`. [VERIFIED: 01-CONTEXT.md D-31,D-32]

**When to use:** Every user-visible semantic mutation, including conflict resolution and undo.

**Schema responsibilities:** Use separate tables/representations for task snapshots, mutation receipts, structured conflicts, undo handles, task activity, and session/security audit state. This separation is locked conceptually even though exact table names are discretionary. [VERIFIED: 01-CONTEXT.md D-56..D-63]

**Important:** Persist accepted and terminal semantic-rejection envelopes. Do not call `Repo.rollback/1` merely because the command result is a conflict; a rollback would remove the result it must replay. [VERIFIED: 01-CONTEXT.md D-32,D-35]

### Pattern 3: Optimistic Revision + Narrow Server-Owned Merge

**What:** Updates carry expected aggregate revision and only touched fields with base/requested values. Under a row lock, compare each touched field with base/requested values; rebase only when allowed, then rerun all aggregate invariants. Lifecycle rules remain command-specific: complete/reopen can cross unrelated edits; Trash/restore/undo demand exact revision. [VERIFIED: 01-CONTEXT.md D-31..D-35]

**When to use:** Any command against an existing aggregate.

**Planning implication:** Put all merge/lifecycle cases into storage-neutral vectors consumed by Elixir domain tests and TypeScript UI fixtures. Generate no client merge engine; the browser only presents server-produced affected-field conflict data. [VERIFIED: 01-CONTEXT.md D-33,D-36,D-39]

### Pattern 4: Canonical Account Day

**What:** Store `planned_on` and `deadline_on` as PostgreSQL/Ecto dates, and lifecycle/audit/acceptance values as UTC microsecond instants. Configure `tzdata`, inject the clock, and resolve the configured IANA account timezone once at command/query acceptance. Elixir's default time-zone database supports UTC only until another database is configured. [VERIFIED: 01-CONTEXT.md D-04..D-07] [CITED: https://hexdocs.pm/elixir/Calendar.html]

**When to use:** Today, Upcoming, Completed-today, warnings, activity display, and expiry boundaries.

**Planning implication:** Golden vectors must freeze UTC instant, account timezone, account day, daylight-saving boundary, and both dates. Device timezone must never enter membership logic. [VERIFIED: 01-CONTEXT.md D-05,D-60]

### Pattern 5: Read Cache vs. Command State Machine

**What:** TanStack Query holds last-good server reads and background refresh states. A separate command object owns draft snapshot, original mutation identity, request bytes/semantics, delivery state, authentication interruption, result lookup, and exact reconciliation. [CITED: https://tanstack.com/query/latest/docs/framework/react/guides/mutations] [VERIFIED: 01-CONTEXT.md D-11,D-27,D-37,D-51]

**When to use:** Quick capture, editor Save/Save & move, lifecycle actions, reorder, conflict resolution, and undo.

**Planning implication:** Do not optimistically remove rows for commands that change membership. Show pending state, then apply the returned snapshot/projection only when the acknowledgement contains the exact submitted mutation identity. [VERIFIED: 01-CONTEXT.md D-16,D-24,D-25,D-38]

### Pattern 6: Same-Origin Session Boundary

**What:** Use Phoenix/Plug signed session facilities only to carry the opaque raw session credential in a Secure, HttpOnly, host-only, SameSite=Lax cookie; store only the credential hash and lifecycle metadata in PostgreSQL. Fetch a CSRF token into the React bootstrap and send it in `x-csrf-token` for state-changing JSON requests. Rotate session and CSRF state at authentication transitions. Plug requires a fetched session and supports header validation; it recommends `delete_csrf_token/0` after login. [VERIFIED: 01-CONTEXT.md D-48,D-52] [CITED: https://hexdocs.pm/plug/Plug.CSRFProtection.html]

**When to use:** All browser routes and every cookie-authenticated mutation.

**Planning implication:** Use a Vite `/api` proxy in development and serve/proxy React and Phoenix under one production origin. This avoids adding a CORS credential matrix to the MVP. [ASSUMED]

### Pattern 7: Closed Bootstrap and Recovery

**What:** Start from `mix phx.gen.auth` controller/session/scopes code, but expose no registration or mandatory email flow. An operator command emits a short-lived raw setup/recovery secret once; PostgreSQL stores only its hash, expiry, purpose, and consumed state. Account creation and permanent setup consumption happen in one transaction. Recovery accepts the token in a browser link and lets the browser submit the new password without the password appearing in CLI args, env, or logs. [VERIFIED: 01-CONTEXT.md D-45..D-47] [CITED: https://hexdocs.pm/phoenix/Mix.Tasks.Phx.Gen.Auth.html]

### Pattern 8: Append-Only Activity, Not Event Sourcing

**What:** Every accepted command appends one closed, versioned activity fact in the same transaction, containing exact changed canonical values and server-derived actor/client metadata. The current task snapshot remains canonical; activity supports trust/history but does not rebuild state. [VERIFIED: 01-CONTEXT.md D-56..D-63]

**When to use:** All accepted task commands, including typed undo compensation.

**Planning implication:** Escape/render all stored values as text; keep mutation receipts, conflicts, security audit, and telemetry in separate schemas and APIs. [VERIFIED: 01-CONTEXT.md D-58,D-61]

### Anti-Patterns to Avoid

- **CRUD endpoints or raw patches:** They bypass command-specific invariant, conflict, activity, and undo behavior. Use one closed versioned schema per semantic command. [VERIFIED: 01-CONTEXT.md D-31,D-39]
- **Read-before-insert idempotency:** Two concurrent deliveries can both observe absence. Make the unique constraint the arbiter and test concurrent first delivery. [CITED: https://www.postgresql.org/docs/current/ddl-constraints.html]
- **Rolling back a semantic conflict:** This destroys replay evidence. Commit the conflict/result receipt without applying the aggregate effect. [VERIFIED: 01-CONTEXT.md D-32,D-35]
- **Client mutation retries with new identities:** This can duplicate accepted intent after response loss. The original identity is part of the draft until a terminal result is known. [VERIFIED: 01-CONTEXT.md D-11,D-37]
- **Derived Inbox or persisted Today membership:** Inbox is explicit; Today is a query over dates/account day. [VERIFIED: 01-CONTEXT.md D-04,D-14]
- **Ecto schema as domain/wire DTO:** It couples rules, persistence, and future clients. Map explicitly at boundaries. [VERIFIED: AGENTS.md:109-109]
- **Global in-memory rate limit only:** ETS fits the one-node reference, but account/source buckets and generic response semantics still need deterministic tests; a restart resets counters and must not create a permanent trust claim. [ASSUMED]
- **Optimistic row disappearance:** It can falsely communicate acceptance. Preserve row/draft until the matching acknowledgement. [VERIFIED: 01-CONTEXT.md D-16,D-37]
- **Color-only membership/conflict or custom grid semantics:** Use text/reasons, native controls, focus restoration, and a live region. [VERIFIED: 01-CONTEXT.md D-06,D-13,D-28,D-36]
- **Snapshot-only UI tests:** Accessibility names, keyboard behavior, focus, draft preservation, and backend truth require behavior and E2E tests. [CITED: https://playwright.dev/docs/accessibility-testing]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---|---|---|---|
| Password hashing | Custom crypto/KDF | `argon2_elixir` / Argon2id | Password hashing requires calibrated memory/time cost and safe verification. [CITED: https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html]
| Session/CSRF primitives | Browser token storage or ad hoc CSRF header | Phoenix/Plug session and CSRF protection | Plug already handles token masking/comparison and session integration. [CITED: https://hexdocs.pm/plug/Plug.CSRFProtection.html]
| Transaction composition | Manually nested success/error callbacks | Ecto.Multi + `Repo.transact/2` | Named operations and one database transaction make failure location testable. [CITED: https://hexdocs.pm/ecto/Ecto.Multi.html]
| IANA timezone rules | Offset arithmetic | `tzdata` + Calendar/DateTime | UTC offsets change; the account stores an IANA zone, not a fixed offset. [CITED: https://hexdocs.pm/tzdata/Tzdata.TimeZoneDatabase.html]
| UUID generation | Timestamp/random concatenation | Browser `crypto.randomUUID()` and native UUID APIs | Web Crypto returns cryptographically secure RFC 4122 v4 identifiers without a package. [CITED: https://developer.mozilla.org/en-US/docs/Web/API/Crypto/randomUUID]
| HTTP error envelope | Bespoke generic JSON error | RFC 9457 Problem Details + closed Keepling extensions | A standard envelope supports stable code, retryability, recovery action, field errors, and conflicts. [CITED: https://www.rfc-editor.org/rfc/rfc9457.html]
| TypeScript transport model | Duplicated handwritten DTOs | Checked-in OpenAPI 3.1 + `openapi-typescript` | Deterministic generation and drift checks expose cross-runtime changes. [CITED: https://openapi-ts.dev/introduction]
| Browser routing/blocking | Custom history stack | React Router `useBlocker` plus scoped `beforeunload` | SPA and hard-navigation cases differ; use platform/library boundaries. [CITED: https://reactrouter.com/how-to/navigation-blocking]
| Server-read cache | Custom request cache/deduper | TanStack Query | It models initial/background/error/refetch states; Keepling still owns write identity. [CITED: https://tanstack.com/query/latest/docs/framework/react/overview]
| Auth rate limiting | Ad hoc process counters | Hammer ETS with explicit buckets/policy | Existing limiter mechanics avoid reimplementing windows/counters; exact policy remains measured. [CITED: https://hex.pm/packages/hammer]
| Browser automation | Homegrown Selenium scripts | Playwright Test | Built-in web server orchestration, emulation, tracing, screenshots, and browser contexts support required evidence. [CITED: https://playwright.dev/docs/test-webserver]

**Key insight:** Keepling should hand-write semantic task behavior and its compact transaction kernel because those are product truth; it should not hand-write security, timezone, protocol, routing, cache, or browser-automation primitives whose edge cases are unrelated to the product.

## Common Pitfalls

### Pitfall 1: Stable replay is accidentally transactional rollback

**What goes wrong:** A stale edit returns a conflict, but the receipt insert rolls back with it; retry later produces a different result.

**Why it happens:** Framework error tuples are treated as database failures even when they are terminal semantic outcomes.

**How to avoid:** Separate infrastructure failure from semantic result. Store the closed conflict/rejection envelope and commit; use rollback only when no trustworthy terminal receipt can be persisted. [VERIFIED: 01-CONTEXT.md D-32,D-35]

**Warning signs:** Replaying a conflict queries current state again, conflict IDs change, or there is no receipt row for a known rejected command.

### Pitfall 2: Read Committed is mistaken for invariant protection

**What goes wrong:** Two concurrent captures/reorders/account setups both pass preflight checks or overwrite a scoped order.

**Why it happens:** PostgreSQL Read Committed gives each command statement a fresh snapshot and ordinary SELECT does not lock the invariant scope. [CITED: https://www.postgresql.org/docs/current/transaction-iso.html]

**How to avoid:** Back uniqueness with database constraints, lock the task/order/account-setup scope before deriving changes, and retry explicitly if Serializable is chosen for a transaction.

**Warning signs:** Application-only uniqueness, `Repo.get` followed by insert, or concurrency tests that never use separate database connections.

### Pitfall 3: Unknown delivery is collapsed into failure

**What goes wrong:** A timeout after commit leaves the UI saying failed and a retry receives a new mutation identity, duplicating intent.

**Why it happens:** Network completion is confused with server transaction outcome.

**How to avoid:** Store the original identity and submitted semantic request in the command state, show “Checking whether your change was saved…”, and query/retry only with that identity. [VERIFIED: 01-CONTEXT.md D-37; 01-UI-SPEC.md:176-184,265-270]

**Warning signs:** UUID generation occurs inside each fetch attempt, draft clears in a `finally`, or TanStack mutation retries are globally enabled.

### Pitfall 4: Account day leaks device timezone

**What goes wrong:** Today/Upcoming/Completed group membership differs between browser, server tests, or DST transitions.

**Why it happens:** Client-side `new Date()` or server local time is used to derive civil day.

**How to avoid:** Derive the account civil date server-side from injected UTC time plus configured IANA timezone; return membership reasons and exact dates. [VERIFIED: 01-CONTEXT.md D-04..D-07,D-60]

**Warning signs:** persisted `is_today`, fixed UTC offsets, or membership SQL that calls database current date without the account zone.

### Pitfall 5: Generated auth is mistaken for the product policy

**What goes wrong:** Public registration/email routes leak into a closed one-account product, setup can race, or session rotation/draft preservation is incomplete.

**Why it happens:** `phx.gen.auth` provides a strong scaffold but generated code is application-owned and does not encode D-45..D-55. [CITED: https://hexdocs.pm/phoenix/Mix.Tasks.Phx.Gen.Auth.html]

**How to avoid:** Generate early, audit every route, keep scopes/session patterns, then implement explicit operator setup/recovery and session inventory/revocation. Track upstream security generator changes after generation.

**Warning signs:** registration endpoint exists, recovery email is required, raw token is stored, or login redirects wipe an editor draft.

### Pitfall 6: Activity becomes an accidental content leak or event store

**What goes wrong:** Full snapshots/notes are copied repeatedly, arbitrary payloads enter history, or telemetry receives activity/mutation IDs.

**Why it happens:** One generic JSON “event” table is used for user history, idempotency, diagnostics, and state reconstruction.

**How to avoid:** Closed versioned activity types, only changed old/new canonical values, text rendering, distinct receipt/conflict/security/telemetry stores. [VERIFIED: 01-CONTEXT.md D-56..D-63]

**Warning signs:** HTML in activity, client-provided actor labels, raw command bodies in logs, or task reconstruction from history.

### Pitfall 7: Accessibility is verified only by axe

**What goes wrong:** Automated checks pass while dirty-navigation, focus restoration, keyboard capture, live announcements, or 320px reflow fails.

**Why it happens:** Static rule automation cannot infer all interaction behavior. Playwright explicitly recommends combining automated tests with manual inclusive-design and usability work. [CITED: https://playwright.dev/docs/accessibility-testing]

**How to avoid:** Add keyboard/focus assertions, both themes, reduced motion, forced colors, zoom/reflow, and representative manual screen-reader checks from UI-SPEC.

**Warning signs:** no test observes `document.activeElement`, no narrow viewport run, or snapshots are the only UI evidence.

## Code Examples

These examples illustrate official primitives, not final Keepling module names or schemas.

### Commit a multi-step result atomically

```elixir
# Source: https://hexdocs.pm/ecto/Ecto.Multi.html
multi =
  Ecto.Multi.new()
  |> Ecto.Multi.insert(:receipt, receipt_changeset)
  |> Ecto.Multi.run(:decision, fn repo, %{receipt: receipt} ->
    apply_semantic_command(repo, receipt, command)
  end)
  |> Ecto.Multi.insert(:activity, fn %{decision: decision} ->
    activity_changeset(decision)
  end)
  |> Ecto.Multi.update(:terminal_receipt, fn %{decision: decision} ->
    terminal_receipt_changeset(decision)
  end)

Repo.transact(multi)
```

`Ecto.Multi.run/3` permits repository-dependent work, and `Repo.transact/2` returns the failed operation and changes; Keepling must refine this skeleton so a terminal semantic rejection updates the receipt and commits rather than returning an infrastructure error tuple. [CITED: https://hexdocs.pm/ecto/Ecto.Multi.html] [ASSUMED]

### Protect JSON mutations with Plug CSRF

```javascript
// Source: https://hexdocs.pm/plug/Plug.CSRFProtection.html
await fetch("/api/commands", {
  method: "POST",
  credentials: "same-origin",
  headers: {
    "content-type": "application/json",
    "x-csrf-token": csrfToken,
  },
  body: JSON.stringify(command),
})
```

The header name quoted by Plug is `x-csrf-token`; the server must also validate origin/host and rotate session/CSRF state after authentication. [CITED: https://hexdocs.pm/plug/Plug.CSRFProtection.html] [VERIFIED: 01-CONTEXT.md D-48]

### Generate a mutation identity before delivery

```typescript
// Source: https://developer.mozilla.org/en-US/docs/Web/API/Crypto/randomUUID
const mutationId = crypto.randomUUID()
const submission = { mutationId, command }
```

`crypto.randomUUID()` is available only in secure contexts and produces a cryptographically secure v4 UUID. Keep this identity with the draft across authentication and response-loss recovery. [CITED: https://developer.mozilla.org/en-US/docs/Web/API/Crypto/randomUUID] [VERIFIED: 01-CONTEXT.md D-11,D-37,D-51]

### Block SPA navigation while a form is dirty

```tsx
// Source: https://reactrouter.com/how-to/navigation-blocking
const blocker = useBlocker(
  useCallback(() => isDirty, [isDirty]),
)
```

React Router's blocker covers client-side navigation only; activate `beforeunload` only while dirty for reload/tab-close coverage, and render the UI-SPEC's Save/Discard/Stay choices rather than a generic silent loss. [CITED: https://reactrouter.com/api/hooks/useBlocker] [VERIFIED: 01-CONTEXT.md D-12]

## State of the Art

| Old approach | Current approach | When changed | Impact |
|---|---|---|---|
| Phoenix auth generator without scopes | `phx.gen.auth` generates scope-aware auth and tracked database sessions | Phoenix 1.8 | Retain scopes/session patterns, then adapt closed setup/recovery rather than inventing the base auth plumbing. [CITED: https://phoenix.hexdocs.pm/mix_phx_gen_auth.html]
| `Repo.transaction/2` naming | `Repo.transact/2` is the current Ecto entry point; `transaction/2` is deprecated | Ecto 3.13 | New code and examples should use `transact`. [CITED: https://hexdocs.pm/ecto/Ecto.Repo.html]
| RFC 7807 Problem Details | RFC 9457 Problem Details | July 2023 | Use RFC 9457 media types/semantics and Keepling closed extensions. [CITED: https://www.rfc-editor.org/rfc/rfc9457.html]
| WCAG 2.1 baseline | WCAG 2.2 Recommendation | October 2023 | Include Focus Not Obscured, Target Size, Consistent Help, and Accessible Authentication criteria where applicable. [CITED: https://www.w3.org/TR/WCAG22/]
| PostgreSQL 14 local development | PostgreSQL 18 current supported major | PostgreSQL 18 released September 2025; 18.6 current in this session | Upgrade the development/test target; PostgreSQL 14 reaches final release November 12, 2026. [CITED: https://www.postgresql.org/support/versioning/]

**Deprecated/outdated:**

- Ecto `Repo.transaction/2`: use `Repo.transact/2` in new code. [CITED: https://hexdocs.pm/ecto/Ecto.Repo.html]
- Browser JWT/bearer credentials in local/session storage: explicitly rejected for this product. [VERIFIED: 01-CONTEXT.md D-48,D-55]
- Offset pagination for task/activity lists: explicitly replaced by account-bound keyset cursors with relevant revision. [VERIFIED: 01-CONTEXT.md D-26,D-60]
- Phoenix LiveView as the browser UI: React is locked; generate controller-based auth and JSON transport, not a second UI runtime. [VERIFIED: 01-CONTEXT.md D-03]

## Likely Planning Decomposition

This is not a plan; it identifies dependency seams the planner should preserve. [ASSUMED]

1. **Wave 0—toolchain and evidence harness:** pin Elixir/OTP/PostgreSQL, scaffold standalone Phoenix without nested repositories, establish ExUnit/Sandbox/StreamData, add web test tooling after SUS checkpoints, create real-stack Playwright boot, and add architecture/privacy guard tests.
2. **Contract/domain tracer:** checked-in OpenAPI 3.1 plus golden vectors; pure task aggregate; civil dates/account day; closed command/result/problem types; generated TS transport drift check.
3. **Transactional command kernel:** receipt/fingerprint/replay, revision/merge, activity, undo handle, conflict, task/order locks, concurrency and before/after-commit response-loss tests.
4. **Closed identity/session slice:** operator setup/recovery, password login/reauth/logout, hashed tracked sessions, CSRF/origin, revocation, expiry, independent rate limits, security audit and redaction.
5. **Browser tracer:** same-origin boot, auth shell, query/command adapters, capture/Inbox/task route/edit/complete/reopen, exact acknowledgement and reauth/unknown-delivery recovery.
6. **Full Phase 1 semantics:** Today/Upcoming/Completed/Trash, projects/tags, clarify/return, reorder/cursors, restore, supported undo matrix, activity pagination and conflict resolution.
7. **UI/evidence closure:** all registered states, focus/keyboard/live regions, narrow/wide behavior, themes/forced colors/reduced motion, visual baselines, real database E2E, adversarial sequences, and telemetry negative assertions.

The planner should keep each feature slice vertical through domain → transaction → contract → browser → evidence, with the command kernel reused rather than duplicating endpoint-specific transaction logic. [VERIFIED: 01-CONTEXT.md D-02,D-31..D-39]

## Assumptions Log

| # | Claim | Section | Risk if wrong |
|---|---|---|---|
| A1 | Serve/proxy React and Phoenix under one origin in production and use a Vite `/api` proxy in development. | Summary / Pattern 6 | A separate origin would require an explicit credentialed-CORS, origin allow-list, cookie-domain, deployment, and E2E design. |
| A2 | Use dense integer positions and transactional section renumbering for Today until measurement requires another representation. | Standard Stack alternatives | Large Today lists or write contention could justify a different internal rank while preserving semantic move commands. |
| A3 | Internal module/file/table names in the project tree and schema discussion are recommendations, not locked names. | Project Structure / Patterns | Planner may select different names but must preserve boundaries and separate representations. |
| A4 | Hammer ETS is sufficient for the single-node Phase 1 reference deployment. | Standard Stack / Pitfalls | Process/node restarts reset limiter counters; a durable or external backend would increase operational complexity. |
| A5 | The proposed Wave 0 scripts and test file paths will be created with the scaffold. | Validation Architecture | Commands do not exist yet and cannot be treated as current evidence. |
| A6 | Use OpenAPI 3.1 because current `openapi-typescript` documentation supports OpenAPI 3.0/3.1. | Contracts | A later toolchain may support OpenAPI 3.2, but adopting it now could break generation. |
| A7 | Use standard-library SHA-256 over deterministic canonical command bytes for semantic fingerprints. | Idempotency | Canonicalization must be specified across versions; an unstable encoding would falsely report identity reuse. |
| A8 | Store hashed undo handles with typed inverse payload and produced revision in a separate table. | Undo architecture | Another schema can work, but raw handle storage or untyped arbitrary payloads would violate security/closed-contract goals. |
| A9 | The proposed phase decomposition is the most efficient dependency order. | Likely Planning Decomposition | Planner may merge/split waves based on repository state, while preserving the tracer-first dependency chain. |
| A10 | Keep Ecto changesets at the persistence boundary and product invariants in pure domain decisions. | Pattern 1 | A different implementation can preserve the dependency direction, but using changesets as the public domain API would couple layers. |
| A11 | Build the deterministic fault harness with injected clocks/IDs, process barriers, captured telemetry, and test-only response-drop controls. | Validation Architecture / Security | Poor isolation could make tests flaky or accidentally expose fault controls in production. |
| A12 | RESOLVED: explicit setup-time IANA timezone; operator-mediated changes never rewrite dates. | Open Questions (RESOLVED) 2 | Later browser settings may call the same setting seam without changing stored dates. |
| A13 | RESOLVED: retain authenticated/authorized/structurally valid terminal semantic receipts for account lifetime; exclude pre-auth/CSRF/malformed/unauthorized traffic. | Open Questions (RESOLVED) 5 | A later purge policy must delete stored response bodies consistently. |
| A14 | RESOLVED: HMAC-authenticated, account-scoped, versioned cursor payloads with per-view revisions. | Open Questions (RESOLVED) 6 | Rule changes invalidate old cursors explicitly without data migration. |
| A15 | Persist hashes, not raw setup/recovery/session/undo bearer secrets, and use constant-time comparison. | Security checklist | Exact hash/keying strategy must be specified and rotated safely. |
| A16 | RESOLVED: versioned title/notes/organization/session-label bounds plus measured password/body/query timeouts. | Open Questions (RESOLVED) 1 | Later changes use explicit contract versions and expand/migrate/contract. |
| A17 | RESOLVED: undo saved details, clarify/return, plan/unplan, complete/reopen, and Trash/restore; exclude reorder and organization commands. | Open Questions (RESOLVED) 3 | The matrix is additive/versioned so later support can expand compatibly. |

## Open Questions (RESOLVED)

1. **Field limits and name equivalence — resolved.** Task titles are 1–512 Unicode scalar values after outer-whitespace trim; notes are 0–50,000 scalar values and otherwise preserved as plain text. Project/tag/session labels are 1–200 scalar values after outer-whitespace trim. Active organization-name collision uses a versioned derived key: Unicode NFC, outer trim, then Unicode case-fold; display form is preserved. Password upper bound and Argon2id cost remain measured on the reference VM as explicitly allowed by the agent-discretion boundary. Bounds and equivalence versions are contract constants/golden vectors; later changes use expand, migrate, age out, contract. This makes the decision costly, not one-way. [VERIFIED: D-46 and compatibility constraint] [ASSUMED: task/organization limits]

2. **Initial account timezone and change path — resolved.** Setup requires an explicit valid IANA timezone; there is no deployment/device-derived default. Phase 1 changes are operator-mediated, validate an IANA name, and never rewrite stored civil dates. The setting is reversible because a later change affects subsequent account-day interpretation only. [VERIFIED: D-05]

3. **Supported undo matrix — resolved.** Saved detail edits, clarify/return, plan/unplan, complete/reopen, and Trash/restore may return a handle. Reorder and project/tag management do not. The matrix is versioned and additive: later commands may gain handles without changing existing stored task data or invalidating old consumers, so the initial selection is costly rather than one-way. [VERIFIED: D-40..D-44] [ASSUMED: matrix selection]

4. **Temporal classification — resolved.** Today eligibility is independently true for every planned/deadline date on or before account day. Past planned intent appears in Overdue with `Planned overdue`; past deadline appears with `Overdue deadline`; equal/today reasons appear in Today; combined reasons remain combined. Upcoming independently includes the next future relevant date, so a task may be in Today for a past/today reason and Upcoming for a later deadline. The full date-pair/DST truth table is versioned; changing classification requires a contract/vector version but no stored-date migration. [VERIFIED: D-04..D-07,D-23]

5. **Terminal receipt classes and retention — resolved.** After authentication, authorization/account scoping, and structural decoding establish receipt ownership, retain accepted results, `already_satisfied`/typed no-change results, invariant/validation rejections, stale outcomes, and persisted conflicts for the account lifetime in Phase 1. Pre-authentication, CSRF/origin/host, malformed JSON/schema, and unauthorized/not-found probes are not receipted. A fingerprint mismatch returns stable `mutation_identity_reused` from the existing receipt without overwriting it. Infrastructure failure is not terminal unless a terminal receipt committed; after-commit response loss recovers that stored result. Later permanent purge must remove receipt bodies consistently with D-63. [VERIFIED: D-31,D-32,D-35,D-38,D-63]

6. **Cursor invalidation — resolved.** Every opaque cursor is HMAC-authenticated and session-account scoped, contains the complete unique keyset tuple and a versioned view revision, and never supplies authorization. A membership-affecting accepted command bumps each affected task-view revision; Today moves additionally bump its scoped order revision; insertion invalidates an older page cursor rather than claiming gap-free continuation; activity uses a separate activity-view revision and cursor. Any mismatch returns the locked stale/refresh action. Cursor payload versioning allows rules to change by invalidating cursors without data migration, so the choice is costly rather than one-way. [VERIFIED: D-22,D-26,D-60]

## Environment Availability

The following probes were executed on 2026-08-30 from the repository root. [VERIFIED: local command probes]

| Dependency | Required by | Available | Local version/state | Fallback/action |
|---|---|---|---|---|
| Node.js | web build/tests | ✓ | v22.14.0 | Meets Vitest's documented Node >=20 baseline. [CITED: https://vitest.dev/guide/]
| pnpm | workspace/install | ✓ | 10.33.0 | Use existing workspace tooling. |
| npm | registry verification only | ✓ | 11.1.0 | Do not change package manager from pnpm. |
| Elixir / Mix | Phoenix server | ✓, upgrade required | 1.19.5 | Pin/install 1.20.2 before scaffold/evidence. |
| Erlang/OTP | Phoenix server | ✓, upgrade required | OTP 28 | Pin/install OTP 29.0.5 alongside Elixir baseline. |
| PostgreSQL client/server | canonical store/tests | ✓, upgrade required | 14.17; local server responding at `/tmp:5432` | Install/use controlled PostgreSQL 18.6; do not call 14 release-ready. |
| Docker CLI | optional reproducible DB/E2E | Partial | 29.5.2; daemon unavailable | Start/configure daemon or use a directly installed pinned PostgreSQL 18.6. |
| Existing web dependencies | current scaffold | ✓ | installed; React 19.2.8, Vite 8.2.2 constraints | Preserve current scaffold and lockfile. [VERIFIED: apps/web/package.json:13-38]
| Server scaffold | server implementation/tests | ✗ | `apps/server` has only boundary documentation | Wave 0 creates standalone Phoenix app in place, without nested Git. [VERIFIED: repository inspection]
| Browser test framework/config | web validation | ✗ | no Vitest/Playwright config or test files | Wave 0 installation/config after legitimacy checkpoints. [VERIFIED: repository inspection]

**Missing dependencies with no fallback:** none if the installed Elixir/OTP/PostgreSQL can be upgraded; those upgrades are prerequisites to the intended verified baseline.

**Missing dependencies with fallback:** Docker daemon is unavailable; direct local PostgreSQL 18.6 is a viable test fallback. The planner must still ensure CI/E2E uses a reproducible supported PostgreSQL version.

## Validation Architecture

Nyquist validation is enabled in `.planning/config.json`; all listed test paths/configurations are Wave 0 gaps because the runtime scaffold has not yet been created. [VERIFIED: .planning/config.json:20-25; repository inspection]

### Test Framework

| Layer | Framework | Config/fixture | Quick run | Full run |
|---|---|---|---|---|
| Pure server domain/application | ExUnit (Elixir 1.20.2) + StreamData 1.4.0 | `apps/server/test/test_helper.exs` | `cd apps/server && mix test test/keepling/domain --max-failures 1` | `cd apps/server && mix test` |
| PostgreSQL/migrations/concurrency | ExUnit + Ecto SQL Sandbox 3.14.0 + real PostgreSQL 18.6 | `apps/server/test/support/data_case.ex` | `cd apps/server && mix test test/keepling/adapters/postgres --max-failures 1` | `cd apps/server && mix test --include integration` |
| HTTP/auth/contracts | ExUnit ConnCase + OpenAPI/golden-vector drift tool | `apps/server/test/support/conn_case.ex`, `packages/contracts/` | `cd apps/server && mix test test/keepling_web --max-failures 1` | planned root `pnpm contracts:check && cd apps/server && mix test` |
| React components/orchestration | Vitest 4.1.11 + Testing Library + jsdom 30.0.1 | `apps/web/vitest.config.ts`, `apps/web/src/test/setup.ts` | `pnpm --filter @keepling/web test --run` | same command with coverage/reporting configured |
| Real browser/system | Playwright Test 1.62.1 + axe 4.13.0 | `apps/web/playwright.config.ts` | `pnpm --filter @keepling/web test:e2e --grep @smoke` | `pnpm --filter @keepling/web test:e2e` |

All commands in this table are recommended Wave 0 scripts and are not currently executable. [ASSUMED] Ecto SQL Sandbox supplies transactional test ownership/isolation, but concurrency tests must use separate connections/processes and real commits rather than a single shared sandbox transaction. [CITED: https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.Sandbox.html]

### Requirement → Test Map

| Req ID | Behavior | Best layer | Automated command (<30s target) | File exists? |
|---|---|---|---|---|
| GTD-01 | Capture validates title, sets explicit Inbox, returns stable ID, replays once | domain + PostgreSQL + contract | `cd apps/server && mix test test/keepling/application/capture_task_test.exs` | ❌ Wave 0 |
| GTD-02 | Touched-field edits, atomic project/tags, clarify, validation preservation | domain vector + browser component | `cd apps/server && mix test test/keepling/domain/edit_task_test.exs` | ❌ Wave 0 |
| GTD-03 | Plan/unplan Today independent of deadline; warning code quoted as `planned_after_deadline` | domain/account-day vectors | `cd apps/server && mix test test/keepling/domain/task_dates_test.exs` | ❌ Wave 0 |
| GTD-04 | Upcoming/Today truth table across timezone/DST/date pairs | query integration + golden vectors | `cd apps/server && mix test test/keepling/adapters/postgres/task_views_test.exs` | ❌ Wave 0 |
| GTD-05 | Complete/reopen replay, `already_satisfied`, unrelated-edit rebase, lifecycle conflict | domain state machine + integration | `cd apps/server && mix test test/keepling/application/task_lifecycle_test.exs` | ❌ Wave 0 |
| GTD-06 | Trash/restore exact revision, retained fields/history/order destination | domain + persistence | `cd apps/server && mix test test/keepling/application/trash_restore_test.exs` | ❌ Wave 0 |
| GTD-07 | 24h boundary, ownership, one-shot, exact produced revision, retry/response loss | domain + persistence/security | `cd apps/server && mix test test/keepling/application/undo_test.exs` | ❌ Wave 0 |
| SRV-01 | Closed setup, Argon2id login, CSRF/origin, expiry, recent auth, sessions/revocation/recovery | ConnCase + PostgreSQL + E2E | `cd apps/server && mix test test/keepling_web/auth_test.exs` | ❌ Wave 0 |
| SRV-02 | Phoenix adapter cannot bypass common command boundary | architecture + golden adapter vectors | `cd apps/server && mix test test/architecture_test.exs` | ❌ Wave 0 |
| SRV-03 | Concurrent duplicate, fingerprint mismatch, stored rejection, before/after-commit loss | PostgreSQL concurrency/fault tests | `cd apps/server && mix test test/keepling/adapters/postgres/idempotency_test.exs` | ❌ Wave 0 |
| WEB-01 | Login → capture → Inbox → edit → complete → reopen against real stack | Playwright smoke | `pnpm --filter @keepling/web test:e2e --grep @smoke` | ❌ Wave 0 |
| WEB-02 | Initial/empty/loading/updating/validation/auth/stale/conflict/retry/unknown states and focus | Vitest interaction + Playwright fault cases | `pnpm --filter @keepling/web test --run` | ❌ Wave 0 |
| QUAL-01 | Deterministic long sequences and boundary-appropriate suites | all layers | planned root `pnpm test` plus `cd apps/server && mix test` | ❌ Wave 0 |

The exact test file names and scripts are recommendations; the behavior mapping is required. [ASSUMED]

### Deterministic Fault and Concurrency Matrix

| Fault/boundary | Injection point | Required assertion |
|---|---|---|
| Duplicate first delivery | Two independent DB connections release on a barrier | One aggregate effect/activity; both callers get byte/semantic-equivalent stored result. |
| Mutation-ID semantic mismatch | Replay same account/key with changed closed arguments | No effect; stable quoted error `mutation_identity_reused`. [VERIFIED: 01-CONTEXT.md D-32]
| Disconnect before server accepts | Transport gate before controller/transaction | Draft/identity preserved; lookup reports unknown/not found without claiming failure. |
| Response lost after commit | Drop response after transaction commit | Browser shows checking, looks up/retries same identity, reconciles exactly once. |
| Semantic conflict | Interleave revisions around row-lock acquisition | Persisted affected-field conflict; original replay is unchanged; resolution uses new identity. |
| Auth expiry before submission | Expire session before command reaches application | Draft preserved, reauth required, no receipt/effect. |
| Auth expiry after unknown delivery | Commit, expire session, drop response | Reauth preserves identity, then lookup/retry recovers stored result. |
| Undo expiry/staleness/race | Inject clock and concurrent follow-up command | Typed no-change result; no inverse when expired/stale; one consumer wins. |
| Today reorder collision | Competing expected scoped order revisions | One order wins; loser receives explicit stale/conflict; no duplicate positions. |
| Cursor invalidation | Change relevant view/order revision after page 1 | Explicit stale cursor and refresh action; no offset-style duplication/skipping claim. |
| Telemetry emission | Install capture handler around every error/command | No task content, prompt, credential, raw token, or arbitrary task/activity/mutation IDs. [VERIFIED: AGENTS.md:112-112; 01-CONTEXT.md D-61]

Use injected clocks, seeded property tests, explicit process barriers, and captured outbound telemetry. Do not simulate concurrency by sequential calls or response loss only in a mocked frontend. [ASSUMED]

### Browser/UI Evidence Matrix

The approved UI contract requires representative visual evidence at 320, 768, 1024, and 1440px; both light and dark themes; reduced motion; forced colors; populated, empty, long-content, conflict, auth-expired, and uncertain-delivery states. [VERIFIED: 01-UI-SPEC.md:302-320]

- Vitest/Testing Library: command state reducer/orchestrator, draft retention, validation focus, dirty navigation, conflict choices, live-region copy, and untrusted-text rendering.
- Playwright against real Phoenix/PostgreSQL: full daily loop, refresh/deep link, session expiry/reauth, response-loss recovery, focus after row removal/load-more, keyboard-only capture/edit, and account-scoping tamper attempts.
- Playwright screenshot assertions: registered wide/narrow routes, light/dark, reduced motion and forced colors, with fonts/animations/data/clock pinned for determinism. Playwright snapshot output is platform-specific, so CI must use one pinned browser/OS image. [CITED: https://playwright.dev/docs/test-snapshots]
- Axe: automated detectable WCAG violations on every important state; manual keyboard, zoom/reflow, screen-reader announcement, authentication, and cognitive-language review remain required. [CITED: https://playwright.dev/docs/accessibility-testing]

### Sampling Rate

- **Per task commit:** the narrow ExUnit file/directory or Vitest file for the changed behavior, targeted below 30 seconds. [ASSUMED]
- **Per wave merge:** complete `mix test`, web Vitest, contract drift, and Playwright `@smoke` against PostgreSQL 18.6. [ASSUMED]
- **Phase gate:** full server/web/contract/E2E suites green; visual/a11y evidence reviewed; package/security checkpoints resolved; no completion or data-safety claims from unit tests alone. [VERIFIED: AGENTS.md:113-113]

### Wave 0 Gaps

- [ ] Scaffold `apps/server` in place with no nested Git and pin Elixir 1.20.2 / OTP 29.0.5 / Phoenix 1.8.13 / PostgreSQL 18.6.
- [ ] Add ExUnit support cases, Ecto SQL Sandbox, StreamData, deterministic clock/ID generators, and independent-connection concurrency helpers.
- [ ] Add `packages/contracts` OpenAPI 3.1 source, JSON schemas/golden vectors, TypeScript generation, and drift check.
- [ ] Add Vitest, Testing Library, jsdom, and accessible interaction helpers after required SUS checkpoints.
- [ ] Add Playwright, real server/DB webServer orchestration, deterministic seeded data, response-drop/fault control, trace/screenshot/axe evidence.
- [ ] Add architecture dependency tests (`mix xref` plus source-level forbidden dependency assertions) and telemetry redaction tests.
- [ ] Add root scripts that coordinate native Mix/pnpm commands without Nx/Turborepo.

## Security Domain

Security enforcement is enabled at ASVS Level 1 in project config. The project should use the current ASVS 5.0 chapter numbering rather than the older V2-auth/V3-session shorthand in legacy templates. [VERIFIED: .planning/config.json:47-49] [CITED: https://owasp.org/www-project-application-security-verification-standard/]

### Applicable ASVS 5.0 Categories

| ASVS 5.0 category | Applies | Standard control for this phase |
|---|---|---|
| V1 Encoding and Sanitization | yes | React text interpolation; no stored HTML; property/E2E tests with hostile content. [VERIFIED: 01-CONTEXT.md D-58]
| V2 Validation and Business Logic | yes | Closed command schemas, server-side invariants, account scope, expected revisions, idempotency fingerprints, bounded fields. |
| V3 Web Frontend Security | yes | No credential in Web Storage, CSP/security headers, safe untrusted rendering, guarded navigation without leaking data. |
| V4 API and Web Service | yes | Same-origin JSON, strict content type/size, OpenAPI 3.1, RFC 9457, CSRF/origin/host verification, no raw patch endpoint. |
| V5 File Handling | no | No uploads/attachments in Phase 1. [VERIFIED: .planning/PROJECT.md exclusions; 01-CONTEXT.md Deferred Ideas]
| V6 Authentication | yes | Argon2id, generic responses, long/paste/autofill-friendly password, calibrated work factor, closed setup/recovery, recent-auth for sensitive changes. [VERIFIED: 01-CONTEXT.md D-45..D-49,D-53]
| V7 Session Management | yes | Random opaque hashed DB sessions; Secure/HttpOnly/host-only/SameSite=Lax cookie; renewal, idle/absolute expiry, inventory and revocation. [VERIFIED: 01-CONTEXT.md D-48..D-52]
| V8 Authorization | yes | Derive account/principal server-side; scope every query/receipt/handle/cursor; handle/ID possession is never authorization. [VERIFIED: 01-CONTEXT.md D-31,D-41,D-42]
| V9 Self-contained Tokens | limited/no | Browser JWTs are rejected; opaque setup/recovery/session/undo values are hash-stored. [VERIFIED: 01-CONTEXT.md D-40,D-45,D-47,D-48,D-55]
| V10 OAuth and OIDC | seam only | Preserve future authorization-code + PKCE/device grant boundary; no implementation in Phase 1. [VERIFIED: 01-CONTEXT.md D-54 and Deferred Ideas]
| V11 Cryptography | yes | Standard CSPRNG UUID/token APIs, Argon2id, standard hashes/HMAC where required, TLS at deployment; never custom crypto. |
| V12 Secure Communication | yes | HTTPS, Secure cookies, trusted proxy/host configuration, no public PostgreSQL. [VERIFIED: AGENTS.md:111-111]
| V13 Configuration | yes | No secrets in source/CLI/logs, production-only cookie/host settings, disable setup after consumption, no test fault endpoints in production. |
| V14 Data Protection | yes | Minimize session/source activity data; no raw IP/fingerprint by default; keep content/identifiers out of telemetry. [VERIFIED: 01-CONTEXT.md D-50,D-58,D-61]
| V15 Secure Coding and Architecture | yes | Inward dependencies, explicit boundary mapping, database constraints, least privilege, dependency legitimacy gates. [VERIFIED: AGENTS.md:13-22,107-117]
| V16 Security Logging and Error Handling | yes | Generic auth responses, privacy-safe security audit, stable Problems, bounded structured diagnostics with negative leakage tests. [VERIFIED: 01-CONTEXT.md D-38,D-53,D-61]
| V17 WebRTC | no | No WebRTC capability in phase scope. [VERIFIED: 01-CONTEXT.md Phase Boundary]

### Known Threat Patterns

| Pattern | STRIDE | Standard mitigation |
|---|---|---|
| Setup race or first-request account takeover | Spoofing / elevation | Operator-generated hashed short-lived single-use setup token; singleton DB constraint; account creation and setup consumption in one transaction. [VERIFIED: 01-CONTEXT.md D-45]
| Credential stuffing/password guessing | Spoofing / denial | Argon2id, generic responses, independent source/account Hammer buckets, bounded backoff, privacy-safe audit; no attacker-triggered permanent lockout. [VERIFIED: 01-CONTEXT.md D-46,D-53]
| Session fixation/theft | Spoofing | Rotate session and CSRF after auth, hash stored token, Secure/HttpOnly/host-only/Lax cookie, idle/absolute expiry, revocation. [VERIFIED: 01-CONTEXT.md D-48..D-52]
| CSRF or forged host/origin | Tampering | Plug CSRF token header plus origin/host validation for every cookie-authenticated mutation. [VERIFIED: 01-CONTEXT.md D-48] [CITED: https://hexdocs.pm/plug/Plug.CSRFProtection.html]
| Cross-account ID/receipt/undo/cursor tampering | Elevation / information disclosure | Derive account from session and include account predicate/constraint in every lookup; never authorize by opaque ID/handle possession. [VERIFIED: 01-CONTEXT.md D-31,D-41,D-42]
| Duplicate/reordered network delivery | Tampering | Account-scoped unique receipt, semantic fingerprint, expected revision, original-result replay, explicit conflict. [VERIFIED: 01-CONTEXT.md D-31..D-38]
| SQL injection | Tampering | Ecto parameterized queries/changesets; never interpolate user values into SQL. [CITED: https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.html]
| Stored XSS via title/note/activity | Tampering / disclosure | Store canonical text only, no HTML, render via React text nodes, CSP, hostile-content tests. [VERIFIED: 01-CONTEXT.md D-58]
| Undo token disclosure/replay | Tampering / elevation | High-entropy opaque value, hash at rest, account/authorization checks, expiry, exact revision, one-shot atomic consumption, never display handle. [VERIFIED: 01-CONTEXT.md D-40..D-42,D-59]
| Sensitive telemetry/log leakage | Information disclosure | Explicit field allow-list/redaction and negative capture tests; exclude content, tokens, prompts, and arbitrary identifiers. [VERIFIED: AGENTS.md:112-112; 01-CONTEXT.md D-61]
| Expensive unbounded inputs/list queries | Denial | Contract/body/field limits, keyset pagination, rate limits, statement/query indexes and timeouts; limits must be decided/measured. [ASSUMED]
| Test-only fault controls exposed in production | Elevation / denial | Compile/environment gate, bind only test server, random per-run control credential, production route-absence test. [ASSUMED]

### Authentication/Session Planning Checklist

- Generate and inspect Phoenix auth code; remove public registration/email dependencies and retain an upstream-security-diff process. [CITED: https://phoenix.hexdocs.pm/mix_phx_gen_auth.html]
- Benchmark Argon2id on the actual reference VM and choose bounded password length before locking parameters; OWASP recommends Argon2id and emphasizes tuning work factor to deployment hardware. [CITED: https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html]
- Store raw setup/recovery/session/undo secrets only in the delivery channel; persist keyed/cryptographic hashes and constant-time compare. [ASSUMED]
- Renew the Phoenix session and delete the prior CSRF token after authentication; fence in-flight browser commands and clear account-scoped query/command memory on logout. [CITED: https://hexdocs.pm/plug/Plug.CSRFProtection.html] [VERIFIED: 01-CONTEXT.md D-52]
- Use database-enforced singleton account/setup state and unique account-scoped keys, then test races with independent connections. [VERIFIED: 01-CONTEXT.md D-45]
- Coarsen recent-session activity and do not store raw IP/user-agent fingerprint as trusted identity. [VERIFIED: 01-CONTEXT.md D-50]

## Sources

### Primary (HIGH confidence project/source-of-truth)

- `01-CONTEXT.md` — D-01..D-63, discretion, deferred scope, and trust scenarios.
- `01-UI-SPEC.md` — approved responsive, component, copy, state, accessibility, theme, and evidence contracts.
- `AGENTS.md`, `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/STATE.md` — project constraints, requirement text, phase boundary, and workflow state.
- `docs/architecture/REPOSITORY.md`, `docs/brand/BRAND-SEED.md` — repository dependency direction and interaction/brand rules.
- [Phoenix 1.8 auth generator](https://hexdocs.pm/phoenix/Mix.Tasks.Phx.Gen.Auth.html) — controller/scopes/session generator switches and ownership.
- [Plug CSRF Protection](https://hexdocs.pm/plug/Plug.CSRFProtection.html) — session prerequisites, header token, auth rotation.
- [Ecto.Multi](https://hexdocs.pm/ecto/Ecto.Multi.html), [Ecto SQL Sandbox](https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.Sandbox.html) — transactions and database test isolation.
- [PostgreSQL version policy](https://www.postgresql.org/support/versioning/), [transaction isolation](https://www.postgresql.org/docs/current/transaction-iso.html), and [constraints](https://www.postgresql.org/docs/current/ddl-constraints.html) — current release, concurrency, database arbitration.
- [Elixir Calendar](https://hexdocs.pm/elixir/Calendar.html), [Tzdata time-zone database](https://hexdocs.pm/tzdata/Tzdata.TimeZoneDatabase.html) — account-timezone conversion.
- [OWASP ASVS](https://owasp.org/www-project-application-security-verification-standard/), [Authentication](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html), [Session Management](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html), [CSRF](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html), and [Password Storage](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html) — security controls.
- [React versions](https://react.dev/versions), [React Router navigation blocking](https://reactrouter.com/how-to/navigation-blocking), [TanStack Query retries](https://tanstack.com/query/latest/docs/framework/react/guides/query-retries), [Vitest](https://vitest.dev/guide/), [Playwright webServer](https://playwright.dev/docs/test-webserver), [Playwright accessibility](https://playwright.dev/docs/accessibility-testing), [Testing Library](https://testing-library.com/docs/react-testing-library/intro/) — current browser/test patterns.
- [OpenAPI specification](https://spec.openapis.org/oas/latest.html), [openapi-typescript](https://openapi-ts.dev/introduction), [RFC 9457](https://www.rfc-editor.org/rfc/rfc9457.html) — transport contracts and errors.
- [WCAG 2.2](https://www.w3.org/TR/WCAG22/) — accessibility baseline.

### Secondary (MEDIUM confidence)

- Official npm/Hex registry metadata retrieved 2026-08-30 — current versions, publish dates, download/repository/postinstall signals.
- `.planning/knowledge/snapshots/2026-08-28-platform-and-architecture.md` and `2026-08-28-mcp-agent-safety-and-evals.md` — retained evidence used only where current decisions did not supersede it.

### Tertiary (LOW confidence)

- None used as authority. All `[ASSUMED]` recommendations are enumerated in the Assumptions Log or Open Questions.

## Metadata

**Confidence breakdown:**

- Standard stack: **MEDIUM** — versions and patterns were checked against official docs/registries on 2026-08-30; several npm patch releases are new enough to trigger human verification.
- Architecture: **HIGH** — the command boundaries, semantics, and UI contracts are locked by D-01..D-63 and repository instructions; only internal names/rank/deployment wiring remain discretionary.
- Transactions/concurrency: **HIGH** for required behavior and PostgreSQL/Ecto primitives; **MEDIUM** for the proposed concrete schema/locking implementation until concurrency spikes run.
- Authentication/security: **HIGH** for required policy; **MEDIUM** for exact Argon2id/rate-limit values because hardware measurement is intentionally outstanding.
- Validation: **HIGH** for required behavior/layer mapping; **MEDIUM** for commands/paths until Wave 0 creates the scaffold and executes them.
- UI/accessibility: **HIGH** for the approved UI-SPEC contract; **MEDIUM** for final visual behavior until browser evidence exists.

**Research date:** 2026-08-30

**Valid until:** 2026-09-06 for fast-moving package versions and security advisories; 2026-09-29 for stable architectural guidance. Re-run registry/security checks at installation.
