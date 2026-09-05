#!/usr/bin/env node
/**
 * D-12: generates the committed Swift wire client for apps/ios/ from
 * packages/contracts/openapi/keepling.yaml using the pinned
 * swift-openapi-generator CLI (built from source, not vendored -- see
 * apps/ios/README.md for the resolved tag and the one-time build command).
 *
 * Mirrors tooling/check-contracts.mjs's committed-generated-output
 * precedent: `--check` regenerates into a scratch directory and diffs
 * against the committed output under
 * apps/ios/Sources/KeeplingCore/Transport/Generated/, exiting non-zero on
 * any difference, rather than trusting a build-tool plugin (D-12 rejects
 * build-tool plugins outright: their output is not diff-reviewable).
 */
import { spawnSync } from 'node:child_process'
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import process from 'node:process'

const repositoryRoot = resolve(import.meta.dirname, '..')
const iosRoot = join(repositoryRoot, 'apps', 'ios')
const contractPath = join(repositoryRoot, 'packages', 'contracts', 'openapi', 'keepling.yaml')
const configPath = join(iosRoot, 'openapi-generator-config.yaml')
const committedOutputDir = join(iosRoot, 'Sources', 'KeeplingCore', 'Transport', 'Generated')

const generatorBinaryEnv = process.env.KEEPLING_SWIFT_OPENAPI_GENERATOR_BIN
const generatorBinary = generatorBinaryEnv && generatorBinaryEnv.length > 0
  ? generatorBinaryEnv
  : join(repositoryRoot, '.build-tools', 'swift-openapi-generator')

const fail = (message) => {
  process.stderr.write(`generate-ios-client: ${message}\n`)
  process.exit(1)
}

if (!existsSync(contractPath)) fail(`missing OpenAPI contract at ${contractPath}`)
if (!existsSync(configPath)) fail(`missing generator config at ${configPath}`)
if (!existsSync(generatorBinary)) {
  fail(
    `swift-openapi-generator binary not found at ${generatorBinary}. ` +
      'Build it once per apps/ios/README.md (git clone the pinned tag, `swift build -c release`, ' +
      'and place/symlink the resulting binary there), or set KEEPLING_SWIFT_OPENAPI_GENERATOR_BIN.',
  )
}

const runGenerate = (outputDirectory) => {
  const result = spawnSync(
    generatorBinary,
    ['generate', contractPath, '--config', configPath, '--output-directory', outputDirectory],
    { cwd: repositoryRoot, encoding: 'utf8' },
  )
  const stdout = result.stdout ?? ''
  const stderr = result.stderr ?? ''
  if (result.status !== 0 || result.error) {
    fail(`generator invocation failed (exit ${String(result.status)}):\n${stdout}\n${stderr}`)
  }
  if (/warning:/i.test(stderr) || /warning:/i.test(stdout)) {
    // D-13: a warning here means the contract still contains a shape the
    // generator cannot fully represent (e.g. the nullable-anyOf decode
    // defect this phase's Task 1 exists to remove). A silently-accepted
    // warning is exactly how that defect shipped invisibly before.
    fail(`generator reported warnings -- treat as a hard failure:\n${stdout}\n${stderr}`)
  }
  return { stderr, stdout }
}

const checkMode = process.argv.includes('--check')

if (!checkMode) {
  runGenerate(committedOutputDir)
  process.stdout.write(`generate-ios-client: wrote generated Swift client to ${committedOutputDir}\n`)
  process.exit(0)
}

const scratchDir = mkdtempSync(join(tmpdir(), 'keepling-ios-client-'))
try {
  runGenerate(scratchDir)
  const committedFiles = existsSync(committedOutputDir) ? readdirSync(committedOutputDir).sort() : []
  const freshFiles = readdirSync(scratchDir).sort()
  if (committedFiles.join(',') !== freshFiles.join(',')) {
    fail(
      `generated file set differs from committed output.\n  committed: ${committedFiles.join(', ')}\n  fresh: ${freshFiles.join(', ')}`,
    )
  }
  let anyDiff = false
  for (const file of freshFiles) {
    const committed = readFileSync(join(committedOutputDir, file), 'utf8')
    const fresh = readFileSync(join(scratchDir, file), 'utf8')
    if (committed !== fresh) {
      anyDiff = true
      process.stderr.write(`generate-ios-client --check: ${file} differs from the committed generated output\n`)
    }
  }
  if (anyDiff) process.exit(1)
  process.stdout.write(`generate-ios-client --check: committed Swift client is current (${freshFiles.length} files)\n`)
} finally {
  rmSync(scratchDir, { recursive: true, force: true })
}
