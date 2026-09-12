---
phase: KPL-06-portability-and-trust-release
plan: 10
subsystem: infra
tags: [codesign, notarization, gatekeeper, hardened-runtime, slsa, sigstore, cyclonedx, sbom, supply-chain, electron-forge]

requires:
  - phase: KPL-06 plan 06-02
    provides: "the ditto transport archive and archiveDigestSha256, which notarization is submitted against"
  - phase: KPL-06 plan 06-03
    provides: "package.json / mix.exs licence metadata, which CycloneDX reads into component licence fields"
provides:
  - "Developer ID signing INSIDE the electron-forge packager step, so applicationDigestSha256 describes the signed bytes"
  - "A measured, two-file, per-helper entitlement set reached through optionsForFile (never --deep)"
  - "Notarization and stapling after the signed digest and the transport archive are recorded"
  - "codeDirectoryHash in the package manifest as the identity that survives stapling"
  - "A fail-closed promotion gate holding the shipped stapled artifact to that identity"
  - "Job-scoped SLSA Build Level 2 provenance attestation on the packaged archive"
  - "Source-generated CycloneDX bills of materials for the Hex and npm ecosystems"
  - "docs/security/SUPPLY-CHAIN.md keeping signing, provenance and inventory as three separate claims"
affects: [06-13 release gate, any future macOS release, any future CI signing lane]

actuals:
  tokens: 18744
  tasks: 4
  commits: 3

tech-stack:
  added:
    - "@electron/osx-sign (already bundled with @electron-forge/cli 7.11.2 — no new dependency)"
    - "xcrun notarytool / xcrun stapler (Apple toolchain, no package added)"
    - "actions/attest-build-provenance (CI only)"
    - "@cyclonedx/cyclonedx-npm + the dev-only Hex :sbom mix task (CI only, npx-invoked, never entering the lockfile)"
  patterns:
    - "Sign inside the packaging step so the recorded digest is the signed digest"
    - "Record the pre-staple directory digest and the stapling-invariant code directory hash as two separate fields, never reconciled"
    - "Resolve signing identities at runtime by SHA-1 fingerprint; never commit a certificate common name"
    - "Measure entitlements one observed failure at a time; an entitlement with no named failure is a finding"

key-files:
  created:
    - apps/desktop/build/entitlements.plist
    - apps/desktop/build/entitlements.helper.plist
    - tooling/generate-sbom.mjs
    - docs/security/SUPPLY-CHAIN.md
  modified:
    - apps/desktop/forge.config.ts
    - tooling/package-desktop.mjs
    - .github/workflows/desktop.yml
    - .gitignore

key-decisions:
  - "Task 1 checkpoint resolved as option A: sign inside the packager step, digest the signed bundle, archive, notarize, staple, read the code directory hash, record both digests, gate the shipped stapled artifact on the code directory hash."
  - "Notarization is NOT configured through the packager's own notarization option, because @electron/notarize staples as its final act and would mutate the bundle before the packaging script hashes it — reintroducing the exact ordering defect the checkpoint exists to prevent."
  - "tooling/package-desktop.mjs, not forge.config.ts, is the single decider of whether a build is signed, because @electron/packager hardcodes continueOnError: true and turns a signing failure into a silently unsigned application."
  - "The signing identity is the certificate's SHA-1 fingerprint resolved at runtime, never its common name, which embeds a legal name and a team id this public repository must not carry."
  - "Both entitlement files carry exactly one key — com.apple.security.cs.allow-jit — each earned by a specific observed crash. The three further keys the circulated Electron template carries were never needed and are absent."
  - "The shipped stapled artifact is archived with ditto from the already-notarized bundle. That re-runs no packager and re-signs nothing; it is transport, not re-packaging."
  - "Server OCI image signing remains unimplemented and disclosed (window #80), because nothing in this repository pushes that image to any registry."

