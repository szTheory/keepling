# Phase 6: Portability and Trust Release - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `06-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-09-11
**Phase:** 6-portability-and-trust-release
**Mode:** advisor (calibration tier `minimal_decisive`), with an owner-requested research fan-out
**Areas discussed:** Export shape & delivery, Release evidence & CI authority, Public trust posture, Residuals & the dogfood gate

---

## Gray area selection

The owner selected **all four** offered areas, and added a standing instruction for how to work
them: fan out across every relevant stakeholder-role lens (security, product, architecture,
DevOps, distributed systems, design, legal, maintainer sustainability), weigh
pros/cons/tradeoffs/examples, antipatterns and best practices, research what other products and
ecosystems actually do, run an adversarial pass — then synthesize **one** decisive recommendation
per decision point rather than a menu.

Six `gsd-advisor-researcher` agents ran in parallel on opus, splitting "Public trust posture" into
signing/SBOM and license/policy, and "Residuals & the dogfood gate" into residual disposition and
SC5 measurement. Each was instructed to verify against the repository before asserting, and to
distinguish VERIFIED from INFERRED.

---

## Export shape & delivery (DATA-01)

| Option | Description | Selected |
|--------|-------------|----------|
| Zip bundle: manifest + per-entity NDJSON + FORMAT.md + human `tasks.md` | Streamable both ways, `jq`/`grep`/`wc -l` work per line, meaningful diffs, readable with no tools at all. Converges with 1Password `.1pux`, Google Takeout, Joplin JEX, Day One | ✓ |
| Single JSON document | One file, no container — but unbounded memory on both sides, one-byte corruption kills it, useless diffs, silent timeout truncation | |
| SQLite / CSV-only / iCalendar VTODO | SQLite needs a tool and re-exports internals; CSV is lossy for the nested actor shape; RFC 5545 + RFC 9253 cannot carry `inbox_state`, activity, agent actors, or the independent planned/deadline pair | |

**Content rule selected:** "authored or durable account history is IN; derived, credential, or
protocol mechanism is OUT" — over "export all 22 durable tables," which was rejected as a `pg_dump`
with a new name that duplicates DATA-02.

**Proof approach selected:** four-part lane with an **independent reader** sharing zero Elixir
code, over a **round-trip importer**. The importer was rejected honestly: it is a permanent second
compatibility surface plus zip-bomb/path-traversal/ID-collision attack surface, and it proves only
self-consistency — the exact failure mode of formats only the product can read.

**Notes:** the agent verified `Ops.@verbs` has no export verb and that
`agent_scope.ex:16`'s closed whitelist already makes agent export structurally impossible. It also
found a concrete footgun: reusing `:task_view_query_timeout_ms` (mandatory and positive at three
adapter call sites) would silently truncate a large-account read.

---

## Release evidence & CI authority (QUAL-02, QUAL-03, SC2)

| Option | Description | Selected |
|--------|-------------|----------|
| CI authoritative for every lane it can physically run; a closed committed set is `local-attested` and must bind to a CI-attested digest | Anti-loophole rule: nothing local may bind to locally built bytes, so a lane cannot be moved out of CI to make it green | ✓ |
| Local `verify-*-phase.mjs` gates remain sole authority; CI informational | Zero migration, works offline — but permanently unfalsifiable by anyone but the owner, and the O-35 disclosure becomes permanent | |

| Option | Description | Selected |
|--------|-------------|----------|
| Build-once / promote-many with a lossless `ditto` archive | Identity of bytes rather than independent re-derivation; literally what QUAL-03's text demands; makes locally-run evidence bindable to released bytes | ✓ |
| Require machine-independent digest equality | Not achievable for a macOS app bundle without an open-ended effort that would likely end in a loosened binding — the failure O-40 already refused once | |

**Notes:** the decisive fact was empirical, not argued. Run `34561455069` shows the `.app` digest
changing across an `actions/upload-artifact` boundary **inside a single run on one runner image**,
because the zip round-trip drops POSIX mode and the smoke check hashes it. The binding caught a
real transport defect.

