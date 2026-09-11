# Phase 6: Portability and Trust Release - Context

**Gathered:** 2026-09-11
**Status:** Ready for planning

<domain>
## Phase Boundary

The final phase of milestone v1.0. It makes the built system **portable, diagnosable,
releasable, and honestly claimed**: the user can take their data out (DATA-01), the release
carries evidence bound to one revision that a third party can check, the public trust posture
(license, security policy, supported versions, privacy, support bounds, signing) exists, the
operator path works from documented commands, and the milestone's last cross-cutting
requirement (SRV-02) is closed rather than deferred a fourth time.

**In scope:** the neutral user-data export; repairing and re-authorizing CI so release
promotion is provable; macOS Developer ID signing + notarization; the release manifest and
provenance attestation; the seven public policy documents plus a machine-checked governance
lane; wiring the two BLOCKED cross-adapter legs to close SRV-02; fixing the open data-loss
class (O-43 / O-44 / O-22) and the agent-consent surface (window 76); the read-only
reconciliation oracle that makes SC5's defect-absence half a measurement; and correcting the
overclaims verification found.

**Out of scope:** new product capabilities of any kind; a hosted service or any surface built
for it; an export *importer*; TestFlight/App Store distribution; the paid credentialed
Hetzner/DNS cutover (stays a protected outer lane); Sigra identity migration.

</domain>

<decisions>
## Implementation Decisions

> **Discussion mode:** advisor (calibration tier `minimal_decisive`, per
> `~/.claude/gsd-core/USER-PROFILE.md` `vendor_philosophy: opinionated`). Six parallel
> research agents ran a breadth-and-depth multi-role sweep with an adversarial pass per
> decision point, at the owner's explicit request. Four genuinely one-way choices were put to
> the owner and all four were answered; everything else below is the synthesized decisive
> recommendation. Decisions marked **one-way** must be raised by `gsd-planner` as
> `checkpoint:decision` before the task implementing them.
>
> **A standing instruction for every downstream agent, learned the hard way in this very
> discussion:** the open-item ledger is NOT truth. Six of the residual items handed to
> research were stale — already closed in shipped source while still recorded `open`. Verify
> against source before acting on any recorded status, including the statuses in this file.

### Neutral export (DATA-01)

- **D-01 — Content rule: "authored or durable account history" is IN; derived, credential, or
  protocol mechanism is OUT.** IN: tasks in every state (active, completed, trashed), projects
  and tags including archived ones and membership, per-task activity, open conflicts, Today
  ordering, account settings, and the access inventory (device grants and MCP registrations,
  metadata only). OUT: command and Today-order receipts, `sync_changes`, `undo_handles`,
  sessions, `sync_epochs`, `operations_state`, `restore_verifications`, `account_recovery`,
  `task_search_index`, and resolved conflicts. *Rationale:* activity is explicitly canonical
  account-lifetime **user** data in this product, so omitting it would fail SC1's "complete
  supported user history" outright; receipts and feed rows are idempotency and transport
  mechanism whose user-visible outcome already lives in `task_activities`; undo handles and
  credentials exist only as hashes, so exporting them exports noise. Exporting all 22 tables
  would be a `pg_dump` with a new name and would duplicate DATA-02.
- **D-02 — Format: a zip bundle of `manifest.json` + `data/<entity>.ndjson` per type +
  `FORMAT.md` + a human-readable `tasks.md`.** Streamable in both directions, so bounded
  memory; `jq -c` / `grep` / `wc -l` work per line; line-oriented diffs are meaningful;
  `tasks.md` is readable with no tools at all, which is what "inspectable without Keepling
  internals" literally means. Prior art converges here (1Password `.1pux`, Google Takeout,
  Joplin JEX, Day One). Rejected: a single JSON document (unbounded memory, one-byte
  corruption kills it, useless diffs), SQLite (needs a tool, re-exports internals), CSV-only
  (lossy for the nested `actor: %{label, principal, type}`), and iCalendar VTODO — RFC 5545
  plus RFC 9253 cannot carry `inbox_state`, activity, agent actors, or the independent
  `planned_on`/`deadline` pair, so adopting it would be cargo cult that loses data.
- **D-03 — The export schema is its OWN JSON Schema under
  `packages/contracts/schemas/export/`, NOT a reuse of `openapi/keepling.yaml` shapes.** —
  **Reversibility:** one-way — a published archive format is what users' five-year-old files
  are written in. *Rationale:* the wire protocol is deliberately allowed to evolve on protocol
  trains **with age-out**; an archive format may never age out. Living in `packages/contracts`
  still buys `pnpm contracts:check` drift gating without coupling the archive's lifetime to
  the protocol's.
- **D-04 — Versioning: a standalone integer `export_format_version` in `manifest.json`,
  starting at 1, decoupled from OpenAPI and from protocol trains; additive-only within a
  version; no age-out, ever.** `keepling_version` and `generated_at` are recorded as
  provenance only — readers MUST key off `export_format_version` alone. — **Reversibility:**
  one-way — the compatibility promise attaches to files already in users' hands.
- **D-05 — Delivery: a new non-destructive `export` verb in `Ops.@verbs`, synchronous,
  streaming to a file path.** In this single-user self-hosted product the user *is* the
  operator; this reuses the proven ops envelope and exit-code machinery, adds no network
  surface, has no HTTP timeout, cannot be a DoS amplifier on a small Hetzner VM, and is
  trivially automatable (which suits the zero-manual-verification rule). An authenticated
  HTTPS download is deliberately **deferred to the hosted-convenience milestone**, where it
  becomes necessary rather than speculative. *Flip condition:* if hosted Keepling is committed
  to within this milestone, build both surfaces over one application command now — retrofitting
  re-auth, rate limiting and async job state onto a shipped ops verb is strictly more work.
- **D-06 — Agents may never export, and this needs no new enforcement.**
  `apps/server/lib/keepling/application/agent_scope.ex:16` is a closed three-string whitelist
  (`tasks.read tasks.write tasks.bulk`) and `require/2` admits only `scope in @agent_scopes`,
  so an `export` scope cannot be granted even if one were persisted. Add one cheap regression
  asserting `"export" not in AgentScope.scopes()` and that the ops path has no MCP adapter.
- **D-07 — Proof: a four-part lane, and NO importer.** (1) **Schema-driven completeness** —
  enumerate `information_schema.columns` and fail on any column absent from the IN/OUT
  classification manifest, so a new migration cannot silently omit a field. (2) **Golden export
  vector** — a fixture account, byte-compared, with fully specified ordering. (3) **Independent
  reader** — a `tooling/` Node script sharing **zero** Elixir code that validates every NDJSON
  line against the schema, checks manifest sha256 and row counts, and reconstructs the task
  list; registered in `packages/contracts/vectors/manifest.json` following the
  `mcp-injection.json` precedent. (4) **No-secrets assertion** grepping the bundle for known
  credential fixtures. *Why no importer:* it is a permanent second compatibility surface plus
  zip-bomb, path-traversal and ID-collision attack surface, and it proves only
  self-consistency — which is exactly the failure mode of formats only the product can read.
  The independent reader proves inspectability better and costs less.
- **D-08 — Export hazards that must be handled explicitly.** (a) **Coherence:** run the whole
  export in one `Repo.transaction` at `REPEATABLE READ` and record the sync-feed high-water
  sequence and restore epoch in `manifest.json`, so the file is a citable point in the existing
  ordered feed rather than a smear. (b) **Timeout truncation — verified footgun:** do NOT reuse
  `:task_view_query_timeout_ms`; it is `fetch_env!`-mandatory and positive
  (`adapters/postgres/task_views.ex:693`, `projects.ex:196`, `search.ex:93` all raise unless
  positive) and would silently kill a large-account read. Use a distinct
  `:export_query_timeout_ms` (or `:infinity` on the stream) with explicit `max_rows` chunking.
  (c) **Silent partials:** write `manifest.json` LAST, with per-file sha256 and row counts, so
  a truncated bundle fails its own validator. (d) **Determinism:** order every file by stable
  opaque ID or feed sequence, canonical JSON key order, UTC ISO-8601, civil dates as plain
  `YYYY-MM-DD`. (e) **Privacy:** the bundle is the richest plaintext artifact in the product —
  write `0600`, state plainly in `README.md` that it is unencrypted and is NOT a backup
  (DATA-02 is), do not invent at-rest encryption, and emit a `security_audit` event per export.
  (f) Scope every query by `account_id` even though the product is single-account.

