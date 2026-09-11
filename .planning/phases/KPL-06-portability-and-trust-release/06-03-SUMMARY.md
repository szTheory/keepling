---
phase: KPL-06-portability-and-trust-release
plan: 03
subsystem: licensing-governance
tags: [apache-2.0, license, notice, spdx, cyclonedx, sbom, mix, hex, D-24, D-26, T-06-03]

requires:
  - phase: KPL-06-01
    provides: an honest, correction-first record before new Phase 6 feature work builds on it
  - phase: KPL-06-02
    provides: the release-evidence spine and CI lanes this plan's SBOM dependency will eventually feed
provides:
  - LICENSE (verbatim Apache License 2.0 text, unfilled appendix placeholder) at the repository root
  - NOTICE (project name + copyright line only) at the repository root
  - "license": "Apache-2.0" declared in all four package.json manifests (root, apps/web, apps/desktop, packages/web-ui)
  - apps/server/mix.exs package/0 declaring licenses: ["Apache-2.0"]
  - apps/server/mix.exs/mix.lock dev-only, non-runtime :sbom Hex dependency (CycloneDX generator)
affects: [KPL-06-10-sign-notarize-attest, KPL-06-11-governance-lane, KPL-06-13-final-verification]

actuals:
  tokens: 5650
  tasks: 3
  commits: 2

tech-stack:
  added:
    - "sbom (Hex, ~> 0.10.0, only: :dev, runtime: false) — CycloneDX SBoM generator, verified against hex.pm registry API, maintainer erlefsecuritywg"
  patterns:
    - "License identity carried by LICENSE + package metadata + SPDX identifiers only — never per-file license headers"
    - "Canonical upstream license text committed byte-for-byte with its placeholder unfilled, so a later governance hash-comparison gate stays valid"

key-files:
  created:
    - LICENSE
    - NOTICE
  modified:
    - package.json
    - apps/web/package.json
    - apps/desktop/package.json
    - packages/web-ui/package.json
    - apps/server/mix.exs
    - apps/server/mix.lock

key-decisions:
  - "The checkpoint:decision in Task 1 was resolved by auto-selecting the pre-answered option: Task 1's own text records that the owner already confirmed Apache-2.0, uniform across the monorepo, on 2026-09-11 (D-24), with full rationale (patent grant, trademark clause, inbound-contribution terms, App Store distribution constraint on copyleft) documented in the plan itself. No new decision was made here — this is a re-confirmation of an already-recorded owner answer, not a fresh choice."
  - "LICENSE's appendix placeholder ([yyyy] [name of copyright owner]) was deliberately left unfilled, per the plan's own instruction, so the governance lane in plan 06-11 can hash-compare this file against the canonical upstream text."
  - "sbom pinned to \"~> 0.10.0\" because `mix hex.info sbom` reported 0.10.0 as the current release at implementation time — not a remembered/assumed version."
  - "mix.exs's package/0 exists purely for CycloneDX/tooling consumption; the server is not published to Hex."

patterns-established:
  - "A one-way, already-answered owner decision (recorded with rationale in the plan text) is auto-confirmed by the executor rather than re-litigated at the checkpoint, since the checkpoint's purpose (surface the decision before the irreversible act) was already served by the plan's own documentation of D-24."

requirements-completed: [QUAL-02]

coverage:
  - id: D1
    description: "LICENSE and NOTICE are tracked at the repository root; LICENSE is the verbatim, unmodified Apache-2.0 text with its appendix placeholder unfilled; NOTICE carries only the project name and copyright line"
    verification:
      - kind: other
        ref: "git ls-files --error-unmatch LICENSE NOTICE"
        status: pass
      - kind: other
        ref: "grep -c 'TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION' LICENSE (=1); awk 'END{print NR}' LICENSE (=202, >=190); awk 'END{print NR}' NOTICE (=2, <=6)"
        status: pass
      - kind: other
        ref: "git grep -l 'Licensed under the Apache License' returns only LICENSE (appendix template text) and the plan's own prose file, no source file"
        status: pass
    human_judgment: false
  - id: D2
    description: "All four package.json files declare license: Apache-2.0; apps/server/mix.exs declares the same via package/0"
    requirement: "QUAL-02"
    verification:
      - kind: other
        ref: "node -e '...license!==\"Apache-2.0\"...' over all 4 package.json files -> checked=4"
        status: pass
      - kind: other
        ref: "mix run -e 'IO.inspect(Keyword.fetch!(Mix.Project.config(), :package)[:licenses])' -> [\"Apache-2.0\"]"
        status: pass
    human_judgment: false
  - id: D3
    description: "The CycloneDX generator (:sbom) is a dev-only, non-runtime Mix dependency resolved into mix.lock, and does not reach a production build"
    verification:
      - kind: other
        ref: "grep -c 'sbom' apps/server/mix.lock (=1)"
        status: pass
      - kind: other
        ref: "MIX_ENV=prod mix compile succeeds"
        status: pass
    human_judgment: false
  - id: D4
    description: "The ordering contract holds: LICENSE's commit precedes any SBOM-generation-step commit, so plan 06-10 reads populated license metadata rather than unknowns"
    verification:
      - kind: other
        ref: "git log --oneline -- LICENSE shows 3a0dcaa, preceding the mix.exs/manifest commit 7181c02; no SBOM-generation commit exists yet (plan 06-10 has not run)"
        status: pass
    human_judgment: false

