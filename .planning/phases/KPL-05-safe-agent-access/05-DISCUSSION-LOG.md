# Phase 5: Safe Agent Access - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-10
**Phase:** 5-safe-agent-access
**Mode:** `--auto` (owner instruction: "auto follow ur recs"). Advisor calibration
`minimal_decisive` from `~/.claude/gsd-core/USER-PROFILE.md` — 1–2 options, one decisive
recommendation, brief rationale. No `AskUserQuestion` calls were made.
**Areas discussed:** Adapter placement and transport, Agent authorization and scopes, Read
surface, Write surface and closed schemas, Ambiguity handling, Preview and commit, Visible
history and privacy, Adversarial posture, Evidence model

---

## Adapter placement and transport

| Option | Description | Selected |
|--------|-------------|----------|
| In-process Elixir adapter | MCP lives in `apps/server`, calls the same application commands the HTTP controllers call | ✓ |
| Node/TS MCP sidecar over the public API | Official SDK ecosystem, but a second process, a second auth implementation, and an extra hop | |

**Auto-selected:** In-process Elixir adapter (recommended).
**Notes:** The decisive argument is evidentiary, not architectural preference. SRV-02 claims
"the same domain invariants through web, desktop, iPhone, API, and MCP entry points". A
sidecar speaking HTTP would prove the API rather than the semantic boundary, so the
cross-adapter proof would be weaker in exactly the place the requirement is strongest. It
also satisfies D-008 and Phase 1 D-02 directly. Cost accepted: the TS/Python MCP SDK
ecosystem is richer than Elixir's, so protocol conformance must be earned by a dedicated
lane (D-25) rather than inherited from an SDK.

---

## Protocol layer: library vs hand-rolled

| Option | Description | Selected |
|--------|-------------|----------|
| Decide in research, constrain now | Evaluate `hermes_mcp`; lock only that the layer owns framing and never owns authorization | ✓ |
| Commit to hand-rolling now | Full control, more code, no dependency risk | |

**Auto-selected:** Decide in research under a fixed constraint.
**Notes:** Library maturity is an evidence question, not a vision question — it belongs to the
researcher. What matters at this stage is the boundary: framing only, never authorization,
scope enforcement, validation, dispatch, or error mapping.

---

## Transport

| Option | Description | Selected |
|--------|-------------|----------|
| Streamable HTTP through the existing router | Inherits `hammer` rate limiting and the `security_audit` path | ✓ |
| stdio | Local-only, but needs a separately signed distributed binary and bypasses server-side limits | |

**Auto-selected:** Streamable HTTP. stdio deferred (see Deferred Ideas).

---

## Agent authorization and scopes

| Option | Description | Selected |
|--------|-------------|----------|
| Agent as a first-class device-grant client class | Own `client_id`, own refresh family, independently revocable, visibly labelled | ✓ |
| Reuse an existing Electron/iPhone grant | Less work; makes agent actions indistinguishable from the user's own | |

**Auto-selected:** First-class client class.
**Notes:** MCP-04 requires the user to see *which agent* acted. That is impossible if the
agent borrows a human client's grant. Revocation also needs to be able to cut the agent
without signing the user out of their Mac.

| Option | Description | Selected |
|--------|-------------|----------|
| Small closed scope vocabulary, checked twice | `tasks.read` / `tasks.write` / `tasks.bulk`; enforced in the adapter *and* re-checked at the application boundary | ✓ |
| Per-command fine-grained scopes | Maximum precision; large published surface, more ways to misconfigure | |

**Auto-selected:** Small closed vocabulary with double enforcement.
**Notes:** Marked **one-way** in CONTEXT.md — scope strings become a published contract that
hosts persist inside stored grants, so renaming one later silently changes what an existing
grant permits. The double check exists so an adapter bug cannot widen authority alone.

| Option | Description | Selected |
|--------|-------------|----------|
| Authorization code + PKCE via external user agent | Reuses the Phase 1 D-22 / Phase 2 D-22 seam; explicit user consent naming scopes | ✓ |
| Static API key or client-credentials grant | Simpler for a solo dogfood user; a bearer secret with no consent moment and no natural revocation | |

**Auto-selected:** Authorization code + PKCE. Marked **one-way** — static keys issued now
outlive any later decision to stop issuing them.

---

## Read surface

**Auto-selected:** Resources for addressable reads, a `search` tool for parameterized
queries, all bounded by the existing opaque keyset cursors.
**Notes:** Scouting found no `search` anywhere in `apps/server/lib`, and no project read
view. MCP-01 names both. The decisive call is that they are built as **shared application
queries reachable by HTTP too**, not MCP-only paths — otherwise MCP gains a capability the
other adapters lack, which would falsify SRV-02's "same invariants" claim in the very commit
that proves it.

