# Cross-Adapter Testing (D-27, SRV-02)

`tooling/verify-cross-adapter-phase.mjs` is the phase-gate lane that proves SRV-02: the same
semantic scenario set, driven through every Keepling entry point, against ONE running server
instance in ONE invocation, asserting that every leg's server-observed result code, conflict
shape, activity record, and revision are identical.

## What it proves, and what it does not (yet)

The shared scenario set is the four command verbs `Keepling.Application.Commands` exposes
identically to every adapter today -- `capture_one_task`, `complete_task`, `reopen_task`, and
`update_stale_expected_revision` (a genuine stale-revision refusal). This is a deliberate
narrowing from the plan's aspirational nine-scenario set
(`tooling/mcp-client/scenarios.mjs`, built by 05-11): two of those nine scenarios
(`preview_and_commit_multi_target`, `commit_stale_preview`) exercise the D-17 preview/commit
primitive, which is an MCP-only wire construct in this phase -- no HTTP `/commands/*` endpoint,
no Electron IPC command, and no iPhone app action expose an equivalent two-step preview/commit
surface. Asserting those two scenarios "identically" across all four adapters is not possible
without inventing a second, adapter-specific preview mechanism this phase never built. This
lane therefore proves MCP-02's four write verbs cross-adapter; MCP-05's bulk/destructive
guarantee remains proven single-adapter by the `adversarial`/`simulated-client` lanes (05-11)
until a later plan gives every adapter its own preview/commit surface.

## How to run it

```bash
node tooling/verify-cross-adapter-phase.mjs --dry-run   # lists the four legs, no server started
node tooling/verify-cross-adapter-phase.mjs              # the real run
pnpm run verify:cross-adapter                             # same as above, via package.json
node tooling/verify-mcp-phase.mjs --lane cross-adapter    # as a lane under the Phase 5 gate
```

The orchestrator boots exactly ONE real, disposable Phoenix/PostgreSQL instance (the same
bootstrap `tooling/mcp-client/client.mjs` uses), computes ONE `inputDigestFor` over the server
source tree, mints ONE run identifier, and runs each leg against that single instance in
sequence. Every leg's `CROSS_ADAPTER_SCENARIO` evidence line carries the same run identifier
and the same input digest; a mismatch fails the run.

## What each leg needs, and how long it takes

| Leg | Needs | Typical duration | What "cannot run" means here |
|---|---|---|---|
| `web-api` | Nothing beyond the orchestrator's own disposable server | ~0.1s | Effectively never blocked -- it is the orchestrator's own server, driven directly |
| `mcp` | A real PKCE-obtained `mcp` device grant against the disposable server | ~0.1s | Effectively never blocked, for the same reason |
| `electron` | A packaged desktop build at `apps/desktop/out/` (`pnpm package:desktop`) | minutes (packaging) + a live IPC driver not yet wired -- see below | No packaged build present, or (today) always, pending the live driver |
| `iphone` | A booted simulator (or the Phase 4 physical-device setup, `docs/testing/ios-testing.md`) with Keepling installed | tens of seconds (simulator boot) + a live UI driver not yet wired -- see below | No booted simulator, no installed app, or (today) always, pending the live driver |

**Disclosed gap, both hardware legs.** As of this plan, `runElectronLeg` and `runIphoneLeg`
(`tooling/cross-adapter/legs.mjs`) check their precondition (a packaged build exists; the app is
installed on a booted simulator) and, if met, still report `BLOCKED` naming that a live driver
against that artifact is not yet wired -- rather than silently skipping or fabricating evidence.
Building the packaged-Electron IPC driver (following `tooling/verify-real-stack-desktop.mjs`'s
discipline) and the iPhone recording-proxy driver (following `tooling/verify-real-stack-ios.mjs`'s
pattern) is the next increment. Until then, the lane is honestly `BLOCKED` on these two legs --
never a false `PASS`.

## What a BLOCKED leg means

A `BLOCKED:`-prefixed error names EXACTLY what is missing -- a packaged build, a booted
simulator, an installed app, a live driver. It is disclosed, genuine missing evidence, never a
code defect and never silently substituted with a fixture, a cached artifact, or another leg's
evidence. `CROSS_ADAPTER_PHASE_GATE: BLOCKED` still exits non-zero: this command can never
report success while required evidence is missing (D-25/D-26's anti-vacuity contract, carried
forward from Phase 4).

## Why a phase-gate cadence, not per-commit

The Electron and iPhone legs need a packaged build and a booted simulator respectively --
minutes of setup, not milliseconds. T-05-68 (this plan's threat register) accepts this as a
deliberate, disclosed cost: this lane runs at phase-gate cadence, the same cadence
`tooling/verify-ios-phase.mjs`'s hardware-dependent lanes already use, not on every commit.

## Evidence format

Every leg emits one `CROSS_ADAPTER_SCENARIO` line per scenario
(`tooling/cross-adapter/scenario-report.mjs`):

```
CROSS_ADAPTER_SCENARIO run_id=<uuid> input_digest=<hex> leg=<name> scenario=<id> result_code=<ok|refused:code> conflict_shape=<code|none> activity_fact=<type|none> final_revision=<n>
```

Every field is read back from the server's own APIs after the action -- the task's current
revision and its most recent activity fact (`GET /api/v1/tasks/:id`,
`GET /api/v1/tasks/:id/activity`, read via the SAME account session cookie regardless of which
adapter performed the mutation) -- never reported from the acting leg's own memory of what it
sent. `compareLegs` groups every leg's lines by scenario and asserts `result_code`,
`conflict_shape`, `activity_fact`, and `final_revision` are identical across every leg that ran;
a scenario present in some legs and absent from others is a failure, not a partial pass.
