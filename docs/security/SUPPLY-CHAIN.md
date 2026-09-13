# Keepling supply-chain posture

This document states, plainly and separately, what each release control actually
proves. Conflating them is the real risk: a reader who thinks "signed" means "safe"
has learned nothing true, and a maintainer who believes the same thing has stopped
looking for the failure these controls do not catch.

Three claims, three headings. They do not overlap and none of them implies another.

## 1. Signing (Developer ID + hardened runtime + notarization + stapling)

**What it addresses:** launch experience and post-distribution tampering.

The packaged macOS application is signed with a Developer ID Application certificate
inside Electron Forge's own packaging step, so `tooling/package-desktop.mjs`'s
application digest is computed over the *signed* bytes rather than a digest that
signing would later invalidate. The bundle is notarized by Apple and the notarization
ticket is stapled onto it. A downloaded, stapled build opens without the "Keepling is
damaged and can't be opened" warning that an unsigned build produces on current
macOS, and the code directory hash recorded in the release manifest is the identity a
Gatekeeper check on the shipped file can be compared against after the fact.

**Status: TRUE AS OF REVISION `REWRITTEN-SHA`, BUT NOT OF THE RETAINED CANDIDATE.**
Continuous integration signs, notarizes and staples: at `REWRITTEN-SHA` the
`desktop-package` job imported the Developer ID identity, resolved it, and
reported `The staple and validate action worked!`, and both `desktop-packaged`
and `desktop-macos-integration` pass against those signed bytes. Window #91 is
closed.

The retained release candidate is a different matter and is deliberately not
restated. `.planning/releases/candidate-1/` is bound to revision `26628e1`,
which predates the signing secrets; that candidate's artifacts really are
unsigned, and its own committed package manifest records
`developerIdSigned: false`, `hardenedRuntime: false` and
`notarization.status: "not-attempted"`. A later capability does not
retroactively re-sign earlier bytes, and this section will not imply that it
does.

**What it does NOT address:** whether the bytes that were signed came from this
repository, or what is inside them. A correctly-signed application built from
tampered or malicious source is still correctly signed — signing proves the bytes
have not changed since a specific signing event, nothing about what decided their
content.

## 2. Provenance (SLSA Build Level 2 attestation)

**What it addresses:** whether the released bytes came from this repository's build.

The release pipeline emits a SLSA **Build Level 2** provenance attestation
(`actions/attest-build-provenance`) naming the packaged archive as its subject. This
project claims exactly Level 2 and nowhere claims Level 3: Level 3 requires a
reusable workflow with isolated signing, and this pipeline's build and attestation
steps share a single job — claiming Level 3 here would be an overclaim of precisely
the kind this document exists to correct.

**Status in the current release candidate: NO ATTESTATION WAS PRODUCED.** The
attestation step lives in the `desktop-promote` job, which was SKIPPED — its
`needs` gate requires every required desktop lane to have succeeded — so
`actions/attest-build-provenance` never ran and this candidate carries no
provenance attestation at all. Tracked as window #88 in `KNOWN-LIMITATIONS.md`.

**The self-hosted server's container image is NOT signed.** Nothing in this
repository builds or pushes that image to any registry, so there is no published
digest to sign; choosing a registry is a deferred decision, tracked as window #80 in
`KNOWN-LIMITATIONS.md`. When it is closed, the image will be signed keylessly by
digest using the GitHub Actions workflow's own OIDC identity (Sigstore/cosign), never
by mutable tag — a signature over a tag proves nothing about the bytes a puller
actually receives. Until then, treat the server image as carrying no provenance
guarantee whatsoever.

What is true today is the key-custody claim: no long-lived signing key exists
anywhere in this repository or in any maintainer's custody, and none will be
introduced to close the gap above.

SHA-256 checksums for the archive and the stapled application are published in the
GitHub Release body — a trust domain distinct from the self-hosted server serving the
same bytes, which is the only thing that gives a checksum any value. Read that
section for what it is: almost nobody will manually verify a checksum. The
load-bearing control for provenance is this attestation, not a hash a user is asked
to compare by hand. The nondeterminism canary lane was intended to share that load;
it currently fails for Developer ID builds, because notarization requires an embedded
RFC 3161 secure timestamp and a freshly-timestamped signature cannot be
byte-reproducible. That is tracked as window #82 and is not claimed as a working
control here.

**What it does NOT address:** whether the source code itself is trustworthy, or what
dependencies it pulls in. Provenance proves "this artifact was built by this
workflow from this commit" — it says nothing about whether that commit's
dependencies were themselves compromised.

