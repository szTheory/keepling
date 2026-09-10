# Phase 5: Safe Agent Access - Context

**Gathered:** 2026-09-10
**Status:** Ready for planning

<domain>
## Phase Boundary

External AI tools reach Keepling through a **safe adapter over the existing application
commands** — never around them. An MCP client can read bounded task views and can capture,
update, complete, and reopen a single task, under least-privilege authorization, closed
schemas, idempotency, expected revisions, ambiguity refusal, bound preview/commit for
anything bulk or destructive, and user-visible history with a working undo path.

This phase also **completes SRV-02**. Phases 1, 3, and 4 each proved one adapter and each
explicitly deferred completion to the Phase 5 cross-adapter proof.

**In scope:** the MCP adapter, the agent authorization/scope model, the server-side `search`
and project read surfaces MCP-01 names, the agent actor in existing activity/history, the
agent-grant management surface, the preview/commit primitive, and the five-lane evidence
model plus the cross-adapter proof.

**Out of scope:** new client applications, collaboration or multi-account access (D-003),
agent-initiated scheduled or recurring work, and any relaxation of an existing domain
invariant for an agent's convenience.

</domain>

<decisions>
## Implementation Decisions

> **Discussion mode:** `--auto` (advisor calibration `minimal_decisive`, per
> `~/.claude/gsd-core/USER-PROFILE.md`). Every decision below was auto-selected as the
> researched recommended option and logged in `05-DISCUSSION-LOG.md` for audit. The
> owner's standing instruction is to research deeply, decide once, and proceed — bouncing
> low/medium-stakes choices back is explicitly unwanted. Genuinely security-sensitive
> decisions are marked **one-way** below so `gsd-planner` raises them as
> `checkpoint:decision` before the task that implements them.

### Adapter placement and transport

- **D-01:** The MCP server is an **in-process Elixir adapter inside `apps/server`**, a
  sibling of `KeeplingWeb`'s controllers, calling the same `Keepling.Application.Commands`,
  `Keepling.Application.TaskViews`, `Keepling.Application.Activity`, and
  `Keepling.Application.Undo` functions the HTTP controllers call. No sidecar process, no
  second deployment artifact, no extra network hop. — **Reversibility:** costly — the
  cross-adapter proof (D-26), the authorization pipeline, and the deployment story all
  bind to this placement; moving to a sidecar later re-does all three. *Rationale:* a Node
  or Python MCP sidecar speaking to the public HTTP API would prove **the API**, not the
  semantic boundary, and would stand up a second authorization implementation to keep in
  sync. SRV-02 says "the same domain invariants through web, desktop, iPhone, API, **and
  MCP** entry points" — that claim is only checkable when MCP enters where the others do.
  It also directly serves D-008 and Phase 1 D-02: domain and application modules must not
  depend on MCP, so MCP depends inward on them.
- **D-02:** Research evaluates a maintained Elixir MCP library (e.g. `hermes_mcp`) against
  hand-rolling the JSON-RPC/MCP framing. **What is locked regardless of that outcome:** the
  chosen layer owns transport framing and protocol shape only. It must never own
  authorization, scope enforcement, schema validation, command dispatch, or error mapping —
  those stay in Keepling code and stay covered by Keepling tests.
- **D-03:** Transport is **Streamable HTTP** mounted at a versioned path through the
  existing Phoenix router with its own pipeline, so agent traffic inherits the existing
  `hammer` rate limiting and the `security_audit` path. **No stdio transport in Phase 5** —
  a stdio bridge needs a separately distributed and signed binary and would sit outside
  server-side rate limiting and audit.
- **D-04:** Pin one MCP protocol revision explicitly and treat it exactly like Phase 2's
  protocol trains (Phase 2 D-26/D-29): declared, tested, and changed deliberately. The protocol
  conformance lane (D-25) tests against the pinned revision, not against "whatever the
  client sent".

### Agent authorization and scopes

- **D-05:** An agent is a **first-class client class in the existing device-grant model** —
  its own `client_id`, its own installation identity, its own refresh family with the same
  rotation and replay detection, independently revocable, and listed alongside Electron and
  iPhone in the device-grant surface, visibly labelled as an AI agent. An agent never
  reuses, borrows, or impersonates an Electron or iPhone grant. — **Reversibility:** costly
  — grants are durable rows with a published revocation surface; reclassifying them later
  is a migration plus a client-visible change.
