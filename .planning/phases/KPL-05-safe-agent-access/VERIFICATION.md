---
phase: KPL-05-safe-agent-access
verified: 2026-09-10T22:05:00Z
status: gaps_found
score: 4/5 success criteria verified
behavior_unverified: 0
overrides_applied: 0
gaps:
  - truth: "SC1 — Representative MCP hosts can read bounded Inbox, Today, Upcoming, project, task, and search resources using least-privilege authorization."
    status: failed
    reason: >-
      The MCP read surface itself is bounded, paginated, and redacted, but the boundedness is a
      property of the SURFACE, not of the agent's CREDENTIAL. An MCP device grant carrying only
      scope ["tasks.read"] is accepted verbatim by the :device_grant_authenticated pipeline, which
      also fronts the native unbounded sync surface and the device-grant administration routes.
      Verified live by direct probe against a disposable server booted by this phase's own
      tooling/mcp-client/client.mjs — not inferred from reading code.
    artifacts:
      - path: "apps/server/lib/keepling_web/router.ex"
        issue: >-
          Lines 120-127: GET /api/v1/device-grants, DELETE /api/v1/device-grants/:installation_id,
          GET /api/v1/sync and GET /api/v1/sync/bootstrap all sit behind :device_grant_authenticated.
          KeeplingWeb.MCP.Pipeline refuses a grant whose client_kind is not "mcp" (one direction),
          but KeeplingWeb.Auth.authenticate_device_grant/1 has no symmetric refusal of client_kind
          == "mcp" (the other direction). The asymmetry is the hole.
      - path: "apps/server/lib/keepling_web/auth.ex"
        issue: "authenticate_device_grant/1 (lines 118-150) asserts nothing about client_kind and nothing about scope."
      - path: "apps/server/lib/keepling_web/controllers/device_grant_controller.ex"
        issue: >-
          list/2 (line 102) returns every grant on the account; revoke/2 (line 112) revokes any
          installation_id on the account. Neither checks the caller's client_kind or its scope.
      - path: "tooling/mcp-client/final-state.mjs"
        issue: >-
          readGrants() (lines 68-78) authenticates against GET /api/v1/device-grants with an MCP
          agent's device-grant bearer and asserts status === 200. The simulated-client lane's PASS
          therefore DEPENDS on the escalation existing. Closing the hole breaks a currently-green lane.
      - path: ".planning/WINDOWS.md"
        issue: >-
          Window #66 records the escalation as a hypothetical consequence of a PROPOSED fix ("moving
          the routes to :client_authenticated would ALSO let any device grant enumerate and revoke").
          The causality is backwards: the escalation is present today on the pipeline as committed.
          The /api/v1/sync bypass is not recorded anywhere in WINDOWS.md, the SUMMARYs, or REQUIREMENTS.md.
    missing:
      - "A client_kind == \"mcp\" refusal on :device_grant_authenticated (symmetric to MCP.Pipeline's non-mcp refusal), or an explicit per-route allow-list."
      - "A scope check on DeviceGrantController.list/2 and revoke/2 so grant administration is not reachable by an agent credential of any scope."
      - "A deliberate authorization decision for the owner's browser path (window #66), which must not be a pipeline swap."
      - "A negative test in the adversarial lane asserting that an MCP grant is refused on /api/v1/sync, /api/v1/sync/bootstrap, and both /api/v1/device-grants routes."
      - "Rework of tooling/mcp-client/final-state.mjs readGrants() to use the owner's session cookie, since its current MCP-bearer path is the escalation."
      - "Correction of WINDOWS.md #66 to state the escalation as present, not prospective."
deferred:
  - truth: "SRV-02 — User receives the same domain invariants through web, desktop, iPhone, API, and MCP entry points."
    addressed_in: "Deferred beyond Phase 5 (no later milestone phase currently claims it; needs an explicit owner)"
    evidence: >-
      REQUIREMENTS.md line 128 states SRV-02 "completes at the Phase 5 cross-adapter proof". That
      lane now exists and ran live, but 2 of its 4 legs are BLOCKED on unwired drivers (electron,
      iphone). This is disclosed missing evidence, not a defect — the remaining work is driver
      wiring in tooling/cross-adapter/legs.mjs, not product change. Phase 6 SC2 names "exact server,
      web, packaged Electron, native archive ... evidence bound to one revision", which is adjacent
      but does not name SRV-02 or the cross-adapter lane, so this is recorded as an unowned deferral
      rather than a silent one.