patterns-established:
  - "Two bindings kept deliberately apart: applicationDigestSha256 is what every gate tested; codeDirectoryHash is what a launch-time check on the shipped file shows."
  - "Fail-closed promotion: a manifest claiming a Developer ID signature with no reachable stapled artifact is refused, never waved through."
  - "Credential-carrying commands bypass the shared run() helper, which echoes its argument vector on failure."
  - "A signed build is not byte-reproducible: the required RFC 3161 secure timestamp makes every signature blob fresh. Reproducibility must be asserted over the payload, never over the signatures."

requirements-completed: [QUAL-03]

coverage:
  - id: D1
    description: "The packaged Mac application is Developer ID signed with the hardened runtime, inside the packager step, so the recorded application digest describes the signed bytes."
    requirement: QUAL-03
    verification:
      - kind: integration
        ref: "codesign --verify --strict --verbose=2 <applicationPath>"
        status: pass
      - kind: integration
        ref: "node -e manifest.codeSigning == {signed:true, developerIdSigned:true, hardenedRuntime:true}"
        status: pass
    human_judgment: false
  - id: D2
    description: "The signed application is notarized by Apple and the ticket stapled, so a downloaded build is accepted by Gatekeeper rather than reported as damaged."
    requirement: QUAL-03
    verification:
      - kind: integration
        ref: "spctl --assess --type execute --verbose <applicationPath> => accepted, source=Notarized Developer ID"
        status: pass
      - kind: integration
        ref: "xcrun notarytool submit --wait => status Accepted (submission 81b5419a-b3d9-4ea3-88ce-f6915968a74c); xcrun stapler staple => The staple and validate action worked!"
        status: pass
    human_judgment: false
  - id: D3
    description: "Each nested helper bundle receives its own entitlement set through the per-file callback rather than the main bundle's, and nothing is signed recursively."
    requirement: QUAL-03
    verification:
      - kind: integration
        ref: "codesign -d --entitlements - <app> => allow-jit; codesign -d --entitlements - <app>/Contents/Frameworks/Keepling Helper (Renderer).app => <dict/> before the helper key was earned"
        status: pass
      - kind: other
        ref: "sed 's|//.*$||' apps/desktop/forge.config.ts | grep -c 'optionsForFile' => 1"
        status: pass
    human_judgment: false
  - id: D4
    description: "The manifest records the pre-staple application digest, the archive digest and the stapling-invariant code directory hash as three distinct fields, and the code directory hash is proven unchanged across stapling on every run."
    requirement: QUAL-03
    verification:
      - kind: integration
        ref: "package-manifest.json carries applicationDigestSha256, archiveDigestSha256, codeDirectoryHash distinctly; the post-staple re-read equality assertion in tooling/package-desktop.mjs ran and passed"
        status: pass
    human_judgment: false
  - id: D5
    description: "The promotion path refuses a shipped stapled artifact whose code directory hash differs from the tested one, and refuses a signed claim with no artifact to check."
    requirement: QUAL-03
    verification:
      - kind: integration
        ref: "node tooling/package-desktop.mjs --promote <fixture with codeDirectoryHash=deadbeef...> => exit 1, 'does not match the tested'"
        status: pass
      - kind: integration
        ref: "node tooling/package-desktop.mjs --promote <fixture with both stapled paths nulled> => exit 1, 'names no reachable stapled artifact'"
        status: pass
    human_judgment: false
  - id: D6
    description: "The signed bundle still survives the artifact transport introduced in plan 06-02 and still runs the full packaged behaviour suite."
    requirement: QUAL-03
    verification:
      - kind: e2e
        ref: "pnpm smoke:desktop:packaged => 11 passed, digest a10ca33303a1b8ad61e44769b527fd99a9a74cf57d2494ab89e9aae46f52e53d"
        status: pass
    human_judgment: false
  - id: D7
    description: "The release carries a SLSA Build Level 2 provenance attestation naming the packaged archive, with OIDC granted at job level only, and no document claims a higher level."
    requirement: QUAL-03
    verification:
      - kind: other
        ref: "node tooling/check-ci-contract.mjs => lanes=9 pins=full-sha; grep 'id-token: write' => single match inside desktop-promote; SLSA-overclaim grep => no matches"
        status: pass
    human_judgment: true
    rationale: "The attestation step's runtime behaviour has never executed: this repository has no git remote and no workflow in .github/workflows has ever run. Only the static shape is proven."
  - id: D8
    description: "The bills of materials are generated from source for the Hex and npm ecosystems, and the Swift gap is declared with both of its causes."
    requirement: QUAL-03
    verification:
      - kind: other
        ref: "node tooling/generate-sbom.mjs --out /tmp/keepling-sbom (plan 06-10 Task 3/4 commit bb43580)"
        status: pass
    human_judgment: false
  - id: D9
    description: "The server container image is signed keylessly by digest."
    verification: []
    human_judgment: true
    rationale: "NOT DELIVERED. Nothing in this repository builds or pushes the server image to any registry, so there is no digest to sign. Recorded as window #80 with a named closing condition. This entry exists so the gap is visible rather than absent."

