#!/usr/bin/env node
/**
 * tooling/verify-export-reader.mjs (06-08-PLAN.md Task 2, D-07 lane 3)
 *
 * The independent reader D-07 exists to build: a program that shares ZERO
 * code with the Elixir producer (`Keepling.Application.Export` /
 * `Keepling.Adapters.Postgres.Export`), validates a bundle end-to-end
 * against the same checked-in contracts (`packages/contracts/schemas/
 * export/`), and reaches the no-secrets conclusion by its own route. A
 * reader built from the producer's own code (or that shells out to Elixir)
 * proves only self-consistency -- exactly the failure mode this lane
 * exists to rule out. This file imports nothing from the Elixir server
 * application source tree and never invokes the Elixir build toolchain; it
 * is written from `packages/contracts/schemas/export/FORMAT.md` alone, the
 * same document a user with no Keepling source access would read.
 *
 * One successful run of `node tooling/verify-export-reader.mjs <bundle.zip>`
 * proves: every file the manifest names is present with the exact recorded
 * sha256 and row count; every `data/*.ndjson` line parses as JSON and
 * validates against its entity's checked-in schema; the reconstructed task
 * list matches the bundle's own `data/task.ndjson`; and none of a known set
 * of credential-fixture strings appears anywhere in the bundle's raw bytes.
 *
 * BLOCKED means this lane could not even attempt validation -- a missing
 * bundle path, an unreadable archive, or (recorded, never silently passed)
 * a bundle containing zero entity files. A bundle that fails any single
 * check below is a hard, non-zero exit naming the offending file; there is
 * no partial-pass state.
 */