### CI, release evidence, and promotion authority (QUAL-02, QUAL-03, SC2)

- **D-09 — Authority: CI is authoritative for every lane it can physically run; a closed,
  committed set of named lanes is `local-attested`; and a `local-attested` lane is valid only
  if its evidence records the CI-attested artifact digest it ran against.** The anti-loophole
  rule, stated so it cannot be argued around: **nothing local may bind to locally built bytes.**
  A lane therefore cannot be moved out of CI to make it green, because the local path requires
  a CI artifact to exist first. *Rationale:* "the local gate is the only authority" was a forced
  disclosure (O-35), not a design; but "CI is truth" is also false, because CI cannot hold a TCC
  Accessibility grant or drive a physical iPhone. *Flip condition:* a self-hosted macOS runner
  on Jon's own Mac with a persistent TCC grant collapses the `local-attested` set to iOS-device
  and live-Hetzner only.
- **D-10 — The red CI is a hard precondition, fixed, not narrowed.** All four root causes are
  verified and shallow, and all four are the same bug class — works on the maintainer's Mac:
  1. `tooling/runtime-preflight.sh:99-107` `provision_runtime()` calls `asdf install erlang`
     with no `asdf plugin add`. Add idempotent `asdf plugin add erlang|elixir|postgres || true`.
     Unblocks 5 phase-2 jobs and both recovery-drills legs.
  2. `tooling/test-phase-2.sh:109` shells out to `rg`, absent from `ubuntu-24.04`. Replace with
     `grep -E`. Do NOT install ripgrep — a tool present on the Mac and not the runner IS the bug.
  3. The artifact-transport digest failure (D-11).
  4. `apps/desktop/test/e2e/lifecycle.spec.ts:256` asserts window-bounds clamping against the
     owner's display geometry. Assert relative to the runner's actual display bounds.
  Also move `phase2-server`, `phase2-sync-property`, `phase2-backup-restore` off `macos-15`
  onto `ubuntu-24.04` with a PostgreSQL service container — nothing about Elixir needs macOS.
  Narrowing to "green core plus informational lanes" is explicitly rejected: that is the exact
  vacuity pattern Phase 4 was burned by.
- **D-11 — Cross-machine reproducibility is NOT the requirement; build-once/promote-many is.**
  — **Reversibility:** costly — every macOS evidence row binds to `applicationDigestSha256`.
  *The decisive empirical fact:* in run `34561455069`, `desktop-packaged` failed with "copied
  application digest does not match the package manifest" — the `.app` changed digest crossing
  an `actions/upload-artifact` boundary **inside a single run on one runner image**, because
  the zip round-trip does not preserve POSIX mode and `smoke-desktop-packaged.mjs:64-77` hashes
  `mode.toString(8)`. **The binding is correct and caught a real transport defect; fix the pipe,
  not the binding** — the same ruling O-40 already made once. Use
  `ditto -c -k --sequesterRsrc --keepParent` out and `ditto -x -k` in, hash the archive AND
  re-verify the expanded tree, and add `archiveDigestSha256` to the manifest. Machine-independent
  digest equality for a macOS app bundle is rejected as an open-ended sink that would end in a
  loosened binding. **Keep `tooling/verify-package-reproducibility.mjs`, but restate its claim
  precisely: deterministic across separate invocations on ONE machine at ONE revision.** It is a
  nondeterminism canary and must never be written up as cross-machine reproducibility.
- **D-12 — "Bound to one revision" is operationalized as a `release-manifest.json` plus a
  verification command.** The manifest carries `revision` (full SHA, ref, runId); `artifacts[]`
  as `{name, kind, digestSha256, archiveDigestSha256, builtByRunId, builtByJob, runnerImage}`
  for the Electron `.app`, the iOS archive, the server OCI image and the web bundle; and
  `lanes[]` as `{lane, status: PASSED|BLOCKED|NOT_RUN_ON_FORK, cases, skipped, seed, elapsedMs,
  inputsSha256, evidenceDigestSha256, ranAgainstArtifactDigest}`. A new
  `tooling/verify-release.mjs --manifest <path>` (1) verifies each attestation, (2) recomputes
  every present artifact digest, (3) asserts every lane in a committed `tooling/release-lanes.json`
  inventory appears **exactly once** — a lane that *vanished* is a hard fail, not a pass — (4)
  asserts every `PASSED` lane's `ranAgainstArtifactDigest` exists in `artifacts[]`, and (5)
  asserts `cases > 0` for every `PASSED`. A missing artifact yields `INCOMPLETE`, never a pass.
  This **extends** the existing digest machinery rather than replacing it.
- **D-13 — Retention: anything whose only copy is a GitHub Actions artifact is NOT retained.**
  Current retentions are 14/30/90 days (`desktop.yml:72,227`; `recovery-drills.yml:80,130,160`;
  `repository-integrity.yml:42,82,106,123`), and SC2 says *retained*. The manifest and evidence
  bundle are committed to `.planning/releases/<tag>/` and attached as GitHub Release assets,
  which do not expire.
- **D-14 — Lane assignment.** *Required on PR + main (ubuntu):* `check-ci-contract.mjs`,
  `check-repository-integrity.sh`, `check-contracts.mjs` + MCP schema check, web lint/typecheck,
  desktop typecheck, the pure/store/worker/ipc vitest lanes, `test-phase-1.sh`,
  `opentofu-host-fixtures`, `test-image-archive-contract.sh`, `verify-image.sh`,
  `verify-compose.sh`, `verify-deploy.sh`, `test-plan-shape-contract.sh`,
  `test-resolved-plan-contract.sh`, `test-provider-ownership.sh`, `test-ops-cli.sh`, the
  host-bootstrap fixture tests, `verify-privacy.sh --self-test`, `mcp-gate-selftest.mjs`,
  `verify-mcp-phase.mjs` (non-model), `verify-cross-adapter-phase.mjs`, `test-compatibility.sh`,
  and the relocated phase-2 lanes. *Required on main (macOS):* `package-desktop.mjs` → attest →
  `smoke-desktop-packaged.mjs` → packaged Playwright → `desktop-e2e` →
  `verify-macos-integration.mjs` no-grant rows → `verify-package-reproducibility.mjs` →
  `--promote`; plus iOS simulator lanes and `build-ios-signed.mjs` (secrets — main only, never
  forked PRs). *Nightly:* `recovery-drills.yml`, the full `test-phase-2.sh` sweep, lane-inventory
  drift recheck. *On-demand (`workflow_dispatch`, main):* `verify-real-stack-desktop.mjs`,
  `verify-real-stack-ios.mjs`. *Never in CI, named BLOCKED contract:* `verify-macos-integration.mjs`
  full-grant rows (needs a non-interactive TCC Accessibility grant, impossible on hosted
  runners — keep the existing "report what TCC this runner actually grants" step at
  `desktop.yml:187`, which converts the impossibility into published evidence);
  `verify-ios-phase.mjs --lane device` and `verify-real-stack-ios.mjs` device rows (physical
  unlocked iPhone); `verify-mcp-phase.mjs --lane representative-model` (real model credential,
  non-deterministic third party); `live-host-dns-acceptance` (Plan 02-09, paid credentials,
  single-attempt). Each emits `status=BLOCKED cases=0 reason=<physical>` into the manifest.
- **D-15 — Structural closes for the ways a green badge becomes a lie.** (a) **Skipped counts as
  success** — GitHub treats a required check skipped by `if:` or a path filter as satisfied.
  `check-ci-contract.mjs:106` already bans `paths:`/`paths-ignore:`; extend the ban to `if:` on
  any required job, and make the single required check an `all-required-passed` aggregator with
  `if: always()` that explicitly asserts every `needs.*.result == 'success'`. (b) **Forked PRs**
  report `NOT_RUN_ON_FORK`, never omission — omission reads as a pass. (c) **Forbid restored
  caches in any artifact-producing job**; caching stays for test lanes only. (d)
  `verify-release.mjs` must work fully **offline** against the committed bundle, degrading only
  the attestation step to `attestation=UNVERIFIED`, printed loudly — so a GitHub outage costs the
  provenance half, not the ability to state the claim. (e) Branch protection ON with **no admin
  bypass**; with one contributor its job is not to stop strangers, it is to stop the maintainer
  at 2am.

