#!/usr/bin/env node
/**
 * 05-10-PLAN.md: the Phase 5 (Safe Agent Access) gate, built distrustfully
 * on `tooling/verify-ios-phase.mjs`'s anti-vacuity structure (D-25/D-26,
 * `.planning/WINDOWS.md` row 65).
 *
 * Phase 4 shipped 21 green lanes over stubs, fakes, and a fixture committed
 * in its post-migration state. Five subsequent verifier passes then found
 * skipped cases published as executed, a counter that discarded whole test
 * bundles (one of which was the ONLY hardware evidence for its lane,
 * contributing zero to the published number), and a composite of three
 * separate runs written up as one passing gate. This phase's central claim
 * -- that a language model cannot escalate its own authority -- would be
 * considerably worse to falsify the same way, so every mechanism below is
 * copied from the FIXED iOS structure, not the one that shipped the defect.
 *
 * Lanes are discovered by globbing `tooling/mcp-lanes/*.mjs` rather than
 * declared inline, so a later plan in this phase adds its lane by adding a
 * file, never by editing this runner's lane list (though later plans DO
 * still edit `REQUIREMENT_LANES` below as they add lanes -- see the comment
 * on that map).
 *
 * `--requirements` checks the machine-readable requirement-to-lane map
 * (REQUIREMENT_LANES below) against this phase's requirement ids read live
 * from `.planning/REQUIREMENTS.md`'s Traceability table, and fails if any
 * requirement has no mapped lane or maps to a lane file that does not
 * exist.
 *
 * A lane may report `BLOCKED` (never PASS, never silently absent) when it
 * genuinely cannot run for want of a live server, a credential, or a prior
 * plan's evidence. BLOCKED still fails the overall run (exit code stays
 * non-zero) so this command can never report green while required evidence
 * is missing -- disclosed, not defective.
 */
import { randomUUID } from 'node:crypto'
import { createHash } from 'node:crypto'
import { readFileSync, readdirSync } from 'node:fs'
import { join, resolve } from 'node:path'
import process from 'node:process'
import { spawnSync } from 'node:child_process'

const repositoryRoot = resolve(import.meta.dirname, '..')
const lanesDir = join(repositoryRoot, 'tooling', 'mcp-lanes')

// A fresh identifier every time this module is loaded (once per process,
// once per `import()`). The self-test asserts two separate loads produce
// two different ids -- the mechanical proof behind "the runner writes its
// summary once per process and cannot be combined into one published
// result" (Task 2's seventh behaviour, the composite-run risk).
const RUN_ID = randomUUID()

const fail = (message) => {
  console.error(`MCP phase gate failed: ${message}`)
}

const gitLsFiles = (paths) => {
  const result = spawnSync('git', ['-C', repositoryRoot, 'ls-files', '-z', ...paths], { encoding: 'utf8' })
  return result.stdout.split('\0').filter(Boolean).sort()
}

/**
 * A SHA-256 digest of every git-tracked file under `paths`, contents
 * included -- copied from `verify-ios-phase.mjs` unmodified except for the
 * paths it is called with. A path that is tracked but no longer exists on
 * disk still contributes its name to the digest (provenance, not silence);
 * a path that has never been tracked (a module that "lands" in a later
 * plan) simply contributes nothing, which is correct provenance too.
 */
const inputDigestFor = (paths) => {
  const files = gitLsFiles(paths)
  const digest = createHash('sha256')
  for (const relativePath of files) {
    digest.update(`${relativePath}\0`)
    try {
      digest.update(readFileSync(join(repositoryRoot, relativePath)))
    } catch {
      // See comment above: a tracked-but-deleted path still names itself.
    }
    digest.update('\0')
  }
  return digest.digest('hex').slice(0, 16)
}

/**
 * The pure PASS / BLOCKED / FAIL discriminator, factored out of `runLane`
 * so the self-test can drive it directly without spawning a process
 * (Task 2's acceptance criteria: a blocked lane is not passed and still
 * fails the run; a lane returning zero cases without throwing is failed,
 * not passed).
 */
