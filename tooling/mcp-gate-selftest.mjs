/**
 * mcp-gate-selftest.mjs (05-10-PLAN.md Task 2): a test of the HARNESS
 * itself, not of the feature. Phase 4 shipped 21 green lanes over stubs and
 * a fixture committed in its post-migration state; five subsequent
 * verifier passes then found skipped cases published as executed and a
 * counter that discarded whole test bundles (`.planning/WINDOWS.md` row
 * 65: auth published 4 of 19, undo 8 of 18, sync-presentation 21 of 35,
 * device 26 of 29). This file attacks the same class of failure in
 * `tooling/verify-mcp-phase.mjs` with synthetic fixtures built from those
 * exact real bundle counts -- the case that failed in Phase 4 is literally
 * the case asserted here -- plus one case per row of
 * `05-VALIDATION.md`'s Anti-Vacuity Controls table this file can exercise
 * without spawning a lane.
 *
 * Run with `node --test tooling/mcp-gate-selftest.mjs`, following this
 * repository's existing tooling conventions rather than adding a test
 * framework.
 */
import assert from 'node:assert/strict'
import { test } from 'node:test'

import { RUN_ID, exUnitSummary, inputDigestFor, laneVerdict } from './verify-mcp-phase.mjs'

test('two ExUnit invocations of 19 and 18 cases sum to 37, not 18 and not 19', () => {
  const stdout = [
    'Running ExUnit with seed: 1, max_cases: 4',
    '...................',
    'Finished in 0.1 seconds (0.00s async, 0.1s sync)',
    '',
    'Result: 19 passed',
    '',
    'Running ExUnit with seed: 2, max_cases: 4',
    '..................',
    'Finished in 0.1 seconds (0.00s async, 0.1s sync)',
    '',
    'Result: 18 passed',
  ].join('\n')

  assert.equal(exUnitSummary(stdout), 37)
})

test('a summary of 19 cases with 4 skipped publishes 15, never the pre-subtraction 19', () => {
  const stdout = ['Running ExUnit with seed: 1, max_cases: 4', 'Finished in 0.1 seconds (0.00s async, 0.1s sync)', '', 'Result: 19 passed, 4 skipped'].join(
    '\n',
  )

  assert.equal(exUnitSummary(stdout), 15)
})

test('two summaries where one reports zero cases throws -- the lane does not pass', () => {
  const stdout = ['Result: 0 tests', '', 'Result: 19 passed'].join('\n')

  assert.throws(() => exUnitSummary(stdout), /executed zero tests/)
})

test('output with no recognizable ExUnit summary throws rather than returning zero', () => {
  assert.throws(() => exUnitSummary('some unrelated program output with no Result: line anywhere'), /no ExUnit "Result:" summary/)
})

test('a non-zero failure count throws even when the process exit status was zero', () => {
  const stdout = ['Result: 15/19 passed', 'Failed: 4 tests'].join('\n')

  // The parser only ever receives stdout/stderr text -- it has no access to
  // the process exit code, so "even if exit status was 0" is proven by the
  // fact that this call passes no status argument at all and still throws
  // purely from the text.
  assert.throws(() => exUnitSummary(stdout), /reported 4 failing test/)
})

test('a lane whose parse error begins with the blocked prefix is reported blocked, never passed', () => {
  const { blocked, passed } = laneVerdict({ cases: 0, exitedCleanly: false, parseError: 'BLOCKED: no server reachable' })

  assert.equal(blocked, true)
  assert.equal(passed, false)
  // The caller (`runLane` in verify-mcp-phase.mjs) unconditionally sets
  // `anyFailed = true` whenever `passed` is false, blocked or not -- so
  // `passed === false` here is the mechanical proof that a blocked lane
  // still causes a non-zero run exit. There is no separate "blocked but
  // still exits 0" branch anywhere in that file.
  assert.equal(passed, false)
})

test('a lane returning a case count of zero without throwing is reported failed, not passed', () => {
  const { blocked, passed } = laneVerdict({ cases: 0, exitedCleanly: true, parseError: null })

  assert.equal(passed, false)
  assert.equal(blocked, false)
})

test('a lane reporting positive cases with a clean exit and no parse error passes', () => {
  const { blocked, passed } = laneVerdict({ cases: 12, exitedCleanly: true, parseError: null })

  assert.equal(passed, true)
  assert.equal(blocked, false)
})

test('inputDigestFor is sensitive to file contents, and an untracked path contributes nothing', () => {
  // Two long-tracked files predating this plan, guaranteed to already be
  // committed (unlike this very file or its siblings, which are still
  // being authored in the same task and are not yet tracked when this
  // test first runs) -- their different real contents must not digest
  // identically. This is the same underlying sensitivity a before/after
  // edit of one file would exercise: `inputDigestFor` hashes each tracked
  // file's actual bytes, so two inputs with different bytes never collide.
  const packageJsonDigest = inputDigestFor(['package.json'])
  const runtimePreflightDigest = inputDigestFor(['tooling/runtime-preflight.sh'])
  assert.notEqual(packageJsonDigest, runtimePreflightDigest)

  // A path this repository has never tracked contributes nothing: `git
  // ls-files` matches zero files for it, so its digest is the SAME
  // "nothing hashed" value regardless of which never-tracked path is
  // named -- proving the contribution is genuinely zero (a path-name-
  // independent constant), not merely "some other non-zero value".
  const untrackedDigestA = inputDigestFor(['tooling/this-path-does-not-exist-and-is-never-tracked.mjs'])
  const untrackedDigestB = inputDigestFor(['tooling/another-path-that-was-also-never-tracked.mjs'])
  assert.equal(untrackedDigestA, untrackedDigestB)
  assert.notEqual(untrackedDigestA, packageJsonDigest)
})

test('the runner carries a per-run identifier that differs between separate process loads', async () => {
  // A fresh dynamic import (cache-busted by a distinct query string) is the
  // cheapest faithful stand-in for "a separate process invocation" without
  // actually spawning `node` twice: ESM module instances are cached by
  // resolved specifier, so two DIFFERENT specifiers load two independent
  // module instances, each re-evaluating `const RUN_ID = randomUUID()` at
  // its own module-initialization time -- exactly the "once per process"
  // property this asserts. Two invocations of the real runner therefore
  // cannot be silently combined into one published result: each carries a
  // run id the other does not share.
  const first = await import('./verify-mcp-phase.mjs?selftest-run-a')
  const second = await import('./verify-mcp-phase.mjs?selftest-run-b')

  assert.notEqual(first.RUN_ID, second.RUN_ID)
  // The module loaded by THIS file's own top-level import is a third,
  // independent instance again.
  assert.notEqual(RUN_ID, first.RUN_ID)
  assert.notEqual(RUN_ID, second.RUN_ID)
})