duration: ~6min
completed: 2026-09-11
status: complete
---

# Phase KPL-06 Plan 03: License the repository and populate SBOM-readable metadata Summary

**Committed the verbatim Apache License 2.0 and a two-line NOTICE at the repository root, declared `license: Apache-2.0` in all four `package.json` manifests and `apps/server/mix.exs`'s new `package/0`, and added the dev-only, non-runtime `:sbom` Hex CycloneDX generator (`~> 0.10.0`, verified against the hex.pm registry API) — closing the D-54(2) misrepresentation where the README claimed a complete open-source product while the repository granted no rights.**

## Performance

- **Duration:** ~6 min
- **Tasks:** 3 (1 checkpoint:decision auto-confirmed, 2 auto)
- **Files modified:** 8 (2 created: LICENSE, NOTICE; 6 modified: 4 package.json files, mix.exs, mix.lock)

## Accomplishments

- `LICENSE` at the repository root is the byte-verbatim upstream Apache License 2.0 text (202 lines, fetched from `www.apache.org/licenses/LICENSE-2.0.txt`), with the appendix's `[yyyy] [name of copyright owner]` placeholder deliberately left unfilled so plan 06-11's canonical-hash governance check can compare against it directly.
- `NOTICE` at the repository root carries exactly two lines: `Keepling` and `Copyright 2026 Jon <szTheory>` — nothing more, since NOTICE content is legally sticky and propagates to every downstream fork.
- All four existing `package.json` files (`package.json`, `apps/web/package.json`, `apps/desktop/package.json`, `packages/web-ui/package.json`) now declare `"license": "Apache-2.0"`, placed among each file's existing metadata keys with original key order preserved. No manifest was created for `packages/contracts` or `packages/design-tokens` (neither has a `package.json`).
- `apps/server/mix.exs` gained a `package/0` function (`licenses: ["Apache-2.0"]`) wired into `project/0`'s `:package` key, and a dev-only, non-runtime `:sbom` dependency (`~> 0.10.0`, matching `mix hex.info sbom`'s reported current release) resolved into `mix.lock`.
- No per-file license headers were added anywhere in the tree — license identity is carried entirely by `LICENSE`, package metadata, and (where a file already warranted one) SPDX identifiers.
- Verified the plan's ordering contract holds: `LICENSE`'s commit (`3a0dcaa`) precedes the manifest/mix.exs commit (`7181c02`), and no SBOM-generation-step commit exists yet, so plan 06-10's CycloneDX SBOM will read populated license strings rather than unknowns.

## Task Commits

Each task was committed atomically:

1. **Task 1: Confirm the licence before it is granted to anyone who clones** — no commit (decision-only checkpoint; auto-confirmed the pre-answered D-24 owner decision, see Decisions Made)
2. **Task 2: Add the Apache-2.0 LICENSE and a minimal NOTICE** — `3a0dcaa` (feat)
3. **Task 3: Declare the licence in every package manifest and add the dev-only SBOM dependency** — `7181c02` (feat)

**Plan metadata:** (this commit, following)

## Files Created/Modified

