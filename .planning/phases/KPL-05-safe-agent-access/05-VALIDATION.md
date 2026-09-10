---
phase: "5"
slug: "safe-agent-access"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-09-10"
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Source: `05-RESEARCH.md` § Validation Architecture. Governing constraint: `05-CONTEXT.md`
> D-25/D-26 — the anti-vacuity contract carried forward verbatim from Phase 4 D-24.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (Elixir `~> 1.20.2`, `apps/server/mix.exs`) for the server; Node `tooling/verify-*.mjs` gate runners for cross-cutting evidence lanes, structured after `tooling/verify-ios-phase.mjs` |
| **Config file** | `apps/server/mix.exs` — the `mix test` alias runs `ecto.create --quiet`, `ecto.migrate --quiet`, `test` |
| **Quick run command** | `cd apps/server && mix test test/keepling_web/mcp/` |
| **Full suite command** | `cd apps/server && mix test` plus `node tooling/verify-mcp-phase.mjs` |
| **Estimated runtime** | ~90 s quick / several minutes full (the representative-model and cross-adapter lanes dominate) |

---

## Sampling Rate

- **After every task commit:** `cd apps/server && mix test test/keepling_web/mcp/` (or the narrowest relevant directory)
- **After every plan wave:** `cd apps/server && mix test` plus the wave's relevant `tooling/verify-*.mjs` lanes
- **Before `/gsd-verify-work`:** the full five-lane gate plus the D-27 cross-adapter proof, green — **or explicitly `BLOCKED` with disclosure** per D-25/D-26. A lane that cannot be genuinely exercised reports BLOCKED; it never silently passes.
- **Max feedback latency:** 120 s for the per-task loop

---

## Per-Task Verification Map

Task IDs are assigned by the planner; this table binds each **requirement** to its lane and
command so the planner can attach them. Wave 0 gaps are marked ❌ W0.

| Requirement | Behavior | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---|---|---|---|---|---|---|---|
| MCP-01 | Bounded, paginated Inbox/Today/Upcoming/project/task/search reads, no direct DB access | V4 Access Control | Reads are account-scoped and cursor-bounded; no path returns another account's rows | deterministic + protocol | `cd apps/server && mix test test/keepling_web/mcp/resources_test.exs` | ❌ W0 | ⬜ pending |
| MCP-02 | Capture/update/complete/reopen via closed schemas, scopes, idempotency, expected revisions, stable errors | V5 Input Validation | `additionalProperties: false`; mutation identity + expected revision required exactly as for human clients | deterministic + simulated-client | `cd apps/server && mix test test/keepling_web/mcp/tools_test.exs`; `node tooling/mcp-lanes/simulated-client.mjs` | ❌ W0 | ⬜ pending |
| MCP-03 | Ambiguous match returns bounded candidates and mutates nothing | Elevation of Privilege | Zero-candidate and too-many-candidate are distinct closed errors; no write executes on either path | deterministic + adversarial | `cd apps/server && mix test test/keepling_web/mcp/ambiguity_test.exs` | ❌ W0 | ⬜ pending |
| MCP-04 | Visible typed history with actor, revisions, result, undo path; no chain of thought | Information Disclosure | **Schema-level:** assert no free-text reasoning field exists on the activity struct/table — not a read-time redaction filter | deterministic | `cd apps/server && mix test test/keepling/application/activity_test.exs` | ✅ extend | ⬜ pending |
| MCP-05 | Preview/commit atomicity; `preview_stale` on drift, zero partial writes | Tampering / Repudiation | Single transaction with expected-revision recheck against live rows; partial success is not representable | deterministic (concurrent-mutation-during-preview) | `cd apps/server && mix test test/keepling/application/preview_test.exs` | ❌ W0 | ⬜ pending |
| D-06 scopes | Two-layer scope check (adapter **and** application boundary) | V4 Access Control | An adapter-layer bug alone cannot widen authority | deterministic | `cd apps/server && mix test test/keepling/accounts/device_grant_test.exs` | ✅ extend | ⬜ pending |
| D-24 injection | Injection corpora in task content never influence authorization | Elevation of Privilege | Scope checks, preview binding and ambiguity resolution read structural fields only; **scored on final DB state**, never on model output | adversarial | `node tooling/mcp-lanes/adversarial.mjs` | ❌ W0 | ⬜ pending |
| D-26 model lane | A real model as MCP client | — | **BLOCKED without a credential**; verdict deterministic given final state | representative-model | `node tooling/mcp-lanes/representative-model.mjs` | ❌ W0 | ⬜ pending |
| D-30 protocol | Conformance against the pinned MCP revision `2025-06-18` | Spoofing | RFC 8707 audience binding verified on every agent-issued token | protocol | `node tooling/mcp-lanes/protocol.mjs` | ❌ W0 | ⬜ pending |
| SRV-02 / D-27 | Identical result codes, conflict shapes and activity records across all five adapters, one server revision | — | The cross-adapter proof; SRV-02 stays unchecked until it passes | cross-adapter | `node tooling/verify-cross-adapter-phase.mjs` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `apps/server/test/keepling_web/mcp/` — no MCP test directory exists; the whole adapter suite is new
- [ ] `apps/server/test/keepling/application/search_test.exs` and `preview_test.exs` — new application modules, no tests exist
- [ ] `tooling/mcp-lanes/*.mjs` — mirroring `tooling/ios-lanes/*.mjs`; `verify-ios-phase.mjs` discovers lanes by glob rather than declaring them inline, and the new runner must do the same
- [ ] `tooling/verify-mcp-phase.mjs` — modelled directly on `verify-ios-phase.mjs`'s anti-vacuity structure: positive case counts, **skips subtracted**, **every bundle summed** (never the last summary line), tracked-input digests, and `BLOCKED:`-prefixed parse errors that still fail the gate
- [ ] A cross-adapter proof runner — no existing lane drives all five adapters against one scenario set; this is new tooling, not an extension

