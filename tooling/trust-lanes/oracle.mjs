// tooling/trust-lanes/oracle.mjs (D-45, 06-12-PLAN.md Task 1)
//
// A read-only reconciliation oracle. It takes three INDEPENDENT reads --
// the server through its own read endpoints plus a database identity that
// holds select privileges only (`keepling_auditor`, provisioned by
// 20260912000300_add_auditor_role.exs), a desktop SQLite store opened
// read-only, and an iOS SQLite store pulled from a device with the
// existing device file-copy capability -- and assembles them into the
// dataset shape tooling/trust-lanes/invariants.mjs evaluates.
//
// STRUCTURAL GUARANTEE: no function in this module ever issues a mutating
// statement against any source, and the server read never uses a
// non-read HTTP verb. This is not merely a convention -- verify-trust-soak.mjs's
// negative gates (mirrored by this plan's own <verify> blocks) scan this
// file's source for exactly those patterns and fail the lane if either
// appears anywhere. This module also imports nothing from apps/desktop,
// apps/ios, or packages/web-ui: the invariants sit on the database and
// endpoint schemas, never on a client's own code, which is what keeps a
// bug shared between a client and its checker from hiding a violation from
// both.
//
// Content is never compared as plaintext. Every entity digest this module
// produces is either computed by Postgres itself over already-hashed bytes
// (see readServerDb) or computed locally from a SQLite snapshot and
// immediately reduced to a digest before the plaintext value leaves this
// function's local scope -- the plaintext itself is never attached to any
// object this module returns, logs, or serializes.