duration: 4h 10m
completed: 2026-09-12
status: complete
---

# Phase KPL-06 Plan 10: Signed, Notarized and Attributable Release Summary

**The packaged Mac application is now Developer ID signed inside the packager step, notarized, stapled, and accepted by Gatekeeper as `source=Notarized Developer ID`, with the tested digest and the stapling-invariant code directory hash recorded as two separate bindings and the shipped artifact gated on the latter.**

## Performance

- **Duration:** ~4h 10m across two sessions (Task 3/4 in commit `bb43580`; Task 2 resumed after the deliberate pause recorded in `.continue-here.md`).
- **Tasks:** 4 of 4.
- **Commits:** 3 (`bb43580` Tasks 3+4, `c7a74ce` Task 2, plus this summary).
- **Files:** 8 (4 created, 4 modified).

## Task 1 — decision record

The checkpoint was resolved as **option A**, confirmed by the owner and treated as binding for Task 2:

1. The packager step runs with signing configured through the packager's own signing option, so the bundle is signed before the packaging script's hashing call executes.
2. The application digest is computed over the signed bundle.
3. The lossless `ditto` archive is made from the signed bundle and its digest recorded.
4. Notarization is submitted against that archive.
5. The ticket is stapled onto the bundle, mutating it again, irreducibly.
6. The code directory hash is read from the signed bundle and recorded separately — it is the identity that survives stapling.
7. The manifest records **both** the pre-staple application digest (what every gate tested) and the code directory hash (what a launch-time check on the shipped file shows).
8. The shipped stapled artifact is gated on its code directory hash equalling the tested one.

The three attached rules held throughout: no attempt was made to stabilise the directory hash across stapling; the application was never re-packaged after notarizing; and nothing was signed with the recursive/deep option — per-helper entitlements go through the per-file callback.

**Credential availability, confirmed at the checkpoint:** the paid Apple Developer Program membership is active, a Developer ID Application certificate is installed locally, and notarization credentials are stored and validated as a keychain profile. The full local chain was therefore exercisable and was exercised. The five values as **GitHub repository secrets** are a separate, still-outstanding owner action (see Outstanding, below); CI has never run at all.

## Accomplishments

### Task 2 — sign, notarize, staple, record the surviving identity

**Signing runs inside the packager step.** `apps/desktop/forge.config.ts` gains `osxSign` and nothing else: every pre-existing `packagerConfig` key is byte-identical. `tooling/package-desktop.mjs` computes `applicationDigestSha256` immediately after the packager returns, so that digest now describes the signed bytes.

**Notarization is deliberately NOT configured through the packager.** `@electron/notarize` staples the ticket as its final act, which would mutate the `.app` *before* the packaging script hashes it — reintroducing the exact ordering defect the checkpoint exists to prevent. Notarization and stapling therefore run in `tooling/package-desktop.mjs`, after the signed digest and the transport archive are both recorded. This is a documented deviation from the plan's prose (see Deviations).

**The identity never touches a committed file.** It is resolved at runtime as the certificate's SHA-1 fingerprint from a `security find-identity -v -p codesigning` listing, matched against the `Developer ID Application:` prefix and refused if ambiguous. No whole-keychain verb is used anywhere; no common name, legal name or team id is written, logged or recorded.

