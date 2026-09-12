---
phase: KPL-06-portability-and-trust-release
verified: 2026-09-12T03:13:27Z
status: human_needed
score: 8/8 must-haves verified (the eighth remediated after this report; see Remediation)
behavior_unverified: 0
overrides_applied: 0
human_verification:
  - test: "Decide whether SRV-02 may remain [x] in .planning/REQUIREMENTS.md:21 while its only lane (cross-adapter-phase) is BLOCKED/unwired in the release manifest."
    expected: "Either uncheck SRV-02, or accept the 06-13 disclosure as sufficient. The manifest's own lane reason string asserts 'SRV-02 depends on this lane and stays unchecked', which the checked box contradicts."
    why_human: "06-13 deliberately declined to re-adjudicate another plan's finding and filed it as window #92 with owner BACKLOG. Whether that is disclosure or deferral is an owner call."
---

# Phase KPL-06: Portability and Trust Release — Verification Report

**Phase Goal:** The dogfood product is portable, diagnosable, release-ready, and supported by exact cross-client evidence.
**Requirements:** DATA-01, plus final verification of QUAL-03..05 across the released system.
**Verified:** 2026-09-12T03:13:27Z
**Status:** human_needed
**Re-verification:** No — initial verification.

## Remediation applied after this report

The one must-have that did not hold — `docs/security/SUPPLY-CHAIN.md` stating
sections 1-3's controls in the unqualified present tense — was remediated in
`5bf5a19`. Each section now opens with its status for THIS candidate before the
prose describing the design: section 1 records that the CI-built artifact is
unsigned and unnotarized (`developerIdSigned: false`, `hardenedRuntime: false`,
`notarization.status: "not-attempted"`, window #91); section 2 records that
`desktop-promote` was skipped so no provenance attestation exists (window #88);
section 3 records that neither CycloneDX document was generated. The finding's
own stated remediation was "one sentence per section", and that is what was
applied. The editorial question the report raised — whether a design document
must be revision-caveated — was answered in the affirmative, consistent with
the phase's no-overclaim standard.

The report's W2 finding was closed in the same commit: `verify-release.mjs` now
recomputes every lane's `evidenceDigestSha256` and refuses a dangling or altered
one, with a fourth guard fixture wired into the `ci-contract` self-test. W4 was
closed by gitignoring `tooling/local/`. W3 (SRV-02) remains an owner decision
and is still listed above.

## Verdict

**The phase goal was achieved under its own stated discipline.** This phase's contract was
no-overclaim, and on the load-bearing checks it holds: the release manifest binds to CI rather than
to local bytes, the verifier's guards are live and reason-specific, the public limitations list is
mechanically generated from the internal ledger, the ledger's two representations agree row for row,
the release evidence is retained and its digests independently recompute, and nothing personally
identifying reached a committed file or a commit message. The 39/11/28 lane split, the non-zero
`verify-release.mjs` exit, and the three unchecked requirement boxes are all the correct outcome and
are all disclosed with a named blocker, a closing command and a real owner.

**One must-have did not fully hold.** `docs/security/SUPPLY-CHAIN.md` — the document whose stated
purpose is to prevent exactly this — carries three present-tense control claims that are stronger
than the evidence at the revision the release is bound to. The two specific overclaims the phase was
asked to avoid (server OCI image signing, reproducibility-as-provenance) are correctly and
explicitly disclaimed; the gap is in the claims nobody thought to check.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | The manifest binds to CI, not to locally built bytes | ✓ VERIFIED | See §1 |
| 2 | The verifier's three guards are real and reason-specific | ✓ VERIFIED | See §2 |
| 3 | `KNOWN-LIMITATIONS.md` is generated, not hand-written | ✓ VERIFIED | See §3 |
| 4 | `.planning/WINDOWS.md`'s two representations agree, every open row owned in both | ✓ VERIFIED | See §4 |
| 5 | No trust document overclaims | ⚠️ PARTIAL | See §5 — the two named must-nots hold; three unnamed present-tense claims do not |
| 6 | No PII in committed files or commit messages | ✓ VERIFIED | See §6 |
| 7 | Gaps are declared rather than papered over | ✓ VERIFIED | See §7 |
| 8 | Exact evidence is bound to one revision and retained (SC2) | ✓ VERIFIED | See §8 |

**Score:** 7/8 truths verified, 1 partial.

---

### §1 The manifest binds to CI, not to local bytes — ✓ VERIFIED

`tooling/release-lanes.json`'s `$comment` states the rule verbatim: *"NOTHING LOCAL MAY BIND TO
LOCALLY BUILT BYTES."* Independently confirmed:

| Check | Result |
|---|---|
| Bound revision | `26628e1771d5b90569b5eec232047456fdda9f2e` — commit exists in this repo |
| `revision.runIds["desktop.yml"]` | `34668212473` ✓ matches the stated run |
| `revision.runIds["repository-integrity.yml"]` | `34668212479` ✓ matches the stated run |
| `revision.forkOrigin` | `false` |
| Source-tree binding | record's `gitTreeSha1 = b0507809d657ebbd650d9df0235c2ed5cf15a83f`; `git rev-parse 26628e1^{tree}` returns the **same value** — independently recomputed, not taken from the manifest |
| Lane inventory closure | 39 lanes in `release-lanes.json`, 39 in the manifest, exactly once each |
| Status split | **11 PASSED, 28 BLOCKED** — matches the expected outcome |
| `verify-release.mjs` exit code | **1** (non-zero), as expected |

**Local-attested lanes.** Exactly 5 lanes carry a non-null `physicalBlocker` and therefore
`authority: local-attested`: `macos-integration-live-appearance`, `macos-integration-full-grant`,
`ios-device`, `mcp-representative-model`, `live-host-dns-acceptance`. **All five report BLOCKED with
`cases: 0`.** None was moved out of CI to make it green; none claims PASSED against local bytes. The
`macos-integration-full-grant` reason is explicit that a locally signed, notarized, stapled build
exists and that its evidence *may not* be recorded here because it binds to locally built bytes at a
different revision — the rule being obeyed against its own author's interest.

Row A14 is now its own lane (`macos-integration-live-appearance`, `local-attested`, BLOCKED) with the
observed CI failure (`background stayed {"b":0,"g":0,"r":0}`, run 34668212473) recorded beside the
note that the identical row passes on a real logged-in session and that the local pass is **not**
recorded as a passing status. Window #84.

Every one of the 11 PASSED lanes binds to a CI-produced artifact digest: 9 to the source-tree record
(`2aa86c8e…`, built by run 34668212473, job `checkout`) and 4 to the desktop package manifest
(`f14a8d8a…`, built by run 34668212473, job `desktop-package`). No PASSED lane binds to a `produced:
false` artifact.

**Independently cross-checked against CI's own bytes:** the committed
`desktop-macos-app.package-manifest.json` records `codeSigning: {signed: true, developerIdSigned:
false, hardenedRuntime: false}` and `notarization: {attempted: false, status: "not-attempted",
stapled: false}`. The release manifest reproduces this faithfully and adds an unambiguous
`signing.statement` that the CI bytes are UNSIGNED and UNNOTARIZED. **No overclaim in the manifest.**

*Precision note:* the anti-loophole binding path is exercised at this revision only by the fixture,
because no local-attested lane reports PASSED. The rule is proven live; it is not proven against real
passing data.

### §2 The verifier's guards are real — ✓ VERIFIED

All three fixtures were run through `tooling/verify-release.mjs --manifest <fixture> --offline`,
reproducing the CI invocation exactly. Each exits non-zero **and** emits its stated reason:

| Fixture | Exit | Stated reason found in output |
|---|---|---|
| `release-manifest.vanished-lane.json` | 1 | `lane vanished from manifest` ✓ |
| `release-manifest.local-unattested.json` | 1 | `nothing local may bind to locally built bytes` ✓ |
| `release-manifest.not-produced-artifact.json` | 1 | `a lane cannot have tested bytes that were never built` ✓ |

`.github/workflows/repository-integrity.yml:36-62` asserts all three by that exact reason string, not
merely by exit code, via an `assert_refused fixture expected` helper that fails loudly on both
*accepted* and *refused-for-the-wrong-reason*. The block carries a correct in-line note that
`set -o pipefail` is deliberately omitted because each fixture exits non-zero **on purpose** and
piping under pipefail would fail the step precisely when the guard works. That reasoning is sound and
the implementation matches it (output captured first, then grepped).

`./tooling/check-ci-contract.mjs` runs clean locally: `lanes=9 pins=full-sha caches=exact
scheduled=non-vacuous privacy_self_test=passed` (exit 0). `./tooling/check-repository-integrity.sh`
exits 0 with `Governance checks passed: 13 assertions performed` — the lane asserts a positive count
so that a vacuous governance lane is itself a failure.

### §3 `KNOWN-LIMITATIONS.md` is generated — ✓ VERIFIED

```
node tooling/generate-known-limitations.mjs --out /tmp/kl.regen
  → Generated /tmp/kl.regen: 28 open limitation(s)
diff KNOWN-LIMITATIONS.md /tmp/kl.regen  → no differences
sha256 both files → 1a7098c75d0fdd2b26404fbabb15b3033b4f00b636a515a09ce0ddd13cf88a53
```

**Byte-identical, 28 open limitations.** The generator's `--self-test` also passes, demonstrating
that a well-formed open row is accepted and an open row with an empty owner is *rejected* — the
anti-unowned clause is enforced by refusal to run, not by convention.

### §4 `.planning/WINDOWS.md`'s two representations agree — ✓ VERIFIED

Parsed the rendered markdown table and the canonical fenced JSON block independently (honoring `\|`
escaping) and compared row by row:

| Check | Result |
|---|---|
| Rows in rendered table | 95 |
| Rows in canonical JSON | 95 |
| `status` mismatches | **0** |
| `owner` mismatches | **0** |
| Open rows | 28 (ids 43, 57, 58, 60, 61, 63, 68, 71, 73, 75, 76, 77, 79, 80, 82, 83–95) |
| Open rows with an empty owner in either representation | **0** |
| New rows 83–95 | **13 present**, all owner `BACKLOG` |
| Frontmatter arithmetic | open 28 + waived 50 + fixed 16 + closed 1 = total 95 ✓ |

Lane ownership in `release-lanes.json` obeys the same clause: all 28 BLOCKED lanes are owned by
`backlog`; the 11 lanes still owned by `KPL-06` are exactly the 11 PASSED ones. The final phase of the
milestone does not own a single blocked lane.

### §5 No trust document overclaims — ⚠️ PARTIAL

**The two named must-nots both hold.**

- **Server OCI image signing (window #80):** `SUPPLY-CHAIN.md:40-47` states in bold that *"The
  self-hosted server's container image is NOT signed"*, gives the true reason (nothing in the
  repository builds or pushes it to any registry), cites window #80, describes what *would* be done,
  and closes with *"treat the server image as carrying no provenance guarantee whatsoever."* The
  release manifest carries a matching `produced: false` absence record. **No overclaim.** Commit
  `a25fa91 fix(06-10): stop claiming the server image is signed` is the correction landing.
- **Reproducibility as a provenance control (window #82):** `SUPPLY-CHAIN.md:58-63` states the lane
  *"currently fails for Developer ID builds"*, gives the true mechanism (notarization requires an
  embedded RFC 3161 secure timestamp; a freshly-timestamped signature cannot be byte-reproducible),
  cites window #82, and says explicitly it *"is not claimed as a working control here."* **No
  overclaim.** The `package-reproducible` lane is BLOCKED in the manifest for the same reason.

**Three claims elsewhere in the same document are stronger than the bound revision's evidence, and
unlike the two above they carry no cross-reference.**

| Location | Claim as written | Evidence at revision 26628e1 |
|---|---|---|
| `SUPPLY-CHAIN.md:14-21` | "The packaged macOS application **is signed** with a Developer ID Application certificate… The bundle **is notarized** by Apple and the notarization ticket **is stapled** onto it." | CI's own package manifest: `developerIdSigned: false`, `hardenedRuntime: false`, `notarization.status: "not-attempted"`, `stapled: false`. **Window #91**, not cited here. |
| `SUPPLY-CHAIN.md:33-38, 56-58` | "The release pipeline **emits** a SLSA Build Level 2 provenance attestation… The load-bearing control for provenance **is this attestation**." | `slsa-provenance-attestation` lane BLOCKED: `desktop-promote` was SKIPPED, so `actions/attest-build-provenance` never ran. `verify-release.mjs` reports `attestation=UNVERIFIED` for all five artifacts. **Window #88**, not cited here. |
| `SUPPLY-CHAIN.md:73-75` | "Two CycloneDX documents **are generated from source, at the release revision**." | `sbom-generation` lane BLOCKED: lives in the skipped `desktop-promote` job, so no bill of materials exists for this revision. Not cited here. |

The same pattern appears once more outside that file: `PRIVACY.md:24` and `SECURITY.md:39` cite
`tooling/verify-privacy.sh` as the live enforcement of the redaction guarantee ("enforced… not merely
stated"), while at this same revision that exact scan **failed** on another lane's diagnostic
artifact (`phase2-server`: `hostile sentinel found in a diagnostic artifact`, run 34668212479). That
failure is honestly recorded as window #85 and, to the project's credit, `QUAL-05`'s own requirement
comment records it as a *named tension* and states *"This checkbox may not be cited without citing
row 85 alongside it."* The public-facing documents do not carry that pointer.

**Mitigating and material:** all four gaps (#91, #88, #85, and the SBOM absence via #88) are
genuinely public — `KNOWN-LIMITATIONS.md` is committed at the repository root and contains `06-91`,
`06-88`, `06-85`, `06-82`, `06-80`. So this is *cross-reference asymmetry inside one document*, not
concealment. But the asymmetry is the tell: #80 and #82 were caveated inline because someone checked
them; #91 and #88 were not because nobody did. Remediation is one sentence per section.

Routed to human verification rather than recorded as a failure: the question of whether a
design-of-controls document must be revision-caveated is editorial, and the established fact that a
genuinely signed, notarized, stapled build exists *locally* makes §1's mechanism description true of
the mechanism if not of the released bytes.

### §6 No PII in committed files or commit messages — ✓ VERIFIED

| Scan | Result |
|---|---|
| Personal email (`REDACTED-PERSONAL-LOCAL-PART`, `@gmail.com`, `@icloud.com`, `@me.com`) in any tracked file | **0 hits** |
| Same patterns in any commit message across all refs | **0 hits** |
| Commit author/committer identities across all refs | exactly one: `szTheory <szTheory@users.noreply.github.com>` — pseudonymous, GitHub noreply |
| Apple Team IDs (extracted from the local keychain's 4 codesigning identities) in tracked files | **0 hits each** |
| Same Team IDs in commit messages | **0 hits each** |
| Signing-identity common names (personal legal name and employer org, extracted from the same 4 certs) in tracked files, case-insensitive | **0 hits each** |
| Same names in commit messages | **0 hits each** |
| Team ID / Apple ID handling in source | fully parameterized: `secrets.APPLE_TEAM_ID`, `process.env.APPLE_ID`, `DEVELOPMENT_TEAM = YOUR_TEAM_ID_HERE` in the `.example` file only |
| Committed CI evidence logs (21 lane logs + 2 full run logs) | all paths are `/Users/runner/...` — hosted-runner paths, no local identity |

*(Per the standing rule, no extracted identity value is reproduced in this report; only match counts.)*

**One low-severity residual:** the literal path `/Users/jon/...` appears in **75 tracked
`.planning/` files** plus `apps/desktop/test/performance/runtime.spec.ts`. That exposes a first name
and local directory layout, not a legal name, email, Team ID or employer. For a repository headed for
public Apache-2.0 release this is worth a sweep, but it is not a release blocker and the phase never
claimed to have done it.

### §7 Gaps are declared rather than papered over — ✓ VERIFIED

| Expected honest outcome | Observed |
|---|---|
| `verify-release.mjs` exits non-zero | ✓ exit 1 |
| 39 lanes / 11 PASSED / 28 BLOCKED | ✓ exactly |
| `DATA-01` unchecked with disclosure | ✓ `- [ ] **DATA-01**` — both export lanes BLOCKED |
| `QUAL-02` unchecked with disclosure | ✓ `- [ ] **QUAL-02**` — disclosure *replaced*, not appended, because none of the four earlier notes described current state |
| `QUAL-03` unchecked with disclosure | ✓ `- [ ] **QUAL-03**` — was previously **checked**; 06-13 **unchecked it** because `desktop-promote` was SKIPPED, turning an untested absence into a tested one. A checkbox moving backwards on evidence is the single strongest signal this discipline is real |
| 13 new WINDOWS.md rows 83–95 | ✓ all present, all owned |

Every BLOCKED lane's reason names a real cause, not a schedule. Spot-checked against the established
facts, and each matches exactly: `phase2-sync-property` / `phase2-backup-restore` fail at `Install
asdf` (`destination path '/home/runner/.asdf' already exists`, exit 128 — toolchain provisioning,
before any project code) → window #87; `image-compose-deploy` fails on hackney 1.25.0 carrying four
open advisories including EEF-CVE-2026-47071 (HIGH) → window #86, correctly characterized as *"a real
supply-chain finding in the bytes the server image would ship, not an infrastructure fault"*;
`live-host-dns-acceptance` *"keeps exiting non-zero so that no skip is ever counted as evidence"* →
D-40 carried forward unchanged.

`trust-soak` (SC5) reports `verdict: BLOCKED` with `samples: 0` and `violations: 0` for all eight
invariants I1–I8, an empty `dailyUsageCensus`, and `detectionFloor.confidence: null` with the note
*"Insufficient accumulated samples to state a detection floor. This proves nothing about defects of
any rarity yet."* Verified directly against
`.planning/releases/candidate-1/evidence/trust-soak-evidence.json`. A zero-sample gate reporting
BLOCKED rather than vacuously green is the correct outcome.

`DATA-01`'s independent reader does pass locally — `node tooling/verify-export-reader.mjs --golden`
→ `PASSED cases=16`, exit 0 — and the manifest nonetheless records the `export-reader` lane as
BLOCKED because no committed workflow job invokes it (window #83). Local green did not become a
checkbox. That is the discipline working.

### §8 Evidence bound to one revision and retained (SC2) — ✓ VERIFIED

`.planning/releases/candidate-1/` contains the manifest, 5 artifact records, 2 full CI logs
(`desktop-34668212473.log`, `repository-integrity-34668212479.log`), 21 per-lane evidence logs, and
the trust-soak evidence file.

**Independently recomputed every lane evidence digest** rather than trusting the manifest:

```
lanes with evidenceDigestSha256: ok=21  bad=0  no-digest=18
evidence files on disk: 21   unreferenced files: none
```

All 21 recorded digests match the retained bytes exactly, and every retained file is referenced. The
18 lanes without a digest are all BLOCKED lanes that produced no evidence.

Artifact digests are recomputed by the verifier itself from bytes on disk (`verify-release.mjs:236-252`),
and no mismatch was reported.

---

### Requirements Coverage

| Requirement | Status in REQUIREMENTS.md | Assessment |
|---|---|---|
| **DATA-01** | `[ ]` unchecked | ✓ HONEST — export machinery exists and passes locally (16 cases); both CI lanes BLOCKED (`export-elixir` blocked behind phase2-server's privacy failure, `export-reader` unwired). Windows #83, #85. |
| **QUAL-02** | `[ ]` unchecked | ✓ HONEST — disclosure fully replaced. |
| **QUAL-03** | `[ ]` unchecked | ✓ HONEST — **unchecked by this phase** on evidence. Clause 1 re-proven (`desktop-packaged`, 11 cases, against the exact CI digest); clause 2 has no passing lane because `desktop-promote` was SKIPPED. Window #88. |
| **QUAL-04** | `[x]` checked | ✓ ACCEPTABLE — re-confirmed and *narrowed* at this revision on CI evidence; the pixel-contrast rows it previously cited are BLOCKED and that narrowing is recorded inline. |
| **QUAL-05** | `[x]` checked | ⚠️ ACCEPTABLE WITH TENSION — `phase2-privacy` PASSED (17 cases) at this revision, but the same scan FAILS on `phase2-server`'s diagnostic artifact. The tension is recorded in the requirement itself with ledger row 85, a closing command and an owner, and the note *"This checkbox may not be cited without citing row 85 alongside it."* Declared, not papered over. |
| **SRV-02** | `[x]` checked | ⚠️ SEE WARNING W3 — checked by 06-05 on a **local** run (`legs_total=4 legs_ran=4 legs_blocked=0`), while the manifest's own `cross-adapter-phase` reason string reads *"SRV-02 depends on this lane and stays unchecked."* |

### Anti-Patterns Found

Scanned all 123 non-`.planning`, non-markdown files changed across the phase's commit range
(`29f9f85~1..HEAD`):

| Pattern | Hits |
|---|---|
| `TBD` / `FIXME` / `XXX` (blocker gate) | **0** |
| `TODO` / `HACK` / `PLACEHOLDER` (warning) | **0** |

Clean. No debt markers, referenced or unreferenced.

---

## Warnings

**W1 — `SUPPLY-CHAIN.md` §1/§2/§3 present-tense claims (see §5).** Highest-value finding. The
document that exists to prevent overclaiming states Developer ID signing, SLSA provenance attestation
and CycloneDX SBOM generation as current facts, while at the bound revision the CI artifact is
unsigned, no attestation was produced and no SBOM was generated. Fix: one caveat sentence per
section, citing #91 and #88, matching the treatment #80 and #82 already get. Also consider pointing
`PRIVACY.md:24` / `SECURITY.md:39` at #85.

**W2 — `verify-release.mjs` does not verify lane evidence digests.** The manifest records
`evidenceDigestSha256` for 21 lanes, but the verifier recomputes only *artifact* digests
(`verify-release.mjs:236-252`); it never recomputes a lane's evidence digest and never checks that the
referenced evidence file exists. I recomputed all 21 by hand and **all match**, so the binding is
true today — but it is unguarded, so a future revision could record a wrong or dangling digest and
the verifier would pass it. This is the same class of hole the three fixtures were built to close,
one level down. Fix: hash `evidence/lanes/<lane>.log` in the verifier and fail on mismatch or absence;
add a fourth fixture.

**W3 — `SRV-02` is checked while its only lane is BLOCKED.** `.planning/REQUIREMENTS.md:21`. The
06-13 disclosure is exemplary — it states plainly that the 06-05 evidence *"was not a
continuous-integration run"*, that *"SRV-02 has no continuous-integration-authoritative evidence at
revision 26628e1"*, names ledger row 92, the closing command and owner BACKLOG, and explains that
re-adjudicating another plan's finding was out of scope. But the electron leg drove *the packaged Mac
app built locally*, which is precisely the binding the phase's own anti-loophole rule forbids, and
the manifest's own lane reason asserts the box should be unchecked. This is the only checked box in
the release whose supporting lane is BLOCKED. Routed to human.

**W4 — `tooling/local/publish-signing-secrets.sh` is untracked and *not* gitignored.** `git
check-ignore` returns nothing for `tooling/local/`. The script itself is clean (no hardcoded Apple
ID, Team ID, passphrase or certificate — everything is read from 1Password or derived at runtime),
so nothing would leak *today*, but a `git add -A` would commit a signing-secrets workflow into a
repository headed for public release. Fix: add `tooling/local/` to `.gitignore`.

**W5 — ROADMAP bookkeeping lags the work.** `.planning/ROADMAP.md` still shows `- [ ]
06-13-PLAN.md` unchecked, `**Plans:** 12/13 plans executed`, and a Progress row reading
`6. Portability and Trust Release | In Progress | 1 + cross-cutting verification | 0%` — while
`06-13-SUMMARY.md` exists and its commits are on `main`. Cosmetic, but this is a phase about claims
matching evidence.

**W6 — Two minor precision nits.** (a) The `trust-soak` lane reason string in the manifest says
*"every invariant I1-I10"*; the evidence file and D-53 both define **eight** invariants, I1–I8. (b)
`06-13-SUMMARY.md` frontmatter declares `commits: 2`; the phase's 06-13 work spans four commits
(`7352607`, `95e6e10`, `e1e4958`, `ca9e73c`, plus the follow-up `1e790f9`).

**W7 — `/Users/jon` in 75 tracked `.planning/` files** plus one test file (see §6). Low-severity
pre-public-release hygiene, out of this phase's declared scope.

---

## Claims I Could Not Substantiate

Stated explicitly so this report does not repeat the failure it is checking for:

1. **The contents of GitHub runs 34668212473 and 34668212479 were not refetched from the API** (per
   the rate-limit constraint). Every CI claim in this report was verified against the *committed*
   evidence under `.planning/releases/candidate-1/` — 21 lane logs and 2 full run logs whose digests
   I recomputed. If those committed logs were fabricated, nothing here would detect it. The manifest's
   own `runIds` are unverifiable offline by construction.
2. **The SLSA provenance attestations are `UNVERIFIED`, not absent-and-proven-absent.**
   `verify-release.mjs` reported `attestation=UNVERIFIED … reason=network-or-tool-unavailable` for all
   five artifacts, because `gh attestation verify` could not run offline. The *lane* status (BLOCKED,
   with `desktop-promote` skipped) is independent evidence that no attestation exists, so the two
   agree — but I did not independently prove absence at GitHub.
3. **The 129 MB packaged application bytes are not in this repository**, so I verified the *record*
   of those bytes (`desktop-macos-app.package-manifest.json`, digest recomputed and matching) rather
   than the bytes. The manifest says this plainly in `digestSha256Note`; I am repeating it because it
   is the correct caveat and it should not be lost.
4. **No CI lane was re-executed.** Running the 39-lane inventory locally would violate the
   anti-loophole rule this phase exists to enforce. I ran only read-only, non-mutating local checks:
   the release verifier against the real manifest and all three fixtures, the two governance scripts,
   the limitations generator, and the export reader's golden vector.
5. **SC5's sustained dogfood outcome is unmeasured, by the phase's own admission** — the trust-soak
   window has not accumulated (zero samples, detection floor `null`). This is correctly BLOCKED rather
   than claimed, and per standing project policy the owner's dogfood feedback is informal,
   non-evidentiary and non-gating. It is not a defect; it is simply not evidence yet.

---

## Where a Document or Checkbox Is Stronger Than Its Evidence

Complete list, strongest first:

1. **`docs/security/SUPPLY-CHAIN.md` §1** — asserts the packaged macOS application is Developer ID
   signed, hardened-runtime, notarized and stapled. The released CI artifact is none of these
   (window #91). *(The local build genuinely is all four — that fact is true and is not in dispute;
   the document simply does not distinguish the two.)*
2. **`docs/security/SUPPLY-CHAIN.md` §2** — asserts the pipeline emits a SLSA L2 attestation and
   calls it the load-bearing provenance control. It did not run at this revision (window #88).
3. **`docs/security/SUPPLY-CHAIN.md` §3** — asserts two CycloneDX SBOMs are generated at the release
   revision. `sbom-generation` is BLOCKED; none was generated.
4. **`.planning/REQUIREMENTS.md:21` `SRV-02` `[x]`** — checked on local evidence; its lane is BLOCKED
   and the manifest's own text says it stays unchecked. Fully disclosed inline (W3).
5. **`PRIVACY.md:24` / `SECURITY.md:39`** — cite `verify-privacy.sh` as live enforcement; that scan
   is red on one lane at this revision (window #85). The requirement ledger carries the tension; the
   public documents do not.
6. **`QUAL-05` `[x]`** — checked with an explicit, self-limiting named tension. Listed for
   completeness; the disclosure is strong enough that I do not consider it an overclaim.

Everything else I checked was either equal to or *weaker* than its evidence — including `QUAL-03`,
which this phase actively unchecked, and the 11 PASSED lanes, every one of which binds to a CI digest
with a positive case count.

---

_Verified: 2026-09-12T03:13:27Z_
_Verifier: Claude (gsd-verifier)_