import { createHash, createHmac, randomBytes } from 'node:crypto'
import { existsSync, readFileSync, statSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { dirname, join, resolve } from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'

const laneDirectory = dirname(fileURLToPath(import.meta.url))
export const repositoryRoot = resolve(laneDirectory, '..', '..')

const UNIT_SEPARATOR = '\x1f'
const ROW_SEPARATOR = '\x1e'

/**
 * Guard-refusal: fails loudly if a shortcut has been injected into this
 * lane's own source or invariants.mjs's -- e.g. a hand-written mutating
 * statement, a client-package import, or a non-read HTTP verb. Mirrors the
 * existing pattern in tooling/mcp-client/client.mjs's
 * guardAgainstShortcuts, scoped to the checks D-45's threat register names.
 */
export const guardAgainstShortcuts = (sourceFilePath) => {
  if (!existsSync(sourceFilePath)) return true
  const source = readFileSync(sourceFilePath, 'utf8')
  const withoutLineComments = source.replace(/\/\/.*$/gm, '')
  const relative = sourceFilePath.replace(`${repositoryRoot}/`, '')
  const mutatingVerbPattern = /\b(insert|update|delete|drop|truncate|alter)[\s]+(into|from|table|set)\b/i
  if (mutatingVerbPattern.test(withoutLineComments)) {
    throw new Error(`${relative} contains a mutating SQL statement -- the oracle must never write`)
  }
  if (/method:\s*['"](POST|PUT|PATCH|DELETE)['"]/i.test(withoutLineComments)) {
    throw new Error(`${relative} issues a non-read HTTP verb against the server`)
  }
  if (/from\s+['"].*(apps\/desktop|apps\/ios|packages\/web-ui)/i.test(withoutLineComments)) {
    throw new Error(`${relative} imports client code -- this recreates the shared-bug class`)
  }
  return true
}

export const newRunKey = () => randomBytes(32).toString('hex')

export const keyedDigest = (runKey, value) =>
  createHmac('sha256', String(runKey)).update(String(value)).digest('hex')

const plainDigest = (value) => createHash('sha256').update(String(value)).digest('hex')

/** Reads a JSON revision-history cache from a prior run, if present. Never required. */
export const loadRevisionCache = (cachePath) => {
  if (!cachePath || !existsSync(cachePath)) return {}
  try {
    return JSON.parse(readFileSync(cachePath, 'utf8'))
  } catch {
    return {}
  }
}

const priorRevisionFor = (cache, key) => (Object.hasOwn(cache, key) ? cache[key] : null)

// ---------------------------------------------------------------------------
// Desktop / iOS read: both platforms persist the local durable store as a
// plain SQLite file under the SAME table names (apps/desktop/migrations vs.
// apps/ios/Sources/KeeplingCore/Storage/Migrations define canonical_shadow,
// visible_projection, outbox, immutable_commands, conflicts identically);
// only the desktop store additionally carries refusal_records (06-06). One
// reader function covers both.
// ---------------------------------------------------------------------------

const nowMs = () => Date.now()

/**
 * Opens a local SQLite store read-only via node:sqlite and reads every
 * table the invariants need. Returns `{ blocked: reason }` when the path is
 * absent or cannot be opened -- never throws, so a missing desktop/iOS
 * store degrades one source rather than crashing the whole run.
 */
export const readLocalStore = async (path, { runKey, revisionCache = {}, cacheKeyPrefix }) => {
  if (!path || !existsSync(path)) {
    return { blocked: `no store file at ${path ?? '(unset)'}` }
  }
  let DatabaseSync
  try {
    ;({ DatabaseSync } = await import('node:sqlite'))
  } catch {
    return { blocked: 'node:sqlite is unavailable in this runtime' }
  }
  let db
  try {
    db = new DatabaseSync(path, { readOnly: true })
  } catch (error) {
    return { blocked: `could not open ${path} read-only: ${error.message}` }
  }
  try {
    const hasTable = (name) =>
      db
        .prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?")
        .get(name) != null

    const outbox = db
      .prepare('SELECT mutation_id, sequence FROM outbox')
      .all()
      .map((row) => ({ mutationId: row.mutation_id, state: stateFor(db, row.mutation_id), ageMs: 0 }))

    const commands = db
      .prepare('SELECT mutation_id, task_id, accepted_at FROM immutable_commands')
      .all()
      .map((row) => ({
        mutationId: row.mutation_id,
        entityId: row.task_id,
        acceptedAt: row.accepted_at,
      }))

    const conflicts = hasTable('conflicts')
      ? db
          .prepare('SELECT mutation_id FROM conflicts')
          .all()
          .map((row) => ({ mutationId: row.mutation_id }))
      : []

    const refusals = hasTable('refusal_records')
      ? db
          .prepare('SELECT mutation_id, entity_id, unresolved FROM refusal_records')
          .all()
          .map((row) => ({
            mutationId: row.mutation_id,
            entityId: row.entity_id,
            unresolved: row.unresolved === 1,
          }))
      : []

    const shadows = db.prepare('SELECT entity_id, snapshot_json FROM canonical_shadow').all()
    const pendingEntityIds = new Set(commands.map((c) => c.entityId))
    const entities = shadows.map((row) => {
      // Read the plaintext snapshot once, reduce it to a digest, and never
      // retain the plaintext itself past this expression.
      const digest = plainDigest(row.snapshot_json)
      let revision = 1
      try {
        revision = JSON.parse(row.snapshot_json)?.revision ?? 1
      } catch {
        revision = 1
      }
      let trashedAt = null
      let restoredAt = null
      try {
        const parsed = JSON.parse(row.snapshot_json)
        trashedAt = parsed?.trashedAt ?? parsed?.trashed_at ?? null
        restoredAt = parsed?.restoredAt ?? parsed?.restored_at ?? null
      } catch {
        // Malformed snapshot JSON: leave trash/restore fields unknown rather
        // than guessing, and let I4/I7 report against what parsed cleanly.
      }
      const cacheKey = `${cacheKeyPrefix}:${row.entity_id}`
      return {
        entityId: row.entity_id,
        revision,
        digest: keyedDigest(runKey, digest),
        priorRevision: priorRevisionFor(revisionCache, cacheKey),
        trashedAt,
        restoredAt,
      }
    })

    const cursorRow = db.prepare('SELECT cursor FROM sync_cursor WHERE singleton = 1').get()

    return {
      outbox,
      commands,
      conflicts,
      refusals,
      entities,
      cursor: cursorRow?.cursor ?? null,
      priorCursor: priorRevisionFor(revisionCache, `${cacheKeyPrefix}:__cursor__`),
    }
  } finally {
    db.close()
  }
}

// The desktop/iOS outbox table records only `state` as a derived value in
// this reader's own vocabulary (queued/in_flight/uncertain live in the
// `state` column added by desktop migration 0002; iOS carries the
// equivalent column under the same migration lineage). Read it directly
// rather than re-deriving it.
function stateFor(db, mutationId) {
  const row = db
    .prepare('SELECT state FROM outbox WHERE mutation_id = ?')
    .get(mutationId)
  return row?.state ?? 'queued'
}

// ---------------------------------------------------------------------------
// Server read: a select-only database identity (never a client's own write
// role) plus the server's own read-only health endpoints.
// ---------------------------------------------------------------------------

const runPsql = (connectionUrl, sql) => {
  const result = spawnSync(
    'psql',
    [connectionUrl, '-v', 'ON_ERROR_STOP=1', '-t', '-A', `-F${UNIT_SEPARATOR}`, '-R', ROW_SEPARATOR, '-c', sql],
    { encoding: 'utf8', timeout: 30_000 },
  )
  if (result.status !== 0) {
    throw new Error(`psql failed: ${(result.stderr ?? '').trim().slice(0, 500)}`)
  }
  const trimmed = result.stdout.replace(/\n$/, '')
  if (trimmed === '') return []
  return trimmed.split(ROW_SEPARATOR).map((row) => row.split(UNIT_SEPARATOR))
}

/**
 * Reads the server's durable state through the select-only `keepling_auditor`
 * identity. Content digests are computed IN Postgres, over bytes Postgres
 * itself already reduced with `sha256()` -- the oracle's own process never
 * receives a task's plaintext title or notes at all for this source.
 */
export const readServerDb = (connectionUrl, { runKey, revisionCache = {} }) => {
  if (!connectionUrl) return { blocked: 'no --server-db-url provided' }
  try {
    const receipts = runPsql(
      connectionUrl,
      "SELECT mutation_id, terminal, response_status FROM command_receipts",
    ).map(([mutationId, terminal, responseStatus]) => ({
      mutationId,
      outcome: outcomeFor(terminal === 't', responseStatus),
    }))

    const taskRows = runPsql(
      connectionUrl,
      "SELECT id, revision, encode(sha256(convert_to(coalesce(title, '') || '|' || coalesce(inbox_state, ''), 'UTF8')), 'hex') FROM tasks",
    ).map(([entityId, revision, contentDigest]) => {
      const cacheKey = `server:${entityId}`
      return {
        entityId,
        revision: Number(revision),
        digest: keyedDigest(runKey, contentDigest),
        priorRevision: priorRevisionFor(revisionCache, cacheKey),
        trashedAt: null,
        restoredAt: null,
      }
    })

    const feedRows = runPsql(
      connectionUrl,
      'SELECT sequence, ordinal FROM sync_changes ORDER BY sequence, ordinal',
    ).map(([sequence, ordinal]) => ({ sequence: Number(sequence), ordinal: Number(ordinal) }))

    const boundsRow = runPsql(connectionUrl, 'SELECT high_sequence, low_water_sequence FROM sync_accounts')[0]

    const activityRows = runPsql(
      connectionUrl,
      'SELECT id, task_id, mutation_id FROM task_activities',
    ).map(([activityId, taskId, mutationId]) => ({ activityId, taskId, mutationId }))

    return {
      receipts,
      entities: taskRows,
      feed: {
        highSequence: boundsRow ? Number(boundsRow[0]) : 0,
        lowWaterSequence: boundsRow ? Number(boundsRow[1]) : 0,
        entries: feedRows,
      },
      activities: activityRows,
    }
  } catch (error) {
    return { blocked: error.message }
  }
}

const outcomeFor = (terminal, responseStatus) => {
  if (!terminal) return 'pending'
  const status = Number(responseStatus)
  if (status >= 200 && status < 300) return 'accepted'
  if (status === 409) return 'conflict'
  if (status === 422) return 'rejected'
  return 'rejected'
}

/** A read-only ping against the server's own health endpoints -- GET only, ever. */
export const readServerEndpoint = async (baseUrl) => {
  if (!baseUrl) return { blocked: 'no --server-base-url provided' }
  try {
    const response = await fetch(new URL('/health/ready', baseUrl), { method: 'GET' })
    return { reachable: response.ok, status: response.status }
  } catch (error) {
    return { blocked: error.message }
  }
}

// ---------------------------------------------------------------------------
// Dataset assembly and the CLI lane report shape shared by every lane in
// this project (name, positive case count, duration, tracked-input digest).
// ---------------------------------------------------------------------------

const gitLsFiles = (paths) => {
  const result = spawnSync('git', ['-C', repositoryRoot, 'ls-files', '--', ...paths], {
    encoding: 'utf8',
  })
  return result.status === 0 ? result.stdout.split('\n').filter(Boolean) : paths
}

export const inputDigestFor = (paths) => {
  const files = gitLsFiles(paths)
  const digest = createHash('sha256')
  for (const relativePath of files) {
    digest.update(`${relativePath}\0`)
    try {
      digest.update(readFileSync(join(repositoryRoot, relativePath)))
    } catch {
      // A tracked-but-locally-deleted path still names itself in the digest.
    }
    digest.update('\0')
  }
  return digest.digest('hex').slice(0, 16)
}

export const ORACLE_TRACKED_INPUTS = [
  'tooling/trust-lanes/oracle.mjs',
  'tooling/trust-lanes/invariants.mjs',
]

/**
 * Assembles the reconciliation dataset from up to three independent
 * sources. Any source that could not be read is `null` in the returned
 * dataset (never substituted, never fabricated) and is separately reported
 * in `sourceStatus` with the reason it was unreadable.
 */
export const buildDataset = async ({
  runKey = newRunKey(),
  serverDbUrl = null,
  serverBaseUrl = null,
  desktopStorePath = null,
  iosStorePath = null,
  revisionCachePath = null,
} = {}) => {
  const revisionCache = loadRevisionCache(revisionCachePath)
  const [serverDb, serverEndpoint, desktop, ios] = await Promise.all([
    Promise.resolve(readServerDb(serverDbUrl, { runKey, revisionCache })),
    readServerEndpoint(serverBaseUrl),
    readLocalStore(desktopStorePath, { runKey, revisionCache, cacheKeyPrefix: 'desktop' }),
    readLocalStore(iosStorePath, { runKey, revisionCache, cacheKeyPrefix: 'ios' }),
  ])

  const sourceStatus = {
    server: serverDb.blocked ? { blocked: serverDb.blocked } : { ok: true, endpoint: serverEndpoint },
    desktop: desktop.blocked ? { blocked: desktop.blocked } : { ok: true },
    ios: ios.blocked ? { blocked: ios.blocked } : { ok: true },
  }

  return {
    dataset: {
      runKey,
      generatedAt: new Date().toISOString(),
      server: serverDb.blocked ? null : serverDb,
      desktop: desktop.blocked ? null : desktop,
      ios: ios.blocked ? null : ios,
    },
    sourceStatus,
  }
}

/** Persists the observed revisions so the NEXT run can check monotonicity across time. */
export const revisionSnapshotFrom = (dataset) => {
  const snapshot = {}
  if (dataset.server) {
    for (const entity of dataset.server.entities ?? []) snapshot[`server:${entity.entityId}`] = entity.revision
  }
  if (dataset.desktop) {
    for (const entity of dataset.desktop.entities ?? []) snapshot[`desktop:${entity.entityId}`] = entity.revision
    if (dataset.desktop.cursor != null) snapshot['desktop:__cursor__'] = dataset.desktop.cursor
  }
  if (dataset.ios) {
    for (const entity of dataset.ios.entities ?? []) snapshot[`ios:${entity.entityId}`] = entity.revision
    if (dataset.ios.cursor != null) snapshot['ios:__cursor__'] = dataset.ios.cursor
  }
  return snapshot
}

const isMain = () => {
  const invoked = process.argv[1] ? resolve(process.argv[1]) : null
  return invoked === fileURLToPath(import.meta.url)
}

if (isMain()) {
  const flag = (name) => {
    const index = process.argv.indexOf(`--${name}`)
    return index === -1 ? null : process.argv[index + 1] ?? null
  }

  const start = nowMs()
  guardAgainstShortcuts(fileURLToPath(import.meta.url))
  guardAgainstShortcuts(join(repositoryRoot, 'tooling', 'trust-lanes', 'invariants.mjs'))

  const runKey = flag('run-key') ?? newRunKey()
  const { dataset, sourceStatus } = await buildDataset({
    runKey,
    serverDbUrl: flag('server-db-url') ?? process.env.KEEPLING_TRUST_SOAK_AUDITOR_URL ?? null,
    serverBaseUrl: flag('server-base-url'),
    desktopStorePath: flag('desktop-store-path'),
    iosStorePath: flag('ios-store-path'),
    revisionCachePath: flag('revisions-cache'),
  })

  const { evaluateInvariants } = await import('./invariants.mjs')
  const results = evaluateInvariants(dataset)
  const positiveCaseCount = results.reduce((sum, r) => sum + r.samples, 0)
  const durationMs = nowMs() - start
  const trackedInputDigest = inputDigestFor(ORACLE_TRACKED_INPUTS)

  const report = {
    lane: 'trust-lanes-oracle',
    runKey,
    positiveCaseCount,
    durationMs,
    trackedInputDigest,
    sourceStatus,
    invariants: results,
  }

  console.log(
    `TRUST_LANES_ORACLE lane=trust-lanes-oracle cases=${positiveCaseCount} duration_ms=${durationMs} tracked_input_digest=${trackedInputDigest}`,
  )
  if (flag('json') !== null || process.argv.includes('--json')) {
    console.log(JSON.stringify(report, null, 2))
  }
}