---

## Anti-Vacuity Controls (D-25/D-26 — mandatory)

Phase 4 shipped 21 green lanes over stubs and a fixture committed in its post-migration state.
These are the structural mechanisms that stop the same thing here. Each is a *test of the
harness*, not of the feature.

| Vacuity risk | Structural prevention |
|---|---|
| A lane passes because it never ran a case | Gate asserts a **positive** case count per bundle; zero cases fails the lane |
| Skipped cases published as executed | Skips subtracted from the published total, as in `verify-ios-phase.mjs` after the Phase 4 fix |
| A whole test bundle silently discarded from the count | Anchor on each bundle summary and **sum**; never read the last `Executed N tests` line |
| The simulated-client lane speaks to a stub rather than the real transport | The lane must complete a real MCP handshake over the real HTTP pipeline with a real grant; assert the server observed the request |
| The adversarial lane scores model text instead of behaviour | Verdict computed **only** from final DB state and a forbidden-side-effect list |
| The representative-model lane silently no-ops without a credential | Reports `BLOCKED`, never a pass |
| The cross-adapter lane proves four adapters and asserts the fifth from a fixture | Each leg must produce its result from a running adapter against the same server revision; a missing leg BLOCKS the lane |

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|---|---|---|---|
| A representative host (Claude Desktop) completes the connector flow end to end | D-29 (DCR) | Host connector UI is not scriptable; DCR behaviour rests on secondary sources and may change | Add the server as a connector in Claude Desktop; confirm registration succeeds behind the authenticated session and scopes are named on the consent screen |
| MCP revision still matches live host behaviour at execution time | D-30 | The spec moved twice during this phase's own discussion | Re-check host-advertised protocol revision **before** writing the transport, not against `05-RESEARCH.md` |

The owner's standing preference is zero manual verification. Both rows above are host-behaviour
checks with no programmatic surface today; if either becomes scriptable, promote it to a lane
rather than leaving it here.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120 s
- [ ] Anti-vacuity controls above each have a test asserting the harness itself
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
