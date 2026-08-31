# Phase KPL-01 Package Approval Dossier

**Status:** APPROVED — all eight exact versions<br>
**Inspected:** 2026-08-30 (America/New_York) / 2026-08-31 UTC<br>
**Approved:** 2026-08-30 (America/New_York), by the user's blanket `approved` checkpoint response<br>
**Scope:** Exact registry releases proposed for Phase KPL-01 Plans 01-02 through 01-04<br>
**Installation status:** None of the packages in this dossier has been installed by this review.

This dossier records official registry metadata, the registry-linked source identity, declared lifecycle hooks, and available provenance for every package flagged by `01-RESEARCH.md`. The user's blanket `approved` checkpoint response explicitly approves only the eight exact versions recorded below. Any later version requires a new review and disposition; this approval does not authorize silent substitution.

## Review method

- npm facts came from the exact-version document at `registry.npmjs.org`, the npm package page, and the registry's signed-attestation bundle.
- Each npm SLSA statement was decoded to identify the GitHub repository, workflow, ref, and resolved source commit. The statement subject SHA-512 matched the package's registry integrity digest.
- npm lifecycle inspection covered `preinstall`, `install`, `postinstall`, `prepublish`, `prepublishOnly`, and `prepare` in the published exact-version manifest, then compared the attested source `package.json` at the resolved commit.
- Hex facts came from the exact Hammer release API and downloaded package tarball. The tarball SHA-256 matched the Hex release checksum, and every packaged file byte-matched the linked source commit identified below.
- Evidence here establishes identity and provenance signals. It does not replace the required human disposition.

## Approval set

| Package | Exact version | Registry | Install-time lifecycle finding | Disposition |
| --- | ---: | --- | --- | --- |
| `hammer` | `7.4.1` | Hex | Mix build; no custom compiler, alias, or dependency hook in published `mix.exs` | APPROVED — exact version via blanket `approved` response |
| `react-router` | `8.3.1` | npm | No `preinstall`, `install`, `postinstall`, or `prepare` in published manifest | APPROVED — exact version via blanket `approved` response |
| `@tanstack/react-query` | `5.102.8` | npm | No lifecycle hooks in published manifest | APPROVED — exact version via blanket `approved` response |
| `vitest` | `4.1.11` | npm | No lifecycle hooks in published manifest | APPROVED — exact version via blanket `approved` response |
| `@testing-library/react` | `16.3.3` | npm | No lifecycle hooks in published manifest | APPROVED — exact version via blanket `approved` response |
| `@testing-library/user-event` | `14.6.6` | npm | No lifecycle hooks in published manifest | APPROVED — exact version via blanket `approved` response |
| `@testing-library/jest-dom` | `7.0.1` | npm | No lifecycle hooks in published manifest | APPROVED — exact version via blanket `approved` response |
| `@axe-core/playwright` | `4.13.0` | npm | Declares `prepare`; no `preinstall`, `install`, or `postinstall` | APPROVED — exact version via blanket `approved` response |

## Hammer