**The build now fails loudly when signing fails.** `@electron/packager` hardcodes `continueOnError: true` when it hands the bundle to `@electron/osx-sign`, so a signing failure produces a green build and a silently unsigned application — the vacuous green this project has repeatedly been burned by. `tooling/package-desktop.mjs` is now the single decider: it resolves the identity, passes it to the packager through the environment, and fails the build when an identity was resolvable but the bundle came back merely ad-hoc signed. **This guard caught a real failure during this task** (see Deviations).

**Two bindings, kept apart.** The manifest (schema version 2) now carries `applicationDigestSha256`, `archiveDigestSha256` and `codeDirectoryHash` as three distinct fields, plus honest `codeSigning` and `notarization` records that default to `not-attempted` rather than to anything optimistic. After stapling, the code directory hash is re-read and proven equal to the pre-staple value — the claim is measured on every run, not asserted once.

**The promotion path is fail-closed.** `--promote` refuses a manifest that claims a Developer ID signature but lacks `codeDirectoryHash`, refuses one that names no reachable stapled artifact, and refuses one whose shipped artifact's code directory hash differs from the tested value. It resolves the artifact either from the stapled bundle directly or by expanding the stapled archive, so the CI path (where only files travel) is checked as strictly as the local one.

**CI wiring is fork-safe and says so.** The Apple credentials are reachable only from a `push` event; the identity is imported into an ephemeral, run-scoped keychain, and `security find-identity` is scoped to that keychain. Every run that cannot reach the secrets emits an explicit `::notice title=Unsigned build::` rather than being silently indistinguishable from a signed one. Both the tested archive and the stapled archive travel as artifacts, and the promotion job rebases the stapled path onto its own download before the gate runs.

### Entitlements — measured, and each one named with its failure

Both files started as an **empty `<dict/>`**. Exactly one key was earned, in each file, by a specific observed failure:

| File | Entitlement | The observed failure that motivated it |
|---|---|---|
| `apps/desktop/build/entitlements.plist` | `com.apple.security.cs.allow-jit` | With an empty dict and the hardened runtime enabled, the packaged main executable aborted during `package-desktop.mjs`'s embedded-versions probe with `# Fatal process out of memory: Failed to reserve virtual memory for CodeRange` — V8 could not map its JIT code range. Packaging exited 1. Adding this one key made the same probe succeed. |
| `apps/desktop/build/entitlements.helper.plist` | `com.apple.security.cs.allow-jit` | With the main bundle fixed and the helper file still an empty dict, every packaged Playwright spec failed with `Error: Target crashed` within ~400 ms. The renderer helper's crash report shows `EXC_BREAKPOINT (SIGTRAP)`, `Trace/BPT trap: 5` — the same V8 abort in the renderer process. Adding this one key took the suite from 0/11 to 10/11. |

**Entitlements deliberately NOT present**, because no observed failure demanded them: `com.apple.security.cs.allow-unsigned-executable-memory`, `com.apple.security.cs.disable-library-validation`, `com.apple.security.cs.allow-dyld-environment-variables`, and every `com.apple.security.*` sandbox or device key. The permissive four-key template that circulates for Electron applications would have added three unearned hardened-runtime exceptions. `06-RESEARCH.md`'s second open question — Keepling's required entitlements were never enumerated — is now closed with a measurement: **one key, both files.**

Two incidental findings from the measurement, both recorded in code comments:

- The plists carry **no XML comments**. `codesign` parses entitlements with AMFI, which rejects a comment outright (`Failed to parse entitlements: AMFIUnserializeXML: syntax error near line 8`). The rationale lives in `forge.config.ts` and here instead.
- `apps/desktop/build/` had to be un-ignored in `.gitignore`: the blanket `build/` rule would have silently untracked both entitlement files, making the signed bundle depend on files no clone contains.

### Tasks 3 and 4 (landed earlier, in commit `bb43580`)

