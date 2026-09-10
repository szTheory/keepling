import { spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { accessSync, constants, readdirSync, readFileSync } from 'node:fs'
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
const compatibilityVectors = resolve(
  repositoryRoot,
  'packages/contracts/vectors/compatibility.json',
)
const redactionVectors = resolve(
  repositoryRoot,
  'packages/contracts/vectors/redaction.json',
)

for (const path of [source, generated, syncSchema, syncVectors, compatibilityVectors, redactionVectors]) {
  try {
    accessSync(path, constants.R_OK)
  } catch {
    process.stderr.write(`Contract drift check failed: missing readable file ${path}\n`)
    process.exit(1)
  }
}

const fail = (message) => {
  throw new Error(`Contract validation failed: ${message}`)
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

const integerRange = (range, context) => {
  exactKeys(range, ['minimum', 'maximum'], context)
  if (!Number.isInteger(range.minimum) || !Number.isInteger(range.maximum) || range.minimum < 1 || range.minimum > range.maximum) {
    fail(`${context} must be an increasing positive integer range`)
  }
}

const compatibilityResult = (result, context) => {
  exactKeys(
    result,
    ['compatibility_state', 'selected_protocol_train', 'recovery_code', 'retryable', 'pending_intent'],
    context,
  )
  if (!['supported', 'deprecated_but_safe', 'unsupported'].includes(result.compatibility_state)) {
    fail(`${context}.compatibility_state is unknown`)
  }
  if (!['continue', 'client_update_available', 'client_upgrade_required', 'server_upgrade_required'].includes(result.recovery_code)) {
    fail(`${context}.recovery_code is unknown`)
  }
  if (result.retryable !== false || result.pending_intent !== 'preserved_locally') {
    fail(`${context} must preserve local intent without automatic retry`)
  }
}

const compatibilityPolicy = (policy, context) => {
  exactKeys(
    policy,
    [
      'now', 'server_release', 'tested_oci_digest', 'distribution', 'current_protocol_train',
      'previous_protocol_train', 'previous_superseded_at', 'deprecation_deadline', 'emergency_override',
      'supported_protocols', 'schema_range', 'platform_minimum_builds', 'update_location',
    ],
    context,
  )
  dateTime(policy.now, `${context}.now`)
  nonEmptyString(policy.server_release, `${context}.server_release`)
  if (!/^sha256:[0-9a-f]{64}$/.test(policy.tested_oci_digest ?? '')) fail(`${context}.tested_oci_digest must be exact`)
  if (!['dogfood', 'distributed'].includes(policy.distribution)) fail(`${context}.distribution is unknown`)
  if (!Number.isInteger(policy.current_protocol_train) || policy.current_protocol_train < 1) fail(`${context}.current_protocol_train is invalid`)
  exactKeys(policy.supported_protocols, ['read', 'write', 'sync'], `${context}.supported_protocols`)
  for (const kind of ['read', 'write', 'sync']) integerRange(policy.supported_protocols[kind], `${context}.supported_protocols.${kind}`)
  integerRange(policy.schema_range, `${context}.schema_range`)
  exactKeys(policy.platform_minimum_builds, ['electron', 'iphone'], `${context}.platform_minimum_builds`)
  if (!Number.isInteger(policy.platform_minimum_builds.electron) || !Number.isInteger(policy.platform_minimum_builds.iphone)) {
    fail(`${context}.platform_minimum_builds must be integers`)
  }
  nonEmptyString(policy.update_location, `${context}.update_location`)
}

const validateCompatibilityVectors = (vectors) => {
  exactKeys(vectors, ['version', 'fixed_clock', 'codec_fixtures', 'artifacts', 'matrix', 'cases'], 'compatibility vectors')
  if (vectors.version !== 1) fail('compatibility version must be 1')
  dateTime(vectors.fixed_clock, 'compatibility fixed_clock')

  if (!Array.isArray(vectors.cases) || vectors.cases.length === 0) fail('zero compatibility negotiation cases executed')
  const caseNames = new Set()
  vectors.cases.forEach((vector, index) => {
    const context = `compatibility.cases[${index}]`
    exactKeys(vector, ['name', 'policy', 'claims', 'expect'], context)
    nonEmptyString(vector.name, `${context}.name`)
    if (caseNames.has(vector.name)) fail(`duplicate compatibility case name: ${vector.name}`)
    caseNames.add(vector.name)
    compatibilityPolicy(vector.policy, `${context}.policy`)
    exactKeys(vector.claims, ['minimum_protocol_train', 'maximum_protocol_train'], `${context}.claims`)
    if (!Number.isInteger(vector.claims.minimum_protocol_train) ||
        !Number.isInteger(vector.claims.maximum_protocol_train) ||
        vector.claims.minimum_protocol_train > vector.claims.maximum_protocol_train) {
      fail(`${context}.claims must be an increasing integer range`)
    }
    compatibilityResult(vector.expect, `${context}.expect`)
  })

  if (!Array.isArray(vectors.codec_fixtures) || vectors.codec_fixtures.length !== 2) {
    fail('current and previous codec fixtures are both required')
  }
  const fixtureTrains = []
  vectors.codec_fixtures.forEach((fixture, index) => {
    const context = `compatibility.codec_fixtures[${index}]`
    exactKeys(fixture, ['name', 'protocol_train', 'cursor_codec', 'receipt_codec', 'receipt', 'generated_response'], context)
    nonEmptyString(fixture.name, `${context}.name`)
    if (!Number.isInteger(fixture.protocol_train)) fail(`${context}.protocol_train is invalid`)
    if (fixture.cursor_codec !== 1 || fixture.receipt_codec !== 1) fail(`${context} uses an unsupported retained codec`)
    const receipt = JSON.parse(fixture.receipt)
    if (receipt.protocol_train !== fixture.protocol_train || receipt.outcome !== 'accepted') fail(`${context}.receipt does not match its train`)
    compatibilityResult(fixture.generated_response, `${context}.generated_response`)
    fixtureTrains.push(fixture.protocol_train)
  })
  if (fixtureTrains.join(',') !== '1,2') fail('codec fixtures must retain previous train 1 and current train 2')

  exactKeys(vectors.artifacts, ['current', 'previous'], 'compatibility.artifacts')
  for (const [name, artifact] of Object.entries(vectors.artifacts)) {
    const context = `compatibility.artifacts.${name}`
    exactKeys(artifact, ['tested_oci_digest', 'schema_range', 'protocol_range'], context)
    if (!/^sha256:[0-9a-f]{64}$/.test(artifact.tested_oci_digest ?? '')) fail(`${context}.tested_oci_digest must be exact`)
    integerRange(artifact.schema_range, `${context}.schema_range`)
    integerRange(artifact.protocol_range, `${context}.protocol_range`)
  }

  exactKeys(vectors.matrix, ['lanes', 'known_bad'], 'compatibility.matrix')
  if (!Array.isArray(vectors.matrix.lanes) || vectors.matrix.lanes.length === 0) fail('zero compatibility matrix lanes executed')
  const laneInputs = []
  vectors.matrix.lanes.forEach((lane, index) => {
    const context = `compatibility.matrix.lanes[${index}]`
    exactKeys(
      lane,
      ['name', 'client_range', 'server_case', 'artifact', 'target', 'expected_negotiation_code', 'expected_artifact_code', 'case_count'],
      context,
    )
    nonEmptyString(lane.name, `${context}.name`)
    if (!caseNames.has(lane.server_case)) fail(`${context}.server_case is unknown`)
    if (!Object.hasOwn(vectors.artifacts, lane.artifact)) fail(`${context}.artifact is unknown`)
    if (!Number.isInteger(lane.case_count) || lane.case_count <= 0) fail(`${context} executed zero cases`)
    exactKeys(lane.client_range, ['minimum_protocol_train', 'maximum_protocol_train'], `${context}.client_range`)
    exactKeys(lane.target, ['schema', 'protocol_train'], `${context}.target`)
    if (!Number.isInteger(lane.target.schema) || !Number.isInteger(lane.target.protocol_train)) fail(`${context}.target inputs must be integers`)
    laneInputs.push(`${lane.name}[digest=${vectors.artifacts[lane.artifact].tested_oci_digest},schema=${lane.target.schema},train=${lane.target.protocol_train},cases=${lane.case_count}]`)
  })

  const knownBad = vectors.matrix.known_bad
  exactKeys(knownBad, ['name', 'artifact', 'target', 'expected_artifact_code'], 'compatibility.matrix.known_bad')
  if (knownBad.expected_artifact_code !== 'rollback_schema_incompatible') fail('known-bad rollback must fail with rollback_schema_incompatible')
  const badArtifact = vectors.artifacts[knownBad.artifact]
  if (!badArtifact || knownBad.target.schema <= badArtifact.schema_range.maximum) fail('known-bad rollback pair is not actually incompatible')

  return { cases: vectors.cases.length, codecs: vectors.codec_fixtures.length, lanes: vectors.matrix.lanes.length, laneInputs }
}

const validateNativeNamespaceContract = (sourceText, generatedText) => {
  for (const field of ['account_subject', 'generation', 'issuer', 'origin', 'server_instance']) {
    if (!sourceText.includes(`        ${field}:`)) fail(`native namespace is missing ${field}`)
    if (!generatedText.includes(`readonly ${field}:`)) fail(`generated native namespace is missing ${field}`)
  }
  for (const requestName of ['NativeAuthorizationCodeExchangeRequest', 'NativeRefreshRequest']) {
    const requestStart = sourceText.indexOf(`    ${requestName}:`)
    const requestEnd = sourceText.indexOf('\n    ', requestStart + 5)
    if (sourceText.slice(requestStart, requestEnd).includes('namespace')) {
      fail(`${requestName} must not accept namespace authority`)
    }
  }
}

const exactStateSets = {
  mutation: ['local_saved', 'checking', 'accepted', 'rejected', 'conflict', 'authentication_required', 'quarantined'],
  synchronization: ['starting', 'catching_up', 'ready', 'stale_last_good', 'retryable_failure'],
  compatibility: ['supported', 'deprecated_but_safe', 'unsupported'],
  recovery: ['backup_unverified', 'restore_in_progress', 'restore_verified', 'restore_failed'],
}

const validateRedactionVectors = (vectors) => {
  exactKeys(
    vectors,
    ['version', 'covered_decisions', 'states', 'state_facts', 'presentation', 'technical_details', 'diagnostic_examples', 'hostile_sentinels'],
    'redaction vectors',
  )
  if (vectors.version !== 1) fail('redaction version must be 1')
  exactKeys(vectors.states, Object.keys(exactStateSets), 'redaction states')
  for (const [kind, expected] of Object.entries(exactStateSets)) {
    if (JSON.stringify(vectors.states[kind]) !== JSON.stringify(expected)) fail(`${kind} trust states drifted`)
  }
  if (!Array.isArray(vectors.state_facts) || vectors.state_facts.length !== 19) fail('every trust state requires one fact')
  const knownStates = new Set(Object.values(exactStateSets).flat())
  const factStates = new Set()
  vectors.state_facts.forEach((fact, index) => {
    exactKeys(fact, ['state', 'durable_location', 'consequence', 'next_action'], `redaction.state_facts[${index}]`)
    if (!knownStates.has(fact.state) || factStates.has(fact.state)) fail('trust state facts must be exhaustive and unique')
    factStates.add(fact.state)
    for (const key of ['durable_location', 'consequence', 'next_action']) nonEmptyString(fact[key], `redaction.${key}`)
  })
  uniqueStrings(vectors.hostile_sentinels, 'redaction.hostile_sentinels', { nonEmpty: true })
  const diagnosticText = JSON.stringify(vectors.diagnostic_examples)
  for (const sentinel of vectors.hostile_sentinels) {
    if (diagnosticText.includes(sentinel)) fail('hostile sentinel entered diagnostic fixture')
  }
  return vectors.state_facts.length
}

/**
 * D-15 cross-consumer gate (04-03-PLAN.md Task 3): every one of the 13
 * golden vector files in packages/contracts/vectors/ declares its required
 * consumers in manifest.json. This fails loudly when a listed consumer did
 * not (or can no longer be proven to) execute a file it is listed for --
 * never a silent, hand-maintained assumption.
 *
 * Evidence differs by consumer, disclosed here rather than uniformly
 * faked:
 *   - swift / typescript: a machine-readable executed-file report, emitted
 *     by that harness's OWN test run (VectorConformanceTests.swift /
 *     sync-vectors.test.ts) and committed, so a consumer that silently
 *     stops executing a file changes this committed evidence -- a real,
 *     reviewable diff, not an invisible regression.
 *   - elixir: no Elixir test file is in this plan's authorized
 *     files_modified, so elixir evidence is computed by a live grep over
 *     every checked-in apps/server/test/**\/*.exs file for a literal
 *     reference to `vectors/<file>` -- dynamically computed at check time,
 *     never a hand-maintained array, and it changes the moment a test
 *     stops referencing a file.
 */
const vectorsDirectory = resolve(repositoryRoot, 'packages/contracts/vectors')
const manifestPath = resolve(vectorsDirectory, 'manifest.json')

const gitGrep = (pattern, paths) => {
  const result = spawnSync('git', ['-C', repositoryRoot, 'grep', '-l', pattern, '--', ...paths], { encoding: 'utf8' })
  // git grep exits 1 when there are zero matches -- not a tool failure.
  if (result.status !== 0 && result.status !== 1) {
    fail(`git grep failed while checking elixir vector consumption: ${result.stderr}`)
  }
  return result.stdout.split('\n').filter(Boolean)
}

const readExecutedFileReport = (consumer) => {
  const reportPath = resolve(repositoryRoot, 'tooling/vector-conformance-reports', `${consumer}.json`)
  try {
    const report = JSON.parse(readFileSync(reportPath, 'utf8'))
    if (report.consumer !== consumer || !Array.isArray(report.executedFiles)) {
      fail(`${reportPath} is malformed (expected {consumer: "${consumer}", executedFiles: [...]})`)
    }
    return new Set(report.executedFiles)
  } catch (error) {
    if (error.code === 'ENOENT') {
      fail(`missing executed-file report for consumer "${consumer}" at ${reportPath} -- run its test suite to regenerate, then commit the report`)
    }
    throw error
  }
}

/**
 * The one property this whole gate exists to enforce, isolated into a
 * function small enough to unit-test directly (see the malformed-fixture
 * check just below): a consumer is "proven executed" for a file only when
 * `hasExecuted(consumer, file)` says so.
 */
const assertConsumerExecutedFile = (consumer, file, hasExecuted) => {
  if (!hasExecuted(consumer, file)) {
    fail(`manifest lists "${consumer}" for ${file}, but its executed-file evidence does not include ${file}`)
  }
}

const validateVectorManifest = () => {
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'))
  if (manifest.version !== 1) fail('vector manifest version must be 1')
  const manifestFiles = Object.keys(manifest.files ?? {})

  const actualFiles = readdirSync(vectorsDirectory)
    .filter((entry) => entry.endsWith('.json') && entry !== 'manifest.json')
    .sort()
  if (actualFiles.length !== 14) fail(`expected 14 vector files, found ${actualFiles.length}: ${actualFiles.join(', ')}`)
  for (const file of actualFiles) {
    if (!manifestFiles.includes(file)) fail(`vector file not in manifest: ${file}`)
  }
  for (const file of manifestFiles) {
    if (!actualFiles.includes(file)) fail(`manifest lists a vector file that no longer exists: ${file}`)
  }

  const reportCache = new Map()
  const hasExecuted = (consumer, file) => {
    if (consumer === 'elixir') return gitGrep(`vectors/${file}`, ['apps/server/test']).length > 0
    if (!reportCache.has(consumer)) reportCache.set(consumer, readExecutedFileReport(consumer))
    return reportCache.get(consumer).has(file)
  }

  let checkedEntries = 0
  for (const [file, entry] of Object.entries(manifest.files)) {
    const consumers = entry.consumers
    if (!Array.isArray(consumers) || consumers.length === 0) fail(`manifest entry for ${file} has no consumers`)
    for (const consumer of consumers) {
      checkedEntries += 1
      assertConsumerExecutedFile(consumer, file, hasExecuted)
    }
  }
  return { files: manifestFiles.length, checkedEntries }
}

const vectorManifestResult = validateVectorManifest()

// Regression proof (Task 3 acceptance criterion): the gate must actually
// FAIL when a listed consumer's evidence does not include a file it is
// listed for. Exercised here against synthetic data -- never the real
// manifest/reports -- so this runs on every `pnpm contracts:check`
// invocation, not only once during authoring.
{
  const fakeEvidence = (consumer, file) => file === 'file-the-consumer-really-executed.json'
  let threw = false
  try {
    assertConsumerExecutedFile('swift', 'file-the-consumer-did-not-execute.json', fakeEvidence)
  } catch (error) {
    threw = true
    if (!String(error.message).includes('does not include')) throw error
  }
  if (!threw) fail('known missing executed-file evidence was accepted by the cross-consumer gate')
}

const schema = JSON.parse(readFileSync(syncSchema, 'utf8'))
if (schema.$schema !== 'https://json-schema.org/draft/2020-12/schema' || !schema.$defs?.case) {
  fail('schema must be a closed Draft 2020-12 state-machine contract')
}

const vectors = JSON.parse(readFileSync(syncVectors, 'utf8'))
validateNativeNamespaceContract(readFileSync(source, 'utf8'), readFileSync(generated, 'utf8'))
const executedSyncCases = validateSyncVectors(vectors)
const compatibility = JSON.parse(readFileSync(compatibilityVectors, 'utf8'))
const executedCompatibility = validateCompatibilityVectors(compatibility)
const redaction = JSON.parse(readFileSync(redactionVectors, 'utf8'))
const executedRedactionFacts = validateRedactionVectors(redaction)

const malformed = structuredClone(vectors)
malformed.cases[0].actions[0].type = 'unknown_action'
try {
  validateSyncVectors(malformed)
  fail('known malformed synchronization fixture was accepted')
} catch (error) {
  if (!String(error.message).includes('type is unknown')) throw error
}

const malformedCompatibility = structuredClone(compatibility)
malformedCompatibility.matrix.lanes[0].case_count = 0
try {
  validateCompatibilityVectors(malformedCompatibility)
  fail('known vacuous compatibility lane was accepted')
} catch (error) {
  if (!String(error.message).includes('executed zero cases')) throw error
}

const malformedRedaction = structuredClone(redaction)
malformedRedaction.states.mutation.push('unknown_state')
try {
  validateRedactionVectors(malformedRedaction)
  fail('known malformed trust state fixture was accepted')
} catch (error) {
  if (!String(error.message).includes('trust states drifted')) throw error
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
  `Contract drift check passed: OpenAPI agrees; ${executedSyncCases} sync cases, ${executedCompatibility.cases} compatibility cases, ${executedCompatibility.codecs} codec fixtures, ${executedCompatibility.lanes} skew lanes, and ${executedRedactionFacts} trust facts validated\n`,
)
for (const input of executedCompatibility.laneInputs) process.stdout.write(`Compatibility lane: ${input}\n`)
process.stdout.write(
  `Vector manifest gate passed: ${vectorManifestResult.files} vector files, ${vectorManifestResult.checkedEntries} consumer entries proven executed\n`,
)
