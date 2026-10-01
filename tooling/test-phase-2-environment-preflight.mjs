#!/usr/bin/env node

import assert from 'node:assert/strict'
import { chmod, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { execFileSync, spawnSync } from 'node:child_process'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const command = path.join(root, 'tooling/check-phase-2-environment.mjs')
const testCommand = fileURLToPath(import.meta.url)
const implementation = await readFile(command, 'utf8')
const requiredSecrets = [
  'HCLOUD_TOKEN',
  'CLOUDFLARE_API_TOKEN',
  'KEEPLING_BACKUP_PRIMARY_ACCESS_KEY',
  'KEEPLING_BACKUP_PRIMARY_SECRET_KEY',
  'KEEPLING_BACKUP_MIRROR_ACCESS_KEY',
  'KEEPLING_BACKUP_MIRROR_SECRET_KEY',
  'KEEPLING_BACKUP_MIRROR_ENDPOINT',
  'KEEPLING_BACKUP_MIRROR_REGION',
  'KEEPLING_BACKUP_MIRROR_BUCKET',
  'KEEPLING_TOFU_STATE_ACCESS_KEY',
  'KEEPLING_TOFU_STATE_SECRET_KEY',
  'KEEPLING_TOFU_STATE_ENDPOINT',
  'KEEPLING_TOFU_STATE_REGION',
  'KEEPLING_TOFU_STATE_BUCKET',
  'KEEPLING_BACKUP_CIPHER_PASSPHRASE',
  'KEEPLING_SSH_PRIVATE_KEY',
]
const requiredContexts = ['All required checks passed', 'Desktop checks passed', 'iOS simulator checks passed']
const apiVersion = '2026-03-10'
const sentinel = 'FAKE_SECRET_SENTINEL_DO_NOT_PRINT_93b164'
const stub = `#!/usr/bin/env node
const fs = require('node:fs')
const mode = process.env.GH_STUB_MODE || 'ready'
const expected = JSON.parse(process.env.GH_STUB_SECRETS_JSON || '[]')
const ledger = process.env.GH_STUB_LEDGER
const sentinel = ${JSON.stringify(sentinel)}
const fail = (message, code = 90) => { process.stderr.write(message + ' ' + sentinel + '\\n'); process.exit(code) }
const out = (value) => process.stdout.write(JSON.stringify(value) + '\\n')
const args = process.argv.slice(2)
if (args[0] === 'auth' && args[1] === 'status') {
  if (mode === 'unauthenticated') fail('not authenticated', 1)
  process.exit(0)
}
if (args[0] !== 'api') fail('non-api command refused')
const methodIndex = args.indexOf('--method')
const method = methodIndex >= 0 ? args[methodIndex + 1] : 'GET'
const endpoint = args[args.length - 1]
if (method !== 'GET') fail('non-GET request refused')
if (!args.includes('X-GitHub-Api-Version: ${apiVersion}')) fail('API version missing')
if (ledger) fs.appendFileSync(ledger, method + '\\t' + endpoint + '\\n', { mode: 0o600 })
if (/\\/secrets\\/[^?]/.test(endpoint)) fail('secret-value endpoint refused')
if (mode === 'permission' && endpoint.includes('/environments/phase-2-protected-environment/secrets?')) fail('permission denied', 1)
if (mode === 'api-error' && endpoint.endsWith('/branches/main/protection')) fail('API failure', 1)
const base = endpoint.split('?')[0]
if (base === 'repos/szTheory/keepling') return out({ full_name: 'szTheory/keepling', private: false })
if (base === 'repos/szTheory/keepling/environments/phase-2-protected-environment') {
  const restricted = mode !== 'unrestricted'
  const result = {
    protection_rules: mode === 'no-reviewer' ? [] : [{ type: 'required_reviewers', reviewers: [{ type: 'User', reviewer: { login: 'szTheory' } }] }],
    deployment_branch_policy: { protected_branches: !restricted, custom_branch_policies: restricted },
  }
  if (mode === 'hostile') result.fixture_note = sentinel
  return out(result)
}
if (base.endsWith('/deployment-branch-policies')) {
  const policies = mode === 'non-main-policy'
    ? [{ name: 'main', type: 'branch' }, { name: 'release', type: 'branch' }]
    : [{ name: 'main', type: 'branch' }]
  return out([{ total_count: policies.length, branch_policies: policies }])
}
if (base.endsWith('/environments/phase-2-protected-environment/secrets')) {
  const omit = process.env.GH_STUB_MISSING_SECRET || ''
  const secrets = expected.filter((name) => name !== omit).map((name) => {
    const item = { name }
    if (mode === 'hostile') item.encrypted_value = sentinel
    return item
  })
  const total = secrets.length + (mode === 'incomplete-pagination' ? 1 : 0)
  return out([{ total_count: total, secrets }])
}
if (base.endsWith('/branches/main/protection')) {
  const contexts = mode === 'missing-context' ? ${JSON.stringify(requiredContexts)}.slice(1) : ${JSON.stringify(requiredContexts)}
  return out({
    required_pull_request_reviews: { required_approving_review_count: 0 },
    required_status_checks: { strict: true, contexts, checks: contexts.map((context) => ({ context, app_id: 15368 })) },
    enforce_admins: { enabled: true },
    allow_force_pushes: { enabled: false },
    allow_deletions: { enabled: false },
  })
}
fail('unexpected endpoint')
`

function validateReport(text) {
  if (typeof text !== 'string' || text.includes(sentinel) || /(?:ghp_|github_pat_|-----BEGIN [A-Z ]*PRIVATE KEY-----)/.test(text)) return false
  const lines = text.trimEnd().split('\n')
  const fixed = new Set([
    '# Phase 2 Environment Readiness',
    'environment: phase-2-protected-environment',
    'This report proves configuration readiness only; it is not owner authorization or live acceptance.',
  ])
  const findings = new Set([
    'github-cli-auth-failed', 'github-api-unavailable', 'repository-identity-mismatch', 'api-response-invalid',
    'pagination-incomplete', 'required-reviewer-missing', 'deployment-policy-not-main-only',
    'main-protection-mismatch', 'required-secret-names-missing', 'report-write-failed',
  ])
  let inMissing = false
  let inFindings = false
  let status = ''
  const missing = []
  const reportFindings = []
  for (const line of lines) {
    if (fixed.has(line) || line === '') continue
    if (/^status: (READY|BLOCKED|ERROR)$/.test(line)) { status = line.slice(8); continue }
    if (/^checked_at: \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(line)) continue
    if (/^required_reviewer: (PASS|FAIL|UNKNOWN)$/.test(line)) { inMissing = false; inFindings = false; continue }
    if (/^main_only_deployment_policy: (PASS|FAIL|UNKNOWN)$/.test(line)) { inMissing = false; inFindings = false; continue }
    if (/^stable_main_protection: (PASS|FAIL|UNKNOWN)$/.test(line)) { inMissing = false; inFindings = false; continue }
    if (line === 'missing_required_secret_names:') { inMissing = true; inFindings = false; continue }
    if (line === 'findings:') { inMissing = false; inFindings = true; continue }
    const item = /^  - ([A-Z][A-Z0-9_]*|none)$/.exec(line)
    if (item && inMissing) {
      if (item[1] !== 'none') {
        if (!requiredSecrets.includes(item[1])) return false
        missing.push(item[1])
      }
      continue
    }
    const finding = /^  - ([a-z][a-z0-9-]*)$/.exec(line)
    if (finding && inFindings) {
      if (finding[1] !== 'none' && !findings.has(finding[1])) return false
      if (finding[1] !== 'none') reportFindings.push(finding[1])
      continue
    }
    return false
  }
  if (!status || new Set(missing).size !== missing.length) return false
  if (status === 'READY') return missing.length === 0 && reportFindings.length === 0 && lines.includes('required_reviewer: PASS') && lines.includes('main_only_deployment_policy: PASS') && lines.includes('stable_main_protection: PASS')
  if (status === 'BLOCKED') return reportFindings.some((item) => item === 'required-secret-names-missing' || item === 'required-reviewer-missing' || item === 'deployment-policy-not-main-only' || item === 'main-protection-mismatch')
  return status === 'ERROR' && reportFindings.some((item) => ['github-cli-auth-failed', 'github-api-unavailable', 'repository-identity-mismatch', 'api-response-invalid', 'pagination-incomplete'].includes(item))
}

function runCommand(args, env = {}) {
  return spawnSync(process.execPath, [command, ...args], {
    encoding: 'utf8',
    env: { ...process.env, ...env },
    timeout: 30_000,
  })
}

function assertRequestsAreReadOnly(ledgerPath) {
  const lines = ledgerPath ? [] : []
  if (ledgerPath) {
    try { lines.push(...execFileSync('/bin/cat', [ledgerPath], { encoding: 'utf8' }).trim().split('\n').filter(Boolean)) } catch {}
  }
  const allowed = new Set([
    'repos/szTheory/keepling',
    'repos/szTheory/keepling/environments/phase-2-protected-environment',
    'repos/szTheory/keepling/environments/phase-2-protected-environment/deployment-branch-policies?per_page=100',
    'repos/szTheory/keepling/environments/phase-2-protected-environment/secrets?per_page=100',
    'repos/szTheory/keepling/branches/main/protection',
  ])
  for (const line of lines) {
    const match = /^GET\t(.+)$/.exec(line)
    assert.ok(match, 'only explicit GET requests are allowed')
    assert.ok(allowed.has(match[1]), 'unexpected or secret-value endpoint: ' + match[1])
    assert.ok(!match[1].includes('/secrets/'), 'secret-value endpoint must never be called')
  }
}

const args = process.argv.slice(2)
if (args[0] === '--check-report') {
  const report = args[1] ? await readFile(path.resolve(args[1]), 'utf8').catch(() => '') : ''
  if (!validateReport(report)) {
    process.stderr.write('FAIL - report schema or redaction check failed\n')
    process.exit(1)
  }
  process.stdout.write('PASS - sanitized report schema and redaction verified without GitHub calls\n')
  process.exit(0)
}

assert.match(implementation, /args\.push\('--method', 'GET'/, 'every GitHub API request must explicitly use GET')
assert.match(implementation, /--paginate/, 'list endpoints must paginate')
assert.match(implementation, /--slurp/, 'all page results must be collected')
assert.doesNotMatch(implementation, /--method['", ]+['"](?:POST|PATCH|PUT|DELETE)['"]/, 'mutating HTTP methods are forbidden')
assert.doesNotMatch(implementation, /gh\s+(?:secret\s+set|workflow\s+run|environment\s+set)/, 'mutating gh subcommands are forbidden')
assert.doesNotMatch(implementation, /\/environments\/[^\s'"`]+\/secrets\/[A-Z]/, 'secret-value API paths are forbidden')

const temp = await mkdtemp(path.join(os.tmpdir(), 'keepling-phase2-preflight-'))
try {
  const bin = path.join(temp, 'gh-stub')
  await writeFile(bin, stub, { mode: 0o700 })
  await chmod(bin, 0o700)
  const ledger = path.join(temp, 'requests.log')
  const reportPath = path.join(temp, 'readiness.md')
  const common = {
    GH_BIN: bin,
    GH_STUB_LEDGER: ledger,
    GH_STUB_SECRETS_JSON: JSON.stringify(requiredSecrets),
  }

  const help = runCommand(['--help'], { ...common, GH_STUB_MODE: 'unauthenticated' })
  assert.equal(help.status, 0, 'help should exit successfully')
  assert.match(help.stdout, /Usage: tooling\/check-phase-2-environment\.sh/)
  assert.equal(await readFile(ledger, 'utf8').catch(() => ''), '', 'help must not make GitHub calls')

  async function execute(mode, extra = {}) {
    await writeFile(ledger, '', { mode: 0o600 })
    const result = runCommand(['--repo', 'szTheory/keepling', '--output', reportPath], {
      ...common,
      GH_STUB_MODE: mode,
      ...extra,
    })
    const output = result.stdout || ''
    const report = await readFile(reportPath, 'utf8').catch(() => '')
    assertRequestsAreReadOnly(ledger)
    assert.equal(output.includes(sentinel), false, 'stdout must not expose a hostile secret sentinel')
    assert.equal(report.includes(sentinel), false, 'report must not expose a hostile secret sentinel')
    return { code: result.status, output, report, ledger: await readFile(ledger, 'utf8').catch(() => '') }
  }

  let result = await execute('ready')
  assert.equal(result.code, 0, 'fully configured environment should be READY')
  assert.match(result.report, /^status: READY$/m)
  assert.equal(validateReport(result.report), true)
  const stat = await (await import('node:fs/promises')).stat(reportPath)
  assert.equal(stat.mode & 0o777, 0o600, 'readiness report must be mode 0600')

  for (const name of requiredSecrets) {
    result = await execute('ready', { GH_STUB_MISSING_SECRET: name })
    assert.equal(result.code, 1, 'missing secret must return BLOCKED: ' + name)
    assert.match(result.report, /^status: BLOCKED$/m)
    assert.match(result.report, new RegExp('^  - ' + name + '$', 'm'))
    const reported = result.report.match(/^  - ([A-Z][A-Z0-9_]*)$/gm) || []
    assert.equal(reported.length, 1, 'only the missing symbolic name should be reported')
    assert.equal(validateReport(result.report), true)
  }

  for (const [mode, expectedFinding] of [
    ['no-reviewer', 'required-reviewer-missing'],
    ['unrestricted', 'deployment-policy-not-main-only'],
    ['non-main-policy', 'deployment-policy-not-main-only'],
    ['missing-context', 'main-protection-mismatch'],
  ]) {
    result = await execute(mode)
    assert.equal(result.code, 1, mode + ' must return BLOCKED')
    assert.match(result.report, new RegExp('^  - ' + expectedFinding + '$', 'm'))
    assert.equal(validateReport(result.report), true)
  }

  for (const [mode, expectedFinding] of [
    ['unauthenticated', 'github-cli-auth-failed'],
    ['permission', 'github-api-unavailable'],
    ['api-error', 'github-api-unavailable'],
    ['incomplete-pagination', 'pagination-incomplete'],
  ]) {
    result = await execute(mode)
    assert.equal(result.code, 2, mode + ' must fail closed as ERROR')
    assert.match(result.report, /^status: ERROR$/m)
    assert.match(result.report, new RegExp('^  - ' + expectedFinding + '$', 'm'))
    assert.equal(validateReport(result.report), true)
  }

  result = await execute('hostile')
  assert.equal(result.code, 0, 'unknown hostile API fields do not affect the readiness result')
  assert.equal(result.output.includes(sentinel), false)
  assert.equal(result.report.includes(sentinel), false)
  assert.equal(result.ledger.split('\n').filter(Boolean).length, 5, 'only the five expected read-only API requests run')

  const beforeCheck = await readFile(ledger, 'utf8')
  const reportCheck = spawnSync(process.execPath, [testCommand, '--check-report', reportPath], {
    encoding: 'utf8',
    env: { ...process.env, ...common, GH_STUB_MODE: 'unauthenticated' },
    timeout: 30_000,
  })
  assert.equal(reportCheck.status, 0, 'report validation must be hermetic')
  assert.match(reportCheck.stdout, /^PASS - sanitized report schema and redaction verified/m)
  assert.equal(await readFile(ledger, 'utf8'), beforeCheck, 'report check must not invoke gh')

  const invalid = result.report.replace('status: READY', 'status: READY\nsecret_value: ' + sentinel)
  assert.equal(validateReport(invalid), false, 'allowlist validator must reject extra fields and sentinels')
  process.stdout.write('PASS - Phase 2 environment preflight policy, pagination, refusal, read-only, and redaction cases\n')
} finally {
  await rm(temp, { recursive: true, force: true })
}
