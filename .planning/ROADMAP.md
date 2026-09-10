# Roadmap: Keepling

## Overview

Keepling is built as six vertical proof increments. Each phase produces observable user value and durable evidence while delaying additional client/runtime complexity until the shared semantics have survived the preceding slice.

### Phase 1: One Trustworthy Task

**Goal:** As a Keepling user, I want to manage one task end to end, so that I can trust every browser change.
**Mode:** mvp
**Requirements:** GTD-01..07, SRV-01, SRV-02 (semantic boundary + web/API proof), SRV-03, WEB-01..02, QUAL-01
**UI hint:** yes
**Success Criteria**:

1. A user can capture, edit, place in Today, complete, reopen, trash, restore, and undo a task through the browser against PostgreSQL.
2. Planned/Today intent remains distinct from deadline semantics and all temporal values have explicit timezone rules.
3. Duplicate mutation submission produces one durable effect and the same stable result.
4. Browser tests exercise real Phoenix/PostgreSQL happy, validation, stale, conflict, authentication-expired, empty, and retry states.
5. Domain/application modules have no dependency on React, HTTP transport, MCP, or client persistence.
6. Phase 1 proves the shared semantic boundary and web/API adapters for SRV-02; Electron, iPhone, and MCP adapter proofs remain assigned to Phases 3, 4, and 5.

**Plans:** 27/27 plans complete

Plans:

- [x] 01-24-PLAN.md
- [x] 01-25-PLAN.md
- [x] 01-26-PLAN.md
- [x] 01-27-PLAN.md

- [x] 01-20-PLAN.md
- [x] 01-21-PLAN.md
- [x] 01-22-PLAN.md
- [x] 01-23-PLAN.md

**Wave 1**

- [x] 01-01-PLAN.md — Verify dependencies and gate the exact researched server runtimes.
- [x] 01-02-PLAN.md — Materialize the complete standalone Mix/OTP/config core and lockfile.
- [x] 01-04-PLAN.md — Execute browser/contracts/Playwright Wave 0.

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 01-03-PLAN.md — Materialize Phoenix Endpoint/web runtime and deterministic ExUnit/concurrency support.

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 01-05-PLAN.md — Prove the authenticated capture Walking Skeleton and exact replay.

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 01-06-PLAN.md — Implement operator setup-token issuance, sole-account creation, and canonical account timezone.

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 01-07-PLAN.md — Implement password authentication, one-use recovery, sessions, and abuse controls.

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 01-08-PLAN.md — Make setup, login, recovery, reauthentication, logout, and Sessions reachable.

**Wave 7** *(blocked on Wave 6 completion)*

- [x] 01-09-PLAN.md — Deliver title/notes editing and explicit Inbox clarification.

**Wave 8** *(blocked on Wave 7 completion)*

- [x] 01-10-PLAN.md — Deliver stable-ID project/tag management and assignment.

**Wave 9** *(blocked on Wave 8 completion)*

- [x] 01-11-PLAN.md — Deliver safe, exact, paginated task activity.

**Wave 10** *(blocked on Wave 9 completion)*

- [x] 01-12-PLAN.md — Own temporal storage/contracts and date editing once.

**Wave 11** *(blocked on Wave 10 completion)*

- [x] 01-13-PLAN.md — Deliver timezone-correct lists, cursors, and Today ordering.

**Wave 12** *(blocked on Wave 11 completion)*

- [x] 01-14-PLAN.md — Deliver complete/reopen as a dedicated vertical slice.

**Wave 13** *(blocked on Wave 12 completion)*

- [x] 01-15-PLAN.md — Deliver Trash/restore as a dedicated vertical slice.

**Wave 14** *(blocked on Wave 13 completion)*

- [x] 01-16-PLAN.md — Deliver persisted semantic conflict resolution.

**Wave 15** *(blocked on Wave 14 completion)*

- [x] 01-17-PLAN.md — Deliver exact uncertain-delivery and auth-interruption recovery.

**Wave 16** *(blocked on Wave 15 completion)*

- [x] 01-18-PLAN.md — Deliver bounded semantic undo and persistent recovery.

**Wave 17** *(blocked on Wave 16 completion)*

- [x] 01-19-PLAN.md — Seal responsive/a11y and adversarial full-phase evidence.

### Phase 2: Synchronization and Replaceable Server

**Goal:** Keepling has a formally tested offline synchronization contract and an always-on, recoverable reference deployment.
**Mode:** mvp
**Requirements:** SRV-04..06, DATA-02..03, OPS-01..05, QUAL-02, QUAL-05
**UI hint:** no
**Plans:** 10/11 plans executed