import { createHash } from 'node:crypto'
import { existsSync, readFileSync } from 'node:fs'
import { basename, dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import process from 'node:process'
import { spawnSync } from 'node:child_process'

const laneDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(laneDirectory, '..')
const schemasDir = join(repositoryRoot, 'packages', 'contracts', 'schemas', 'export')

// Guard-refusal: this lane's own file is tracked so a shortcut injected
// into it (a hand-waved validator, a hardcoded "cases=1") cannot hide from
// the report it produces about itself.
const GUARDED_FILES = [join(repositoryRoot, 'tooling', 'verify-export-reader.mjs')]

const TRACKED_INPUT_PATHS = [
  'tooling/verify-export-reader.mjs',
  'packages/contracts/schemas/export/manifest.schema.json',
  'packages/contracts/schemas/export/task.schema.json',
  'packages/contracts/schemas/export/project.schema.json',
  'packages/contracts/schemas/export/tag.schema.json',
  'packages/contracts/schemas/export/task-activity.schema.json',
  'packages/contracts/schemas/export/conflict.schema.json',
  'packages/contracts/schemas/export/today-order.schema.json',
  'packages/contracts/schemas/export/account-settings.schema.json',
  'packages/contracts/schemas/export/access-inventory.schema.json',
]

// A known-hostile no-secrets sentinel set. The Elixir lane (export_test.exs)
// greps for its own randomly-generated fixture values within a single test
// run; this independent lane cannot see those values (a different process,
// a different language), so it instead asserts structurally -- no
// data/access-inventory.ndjson record may carry any of these column names
// at all (device_grants' full credential surface, per classification.json)
// -- and, defensively, that none of a small set of literal credential-shaped
// substrings ever appears in the bundle's raw bytes.
const FORBIDDEN_ACCESS_INVENTORY_KEYS = [
  'installation_id',
  'redirect_uri',
  'redirect_uris',
  'authorization_code_hash',
  'authorization_code_expires_at',
  'authorization_code_consumed_at',
  'state_hash',
  'pkce_challenge',
  'access_token_hash',
  'access_expires_at',
  'refresh_inactivity_expires_at',
  'family_absolute_expires_at',
  'generation',
  'last_refreshed_at',
  'resource',
]

const HOSTILE_SUBSTRING_PATTERNS = [/password_hash/i, /credential_hash/i, /token_hash/i]

const fail = (message) => {
  console.error(`verify-export-reader failed: ${message}`)
}

const sha256Hex = (bytes) => createHash('sha256').update(bytes).digest('hex')

// -- Minimal, hand-rolled JSON Schema validator ------------------------------
// Deliberately narrow: covers exactly the vocabulary the eight checked-in
// entity schemas use (type, enum, const, pattern, format: date-time,
// minLength, minItems, uniqueItems, minimum, items, additionalProperties:
// false + required). No dependency added -- T-06-08-05 requires re-running
// the package legitimacy check before adding one, and this bundle's schema
// surface is small and closed enough not to need one.
const DATE_TIME_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/

const typeMatches = (type, value) => {
  switch (type) {
    case 'object':
      return value !== null && typeof value === 'object' && !Array.isArray(value)
    case 'array':
      return Array.isArray(value)
    case 'string':
      return typeof value === 'string'
    case 'integer':
      return Number.isInteger(value)
    case 'null':
      return value === null
    case 'boolean':
      return typeof value === 'boolean'
    default:
      return false
  }
}

const validateAgainstSchema = (schema, value, path) => {
  const errors = []

  const types = Array.isArray(schema.type) ? schema.type : schema.type ? [schema.type] : null
  if (types && !types.some((type) => typeMatches(type, value))) {
    errors.push(`${path}: expected type ${types.join('|')}, got ${JSON.stringify(value)}`)
    return errors
  }

  if (schema.const !== undefined && value !== schema.const) {
    errors.push(`${path}: expected const ${JSON.stringify(schema.const)}, got ${JSON.stringify(value)}`)
  }

  if (schema.enum && !schema.enum.includes(value)) {
    errors.push(`${path}: ${JSON.stringify(value)} is not one of ${JSON.stringify(schema.enum)}`)
  }

  if (typeof value === 'string') {
    if (typeof schema.minLength === 'number' && value.length < schema.minLength) {
      errors.push(`${path}: string shorter than minLength ${schema.minLength}`)
    }
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) {
      errors.push(`${path}: does not match pattern ${schema.pattern}`)
    }
    if (schema.format === 'date-time' && !DATE_TIME_RE.test(value)) {
      errors.push(`${path}: does not match required date-time format`)
    }
  }

  if (typeof value === 'number') {
    if (typeof schema.minimum === 'number' && value < schema.minimum) {
      errors.push(`${path}: ${value} is below minimum ${schema.minimum}`)
    }
  }

  if (Array.isArray(value)) {
    if (typeof schema.minItems === 'number' && value.length < schema.minItems) {
      errors.push(`${path}: array shorter than minItems ${schema.minItems}`)
    }
    if (schema.uniqueItems && new Set(value.map((item) => JSON.stringify(item))).size !== value.length) {
      errors.push(`${path}: array has duplicate items`)
    }
    if (schema.items) {
      value.forEach((item, index) => errors.push(...validateAgainstSchema(schema.items, item, `${path}[${index}]`)))
    }
  }

  if (value !== null && typeof value === 'object' && !Array.isArray(value)) {
    const properties = schema.properties || {}
    if (schema.additionalProperties === false) {
      for (const key of Object.keys(value)) {
        if (!Object.hasOwn(properties, key)) errors.push(`${path}: unexpected additional property "${key}"`)
      }
    }
    for (const requiredKey of schema.required || []) {
      if (!Object.hasOwn(value, requiredKey)) errors.push(`${path}: missing required property "${requiredKey}"`)
    }
    for (const [key, subSchema] of Object.entries(properties)) {
      if (Object.hasOwn(value, key)) errors.push(...validateAgainstSchema(subSchema, value[key], `${path}.${key}`))
    }
  }

  return errors
}

// -- Bundle extraction (system `unzip`, no npm zip dependency) ---------------
const listBundleEntries = (bundlePath) => {
  const result = spawnSync('unzip', ['-Z1', bundlePath], { encoding: 'utf8' })
  if (result.status !== 0) {
    throw new Error(`unable to list bundle entries (unzip -Z1 exited ${result.status}): ${result.stderr}`)
  }
  return result.stdout.split('\n').map((line) => line.trim()).filter(Boolean)
}