- **D-06:** Introduce a **small closed scope vocabulary**, minimally `tasks.read`,
  `tasks.write`, `tasks.bulk`. Absent scope means denied — there is no implicit grant and no
  wildcard. Scope is stored on the grant, checked in the MCP adapter before dispatch, **and
  re-checked at the application boundary**, so a bug in the adapter cannot widen authority
  on its own. Permanently outside any agent scope: account credentials, session and
  device-grant administration, recovery, export, and permanent deletion. —
  **Reversibility:** one-way — scope strings become a published authorization contract that
  hosts persist in stored grants; renaming or re-scoping them later silently changes what
  an existing grant permits.
- **D-07:** Agent authorization reuses the **external user agent + authorization code +
  S256 PKCE + exact redirect binding** seam already locked in Phase 1 D-22 and Phase 2 D-22.
  The consent screen names the exact scopes and states plainly that the requester is an AI
  agent. **No client-credentials grant and no long-lived static API key in Phase 5** — both
  produce a bearer secret with no user-visible consent and no natural revocation moment. —
  **Reversibility:** one-way — issuing a static key creates credentials in the wild that
  outlive the decision to stop issuing them.

### Read surface (MCP-01)

- **D-08:** Reads are exposed as **MCP resources** wherever the thing is addressable, with a
  parameterized `search` tool for queries that take arguments. Bounded and paginated with the
  existing opaque account-bound keyset cursors (Phase 1 D-26) — explicit paging, never
  unbounded enumeration, and never raw database access.
- **D-09:** **`search` does not exist server-side today** (there is no search endpoint in
  `KeeplingWeb`), and MCP-01 requires it. Build it as an **application-level bounded query
  shared with the HTTP API**, not as an MCP-only code path. The same applies to the project
  read view. Giving MCP a capability the other adapters lack would falsify SRV-02's "same
  invariants" claim in the same commit that proves it.
- **D-10:** Resource payloads are **redacted by construction**: stable opaque identities and
  user-visible fields only. No internal identifiers, no other accounts, no audit internals,
  no server implementation detail. This mirrors the existing `redaction.json` vector
  discipline.

### Write surface and closed schemas (MCP-02)

- **D-11:** Expose a **small closed tool set matching MCP-02 exactly** — capture, update,
  complete, reopen — plus the preview/commit pair from D-16. Deliberately **not** a 1:1
  mirror of the twelve `/commands/*` endpoints: a task-shaped tool surface is what MCP hosts
  use well, and every additional tool is additional authorization surface.
- **D-12:** Tool input schemas are **closed** (`additionalProperties: false`) and
  **generated from `packages/contracts`**, so a contract change breaks the MCP adapter in CI
  rather than at runtime in front of a model. This extends the Phase 4 D-13/D-14 discipline
  (normalize the contract, then generate; round-trip every payload) to a fourth consumer.
- **D-13:** Every agent write carries a **client-generated mutation identity** and, except
  capture, an **expected revision** — identical to Phase 1 D-31/D-32 and SRV-03. Agents
  receive no relaxation of idempotency or concurrency control. Replaying a mutation identity
  returns the original stored result exactly as it does for a human client.
- **D-14:** Errors are **stable, closed, and model-correctable**: a machine-readable code
  plus a short fixed human string naming what was wrong and what to do next. No stack
  traces, no internal detail, and no free-form prose that varies between runs — a model
  cannot learn to correct against a moving target, and a varying string cannot be asserted
  in a deterministic lane.

### Ambiguity (MCP-03)