Package: hammer<br>
Version: 7.4.1<br>
Registry: Hex — https://hex.pm/packages/hammer/7.4.1<br>
Repository: https://github.com/ExHammer/hammer<br>
Publisher: Hex user and package owner `epinault`<br>
Maintainers: Published `mix.exs` names Emmanuel Pinault and June Kelly; the Hex package API's maintainers array is empty.<br>
Publish date: 2026-08-29T04:16:41.471019Z<br>
License: MIT<br>
Lifecycle scripts: npm-style lifecycle scripts do not apply. Hex declares `mix` as the build tool. The published `mix.exs` uses the standard Mix compiler and defines no custom compilers, aliases, or runtime dependencies.<br>
Provenance: The official release API reports SHA-256 `48dc0409c20be510c76b04d0ab51a8c40faf700997016ccc916603d157bde765`; the downloaded official tarball matched it. All 18 packaged regular files byte-matched source commit [`53c976ba4c0373cd8b4672bb5fef9ea67a54b64a`](https://github.com/ExHammer/hammer/commit/53c976ba4c0373cd8b4672bb5fef9ea67a54b64a), a GitHub-verified commit authored by `epinault` that bumps Hammer to 7.4.1. The repository does **not** expose a `v7.4.1` tag even though the package's docs configuration names that source ref; this discrepancy is explicitly part of the human review.<br>
Official evidence: [Hex exact release API](https://hex.pm/api/packages/hammer/releases/7.4.1), [Hex package API](https://hex.pm/api/packages/hammer), [source commit](https://github.com/ExHammer/hammer/commit/53c976ba4c0373cd8b4672bb5fef9ea67a54b64a), [repository tags](https://github.com/ExHammer/hammer/tags)<br>
Disposition: APPROVED — the user's blanket `approved` checkpoint response applies to exact version `hammer@7.4.1` and no substitute.

## React Router

Package: react-router<br>
Version: 8.3.1<br>
Registry: npm — https://www.npmjs.com/package/react-router/v/8.3.1<br>
Repository: https://github.com/remix-run/react-router/tree/da2a0f0948af60ba45d9590b427d5e58fe4b0109/packages/react-router<br>
Publisher: `GitHub Actions <npm-oidc-no-reply@github.com>` through npm trusted publisher OIDC configuration `oidc:f23c4f07-ce7d-474c-95b4-6bb6c96a5823`<br>
Maintainers: npm accounts `brophdawg11`, `mjackson`<br>
Publish date: 2026-08-28T14:47:42.622Z<br>
License: MIT<br>
Lifecycle scripts: The published manifest contains no `preinstall`, `install`, `postinstall`, `prepublish`, `prepublishOnly`, or `prepare`. The attested source manifest has `prepublishOnly: node ./scripts/copy-docs.mjs`, a publish-time hook absent from the published package manifest.<br>
Provenance: npm exposes publish and SLSA provenance attestations for `pkg:npm/react-router@8.3.1`. The SLSA statement maps the package SHA-512 digest to `remix-run/react-router` commit [`da2a0f0948af60ba45d9590b427d5e58fe4b0109`](https://github.com/remix-run/react-router/commit/da2a0f0948af60ba45d9590b427d5e58fe4b0109), built by `.github/workflows/release.yml` on GitHub-hosted Actions. Registry integrity is `sha512-TEOpiO2g0TJHEOJeRVv4amUFun9v1npCKszvcquNvzETUtJ8udV86ah5eFoHT7g26bsBvT6EiIhqulR8eDF++A==`.<br>
Official evidence: [exact registry document](https://registry.npmjs.org/react-router/8.3.1), [npm provenance bundle](https://registry.npmjs.org/-/npm/v1/attestations/react-router@8.3.1), [source commit](https://github.com/remix-run/react-router/commit/da2a0f0948af60ba45d9590b427d5e58fe4b0109)<br>
Disposition: APPROVED — the user's blanket `approved` checkpoint response applies to exact version `react-router@8.3.1` and no substitute.

## TanStack React Query

Package: @tanstack/react-query<br>
Version: 5.102.8<br>
Registry: npm — https://www.npmjs.com/package/@tanstack/react-query/v/5.102.8<br>
Repository: https://github.com/TanStack/query/tree/2969edf32f7e0c48e2a108d84712d6e01edfde21/packages/react-query<br>
Publisher: `GitHub Actions <npm-oidc-no-reply@github.com>` through npm trusted publisher OIDC configuration `oidc:723a6f52-dd1e-45dd-997e-011d5c0b77a0`<br>
Maintainers: npm accounts `tannerlinsley`, `alemtuzlak`, `kevinvandy`<br>
Publish date: 2026-08-27T16:06:57.089Z<br>
License: MIT<br>
Lifecycle scripts: No reviewed lifecycle hooks are present in either the published manifest or the attested source manifest.<br>
Provenance: npm exposes publish and SLSA provenance attestations for `pkg:npm/%40tanstack/react-query@5.102.8`. The SLSA statement maps the package SHA-512 digest to `TanStack/query` commit [`2969edf32f7e0c48e2a108d84712d6e01edfde21`](https://github.com/TanStack/query/commit/2969edf32f7e0c48e2a108d84712d6e01edfde21), built by `.github/workflows/release.yml` on GitHub-hosted Actions. Registry integrity is `sha512-TYBea4OuXWD7MhaSHq069TWbFe7rcwWN6kzT7JF0OKi1K6c1gTv2IzD6A6ExJsCMozdkqBWeuIUZmu4KQg0O5A==`.<br>
Official evidence: [exact registry document](https://registry.npmjs.org/@tanstack%2freact-query/5.102.8), [npm provenance bundle](https://registry.npmjs.org/-/npm/v1/attestations/@tanstack%2freact-query@5.102.8), [source commit](https://github.com/TanStack/query/commit/2969edf32f7e0c48e2a108d84712d6e01edfde21)<br>
Disposition: APPROVED — the user's blanket `approved` checkpoint response applies to exact version `@tanstack/react-query@5.102.8` and no substitute.

## Vitest

Package: vitest<br>
Version: 4.1.11<br>
Registry: npm — https://www.npmjs.com/package/vitest/v/4.1.11<br>
Repository: https://github.com/vitest-dev/vitest/tree/9bd8d464e6328c567c2dbcd8fdd977d57a9425c2/packages/vitest<br>
Publisher: `GitHub Actions <npm-oidc-no-reply@github.com>` through npm trusted publisher OIDC configuration `oidc:1f286ab6-26e9-44a1-ba48-3a20cbe590fd`; registry metadata records npm approver `oreanno`<br>
Maintainers: npm accounts `ariperkkio`, `antfu`, `hiogawa`, `oreanno`, `yyx990803`<br>
Publish date: 2026-08-18T14:27:07.240Z<br>
License: MIT<br>
Lifecycle scripts: No reviewed lifecycle hooks are present in either the published manifest or the attested source manifest.<br>
Provenance: npm exposes publish and SLSA provenance attestations for `pkg:npm/vitest@4.1.11`. The SLSA statement maps the package SHA-512 digest to `vitest-dev/vitest` commit [`9bd8d464e6328c567c2dbcd8fdd977d57a9425c2`](https://github.com/vitest-dev/vitest/commit/9bd8d464e6328c567c2dbcd8fdd977d57a9425c2), built from the `v4` branch by `.github/workflows/publish.yml` on GitHub-hosted Actions. Registry integrity is `sha512-fhACrNXUidIbGSBr5FlbuBkO7VWC1ZyLl0DO4CU2DrQoAPxX84Ysxs+HeGQpii5lZWV1Q4gBZTTu49mF+A6Edw==`.<br>
Official evidence: [exact registry document](https://registry.npmjs.org/vitest/4.1.11), [npm provenance bundle](https://registry.npmjs.org/-/npm/v1/attestations/vitest@4.1.11), [source commit](https://github.com/vitest-dev/vitest/commit/9bd8d464e6328c567c2dbcd8fdd977d57a9425c2)<br>
Disposition: APPROVED — the user's blanket `approved` checkpoint response applies to exact version `vitest@4.1.11` and no substitute.

## Testing Library React

Package: @testing-library/react<br>
Version: 16.3.3<br>
Registry: npm — https://www.npmjs.com/package/@testing-library/react/v/16.3.3<br>
Repository: https://github.com/testing-library/react-testing-library/tree/20ce75f2907ca0e5c5a8ae595c0e9a4e368c7800<br>
Publisher: `GitHub Actions <npm-oidc-no-reply@github.com>` through npm trusted publisher OIDC configuration `oidc:1400df4e-14d8-4ffa-8506-a621ef7a81ec`<br>
Maintainers: npm accounts `testing-library-bot`, `kentcdodds`, `timdeschryver`, `patrickhulce`, `dfcook`, `gpx`, `mpeyper`, `mihar-22`, `pago`, `cmckinstry`, `thymikee`, `brrianalexis`, `jdecroock`, `mdjastrzebski`, `eps1lon`, `phryneas`, `snowystinger`, `matanbobi`<br>
Publish date: 2026-08-27T17:41:18.735Z<br>
License: MIT<br>
Lifecycle scripts: No reviewed lifecycle hooks are present in either the published manifest or the attested source manifest.<br>
Provenance: npm exposes publish and SLSA provenance attestations for `pkg:npm/%40testing-library/react@16.3.3`. The SLSA statement maps the package SHA-512 digest to `testing-library/react-testing-library` commit [`20ce75f2907ca0e5c5a8ae595c0e9a4e368c7800`](https://github.com/testing-library/react-testing-library/commit/20ce75f2907ca0e5c5a8ae595c0e9a4e368c7800), built by `.github/workflows/release.yml` on GitHub-hosted Actions. Registry integrity is `sha512-Uo193NgQbPMz6lrrhtRQQFcMC6Re/ELLFbbuVL30WDlZxlpZf9/lMHTAVxPRLw1q1iu9OJmR1c2BLiENRstdBg==`.<br>
Official evidence: [exact registry document](https://registry.npmjs.org/@testing-library%2freact/16.3.3), [npm provenance bundle](https://registry.npmjs.org/-/npm/v1/attestations/@testing-library%2freact@16.3.3), [source commit](https://github.com/testing-library/react-testing-library/commit/20ce75f2907ca0e5c5a8ae595c0e9a4e368c7800)<br>
Disposition: APPROVED — the user's blanket `approved` checkpoint response applies to exact version `@testing-library/react@16.3.3` and no substitute.

## Testing Library user-event

Package: @testing-library/user-event<br>
Version: 14.6.6<br>
Registry: npm — https://www.npmjs.com/package/@testing-library/user-event/v/14.6.6<br>
Repository: https://github.com/testing-library/user-event/tree/71a547572e6f7793b925052c71aaabef6a443995<br>
Publisher: `GitHub Actions <npm-oidc-no-reply@github.com>` through npm trusted publisher OIDC configuration `oidc:08bd6589-4fbe-475a-ba4b-400a45e433f8`<br>
Maintainers: npm accounts `testing-library-bot`, `kentcdodds`, `timdeschryver`, `patrickhulce`, `dfcook`, `gpx`, `mpeyper`, `mihar-22`, `pago`, `cmckinstry`, `thymikee`, `brrianalexis`, `jdecroock`, `mdjastrzebski`, `eps1lon`, `phryneas`, `snowystinger`, `matanbobi`<br>
Publish date: 2026-08-22T02:06:46.844Z<br>
License: MIT<br>
Lifecycle scripts: No reviewed lifecycle hooks are present in either the published manifest or the attested source manifest.<br>
Provenance: npm exposes publish and SLSA provenance attestations for `pkg:npm/%40testing-library/user-event@14.6.6`. The SLSA statement maps the package SHA-512 digest to `testing-library/user-event` commit [`71a547572e6f7793b925052c71aaabef6a443995`](https://github.com/testing-library/user-event/commit/71a547572e6f7793b925052c71aaabef6a443995), built by `.github/workflows/ci.yml` on GitHub-hosted Actions. Registry integrity is `sha512-Jbs9FpkkIDw8FgSc6kOVsOv8JuuqGAL7J4X1oot77JxAoDlkNn2GRkd0aYRVuQ+pVQAiHWVkE4rX/dkF5fBiCw==`.<br>
Official evidence: [exact registry document](https://registry.npmjs.org/@testing-library%2fuser-event/14.6.6), [npm provenance bundle](https://registry.npmjs.org/-/npm/v1/attestations/@testing-library%2fuser-event@14.6.6), [source commit](https://github.com/testing-library/user-event/commit/71a547572e6f7793b925052c71aaabef6a443995)<br>
Disposition: APPROVED — the user's blanket `approved` checkpoint response applies to exact version `@testing-library/user-event@14.6.6` and no substitute.

## Testing Library jest-dom

Package: @testing-library/jest-dom<br>
Version: 7.0.1<br>
Registry: npm — https://www.npmjs.com/package/@testing-library/jest-dom/v/7.0.1<br>
Repository: https://github.com/testing-library/jest-dom/tree/3782c78b3dc9824675afe0cb8f1722f8c96f494d<br>
Publisher: `GitHub Actions <npm-oidc-no-reply@github.com>` through npm trusted publisher OIDC configuration `oidc:e0d2debc-1258-486a-af8e-d706f49b26f5`<br>
Maintainers: npm accounts `testing-library-bot`, `kentcdodds`, `timdeschryver`, `patrickhulce`, `dfcook`, `gpx`, `mpeyper`, `mihar-22`, `pago`, `cmckinstry`, `thymikee`, `brrianalexis`, `jdecroock`, `mdjastrzebski`, `eps1lon`, `phryneas`, `snowystinger`, `matanbobi`<br>
Publish date: 2026-08-09T23:44:33.598Z<br>
License: MIT<br>
Lifecycle scripts: No reviewed lifecycle hooks are present in either the published manifest or the attested source manifest.<br>
Provenance: npm exposes publish and SLSA provenance attestations for `pkg:npm/%40testing-library/jest-dom@7.0.1`. The SLSA statement maps the package SHA-512 digest to `testing-library/jest-dom` commit [`3782c78b3dc9824675afe0cb8f1722f8c96f494d`](https://github.com/testing-library/jest-dom/commit/3782c78b3dc9824675afe0cb8f1722f8c96f494d), built by `.github/workflows/validate.yml` on GitHub-hosted Actions. Registry integrity is `sha512-oMDTC3oA+6CXSO2JZnvOI7CA6oVub6kij5ggk9ohwye5slmkwxYDXcPOVxgMw/RQlticjtO0C1RZkR97HgrWMw==`.<br>
Official evidence: [exact registry document](https://registry.npmjs.org/@testing-library%2fjest-dom/7.0.1), [npm provenance bundle](https://registry.npmjs.org/-/npm/v1/attestations/@testing-library%2fjest-dom@7.0.1), [source commit](https://github.com/testing-library/jest-dom/commit/3782c78b3dc9824675afe0cb8f1722f8c96f494d)<br>
Disposition: APPROVED — the user's blanket `approved` checkpoint response applies to exact version `@testing-library/jest-dom@7.0.1` and no substitute.

## axe Playwright

Package: @axe-core/playwright<br>
Version: 4.13.0<br>
Registry: npm — https://www.npmjs.com/package/@axe-core/playwright/v/4.13.0<br>
Repository: https://github.com/dequelabs/axe-core-npm/tree/70dca949a4e55e2fb83e4e6896fbbf788c56b6fd/packages/playwright<br>
Publisher: `GitHub Actions <npm-oidc-no-reply@github.com>` through npm trusted publisher OIDC configuration `oidc:12fe4cc9-2ced-4071-a2a5-bc031837f5cd`<br>
Maintainers: npm accounts `dqlabs`, `wilcofiers`, `dylanb`, `npmdeque`, `stephendeque`<br>
Publish date: 2026-08-11T17:07:40.763Z<br>
License: MPL-2.0<br>
Lifecycle scripts: The published and attested source manifests declare `prepare: npx playwright install && npm run build`; neither declares `preinstall`, `install`, or `postinstall`. The declared `prepare` hook is retained as a specific supply-chain review flag rather than being summarized as “no scripts.”<br>
Provenance: npm exposes publish and SLSA provenance attestations for `pkg:npm/%40axe-core/playwright@4.13.0`. The SLSA statement maps the package SHA-512 digest to `dequelabs/axe-core-npm` commit [`70dca949a4e55e2fb83e4e6896fbbf788c56b6fd`](https://github.com/dequelabs/axe-core-npm/commit/70dca949a4e55e2fb83e4e6896fbbf788c56b6fd), built by `.github/workflows/deploy.yml` on GitHub-hosted Actions. Registry integrity is `sha512-6YLx+kxXu5GJceG4ozFg+33a2EMTdjYwWGloJ3sb9Kta5pp+ZNS53uxGVog5JetIY8s++P5UrtX+cri+u0VAVg==`.<br>
Official evidence: [exact registry document](https://registry.npmjs.org/@axe-core%2fplaywright/4.13.0), [npm provenance bundle](https://registry.npmjs.org/-/npm/v1/attestations/@axe-core%2fplaywright@4.13.0), [source commit](https://github.com/dequelabs/axe-core-npm/commit/70dca949a4e55e2fb83e4e6896fbbf788c56b6fd)<br>
Disposition: APPROVED — the user's blanket `approved` checkpoint response applies to exact version `@axe-core/playwright@4.13.0` and no substitute.

## Human response recorded

The user replied exactly `approved` at the blocking-human checkpoint. That blanket response approves all eight exact versions above and only those versions. No package was rejected; downstream plans may install these exact pins after their own prerequisites pass.