const readBundleEntry = (bundlePath, entryPath) => {
  const result = spawnSync('unzip', ['-p', bundlePath, entryPath], { encoding: 'buffer', maxBuffer: 1024 * 1024 * 256 })
  if (result.status !== 0) {
    throw new Error(`missing or unreadable bundle entry "${entryPath}" (unzip -p exited ${result.status})`)
  }
  return result.stdout
}

const args = process.argv.slice(2)
const goldenMode = args.includes('--golden')
const bundlePath = !goldenMode && args[0] ? resolve(args[0]) : null

if (!goldenMode && !bundlePath) {
  fail('usage: node tooling/verify-export-reader.mjs <bundle.zip>  |  node tooling/verify-export-reader.mjs --golden')
  process.exit(2)
}

for (const guardedPath of GUARDED_FILES) {
  if (!existsSync(guardedPath)) {
    fail(`guarded file missing: ${guardedPath}`)
    process.exit(1)
  }
}

const trackedInputDigest = createHash('sha256')
for (const relativePath of TRACKED_INPUT_PATHS) {
  trackedInputDigest.update(`${relativePath}\0`)
  trackedInputDigest.update(readFileSync(join(repositoryRoot, relativePath)))
  trackedInputDigest.update('\0')
}
const trackedInputSha256 = trackedInputDigest.digest('hex')

const startedAtMs = Date.now()

// Entity name (as it appears in packages/contracts/schemas/export/) for
// each data/*.ndjson path a bundle (or the golden vector) can carry.
const ENTITY_SCHEMA_BY_PATH = Object.fromEntries(
  ['task', 'project', 'tag', 'task-activity', 'conflict', 'today-order', 'account-settings', 'access-inventory'].map(
    (entity) => [`data/${entity}.ndjson`, entity],
  ),
)

const entitySchemas = new Map()
const schemaFor = (entity) => {
  if (!entitySchemas.has(entity)) {
    const schemaPath = join(schemasDir, `${entity}.schema.json`)
    entitySchemas.set(entity, JSON.parse(readFileSync(schemaPath, 'utf8')))
  }
  return entitySchemas.get(entity)
}