- **D-15:** Writes address tasks by **stable opaque identity only**. A title, a description,
  or any natural-language phrase is never a write address. This is Phase 1 D-18 ("references
  use stable opaque IDs rather than mutable names") applied to the surface where the caller
  is a language model and the failure mode is silently editing the wrong task. —
  **Reversibility:** one-way — name-addressed writes, once published, are what hosts build
  against, and withdrawing them breaks every integration that adopted them.
- **D-16:** An under-determined target returns **`ambiguous_match` with the bounded
  candidate set** — each candidate carrying its identity and enough fields to disambiguate —
  and performs **zero mutations**. Zero-candidate and too-many-candidates are distinct
  closed errors, not the same error with a different count.

### Preview and commit (MCP-05)

- **D-17:** Bulk and destructive changes are **two-step**. Preview returns an opaque,
  account-bound, expiring `preview_token` that binds: the exact target identity set, each
  target's expected revision, the command and its arguments, and the server instance plus
  synchronization epoch (reusing the Phase 2 D-10 cursor-binding discipline). Commit accepts
  **only** the token and a mutation identity — never a re-sent target list, which would let
  the committed set differ from the previewed one.
- **D-18:** Any drift between preview and commit — a target changed, disappeared, or the set
  no longer matches — **fails atomically as `preview_stale` with zero partial writes**.
  Partial success is not a representable outcome of a commit. — **Reversibility:** one-way —
  this is the guarantee the requirement is written to buy; a partial-write path added later
  invalidates every prior claim.
- **D-19:** "Destructive" is defined **explicitly and closed**: trash, restore, undo, and
  any command affecting more than one task. Complete and reopen of a single task are not
  destructive. A closed list is testable; "high-impact" as a judgment call is not.

### Visible history and privacy (MCP-04)

- **D-20:** Extend the **existing** activity actor — `%{label, principal, type}` in
  `Keepling.Application.Activity` — with an agent actor type naming the grant. Do not build a
  parallel agent-audit surface; a second history is a second thing that can disagree with
  the first.
- **D-21:** Keepling **persists no model reasoning, no prompt text, no tool-call rationale,
  and no conversation content** — only the closed command and the arguments actually
  executed. This is a storage-level guarantee (there is no column for it), not a redaction
  filter applied on read. — **Reversibility:** one-way — a schema that can hold chain of
  thought will eventually hold it, and the requirement forbids exposing it.
- **D-22:** Agent actions expose the **same GTD-07 undo handle** as human actions. An agent
  action the user can see but cannot undo does not satisfy MCP-04 and does not ship.
- **D-23:** The Phase 5 UI surface is the **existing activity/history view** plus an
  **agent-grant management view** (grant, scopes, last used, revoke). No new client
  applications.

### Adversarial posture

- **D-24:** All task content returned to a model — titles, notes, project and tag names — is
  **untrusted data**. Authorization is never influenced by content. Concretely: scope checks,
  preview binding, and ambiguity resolution read structural fields only, never free text, and
  no path exists by which text stored in a task can widen a grant, mint or alter a preview
  token, or cause a commit. — **Reversibility:** one-way — this is the security property the
  phase exists to establish; a content-influenced authorization path found later invalidates
  every claim made here.

### Evidence model and honest claims (SC5)

- **D-25:** Five named lanes: **deterministic** (unit and contract), **protocol** (MCP
  conformance against the pinned revision from D-04), **simulated-client** (a scripted MCP
  client over the real transport with real authorization), **representative-model** (a real
  model as the client), and **adversarial** (injection corpora embedded in task content).
  Carry **Phase 4's D-24 anti-vacuity contract forward verbatim**: a lane that cannot be
  genuinely exercised reports **BLOCKED**, never a silent pass; published case counts are the
  evidence and must mean what they say — skips subtracted, every bundle summed, no bundle
  silently discarded.
- **D-26:** The **representative-model** lane requires a real model credential and reports
  **BLOCKED** without one. It is scored on **final database state and forbidden side
  effects**, never on the text the model produced, so its verdict is deterministic given the
  final state. The adversarial lane is scored the same way.
- **D-27:** **SRV-02 completion — the cross-adapter proof.** One lane drives the identical
  semantic scenario set through **all five adapters** — web/API, Electron, iPhone, MCP —
  against **one server revision**, and asserts identical result codes, identical conflict
  shapes, and identical activity records. SRV-02 is not checked until this lane passes.
- **D-28:** **Correct an existing overclaim first.** `.planning/REQUIREMENTS.md` line 21
  currently marks SRV-02 `[x]` while every traceability row (lines 117, 123, 124, 125) states
  it completes only at this phase's cross-adapter proof. Uncheck it as the first act of the
  phase and restore it only when D-27's lane passes.

### Research-driven corrections (added 2026-09-10, after `05-RESEARCH.md`)

- **D-29 — Dynamic Client Registration is REQUIRED, correcting D-07's discretion note.** The
  discretion item assumed pre-registered clients would suffice for dogfood. Research falsified
  that: the two named representative hosts **disagree**. Claude Code works with a
  pre-registered `client_id`; Claude Desktop performs DCR unconditionally with **no fallback**,
  so a pre-registration-only server simply cannot be connected from it. Settling this either
  way silently drops a host. **Build a scoped DCR endpoint** — RFC 7591 registration gated
  behind the existing authenticated session, so registration only succeeds for a caller who has
  already proven ownership of the single Keepling account. That keeps both hosts working while
  refusing the open-registration abuse an unauthenticated DCR endpoint invites, and it stays
  consistent with D-003's single-account exclusivity. **This does not weaken D-07:** the
  authorization grant itself is still external-user-agent + authorization code + S256 PKCE with
  explicit scope-naming consent, and there is still no static API key and no client-credentials
  grant. — **Reversibility:** one-way — a registration endpoint, once reachable by a host, is
  part of the published authorization surface.

  **Owner answer, 2026-09-10:** Jon uses **both Claude Code and Cowork**. Claude Code needs no
  DCR; Cowork's connector-registration flow is **not reliably known** to this planning session,
  but it is app-side rather than local-config-side, so it almost certainly takes the
  Desktop-style path. **DCR stays.** The cost of keeping it is one session-gated endpoint; the
  cost of dropping it is a host Jon actually uses failing at the connector step with an
  unexplanatory error. 05-02's checkpoint verifies this empirically against the live host rather
  than against this document.
- **D-30 — Pin MCP revision `2025-06-18`, and re-check before implementation, not just now.**
  The specification moved twice during this phase's own discussion (`2025-11-25`, then a
  structurally different stateless `2026-07-28`). `2025-06-18` is mature, carries the full
  OAuth/PRM requirement set, and predates the newest churn while remaining reachable through the
  spec's backward-compatibility guarantee. Research explicitly flags that representative hosts
  may have moved by execution time — **verify against live host behaviour before writing the
  transport, not against this document.**