Plans:
**Wave 1**

- [x] 02-01-PLAN.md — Prove durable local sync semantics with storage-neutral vectors and a reference reducer.

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 02-03-PLAN.md — Freeze account fencing and implement separately revocable installation grants.

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 02-02-PLAN.md — Commit atomic ordered feed rows and deliver authenticated cursor/bootstrap recovery.
- [x] 02-11-PLAN.md — Close native authorization-code, refresh/revocation, and bearer-authenticated grant transport.

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 02-04-PLAN.md — Deliver protocol-train negotiation and current/previous compatibility evidence.

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 02-05-PLAN.md — Expose authenticated sync transport and privacy-safe semantic trust states.

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 02-06-PLAN.md — Deliver inward operator semantics, health/status boundaries, and stable CLI verbs.

**Wave 7** *(blocked on Wave 6 completion)*

- [x] 02-07-PLAN.md — Package and locally deploy the immutable Caddy/Phoenix/PostgreSQL topology.

**Wave 8** *(blocked on Wave 7 completion)*

- [x] 02-08-PLAN.md — Prove encrypted backup, PITR, restore safety, and epoch rotation.

**Wave 9** *(blocked on Wave 8 completion)*

- [ ] 02-09-PLAN.md — Provision and credentialedly rehearse full Hetzner host replacement and DNS cutover.

**Wave 10** *(blocked on Wave 9 completion)*

- [x] 02-10-PLAN.md — Bind every Phase 2 capability to required CI, scheduled recovery, and privacy evidence.

**Success Criteria**:

1. Golden cross-runtime vectors prove accepted, duplicate, rejected, stale, conflict, tombstone, cursor, logout/account-switch, reconnect, and relaunch semantics.
2. The server atomically records idempotent mutation results, canonical snapshots, ordered scoped changes, and tombstones without relying on sockets for correctness.
3. A pinned app-plus-PostgreSQL topology reaches readiness locally and on a replaceable Hetzner VM provisioned from source.
4. Backup automation restores into a disposable environment and proves schema, representative data/history, login, read, and safe write/undo behavior.
5. Privacy tests reject raw task content and unsafe identifiers from logs, metrics, traces, and diagnostic bundles.

### Phase 3: Mac Daily Loop

**Goal:** Jon can dogfood the core loop in an always-open Electron Mac client, including durable offline work and process relaunch.
**Mode:** mvp
**Requirements:** MAC-01..05, QUAL-03..04, SRV-02 (Electron adapter proof)
**UI hint:** yes
**Plans:** 27/27 plans complete

Plans:

**Gap closure — Waves 24-26** *(from 03-VERIFICATION.md; the 24 plans below are complete)*

- [x] 03-24-PLAN.md — Give undo back to a Mac with no server, without opening a divergence window.
- [x] 03-25-PLAN.md — Make packaged Mac bytes reproducible so digest-bound macOS evidence survives a rebuild (Gap 1b).
- [x] 03-26-PLAN.md — Remove the macOS lane's order-dependent cross-row interference as a class, and record a reproducible A1-A15 pass (Gap 1a).
- [x] 03-27-PLAN.md — Build behavioral appearance evidence at the five named window sizes and amend the UI-SPEC evidence contract and sign-off (Gap 2).

- [x] 03-18-PLAN.md
- [x] 03-19-PLAN.md
- [x] 03-20-PLAN.md
- [x] 03-21-PLAN.md
- [x] 03-22-PLAN.md
- [x] 03-23-PLAN.md

- [x] 03-17-PLAN.md

- [x] 03-16-PLAN.md

- [x] 03-15-PLAN.md

- [x] 03-14-PLAN.md

- [x] 03-13-PLAN.md

**Wave 1**

- [x] 03-07-PLAN.md — Create the desktop workspace, process-build, and renderer-entry foundation.

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 03-12-PLAN.md — Create isolated test discovery, package-once, external-smoke, and anti-vacuous harness plumbing.

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 03-01-PLAN.md — Prove exact packaged offline capture, hard-kill relaunch, and one-time acknowledgement.

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 03-02-PLAN.md — Deliver real synchronization, namespace fencing, credentials, and one recovery projection.

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 03-09-PLAN.md — Extract the presentation-only ClientFacade and one shared workspace slice.

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 03-03-PLAN.md — Deliver the complete facade-driven Mac workspace and UI state matrix.

**Wave 7** *(blocked on Wave 6 completion)*