- `desktop-promote` gains `id-token: write` and `attestations: write` **at job level only**, with the workflow-level block left at `contents: read`, and an `actions/attest-build-provenance` step naming the packaged archive as its subject. The claim is fixed at exactly **SLSA Build Level 2**; a grep gate fails on any affirmative claim above it.
- `tooling/generate-sbom.mjs` produces two CycloneDX documents **from source** — Hex via the dev-only mix task plan 06-03 added, npm via the CycloneDX project's own CLI invoked without entering the lockfile — never by scanning the built `.app`, which would report a handful of components for an application with hundreds of npm resolutions.
- A release-body checksum template is generated for the archive and, now that Task 2 has landed, the stapled application's code directory hash — worded so the load-bearing controls are named as the reproducibility lane and the provenance attestation, not the hash.
- `docs/security/SUPPLY-CHAIN.md` keeps signing, provenance and inventory as three separately-headed claims, names the malicious-dependency-update adversary that every one of them would happily sign, declares the Swift gap with both causes, and records the non-manufacturer regulatory posture with its flip condition.

## Verification — every gate's actual result

### Task 2 gates (all five, as written in the plan)

| Gate | Result |
|---|---|
| `pnpm package:desktop` | **PASS** (exit 0). Manifest carries `codeDirectoryHash` = `16d0a2b773d167e0451273aaf7cf981d3323d806`. |
| `codesign --verify --strict --verbose=2 <applicationPath>` | **PASS** (exit 0) — `valid on disk`, `satisfies its Designated Requirement`. |
| `spctl --assess --type execute --verbose <applicationPath>` | **PASS** (exit 0) — `accepted`, `source=Notarized Developer ID`. No `rejected` in output. |
| `pnpm smoke:desktop:packaged` | **PASS** (exit 0) — `11 passed`, digest `a10ca33303a1b8ad61e44769b527fd99a9a74cf57d2494ab89e9aae46f52e53d`. No `digest does not match`. |
| `sed 's\|//.*$\|\|' apps/desktop/forge.config.ts \| grep -c 'optionsForFile'` | **PASS** — count `1` (non-zero). |

Notarization itself: `xcrun notarytool submit --wait` returned `status: Accepted`, submission `81b5419a-b3d9-4ea3-88ce-f6915968a74c`; `xcrun stapler staple` reported `The staple and validate action worked!`.

### Acceptance criteria

| Criterion | Result |
|---|---|
| Pre-existing `packagerConfig` keys byte-identical; signing + hardened runtime + per-file callback + notarization added | **PASS**, with one deviation: notarization lives in `package-desktop.mjs`, not `packagerConfig` — see Deviations. |
| Both entitlement files exist and are tracked; summary names each entitlement with its observed failure | **PASS** (table above). |
| Manifest contains `applicationDigestSha256`, `archiveDigestSha256`, `codeDirectoryHash` as three distinct fields | **PASS**. |
| Promotion path fails on a deliberately mismatched code directory hash | **PASS**, proven against two fixtures (below). |
| `codesign --verify --strict` and `spctl --assess --type execute` both succeed | **PASS**. |
| No step re-packages after notarization | **PASS**. The stapled archive is a `ditto` of the already-notarized bundle; no packager re-run, no re-sign, no byte altered. |

### The deliberately mismatched fixtures (reproducible)

```
FIXTURE A  manifest.codeDirectoryHash := deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
           node tooling/package-desktop.mjs --promote <fixture>
           => exit 1: "the shipped stapled artifact's code directory hash
              16d0a2b773d167e0451273aaf7cf981d3323d806 does not match the tested
              deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

FIXTURE B  manifest.stapledApplicationPath := null; manifest.stapledArchivePath := null
           => exit 1: "promotion manifest claims a Developer ID signature but names
              no reachable stapled artifact to check the code directory hash against"

FIXTURE C  manifest.stapledApplicationPath := null (archive only — the CI shape)
           => exit 0: "Shipped stapled artifact gated: codeDirectoryHash=16d0a2b7..."
```

### Task 3 gates (re-run after this task edited the same workflow file)