- **D-31 — Reject `hermes_mcp`; hand-roll the framing.** Last hex.pm release `0.14.1`
  (2025-08-14), documented example targets `2025-03-26` — a revision behind even the
  conservative pin. D-02 already required that any adopted layer own framing only; a library
  that is behind on the protocol buys nothing and costs a dependency.
- **D-32 — Three closed client-kind lists must change together.** `device_grants`' migration
  CHECK constraint, `DeviceGrant.@client_kinds`, and `DeviceGrantController.@client_ids` are each
  closed to `('electron','iphone')`. Note the landmine: `Keepling.Accounts.@client_kinds`
  *already* contains `"mcp"`, but that is the browser-session labelling vocabulary, a different
  module — it is **not** evidence that device-grant support exists. Treat it as a trap, not a
  shortcut.
- **D-33 — The MCP authorization path needs its own key allow-list.** `exact_keys/2` rejects any
  request carrying a key outside a fixed list, and RFC 8707 requires MCP clients to send
  `resource` on both the authorization and token requests — so a real client is rejected before
  authorization begins. Give the MCP path its own allow-list including `resource`, and enforce
  that its value matches this server's canonical MCP resource URI. **Do not loosen the existing
  `@authorize_keys`/`@exchange_keys`**, which would weaken validation for the two client classes
  that have no resource-indicator requirement.
- **D-34 — Preview token as a signed opaque HMAC value**, mirroring the existing cursor
  construction and `SyncFeed.authorize_namespace/2`, rather than a durable row. Research flags
  this as an assumption open to override **if an operational kill-switch for pending previews is
  wanted** — with a 15-minute-class expiry and single-account scope, the kill switch has little
  to act on, so the simpler construction wins unless the planner finds otherwise.
- **D-35 — `search` gets its own module, not a fifth `TaskViews` entry.** `TaskViews` is closed
  to `~w(inbox today upcoming completed)a` and its cursor shape assumes a named unfiltered view.
  Use native PostgreSQL `tsvector`/GIN ordered by `(accepted_at DESC, task_id)`, reusing the
  proven HMAC-signed cursor pattern — **not** rank-based pagination, which is not stable under
  a keyset cursor.

### Claude's Discretion

Auto-selected here, but genuinely open for research to settle on evidence — none of these
change the shape of the phase:

- Exact MCP protocol revision to pin, and library (`hermes_mcp`) versus hand-rolled framing.
- Exact scope string spellings and whether `tasks.bulk` is a third scope or a property of
  `tasks.write`.
