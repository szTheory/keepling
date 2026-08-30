# Phase 1: One Trustworthy Task - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-30
**Phase:** 1-One Trustworthy Task
**Areas discussed:** Repository boundary; Temporal rules; Capture and editing; Undo, conflicts, and recovery; Account and sessions; Task organization and Inbox clearing; List ordering and lifecycle visibility; User-visible activity and trust

---

## Repository boundary

| Option | Description | Selected |
|--------|-------------|----------|
| One coordinating monorepo | Root Git and `.planning/` own apps, packages, infrastructure, contracts, and evidence; extract only after an independently versioned lifecycle is proven | ✓ |
| Parent workspace plus child repositories | Independent nested repositories coordinated through a manifest and commit lock | |
| Git submodules | Independent repositories linked through Git submodules | |

**User's choice:** Preserve the locked monorepo architecture and supersede the interrupted checkpoint's child-repository deviation.
**Notes:** This reconciles the checkpoint with PROJECT.md, decision D-010, REPOSITORY.md, and the active coordination contract.

---

## Temporal rules

| Option | Description | Selected |
|--------|-------------|----------|
| `planned_on` plus `deadline_on` civil dates | Separate deliberate planning from deadline semantics; lifecycle/audit times remain UTC instants | ✓ |
| Add an availability/start date | Represent a third temporal concept in Phase 1 | |
| Zoned task date-times | Use exact instants and zones for ordinary planning/deadlines | |

**User's choice:** Use nullable planned and deadline civil dates, one canonical account IANA timezone, derived Today membership, carried-forward unfinished tasks, and an explicit non-blocking warning when planning occurs after a deadline.
**Notes:** Availability dates, exact times, reminders, recurrence, Someday, and This Evening were deferred.

---

## Capture and editing

| Option | Description | Selected |
|--------|-------------|----------|
| Wide list/detail plus routed narrow editor | Things-like daily workspace with one canonical editor at different widths | ✓ |
| Inline expanding rows | Edit directly inside task rows | |
| Modal or separate-page editing everywhere | Isolate all editing from list context | |

| Save behavior | Description | Selected |
|---------------|-------------|----------|
| Explicit Save/Cancel | Protect dirty navigation and retain drafts until exact acknowledgement | ✓ |
| Continuous autosave | Submit changes while typing | |
| Save on blur/navigation | Implicitly commit when focus or route changes | |

**User's choice:** Quick capture defaults visibly to Inbox with optional Today; full editing uses explicit Save/Cancel, dirty-navigation protection, native keyboard semantics, and draft preservation through validation, reauthentication, and uncertain outcomes.
**Notes:** Global desktop shortcuts and durable unsubmitted browser-draft recovery were deferred.

---

## Undo, conflicts, and recovery

| Option | Description | Selected |
|--------|-------------|----------|
| Semantic compensation handle plus durable Trash | One-shot server-side undo, exact-revision validation, typed inverse, persistent recovery action | ✓ |
| Multi-level distributed undo/redo stack | Repeated global undo/redo across devices and actors | |
| Snapshot rollback | Restore a stored pre-mutation record image | |

| Concurrency option | Description | Selected |
|--------------------|-------------|----------|
| Narrow semantic three-way merge | Merge invariant-safe disjoint fields and persist explicit overlapping/lifecycle conflicts | ✓ |
| Whole-task compare-and-swap | Reject every mutation after any aggregate revision mismatch | |
| Per-field revisions | Track independent versions for every field | |

**User's choice:** Follow the researched recommendation: 24-hour one-shot semantic undo handles, no Phase 1 hard delete, account-scoped mutation identity with stable stored result, narrow semantic three-way merge, exact-revision recovery boundaries, persistent conflict UI, and same-identity query/retry for uncertain delivery.
**Notes:** Rejected last-write-wins, timestamps as revisions, generic JSON Patch, client merge logic, editor leases, CRDTs, full event sourcing, and client-only timed undo.

---

## Account and session behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Operator-gated password baseline | Closed bootstrap, Argon2id, no SMTP dependency, additive passkeys later | ✓ |
| Magic-link-first | Require reliable email delivery for ordinary authentication and recovery | |
| Passkey-first | Require WebAuthn and operator recovery in Phase 1 | |