## 3. Bill of materials (CycloneDX SBOM)

**What it addresses:** what is inside the release, so a later vulnerability
disclosure can be checked against a concrete, dated inventory.

Two CycloneDX documents are generated **from source**, at the release revision, never
by scanning the built application:

**Status in the current release candidate: NEITHER DOCUMENT EXISTS.** The
generator also lives in the skipped `desktop-promote` job, so
`tooling/generate-sbom.mjs` never ran and no bill of materials was produced for
this candidate. The description below is the design, not an inventory you can
go read today. Tracked as the `sbom-generation` lane's BLOCKED entry in the
release manifest.

- **Hex** — `apps/server/mix.exs` and `mix.lock`, via the dev-only, non-runtime
  `:sbom` mix task. Every first-party and third-party Hex component carries the
  licence declared in its own package metadata, including `keepling` itself
  (`Apache-2.0`, added by the licensing plan that landed before this generator).
- **npm** — the whole pnpm workspace's resolved dependency tree, via the CycloneDX
  project's own npm command-line tool (`@cyclonedx/cyclonedx-npm`), invoked through
  `npx` so it is never added to `package.json` or `pnpm-lock.yaml`.

Both are generated from source deliberately. `apps/desktop/forge.config.ts` ignores
`node_modules` and ships four pre-bundled outputs (main, preload, renderer, worker),
so a binary scan of the packaged `.app` would see minified, bundled code rather than
the workspace's hundreds of npm resolutions — a handful of entries presented as a
complete inventory for an application with hundreds of real dependencies is exactly
the vacuous-green failure this project has been burned by before.

**The Swift gap, declared out loud.** No CycloneDX document is generated for the
iOS client's dependencies. `apps/ios/Package.resolved` is published as-is, at its
existing committed path, with this gap named rather than papered over with a scan
that would under-report:

1. `apps/ios/Package.resolved`'s resolved-file format is `"version": 3`, which the
   common scanner (`syft`) cannot parse
   ([anchore/syft#2759](https://github.com/anchore/syft/issues/2759)).
2. Swift Package Manager's own native SBOM support is still only a proposal
   ([SE-0509](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0509-swiftpm-sbom.md)),
   not yet shipped in any released toolchain.

This gap closes when either upstream lands: a syft release that parses format
version 3, or SwiftPM ships SE-0509. Until then, the Swift lockfile itself remains
the only published inventory for that ecosystem, and it is complete for what it
covers (every pinned dependency and its resolved version) — it is simply not in
CycloneDX form.

**What it does NOT address:** whether any listed component is itself safe to run
today. An SBOM is an inventory, not a verdict; it makes a later vulnerability
disclosure checkable, it does not prevent one.

## The realistic adversary, named plainly

For a personal, pre-users GTD application, the realistic threat is a **malicious
dependency update** — a compromised maintainer account or a supply-chain attack
landing in a transitive dependency that this project then pulls in during ordinary
development.

**Every control in this document would happily sign, attest, and inventory that
dependency.** Signing proves the bytes did not change after packaging; it says
nothing about whether the source that produced them was trustworthy. Provenance
proves the build ran in this repository's own CI from a real commit; it does not
audit what that commit's `package.json` or `mix.exs` newly depend on. The SBOM
records that the compromised package is present; it does not flag that its latest
version is malicious.

What actually addresses this adversary is **not** any of the three controls above —
it is the project's own enforced provenance-review culture: dependency version
changes require a Provenance Audit (registry age, download counts, source
repository, verdict) before they are accepted, exactly the discipline
`06-RESEARCH.md`'s own Package Legitimacy Audit exercises for every tool this phase
itself introduces. That review culture is a process control, not a cryptographic
one, and it is the actual thing standing between a compromised upstream release and
a signed, attested, inventoried Keepling build that happily ships it.

## Legal posture: not a CRA manufacturer, today

Keepling is a personal, non-commercial, open-source project maintained by a single
natural person. The EU Cyber Resilience Act's manufacturer obligations do not apply
to a natural person acting outside a commercial or professional capacity, and do not
apply to a project with no commercial distribution. **Today, neither condition is
met and the CRA does not apply.**

**Flip condition:** this changes the moment a hosted, commercial offering ships. At
that point the maintainer becomes a manufacturer under the CRA's definitions, and
this document's SBOM and vulnerability-handling posture would need to be
re-evaluated against that regime's actual requirements — not assumed to already
satisfy them because the artifacts described above happen to exist.