- Resource URI scheme and naming.
- Default and maximum page sizes for bounded reads.
- Preview token expiry duration and storage (durable row versus signed opaque value).
- ~~Whether Dynamic Client Registration (RFC 7591) is needed for the representative hosts.~~
  **Closed by research 2026-09-10 — see D-29. Not an open question any more.**

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked project-level decisions
- `.planning/knowledge/DECISIONS.md` D-008 — "Treat MCP as a safe adapter over application
  commands. Models should not bypass deterministic authorization, invariants, confirmation,
  idempotency, audit, or recovery." This is the phase's founding constraint.
- `.planning/knowledge/DECISIONS.md` D-003 — collaboration and enterprise work management are
  excluded; agent access is single-account only.
- `.planning/knowledge/DECISIONS.md` D-004, D-007 — Phoenix/PostgreSQL modular monolith;
  explicit commands/events/change feed rather than full event sourcing.

### Requirements and roadmap
- `.planning/REQUIREMENTS.md` §"Agent and MCP access" (MCP-01..05) — the five requirements.
- `.planning/REQUIREMENTS.md` line 21 and the traceability table lines 117, 123, 124, 125,
  128 — SRV-02's incremental proof history and the overclaim named in D-28.
- `.planning/ROADMAP.md` §"Phase 5: Safe Agent Access" — goal and the five success criteria.

### Invariants inherited from earlier phases (do not re-derive, do not weaken)
- `.planning/phases/KPL-01-one-trustworthy-task/01-CONTEXT.md` D-02 (domain/application
  modules must not depend on MCP), D-18 (opaque IDs, not names), D-26 (opaque keyset
  cursors, explicit Load more), D-31/D-32 (mutation identity, expected revision, stable
  reuse semantics), D-33/D-34 (narrow semantic three-way merge; which commands may rebase).
- `.planning/phases/KPL-02-synchronization-and-replaceable-server/02-CONTEXT.md` D-10 (opaque
  values bound to server instance, account subject, epoch, protocol version — the model for
  the preview token), D-22 (external user agent + authorization code + PKCE seam), Phase 2 D-26/D-29
  (protocol trains and what constitutes a breaking change), D-15 (golden vector discipline).
- `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md` D-31 (Phoenix controllers stay thin
  over existing application commands — the MCP adapter is held to the same rule).
- `.planning/phases/KPL-04-native-iphone-daily-loop/04-CONTEXT.md` D-13/D-14 (normalize the
  contract before generating; round-trip every wire payload), D-20/D-22 (named-lane evidence
  with disclosed gaps), **D-24 (the anti-vacuity contract carried forward by D-25 above)**.

### Existing contract and code surfaces
- `packages/contracts/openapi/keepling.yaml` — the wire contract MCP tool schemas generate
  from.
- `packages/contracts/vectors/manifest.json` and the 13 vector files — especially
  `activity.json`, `undo.json`, `redaction.json`, `conflicts.json`.
- `apps/server/lib/keepling_web/router.ex` — the existing pipelines (`:authenticated`,
  `:device_grant_authenticated`, `:client_authenticated`, `:mutation`, `command_pipelines`)
  the MCP pipeline sits beside.
- `docs/architecture/REPOSITORY.md` — repository layout and module boundaries.
- `AGENTS.md` — repository working agreements.

### Deferred and already-decided elsewhere
- `.planning/ROADMAP.md` §"Candidate future milestone: Sigra identity migration" — do not
  re-litigate; Keepling keeps its own outbound authorization server for this phase.
- `.planning/ROADMAP.md` §"Backlog" Phase 999.2 — Phase 2's credentialed outer acceptance,
  blocked on live credentials; unrelated to this phase but must not be re-detected as
  incomplete work.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `apps/server/lib/keepling/application/commands.ex` — the twelve semantic commands the MCP
  tools dispatch into. The MCP adapter adds no new commands for MCP-02's four verbs.
- `apps/server/lib/keepling/application/task_views.ex` and `.../adapters/postgres/task_views.ex`
  — bounded Inbox/Today/Upcoming/Completed views with keyset paging; the MCP read resources
  wrap these.
- `apps/server/lib/keepling/application/activity.ex` — already returns
  `actor: %{label, principal, type}` and has an `@activity_types` closed vocabulary plus
  cursor encode/decode. MCP-04 extends this, it does not replace it.