| Session option | Description | Selected |
|----------------|-------------|----------|
| Stateful revocable cookie sessions | Opaque HttpOnly cookie, hashed server record, CSRF protection, individual revocation | ✓ |
| Stateless browser JWT | Browser stores and presents a self-contained bearer token | |
| Shared permanent credential | Reuse one long-lived secret across browser/native/API clients | |

**User's choice:** Follow the researched recommendation: sole-account operator bootstrap, password-manager-friendly Argon2id authentication, stateful revocable browser sessions, draft-preserving reauthentication, dirty-work-aware logout, privacy-safe session visibility, and an extensible future grant seam.
**Notes:** Initial configurable defaults are 30-day idle, 180-day absolute, and 15-minute recent-auth for sensitive account/session changes. Mandatory magic links, passkey-only bootstrap, browser-storage bearer credentials, fingerprint trust, and shared forever-tokens were rejected.

---

## Task organization and Inbox clearing

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit Inbox membership | Capture marks unclarified state; only clarify/return commands change it | ✓ |
| Inbox as a system project | Every task lives in exactly one location and Inbox is the default container | |
| Metadata-triggered cleanup | Project/date/tag edits automatically remove tasks from Inbox | |
| Configurable cleanup policy | Account settings decide which edits clear Inbox | |

**User's choice:** Follow the researched recommendation: explicit Inbox state, zero-or-one project, zero-or-many flat tags, minimal idempotent organization lifecycle commands, stable ID-addressed references, preserved archived assignments, and no hidden cleanup side effects.
**Notes:** Areas, headings, checklists, nesting, project completion, organization hard deletion, cascading detach, and name-addressed writes were deferred or rejected.

---

## List ordering and lifecycle visibility

| Option | Description | Selected |
|--------|-------------|----------|
| Calm hybrid | Deterministic Inbox/Upcoming/archives with manual order only within Today sections | ✓ |
| Manual order everywhere | Persist user-defined positions for all views | |
| Fully automatic ordering | Let deterministic rules choose all ordering, including Today | |
| Configurable policies | Expose multiple sort/group/display preferences | |

**User's choice:** Follow the researched recommendation: newest-first Inbox, manually ordered Overdue/Today sections, read-only date-grouped Upcoming, Completed today shelf plus Completed archive, dedicated Trash, keyset pagination, explicit Load more, stable focus, honest loading/refresh states, and Reduce Motion alternatives.
**Notes:** Manual ordering outside Today, offset pagination, infinite scroll, instant completion disappearance, silent stale replacement, dashboards/calendars, and CRDT-like ordering were rejected or deferred.

---

## User-visible activity and trust

| Option | Description | Selected |
|--------|-------------|----------|
| Typed per-task activity facts | Semantic accepted actions with trusted attribution, deltas, revisions, and recovery linkage | ✓ |
| Global mutation ledger UI | One account chronology for accepted and failed commands | |
| Full snapshot per revision | Persist complete task state after every change | |

**User's choice:** Follow the researched recommendation: append typed per-task activity atomically with accepted commands; show compact human summaries and exact timestamps; keep technical identifiers behind disclosure; and separate activity, conflicts, receipts, sync, security audit, and telemetry.
**Notes:** Later MCP actors reuse the envelope without prompts or chain of thought. Global reporting, failed-agent review, WORM claims, and hard-purge policy were deferred.

---

## the agent's Discretion

- Current stable framework/runtime versions after official-documentation verification.
- Exact opaque identifier encoding and internal table/index/cursor/rank representations.
- Calibrated Argon2id and rate-limit parameters.
- Compact activity copy and detailed conflict-surface presentation within the locked trust/accessibility behavior.

## Deferred Ideas

- Durable browser-offline support, multi-level undo/redo, configurable list policies, areas/headings/checklists/nesting, reminders/recurrence, passkeys, native PKCE grant implementation, global Recent Changes, MCP-specific history presentation, calendar/dashboard views, hard-delete retention, and CRDT/per-field revision machinery.