const laneVerdict = ({ cases, exitedCleanly, parseError }) => {
  const passed = exitedCleanly && parseError === null && Number.isFinite(cases) && cases > 0
  // A parse error prefixed "BLOCKED:" is a genuine, disclosed inability to
  // run -- missing server/credential/prior-plan evidence -- NEVER a silent
  // skip and NEVER counted as a pass. The caller (`runLane`) still marks
  // the overall run failed for a blocked lane (anyFailed stays true), so
  // the gate can never report green while required evidence is missing.
  const blocked = !passed && parseError !== null && parseError.startsWith('BLOCKED:')
  return { blocked, passed }
}

let anyFailed = false
const results = []

/**
 * Runs one lane's command, then hands raw stdout/stderr to `parse` to
 * extract a positive case count. `parse` MUST throw or return a
 * non-positive count for output it cannot make sense of -- there is no
 * "assume it passed" fallback anywhere in this file. A lane file that
 * fails to LOAD is a runner failure, never a skipped lane (enforced by the
 * loader below, not here).
 */
const runLane = ({ args, command, cwd, env, name, parse, trackedInputPaths }) => {
  const startedAt = Date.now()
  const result = spawnSync(command, args, { cwd: cwd ?? repositoryRoot, encoding: 'utf8', env: { ...process.env, ...env } })
  const durationMs = Date.now() - startedAt
  const stdout = result.stdout ?? ''
  const stderr = result.stderr ?? ''
  const inputDigest = trackedInputPaths ? inputDigestFor(trackedInputPaths) : 'n/a'

  let cases = 0
  let parseError = null
  try {
    cases = parse(stdout, stderr, result.status)
  } catch (error) {
    parseError = error instanceof Error ? error.message : String(error)
  }

  const exitedCleanly = result.status === 0 && !result.error
  const { blocked, passed } = laneVerdict({ cases, exitedCleanly, parseError })
  results.push({ blocked, cases, durationMs, inputDigest, name, passed })

  const statusWord = passed ? 'PASS' : blocked ? 'BLOCKED' : 'FAIL'
  console.log(`LANE name=${name} status=${statusWord} cases=${cases} duration_ms=${durationMs} input_digest=${inputDigest} run_id=${RUN_ID}`)
  if (!passed) {
    anyFailed = true
    if (parseError) fail(`${name}: ${parseError}`)
    else if (!exitedCleanly) fail(`${name}: exited ${result.status ?? 'without status'}${stderr ? `: ${stderr.trim().slice(-2000)}` : ''}`)
    else fail(`${name}: reported zero cases`)
    console.error(`--- ${name} stdout tail ---`)
    console.error(stdout.trim().slice(-4000))
    console.error(`--- ${name} stderr tail ---`)
    console.error(stderr.trim().slice(-2000))
  }
}

/**
 * Parses `mix test`'s own CLI-formatter summary (Elixir 1.20.2,
 * `lib/ex_unit/cli_formatter.ex`). Measured directly against this
 * repository's pinned runtime, not assumed from documentation:
 *
 *   - all passed, one test type:        "Result: 34 passed"
 *   - all passed, multiple types:       "Result: 237 passed (1 property, 236 tests)"
 *   - some failed:                      "Result: 1/2 passed" + "\nFailed: 1 test"
 *   - a skip present:                   "Result: 1 passed, 1 skipped"
 *
 * ExUnit's own `test_counter` (the number before "passed", or before the
 * `/` when some failed) already excludes skipped and excluded tests -- it
 * increments only on a test that reached a terminal `nil` or `{:failed,_}`
 * state, never on `{:skipped,_}` or `{:excluded,_}`. This function
 * subtracts the skipped/excluded counts from that number ANYWAY: not
 * because Elixir's own arithmetic is wrong today, but because trusting a
 * single formatter's bookkeeping to never regress is exactly the posture
 * that let `.planning/WINDOWS.md` row 65 happen one layer up (xcodebuild's
 * own "Executed N tests" DID include skips, and nothing caught it until a
 * human read the numbers by hand). The subtraction can only ever make the
 * published count MORE conservative than reality -- it can turn a healthy
 * bundle's count down by a handful, but it can never turn a zero-evidence
 * bundle into a positive one. A bundle that is entirely skips is exactly
 * the case this is written to catch: it throws here instead of quietly
 * reporting the pre-skip declared total as though it had all been run.
 *
 * Throws on output it cannot parse, on any single invocation that executed
 * zero tests, on any invocation that reported a failure, and on an
 * invocation ExUnit itself marked `invalid` (a `setup_all` failure that
 * invalidated tests without running them) -- there is no
 * assume-it-passed fallback anywhere in this function, matching
 * `xcodebuildSummary`'s own rule.
 */
