import { spawnSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const phaseDirectory = resolve(
  repositoryRoot,
  '.planning/phases/KPL-01-one-trustworthy-task',
)
const uatPath = resolve(phaseDirectory, '01-UAT.md')

const checkpoints = [
  {
    marker: '@uat-accessibility',
    minimumCases: 8,
    name: 'Assistive-technology semantics and keyboard continuity',
    supportingFiles: [
      'apps/web/src/test/ui-contract.test.tsx',
      'apps/web/src/features/tasks/conflict-resolver.test.tsx',
      'apps/web/src/features/tasks/lifecycle.test.tsx',
      'apps/web/src/features/sessions/session-list.test.tsx',
    ],
  },
  {
    marker: '@uat-reflow',
    minimumCases: 4,
    name: 'Responsive, theme, zoom, forced-color, and reduced-motion contract',
    supportingFiles: [
      'apps/web/e2e/visual.spec.ts',
      'apps/web/e2e/responsive-route-matrix.spec.ts',
      'packages/design-tokens/tokens.json',
    ],
  },
  {
    marker: '@uat-auth-interop',
    minimumCases: 5,
    name: 'Password-manager-compatible authentication and exact recovery',
    supportingFiles: [
      'apps/web/src/features/auth/auth.test.tsx',
      'apps/web/e2e/auth-recovery.spec.ts',
      'apps/web/e2e/lifecycle-recovery.spec.ts',
    ],
  },
]

const fail = (message) => {
  process.stderr.write(`Phase 1 automated UAT coverage failed: ${message}\n`)
  process.exit(1)
}

if (!existsSync(uatPath)) fail('01-UAT.md is missing')

const uat = readFileSync(uatPath, 'utf8')
if (!/^status: complete$/m.test(uat)) fail('01-UAT.md is not complete')
if (/result: \[pending\]|awaiting: user response|status: pending/.test(uat)) {
  fail('01-UAT.md still contains a pending user checkpoint')
}

for (const { marker, name, supportingFiles } of checkpoints) {
  if (!uat.includes(`coverage_marker: ${marker}`)) {
    fail(`01-UAT.md does not map "${name}" to ${marker}`)
  }
  for (const relativePath of supportingFiles) {
    if (!existsSync(resolve(repositoryRoot, relativePath))) {
      fail(`supporting evidence is missing: ${relativePath}`)
    }
  }
}

const listed = spawnSync(
  'pnpm',
  ['--filter', '@keepling/web', 'exec', 'playwright', 'test', '--list'],
  { cwd: repositoryRoot, encoding: 'utf8' },
)

if (listed.status !== 0) {
  process.stderr.write(listed.stdout)
  process.stderr.write(listed.stderr)
  fail('Playwright could not enumerate the real-stack evidence')
}

const inventory = `${listed.stdout}\n${listed.stderr}`
let mappedCases = 0
for (const { marker, minimumCases, name } of checkpoints) {
  const count = inventory.split(marker).length - 1
  if (count < minimumCases) {
    fail(`"${name}" has ${count} listed ${marker} cases; expected at least ${minimumCases}`)
  }
  mappedCases += count
}

const automatedResults = [...uat.matchAll(/^result: pass$/gm)].length
const automatedSources = [...uat.matchAll(/^source: automated$/gm)].length
if (automatedResults !== checkpoints.length || automatedSources !== checkpoints.length) {
  fail(
    `01-UAT.md must contain exactly ${checkpoints.length} automated passing checkpoints ` +
      `(found ${automatedResults} passes and ${automatedSources} automated sources)`,
  )
}

process.stdout.write(
  `Phase 1 automated UAT coverage passed: ${checkpoints.length}/${checkpoints.length} checkpoints mapped to ${mappedCases} listed Playwright cases plus component and contract evidence\n`,
)
