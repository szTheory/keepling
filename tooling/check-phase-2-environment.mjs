#!/usr/bin/env node

import { execFileSync } from 'node:child_process'
import { chmod, mkdir, open, rename, rm } from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import { randomUUID } from 'node:crypto'
import { fileURLToPath } from 'node:url'

const API_VERSION = '2026-03-10'
const REPOSITORY = 'szTheory/keepling'
const ENVIRONMENT = 'phase-2-protected-environment'
const PROTECTION_APP_ID = 15368
const REQUIRED_SECRETS = [
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
const REQUIRED_CONTEXTS = [
  'All required checks passed',
  'Desktop checks passed',
  'iOS simulator checks passed',
]
const FINDINGS = new Set([
  'github-cli-auth-failed',
  'github-api-unavailable',
  'repository-identity-mismatch',
  'api-response-invalid',
  'pagination-incomplete',
  'required-reviewer-missing',
  'deployment-policy-not-main-only',
  'main-protection-mismatch',
  'required-secret-names-missing',
  'report-write-failed',
])
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const DEFAULT_OUTPUT = path.join(
  root,
  '.planning/quick/261001-j58-add-a-read-only-pre-dispatch-phase-2-git/261001-j58-READINESS.md',
)
const usage = `Usage: tooling/check-phase-2-environment.sh [--repo szTheory/keepling] [--output PATH]

Read-only GitHub readiness check for the Phase 2 protected environment.
Reads environment policy, environment secret names, and main branch protection.
Never reads secret values or dispatches a workflow.`

class PreflightError extends Error {
  constructor(code) {
    super(code)
    this.code = code
  }
}

function parseArgs(args) {
  let repo = REPOSITORY
  let output = DEFAULT_OUTPUT
  const seen = new Set()
  for (let i = 0; i < args.length; i += 1) {
    const key = args[i]
    if (key === '--help' || key === '-h') return { help: true }
    if (!['--repo', '--output'].includes(key) || seen.has(key) || !args[i + 1]) {
      throw new PreflightError('usage')
    }
    seen.add(key)
    const value = args[++i]
    if (key === '--repo') repo = value
    else output = path.resolve(value)
  }
  if (repo.toLowerCase() !== REPOSITORY.toLowerCase()) throw new PreflightError('repository-identity-mismatch')
  return { help: false, repo: REPOSITORY, output: path.resolve(output) }
}

function gh(args, binary = process.env.GH_BIN || 'gh') {
  try {
    return execFileSync(binary, args, {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      maxBuffer: 1024 * 1024,
      timeout: 30_000,
    })
  } catch {
    throw new PreflightError('github-api-unavailable')
  }
}

function requestJson(endpoint, { paginate = false } = {}) {
  const args = ['api']
  if (paginate) args.push('--paginate', '--slurp')
  args.push('--method', 'GET', '--header', `X-GitHub-Api-Version: ${API_VERSION}`, endpoint)
  const raw = gh(args)
  try {
    return JSON.parse(raw)
  } catch {
    throw new PreflightError(paginate ? 'pagination-incomplete' : 'api-response-invalid')
  }
}

function collectPages(response, collectionKey, { allowEmpty = true } = {}) {
  if (!Array.isArray(response) || response.length === 0 || response.length > 100) {
    throw new PreflightError('pagination-incomplete')
  }
  const total = response[0]?.total_count
  if (!Number.isSafeInteger(total) || total < 0) throw new PreflightError('pagination-incomplete')
  const all = []
  for (const page of response) {
    if (!page || page.total_count !== total || !Array.isArray(page[collectionKey])) {
      throw new PreflightError('pagination-incomplete')
    }
    all.push(...page[collectionKey])
  }
  if ((!allowEmpty && total === 0) || all.length !== total) throw new PreflightError('pagination-incomplete')
  if (new Set(all.map((item) => item?.name)).size !== all.length) throw new PreflightError('pagination-incomplete')
  return all
}

function validateSecretNames(pages) {
  const items = collectPages(pages, 'secrets')
  const names = []
  for (const item of items) {
    if (!item || typeof item.name !== 'string' || !/^[A-Z][A-Z0-9_]*$/.test(item.name)) {
      throw new PreflightError('api-response-invalid')
    }
    names.push(item.name)
  }
  return new Set(names)
}

function validatePolicies(pages) {
  const policies = collectPages(pages, 'branch_policies')
  return policies.length === 1 && policies[0]?.type === 'branch' && policies[0]?.name === 'main'
}

function validMainProtection(data) {
  const checks = data?.required_status_checks
  const contexts = checks?.contexts
  const appChecks = checks?.checks
  const sameExactSet = (items, expected) =>
    Array.isArray(items) && items.length === expected.length &&
    [...items].sort().every((value, index) => value === [...expected].sort()[index])
  const appChecksValid = Array.isArray(appChecks) && appChecks.length === REQUIRED_CONTEXTS.length &&
    appChecks.every((item) => item && item.app_id === PROTECTION_APP_ID && REQUIRED_CONTEXTS.includes(item.context)) &&
    new Set(appChecks.map((item) => item.context)).size === REQUIRED_CONTEXTS.length
  return Boolean(
    data?.required_pull_request_reviews && data.required_pull_request_reviews.required_approving_review_count === 0 &&
    checks?.strict === true && sameExactSet(contexts, REQUIRED_CONTEXTS) && appChecksValid &&
    data?.enforce_admins?.enabled === true && data?.allow_force_pushes?.enabled === false &&
    data?.allow_deletions?.enabled === false
  )
}

function renderReport({ status, checkedAt, reviewer, deploymentPolicy, mainProtection, missingSecrets, findings }) {
  const lines = [
    '# Phase 2 Environment Readiness',
    `status: ${status}`,
    `checked_at: ${checkedAt}`,
    `environment: ${ENVIRONMENT}`,
    `required_reviewer: ${reviewer}`,
    `main_only_deployment_policy: ${deploymentPolicy}`,
    `stable_main_protection: ${mainProtection}`,
    'missing_required_secret_names:',
  ]
  if (missingSecrets.length) lines.push(...missingSecrets.map((name) => `  - ${name}`))
  else lines.push('  - none')
  lines.push('findings:')
  if (findings.length) lines.push(...findings.map((finding) => `  - ${finding}`))
  else lines.push('  - none')
  lines.push('', 'This report proves configuration readiness only; it is not owner authorization or live acceptance.', '')
  return lines.join('\n')
}

function isoNow() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z')
}