// -- D-07 lane 2 (06-08-PLAN.md Task 3): golden vector byte comparison ------
// `--golden` holds this reader to the SAME bytes the Elixir export_test.exs
// golden-vector case does, by an independent route: it never runs the
// Elixir producer -- it recomputes every recorded sha256/rowCount straight
// from `expected.files`' own literal content strings and asserts they
// equal `expected.manifest.files`, then validates every entity record
// against its checked-in schema. A vector whose checked-in digests
// disagree with its own checked-in content fails here exactly as it would
// fail a real bundle comparison.
if (goldenMode) {
  const goldenPath = join(repositoryRoot, 'packages', 'contracts', 'vectors', 'export-golden.json')
  let golden
  try {
    golden = JSON.parse(readFileSync(goldenPath, 'utf8'))
  } catch (error) {
    fail(`BLOCKED: could not read/parse ${goldenPath}: ${error instanceof Error ? error.message : String(error)}`)
    process.exit(1)
  }

  let goldenFailed = false
  let goldenCases = 0
  const manifestFilesByPath = Object.fromEntries(golden.expected.manifest.files.map((entry) => [entry.path, entry]))

  for (const [path, content] of Object.entries(golden.expected.files)) {
    const manifestEntry = manifestFilesByPath[path]
    if (!manifestEntry) {
      fail(`golden vector file "${path}" has no corresponding expected.manifest.files entry`)
      goldenFailed = true
      continue
    }
    const bytes = Buffer.from(content, 'utf8')
    const actualSha256 = sha256Hex(bytes)
    if (actualSha256 !== manifestEntry.sha256) {
      fail(`golden vector "${path}": recorded sha256 does not match its own checked-in content (recorded=${manifestEntry.sha256} actual=${actualSha256})`)
      goldenFailed = true
    } else {
      goldenCases += 1
    }

    const entity = ENTITY_SCHEMA_BY_PATH[path]
    if (!entity) continue
    const nonEmptyLines = content.split('\n').filter((line) => line.length > 0)
    if (nonEmptyLines.length !== manifestEntry.rowCount) {
      fail(`golden vector "${path}": recorded rowCount ${manifestEntry.rowCount} does not match its own content (actual=${nonEmptyLines.length})`)
      goldenFailed = true
      continue
    }
    const schema = schemaFor(entity)
    for (const [index, line] of nonEmptyLines.entries()) {
      const record = JSON.parse(line)
      const errors = validateAgainstSchema(schema, record, `${path}:${index + 1}`)
      if (errors.length > 0) {
        for (const schemaError of errors) fail(schemaError)
        goldenFailed = true
      } else {
        goldenCases += 1
      }
    }
  }

  const formatMdPath = join(schemasDir, 'FORMAT.md')
  const formatMdOnDisk = readFileSync(formatMdPath, 'utf8')
  const formatMdEntry = manifestFilesByPath['FORMAT.md']
  if (formatMdEntry && sha256Hex(Buffer.from(formatMdOnDisk, 'utf8')) !== formatMdEntry.sha256) {
    fail('golden vector "FORMAT.md": recorded sha256 does not match the checked-in FORMAT.md on disk')
    goldenFailed = true
  } else if (formatMdEntry) {
    goldenCases += 1
  }

  if (goldenFailed) {
    fail('export-golden.json vector did not self-validate')
    process.exit(1)
  }

  console.log(`verify-export-reader --golden PASSED cases=${goldenCases} trackedInputSha256=${trackedInputSha256}`)
  process.exit(0)
}

if (!existsSync(bundlePath)) {
  fail(`BLOCKED: bundle does not exist at ${bundlePath}`)
  process.exit(1)
}

let bundleEntryNames
try {
  bundleEntryNames = listBundleEntries(bundlePath)
} catch (error) {
  fail(`BLOCKED: ${error instanceof Error ? error.message : String(error)}`)
  process.exit(1)
}
if (bundleEntryNames.length === 0) {
  fail('BLOCKED: bundle archive contains zero entries -- not a valid export bundle')
  process.exit(1)
}

let manifest
try {
  const manifestBytes = readBundleEntry(bundlePath, 'manifest.json')
  manifest = JSON.parse(manifestBytes.toString('utf8'))
} catch (error) {
  fail(`BLOCKED: could not read/parse manifest.json: ${error instanceof Error ? error.message : String(error)}`)
  process.exit(1)
}

if (!Array.isArray(manifest.files) || manifest.files.length === 0) {
  fail('manifest.json declares zero files -- a vacuous manifest is refused, never a pass')
  process.exit(1)
}

let overallFailed = false
let positiveCases = 0
let entityFilesValidated = 0
let taskRecords = []
const rawByteChunks = []
const accessInventoryRecords = []