- [x] 03-04-PLAN.md — Deliver native menus, keyboard routing, and durable configurable Quick Entry.
- [x] 03-10-PLAN.md — Seal packaged-content and hostile renderer/IPC boundaries.

**Wave 8** *(blocked on Wave 7 completion)*

- [x] 03-11-PLAN.md — Prove resident single-instance lifecycle, restoration, bounded quit, and relaunch.

**Wave 9** *(blocked on Wave 8 completion)*

- [x] 03-05-PLAN.md — Seal hostile IPC, store-failure recovery, and safe local-data removal.

**Wave 10** *(blocked on Wave 9 completion)*

- [x] 03-08-PLAN.md — Record every D-43 packaged runtime metric and named regression budget.

**Wave 11** *(blocked on Wave 10 completion)*

- [x] 03-06-PLAN.md — Bind exact packaged bytes to CI, accessibility, and bounded dogfood evidence.

**Success Criteria**:

1. The packaged Mac application supports quick capture, Inbox, Today, edit, complete/reopen, trash/restore, and undo with complete keyboard navigation.
2. Local projection and outbox commit atomically before the UI reports success; kill/relaunch retains every accepted local intent.
3. Reconnect acknowledges each mutation exactly by identity, never silently duplicates it, and shows structured conflicts rather than overwriting.
4. The renderer has no raw database, filesystem, credential, or unrestricted IPC access; packaged-artifact tests prove the actual installed boundary.
5. Jon can use the supported Mac loop daily without opening Things for those actions.

### Phase 4: Native iPhone Daily Loop

**Goal:** Jon can dogfood the same trustworthy core loop through a native, platform-integrated SwiftUI iPhone client.
**Mode:** mvp
**Requirements:** IOS-01..04, SRV-02 (iPhone adapter proof)
**UI hint:** yes
**Plans:** 18/18 plans complete

Plans:
**Wave 1**

- [x] 04-01-PLAN.md — TRACER: normalize the wire contract, scaffold apps/ios, and capture one task end to end from simulator to real server.

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 04-02-PLAN.md — Durable local store: 11 STRICT tables, an app-owned migration ledger that halts on drift, and gates G1-G6.
- [x] 04-03-PLAN.md — The Swift sync reducer as a third independent implementation, with structural vector conformance and a cross-runtime consumer gate.
- [x] 04-04-PLAN.md — Measure whether the bottom accessory can be genuinely absent on SDK 26.5, and emit the committed Swift design tokens.

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 04-05-PLAN.md — Wire transport: decode round-trip over every vector payload, unreachable-versus-refused classification, and hand-written mappers.
- [x] 04-06-PLAN.md — Terminal settlement (G8), the durable unit and backup exclusion, and the restored-store replay-no-op fixture.

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 04-07-PLAN.md — Device-grant PKCE authentication, Keychain credentials, server-only namespace activation, and account fencing.

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 04-08-PLAN.md — The bounded sync pass, outbound commands for the full supported loop, and background execution proven to be acceleration only.

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 04-09-PLAN.md — The two-tab daily loop: lists, the locked gesture contract, task detail and conflict resolver, and the durable capture draft.

**Wave 7** *(blocked on Wave 6 completion)*

- [x] 04-10-PLAN.md — One authoritative sync presentation, the conditional bottom accessory, the Sync & Recovery sheet, and debounced announcements.

**Wave 8** *(blocked on Wave 7 completion)*

- [x] 04-11-PLAN.md — Named, timerless undo as a compensating semantic action through the server-issued handle.

**Wave 9** *(blocked on Wave 8 completion)*

- [x] 04-12-PLAN.md — Capture and Complete App Intents in the main target, sharing one store handle, with deferred surfaces provably absent.

**Wave 10** *(blocked on Wave 9 completion)*

- [x] 04-13-PLAN.md — Accessibility as release evidence: audits on every screen, the Dynamic Type matrix, Reduce Motion, and focus safety.
- [x] 04-14-PLAN.md — Deterministic state injection, the twelve-state matrix, and the held-out overflow and long-text suite.
- [x] 04-15-PLAN.md — Diagnostics that reconstruct a bad day without carrying task content, credentials, cursors, or fingerprints.

**Wave 11** *(blocked on Wave 10 completion)*

- [x] 04-16-PLAN.md — The physical-device evidence lane: signed build, read-back attestation, and real-stack recovery scenarios.

**Wave 12** *(blocked on Wave 11 completion)*