const exUnitSummary = (stdout) => {
  if (typeof stdout !== 'string') throw new Error('exUnitSummary: no stdout to parse')

  // A bundle that ran nothing must never let a healthy sibling bundle's
  // count stand in for it -- the exact shape of the iOS defect this
  // function exists to not repeat, one level up (a whole ExUnit invocation
  // discarded from a multi-invocation lane's published total).
  if (/Result: 0 tests/.test(stdout)) {
    throw new Error('one of this lane\'s ExUnit invocations executed zero tests')
  }

  const resultLine = /Result: (\d+)(?:\/(\d+))? passed(?:\s*\([^)\n]*\))?(?:, (\d+) invalid)?(?:, (\d+) skipped)?(?:, (\d+) excluded)?/g
  const matches = [...stdout.matchAll(resultLine)]
  if (matches.length === 0) {
    throw new Error('no ExUnit "Result:" summary found in output')
  }

  let total = 0
  for (const match of matches) {
    const passedCount = Number(match[1])
    const declared = match[2] !== undefined ? Number(match[2]) : passedCount
    const invalid = match[3] !== undefined ? Number(match[3]) : 0
    const skipped = match[4] !== undefined ? Number(match[4]) : 0
    const excluded = match[5] !== undefined ? Number(match[5]) : 0
    const failures = declared - passedCount

    if (invalid > 0) {
      throw new Error(`ExUnit reported ${invalid} invalid test(s) (a setup_all failure invalidated tests without running them)`)
    }
    if (failures > 0) {
      throw new Error(`ExUnit reported ${failures} failing test(s)`)
    }

    const executed = declared - skipped - excluded
    if (executed <= 0) {
      throw new Error(
        `this ExUnit invocation's ${declared} declared case(s) reduce to zero after subtracting ${skipped} skipped and ${excluded} excluded`,
      )
    }
    total += executed
  }

  if (total <= 0) throw new Error('ExUnit executed zero tests across every invocation in this lane')
  return total
}

/**
 * The requirement-to-lane map (05-10-PLAN.md Task 1, extended by
 * 05-11-PLAN.md Task 3 exactly as 05-10-SUMMARY.md's own Next Phase
 * Readiness section named this plan as the one that would). Every
 * requirement this phase's `.planning/REQUIREMENTS.md` Phase 5 row names
 * -- MCP-01..05 and SRV-02 -- must map to at least one EXISTING lane file,
 * checked below by `--requirements`.
 *
 * This plan (05-11, Wave 6) adds `simulated-client`, `adversarial`, and
 * `representative-model` to every MCP-0N requirement's map -- the D-25
 * evidence lanes that genuinely exercise a live client, real authorization,
 * and (credential permitting) a real model against each requirement's
 * surface. `SRV-02` is deliberately left mapped to the SAME two lanes
 * 05-10 gave it (`deterministic`, `protocol`): D-27 requires SRV-02's
 * completion proof to be the CROSS-ADAPTER lane specifically -- driving
 * web/API, Electron, iPhone, and MCP together against one server revision
 * -- which does not exist as a file until 05-12-PLAN.md (Wave 7) lands it.
 * Mapping SRV-02 to this plan's single-adapter lanes would let
 * `--requirements` claim evidence this plan does not provide; 05-12 is the
 * plan that extends SRV-02's row here, exactly as this plan extended
 * MCP-01..05's rows for 05-10.
 */