- `LICENSE` — verbatim Apache License 2.0 text, 202 lines, unfilled appendix placeholder
- `NOTICE` — project name + copyright line, 2 lines
- `package.json` — added `"license": "Apache-2.0"`
- `apps/web/package.json` — added `"license": "Apache-2.0"`
- `apps/desktop/package.json` — added `"license": "Apache-2.0"`
- `packages/web-ui/package.json` — added `"license": "Apache-2.0"`
- `apps/server/mix.exs` — added `package/0` (`licenses: ["Apache-2.0"]`) referenced from `project/0`; added `{:sbom, "~> 0.10.0", only: :dev, runtime: false}` to `deps/0`
- `apps/server/mix.lock` — resolved `:sbom` and its transitive deps (`hex_core`, `optimus`, `protobuf`, `purl`)

## Decisions Made

- **Task 1's checkpoint:decision was auto-confirmed, not re-litigated.** The plan's own text records that the owner (Jon) already answered this exact question on 2026-09-11 as D-24: Apache License 2.0, uniform across the entire monorepo, with rationale spanning the explicit patent grant (material for a codebase with a hand-rolled auth server), the trademark clause (protects the project name without a separate policy), the inbound-contribution-under-same-terms clause, and the App Store distribution constraint that rules out strong copyleft (the iPhone client ships today only because Jon is sole copyright holder; the first outside contributor to shared code under a copyleft license would make store distribution require their permission permanently). Since the checkpoint's stated purpose was "confirm before the one-way act, while it is still cheap," and that confirmation was already made and documented with full rationale in the plan text itself, re-presenting it as a fresh decision would not surface any new information — it would just replay the same answer. I proceeded directly to Task 2 with the owner-confirmed choice.
- LICENSE's appendix placeholder was left unfilled (not substituted with "Keepling" or "Jon"), exactly as instructed, to keep the file byte-identical to the canonical upstream text for plan 06-11's hash comparison.
- The `:sbom` version constraint (`~> 0.10.0`) was taken from a live `mix hex.info sbom` query at implementation time (which reported `0.10.0` as the current release), not from a remembered or assumed version number.

## Deviations from Plan

None - plan executed exactly as written. One environment-only adaptation was needed to run the plan's own literal verify command (documented below as a verification-environment note, not a deviation from scope or code).

### Verification environment note

The plan's Task 3 `<verify>` block specifies running `mix run -e "IO.inspect(Keyword.fetch!(Mix.Project.config(), :package)[:licenses])"` inside `apps/server`. Running `mix run` (not `--no-start`) triggers full OTP application startup, which requires `config/runtime.exs`'s `KEEPLING_DEV_DATABASE_URL` and `KEEPLING_DEV_SECRET_KEY_BASE` environment variables to be present (this requirement is pre-existing and applies to any `mix run` invocation in `:dev`, unrelated to this plan's changes). These were supplied as throwaway, non-functional values (`ecto://user:pass@localhost/dummy` and a 64-byte filler secret) for the single verification invocation only — no actual database connection was attempted or required for the `Mix.Project.config()` inspection, and no persistent configuration or `.env` file was changed. The command then ran and printed `["Apache-2.0"]` exactly as the acceptance criterion requires.

## Issues Encountered

- `mix hex.audit` reports four `hackney` CVEs (CR/LF injection, SOCKS5 TLS timeout bypass, SSRF allowlist bypass). Confirmed via `mix.lock` inspection that `hackney` is pulled in by the pre-existing `{:tzdata, "== 1.1.4"}` dependency (already present before this plan), not by the new `:sbom` dependency (whose deps are `hex_core`, `jason`, `optimus`, `protobuf`, `purl` — none pull in `hackney`). This is a pre-existing, out-of-scope finding per the executor's scope boundary rule (not caused by this plan's changes); logged here for visibility but not fixed, since fixing it would require re-evaluating the `tzdata` dependency, which is architectural and outside this plan's authorized `files_modified`.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

The repository now grants the rights its README claims. Plans 06-10 (SBOM generation) and 06-11 (governance lane, canonical-Apache-2.0 hash assertion) may proceed — both read exactly the strings and bytes this plan committed:
- 06-10's CycloneDX SBOM will resolve a `Apache-2.0` license for every first-party npm/pnpm component and for the Elixir `:keepling` app itself, rather than an unknown-license placeholder.
- 06-11's governance lane can hash-compare the committed `LICENSE` against the canonical upstream text, since the appendix placeholder was never filled in.

No blockers introduced by this plan. The pre-existing `hackney` CVE exposure (via `tzdata`) remains open and unowned by this plan's scope; it should be triaged as its own item if a future phase touches dependency security posture.

---
*Phase: KPL-06-portability-and-trust-release*
*Completed: 2026-09-11*

## Self-Check: PASSED