- [x] 04-17-PLAN.md — The assembled anti-vacuous iOS phase gate, the requirement-to-lane map, and one consolidated disclosures section.
- [x] 04-18-PLAN.md — Close the device blocker without weakening anything: the server-driven scenarios on the real phone over a publicly-trusted tailnet host, configuration attestation, and IOS-04.

**Success Criteria**:

1. A physical iPhone supports capture, Inbox, Today, edit, complete/reopen, trash/restore, and undo with native touch and accessibility behavior. *(Met, with one disclosed exception: every listed action except UNDO is driven on physical hardware by `DeviceCoreLoopTests`. Undo availability is minted by a server acknowledgement, so it needs the recording-proxy stack in the UI device lane; it is proven on the simulator only. See IOS-01 in REQUIREMENTS.md.)*
2. Offline mutation, termination, relaunch, expired authentication, account fencing, duplicate replay, and structured conflict scenarios preserve intent and account isolation.
3. Background execution is only an acceleration; foreground launch/resume/reconnect always restores correctness from the durable outbox.
4. Dynamic Type, VoiceOver semantics, touch targets, and Reduce Motion alternatives pass the supported user flows.
5. Jon can use the supported iPhone loop daily without opening Things for those actions.

### Phase 5: Safe Agent Access

**Goal:** External AI tools can use Keepling meaningfully without bypassing its authorization, domain rules, or recovery model.
**Mode:** mvp
**Requirements:** MCP-01..05, SRV-02 (MCP adapter proof)
**UI hint:** yes
**Success Criteria**:

1. Representative MCP hosts can read bounded Inbox, Today, Upcoming, project, task, and search resources using least-privilege authorization.
2. A direct user request can capture, update, complete, or reopen exactly one task through closed schemas and stable, model-correctable errors.
3. Ambiguous matches mutate nothing; bulk/high-impact changes require a bound exact preview and explicit commit; stale previews fail atomically.
4. User-visible history shows typed actions, affected identities/revisions, result, actor, and recovery without exposing private chain of thought.
5. Deterministic, protocol, simulated-client, representative-model, and adversarial suites score final state and forbidden side effects.

**Plans:** 9/12 plans executed in 7 waves

Plans:

- [x] 05-01-PLAN.md — Tracer: an agent grant captures one task end to end through the MCP endpoint
- [x] 05-02-PLAN.md — Authorization discovery documents and the session-gated RFC 7591 registration endpoint
- [x] 05-03-PLAN.md — Bounded search and project read surfaces, shared by HTTP and MCP
- [x] 05-04-PLAN.md — MCP read resources, redaction by construction, and the decided surface coverage
- [x] 05-05-PLAN.md — Contract-generated closed write tool schemas and the closed error vocabulary
- [ ] 05-06-PLAN.md — Identity-only write addressing, ambiguity refusal, and content-independent authorization
- [x] 05-07-PLAN.md — Preview and commit: bound tokens, atomic commits, zero partial writes
- [x] 05-08-PLAN.md — Agent actor in the one history, no storable model reasoning, and the agent undo handle
- [x] 05-09-PLAN.md — Agent grant management and agent-aware activity in the existing web app
- [x] 05-10-PLAN.md — The anti-vacuity phase gate and a test of the harness itself
- [ ] 05-11-PLAN.md — Simulated-client, adversarial, and representative-model lanes scored on final state
- [ ] 05-12-PLAN.md — The five-adapter cross-adapter proof and the restoration of SRV-02

### Phase 6: Portability and Trust Release

**Goal:** The dogfood product is portable, diagnosable, release-ready, and supported by exact cross-client evidence.
**Mode:** mvp
**Requirements:** DATA-01 and final verification of QUAL-03..05 across the released system
**UI hint:** yes
**Success Criteria**:

1. A versioned neutral export contains the complete supported user history and can be inspected without Keepling internals.
2. Exact server, web, packaged Electron, native archive, migration, backup, restore, and compatibility evidence is bound to one revision and retained.
3. Upgrade preflight, migrations, readiness, rollback guidance, doctor output, and host-replacement recovery succeed from documented operator commands.
4. Security policy, supported-version policy, SBOM/checksum/signing posture appropriate to distributed artifacts, privacy disclosures, and bounded support contract are public.
5. Jon has completed a sustained Mac+iPhone dogfood period with no unresolved data-loss, silent-overwrite, or recovery-severity defects in the supported loop.

## Candidate future milestone: Sigra identity migration

Not part of milestone v1.0. Recorded 2026-09-02 so the decision is not re-litigated.