| Gate | Result |
|---|---|
| `node tooling/check-ci-contract.mjs` | **PASS** — `lanes=9 pins=full-sha caches=exact scheduled=non-vacuous privacy_self_test=passed`. |
| Full-SHA pinning check | **PASS** — `pinned=19`, no unpinned references. |
| `grep 'id-token: write'` | **PASS** — single match, inside `desktop-promote`, not the workflow-level block. |
| SLSA-above-2 overclaim grep | **PASS** — no matches (`exit=1`, the passing outcome). |
| `yaml.safe_load` of the edited workflow | **PASS** — six jobs parse. |

## Gates that did NOT pass

**1. `node tooling/verify-release.mjs --manifest .planning/releases/candidate-0/release-manifest.json --offline` — FAILS (exit 1).**
This is the pre-existing, correct failure already recorded in `.continue-here.md`, not a regression from this plan:

```
verify-release failed: lane vanished from manifest: export-elixir
verify-release failed: lane vanished from manifest: export-reader
verify-release failed: revision f7b7c902... verification did not pass (PASSED)
```

Plan 06-08 added two lanes that the `candidate-0` manifest predates; this is the vanished-lane detection working as designed. Regenerating the manifest — which will also pick up the new `codeDirectoryHash` and stapled-artifact fields — is **06-13's declared scope**.

**2. CI has never executed any of this.** This repository has no git remote. The `desktop.yml` signing, attestation, image-signing and SBOM steps are proven only as static shape (contract check, pinning, permission scoping, YAML parse). QUAL-02 stays unchecked. The five Apple values are **not** present as GitHub repository secrets — that remains an owner action, and the `.p12` has not been exported.

**3. `node tooling/verify-desktop-phase.mjs` — FAILS (exit 1), and this plan made it worse: 9 of 11 lanes, not the 10 of 11 the handoff recorded.**

```
FAIL package-reproducible   cases=0   <- NEW, caused by this plan
FAIL macos-integration      cases=0   <- pre-existing, stale evidence cache
```

- **`macos-integration`** is the known, already-disclosed failure: it has no cached evidence for the current packaged-artifact digest, and this plan changed that digest again, by design, since the bundle is now signed. Regenerating it is 06-13's declared scope.
- **`package-reproducible` is a genuine regression introduced by this plan, and it is reported rather than smoothed over.** Two separate builds at one clean revision now differ in **16 of 618 compared entries** — and the 16 are *exactly* the signature-bearing ones: every signed Mach-O (the Electron Framework, all four helpers, `Contents/MacOS/Keepling`, the bundled dylibs) plus both `_CodeSignature/CodeResources` files. The other 602 entries are byte-identical, so the *payload* is still reproducible; the signatures are not.

  **The cause is not a defect and cannot be removed.** `@electron/osx-sign` signs with `--timestamp`, which embeds a fresh RFC 3161 secure timestamp from Apple's timestamp authority into every signature blob. A secure timestamp is **required** for notarization, so dropping it to regain byte-identical signatures would trade a working Gatekeeper story for a reproducibility number. A signed build is not byte-reproducible, by construction.

  **It is deliberately NOT fixed here**, for two reasons: the lane lives in `tooling/verify-package-reproducibility.mjs` / `tooling/verify-desktop-phase.mjs`, outside this task's declared file scope; and the tempting "fix" — loosening the comparison to ignore signature blobs — is precisely the loosened-binding trap the Task 1 checkpoint exists to refuse. See the findings below for the two honest options.

## Deviations from Plan

**1. [Rule 1 — ordering correctness] Notarization runs in `package-desktop.mjs`, not through `packagerConfig.osxNotarize`.**
- **Found during:** Task 2, while reconciling the plan's action prose with the Task 1 decision.
- **Issue:** The plan's prose says "configure notarization through the packager's notarization option". `@electron/notarize` **staples the ticket as its final act**, which mutates the `.app` before `package-desktop.mjs` computes `applicationDigestSha256`. Following the prose literally would have reintroduced the exact silent-mismatch defect the Task 1 checkpoint exists to prevent, with every gate green.
- **Fix:** Notarization and stapling moved to `tooling/package-desktop.mjs`, after the signed digest and the transport archive are recorded — steps 4–6 of the confirmed ordering. The binding decision outranks the prose.
- **Files:** `apps/desktop/forge.config.ts` (documents the omission and why), `tooling/package-desktop.mjs`.
- **Commit:** `c7a74ce`.