async function writeAtomically(output, contents) {
  await mkdir(path.dirname(output), { recursive: true })
  const temp = path.join(path.dirname(output), `.${path.basename(output)}.${randomUUID()}.tmp`)
  let handle
  try {
    handle = await open(temp, 'wx', 0o600)
    await handle.writeFile(contents, 'utf8')
    await handle.sync()
    await handle.close()
    handle = undefined
    await chmod(temp, 0o600)
    await rename(temp, output)
    await chmod(output, 0o600)
  } catch {
    if (handle) await handle.close().catch(() => {})
    await rm(temp, { force: true }).catch(() => {})
    throw new PreflightError('report-write-failed')
  }
}

async function main(args = process.argv.slice(2)) {
  let parsed
  try {
    parsed = parseArgs(args)
  } catch (error) {
    process.stderr.write(error.code === 'usage' ? `${usage}\n` : 'status: ERROR\nfindings:\n  - repository-identity-mismatch\n')
    return 2
  }
  if (parsed.help) {
    process.stdout.write(`${usage}\n`)
    return 0
  }

  let reviewer = 'UNKNOWN'
  let deploymentPolicy = 'UNKNOWN'
  let mainProtection = 'UNKNOWN'
  let missingSecrets = []
  let findings = []
  let status = 'ERROR'
  try {
    const ghBinary = process.env.GH_BIN || 'gh'
    try {
      execFileSync(ghBinary, ['auth', 'status', '--hostname', 'github.com'], {
        stdio: 'ignore',
        timeout: 15_000,
      })
    } catch {
      throw new PreflightError('github-cli-auth-failed')
    }

    const repo = requestJson(`repos/${parsed.repo}`)
    if (repo?.full_name?.toLowerCase() !== REPOSITORY.toLowerCase()) {
      throw new PreflightError('repository-identity-mismatch')
    }

    const environment = requestJson(`repos/${parsed.repo}/environments/${ENVIRONMENT}`)
    const reviewers = Array.isArray(environment?.protection_rules) && environment.protection_rules.some((rule) =>
      rule?.type === 'required_reviewers' && Array.isArray(rule.reviewers) && rule.reviewers.length > 0,
    )
    reviewer = reviewers ? 'PASS' : 'FAIL'

    const branchPolicy = environment?.deployment_branch_policy
    const branchPolicies = validatePolicies(requestJson(
      `repos/${parsed.repo}/environments/${ENVIRONMENT}/deployment-branch-policies?per_page=100`,
      { paginate: true },
    ))
    const mainOnly = branchPolicy?.custom_branch_policies === true && branchPolicy?.protected_branches === false && branchPolicies
    deploymentPolicy = mainOnly ? 'PASS' : 'FAIL'

    const existingSecrets = validateSecretNames(requestJson(
      `repos/${parsed.repo}/environments/${ENVIRONMENT}/secrets?per_page=100`,
      { paginate: true },
    ))
    missingSecrets = REQUIRED_SECRETS.filter((name) => !existingSecrets.has(name))

    mainProtection = validMainProtection(requestJson(`repos/${parsed.repo}/branches/main/protection`)) ? 'PASS' : 'FAIL'

    if (reviewer === 'FAIL') findings.push('required-reviewer-missing')
    if (deploymentPolicy === 'FAIL') findings.push('deployment-policy-not-main-only')
    if (mainProtection === 'FAIL') findings.push('main-protection-mismatch')
    if (missingSecrets.length) findings.push('required-secret-names-missing')
    status = findings.length ? 'BLOCKED' : 'READY'
  } catch (error) {
    const code = FINDINGS.has(error?.code) ? error.code : 'github-api-unavailable'
    findings = [code]
    status = 'ERROR'
  }

  const report = renderReport({
    status,
    checkedAt: isoNow(),
    reviewer,
    deploymentPolicy,
    mainProtection,
    missingSecrets,
    findings,
  })
  try {
    await writeAtomically(parsed.output, report)
  } catch {
    process.stdout.write('status: ERROR\nfindings:\n  - report-write-failed\n')
    return 2
  }
  process.stdout.write(report)
  return status === 'READY' ? 0 : status === 'BLOCKED' ? 1 : 2
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().then((code) => { process.exitCode = code })
}

export { REQUIRED_SECRETS, REQUIRED_CONTEXTS, renderReport, validMainProtection }