coincidental_reliance_items:
  - truth: "SC5 — the simulated-client lane scores final state and forbidden side effects (9 scenarios PASS)."
    reason: undeclared-precondition
    harden: >-
      final-state.mjs readGrants() reads the account's grant list using an MCP agent's own bearer.
      Nothing in the product is supposed to guarantee that an agent credential can enumerate grants
      — in fact the phase goal forbids it. The lane passes because of the defect above. Re-point
      readGrants() at the owner's session cookie (readTask/readActivity already use it) so the lane's
      green does not rest on the escalation it should be catching.
---

# Phase KPL-05: Safe Agent Access — Verification Report

**Phase Goal:** External AI tools can use Keepling meaningfully without bypassing its authorization, domain rules, or recovery model.
**Verified:** 2026-09-10 (main checkout, `382419d`)
**Status:** gaps_found
**Re-verification:** No — initial verification

## Verdict

**NOT MET.**

The two BLOCKED lanes would *not*, on their own, have sunk this phase. `cross-adapter`'s electron
and iphone legs are unwired drivers over artifacts that genuinely exist, and SRV-02 was scheduled
from the start to complete at that lane — that is textbook disclosed missing evidence and would have
supported a MET WITH DISCLOSURE verdict at 4/5.

What sinks it is a defect in the phase's central claim, found by probe, not by reading SUMMARYs: an
MCP agent credential scoped to `tasks.read` alone can read the entire account through the native
sync surface, enumerate every device grant, and revoke another client's grant. The goal sentence
names exactly these three things — authorization, domain rules, recovery model — and the third one
is not merely unproven, it is actively attackable by the credential this phase issues.

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Representative MCP hosts read bounded Inbox/Today/Upcoming/project/task/search using least-privilege authorization | ✗ FAILED | Read SURFACE verified (`resources.ex`, default limit 20 / max 50, cursor pagination, `Redaction.page/2`; `resources_test.exs` 22 cases; `representative-model` lane drove a live model through `resources/read` and search). Least-privilege AUTHORIZATION falsified by probe — see Gap 1. |
| 2 | A direct user request can capture, update, complete, or reopen exactly one task through closed schemas and stable, model-correctable errors | ✓ VERIFIED | `tools.ex` (848 lines) — four single-task tools, closed key sets (`@capture_task_keys`, `@lifecycle_keys`), `mutation_id` idempotency, `expected_revision` gate, `Errors.unknown_tool/0` fallthrough; `tools_test.exs` 14 cases; `simulated-client` 9 scenarios scored on final DB state; live model passed `benign_capture` AND `scope_forbidden_request` (a real model asked to write with a read-only grant was refused); e2e step 2 against the real stack. |
| 3 | Ambiguous matches mutate nothing; bulk/high-impact changes require a bound exact preview and explicit commit; stale previews fail atomically | ✓ VERIFIED | `addressing.ex` (identity-only), `ambiguity_test.exs` 9 cases, `preview_commit_test.exs` 11 cases, `Keepling.Application.Preview`. Live model scenarios `under_determined_target` (model could not guess a target and mutated nothing — proven by `assertNoForbiddenSideEffects`, not by the model's own words) and `bulk_destructive_via_preview_commit` (lane asserts the destructive change was *reached through* the two-step pair). `cross-adapter` `update_stale_expected_revision` returns `refused:task_lifecycle_conflict` with `final_revision=2` (unchanged) on both live legs. |
| 4 | User-visible history shows typed actions, affected identities/revisions, result, actor, and recovery without exposing private chain of thought | ✓ VERIFIED | `e2e/agent-access.spec.ts` steps 3 and 4 PASS against the real stack — the owner's browser sees both agent actions with actor attribution, and the undo control on the agent's completion works. (The spec as a whole is red, but it reaches line 250, i.e. it fails in step 5 / grant management, *after* every MCP-04 assertion has passed. Verified by running the spec, not by reading the summary.) `content_isolation_test.exs` 8 cases; `redaction.ex`; the `representative-model` lane never reads the model's own text — verdicts come from `final-state.mjs`. |
| 5 | Deterministic, protocol, simulated-client, representative-model, and adversarial suites score final state and forbidden side effects | ✓ VERIFIED | All five lanes exist as files and all five PASS in my own runs: deterministic 183, protocol 2, simulated-client 9, adversarial 6, representative-model 6 (live model). Scoring is on final DB state + `FORBIDDEN_SIDE_EFFECTS`, never on HTTP status — `parseSimulatedClientOutput` deliberately never inspects a status code. See the coincidental-reliance note on the simulated-client lane. |

**Score:** 4/5 truths verified (0 present, behavior-unverified)

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|--------------|----------|
| 1 | SRV-02 cross-adapter completion | Unowned — not Phase 5, not explicitly Phase 6 | 2 of 4 legs BLOCKED on unwired drivers; see frontmatter `deferred` |

### Requirements Coverage

| Requirement | Recommendation | Evidence | Where the evidence is thin |
|-------------|----------------|----------|-----------------------------|
| **MCP-01** — bounded, paginated reads without direct database access | ✗ **DO NOT CHECK** | Surface is real: `resources.ex` routes all six views through one shared port with cursor+limit; 22 resource tests; live model read through it. | The requirement's operative word is *bounded*. Probe shows the same agent bearer returns full task content (title `probe secret payload`) from `GET /api/v1/sync/bootstrap` — unbounded, unpaginated, unredacted. The agent has "direct database access" in every sense that matters. Fix the pipeline, then check. |
| **MCP-02** — capture/update/complete/reopen via closed schemas, least-privilege scopes, idempotency, expected revisions, stable errors | ✓ **CHECK** | Every clause independently exercised: closed key sets in `tools.ex`; generated schemas under `contracts:check:mcp`; `mutation_id` replay handling; explicit `expected_revision` comparison against a fresh read; `errors.ex` closed vocabulary (258 lines); live model refused on an out-of-scope write; identical `result_code`/`conflict_shape` on web-api and mcp legs. | Thin spot, disclosed: "least-privilege scopes" holds *for task writes* (proven), but the credential is over-privileged *outside* the task surface (Gap 1). Check MCP-02 on its own text; do not let it stand as evidence that the agent credential is least-privilege overall. |
| **MCP-03** — ambiguous requests return candidates and perform no mutation | ✓ **CHECK** | `ambiguity_test.exs` 9 cases; identity-only addressing in `addressing.ex` means there is no name-matching write path to be ambiguous *with*; the live-model `under_determined_target` scenario is scored by before/after DB diff, so "no mutation" is proven by state, not by the model's claim. | Strongest of the five. No material thinness. |
| **MCP-04** — user sees which agent action occurred, affected identities/revisions, and an undo path, without private chain of thought | ✓ **CHECK** | e2e steps 3-4 PASS on the real stack (see SC4 row) — this is browser-observed, not unit-level. `content_isolation_test.exs` 8 cases. The representative-model harness structurally cannot store model reasoning: it never reads assistant text. | The "no chain of thought" half is proven by construction (nothing writes it) rather than by an adversarial attempt to *make* the server store reasoning. Acceptable, but it is an absence-of-mechanism argument. |
| **MCP-05** — bulk/destructive changes require an exact bound preview and explicit commit; stale commits fail atomically with zero partial writes | ✓ **CHECK** | `Keepling.Application.Preview`; `preview_commit_test.exs` 11 cases; `bulk_destructive_via_preview_commit` driven by a live model, which had to discover and use the two-step pair; forbidden-side-effect scoring proves zero partial writes. | "Zero partial writes" is asserted via the scenario diff rather than by injecting a mid-commit fault. A fault-injected partial-commit test would be stronger. Not enough to withhold the check. |
| **SRV-02** — same domain invariants through web, desktop, iPhone, API, and MCP | ✗ **DO NOT CHECK — DEFER** | `cross-adapter` lane exists and ran live; `web-api` and `mcp` legs PASS with identical `result_code`/`conflict_shape`/`activity_fact`/`final_revision` across all 4 shared scenarios (`comparison_ok=true`). | Two of four legs BLOCKED on unwired drivers. Independently, Gap 1 is itself an SRV-02 divergence in the wrong direction: the MCP entry point does not deliver *the same* invariants, it delivers strictly more authority than the surface it fronts. Both must close. |

**Recommendation: check MCP-02, MCP-03, MCP-04, MCP-05. Leave MCP-01 and SRV-02 unchecked.**

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `KeeplingWeb.MCP.Dispatch` | `KeeplingWeb.MCP.Pipeline` | `:mcp` router pipeline | ✓ WIRED | Refuses `client_kind != "mcp"` and enforces the RFC 8707 resource audience. |
| `KeeplingWeb.Auth` `:device_grant_authenticated` | `/api/v1/sync`, `/api/v1/device-grants` | router.ex 120-127 | ✗ MIS-WIRED | Accepts `client_kind == "mcp"`. This is Gap 1. |
| `KeeplingWeb.MCP.Resources` | `Keepling.Application.Search` / projects port | compile-env ports | ✓ WIRED | Same ports the HTTP `/api/v1/search` endpoint uses — one query, not a parallel one. |
| `tooling/verify-mcp-phase.mjs` | `tooling/mcp-lanes/*.mjs` | directory glob + default-export contract | ✓ WIRED | A lane file that fails to load is a runner failure, never a skipped lane (verified by reading the loader, exercised by the self-test). |
| `tooling/mcp-client/final-state.mjs` | `/api/v1/device-grants` | MCP device-grant bearer | ⚠️ HOLLOW | Wired and passing, but only because of Gap 1. See coincidental-reliance. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full phase gate reproduces published lane counts | `node tooling/verify-mcp-phase.mjs` | deterministic 183, protocol 2, simulated-client 9, adversarial 6 PASS; cross-adapter + representative-model BLOCKED; exit 1 | ✓ PASS (matches claim) |
| Representative-model lane with credential loaded | `pnpm run verify:mcp:model` | `PASS cases=6 duration_ms=54929`; `.env.local` present and loaded, `.env` absent; model id = lane default (`KEEPLING_MCP_MODEL` unset) | ✓ PASS |
| Harness self-test (05-10's test-of-the-harness) | `node --test tooling/mcp-gate-selftest.mjs` | 10 pass, 0 fail, 0 skipped | ✓ PASS |
| The named failing e2e spec | `KEEPLING_E2E_POSTGRES_PORT=55442 pnpm --filter @keepling/web test:e2e -- agent-access.spec.ts` | 25 passed, 1 failed at `agent-access.spec.ts:250` (step 5, grant listing) — steps 1-4 all passed | ✓ PASS (localizes the failure away from MCP-01..05) |
| Read-only MCP grant reaches native sync | probe via `tooling/mcp-client/client.mjs`, disposable server | `GET /api/v1/sync/bootstrap` → **200**, body contains the task title captured through MCP | ✗ FAIL (escalation) |
| Read-only MCP grant enumerates grants | same probe | `GET /api/v1/device-grants` → **200**, both installations listed | ✗ FAIL (escalation) |
| Read-only MCP grant revokes another client | same probe | `DELETE /api/v1/device-grants/verifier-probe-writer` → **200** `{"status":"device_grant_revoked"}`; the victim grant then **401**s on `/mcp/v1` | ✗ FAIL (escalation, recovery-model impact) |

Credential handling: `.env.local` was loaded only by Node's own `--env-file-if-exists` inside the
`pnpm` script. The credential value was never read, echoed, copied, or written to any artifact; only
its presence and the lane's verdict are recorded here.

### Probe Execution

| Probe | Command | Result | Status |
|-------|---------|--------|--------|
| MCP phase gate | `node tooling/verify-mcp-phase.mjs` | exit 1, `blocked=2 failed=0` | BLOCKED (by design) |
| Cross-adapter lane | (within gate) | `legs_ran=2 legs_blocked=2 legs_failed=0 comparison_ok=true` | BLOCKED (disclosed) |
| Gate self-test | `node --test tooling/mcp-gate-selftest.mjs` | 10/10 | PASS |

### Anti-Vacuity Audit (05-10's own claim, checked adversarially)

05-10's reasoning **holds**, and I tried to break it:

- `exUnitSummary` subtracts skipped/excluded from the declared count and **throws** on a bundle that
  reduces to zero — the exact Phase 4 defect (WINDOWS #65) is asserted against with the real bundle
  counts (19+18→37, not 18).
- `laneVerdict` is factored out as a pure function so BLOCKED-vs-FAIL-vs-PASS is testable without
  spawning anything; a lane returning zero cases without throwing is FAILED, not passed.
- `RUN_ID` is minted per module load and the self-test asserts two loads differ — the mechanical
  answer to "three runs written up as one gate".
- Lanes are discovered by glob; a lane file that fails to load exits the runner, so a lane cannot
  vanish silently.
- `guardAgainstShortcuts` greps each lane's own source for `KEEPLING_TEST_SYNC_MODE`, `.invalid`
  hosts, injected `fetch`, and hand-injected bearers before booting a server.
- `parseSimulatedClientOutput` never inspects an HTTP status code.
- `--requirements` reads the requirement ids live from REQUIREMENTS.md rather than hardcoding them.

One genuine weakness: the `protocol` lane hardcodes `cases=2` in its own evidence line, so its case
count is a constant rather than a count of assertions executed. The lane does perform real handshake
assertions over the real transport against a pinned protocol revision, so it is not vacuous — but
its number is decorative, and the anti-vacuity contract elsewhere in this phase is about numbers
meaning something. Minor; recorded, not gating.

And one weakness the harness could not catch by construction: every lane is built to detect
*under*-delivery (a surface that refuses what it should allow, a mutation that did not happen).
Nothing in the six lanes probes *over*-delivery — whether the credential the harness itself mints
reaches surfaces the MCP adapter does not front. Gap 1 lived in exactly that blind spot, and
`final-state.mjs` quietly consumed the hole as a convenience.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `apps/server/lib/keepling_web/auth.ex` | 118-150 | Missing symmetric authorization check | 🛑 Blocker | An `mcp` grant is accepted on the native device pipeline. |
| `apps/server/lib/keepling_web/controllers/device_grant_controller.ex` | 102, 112 | Grant administration with no scope or client_kind gate | 🛑 Blocker | Any agent credential enumerates and revokes the owner's clients. |
| `tooling/mcp-client/final-state.mjs` | 68-78 | Test harness depends on the defect it should catch | ⚠️ Warning | A green lane rests on the escalation. |
| `.planning/WINDOWS.md` | 83 (#66) | Present defect recorded as a prospective one | ⚠️ Warning | Understates an existing privilege escalation as a future risk. |
| `tooling/mcp-lanes/representative-model.mjs` | 355 | `void errorVectors // reserved for a future ...` | ℹ️ Info | Loaded-but-unused vector set; no debt marker (`TODO`/`FIXME`/`XXX`) present, so not gating. |

No unreferenced `TBD`/`FIXME`/`XXX` debt markers were found in the phase's modified files.

### Gaps Summary

The phase built a great deal that genuinely works. The MCP adapter is real, the write tools are
closed and revision-gated, ambiguity refuses by construction because addressing is identity-only,
preview/commit is bound and atomic, the owner really does see and undo an agent's action in a
browser against a live stack, and a real language model really does drive the real server and get
refused when it reaches past its scope. Four of five success criteria are met on evidence I
reproduced myself, and 05-10's anti-vacuity machinery survived my attempts to find a way for a lane
to pass without exercising the product.

The failure is narrow and severe. The MCP pipeline carefully refuses non-`mcp` grants, but nothing
performs the mirror-image refusal, so the credential this phase mints for an external AI tool is
simultaneously a full native device credential. A grant scoped `tasks.read` reads the whole account
through `/api/v1/sync/bootstrap` — around the bounded, paginated, redacted surface the phase spent
four plans building — lists every device grant on the account, and revokes any of them. In
production that is an agent switching off the owner's iPhone.

Two further things make this worse than a single missing check. First, the phase's own test harness
*uses* the hole: `final-state.mjs` reads the grant list with an agent bearer and asserts 200, so the
`simulated-client` lane is green partly because the escalation exists. Second, WINDOWS #66 has the
causality inverted — it describes the escalation as something a future fix would introduce, when it
is present in the committed pipeline today, and it never mentions the sync surface at all. Both
would have carried the defect past a reader who trusted the record.

Recommended sequencing: close the pipeline asymmetry and the grant-administration authorization
together (they are one decision, and window #66's browser-side question is the third face of it),
re-point `final-state.mjs` at the session cookie, add adversarial-lane negative cases for all four
routes, correct #66, and only then revisit MCP-01. SRV-02's driver wiring is independent and can
proceed in parallel or defer.

---

_Verified: 2026-09-10_
_Verifier: Claude (gsd-verifier)_