---

## Write surface and closed schemas

| Option | Description | Selected |
|--------|-------------|----------|
| Small task-shaped tool set (MCP-02's four verbs + preview/commit) | Fewer tools, less authorization surface, better host ergonomics | ✓ |
| 1:1 mirror of the twelve `/commands/*` endpoints | Complete; every extra tool is extra authorization surface and extra schema to keep in sync | |

**Auto-selected:** Small task-shaped set.
**Notes:** Schemas closed (`additionalProperties: false`) and generated from
`packages/contracts`, extending Phase 4's D-13/D-14 discipline to a fourth consumer.
Mutation identity and expected revision are required exactly as for human clients — agents
get no relaxation. Errors are stable and closed so a model can correct against them and a
deterministic lane can assert them.

---

## Ambiguity handling

**Auto-selected:** Opaque identity is the only write address; under-determined targets return
`ambiguous_match` with bounded candidates and mutate nothing.
**Notes:** This is Phase 1 D-18 applied where the caller is a language model and the failure
mode is silently editing the wrong task. Marked **one-way**: name-addressed writes, once
published, are what hosts build against.

---

## Preview and commit

**Auto-selected:** Two-step with an opaque, account-bound, expiring token binding the exact
target set, each target's expected revision, the command and arguments, and the server
instance plus sync epoch. Commit takes only the token and a mutation identity.
**Notes:** The token construction is deliberately the same as Phase 2 D-10's cursor binding.
Commit accepting a re-sent target list was rejected outright — it would let the committed set
differ from the previewed one, which is the exact failure MCP-05 forbids. Partial success is
not a representable outcome (**one-way**). "Destructive" is a closed list — trash, restore,
undo, and anything affecting more than one task — because a closed list is testable and
"high-impact as a judgment call" is not.

---

## Visible history and privacy

**Auto-selected:** Extend the existing `actor: %{label, principal, type}` model rather than
building a parallel agent-audit surface; persist no model reasoning at the schema level;
agent actions expose the same GTD-07 undo handle as human actions.
**Notes:** "No chain of thought" is implemented as *there is no column for it*, not as a
redaction filter on read (**one-way**). A second history surface was rejected as a second
thing that can disagree with the first. Phase 5 UI is the existing activity view plus an
agent-grant management view — no new client applications.

---

## Adversarial posture

**Auto-selected:** All task content returned to a model is untrusted data; authorization
outcomes are structurally incapable of depending on free text.
**Notes:** The interesting attack here is a task whose notes instruct the model to escalate,
not an unauthenticated request. Scope checks, preview binding, and ambiguity resolution read
structural fields only. Marked **one-way** — this is the security property the phase exists
to establish.

---

## Evidence model

**Auto-selected:** Five named lanes (deterministic, protocol, simulated-client,
representative-model, adversarial), carrying Phase 4's D-24 anti-vacuity contract forward
verbatim; model-driven lanes scored on final database state and forbidden side effects, never
on model output; one cross-adapter lane completing SRV-02.
**Notes:** Phase 4 shipped 21 green lanes over stubs, fakes, and a fixture committed in its
post-migration state, then five verifier passes found skipped cases published as executed, a
counter discarding whole bundles, and a composite of three runs written up as one gate. This
phase is about agent *safety*, so the same failure would be considerably worse. Hence: an
unexercised lane reports BLOCKED, the representative-model lane BLOCKS without a real
credential, and every model-driven verdict is deterministic given final state.

**Also recorded:** `.planning/REQUIREMENTS.md` line 21 marks SRV-02 `[x]` while all four of
its traceability rows say it completes only at this phase's cross-adapter proof. Captured as
D-28 — uncheck it as the first act of the phase.

---

## Claude's Discretion

Auto-selected but genuinely open for research to settle on evidence: MCP protocol revision to
pin; `hermes_mcp` versus hand-rolled framing; exact scope string spellings and whether
`tasks.bulk` is a scope or a property of `tasks.write`; resource URI scheme; default and
maximum page sizes; preview token expiry and storage; whether RFC 7591 Dynamic Client
Registration is needed for representative hosts.

## Deferred Ideas

- stdio MCP transport / locally distributed bridge binary — Phase 6, with packaging and
  signing posture.
- Dynamic Client Registration for arbitrary third-party hosts — Phase 6 security and support
  policy.
- Agent-initiated scheduled or recurring actions — new capability, different authorization
  story.
- Agent-authored projects, areas, and tags — own scope, own phase.
- Sigra identity migration — already recorded as a candidate future milestone.
- Collaboration and multi-account agent access — excluded by D-003.