### Signing, SBOM, and supply-chain posture (SC4, part)

- **D-16 — macOS: Developer ID + hardened runtime + notarize + staple. The marginal cost is $0.**
  Verified: `apps/desktop/forge.config.ts` has no `osxSign`/`osxNotarize`/entitlements today, and
  `tooling/build-ios-signed.mjs:348-366` refuses profiles with ≤30 days validity while stating a
  paid Apple Developer Program membership is required — **the $99/yr gate is already cleared.**
  On macOS Tahoe the Control-click Gatekeeper bypass is gone, so today's unsigned download reads
  *"Keepling is damaged and can't be opened"* — indistinguishable from malware to a self-hoster.
  Highest user-visible payoff in this whole area.
- **D-17 — THE SIGNING-INVALIDATES-THE-TESTED-DIGEST TRAP, and its exact resolution.** —
  **Reversibility:** one-way — getting this wrong ships a different file than the one every gate
  tested, with every gate green. `tooling/package-desktop.mjs:326` computes
  `applicationDigestSha256 = hashDirectory(applicationPath)` immediately after Forge emits the
  `.app`. Therefore: (a) **signing must run INSIDE Forge's `package` step** (`osxSign` via
  `@electron/osx-sign`), so `hashDirectory` observes the *signed* bundle and the ZIP is made from
  it; (b) notarization and stapling mutate the bundle again, irreducibly, after the digest exists
  — so record `codeDirectoryHash` (from `codesign -dvvv --verbose=4`) in the manifest as the
  identity that **survives stapling**, keep `applicationDigestSha256` as the pre-staple signed
  digest, and gate on the stapled artifact's CDHash equalling the tested one; (c) do NOT try to
  make `hashDirectory` stable across stapling; (d) never re-package after notarizing; (e) use
  per-helper entitlements for Electron's nested helpers and **never `codesign --deep`**.
- **D-18 — iOS: no change. Keep development-signed + `devicectl`.** Verified:
  `build-ios-signed.mjs:42-48,302-304` uses `method=development`, and `docs/testing/ios-dogfood.md:67`
  records TestFlight/App Store as deferred to Phase 6 — this is that deferral being decided, as
  "no". TestFlight's 90-day build expiry reintroduces a recurring manual step, which is exactly
  what the zero-manual-verification rule exists to remove; App Review also carries real risk for
  an app whose premise is connecting to a user-supplied self-hosted server. *Flip condition:* a
  second human wants the iPhone app — then go straight to TestFlight.
- **D-19 — Server OCI image: cosign keyless via GitHub OIDC on the pushed digest.** Base images
  are already digest-pinned (`infra/images/server/Dockerfile:3-4`). Keyless avoids a solo
  maintainer's key-custody single point of failure entirely. No GPG tag signing — solo GPG
  custody is a pure liability.
