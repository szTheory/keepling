import { spawnSync } from 'node:child_process'
import { accessSync, constants } from 'node:fs'
import { resolve } from 'node:path'
import process from 'node:process'

const repositoryRoot = resolve(import.meta.dirname, '..')
const source = resolve(
  repositoryRoot,
  'packages/contracts/openapi/keepling.yaml',
)
const generated = resolve(
  repositoryRoot,
  'packages/contracts/generated/keepling.ts',
)

for (const path of [source, generated]) {
  try {
    accessSync(path, constants.R_OK)
  } catch {
    process.stderr.write(`Contract drift check failed: missing readable file ${path}\n`)
    process.exit(1)
  }
}

const result = spawnSync(
  'pnpm',
  [
    'exec',
    'openapi-typescript',
    source,
    '--output',
    generated,
    '--alphabetize',
    '--immutable',
    '--check',
  ],
  {
    cwd: repositoryRoot,
    stdio: 'inherit',
  },
)

if (result.error) {
  process.stderr.write(`Contract drift check failed: ${result.error.message}\n`)
  process.exit(1)
}

if (result.status !== 0) {
  process.exit(result.status ?? 1)
}

process.stdout.write('Contract drift check passed: OpenAPI and TypeScript agree\n')
