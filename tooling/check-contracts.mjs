import { spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { accessSync, constants, readFileSync } from 'node:fs'
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
const syncSchema = resolve(
  repositoryRoot,
  'packages/contracts/schemas/sync-state-machine.schema.json',
)
const syncVectors = resolve(
  repositoryRoot,
  'packages/contracts/vectors/sync.json',
)

for (const path of [source, generated, syncSchema, syncVectors]) {
  try {
    accessSync(path, constants.R_OK)
  } catch {
    process.stderr.write(`Contract drift check failed: missing readable file ${path}\n`)
    process.exit(1)
  }
}

const fail = (message) => {
  throw new Error(`Sync contract validation failed: ${message}`)
}

const exactKeys = (value, allowed, context) => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    fail(`${context} must be an object`)
  }

  const unexpected = Object.keys(value).filter((key) => !allowed.includes(key))
  if (unexpected.length > 0) fail(`${context} has unknown fields: ${unexpected.join(', ')}`)
}

const nonEmptyString = (value, context) => {
  if (typeof value !== 'string' || value.length === 0) fail(`${context} must be a non-empty string`)
}

const dateTime = (value, context) => {
  nonEmptyString(value, context)
  if (Number.isNaN(Date.parse(value))) fail(`${context} must be a fixed ISO-8601 clock`)
}

const uniqueStrings = (values, context, { nonEmpty = false, sorted = false } = {}) => {
  if (!Array.isArray(values) || (nonEmpty && values.length === 0)) fail(`${context} must be an array`)
  values.forEach((value, index) => nonEmptyString(value, `${context}[${index}]`))
  if (new Set(values).size !== values.length) fail(`${context} must contain unique values`)
  if (sorted && values.some((value, index) => value !== [...values].sort()[index])) {
    fail(`${context} must use canonical bytewise ordering`)
  }
}

const validateSnapshot = (snapshot, context) => {
  exactKeys(snapshot, Object.keys(snapshot ?? {}), context)
  nonEmptyString(snapshot.id, `${context}.id`)
  if (!Number.isInteger(snapshot.revision) || snapshot.revision < 0) {
    fail(`${context}.revision must be a non-negative integer`)
  }
}

const validateMutation = (mutation, context) => {
  exactKeys(
    mutation,
    ['mutation_id', 'fingerprint', 'command_bytes', 'resource_keys', 'dependencies', 'accepted_at', 'effect'],
    context,
  )
  nonEmptyString(mutation.mutation_id, `${context}.mutation_id`)
  if (!/^[0-9a-f]{64}$/.test(mutation.fingerprint ?? '')) fail(`${context}.fingerprint must be lowercase SHA-256`)
  nonEmptyString(mutation.command_bytes, `${context}.command_bytes`)
  const digest = createHash('sha256').update(mutation.command_bytes).digest('hex')
  if (digest !== mutation.fingerprint) fail(`${context}.fingerprint does not match immutable command bytes`)

  let command
  try {
    command = JSON.parse(mutation.command_bytes)
  } catch {
    fail(`${context}.command_bytes must contain closed JSON`)
  }
  if (command.mutation_id !== mutation.mutation_id) fail(`${context}.command_bytes changed mutation identity`)

  uniqueStrings(mutation.resource_keys, `${context}.resource_keys`, { nonEmpty: true, sorted: true })
  uniqueStrings(mutation.dependencies, `${context}.dependencies`)
  dateTime(mutation.accepted_at, `${context}.accepted_at`)
  exactKeys(mutation.effect, ['entity_id', 'snapshot'], `${context}.effect`)
  nonEmptyString(mutation.effect.entity_id, `${context}.effect.entity_id`)
  validateSnapshot(mutation.effect.snapshot, `${context}.effect.snapshot`)
}

const validateAcknowledgement = (acknowledgement, context) => {
  exactKeys(acknowledgement, ['mutation_id', 'fingerprint', 'outcome', 'snapshot'], context)
  nonEmptyString(acknowledgement.mutation_id, `${context}.mutation_id`)
  if (!/^[0-9a-f]{64}$/.test(acknowledgement.fingerprint ?? '')) fail(`${context}.fingerprint must be lowercase SHA-256`)
  if (!['accepted', 'already_satisfied', 'rejected', 'stale', 'conflict'].includes(acknowledgement.outcome)) {
    fail(`${context}.outcome is unknown`)
  }
  validateSnapshot(acknowledgement.snapshot, `${context}.snapshot`)
}