- **D-20 — SBOM: honest partial, with a named declared gap.** CycloneDX (what the Elixir
  ecosystem actually generates) from source for Hex (38 locked) and npm (915 resolutions);
  **published lockfiles only for Swift, with the gap declared out loud.** Verified reasons:
  `apps/ios/Package.resolved` is `"version": 3`, which syft cannot parse
  ([anchore/syft#2759](https://github.com/anchore/syft/issues/2759)), and SwiftPM-native SBOM is
  still only a proposal (SE-0509). Worse, an SBOM scanned from the *built* `.app` would be
  near-empty because `forge.config.ts` sets `ignore: /node_modules/` and ships four bundled
  outputs — a 3-entry SBOM for a 915-dependency app is precisely the vacuous green this project
  has been burned by twice. Generate per-release, from source, inside `desktop-promote` at the
  revision the manifest records. *Flip condition:* the hosted business ships, making Jon a CRA
  manufacturer rather than a steward. **The CRA does not apply to Keepling today** — a natural
  person cannot be a steward and a non-commercial personal project is out of scope.
- **D-21 — Checksums: SHA-256 for the ZIP and the stapled `.app`, in the GitHub Release body and
  nowhere else** — a checksum served from the same origin as the artifact is worthless; GitHub
  Releases is a different trust domain from the self-hosted server, which is the only thing that
  gives it value. **Word it honestly:** the load-bearing controls are the reproducibility lane
  and the provenance attestation, not a hash users will never check.
- **D-22 — Provenance: emit `actions/attest-build-provenance` from `desktop-promote` and claim
  exactly "SLSA Build Level 2."** L3 needs a reusable workflow with isolated signing; build and
  attest currently share a job, so **claiming L3 would be an overclaim.** Requires adding
  `id-token: write` and `attestations: write` to `desktop.yml` (verified absent: it has
  `contents: read` only).
- **D-23 — Publish the honest threat-model statement.** The realistic adversary for a pre-users
  personal GTD app is a **malicious dependency update**, and every control above would happily
  sign it. What addresses that adversary is the existing enforced provenance-review culture.
  Signing addresses Gatekeeper UX and post-distribution tampering; provenance addresses "did this
  come from that repo"; SBOM addresses "what is in it, later." Three different claims — the README
  must not conflate them.

### Open-source governance and public policy (SC4, remainder)

- **D-24 — License: Apache-2.0, SPDX `Apache-2.0`, uniform across the entire monorepo.**
  **[OWNER-ANSWERED 2026-09-11]** — **Reversibility:** one-way — a license cannot be retracted
  from copies already distributed. *Rationale:* it matches the author's newer Elixir convention
  (crosswake, lockspire, scrypath, oban_powertools are Apache-2.0 on hex.pm); its explicit patent
  grant with defensive termination is material for a codebase shipping a hand-rolled OAuth 2.1
  authorization server, PKCE, refresh rotation and Argon2id; §6 withholds trademark rights,
  protecting the Keepling name without a separate policy; §5 makes inbound contributions
  same-terms automatically, which removes the main reason to want a CLA; and it leaves every
  future option (hosted service, App Store, dual-license, acquisition) open. Uniform means no
  per-package reasoning ever — the usual "make the client library more permissive" move exists
  to fix copyleft friction that Apache-2.0 does not have. **AGPL-3.0 was rejected on a concrete
  ground:** GPL-family terms conflict with App Store Usage Rules, so the iPhone client is
  shippable today only because Jon is sole copyright holder, and the first AGPL contributor to
  touch shared code would make App Store distribution require their permission forever. BSL/FSL/
  Elastic-2.0 were rejected because the README already claims "complete open-source personal
  product," and a non-OSI license under that sentence is precisely the overclaim this project's
  culture exists to prevent. *Flip condition (both halves required, neither true today):* hosted
  Keepling becomes the primary revenue model AND the iPhone client is permanently distributed
  outside the App Store.
- **D-25 — Contributor agreement: DCO 1.1, enforced by a lane. No CLA.** — **Reversibility:**
  one-way in effect — you can never unilaterally relicense without every contributor's consent.
  *Rationale:* Apache-2.0 §5 already supplies the inbound copyright *and patent* grant, so the
  DCO only has to carry **provenance** — which is the live risk for an AI-built, AI-native
  project: a contributor or their coding assistant pasting GPL/AGPL code in. A CLA buys the
  unilateral relicense right, which under Apache-2.0 is nearly worthless (you can already run a
  closed hosted service, ship to the App Store, dual-license your own copyright, and be acquired)
  and whose historical exercise is exactly what triggered HashiCorp→OpenTofu and Redis→Valkey.
  Add to CONTRIBUTING.md: *"If an AI assistant wrote part of your contribution, sign off anyway —
  the sign-off is your assertion that you have the right to submit it, and that assertion is
  yours to make, not the tool's."*
- **D-26 — License mechanics.** `LICENSE` (verbatim Apache-2.0) and `NOTICE` (minimal: project
  name + `Copyright 2026 Jon <szTheory>` only — NOTICE content is legally sticky and propagates
  downstream) at repo root. **No per-file Apache headers** — `SPDX-License-Identifier: Apache-2.0`
  only, following the author's own `kiln` pattern. Metadata fields are load-bearing and must land
  BEFORE the SBOM is generated, because CycloneDX component license fields are populated from
  exactly these strings: root `package.json`, all three `packages/*`, `apps/web`, `apps/desktop`
  get `"license": "Apache-2.0"`, and `apps/server/mix.exs` gets a `package/0` with
  `licenses: ["Apache-2.0"]` even though it is not published to Hex. *(Note: the brief's
  `packages/api-client-ts` and `packages/client-core-ts` do not exist — `packages/` is
  `contracts`, `design-tokens`, `web-ui`.)*
- **D-27 — SECURITY.md at repo root; GitHub private vulnerability reporting as the ONLY channel.**
  Matches the author's existing `sigra/SECURITY.md` house style (private reporting, deliberately
  no SLA, plus Security Invariants and Security Non-Goals tables — reuse that structure). No
  published security email: an unmonitored or bouncing address is worse than none. **Commit to no
  response time at all, and instead publish a bound in the reporter's favour** — "if fourteen days
  pass with no acknowledgement, assume I am unreachable and disclose publicly without further
  notice to me." You cannot breach a promise you did not make. Include a safe-harbour statement
  scoped to instances the researcher owns, and note it cannot bind a self-hoster's instance.
- **D-28 — The prompt-injection scope boundary, drawn at AUTHORITY rather than persuasion.**
  **In scope as a vulnerability:** content in a task, note, or tool result that causes action
  outside the calling agent's granted scopes, bypasses preview or undo, causes an unconfirmed
  write where confirmation is required, exfiltrates data the agent was not scoped to read, or
  reaches the model despite a redaction guarantee. **Out of scope by design:** that a model can
  be made to produce wrong, rude, or manipulated *text*. Keepling does not claim its models are
  uninfluenceable; it claims the authorization boundary holds regardless of what the model was
  convinced to want. A report that defeats the existing adversarial injection lane is the most
  valuable report this project can receive — say so.
- **D-29 — Supported-version policy is DERIVED from the existing protocol-train machinery, never
  invented beside it.** The unit of support is the **protocol train**, not the marketing version:
  supported = current train + immediately previous train, the same window the sync layer already
  enforces. End of support is the inclusive deprecation deadline already published by
  `/compatibility`, which is the machine-readable source of truth; the SECURITY.md table is a
  **generated or checked** human mirror, never hand-maintained. Carry the recorded security-
  emergency exception forward and make it auditable: a floor raise without a simultaneously
  published advisory is a bug in the policy's execution, and readers should report it as one.
  **Pre-1.0 honesty line:** "Keepling has not had a first release. Until it does, the supported
  set is empty and this table says so. It will not list a version that was never published."
- **D-30 — PRIVACY.md at repo root (not `docs/` — GitHub does not surface `docs/`), written as
  CLAIMS WITH EVIDENCE POINTERS.** This is the differentiator: almost every privacy policy is a
  promise; this one can cite a lane. A table of claim → enforcing mechanism → verify-it-yourself
  path (`packages/contracts/vectors/redaction.json`, `tooling/verify-privacy.sh`, the D-21
  storage-level test module). State the controller boundary plainly — a self-hoster is their own
  controller, there is no controller-processor relationship with the author, and neither GDPR nor
  CCPA attaches to him by virtue of their use. **Pre-write the hosted boundary now, before the
  service exists, so it cannot later be blurred:** nothing in PRIVACY.md may be cited as the
  privacy policy of any hosted service.
- **D-31 — SUPPORT.md states what is NOT promised, and includes the abandonment clause almost
  nobody writes.** No response-time commitment for issues, PRs or discussions; no paid support,
  consulting or SLAs (out of scope, not merely unavailable); no help operating your deployment;
  no feature requests by default; no commitment to accept pull requests. Then the counterweight:
  *"Because Keepling is Apache-2.0, none of the above can strand you… the licence is the support
  guarantee."* And: if the project goes quiet the README says so and the repo is archived; **six
  months of no commits and no maintainer replies means treat it as unmaintained whether or not a
  notice appeared**; your data comes with you because the export path is tested; forking is
  pre-blessed (rename it — the licence does not grant the Keepling name).
- **D-32 — File layout and the anti-drift lane.** Root: `LICENSE`, `NOTICE`, `SECURITY.md`,
  `SUPPORT.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` (Contributor Covenant 3.0 **with the
  enforcer named** — a CoC with no named enforcer is the policy equivalent of a lane that cannot
  fail), `PRIVACY.md`, `KNOWN-LIMITATIONS.md`. `.github/`: issue-template routing, PR template
  with the DCO checkbox. **Skip `FUNDING.yml`** (a funding button invites the expectation
  SUPPORT.md just disclaimed) and **skip `CITATION.cff`** (not an academic artifact; another file
  to rot). **The lane — this is what stops five documents written in one afternoon from rotting:**
  extend `tooling/check-repository-integrity.sh` (already wired into
  `.github/workflows/repository-integrity.yml`) with a `governance` lane asserting every file
  exists and is non-empty; `LICENSE` hashes to canonical Apache-2.0; every `package.json` and
  `mix.exs` declares `Apache-2.0` with no `UNKNOWN`; the SECURITY.md supported-versions table is
  byte-identical to one rendered from the `/compatibility` fixture; **every claim row in
  PRIVACY.md names an evidence path and every named path exists** (delete `redaction.json` and
  the privacy claim goes red — that is the point); and if the lane cannot read the
  `/compatibility` fixture it reports **BLOCKED**, not pass.
- **D-33 — CVE posture: opt in, narrowly.** Enable private vulnerability reporting and GitHub
  Security Advisories; request a CVE from GitHub (CNA, ~72h) for any confirmed vulnerability in a
  **released, distributed artifact with a shipped fix**. Do NOT request CVEs for pre-release
  main-branch issues — that is "counts must mean what they say" applied to advisories. Publishing
  an advisory is also what makes GitHub dependency alerts notify self-hosters, which answers "how
  do I learn about a security update."

### Residual disposition and the honesty of the release claim (SC2, SC3, SC5)

- **D-34 — The classification rule. Five classes, applied in order, first match wins; and every
  class except `closed` NAMES AN OWNER.** (1) **MUST-CLOSE** — the item is in the data-loss /
  silent-overwrite / unrecoverable class named by SC5, OR is a *checked* claim verification shows
  false, OR is the last unproven clause of a requirement this milestone's traceability assigns to
  this phase. (2) **CORRECTED-OVERCLAIM** — a subset of the above, executed as the **first act of
  the phase**, before any new plan runs (the Phase 5 D-28 precedent). (3) **DISCLOSED-NOT-PROVEN**
  — mechanism built and locally proven; only an environment or authority the owner cannot supply
  hermetically is missing. Requires a named blocker, **a named command that would close it**, and
  a `KNOWN-LIMITATIONS.md` line. Never satisfies a checkbox. (4) **PROTECTED-OUTER-LANE** — must
  exist, must never report green without fresh outer evidence, expected to be non-passing; the
  lane's own non-zero exit is the enforcement, not a document. (5) **BACKLOG-WITH-STANDING-RULE**.
- **D-35 — The anti-"unowned" clause, which is the structural fix this phase most needs.** — **
  Reversibility:** one-way in effect — it changes what a verifier is permitted to pass. A class
  3/4/5 disposition is **invalid** unless it names a `.planning/WINDOWS.md` row and an owner that
  is either a phase number or `BACKLOG`. **`"Unowned"` is not a legal value.** Phase 6's
  verification must fail if any open window has an empty owner field. Corollary: **a verifier may
  not pass a phase N/N while recording a BLOCKED lane whose owner is not another named, existing
  phase.** This is exactly what happened to SRV-02 at `05-VERIFICATION.md:49` and is the pattern
  most worth killing.
- **D-36 — SRV-02: Phase 6 owns wiring the electron and iphone cross-adapter legs.**
  **[OWNER-ANSWERED 2026-09-11]** Both are **wiring over harnesses that already exist**, not
  invention. The electron leg mirrors `apps/desktop/test/real-stack/real-stack-sync.spec.ts`
  (packaged app, disposable profile, real adapter), invoked from `tooling/cross-adapter/legs.mjs:291`.
  **Correction to the ledger:** `WINDOWS.md` row 69 cites
  `apps/desktop/test/packaged/real-stack-sync.spec.ts` — that path does not exist; the file is at
  `apps/desktop/test/real-stack/real-stack-sync.spec.ts` (verified). The iphone leg mirrors
  `tooling/ios-device/server-driven-run.mjs:214-266` against the booted simulator on host
  loopback. Shared refactor: `legs.mjs:73-179` must let a leg mint its own task id and must
  advance the revision out-of-band for scenario 4. **`verify-cross-adapter-phase.mjs:36-47`'s
  guard-refusal checks MUST be extended to the new driver files, or the lane loses its
  anti-vacuity teeth.** SRV-02 is checked only when `legs_blocked=0`. *Rationale for owning it:*
  deferring makes three prior phases' deferrals permanently unpaid, so "Phase 3 complete" and
  "Phase 4 complete" would rest on a promise never kept. **Forbidden resolution:** narrowing
  SRV-02's text to the two proven adapters — that is renaming the requirement to match the
  evidence, the exact move D-28 exists to forbid. *Flip condition:* if a spike shows the iPhone
  leg cannot drive capture/complete/reopen with a caller-chosen expected revision **without a
  test-only affordance inside the shipped app**, the iphone leg becomes class 3 with a named
  backlog owner and SRV-02 stays unchecked. **Adding a test-only command surface to the shipped
  iOS app to make this lane green is forbidden** — that is Phase 4's vacuity failure mode.
- **D-37 — The data-loss class, ruled as one coupled unit. SC5 cannot be signed with O-43 or O-22
  open.** The product's stated core value is literally "accepted changes are never silently lost
  or overwritten"; `apps/desktop/store-worker/local-store.ts:727-743` is a comment in **shipped
  code** describing exactly that happening ("the NEXT pull replays the shadow and the local value
  is lost"), and `apps/desktop/renderer/DesktopShell.tsx:54,61,64` is a keystroke that walks past
  `packages/web-ui/src/workspace/Workspace.tsx:254-265`'s dirty-state dialog. **Minimum honest
  fix:** refused bytes plus the person's value land in a durable table **for every refusal
  outcome, not only title divergence**; the pull path refuses to overwrite an unresolved refusal;
  the desktop conflict chooser covers lifecycle/Trash divergence (O-44 is not separable — a
  durable record the user cannot act on is not a fix); and keyboard navigation routes through
  `attemptNavigation`. **O-22 has no `WINDOWS.md` row at all — file one first; an untracked
  data-loss defect is itself the finding.** O-51 is already closed, so the recorded "decide O-43
  and O-51 together" instruction is satisfied, not pending.
- **D-38 — Window 76 (agent consent UI) is MUST-CLOSE.** A phase named "Trust Release" cannot ship
  a consent screen that renders "Not yet reported" for what an agent may do and when it last did
  it. Publish `scope`, `authorized_at`, `last_used_at` from `Keepling.Accounts.DeviceGrant` and
  widen `DeviceGrantSummary` in `packages/contracts/openapi/keepling.yaml`. **Preserve the
  distinction the 05-UI-REVIEW fix established: an absent scope key means UNKNOWN, an empty array
  means GENUINELY NO SCOPES — opposite claims on a consent screen, never to be collapsed again.**
- **D-39 — `receipt-scope-inversion` (window 73) is MUST-CLOSE, not a known limitation.** "Not
  enumerable" is a coincidence of UUIDv4 choice, not a control — one leaked mutation id from a
  log, a URL, or a future API turns it live. Fix is small and local (`keeplingweb/auth.ex:200`
  plus `Commands.lookup_result/3`): bind receipt reads to the grant that issued the mutation,
  which is what D-49's own wording ("the authority that could have issued it") actually argues
  for.
- **D-40 — SC3 is narrowed in writing; the credentialed live run stays a protected outer lane.**
  **[OWNER-ANSWERED 2026-09-11]** Hermetic rehearsal becomes the gate —
  `tooling/verify-host-replacement.sh` and `tooling/test-host-replacement-sequence.sh` already
  produce real recovery evidence. The live Hetzner/DNS cutover keeps exiting non-zero, so no skip
  is ever counted as evidence. **DATA-03 and OPS-02 stay unchecked**, which is honest. Requires a
  **dated** SC3 amendment in `ROADMAP.md`, a `KNOWN-LIMITATIONS.md` entry, and `WINDOWS.md` row 43
  gaining owner `BACKLOG/999.2`. *Flip condition:* the owner volunteers the credentials and
  accepts a one-shot outcome — do not plan the phase around it.
- **D-41 — Corrections owed as the FIRST act of the phase, before any new plan runs.**
  1. **Uncheck QUAL-02** (`.planning/REQUIREMENTS.md:72`). Its disclosure says CI has never
     executed; CI now executes and fails **17/17** on two workflows. The disclosure is now
     factually wrong *in the project's favour*, which is the worst direction for it to be wrong.
  2. Set the owner field on `WINDOWS.md` row 69 to `Phase 6`, and reject `"Unowned"` at
     `05-VERIFICATION.md:49` as an invalid disposition.
  3. Resolve stale window 59 (O-45/O-51 are closed — verified at
     `apps/desktop/main/application/DesktopApplication.ts:466-517`); delete the stale blocker
     prose at `STATE.md:368` (O-21, closed at `apps/desktop/main/index.ts:911-918`) and
     `STATE.md:370` (O-51).
  4. File a new `WINDOWS.md` row for O-22.
  5. Amend SC3 in `ROADMAP.md` with a dated narrowing.
  6. **Split `REQUIREMENTS.md`'s grouped traceability rows into one row per REQ-ID (window 75)
     BEFORE any `phase complete` runs again** — that tool has twice checked SRV-02 against its own
     stated precondition, and leaving it is leaving a machine that manufactures overclaims.
- **D-42 — `KNOWN-LIMITATIONS.md` is GENERATED from `WINDOWS.md` rows, never hand-written**, so it
  cannot disagree with the ledger or quietly become a graveyard.
- **D-43 — Other dispositions.** MUST-CLOSE: window 68 (flaky web e2e — flake accountability is
  QUAL-02's own text, and a known-flaky required lane at a release boundary is how green evidence
  stops meaning anything); window 71 (implicit login budget in `config/test.exs`). KNOWN-LIMITATIONS:
  `preview-token-is-account-bound-not-grant-bound`; windows 60/61 (two of thirteen desktop
  presentation states have no production construction site — **do not wire speculatively**; the
  iOS half closed in Phase 4). CLOSED-BY-DECISION: `rfc8707-audience-not-enforced-outside-mcp` —
  write the decision record, do **not** add the audience check. DISCLOSED-NOT-PROVEN, owner
  `BACKLOG`: window 63 (G7 locked-device write — no programmatic lock control exists).

### The SC5 trust gate

- **D-44 — The existing dogfood contract is EXTENDED, never replaced, and the human half is
  untouched.** `docs/testing/ios-dogfood.md:110-115` already ruled: *"Criterion 5 — sustained
  daily use. Not automatable, and not a gate… Sustained daily adoption is owner dogfood feedback,
  not a gate. Nobody signs off on it and nothing counts it."* `docs/testing/desktop-dogfood.md:3-20`
  fixes the shape: no checklist, no gate, no sign-off, no required cadence or duration or
  active-day count. **That ruling stands.** What it left open is that SC5's defect-absence half
  was never measured by anything — which under this project's own evidence culture is the
  green-but-untrue failure it has twice corrected. The tell: **O-43 and O-22 are both silent-class
  defects and both were found by code review and probes, not by using the app.**
- **D-45 — The detector: a read-only reconciliation oracle, in two placements.**
  **[OWNER-ANSWERED 2026-09-11 — full scope]** `tooling/trust-lanes/oracle.mjs` takes three
  **independent** reads — the server via GET endpoints plus a `keepling_auditor` PG role holding
  `GRANT SELECT` only; the desktop SQLite opened `mode=ro`; the iOS store pulled via
  `devicectl device copy from` (a capability already in use per `ios-dogfood.md:38`). **No INSERT,
  UPDATE, DELETE or non-GET verb anywhere** — a checker with write access is a new data-loss
  vector. It imports **no client code**, which is what kills the shared-bug class: invariants sit
  on the SQL and HTTP schema, not on the implementation.
- **D-46 — The eight invariants.** **I1** no unsettled intent — no outbox row is `in_flight` while
  no client process runs. **I2** receipt closure — a `mutation_id` absent from the outbox *and*
  from `command_receipts` is silent loss. **I3 (catches O-43)** refusal durability — every
  refused/conflicted receipt has a durable local home or a conflicts row; a local value that
  reverted to the server's pre-mutation value with no conflict artifact fires. **I4** projection
  agreement at `entity_revision`, or explained by an outbox row. **I5** feed continuity — no
  `(sequence, ordinal)` gap between `low_water_sequence` and `high_sequence`; the client cursor
  never moves backward. **I6** revision monotonicity per entity, both sides. **I7**
  tombstone/restore coherence. **I8** activity completeness (the direction the existing FK does
  not cover). Content is compared as **HMAC digests under a run-local key, never plaintext**;
  violation records carry UUIDs, field names, revisions and enum reasons only — the same closed-
  vocabulary discipline as iOS `DiagnosticEvent`.
- **D-47 — The numbers, and the honesty that goes with them.** *Real-install placement:* ≥14
  calendar days (must span a full weekly cycle plus margin), ≥1 sample per 30 min while a client
  runs, ≥300 samples. *Soak placement:* ≥72 accumulated machine-hours across ≥200 seeds of
  adversarial two-client soak against the real stack, each chaos operator exercised ≥50 times —
  SIGKILL mid-flight, partition in the POST-sent-before-response window (the exact `uncertain`
  window `apps/desktop/migrations/0002_outbox_state.sql` exists for), clock skew ±1 day, relaunch,
  account switch, logout, an offline window long enough to advance the feed low-water, concurrent
  conflicting same-field edits on both clients, reconnect mid-pull, restore-epoch bump.
  **The artifact must state its own detection floor:** ~21,600 mutation cycles detects a defect of
  per-cycle manifestation probability p ≥ 1.4e-4 at ≥95% confidence, and **proves nothing about
  defects rarer than roughly 1 in 7,000 cycles.** Saying so is the difference between evidence and
  ceremony.
- **D-48 — The thin-day census, which closes the worst failure mode of any defect-absence
  criterion.** Record per day: `mutationsOriginatedLocally`, `distinctTaskIdsTouched`,
  `offlineMinutes`, `syncRoundsCompleted`, `distinctScreensReached`. A day under 5 locally-
  originated mutations is a **thin day**, and the gate requires **≥10 non-thin days of 14**. A
  quiet fortnight therefore reads as *insufficient exposure*, never as *clean*.
- **D-49 — Who checks the checker: a mandatory `--self-test` over ~12 synthetic corrupted
  fixtures, one per invariant, each of which the oracle MUST flag** — mirroring
  `verify-macos-integration.mjs --self-test-restore`. Not a second implementation (infinite
  regress). **An oracle that passes clean data but cannot detect injected corruption is vacuous,
  and the gate refuses it.**
- **D-50 — The disclosed blind spot, permanent and named in the artifact itself.** The oracle sees
  only durable state, so **loss between keystroke and `COMMIT` is entirely outside its reach** —
  which is precisely O-22's class. That window belongs to the E2E and accessibility lanes, and the
  gate must **name** it rather than let coverage be inferred.
- **D-51 — Verdict, artifact, and the un-gameable window.** `node tooling/verify-trust-soak.mjs
  --gate` → `.artifacts/trust-soak/trust-soak-evidence.json`, digest-bound by
  `applicationDigestSha256` + `keeplingBuildDigest` + server `gitRevision` + `laneSourceDigest` +
  `oracleSourceDigest`, carrying per-invariant `{name, samples, violations, disposition}`,
  `seedCorpusDigest`, `chaosOperatorCounts`, `dailyUsageCensus[]`. Verdicts: **PASS** (every
  invariant has a positive sample count and zero unexplained violations, census floor met, and the
  open-defect register shows zero open items in the three classes) / **DISCLOSED-NOT-PROVEN** (per
  invariant, with a named reason) / **BLOCKED** (any zero-sample lane, or an unqueried register).
  Violations append to `violations.ndjson` with each line carrying `prevLineSha256`, so a
  truncated record is detectable **and the window cannot be chosen after the fact** — the window
  *starts* at the first sample whose `applicationDigestSha256` equals the release candidate's. A
  violation does not reset a clock; it enters release-blocker triage, and the gate stays non-PASS
  until the item closes or is explicitly disclosed.
- **D-52 — Adoption is reported as an outcome, never gated.** The Phase 4 precedent that "SC5
  daily adoption was never a gate" **stands and is tightened**: adoption is an n=1 preference
  signal from the author, and gating correctness on it conflates two different claims. "Jon stops
  reaching for Things" is reported as a milestone outcome with the census as its only quantitative
  accompaniment. **The only permitted path from informal feedback to evidence:** feedback the
  oracle missed becomes a new invariant or a new chaos operator, and the corpus is re-run.
  Feedback never becomes an evidence row.
- **D-53 — Proposed replacement wording for SC5**, to be applied to `ROADMAP.md` with a dated
  correction:
  > 5. The three defect classes are measured rather than assumed. (a) A read-only reconciliation
  > oracle has run against the real Mac+iPhone dogfood installation for ≥14 calendar days, ≥300
  > samples, ≥10 non-thin usage days, with zero unexplained violations of invariants I1–I8 and a
  > published per-day usage census; (b) the same oracle has served as the assertion layer over ≥72
  > accumulated machine-hours across ≥200 seeds of adversarial two-client soak against the real
  > stack, every chaos operator exercised ≥50 times; (c) the open-defect register lists no open
  > item classed data-loss, silent-overwrite, or recovery-severity. Evidence:
  > `.artifacts/trust-soak/trust-soak-evidence.json`, digest-bound, stating its own detection
  > floor and its disclosed blind spot. Owner dogfood feedback remains informal, unstructured,
  > non-evidentiary and non-gating; "Jon stops reaching for Things" is reported as a milestone
  > outcome, not a gate.

### Sequencing constraints the planner must honor

- **D-54 — Ordering.** (1) The D-41 overclaim corrections, first, before any new plan runs.
  (2) `LICENSE` + `NOTICE` + every license metadata field — independently of everything else; this
  closes a live misrepresentation (public repo, README claims open source, no rights granted) and
  it must land **before** the SBOM is generated so component license fields are populated. (3) CI
  repair (D-10, D-11), because D-09's authority model and D-12's manifest are incoherent until CI
  is green and the artifact transport is lossless. (4) Signing (D-16, D-17) — but note it changes
  `applicationDigestSha256`, so it must land before any evidence is bound for the release. (5) The
  remaining policy documents and the governance lane. (6) DATA-01, SRV-02 legs, the data-loss
  fixes, window 76 — parallelizable. (7) The trust oracle build, then its ≥14-day real-install
  window, which is the phase's long pole and should start as early as the release-candidate digest
  is stable.

### Claude's Discretion

Genuinely open for research and planning to settle on evidence; none change the shape of the phase:

- Exact NDJSON entity-file split and the `manifest.json` field names.
- `export_query_timeout_ms` default, `max_rows` chunk size.
- Whether the `tasks.md` human rendering covers activity or only current task state.
- Exact CycloneDX generator choice for Hex (`mix sbom.cyclonedx` vs `syft` vs `cdxgen`).
- Sampling implementation for the oracle (polling daemon vs launchd/`launchctl` timer vs a
  scheduled CI job pulling from the install).
- Whether the electron and iphone cross-adapter legs are one plan or two.
- `keepling_auditor` role provisioning mechanism (migration vs ops verb).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements, roadmap, and the ledger
- `.planning/ROADMAP.md` §"Phase 6: Portability and Trust Release" — goal and the five success
  criteria. SC3 and SC5 are amended by D-40 and D-53.
- `.planning/ROADMAP.md` §"Backlog" Phase 999.2 — the credentialed outer acceptance and its
  standing rule. Do not re-detect as incomplete work; do not absorb into a completion claim.
- `.planning/ROADMAP.md` §"Candidate future milestone: Sigra identity migration" — do not
  re-litigate.
- `.planning/REQUIREMENTS.md` — DATA-01 (line 57), DATA-03, OPS-02, QUAL-02 (line 72, **to be
  unchecked per D-41**), QUAL-03 (line 73, clause 2 owned here), QUAL-04, QUAL-05, SRV-02 (line
  21), and the traceability table line 126. **Window 75 requires splitting the grouped rows before
  any `phase complete` runs.**
- `.planning/WINDOWS.md` — the open-item ledger. Rows 43, 57, 58, 59, 60, 61, 63, 68, 69, 71, 73,
  74, 75, 76 are all implicated. **Treat every recorded status as untrusted until verified against
  source** — six were stale in this discussion alone.
- `.planning/STATE.md` §Blockers — lines 368 and 370 are verified stale and are corrected by D-41.

### Prior-phase invariants (do not re-derive, do not weaken)
- `.planning/phases/KPL-05-safe-agent-access/05-CONTEXT.md` — D-06 (closed scope vocabulary;
  export permanently outside any agent scope), D-25/D-26 (the five-lane evidence model and the
  anti-vacuity contract), D-27 (the cross-adapter proof definition), D-28 (correct an overclaim as
  the first act of a phase).
- `.planning/phases/KPL-05-safe-agent-access/05-VERIFICATION.md` — the three disclosures, and
  line 49's `"Unowned"` disposition that D-35 makes illegal.
- `.planning/phases/KPL-05-safe-agent-access/05-UI-REVIEW.md` — Pillar 6, window 76's origin, and
  the absent-vs-empty scope distinction D-38 preserves.
- `.planning/phases/KPL-04-native-iphone-daily-loop/04-CONTEXT.md` — **D-24, the anti-vacuity
  contract**, inherited verbatim by everything in this phase that publishes a count.
- `.planning/phases/KPL-03-mac-daily-loop/03-22-SUMMARY.md` — the "What the tests actually
  exercised — honestly" section, and the origin of O-43's recorded known limit.
- `.planning/phases/KPL-02-synchronization-and-replaceable-server/02-CONTEXT.md` — D-10 (opaque
  values bound to server instance, account subject, epoch, protocol version), protocol trains and
  what constitutes a breaking change (the basis for D-29), D-15 (golden vector discipline).
- `.planning/phases/KPL-02-synchronization-and-replaceable-server/deferred-items.md` — Plan 02-09's
  standing rule.

### Dogfood and testing contracts (extend, never replace)
- `docs/testing/ios-dogfood.md` — especially lines 38 (`devicectl` capability), 67 (TestFlight
  deferral, decided as "no" by D-18), 110-115 (**the SC5 ruling D-44 preserves**), 189-192.
- `docs/testing/desktop-dogfood.md` — lines 3-20 (the shape: no checklist, no gate, no sign-off)
  and line 80 (the `--self-test-restore` precedent D-49 mirrors).
- `docs/testing/cross-adapter-testing.md`, `docs/testing/desktop-testing.md`,
  `docs/testing/desktop-performance.md`.

### Code surfaces this phase touches
- `apps/server/lib/keepling/application/ops.ex:10-11` — `@verbs` and `@destructive`; D-05 adds
  `export` as non-destructive. Exit-class contract at `:12-18`.
- `apps/server/lib/mix/tasks/keepling.ops.ex` — the CLI surface.
- `apps/server/lib/keepling/application/agent_scope.ex:16` — the closed `@agent_scopes` whitelist
  that makes D-06 structural.
- `apps/server/lib/keepling_web/auth.ex:200` — `agent_authority/2`, the receipt-scope inversion
  (D-39).
- `apps/server/lib/keepling_web/controllers/device_grant_controller.ex:167-175` —
  `grant_response/1`, window 76 (D-38).
- `apps/server/lib/keepling/adapters/postgres/task_views.ex:693`, `projects.ex:196`,
  `search.ex:93` — the mandatory positive query timeout D-08(b) must NOT reuse.
- `apps/server/priv/repo/migrations/20260901000100_add_sync_feed.exs` — `sync_changes`, the closed
  `kind` vocabulary, the receipt FK, `sync_accounts.high_sequence`/`low_water_sequence`. The
  schema the oracle's I5 reads.
- `apps/desktop/store-worker/local-store.ts:716-743` — `#replayVisible()` and the O-43 known limit,
  in shipped source (D-37).
- `apps/desktop/renderer/DesktopShell.tsx:50-66` — the `facade.setRoute` keyboard paths (O-22).
- `packages/web-ui/src/workspace/Workspace.tsx:254-265` — `attemptNavigation`, the guard O-22
  bypasses.
- `packages/web-ui/src/tasks/ConflictResolver.tsx` — the title-only desktop chooser (O-44).
- `apps/desktop/main/application/DesktopApplication.ts:466-517` — the O-45 closure that makes
  window 59 stale.
- `apps/desktop/main/index.ts:911-918` — the `ElectronForegroundApp` wiring that makes O-21 stale.
- `apps/desktop/migrations/0002_outbox_state.sql` — the three-state outbox the oracle's I1/I3 read.
- `apps/desktop/test/real-stack/real-stack-sync.spec.ts` — **the electron cross-adapter driver's
  model. Note `WINDOWS.md` row 69 cites a `test/packaged/` path that does not exist.**
- `packages/contracts/openapi/keepling.yaml` — `DeviceGrantSummary` widening (D-38).
- `packages/contracts/vectors/manifest.json` — where the export vector registers (D-07), following
  the `mcp-injection.json` multi-consumer precedent.

### Tooling and CI
- `tooling/cross-adapter/legs.mjs:73-179` (the adapter contract needing refactor), `:291-312`
  (electron leg), `:321-348` (iphone leg).
- `tooling/verify-cross-adapter-phase.mjs:36-47` — the guard-refusal checks that MUST be extended
  to new drivers.
- `tooling/ios-device/server-driven-run.mjs:214-266` — the iphone driver's model.
- `tooling/verify-ios-phase.mjs:1-25` — the lane conventions every new lane must follow: name,
  **positive** case count, duration, tracked-input digest; a lane that cannot report a positive
  count is a failure, never a skip; BLOCKED still exits non-zero.
- `tooling/verify-macos-integration.mjs` — digest binding and the `--self-test-restore` precedent.
- `tooling/package-desktop.mjs:142-145` (mode/symlink hashing), `:326` (**where
  `applicationDigestSha256` is computed — the signing-order crux, D-17**).
- `tooling/smoke-desktop-packaged.mjs:64-77` — the digest recomputation that caught the transport
  defect.
- `tooling/verify-package-reproducibility.mjs` — keep; restate its claim per D-11.
- `tooling/runtime-preflight.sh:99-107` and `tooling/test-phase-2.sh:109` — the two shallow CI
  failures (D-10).
- `tooling/check-ci-contract.mjs:50` (lane-list hard compare — the pattern D-12 reuses), `:106`
  (paths ban), `:119` (`continue-on-error` ban).
- `tooling/check-repository-integrity.sh` + `.github/workflows/repository-integrity.yml` — the host
  for D-32's governance lane.
- `tooling/verify-privacy.sh` and `packages/contracts/vectors/redaction.json` — the evidence
  PRIVACY.md cites (D-30).
- `tooling/verify-host-replacement.sh`, `tooling/test-host-replacement-sequence.sh` — the hermetic
  rehearsal that becomes SC3's gate (D-40).
- `tooling/build-ios-signed.mjs:42-48`, `:302-304`, `:348-366` — development signing, and the
  evidence the paid Apple membership is already active.
- `apps/desktop/forge.config.ts` — where `osxSign`/`osxNotarize` must go (D-17).
- `.github/workflows/desktop.yml` — `:72,227` retention, `:187` the TCC-report step, and the
  missing `id-token: write` / `attestations: write` permissions (D-22).
- `infra/images/server/Dockerfile:3-4` — digest-pinned base images.

### Project-level
- `.planning/PROJECT.md` — core value, constraints, and the "complete open source first" claim
  D-24 makes true.
- `.planning/knowledge/DECISIONS.md` — D-003 (single-account), D-004/D-007, D-008.
- `docs/architecture/REPOSITORY.md`, `docs/architecture/MCP-SURFACE.md`,
  `docs/architecture/AGENT-RECOVERY.md`, `AGENTS.md`.
- Author's own convention, checked rather than assumed: `szTheory/sigra/SECURITY.md` (the house
  security-policy style D-27 reuses), `szTheory/exifcleaner/CONTRIBUTING.md`, and hex.pm license
  metadata for `sigra`, `lockspire`, `scrypath`, `oban_powertools`, `kiln`.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`Keepling.Application.Ops`** — a closed verb list, a frozen exit-class contract (success 0,
  usage 2, refusal 10, dependency 20, compatibility 30, recovery 40, execution 50), a port
  abstraction, and bounded privacy-safe facts. The export verb slots in as the ninth verb with no
  new machinery.
- **`Repo.stream` inside a transaction** — the existing pattern for bounded reads; the export's
  memory bound depends on it.
- **`tooling/verify-ios-phase.mjs`** — the working reference for a phase gate that refuses a pass
  it cannot support. Every new lane in this phase copies its shape.
- **`tooling/cross-adapter/legs.mjs`** — two of four legs already pass with `comparison_ok=true`
  across all four shared scenarios; the remaining work is drivers, not scenarios.
- **`apps/desktop/test/real-stack/real-stack-sync.spec.ts`** and
  **`tooling/ios-device/server-driven-run.mjs`** — working real-stack harnesses for both clients;
  the cross-adapter drivers mirror these rather than inventing.
- **`tooling/check-repository-integrity.sh`** + its workflow — an existing, already-required host
  for the governance lane; no new workflow needed.
- **`packages/contracts`** — OpenAPI, generated TS and Swift, 13 frozen vectors, `manifest.json`
  with a multi-consumer precedent, and `pnpm contracts:check` drift gating.
- **`security_audit`** with `record_required!`/`record_best_effort` and a closed event vocabulary —
  the export event joins it.
- **The three-state outbox** (`queued | in_flight | uncertain`) and **`command_receipts`** — the
  durable facts the oracle's invariants are predicates over.

### Established Patterns
- **Thin transport over application commands.** The export is an application capability with an ops
  transport, never a controller or a SQL script.
- **Closed vocabularies everywhere** — `@verbs`, `@agent_scopes`, `@activity_types`,
  `@closed_event_types`, `sync_changes.kind`. The export's entity list and the oracle's violation
  reasons follow the same shape.
- **Digest-bound evidence that refuses staleness** — evidence binds to artifact digests AND to
  test-source digests. Every new lane inherits this; `verify-release.mjs` generalizes it.
- **Anti-vacuity: BLOCKED, never a silent pass; positive case counts or failure.** Non-negotiable
  and extended to the release manifest, the governance lane, and the trust oracle.
- **Absent ≠ empty.** Established by the 05-UI-REVIEW scope fix; applies to `DeviceGrantSummary`
  and to every optional field in the export manifest.

### Integration Points
- **New:** `Ops` export verb + application module + PostgreSQL adapter; `packages/contracts/schemas/export/`;
  `tooling/` independent export reader.
- **New:** `tooling/verify-release.mjs`, `tooling/release-lanes.json`, `release-manifest.json`,
  `.planning/releases/<tag>/`.
- **New:** `tooling/trust-lanes/{oracle,invariants,chaos,census}.mjs`,
  `tooling/verify-trust-soak.mjs`, a `keepling_auditor` read-only PG role.
- **New:** eight root policy documents plus the governance lane.
- **Extended:** `forge.config.ts` (signing), `package-desktop.mjs` (`archiveDigestSha256`,
  `codeDirectoryHash`), `desktop.yml` (permissions, `ditto` transport, attestation),
  `runtime-preflight.sh`, `test-phase-2.sh`, `check-ci-contract.mjs`,
  `check-repository-integrity.sh`.
- **Extended:** `legs.mjs` adapter contract + two new drivers; `verify-cross-adapter-phase.mjs`
  guard checks.
- **Extended:** `local-store.ts` refusal durability + a migration; `ConflictResolver.tsx`
  multi-field desktop chooser; `DesktopShell.tsx` keyboard navigation;
  `device_grant_controller.ex` + `keepling.yaml` `DeviceGrantSummary`; `auth.ex` receipt authority.

</code_context>

<specifics>
## Specific Ideas

- **The owner's explicit process instruction for this discussion**, which shaped every decision
  above and should shape research too: fan out across all relevant stakeholder-role lenses
  (security, product, architecture, DevOps, design, distributed systems, legal, maintainer
  sustainability), consider pros/cons/tradeoffs/examples, antipatterns and best practices, look at
  what other products and ecosystems actually do, run an adversarial pass — **then synthesize one
  decisive recommendation per point.** Six research agents did exactly that; the decisions above
  are the synthesis, not a menu.
- **The phase is named "Trust Release," and that name is load-bearing.** The sharpest finding
  across all six agents: shipping a release labelled "Trust" while `local-store.ts` contains a
  comment stating the person's edit will be lost on the next pull, and while the consent screen
  tells the user it does not know what its agents may do, would itself be the exact failure this
  project has twice corrected — green words over a known-false state. That is why O-43/O-44/O-22
  and window 76 are MUST-CLOSE rather than known limitations.
- **The ledger lies, and that is a finding in its own right.** Six of the residual items were stale
  — closed in shipped source while still recorded `open` — and one open data-loss defect (O-22) had
  no ledger row at all. Verify against source; never inherit a status.
- **"Unowned" is the pattern most worth killing.** A verifier passed a phase 5/5 while recording a
  BLOCKED lane as somebody else's problem. D-35 makes that structurally impossible.
- **Things (Cultured Code) remains the UI reference** for any open interaction question in the
  agent-grant and conflict-chooser surfaces (standing owner preference).
- **Zero manual verification is a locked constraint, not a preference.** It is why TestFlight is
  rejected (D-18), why SC5 becomes a machine measurement (D-45), and why the human's dogfood role
  stays informal with no checklist and no sign-off (D-44).

</specifics>

<deferred>
## Deferred Ideas

- **Authenticated HTTPS export download** — belongs to the hosted-convenience milestone, where it
  is necessary rather than speculative (D-05).
- **An export importer / round-trip re-ingest** — a permanent second compatibility surface plus
  real attack surface, and it proves less about inspectability than the independent reader does
  (D-07).
- **TestFlight or App Store iOS distribution** — revisit when a second human wants the iPhone app
  (D-18).
- **A unified four-ecosystem SBOM** — blocked on Swift tooling (`Package.resolved` v3 unsupported
  by syft; SE-0509 unshipped). Revisit when SwiftPM ships native SBOM support (D-20).
- **SLSA Build Level 3** — needs a reusable workflow with isolated signing; L2 is what is honestly
  achievable now (D-22).
- **The paid credentialed Hetzner/DNS cutover** (Phase 999.2, DATA-03, OPS-02) — stays a protected
  outer lane with a standing rule (D-40).
- **Deterministic simulation testing of the sync protocol** (FoundationDB/TigerBeetle-VOPR style) —
  would require making the sync core deterministic and injectable in **two** runtimes (TypeScript
  main process and Swift), which means production-surface change to make a gate pass; and it still
  could not observe the real install. Revisit only if a later milestone unifies the sync core into
  one shared runtime, and then only as an addition.
- **Wiring desktop `preparing`/`uncertain` presentation states** — do not wire speculatively;
  recorded as a known limitation (windows 60/61, D-43).
- **An RFC 8707 audience check at `:client_authenticated`** — explicitly ruled out; it would buy no
  authority reduction. Write the decision record instead (D-43).
- **`FUNDING.yml` and `CITATION.cff`** — deliberately skipped (D-32).
- **Sigra identity migration** — already a candidate future milestone; not re-litigated.
- **Stdio MCP transport / a locally distributed bridge binary** — deferred from Phase 5 to "Phase 6
  alongside packaging and signing." **Reviewed here and deferred again:** it needs its own signed,
  distributed artifact and sits outside server-side rate limiting and audit, and this phase's
  packaging scope is already the critical path. Not in scope.
- **Dynamic Client Registration for arbitrary third-party MCP hosts** — deferred from Phase 5 to
  "the Phase 6 security and support policy." **Reviewed here:** the scoped, session-gated DCR built
  in Phase 5 stays as-is; opening registration to arbitrary hosts is a public-surface expansion,
  not a policy document, and belongs with a real multi-host requirement.

</deferred>

---

*Phase: 6-Portability and Trust Release*
*Context gathered: 2026-09-11*