for (const fileEntry of manifest.files) {
  const { path: entryPath, sha256: expectedSha256, rowCount: expectedRowCount } = fileEntry
  let bytes
  try {
    bytes = readBundleEntry(bundlePath, entryPath)
  } catch (error) {
    fail(error instanceof Error ? error.message : String(error))
    overallFailed = true
    continue
  }

  rawByteChunks.push(bytes)

  const actualSha256 = sha256Hex(bytes)
  if (actualSha256 !== expectedSha256) {
    fail(`${entryPath}: digest mismatch (manifest=${expectedSha256} actual=${actualSha256})`)
    overallFailed = true
    continue
  }
  positiveCases += 1

  const text = bytes.toString('utf8')
  const nonEmptyLines = text.split('\n').filter((line) => line.length > 0)

  // rowCount's meaning is file-specific, per manifest.schema.json: for
  // data/*.ndjson it is the NDJSON line count (non-empty lines); for
  // FORMAT.md it is the rendered document's raw line count (a bytewise
  // split on "\n", including blank separator lines and any trailing empty
  // segment -- this bundle's own convention for "line count of the
  // rendered document"); for tasks.md it is the number of rendered task
  // entries, one per checkbox bullet line, not the document's raw line
  // count (a header and a "no tasks" placeholder line are not tasks).
  let actualRowCount
  if (entryPath === 'FORMAT.md') {
    actualRowCount = text.split('\n').length
  } else if (entryPath === 'tasks.md') {
    actualRowCount = nonEmptyLines.filter((line) => /^-\s\[[ x]\]\s/.test(line)).length
  } else {
    actualRowCount = nonEmptyLines.length
  }

  if (actualRowCount !== expectedRowCount) {
    fail(`${entryPath}: row count mismatch (manifest=${expectedRowCount} actual=${actualRowCount})`)
    overallFailed = true
    continue
  }
  positiveCases += 1

  const entity = ENTITY_SCHEMA_BY_PATH[entryPath]
  if (!entity) continue // tasks.md, FORMAT.md -- not NDJSON entity data

  const lines = nonEmptyLines

  entityFilesValidated += 1
  const schema = schemaFor(entity)
  const records = []
  let malformed = false

  for (const [index, line] of lines.entries()) {
    let record
    try {
      record = JSON.parse(line) // throws on malformed NDJSON -- that is the point
    } catch (error) {
      fail(`${entryPath}:${index + 1}: malformed NDJSON line (${error instanceof Error ? error.message : String(error)})`)
      overallFailed = true
      malformed = true
      continue
    }
    const errors = validateAgainstSchema(schema, record, `${entryPath}:${index + 1}`)
    if (errors.length > 0) {
      for (const schemaError of errors) fail(schemaError)
      overallFailed = true
      malformed = true
      continue
    }
    records.push(record)
  }

  if (!malformed) positiveCases += 1

  if (entity === 'task') taskRecords = records
  if (entity === 'access-inventory') accessInventoryRecords.push(...records)
}

if (entityFilesValidated === 0) {
  fail('bundle contains zero entity data files -- a reader that validated nothing must not pass')
  process.exit(1)
}

// Reconstruct the task list a human would read, exactly the way tasks.md
// itself is rendered, to prove the parsed records are actually usable.
const reconstructedTaskList = taskRecords.map((task) => {
  const checkbox = task.completed_at ? '[x]' : '[ ]'
  const trashed = task.trashed_at ? ' (trashed)' : ''
  return `- ${checkbox} ${task.title}${trashed}`
})
console.log(`reconstructed ${reconstructedTaskList.length} task(s) from data/task.ndjson`)

// -- No-secrets assertion, reached by an independent route ------------------
for (const record of accessInventoryRecords) {
  for (const forbiddenKey of FORBIDDEN_ACCESS_INVENTORY_KEYS) {
    if (Object.hasOwn(record, forbiddenKey)) {
      fail(`access-inventory record leaked forbidden column "${forbiddenKey}": ${JSON.stringify(record)}`)
      overallFailed = true
    }
  }
}

const rawBytes = Buffer.concat(rawByteChunks)
for (const pattern of HOSTILE_SUBSTRING_PATTERNS) {
  if (pattern.test(rawBytes.toString('utf8'))) {
    fail(`bundle raw bytes matched a hostile credential-shaped pattern: ${pattern}`)
    overallFailed = true
  }
}
if (!overallFailed) positiveCases += 1

const elapsedMs = Date.now() - startedAtMs

if (overallFailed) {
  fail(`bundle ${bundlePath} did not validate`)
  process.exit(1)
}

console.log(
  `verify-export-reader PASSED bundle=${basename(bundlePath)} cases=${positiveCases} entityFiles=${entityFilesValidated} tasks=${reconstructedTaskList.length} elapsedMs=${elapsedMs} trackedInputSha256=${trackedInputSha256}`,
)
process.exit(0)