Keepling's `apps/server/lib/keepling/accounts/` is hand-rolled (Argon2id passwords, sessions,
device grants, rate limiting, security audit). The intended eventual owner of the human-facing half
is **Sigra** (`~/projects/sigra`, `hex.pm/packages/sigra`, v1.5.0) — passkeys, TOTP MFA, social SSO
(Apple/Facebook/GitHub/Google/generic), enterprise connections, sessions, lockout, suspicious-login,
and audit.

**The two halves do not overlap.** Sigra's OAuth is *inbound* — it is an OAuth client for social
login, not an authorization server for a project's own native clients. Keepling's
`accounts/device_grant.ex` owns the *outbound* half: authorization code + PKCE for
`client_id=electron`/`iphone`, refresh rotation with replay detection, per-installation revocation,
and the locked five-field namespace tuple. Sigra does not provide that and is not trying to.

**Why this does not block Phase 3.** Plan 03-14 delegates desktop authentication to the system
browser (RFC 8252). The desktop only ever knows `browser → keepling://auth/callback → /oauth/token`.
Whatever authenticates the browser session behind `/oauth/authorize` can be replaced wholesale
without touching Electron or, later, the iPhone client. Adopting Sigra therefore *adds* passkeys,
Touch ID, and SSO to every client with zero client-side work.

**Why it is a migration, not a drop-in.** Sigra generates host-owned contexts/schemas/LiveViews;
Keepling already has a locked namespace design and a closed `security_audit` vocabulary.
Reconciling schemas, session store, and audit vocabulary is real work that would stall dogfooding if
attempted now.

## Backlog

### Phase 999.2: Follow-up — Phase 2 credentialed outer acceptance (BACKLOG)

**Goal:** Prove the deferred Plan 02-09 outer boundary — restore/runtime semantics followed by authoritative and recursive DNS cutover, propagation, rollback, and rollback propagation under the corrected image-identity contract
**Source phase:** 2
**Deferred at:** 2026-09-10 during /gsd-progress --next advancement to Phase 5
**Blocked on:** Live credentials only the owner can supply — `HCLOUD_TOKEN`, `CLOUDFLARE_API_TOKEN_FILE` + zone/record, and the primary/mirror backup credential and cipher files. This is a paid, single-attempt outer acceptance test, not a debugging loop.
**Standing rule (from `.planning/phases/KPL-02-synchronization-and-replaceable-server/deferred-items.md`):** Plan 02-09 must not gain a SUMMARY.md or a completion claim until fresh outer-boundary evidence exists. Schedules, skips, and missing credentials never count as green evidence.
**Plans:**

- [ ] 02-09: Provision and credentialedly rehearse full Hetzner host replacement and DNS cutover (planned, never executed — no SUMMARY.md by design)

**Already recorded in:** `.planning/STATE.md` (Accumulated Context), `.planning/REQUIREMENTS.md` (traceability — DATA-03, OPS-02), and the phase-2 `deferred-items.md`.

## Progress

| Phase | Status | Requirements | Progress |
|-------|--------|--------------|----------|
| 1. One Trustworthy Task | Complete    | 13 | 74% |
| 2. Synchronization and Replaceable Server | In Progress | 12 | 91% |
| 3. Mac Daily Loop | Complete    | 7 | 100% (27/27 plans, incl. 3 gap-closure plans 03-25..03-27; verified 2026-09-04 — 03-VERIFICATION.md status: passed, 5/5 must-haves. MAC-01..05 and QUAL-03..04 complete; SRV-02 deferred to Phase 5 cross-adapter proof by design) |
| 4. Native iPhone Daily Loop | Complete    | 4 | 100% (18/18 plans; verified 2026-09-10 — 04-VERIFICATION.md status: passed, 23/23 must-haves: 20 by evidence, 3 accepted by the owner as disclosed-not-proven. IOS-01..04 all complete. The full gate passes in one invocation: `lanes=24 failed=0 blocked=0`, 496 executed cases, two lanes driven on a physical iPhone. SRV-02's iPhone adapter proof is delivered but deferred to the Phase 5 cross-adapter proof by design. Disclosed residuals: SC5 daily adoption (never a gate), G7's locked-device write, the Debug-configuration substitution for the device suites, and 04-14's D9 judgment) |
| 5. Safe Agent Access | In Progress| 5 | 0% |
| 6. Portability and Trust Release | ○ Pending | 1 + cross-cutting verification | 0% |

---
*Roadmap created: 2026-08-28 after project initialization*