The agent read actual failure logs rather than guessing. All four CI root causes are shallow
"works on the maintainer's Mac" bugs: `asdf install` with no `asdf plugin add`, a missing `rg`,
the artifact transport, and a display-geometry assertion. "Narrow CI to a green core plus
informational lanes" was rejected as the exact vacuity pattern Phase 4 was burned by.

---

## Public trust posture — signing, SBOM, supply chain (SC4, part)

| Option | Description | Selected |
|--------|-------------|----------|
| iOS: keep development-signed + `devicectl` | Zero new machinery, no Apple availability in the release path, no recurring manual step | ✓ |
| iOS: TestFlight | Reachable by other testers, but a 90-day build-expiry treadmill reintroduces exactly the manual step the zero-manual-verification rule exists to remove; App Review carries real risk for a connect-to-your-own-server app | |

| Option | Description | Selected |
|--------|-------------|----------|
| SBOM: honest partial (CycloneDX for Hex + npm; published lockfiles for Swift with a named declared gap) | The anti-vacuity contract applied to supply chain | ✓ |
| SBOM: unified across all four ecosystems | Would be a lie — `Package.resolved` v3 is unparseable by syft, and an SBOM scanned from the built `.app` would show ~3 entries for a 915-dependency bundled app | |

**Notes:** the agent verified the Apple Developer Program is **already paid**
(`build-ios-signed.mjs:348-366`), collapsing macOS Developer ID signing + notarization to a $0
marginal change with the largest user-visible payoff — on Tahoe the unsigned build reads "Keepling
is damaged and can't be opened." It also pinned the signing-order trap precisely: the digest is
computed at `package-desktop.mjs:326` immediately after Forge emits the `.app`, so signing must
run inside Forge's `package` step, and `codeDirectoryHash` is the identity that survives stapling.
SLSA L3 was explicitly rejected as an overclaim (build and attest share a job); L2 is claimed.

---

## Public trust posture — license and policy (SC4, remainder)

| Option | Description | Selected |
|--------|-------------|----------|
| Apache-2.0, uniform across the monorepo | Matches the author's newer Elixir convention; explicit patent grant for a codebase shipping an OAuth 2.1 authorization server and credential store; §6 withholds trademark rights; §5 removes the main reason for a CLA; keeps hosted/App Store/dual-license/acquisition all open | ✓ |
| MIT, uniform | The author's most common license; simpler — loses the patent grant and trademark clause | |
| AGPL-3.0 | The only option that deters a hosted clone — but breaks the iPhone client (GPL-family vs App Store Usage Rules), kills third-party reuse of `packages/contracts`, and protects revenue the project says is out of scope | |

| Option | Description | Selected |
|--------|-------------|----------|
| DCO 1.1, enforced by a lane | Apache-2.0 §5 already grants inbound copyright and patent, so the DCO carries **provenance** — the live risk for an AI-built project | ✓ |
| CLA | Buys a unilateral relicense right that is nearly worthless under Apache-2.0, and whose historical exercise triggered HashiCorp→OpenTofu and Redis→Valkey | |

**User's choice:** Apache-2.0 uniform.
**Notes:** the agent checked the author's actual practice rather than guessing — GitHub API over
`szTheory` plus hex.pm metadata confirmed Apache-2.0 on crosswake, lockspire, scrypath and
oban_powertools, and found an existing house SECURITY.md style in `sigra` (private reporting,
deliberately no SLA, Security Invariants and Security Non-Goals tables). It also found the most
urgent item in the phase: the repo is public and claims open source in the README while granting
no rights at all. BSL/FSL/Elastic-2.0 were rejected because a non-OSI license under that sentence
would be the same class of overclaim this project's culture exists to prevent.

---

## Residuals & SRV-02

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 6 owns wiring the electron + iphone cross-adapter legs | Both are wiring over harnesses that already exist; closes the milestone's last cross-cutting requirement; retires a deferral Phases 1, 3 and 4 each pushed forward | ✓ |
| Defer SRV-02 to a named post-v1.0 phase | Protects final-phase scope, but makes three prior phases' deferrals permanently unpaid and leaves SC2 unclaimable | |

