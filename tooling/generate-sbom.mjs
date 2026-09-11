#!/usr/bin/env node
/**
 * tooling/generate-sbom.mjs (06-10-PLAN.md Task 4, D-20)
 *
 * Produces two CycloneDX bills of materials, generated FROM SOURCE, never by
 * scanning the built application. `apps/desktop/forge.config.ts` ignores
 * `node_modules` and ships four bundled outputs (main/preload/renderer/worker),
 * so a binary scan of the packaged `.app` would see minified code and produce
 * a handful of entries for an application with hundreds of npm resolutions --
 * a near-empty document presented as a complete inventory is precisely the
 * vacuous green this project has been burned by (Pitfall 3, 06-RESEARCH.md).
 *
 * Outputs, written to `--out <dir>`:
 *   sbom-hex.cdx.json  -- Hex/Elixir dependencies, via the dev-only,
 *                         non-runtime `:sbom` mix task plan 06-03 added
 *                         (apps/server/mix.exs). Reads each dependency's
 *                         declared licence, including the first-party
 *                         `keepling` component's own `Apache-2.0` (plan
 *                         06-03's `package/0`).
 *   sbom-npm.cdx.json  -- npm/pnpm dependencies across the whole workspace,
 *                         via the CycloneDX project's own npm CLI
 *                         (`@cyclonedx/cyclonedx-npm`, pinned to the exact
 *                         version verified against the npm registry in
 *                         06-RESEARCH.md's Package Legitimacy Audit), invoked
 *                         through `npx` so it never enters `pnpm-lock.yaml`.
 *
 * The THIRD ecosystem, Swift (`apps/ios/Package.resolved`), is deliberately
 * NOT scanned here. Its resolved-file format is `"version": 3`, which the
 * common scanner (syft) cannot parse (github.com/anchore/syft/issues/2759),
 * and SwiftPM's own native SBOM support is still only a proposal (SE-0509).
 * The lockfile is published as-is at its existing committed path, and this
 * gap is declared out loud in `docs/security/SUPPLY-CHAIN.md` -- never
 * silently filled with an under-reporting scan (D-20).
 */
import { existsSync, mkdirSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import process from 'node:process'
import { spawnSync } from 'node:child_process'

const toolingDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(toolingDirectory, '..')

// [VERIFIED: 06-RESEARCH.md Package Legitimacy Audit -- npm registry,
// verdict OK, weeklyDownloads 370402, repo github.com/CycloneDX/cyclonedx-node-npm]
const CYCLONEDX_NPM_VERSION = '6.0.1'

function fail(message) {
  console.error(`generate-sbom failed: ${message}`)
  process.exit(1)
}

function parseArgs(argv) {
  const args = { out: null }
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--out') {
      args.out = argv[i + 1]
      i += 1
    }
  }
  if (!args.out) fail('--out <dir> is required')
  return args
}

const { out } = parseArgs(process.argv.slice(2))
const outputDirectory = resolve(repositoryRoot, out)
if (!existsSync(outputDirectory)) mkdirSync(outputDirectory, { recursive: true })

const hexOutputPath = join(outputDirectory, 'sbom-hex.cdx.json')
const npmOutputPath = join(outputDirectory, 'sbom-npm.cdx.json')

// Hex/Elixir: generated from apps/server/mix.exs + mix.lock via the dev-only
// `:sbom` task (runtime: false -- never reaches a production build). Uses
// the repository's own runtime-preflight wrapper so the exact pinned
// Elixir/OTP toolchain (tooling/runtime-versions.env) is selected the same
// way every other Elixir invocation in this repository selects it.
console.log(`Generating Hex SBOM from source (apps/server) -> ${hexOutputPath}`)
// `runtime-preflight.sh --exec` itself `cd`s to the repository root before
// exec-ing its command, so a `cwd` passed to spawnSync here would be
// silently overridden -- the server subdirectory change must happen inside
// the command runtime-preflight.sh execs, via an explicit `sh -c 'cd ...'`.
const hexResult = spawnSync(
  join(repositoryRoot, 'tooling', 'runtime-preflight.sh'),
  [
    '--exec',
    '--',
    'sh',
    '-c',
    `cd apps/server && mix sbom.cyclonedx --force --pretty --output '${hexOutputPath}'`,
  ],
  {
    cwd: repositoryRoot,
    env: { ...process.env, MIX_ENV: 'dev' },
    stdio: 'inherit',
  },
)
if (hexResult.status !== 0) fail('mix sbom.cyclonedx exited non-zero')
if (!existsSync(hexOutputPath)) fail(`${hexOutputPath} was not produced`)

// npm/pnpm: generated from source across the whole workspace's installed
// tree via the CycloneDX project's own first-party npm CLI, invoked through
// `npx` so it is never added to package.json or pnpm-lock.yaml.
// `--ignore-npm-errors` is required, not optional, in this repository: the
// tool shells out to `npm ls --json --long --all` internally, and pnpm's
// node_modules layout does not match npm's own expected tree (pnpm hoists
// and symlinks differently), so plain `npm ls` reports every pnpm-managed
// package as "extraneous" and exits non-zero even though nothing is
// actually missing or broken -- this is a package-manager-shape mismatch,
// not a real dependency problem, and cyclonedx-npm still produces a
// complete document from the reachable tree despite the printed npm errors.
console.log(`Generating npm SBOM from source (workspace root) -> ${npmOutputPath}`)
const npmResult = spawnSync(
  'npx',
  [
    '--yes',
    `@cyclonedx/cyclonedx-npm@${CYCLONEDX_NPM_VERSION}`,
    '--ignore-npm-errors',
    '--output-format',
    'JSON',
    '--output-file',
    npmOutputPath,
  ],
  {
    cwd: repositoryRoot,
    stdio: 'inherit',
  },
)
if (npmResult.status !== 0) fail('cyclonedx-npm exited non-zero')
if (!existsSync(npmOutputPath)) fail(`${npmOutputPath} was not produced`)

console.log(
  `SBOM generation complete: ${hexOutputPath}, ${npmOutputPath}. ` +
    'The Swift ecosystem (apps/ios/Package.resolved) is published as-is, ' +
    'gap declared in docs/security/SUPPLY-CHAIN.md -- not scanned here.',
)