const REQUIREMENT_LANES = {
  'MCP-01': ['deterministic', 'protocol', 'simulated-client', 'adversarial', 'representative-model'],
  'MCP-02': ['deterministic', 'protocol', 'simulated-client', 'adversarial', 'representative-model'],
  'MCP-03': ['deterministic', 'protocol', 'simulated-client', 'adversarial', 'representative-model'],
  'MCP-04': ['deterministic', 'protocol', 'simulated-client', 'adversarial', 'representative-model'],
  'MCP-05': ['deterministic', 'protocol', 'simulated-client', 'adversarial', 'representative-model'],
  'SRV-02': ['deterministic', 'protocol'],
}

/**
 * Reads this phase's requirement ids straight from the Phase 5 row of
 * `.planning/REQUIREMENTS.md`'s Traceability table, rather than
 * hard-coding them, so a requirement later added to that row without a
 * mapped lane fails `--requirements` instead of silently passing. Mirrors
 * `verify-ios-phase.mjs`'s `phase4RequirementIds` exactly, one phase over.
 */
const phase5RequirementIds = () => {
  const requirementsPath = join(repositoryRoot, '.planning', 'REQUIREMENTS.md')
  const text = readFileSync(requirementsPath, 'utf8')
  const row = text.split('\n').find((line) => line.includes('| Phase 5 |') && line.includes('MCP'))
  if (!row) throw new Error('no Phase 5 row found in .planning/REQUIREMENTS.md Traceability table')
  // Only the row's FIRST cell names requirement ids; later cells are prose
  // that may cite other id-shaped tokens (decision ids, etc).
  const idCell = row.split('|')[1] ?? ''
  const ids = new Set()
  for (const match of idCell.matchAll(/([A-Z]+)-(\d+)\.\.(\d+)/g)) {
    const [, prefix, start, end] = match
    for (let n = Number(start); n <= Number(end); n += 1) ids.add(`${prefix}-${String(n).padStart(2, '0')}`)
  }
  for (const match of idCell.matchAll(/\b([A-Z]+-\d+)\b/g)) {
    if (!/\.\.$/.test(idCell.slice(0, match.index))) ids.add(match[1])
  }
  if (ids.size === 0) throw new Error('Phase 5 row named no requirement ids')
  return [...ids].sort()
}