| Option | Description | Selected |
|--------|-------------|----------|
| Narrow SC3 in writing; live Hetzner/DNS cutover stays a protected outer lane | Hermetic rehearsal becomes the gate; the lane keeps exiting non-zero so no skip counts as evidence; DATA-03 and OPS-02 stay honestly unchecked | ✓ |
| Attempt the paid single-attempt live run inside Phase 6 | Would close three items at once, but is owner-credentialed, single-attempt, and a mid-phase failure blocks the milestone on a provider rather than on code | |

**User's choices:** Phase 6 owns SRV-02; SC3 narrowed in writing.
**Notes:** the agent verified before ruling and found **six of the items handed to it were stale** —
O-21, O-45, O-51, the two 04-16 device blockers and 05-01 are all closed in shipped source while
still recorded open. Conversely O-43 and O-22 are confirmed open, and **O-22 has no ledger row at
all**. It also found QUAL-02's situation is worse than recorded: its disclosure says CI has never
executed, but CI now executes and fails 17/17 — the disclosure is factually wrong in the project's
favour. A third option, "narrow SRV-02's text to the two proven adapters," was considered and
rejected as renaming the requirement to match the evidence.

---

## The SC5 dogfood gate

| Option | Description | Selected |
|--------|-------------|----------|
| Read-only reconciliation oracle in two placements (real install + adversarial soak), full scope | 8 invariants over server + both clients, importing no client code; I3 catches O-43's silent revert as a named predicate; thin-day census makes low usage visible rather than clean-looking | ✓ |
| Oracle only, skip the ≥72-hour soak | Roughly half the build, but loses the stated detection floor and deliberate exercise of the kill/partition/skew/conflict operators | |
| Fix the known defects and disclose SC5 | Cheapest, but leaves the milestone's headline trust claim resting on an unmeasured absence | |
| Deterministic simulation testing (VOPR-style) | Superior interleaving coverage, but needs the sync core made deterministic and injectable in two runtimes — production change to make a gate pass — and still cannot observe the real install | |

**User's choice:** build it, full scope.
**Notes:** the agent found the dogfood contract already exists and already ruled — `ios-dogfood.md:110-115`
says Criterion 5 is "not automatable, and not a gate." Its design extends that rather than
replacing it: the human half stays informal with no checklist and no sign-off, and only the
defect-absence half becomes a measurement. Its sharpest observation is that O-43 and O-22 are both
silent-class defects and both were found by code review and probes, not by using the app — which
is itself evidence about how much a dogfood period can be relied on to detect this class.

---

## Claude's Discretion

Auto-selected, genuinely open for research and planning to settle on evidence; none change the
shape of the phase:

- Exact NDJSON entity-file split and `manifest.json` field names.
- `export_query_timeout_ms` default and `max_rows` chunk size.
- Whether the human `tasks.md` rendering covers activity or only current task state.
- CycloneDX generator choice for Hex (`mix sbom.cyclonedx` vs `syft` vs `cdxgen`).
- Oracle sampling mechanism (polling daemon vs launchd timer vs scheduled CI pull).
- Whether the two cross-adapter legs are one plan or two.
- `keepling_auditor` role provisioning (migration vs ops verb).

## Deferred Ideas

- Authenticated HTTPS export download — hosted-convenience milestone.
- Export importer / round-trip re-ingest — permanent second compatibility surface.
- TestFlight or App Store iOS distribution — when a second human wants the app.
- Unified four-ecosystem SBOM — when SwiftPM ships native SBOM support.
- SLSA Build Level 3 — needs a reusable workflow with isolated signing.
- The paid credentialed Hetzner/DNS cutover — protected outer lane, Phase 999.2.
- Deterministic simulation testing of the sync protocol — only if a later milestone unifies the
  sync core into one runtime, and then only as an addition.
- Wiring desktop `preparing`/`uncertain` presentation states — recorded, not wired speculatively.
- An RFC 8707 audience check at `:client_authenticated` — ruled out; write the decision record.
- `FUNDING.yml` and `CITATION.cff` — deliberately skipped.
- Stdio MCP transport — deferred from Phase 5 to here, reviewed, and deferred again.
- DCR for arbitrary third-party MCP hosts — deferred from Phase 5 to here; the scoped session-gated
  DCR stays as-is, and opening registration is a surface expansion, not a policy document.
- Sigra identity migration — candidate future milestone, not re-litigated.