- `apps/server/lib/keepling/application/undo.ex` — the GTD-07 bounded revision-aware undo
  handle that D-22 requires agent actions to expose.
- `apps/server/lib/keepling/accounts/device_grant.ex` — authorization code + PKCE, refresh
  rotation with replay detection, per-installation revocation. D-05's agent client class
  extends this.
- `apps/server/lib/keepling/accounts/security_audit.ex` — closed `@closed_event_types` with
  `record_required!` (transactional) and `record_best_effort` (availability-preserving), plus
  a health latch. Agent authorization events join this vocabulary.
- `apps/server/lib/keepling/accounts/rate_limit.ex` + `hammer 7.4.1` — agent traffic inherits
  this rather than introducing a second limiter.
- `packages/contracts/` — `openapi/keepling.yaml`, `generated/keepling.ts`, and the frozen
  vectors; `pnpm contracts:check` already gates contract drift.

### Established Patterns
- **Thin transport over application commands** (Phase 3 D-31): controllers hold no domain
  logic. The MCP adapter is the fourth instance of this pattern, not an exception to it.
- **Closed vocabularies everywhere**: `@activity_types`, `@closed_event_types`, closed command
  arguments with `version: 1`. Scopes (D-06) and agent errors (D-14) follow the same shape.
- **Opaque bound values**: sync cursors bind server instance, account subject, epoch, protocol
  version, sequence, ordinal (Phase 2 D-10); activity cursors are account-bound with a size
  cap. The preview token (D-17) is deliberately the same construction.
- **Named-lane evidence with explicit BLOCKED** (Phase 4 D-20/D-22/D-24): `tooling/verify-ios-phase.mjs`
  is the working reference for a phase gate that refuses to report a pass it cannot support.

### Integration Points
- **New:** an MCP pipeline in `apps/server/lib/keepling_web/router.ex` and an adapter module
  tree beside `keepling_web/controllers/`.
- **New:** a `search` application query plus its HTTP endpoint (D-09) — the one genuinely
  missing read capability; `grep -rn search apps/server/lib` returns nothing today.
- **New:** a project read view reachable by both HTTP and MCP.
- **Extended:** `device_grant.ex` gains the agent client class and a scope column; the
  device-grant list and revoke endpoints gain agent rows.
- **Extended:** the activity actor vocabulary and its vector file.
- **New tooling:** the five-lane gate plus the cross-adapter proof lane, following
  `tooling/verify-ios-phase.mjs`'s structure.

</code_context>

<specifics>
## Specific Ideas

- **Phase 4's lesson is the design input here.** That phase shipped 21 green lanes over
  stubs, fakes, and a fixture that had been committed in its post-migration state — the
  assertion was tautological on every checkout. Five separate verifier passes then found
  skipped cases published as executed, a counter that discarded whole test bundles, and a
  composite of three runs written up as one gate. D-25 and D-26 exist so that an agent-safety
  claim cannot be made the same way: an unexercised lane says BLOCKED, and every lane is
  scored on final database state rather than on what a model said it did.
- **The threat model is content, not the network.** The interesting attack on this phase is a
  task whose notes tell the model to escalate — not an unauthenticated request. D-24 is
  written so that authorization outcomes are structurally incapable of depending on text.
- **Things (Cultured Code) remains the UI reference** for any open interaction question in the
  agent-grant and history surfaces (standing owner preference).

</specifics>

<deferred>
## Deferred Ideas

- **stdio MCP transport / locally distributed bridge binary** — needs its own signed,
  distributed artifact and sits outside server-side rate limiting and audit (D-03). Revisit
  in Phase 6 alongside packaging and signing posture.
- **Dynamic Client Registration (RFC 7591) for arbitrary third-party MCP hosts** — Phase 5
  serves representative hosts; open registration is a public-surface decision that belongs
  with the Phase 6 security and support policy.
- **Agent-initiated scheduled or recurring actions** — a new capability, and one whose
  authorization story is materially different from request-scoped access.
- **Agent-authored projects, areas, and tags** — MCP-02 names four task verbs; organization
  mutation by agent is its own scope and its own phase.
- **Sigra identity migration** — already recorded as a candidate future milestone; explicitly
  not re-litigated here.
- **Collaboration and multi-account agent access** — excluded by D-003.

</deferred>

---

*Phase: 5-Safe Agent Access*
*Context gathered: 2026-09-10*