const runAsCli = async () => {
  const requestedLane = (() => {
    const flagIndex = process.argv.indexOf('--lane')
    return flagIndex === -1 ? null : process.argv[flagIndex + 1]
  })()

  const requirementsMode = process.argv.includes('--requirements')

  let laneFiles
  try {
    // Slow and credential-gated lanes rank first, so a missing credential
    // or unreachable server is discovered in seconds rather than after the
    // deterministic lane has already run its full suite -- mirrors the
    // iOS runner's hardware-first ordering (device-lock lesson, one level
    // over: here it is a missing model credential or server, not a phone
    // that auto-locked).
    const SLOW_OR_GATED_LANES = ['protocol.mjs', 'simulated-client.mjs', 'representative-model.mjs', 'adversarial.mjs', 'cross-adapter.mjs']
    const rank = (entry) => (SLOW_OR_GATED_LANES.includes(entry) ? 0 : 1)
    laneFiles = readdirSync(lanesDir)
      .filter((entry) => entry.endsWith('.mjs'))
      .sort((a, b) => rank(a) - rank(b) || a.localeCompare(b))
  } catch (error) {
    console.error(`MCP phase gate failed: could not read lane directory ${lanesDir}: ${String(error)}`)
    process.exit(1)
  }

  if (laneFiles.length === 0) {
    console.error('MCP phase gate failed: tooling/mcp-lanes/ contains no lane files')
    process.exit(1)
  }

  if (requirementsMode) {
    let ids
    try {
      ids = phase5RequirementIds()
    } catch (error) {
      console.error(`MCP phase gate failed: ${String(error.message ?? error)}`)
      process.exit(1)
    }
    let unmapped = false
    for (const id of ids) {
      const lanes = REQUIREMENT_LANES[id]
      if (!lanes || lanes.length === 0) {
        console.error(`MCP phase gate failed: requirement ${id} has no mapped lane in REQUIREMENT_LANES`)
        unmapped = true
        continue
      }
      const missingLanes = lanes.filter((lane) => !laneFiles.includes(`${lane}.mjs`))
      if (missingLanes.length > 0) {
        console.error(`MCP phase gate failed: requirement ${id} maps to lane(s) with no definition file: ${missingLanes.join(', ')}`)
        unmapped = true
        continue
      }
      console.log(`REQUIREMENT id=${id} lanes=${lanes.join(',')}`)
    }
    const unmappedDefinedLanes = Object.keys(REQUIREMENT_LANES).filter((id) => !ids.includes(id))
    if (unmappedDefinedLanes.length > 0) {
      console.error(`MCP phase gate failed: REQUIREMENT_LANES declares id(s) absent from the Phase 5 row: ${unmappedDefinedLanes.join(', ')}`)
      unmapped = true
    }
    if (unmapped) {
      console.error('MCP requirement map: FAILED')
      process.exit(1)
    }
    console.log(`MCP requirement map: ${ids.length} requirement(s) all mapped to existing lanes`)
    process.exit(0)
  }

  for (const file of laneFiles) {
    const laneName = file.replace(/\.mjs$/, '')
    if (requestedLane !== null && requestedLane !== laneName) continue
    let laneModule
    try {
      // eslint-disable-next-line no-await-in-loop
      laneModule = await import(join(lanesDir, file))
    } catch (error) {
      // A lane file that fails to load is a RUNNER failure, never a
      // skipped lane.
      console.error(`MCP phase gate failed: lane file ${file} failed to load: ${String(error)}`)
      process.exit(1)
    }
    if (typeof laneModule.default !== 'function') {
      console.error(`MCP phase gate failed: lane file ${file} has no default export function`)
      process.exit(1)
    }
    const definition = laneModule.default({ exUnitSummary, repositoryRoot })
    runLane(definition)
  }

  if (requestedLane !== null && results.length === 0) {
    console.error(`MCP phase gate failed: requested lane "${requestedLane}" was not found in ${lanesDir}`)
    process.exit(1)
  }

  const blockedCount = results.filter((r) => r.blocked).length
  console.log('')
  console.log(`MCP phase gate summary: lanes=${results.length} failed=${results.filter((r) => !r.passed).length} blocked=${blockedCount} run_id=${RUN_ID}`)
  for (const result of results) {
    const word = result.passed ? 'PASS' : result.blocked ? 'BLOCKED' : 'FAIL'
    console.log(`  ${word} ${result.name} cases=${result.cases} duration_ms=${result.durationMs} input_digest=${result.inputDigest}`)
  }

  if (blockedCount > 0) {
    console.error('')
    console.error(
      `MCP phase gate: BLOCKED (${blockedCount} lane(s) cannot run yet -- see BLOCKED lines above). This is not a code defect; ` +
        'it is disclosed, genuine missing evidence (server/credential/prior-plan checkpoint). The gate refuses to report ' +
        'success while it is missing, per D-25/D-26 and the anti-vacuity contract.',
    )
  }

  if (anyFailed) {
    console.error('MCP phase gate: FAILED')
    process.exit(1)
  }
  console.log('MCP phase gate: PASSED')
}

// Behind the usual main-module guard: importing this file (the self-test
// does exactly that) must never spawn a lane or touch process.argv/exit.
if (import.meta.url === `file://${process.argv[1]}`) {
  await runAsCli()
}

export { RUN_ID, exUnitSummary, gitLsFiles, inputDigestFor, laneVerdict, phase5RequirementIds, REQUIREMENT_LANES }