const validateAction = (action, context) => {
  nonEmptyString(action?.type, `${context}.type`)

  switch (action.type) {
    case 'local_accept':
      exactKeys(action, ['type', 'mutation'], context)
      validateMutation(action.mutation, `${context}.mutation`)
      break
    case 'pull':
      exactKeys(action, ['type', 'page'], context)
      exactKeys(action.page, ['cursor', 'changes'], `${context}.page`)
      nonEmptyString(action.page.cursor, `${context}.page.cursor`)
      if (!Array.isArray(action.page.changes) || action.page.changes.length > 50) fail(`${context}.page.changes must be bounded`)
      action.page.changes.forEach((change, index) => {
        exactKeys(change, ['entity_id', 'snapshot'], `${context}.page.changes[${index}]`)
        nonEmptyString(change.entity_id, `${context}.page.changes[${index}].entity_id`)
        validateSnapshot(change.snapshot, `${context}.page.changes[${index}].snapshot`)
      })
      break
    case 'ready_pushes':
    case 'relaunch':
      exactKeys(action, ['type'], context)
      break
    case 'acknowledge':
      exactKeys(action, ['type', 'acknowledgement'], context)
      validateAcknowledgement(action.acknowledgement, `${context}.acknowledgement`)
      break
    case 'fence':
      exactKeys(action, ['type', 'reason'], context)
      if (action.reason !== null) nonEmptyString(action.reason, `${context}.reason`)
      break
    default:
      fail(`${context}.type is unknown: ${action.type}`)
  }
}

const validateSyncVectors = (vectors) => {
  exactKeys(vectors, ['$schema', 'version', 'fixed_clock', 'cases'], 'sync vectors')
  if (vectors.$schema !== '../schemas/sync-state-machine.schema.json') fail('vectors must bind the checked-in schema')
  if (vectors.version !== 1) fail('version must be 1')
  dateTime(vectors.fixed_clock, 'fixed_clock')
  if (!Array.isArray(vectors.cases) || vectors.cases.length === 0) fail('zero synchronization cases executed')

  const names = new Set()
  vectors.cases.forEach((vector, caseIndex) => {
    const context = `cases[${caseIndex}]`
    exactKeys(vector, ['name', 'actions', 'expect'], context)
    nonEmptyString(vector.name, `${context}.name`)
    if (names.has(vector.name)) fail(`duplicate case name: ${vector.name}`)
    names.add(vector.name)
    if (!Array.isArray(vector.actions) || vector.actions.length === 0) fail(`${context}.actions must not be empty`)
    vector.actions.forEach((action, actionIndex) => validateAction(action, `${context}.actions[${actionIndex}]`))
    exactKeys(vector.expect, ['cursor', 'outbox', 'ready_pushes'], `${context}.expect`)
    if (vector.expect.cursor !== null) nonEmptyString(vector.expect.cursor, `${context}.expect.cursor`)
    uniqueStrings(vector.expect.outbox, `${context}.expect.outbox`)
    uniqueStrings(vector.expect.ready_pushes, `${context}.expect.ready_pushes`)
  })

  return vectors.cases.length
}

const schema = JSON.parse(readFileSync(syncSchema, 'utf8'))
if (schema.$schema !== 'https://json-schema.org/draft/2020-12/schema' || !schema.$defs?.case) {
  fail('schema must be a closed Draft 2020-12 state-machine contract')
}

const vectors = JSON.parse(readFileSync(syncVectors, 'utf8'))
const executedSyncCases = validateSyncVectors(vectors)

const malformed = structuredClone(vectors)
malformed.cases[0].actions[0].type = 'unknown_action'
try {
  validateSyncVectors(malformed)
  fail('known malformed synchronization fixture was accepted')
} catch (error) {
  if (!String(error.message).includes('type is unknown')) throw error
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

process.stdout.write(
  `Contract drift check passed: OpenAPI agrees and ${executedSyncCases} synchronization vector cases validated\n`,
)
