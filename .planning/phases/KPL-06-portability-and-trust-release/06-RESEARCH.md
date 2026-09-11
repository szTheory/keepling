# Phase 6: Portability and Trust Release - Research

**Researched:** 2026-09-11
**Domain:** Neutral data export, release provenance/signing, SBOM/supply-chain posture, OSS governance, cross-adapter test wiring, read-only reconciliation oracle
**Confidence:** MEDIUM (mechanics of in-repo code are HIGH/VERIFIED; external tool syntax is MEDIUM/CITED against current docs; a few CONTEXT.md background claims were found stale during this research and are corrected below)

## Summary

06-CONTEXT.md (D-01 through D-54) already makes every architectural decision for this phase; this
research does not re-litigate any of them. What it adds is the concrete, runnable mechanics the
planner needs to turn each decision into tasks: (1) the exact Elixir/Ecto pattern for a
transactional, chunked, streaming export inside the existing `Ops` verb machinery; (2) the exact
ordering of Electron Forge packaging → codesign → notarize → staple so the digest the phase binds
evidence to is the digest that ships (D-17's "signing-invalidates-the-tested-digest trap"); (3) the
exact GitHub Actions permissions and action calls needed for SLSA-L2 build provenance
(`actions/attest-build-provenance`) and cosign keyless OCI signing; (4) SBOM tool choices for Hex
and npm; and (5) two findings that correct background claims in 06-CONTEXT.md's `<code_context>`
section that this research found to be *aspirational, not actual* when checked against source.

**Correction to 06-CONTEXT.md's `<code_context>` "Reusable Assets" list:** `Repo.stream` does not
currently appear anywhere in `apps/server/lib` — grepped and confirmed zero hits. Only one
`Repo.transaction` call site exists in the whole server app
(`apps/server/lib/keepling/adapters/postgres/preview.ex:70`). D-08(a)'s "run the whole export in
one `Repo.transaction` at `REPEATABLE READ`" is achievable exactly as decided, but D-08(b)'s
"bounded reads" and the `<code_context>` claim that `Repo.stream` is "the existing pattern... the
export's memory bound depends on it" is **not** an existing pattern in this codebase — the export
plan introduces `Repo.stream` for the first time. This does not change any decision, but the
planner should not describe it as "reuse an existing streaming pattern" — it is new machinery
built on a well-documented Ecto primitive, and needs its own test coverage rather than inheriting
proof from a sibling call site that doesn't exist.

**Primary recommendation:** Sequence work exactly per D-54; for each of the five mechanically
novel areas below, use the runnable commands and code skeletons in this document rather than
re-deriving tool syntax from training memory, since GitHub Actions attestation and cosign syntax
have changed meaningfully across recent major versions.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Neutral data export (DATA-01) | API/Backend (Elixir `Ops` application layer) | Database (PostgreSQL, `Repo.stream`) | D-05 locks this as a new `Ops` verb; export logic must stay inward of the domain per AGENTS.md's modular-monolith rule, never a raw SQL script |
| Export format/schema (`FORMAT.md`, JSON Schema) | Contracts package (`packages/contracts/schemas/export/`) | — | D-03: standalone schema, decoupled from OpenAPI's protocol-train lifecycle |
| Release manifest + verification (`verify-release.mjs`) | CI/Build tooling (`tooling/`) | GitHub Actions (macOS + Ubuntu runners) | D-12: extends existing digest-binding machinery; must run offline-capable (D-15d) |
| macOS code signing / notarization | Build tooling (`package-desktop.mjs`, `forge.config.ts`) inside CI (`desktop.yml`, macOS runner) | — | D-16/D-17: must run *inside* Forge's package step so the tested digest is the signed digest |
| SBOM generation | Build tooling, per-ecosystem (Hex: `mix sbom.cyclonedx`; npm: `cyclonedx-npm`) | CI (`desktop-promote` job) | D-20: generated from source per-release, not scanned from the built artifact |
| Server OCI image signing | CI (cosign via GH OIDC) | Registry (GHCR or wherever image is pushed) | D-19: keyless, no key custody |
| Governance/policy documents | Repo root (static files) | CI (`check-repository-integrity.sh` governance lane) | D-32: files plus a machine-checked anti-drift lane |
| Cross-adapter electron/iphone legs (SRV-02) | Build tooling drivers (`tooling/cross-adapter/legs.mjs`) | Desktop main process (IPC) / iOS simulator (UI automation) | D-36: wiring over existing harnesses, not new invention |
| Data-loss fixes (O-43/O-44/O-22) | Desktop renderer + store-worker (Electron) | Shared UI package (`packages/web-ui`) | D-37: `local-store.ts` (storage layer) and `ConflictResolver.tsx`/`DesktopShell.tsx` (presentation layer) both need changes |
| Agent-consent surface (window 76) | API/Backend (`device_grant_controller.ex`) | Contracts (OpenAPI `DeviceGrantSummary`) | D-38: publish fields the server already partially has (`scope`) and partially lacks (`last_used_at` — see finding below) |
| Trust oracle (SC5) | New standalone tooling (`tooling/trust-lanes/`) | Database (read-only role), Desktop SQLite (ro), iOS (via `devicectl`) | D-45: imports no client code; reads three independent sources |

## Standard Stack

### Core (no new runtime dependencies — all built on already-pinned tooling)

| Library/Tool | Version | Purpose | Why Standard |
|---|---|---|---|
| Ecto (`Repo.stream`, `Repo.transaction`) | already pinned in `mix.lock` | Bounded, transactional export reads | Ecto's `Repo.stream/2` is the documented mechanism for cursor-based chunked reads inside a transaction; no new dependency |
| `mix_sbom` (hex package `sbom`, `erlef/mix_sbom`) | latest on hex.pm; verify at plan time with `mix hex.info sbom` | CycloneDX SBOM from Hex deps | `[CITED: hexdocs.pm/sbom]` — the only Elixir-ecosystem-native CycloneDX generator; add `only: :dev, runtime: false` and do not run under `MIX_ENV=prod` |
| `@cyclonedx/cyclonedx-npm` | 6.0.1 confirmed on npm registry at research time | CycloneDX SBOM from npm deps | `[VERIFIED: npm registry — package-legitimacy check verdict OK, weeklyDownloads 370402, repo github.com/CycloneDX/cyclonedx-node-npm]`. Run via `npx @cyclonedx/cyclonedx-npm --output-format JSON --output-file sbom-npm.cdx.json`, no lockfile install needed |
| `actions/attest-build-provenance` | pin to a full commit SHA (repo's own convention — see `check-ci-contract.mjs` pinning rule) | SLSA Build L2 provenance attestation | `[CITED: docs.github.com/actions/security-for-github-actions/using-artifact-attestations]` — official GitHub docs |
| `cosign` (sigstore) | latest release; install via `sigstore/cosign-installer` action or a pinned binary download | Keyless OCI image signing | `[CITED: docs.sigstore.dev, github.com/sigstore/cosign]` |
| `@electron/osx-sign` (transitively via `@electron-forge/cli` 7.11.2's packager) | already bundled by Forge — no new install | macOS codesign step, invoked via `packagerConfig.osxSign` | `[VERIFIED: apps/desktop/package.json:30-31 pins @electron-forge/cli 7.11.2]`; Forge's packager internally calls `@electron/osx-sign` when `osxSign` is set — no separate package to add |

### Supporting

| Tool | Purpose | When to Use |
|---|---|---|
| `ditto` (macOS-native, no install) | Lossless `.app` archive/expand preserving POSIX modes | D-11's fix for the actions/upload-artifact digest-mismatch defect — `ditto -c -k --sequesterRsrc --keepParent <app> <zip>` out, `ditto -x -k <zip> <dir>` in |
| `codesign -dvvv --verbose=4` | Extract `CDHash` (code directory hash) that survives stapling | D-17(b) — the identity to bind post-staple evidence to |
| `xcrun notarytool` | Apple notarization submission (replaces deprecated `altool`) | Invoked by Forge's `osxNotarize`, or directly if bypassing Forge's built-in step |
| `information_schema.columns` (raw SQL via `Ecto.Adapters.SQL.query!`) | D-07(1) schema-driven completeness check | Enumerate live columns; fail export test if a column isn't in the classification manifest |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|---|---|---|
| `mix sbom.cyclonedx` (hex `sbom` pkg) | `syft` for Hex | `syft` support for Elixir/Hex lockfiles is weaker than Elixir-native tooling and adds a non-BEAM binary dependency; rejected per AGENTS.md's "prefer BEAM/OTP... shallow dependency trees" |
| `@cyclonedx/cyclonedx-npm` | `syft` or `cdxgen` for npm | `cdxgen` pulls in a much larger dependency surface and additional runtime requirements (Java for some enrichers); `cyclonedx-npm` is CycloneDX's own first-party npm tool, single-purpose, `npx`-invocable with no lockfile pollution |
| `actions/attest-build-provenance` action | Hand-rolled in-toto/SLSA provenance generation | GitHub's own action is the load-bearing, officially supported mechanism for `attestations: write`; hand-rolling would fail Don't-Hand-Roll guidance below |
| GitHub App `dcoapp/app` for DCO | `KineticCafe/actions-dco` workflow-based Action | The App requires zero workflow YAML (installed once via GitHub Marketplace, needs no `permissions:` grant in any workflow) — simpler for a solo-maintainer repo already at capacity on required lanes; the Action needs `pull-requests: write` if it comments. Recommend the App unless org-level app installation is undesired. |

**Installation:** No new dependencies land in any lockfile for the core signing/SBOM/provenance
work — `cyclonedx-npm` and `cosign` are invoked via `npx`/binary-download inside CI, `mix_sbom`
is a dev-only, `runtime: false` mix dependency (the one exception, added deliberately per D-20):

```bash
# apps/server/mix.exs deps() addition (dev-only, runtime: false)
{:sbom, "~> <verified-version>", only: :dev, runtime: false}
```

```bash
# Verify current versions before committing to mix.exs / CI step
mix hex.info sbom
npm view @cyclonedx/cyclonedx-npm version
```

## Package Legitimacy Audit

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---|---|---|---|---|---|---|
| `@cyclonedx/cyclonedx-npm` | npm | published 2026-08-11 (latest release; project itself is multi-year) | 370,402/wk | github.com/CycloneDX/cyclonedx-node-npm | `[OK]` (`gsd_run package-legitimacy check` verdict OK) | Approved |
| `sbom` (mix_sbom, hex.pm) | hex.pm | EEF-backed (`erlef/mix_sbom`), maintainer `erlefsecuritywg` | not scored by the npm/pypi/crates-only legitimacy seam (hex unsupported by that tool) | github.com/erlef/mix_sbom | `[VERIFIED: hex.pm API — GET /api/packages/sbom confirms maintainer `erlefsecuritywg`, licenses list, GitHub link]` | Approved — verified directly against the hex.pm registry API since the automated legitimacy seam does not cover the `hex` ecosystem |
| `cosign` | not a package-manager artifact (Go binary / GH Action `sigstore/cosign-installer`) | N/A | N/A | github.com/sigstore/cosign | N/A — outside npm/pypi/crates scope | Use the pinned-SHA `sigstore/cosign-installer` action per this repo's existing action-pinning convention (`check-ci-contract.mjs`'s full-commit-SHA rule) |
| `actions/attest-build-provenance` | GitHub Action | official GitHub-maintained action | N/A | github.com/actions/attest-build-provenance | N/A — GitHub-first-party | Pin to full commit SHA per repo convention |

**Packages removed due to `[SLOP]` verdict:** none.
**Packages flagged as suspicious `[SUS]`:** none.

*`cyclonedx-npm` is invoked via `npx` at CI time rather than added to the root `package.json`
lockfile, so it never enters `pnpm-lock.yaml`'s dependency graph; if the planner instead chooses
to pin it as a devDependency for reproducibility, re-run `pnpm audit` / the legitimacy check
against the exact pinned version at plan time.*

## Architecture Patterns

### System Architecture Diagram — Export Flow (DATA-01)

```
Operator CLI (mix keepling.ops export --output <path>)
        │
        ▼
Keepling.Application.Ops.run("export", input, PostgresExportPort, opts)
        │  (Ops.Port.inspect/1 → readiness; then execute/3)
        ▼
Keepling.Application.Export  (NEW — inward application module)
        │
        ├─► Repo.transaction(fn -> ... end, timeout: :export_query_timeout_ms)
        │       │  isolation_level: :repeatable_read
        │       ▼
        │   Repo.stream(query, max_rows: <chunk_size>)  ×  one per exported entity
        │       │  (tasks, projects, tags, task_activities, conflicts,
        │       │   today_order, account_settings, access_inventory)
        │       ▼
        │   NDJSON line writer per entity  →  data/<entity>.ndjson
        │       (canonical key order, UTC ISO-8601, stable ID/sequence order)
        │
        ├─► record sync_accounts.high_sequence + sync_epochs.epoch as of the
        │       transaction snapshot  →  manifest.json provenance fields
        │
        ├─► render tasks.md (human-readable rollup, D-Discretion: scope TBD)
        │
        └─► write manifest.json LAST (per-file sha256 + row counts)
                │
                ▼
        zip bundle, chmod 0600, security_audit event emitted
                │
                ▼
   tooling/ independent Node reader (zero shared Elixir code)
        validates every NDJSON line against packages/contracts/schemas/export/*,
        checks manifest sha256 + row counts, reconstructs task list,
        runs the no-secrets grep assertion
```

### Recommended Project Structure (new surfaces only)

```
apps/server/lib/keepling/application/
├── ops.ex                      # add "export" to @verbs (non-destructive)
└── export.ex                   # NEW: export orchestration, inward-only

apps/server/lib/keepling/adapters/postgres/
└── export.ex                   # NEW: Postgres Ops.Port impl for export inspect/execute

packages/contracts/schemas/export/
├── manifest.schema.json
├── task.schema.json
├── project.schema.json
├── ...
└── FORMAT.md

packages/contracts/vectors/
└── export-golden.json          # D-07(2) golden vector, registered in manifest.json

tooling/
├── verify-export-reader.mjs    # D-07(3) independent reader, zero shared Elixir code
├── verify-release.mjs          # D-12
├── release-lanes.json          # D-12 committed lane inventory
└── trust-lanes/
    ├── oracle.mjs              # D-45
    ├── invariants.mjs          # D-46 (I1-I8)
    ├── chaos.mjs
    └── census.mjs

.planning/releases/<tag>/
├── release-manifest.json
└── evidence bundle (mirrors GitHub Release assets, D-13)
```

### Pattern 1: Bounded transactional export read (Ecto)

**What:** Stream large tables inside one transaction without loading the whole account into memory.
**When to use:** Every entity file in the export.
**Example:**
```elixir
# Source: Ecto.Repo.stream/2 official docs (hexdocs.pm/ecto/Ecto.Repo.html#c:stream/2)
# [CITED: hexdocs.pm — Repo.stream requires being called inside a transaction]
Repo.transaction(
  fn ->
    Task
    |> where([t], t.account_id == ^account_id)
    |> order_by([t], asc: t.id)
    |> Repo.stream(max_rows: chunk_size)
    |> Stream.each(&write_ndjson_line(&1, tasks_file))
    |> Stream.run()
  end,
  timeout: export_timeout(),
  isolation_level: :repeatable_read
)
```
Note per D-08(b): do **not** reuse `Application.fetch_env!(:keepling, :task_view_query_timeout_ms)`
`[VERIFIED: apps/server/lib/keepling/adapters/postgres/task_views.ex:691-697]` — that helper
`raise`s `ArgumentError` unless the configured value `is_integer(timeout) and timeout > 0`, i.e. it
structurally cannot express `:infinity`. Quote:
```
defp query_options do
  timeout = Application.fetch_env!(:keepling, :task_view_query_timeout_ms)

  if is_integer(timeout) and timeout > 0 do
    [timeout: timeout]
  else
    raise ArgumentError, "task-view query timeout must be a positive integer"
  end
end
```
Define a distinct `:export_query_timeout_ms` config key with its own accessor that does permit
`:infinity`, exactly as D-08(b) directs.

### Pattern 2: Schema-driven completeness check (D-07 lane 1)

```elixir
# [VERIFIED: pattern uses information_schema, a standard PostgreSQL system view —
#  no Keepling-specific source needed to confirm this table exists]
{:ok, %{rows: rows}} =
  Ecto.Adapters.SQL.query(
    Repo,
    "SELECT table_name, column_name FROM information_schema.columns WHERE table_schema = 'public'",
    []
  )
# Compare `rows` against the checked-in IN/OUT classification manifest (D-01);
# fail the test if any column is absent from that manifest.
```

### Pattern 3: macOS sign → digest → notarize → staple ordering (D-16/D-17)

**What:** The exact sequencing that keeps `applicationDigestSha256` bound to the *signed* bytes.
**Why it matters:** `[VERIFIED: tooling/package-desktop.mjs — applicationDigestSha256 = hashDirectory(applicationPath) computed immediately after Forge's packager step, BEFORE this phase adds signing]`. Quote from the current hashing helper (unchanged by this phase, just now must run post-sign):
```js
const applicationDigestSha256 = hashDirectory(applicationPath)
if (hashDirectory(copiedApplicationPath) !== applicationDigestSha256) fail('the copied application digest differs from the built application')
```
`[VERIFIED: apps/desktop/forge.config.ts — full file has no osxSign, osxNotarize, or entitlements keys today]`:
```ts
packagerConfig: {
  appBundleId: 'dev.keepling.desktop',
  appCategoryType: 'public.app-category.productivity',
  appCopyright: 'Copyright © Keepling contributors',
  asar: true,
  extraResource: [ /* ... */ ],
  ignore: [/node_modules/],
  name: 'Keepling',
  prune: false,
},
```
The ordering, per D-17:
```
1. Forge packager step runs, WITH packagerConfig.osxSign now set        <- adds signing
2. Forge invokes @electron/osx-sign internally (bundled with
   @electron-forge/cli 7.11.2, no separate install)                    <- .app is now signed
3. package-desktop.mjs computes applicationDigestSha256 = hashDirectory(.app)  <- SIGNED digest
4. ditto -c -k --sequesterRsrc --keepParent <.app> <archive>            <- lossless archive (D-11)
5. Forge/CI notarizes the ARCHIVE (osxNotarize, or `xcrun notarytool submit`) <- mutates nothing in .app itself, but staple (step 6) does
6. `xcrun stapler staple` the notarization ticket onto the .app          <- mutates the bundle again, irreducibly
7. codesign -dvvv --verbose=4 <.app> | grep CDHash                       <- extract codeDirectoryHash: the identity that SURVIVES staple
8. Record BOTH in release-manifest.json:
     applicationDigestSha256   (pre-staple, step 3 — what every gate tested)
     codeDirectoryHash         (step 7 — what a Gatekeeper check on the shipped file will show)
9. Never re-run hashDirectory after staple and call it applicationDigestSha256 — gate on
   CDHash equality instead, exactly as D-17(b) states.
```
Forge config skeleton (per D-17e, never `codesign --deep`, per-helper entitlements via
`optionsForFile`) `[CITED: electronforge.io/guides/code-signing/code-signing-macos]`:
```ts
packagerConfig: {
  // ...existing keys unchanged...
  osxSign: {
    identity: 'Developer ID Application: <Name> (<TEAM_ID>)',
    optionsForFile: (filePath: string) => {
      const isMainAppBundle = filePath.endsWith('.app') && !filePath.includes('Helper')
      return {
        hardenedRuntime: true,
        entitlements: isMainAppBundle
          ? fromDesktopRoot('./build/entitlements.plist')
          : fromDesktopRoot('./build/entitlements.helper.plist'),
      }
    },
  },
  osxNotarize: {
    appleId: process.env.APPLE_ID,
    appleIdPassword: process.env.APPLE_APP_SPECIFIC_PASSWORD,
    teamId: process.env.APPLE_TEAM_ID,
  },
}
```

### Pattern 4: SLSA Build L2 provenance attestation (D-22)

`[VERIFIED: .github/workflows/desktop.yml top-level permissions block is `contents: read` only — no id-token or attestations key present]`:
```yaml
permissions:
  contents: read
```
Required addition, scoped to the job that builds and attests (not the whole workflow, to keep
least-privilege on PR-triggered jobs) `[CITED: docs.github.com/actions/security-for-github-actions/using-artifact-attestations]`:
```yaml
jobs:
  desktop-promote:
    permissions:
      contents: read
      id-token: write        # mint the OIDC token for Sigstore
      attestations: write    # persist the attestation
    steps:
      # ...existing packaging/signing/notarizing steps...
      - uses: actions/attest-build-provenance@<pin-to-full-commit-sha>
        with:
          subject-path: 'apps/desktop/out/**/*.zip'
```
Claim exactly "SLSA Build Level 2" in public docs, per D-22 — L3 needs a reusable workflow with
isolated signing, which this single-job pipeline does not have.

### Pattern 5: cosign keyless signing of the server OCI image (D-19)

`[CITED: docs.sigstore.dev, chainguard.dev/unchained/zero-friction-keyless-signing-with-github-actions]`:
```yaml
permissions:
  id-token: write
  packages: write   # or the appropriate registry-push permission
steps:
  - uses: sigstore/cosign-installer@<pin-to-full-commit-sha>
  - run: cosign sign --yes ${{ env.IMAGE_REF }}@${{ steps.push.outputs.digest }}
```
Always sign by digest (immutable), never by tag. `--yes` accepts the Rekor transparency-log
upload non-interactively, required for unattended CI.

### Pattern 6: Neutral export format precedent survey (D-02, informing Claude's Discretion items)

`[ASSUMED — training knowledge of publicly documented export formats, not independently re-verified this session; low-risk claims about industry precedent shape, not about this codebase]`:
- **1Password `.1pux`:** zip containing a top-level `export.attributes` + `export.data` (JSON), one entry per vault/item — validates D-02's "zip of structured files" direction.
- **Google Takeout:** per-service directories, often NDJSON or per-record JSON files, a top-level `archive_browser.html` for human inspection — validates the `tasks.md`/human-readable-file idea.
- **Joplin JEX / Day One `.dayone`:** zip of one file per note/entry plus a manifest — same shape.
- None of these surveyed formats embed a JSON Schema inside the bundle itself; Keepling's D-03
  decision to publish the schema in `packages/contracts/schemas/export/` (out-of-band, versioned)
  rather than bundling it is a reasonable deviation, not a violation of precedent — no surveyed
  format bundles a schema either.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---|---|---|---|
| SLSA build provenance attestation | Custom in-toto statement signing | `actions/attest-build-provenance` | GitHub-maintained, handles Sigstore/Fulcio/Rekor plumbing correctly; a hand-rolled signer is exactly the kind of custom crypto this project's own culture (Argon2id, PKCE) already avoids reinventing |
| Container image signing | Manual GPG detached signatures | `cosign sign` (keyless) | GPG requires solo key custody (D-19's stated rejection reason); cosign keyless has no key to lose or leak |
| CycloneDX SBOM parsing/generation | A hand-written dependency walker | `mix_sbom` (Hex) / `@cyclonedx/cyclonedx-npm` | Both are the ecosystem-canonical generators; a hand-rolled walker would miss transitive-dependency edge cases (optional deps, git deps) these tools already handle |
| DCO sign-off enforcement | A custom GitHub Actions script that parses commit trailers | `dcoapp/app` (GitHub App) or `KineticCafe/actions-dco` | Commit-trailer parsing has edge cases (merge commits, squash-merge rewriting, multiple authors) both tools already handle |
| Export completeness proof | Manually maintaining a hand-written list of "exported columns" | `information_schema.columns` diffed against the classification manifest at test time (D-07 lane 1) | A hand-maintained list silently drifts the moment a migration adds a column — exactly the vacuity class this project has been burned by twice per D-34/D-35 |

**Key insight:** every "don't hand-roll" item in this phase maps to a supply-chain trust primitive
(signing, attestation, SBOM) where a subtly-wrong home-grown implementation is *worse than having
none*, because it produces a false sense of verified provenance — the same failure class D-34's
CORRECTED-OVERCLAIM category exists to catch.

## Runtime State Inventory

Not applicable — Phase 6 is not a rename/refactor/migration phase. Skipped per template guidance.

## Common Pitfalls

### Pitfall 1: Signing after digesting (the D-17 trap, restated as a pitfall)
**What goes wrong:** Computing `applicationDigestSha256` before code-signing, then discovering
after CI adds signing that gates fail because the file changed after being measured.
**Why it happens:** The natural place to add `osxSign` is "wherever Forge's packaging call
happens," but `package-desktop.mjs` hashes immediately after that call returns — if signing is
added as a *separate* step after `package-desktop.mjs` runs (e.g., a follow-on `codesign` shell
step in the workflow), the hash is stale before signing ever occurs.
**How to avoid:** Signing must be configured through `packagerConfig.osxSign` so Forge's own
packager step performs it *before* `package-desktop.mjs`'s `hashDirectory` call executes — not
bolted on afterward.
**Warning signs:** `verify-macos-integration.mjs`'s digest-binding checks start failing only in CI
(never locally, since local unsigned builds hash consistently); `codesign --verify` on the shipped
artifact fails even though the manifest says it's signed.

### Pitfall 2: ZIP round-trip losing POSIX mode bits (the O-40 defect, already found — do not reintroduce)
**What goes wrong:** `actions/upload-artifact`'s zip round-trip does not preserve POSIX mode,
so a re-hashed `.app` after download differs from the one hashed before upload.
**Why it happens:** `hashDirectory` in both `package-desktop.mjs` and `smoke-desktop-packaged.mjs`
includes `metadata.mode.toString(8)` in the digest input `[VERIFIED: tooling/package-desktop.mjs — digest.update(\`${relativePath}\0${metadata.mode.toString(8)}\0\`)]` — any transport that doesn't
preserve mode bits changes the digest even though file content is unchanged.
**How to avoid:** Use `ditto -c -k --sequesterRsrc --keepParent` for the artifact transport instead
of relying on the default zip behavior of `actions/upload-artifact`, and re-verify the *expanded*
tree after `ditto -x -k` on the receiving side, per D-11.
**Warning signs:** `smoke-desktop-packaged.mjs`'s "copied application digest does not match the
package manifest" failure — this is the literal error message from the real incident in run
`34561455069` that motivated D-11.

### Pitfall 3: SBOM scanned from the built artifact instead of from source
**What goes wrong:** Running `syft` (or any binary-scanning SBOM tool) against the packaged
`.app` produces a near-empty SBOM.
**Why it happens:** `[VERIFIED: apps/desktop/forge.config.ts — ignore: [/node_modules/]]` and the
packager bundles four pre-built outputs (main/preload/renderer/worker) rather than raw
`node_modules` — a binary scan of the shipped bundle sees minified/bundled code, not the
915-entry dependency graph.
**How to avoid:** Generate the npm SBOM from `pnpm-lock.yaml` / `package.json` at the release
revision (source-based), inside the `desktop-promote` job, per D-20 — not from the built `.app`.
**Warning signs:** An SBOM with fewer than ~10 entries for an app that has 915 npm resolutions.

### Pitfall 4: Treating `WINDOWS.md` / `STATE.md` recorded status as ground truth
**What goes wrong:** Planning a task around a ledger row's stated status ("BLOCKED", "closed",
"open") without re-checking source.
**Why it happens:** Six of the residual items handed to research in this very discussion were
stale (per 06-CONTEXT.md's own standing instruction).
**How to avoid:** Every code-surface claim in a plan must be re-verified against source before the
plan is written — this research document itself models that discipline throughout.
**Warning signs:** A plan cites a `WINDOWS.md` row number as its only evidence for a claim about
current code state.

### Pitfall 5: `last_used_at` has no backing column today (new finding, informs D-38's task)
**What goes wrong:** Assuming D-38's "publish `scope`, `authorized_at`, `last_used_at`" is a pure
serialization change to `grant_response/1`.
**Why it happens:** `[VERIFIED: apps/server/lib/keepling/accounts/device_grant.ex:37 — field :scope, {:array, :string}, default: []]` — `scope` already exists on the struct. `[VERIFIED: apps/server/priv/repo/migrations/20260901000200_add_device_grants.exs:6-24]` — the migration's full column list is `id, account_id, installation_id, label, client_kind, redirect_uri, authorization_code_hash, authorization_code_expires_at, authorization_code_consumed_at, state_hash, pkce_challenge, access_token_hash, access_expires_at, refresh_inactivity_expires_at, family_absolute_expires_at, generation, last_refreshed_at, revoked_at, inserted_at, updated_at`. There is no `last_used_at` column, and no code path anywhere in `apps/server/lib/keepling/accounts/` or `apps/server/lib/keepling_web/` writes a "last used" timestamp (grepped `last_used`, zero hits).
**How to avoid:** The planner must treat "publish `last_used_at`" as a task requiring (a) a new
migration adding the column, (b) a decision on what counts as "used" (every authenticated request?
only mutations? — this touches privacy/telemetry granularity questions the project cares about),
and (c) a write-path at the point that event occurs. `authorized_at` can map cleanly to the
existing `inserted_at` (grant creation time) with no schema change; `last_used_at` cannot reuse
`last_refreshed_at` (that column only advances on OAuth refresh-token rotation, not on ordinary
authenticated API calls) without narrowing the claim on the consent screen to "last token refresh"
rather than "last used."
**Warning signs:** A plan that widens `DeviceGrantSummary` and `grant_response/1` without a
companion migration — the field would either be hand-waved to `nil` (recreating D-38's own "absent
vs. empty" distinction the phase exists to fix) or backed by the wrong semantic column.

## Code Examples

### Independent export reader (D-07 lane 3) — skeleton, zero shared Elixir code

```js
// tooling/verify-export-reader.mjs — Node-only, no import from apps/server
import { createHash } from 'node:crypto'
import { readFileSync, readdirSync } from 'node:fs'
import Ajv from 'ajv' // or a hand-rolled minimal validator if a new dep is undesirable

const manifest = JSON.parse(readFileSync('manifest.json', 'utf8'))
for (const file of manifest.files) {
  const bytes = readFileSync(file.path)
  const digest = createHash('sha256').update(bytes).digest('hex')
  if (digest !== file.sha256) throw new Error(`${file.path}: digest mismatch`)
  const lines = bytes.toString('utf8').trim().split('\n').filter(Boolean)
  if (lines.length !== file.rowCount) throw new Error(`${file.path}: row count mismatch`)
  for (const line of lines) {
    const record = JSON.parse(line) // throws on malformed NDJSON — that's the point
    // validate `record` against packages/contracts/schemas/export/<entity>.schema.json
  }
}
// no-secrets assertion: grep every file for known credential-fixture substrings
```
Registering in `packages/contracts/vectors/manifest.json` follows the existing multi-consumer
precedent `[VERIFIED: packages/contracts/vectors/manifest.json:3 — describes per-file required
consumers determined "by inspecting every consuming test file directly," never hand-guessed]`.

### `Ops` verb registration (D-05)

```elixir
# apps/server/lib/keepling/application/ops.ex
# [VERIFIED: current @verbs list, line 10]
@verbs ~w(preflight status doctor backup restore restore-verify deploy upgrade replace-host)
@destructive ~w(restore restore-verify deploy upgrade replace-host)
# Add "export" to @verbs, NOT to @destructive (D-05: non-destructive, synchronous, streaming)
```

### CI lane fixes (D-10) — exact diffs against verified current source

```bash
# tooling/runtime-preflight.sh — provision_runtime() currently (verified, lines 99-107):
#   asdf install erlang "$OTP_VERSION"      <- fails with no plugin added first
#   asdf install elixir "$ELIXIR_ASDF_VERSION"
#   brew install postgresql@18
# Fix: add idempotent plugin registration before each `asdf install`:
asdf plugin add erlang || true
asdf plugin add elixir || true
asdf plugin add postgres || true
```
```bash
# tooling/test-phase-2.sh:109 — [VERIFIED: count_tests() shells to `rg`]
count_tests() {
  rg -n '^[[:space:]]*(test|property) "' "$@" | wc -l | tr -d '[:space:]'
}
# Fix: replace `rg -n` with `grep -nE`, keeping the same capture group behavior:
count_tests() {
  grep -nE '^[[:space:]]*(test|property) "' "$@" | wc -l | tr -d '[:space:]'
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|---|---|---|---|
| Apple `altool` for notarization | `xcrun notarytool` | `altool` notarization deprecated by Apple (notarytool has been the required path for several years); Forge's `osxNotarize` already uses notarytool under recent `@electron/notarize` versions | Confirms `osxNotarize` config keys (`appleId`/`appleIdPassword`/`teamId` or API-key form) map to notarytool, not the deprecated altool flow |
| Legacy `CycloneDX/gh-node-module-generatebom` GitHub Action | `@cyclonedx/cyclonedx-npm` invoked directly | Marketplace listing itself flags the older action as legacy/deprecated for npm projects | Use the npm-native CLI directly via `npx`, not the older Action wrapper |
| SLSA provenance hand-signed with a repo-held key | `actions/attest-build-provenance` + Sigstore/Fulcio ephemeral certs | GitHub's artifact attestations GA'd this OIDC-based flow | No long-lived signing key for the maintainer to protect |

**Deprecated/outdated:**
- Apple `altool` — do not reference it in any new tooling or docs; `notarytool` is current.
- Long-lived GPG signing for OCI images — D-19 already rejects this for the correct reason (solo
  key-custody risk); do not resurrect it even as a "belt and suspenders" measure.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|---|---|---|
| A1 | 1Password/.1pux, Google Takeout, Joplin JEX, Day One export-format shapes described from training knowledge, not re-fetched this session | Architecture Patterns, Pattern 6 | Low — this is background precedent informing an already-locked format decision (D-02), not a claim about Keepling's own code; if any detail is misremembered, it does not change D-02's outcome |
| A2 | `xcrun notarytool` fully replaces `altool`-based flows in current `@electron/notarize` (used internally by Forge's `osxNotarize`) | State of the Art | Low-medium — if Forge 7.11.2's bundled `@electron/notarize` version still defaults to a different flow, the planner should pin/verify the exact notarize invocation Forge uses at implementation time |
| A3 | `dcoapp/app` GitHub App requires no workflow YAML and is simpler than an Action for a solo-maintainer repo | Standard Stack, Alternatives Considered | Low — a governance/tooling preference, not a correctness claim; either option satisfies D-25 |

**If this table is empty:** N/A — assumptions exist above and are all low-risk background/tooling
preferences, not claims about locked decisions or in-repo behavior.

## Open Questions

1. **What exact event(s) should advance `last_used_at` for a device grant?**
   - What we know: `authorized_at` maps cleanly to existing `inserted_at`; no column or write path
     for "last used" exists today (see Pitfall 5).
   - What's unclear: whether "used" means every authenticated API request (high write volume,
     needs debouncing to avoid a write-per-request performance/contention cost) or only mutations,
     or only MCP tool calls specifically (since D-38's animating concern is the agent-consent
     screen, not device-grant activity in general).
   - Recommendation: raise as a `checkpoint:decision` in the plan — this is a small but real scope
     decision D-38 did not fully specify at the mechanism level, and it affects both a migration
     and a hot code path.

2. **Where exactly does `entitlements.plist` need to live, and what capabilities does Keepling's
   Electron app actually need (network, no sandboxing, etc.)?**
   - What we know: Forge's `osxSign.optionsForFile` callback pattern is the mechanism (Pattern 3).
   - What's unclear: this research did not enumerate Keepling's actual required entitlements
     (e.g., does the app need `com.apple.security.cs.allow-unsigned-executable-memory` for any
     native module or JIT reason specific to Electron 44 + Node 24?).
   - Recommendation: the planner's task for D-16/D-17 should include a sub-task to test the signed
     +notarized build with a minimal entitlements set first, add only what a real Gatekeeper/launch
     failure demands — matching this project's general "measure, don't assume" discipline.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|---|---|---|---|---|
| `asdf` + `erlang`/`elixir`/`postgres` plugins | D-10 CI fix | Not probed in this sandbox (CI-only concern — the fix targets `ubuntu-24.04` GitHub-hosted runners, not this research environment) | — | N/A — this is a CI-runner-only fix; no local fallback needed |
| `rg` (ripgrep) | Explicitly to be REMOVED from `test-phase-2.sh`, replaced with `grep -E` | Present locally (`sed`/`grep` confirmed available in this sandbox) | — | `grep -E` is the fallback and the actual fix — see D-10(2) |
| Apple Developer ID cert + notarization credentials | D-16/D-17 signing | Cannot be probed in this sandbox — requires the owner's paid Apple Developer Program membership, already verified active per `tooling/build-ios-signed.mjs:348-366`'s existing profile-validity check | — | None — this blocks the macOS signing task until credentials are supplied to CI as secrets |
| `cosign` binary | D-19 OCI signing | Not installed in this sandbox; install via `sigstore/cosign-installer` action in CI | — | None needed — CI-only |
| GitHub Actions `id-token`/`attestations` OIDC | D-22 provenance | Requires the repo to have a functioning git remote and Actions enabled — confirmed CI is being repaired this same phase (D-10) | — | Blocked until D-10's CI repair lands; sequencing already requires this (D-54 step 3 before step 4) |

**Missing dependencies with no fallback:**
- Apple Developer ID signing certificate + notarization app-specific password/API key must be
  added as CI secrets before D-16/D-17 tasks can execute for real (not just be written).

**Missing dependencies with fallback:**
- `rg` → `grep -E` (this is itself the fix, not a fallback for a missing tool elsewhere).

## Validation Architecture

### Test Framework

| Property | Value |
|---|---|
| Framework | `mix test` (ExUnit) for server/export; Vitest for desktop/web; XCTest for iOS; Node scripts (no framework, assertion-by-exit-code) for `tooling/*.mjs` gates — all four already established, none new |
| Config file | `apps/server/mix.exs`; `apps/desktop/vitest.config.ts` (existing); no config file for `tooling/` scripts — each is a standalone executable asserting and exiting non-zero on failure |
| Quick run command | `cd apps/server && mix test test/keepling/application/export_test.exs` (new file) |
| Full suite command | `node tooling/verify-release.mjs --manifest .planning/releases/<tag>/release-manifest.json` (new, D-12) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|---|---|---|---|---|
| DATA-01 | Export produces a complete, versioned, neutral bundle | integration | `mix test test/keepling/application/export_test.exs` | ❌ Wave 0 |
| DATA-01 | Export bundle is inspectable without Keepling internals | tooling (independent reader) | `node tooling/verify-export-reader.mjs <bundle-path>` | ❌ Wave 0 |
| QUAL-02 | CI is green, no forced skips | CI (all lanes) | `gh workflow view` / re-run after D-10 fixes | ❌ Wave 0 (fix is the task) |
| QUAL-03 | Release promotion uses exact tested revision/artifact | tooling | `node tooling/verify-release.mjs --manifest <path>` | ❌ Wave 0 |
| QUAL-04/05 | Cross-client release evidence complete | tooling (release manifest lane assertions) | `node tooling/verify-release.mjs --manifest <path>` | ❌ Wave 0 |
| SRV-02 | Electron/iPhone cross-adapter legs pass | tooling | `node tooling/verify-cross-adapter-phase.mjs` | ✅ exists, currently BLOCKED on both new legs |

### Sampling Rate
- **Per task commit:** the relevant unit/integration test file for that task.
- **Per wave merge:** `node tooling/verify-release.mjs` (once it exists) plus the existing full
  desktop/server/iOS phase gates.
- **Phase gate:** `verify-trust-soak.mjs --gate` for SC5 (long-pole, D-51) plus a green
  `verify-release.mjs` for SC2/SC3.

### Wave 0 Gaps
- [ ] `apps/server/test/keepling/application/export_test.exs` — covers DATA-01
- [ ] `tooling/verify-export-reader.mjs` — independent reader, D-07 lane 3
- [ ] `tooling/verify-release.mjs` + `tooling/release-lanes.json` — D-12
- [ ] `tooling/trust-lanes/{oracle,invariants,chaos,census}.mjs` + `tooling/verify-trust-soak.mjs` — D-45..D-51
- [ ] Migration for `last_used_at` tracking (new finding, Pitfall 5) if D-38's scope includes it after the checkpoint decision

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---|---|---|
| V2 Authentication | yes (agent-consent surface, window 76) | Existing PKCE + device-grant flow (Phase 5); this phase only widens the *summary* exposed, not the auth mechanism |
| V3 Session Management | no new surface | Unchanged — export runs as the account's own operator, no new session type (D-05) |
| V4 Access Control | yes | D-06's closed `@agent_scopes` whitelist `[VERIFIED: apps/server/lib/keepling/application/agent_scope.ex:16 — @agent_scopes ~w(tasks.read tasks.write tasks.bulk)]` structurally excludes export from ever being agent-reachable — no new code needed beyond the regression test D-06 specifies |
| V5 Input Validation | yes | Export manifest/schema validation (independent reader); `information_schema` completeness check is itself a form of schema validation |
| V6 Cryptography | yes | SHA-256 for all digests (already the project's convention throughout `package-desktop.mjs`/`smoke-desktop-packaged.mjs`); cosign keyless uses Sigstore's Fulcio/Rekor rather than any custom crypto — never hand-roll |
| V14 Configuration | yes | Governance lane (D-32) is effectively a configuration-drift ASVS control for public trust documents |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---|---|---|
| Export bundle used as an exfiltration vector if agents could trigger it | Information Disclosure | D-06's structural agent-scope exclusion (already in place, needs only a regression test) |
| Malicious dependency update reaching a signed release | Tampering | D-23's named realistic threat model — provenance attestation + SBOM + the existing provenance-review culture (not signing alone, which would happily sign a compromised dependency too) |
| Receipt-scope inversion (window 73) — enumerable mutation IDs granting cross-grant read access | Elevation of Privilege | D-39's fix: bind receipt reads to the issuing grant `[VERIFIED: apps/server/lib/keepling_web/auth.ex:190-209 — agent_authority/2's closed method/path match list, the same file D-39 targets at line 200]` |
| Consent screen showing stale/absent agent activity data | Information Disclosure (of the *wrong kind* — under-disclosure) | D-38's widened `DeviceGrantSummary`; absent-vs-empty distinction preserved per the 05-UI-REVIEW precedent |

## Sources

### Primary (HIGH confidence — in-repo, read this session)
- `apps/server/lib/keepling/application/ops.ex` — `@verbs`/`@destructive`/exit-class contract
- `apps/server/lib/keepling/application/agent_scope.ex` — closed agent scope vocabulary
- `apps/server/lib/keepling/adapters/postgres/task_views.ex:685-697` — the mandatory-positive-timeout helper D-08(b) must not reuse
- `apps/server/priv/repo/migrations/20260901000100_add_sync_feed.exs` — sync feed schema (closed `kind` vocabulary, receipt FK)
- `apps/server/priv/repo/migrations/20260901000200_add_device_grants.exs` — full `device_grants` column list
- `apps/server/lib/keepling/accounts/device_grant.ex` — `scope` field, existing scope-handling code
- `apps/server/lib/keepling_web/controllers/device_grant_controller.ex:167-175` — current `grant_response/1`
- `apps/server/lib/keepling_web/auth.ex:190-209` — `agent_authority/2`
- `packages/contracts/openapi/keepling.yaml:1831-1867` — current `DeviceGrantSummary` schema
- `tooling/package-desktop.mjs` — `hashDirectory`, `applicationDigestSha256` computation site
- `tooling/smoke-desktop-packaged.mjs` — digest recomputation, the O-40/D-11 transport defect site
- `tooling/verify-package-reproducibility.mjs` — header comment restating its one-machine claim
- `tooling/runtime-preflight.sh:99-113`, `tooling/test-phase-2.sh:100-115` — the two shallow CI bugs
- `tooling/check-ci-contract.mjs:40-125` — lane-inventory/pinning/`paths:`-ban enforcement
- `tooling/check-repository-integrity.sh` — current 35-line script the governance lane extends
- `tooling/cross-adapter/legs.mjs:60-350`, `tooling/verify-cross-adapter-phase.mjs:1-60` — cross-adapter scenario runner and both BLOCKED legs verbatim
- `apps/desktop/forge.config.ts` — confirmed absence of `osxSign`/`osxNotarize`
- `apps/desktop/store-worker/local-store.ts:700-750` — the O-43 refusal-durability comment, verbatim
- `packages/web-ui/src/workspace/Workspace.tsx:245-270` — `attemptNavigation`/`commitNavigation`, the O-22 bypass target
- `.github/workflows/desktop.yml` — confirmed `permissions: contents: read` only, retention-days 14
- `apps/server/mix.exs`, root `package.json`, `apps/*/package.json` — confirmed no `license`/`package/0` fields anywhere

### Secondary (MEDIUM confidence — official docs via WebSearch)
- docs.github.com/actions/security-for-github-actions/using-artifact-attestations — `actions/attest-build-provenance` permissions and usage
- electronforge.io/guides/code-signing/code-signing-macos — `osxSign`/`osxNotarize` config shape
- hexdocs.pm/sbom — `mix sbom.cyclonedx` usage and options
- docs.sigstore.dev, chainguard.dev/unchained — cosign keyless signing flow

### Tertiary (LOW confidence — background precedent, not independently re-verified this session)
- 1Password `.1pux`, Google Takeout, Joplin JEX, Day One export format shapes (training knowledge, cited only as precedent informing an already-locked decision, D-02)

## Metadata

**Confidence breakdown:**
- In-repo code mechanics (export insertion point, digest computation, agent scope, CI bugs, cross-adapter legs, device-grant schema): HIGH — every claim verified by reading the file this session
- External tool syntax (Forge signing config, GH Actions attestation permissions, cosign, SBOM tools): MEDIUM — verified against current official docs via WebSearch this session, not executed
- Export format precedent survey: LOW — background context only, does not gate any decision

**Research date:** 2026-09-11
**Valid until:** 30 days for in-repo findings (re-verify if source changes before planning executes); 14 days for external tool/action version specifics (GitHub Actions and Electron Forge signing guidance changes faster than stable libraries)