**2. [Rule 1 — bug, caught by the new guard] `@electron/packager` swallowed a real signing failure.**
- **Found during:** Task 2, first signed packaging run.
- **Issue:** `@electron/osx-sign`'s identity validation matches the identity string against the certificate's **common name**, so it rejected the SHA-1 fingerprint outright — and `@electron/packager` hardcodes `continueOnError: true`, so the build exited 0 with an **ad-hoc-signed** bundle and no message anywhere. The manifest would have recorded `developerIdSigned: false` and the release would have looked fine.
- **Fix:** `identityValidation: false` (`codesign -s` accepts the fingerprint directly), plus a new hard assertion in `package-desktop.mjs`: if an identity was resolvable and the bundle is not Developer ID signed, the build fails. That assertion then fired for real on the next run and produced exactly the loud failure it exists to produce.
- **Files:** `apps/desktop/forge.config.ts`, `tooling/package-desktop.mjs`.
- **Commit:** `c7a74ce`.

**3. [Rule 3 — blocker] `.gitignore`'s blanket `build/` rule would have untracked both entitlement files.**
- **Found during:** Task 2, before the first signed build.
- **Issue:** `build/` matches `apps/desktop/build/` at any depth. Both entitlement files would have been silently untracked, leaving the signed bundle dependent on files no clone contains — and the acceptance criterion explicitly requires them tracked.
- **Fix:** an `!apps/desktop/build/` exception with a comment explaining why it must stay.
- **Files:** `.gitignore` (outside the plan's declared `files_modified`, added as a blocking fix).
- **Commit:** `c7a74ce`.

**4. [Rule 3 — blocker] Entitlement plists cannot carry XML comments.**
- **Found during:** Task 2, first signing attempt — `Failed to parse entitlements: AMFIUnserializeXML: syntax error near line 8`, raised while signing a `locale.pak`.
- **Fix:** both files rewritten comment-free; the measured-not-copied rationale moved into `forge.config.ts` and this summary.
- **Commit:** `c7a74ce`.

**5. [Rule 3 — blocker] The plan's gates name a manifest path the packaging script never wrote.**
- **Found during:** Task 2, running the plan's own verify commands.
- **Issue:** two gates read `./apps/desktop/out/keepling-package-manifest.json`; the script writes its manifest into a `mkdtemp` artifact root and records the path in a tmpdir locator file.
- **Fix:** the script now also writes a well-known copy at that path. The authoritative manifest remains the one under the artifact root, and the copy is never promoted. `apps/desktop/out/` is gitignored build output.
- **Commit:** `c7a74ce`.

**6. [additive] A stapled transport archive and two extra manifest fields.**
- **Issue:** the tested archive is made pre-staple, so a downloader receiving only that archive gets an application **without** a stapled ticket, which needs an online Gatekeeper check to open — undercutting the user story this plan exists to serve.
- **Fix:** after stapling, a second `ditto` archive of the already-notarized bundle is produced and its digest recorded as `stapledArchiveDigestSha256`, alongside `stapledApplicationPath`/`stapledArchivePath`. This re-runs no packager, re-signs nothing, and alters no byte of the bundle — it is transport, not re-packaging. The two archive digests are never interchangeable.
- **Commit:** `c7a74ce`.

**Total deviations:** 6 (2 correctness, 3 blockers, 1 additive). **Impact:** the confirmed ordering is implemented exactly; two of the six exist specifically because following the plan's literal prose would have produced a silently-wrong result.

## Authentication Gates

Two interactive macOS prompts occurred during Task 2, both normal first-use flow, neither a failure:

1. **Codesign private-key authorization** the first time `codesign` used the Developer ID key.
2. **Keychain authorization for `safeStorage`.** After the bundle's identity changed from ad-hoc to Developer ID, `safeStorage.isEncryptionAvailable()` blocked on a `SecurityAgent` prompt and the packaged security spec timed out at 60 s (10/11 passing). Once the prompt was answered, the same spec passed in 470 ms and the full suite went to 11/11. **No entitlement was added for this** — a keychain prompt is an ACL decision, not an entitlement gap, and `com.apple.security.keychain-access-groups` would not have prevented it. This is worth knowing for CI: a hosted runner with a fresh ephemeral keychain will not raise the prompt, but any *new* signing identity re-raises it on a developer machine.

## Known Stubs

None introduced by this plan.

## Findings for a gap-closure plan (not fixed inline — outside this task's file scope)

1. **`docs/security/SUPPLY-CHAIN.md` §2 claims the server container image "is signed keylessly, by digest" — it is not.** Window #80 records the deferral and states in terms: *"Until it is closed, no supply-chain document may claim the server image is signed."* The document does. This is a live no-overclaim violation in a public-facing trust document and should be corrected to future/conditional wording before the repository goes public. It predates this task (commit `bb43580`) and lives in Task 4's file, so it is reported rather than edited here. **Recorded as window #81** (`unmet-truth`, open) in `.planning/WINDOWS.md`, hand-edited per the procedure window #79 documents, so it survives past this summary and blocks `/gsd-ship`.
2. **`tooling/local/publish-signing-secrets.sh` is untracked.** It was written during the prior session and is referenced by the phase handoff. It contains no PII (checked). Decide deliberately whether it is committed or gitignored, rather than leaving it in limbo.
3. **`verify-release.mjs`'s release manifest predates two lanes and now also predates the signing fields.** 06-13 owns the regeneration; it should pick up `codeDirectoryHash`, `stapledArchiveDigestSha256` and the `codeSigning`/`notarization` records so the release evidence describes the signed artifact.
4. **`package-reproducible` must be re-scoped to what a signed build can honestly promise** (recorded as window #82). Two options, both honest; pick one deliberately rather than by default:
   - **(a) Measure reproducibility on the unsigned payload.** The lane invokes `pnpm package:desktop` with `KEEPLING_MACOS_SKIP_SIGNING=1` (the escape hatch already exists in `forge.config.ts` and `tooling/package-desktop.mjs`), so it keeps asserting byte-identical *builds* and stops asserting byte-identical *signatures*, which no signed build can provide. One environment variable in the lane invocation; nothing loosened.
   - **(b) Keep signing on and assert the narrower true thing:** that every non-signature entry is identical AND that the differing set is exactly the signature-bearing set. Stronger, but it needs a real signature-blob classifier — do not approximate it with a path allowlist, which would silently stop noticing a genuine payload change inside a signed binary.

   What must NOT happen is the third option nobody should take: relaxing the existing comparison to "ignore these 16 paths" and calling the lane green again.
5. **The promotion code-directory-hash gate is proven by a reproducible manual fixture, not by a checked-in regression test.** The three fixture invocations are recorded above verbatim; promoting them into a `tooling/` self-test would keep the gate honest as the manifest schema evolves.

## Outstanding owner actions

- Export the **single** Developer ID identity from Keychain Access (never a bulk keychain export) and run `./tooling/local/publish-signing-secrets.sh` to publish the five repository secrets. Until then the CI signing path cannot execute.
- GitHub → Settings → Actions → General: confirm Actions may create attestations.

## Next

Ready for **06-13**, the release gate, which owes the release-manifest regeneration and the `macos-integration` evidence regeneration, and which is now also the first consumer of `codeDirectoryHash`.

## Self-Check: PASSED

- `apps/desktop/build/entitlements.plist` — FOUND
- `apps/desktop/build/entitlements.helper.plist` — FOUND
- `tooling/generate-sbom.mjs` — FOUND
- `docs/security/SUPPLY-CHAIN.md` — FOUND
- commit `bb43580` — FOUND
- commit `c7a74ce` — FOUND
