# Phase 1: One Trustworthy Task - Context

**Gathered:** 2026-08-30
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver one trustworthy end-to-end browser slice through React, Phoenix, and PostgreSQL. A single personal account can capture and clarify tasks; edit title, notes, project, tags, and supported dates; use Inbox, Today, Upcoming, Completed, and Trash; complete, reopen, trash, restore, and undo; inspect accepted activity; and recover honestly from validation, stale state, conflicts, expired authentication, retries, and uncertain delivery. The browser is online-first. This phase establishes semantic commands and contracts that later Electron, iPhone, synchronization, and MCP adapters must reuse without bypassing domain invariants.

</domain>

<decisions>
## Implementation Decisions

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

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.** Dated snapshots are evidence, not authority; current lifecycle documents and decision dispositions win on conflict.

### Product scope and requirements

- `.planning/PROJECT.md` — current product truth, constraints, exclusions, and core trust value.
- `.planning/REQUIREMENTS.md` — Phase 1 requirements GTD-01..07, SRV-01..03, WEB-01..02, and QUAL-01.
- `.planning/ROADMAP.md` — Phase 1 boundary, goal, UI hint, and success criteria.
- `.planning/STATE.md` — current workflow position and retained open decisions.

### Architecture and decision authority

- `docs/architecture/REPOSITORY.md` — monorepo ownership, creation timing, dependency direction, and Git rules.
- `.planning/knowledge/DECISIONS.md` — active consequential decisions, especially D-004, D-006..D-008, and D-010.
- `.planning/knowledge/OPEN-QUESTIONS.md` — phase-owned open questions, especially OQ-001, OQ-002, and OQ-006.

### Product and interaction character

- `docs/brand/BRAND-SEED.md` — calm, honest state language; platform-native UI; accessibility and Reduce Motion expectations.

### Retained architecture evidence

- `.planning/knowledge/snapshots/2026-08-28-platform-and-architecture.md` — server authority, mutation/outbox envelope, conflict semantics, test layers, and phase evidence. Evidence only where not superseded.
- `.planning/knowledge/snapshots/2026-08-28-mcp-agent-safety-and-evals.md` — bounded undo, expected revisions, actor/audit separation, and future MCP safety constraints. Evidence only where not superseded.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- No runtime framework or reusable application component exists yet. Phase 1 intentionally owns the first server and web scaffolds.
- `apps/server/README.md` and `apps/web/README.md` define the planned ownership boundaries.
- `packages/README.md` limits shared packages to contracts, vectors, tokens, generated transport, and presentation with proven multi-consumer value.

### Established Patterns

- Root planning and architecture documents are the current source of truth.
- Runtime directories are scaffolded only when their vertical phase begins.
- Representations remain separate: domain/application values, Ecto schemas, wire DTOs, and React view state do not collapse into one shared model.

### Integration Points

- `apps/server` will own domain/application commands, PostgreSQL persistence, authentication/authorization, HTTP adapters, migrations, and semantic mutation results.
- `apps/web` will own browser bootstrap, routing, online query/mutation adapters, dirty-draft handling, and user-visible state recovery.
- Initial checked-in contracts and storage-neutral golden vectors belong under `packages/` only where they establish cross-runtime truth.

</code_context>

<specifics>
## Specific Ideas

- Things is the interaction benchmark when alternatives are otherwise viable, but Keepling deliberately deviates for explicit trust state, browser conventions, accessibility, cross-platform consistency, and safe automation rather than copying Things' visual identity.
- Routine success is quiet. Error and recovery copy names the actual state and next action: saved, checking whether saved, authentication required, stale, conflicted, restored, or unrecoverable.
- A user should always be able to tell why a task is in Today, whether a submitted change was acknowledged, what accepted action occurred, and what recovery remains available.
- Phase 1 should prove long and adversarial command sequences, duplicate delivery, before/after-commit response loss, stale edits, conflict resolution, cross-account tampering, expiry boundaries, reauthentication, focus restoration, and telemetry redaction.

</specifics>

<deferred>
## Deferred Ideas

- Durable browser-offline mutation/outbox behavior; owned by Electron/iPhone and the synchronization phase unless later browser dogfooding proves a need.
- Multi-level undo/redo, hard-delete retention, configurable list policies, manual ordering outside Today, areas, headings, checklists, nested organization, reminders, recurrence, Someday, and This Evening.
- Passkeys, native authorization-code/PKCE grant implementation, and platform credential storage; retain only the compatible seam in Phase 1.
- Global Recent Changes, MCP-specific history presentation, failed-agent-attempt review, bulk previews, and cryptographic audit guarantees; later phases own these capabilities.
- Calendar/dashboard views, full manual spatial ordering, and CRDT/per-field revision machinery pending measured dogfood need.

</deferred>

---

*Phase: 1-One Trustworthy Task*
*Context gathered: 2026-08-30*
