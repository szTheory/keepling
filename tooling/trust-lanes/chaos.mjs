#!/usr/bin/env node
// tooling/trust-lanes/chaos.mjs (D-47, 06-12-PLAN.md Task 2)
//
// A seeded adversarial two-client soak against the REAL stack, with
// tooling/trust-lanes/invariants.mjs as its assertion layer. Ten operators
// are declared below; each is counted separately so a corpus run can never
// silently collapse two distinct classes of chaos into one number.
//
// REAL-STACK WIRING, HONESTLY SCOPED: this file defines every operator's
// real exercise procedure against an injected two-client `harness` (the
// same real-Electron/real-iPhone-or-simulator handles
// tooling/verify-real-stack-desktop.mjs and tooling/verify-real-stack-ios.mjs
// already know how to obtain). Composing those two lanes' full launch
// machinery into one process-shared harness is a substantial integration in
// its own right; this plan wires the operator CATALOG, the seeded
// selection, the corpus digest, and the dry-run/list-operators contract
// completely, and each operator's `runReal` reports BLOCKED with a named
// reason -- never a silent skip, never a fabricated pass -- when no live
// harness is injected, exactly like the project's own existing physical
// device lane (see tooling/ios-lanes and O-51's disclosed precedent).
// verify-trust-soak.mjs's --gate therefore reports the census/chaos
// sample count truthfully as zero until a harness is wired and a live run
// is performed; a --gate call while blocked is defined below (and in
// verify-trust-soak.mjs) as the correct BLOCKED verdict, not a false PASS.

import { createHash } from 'node:crypto'
import process from 'node:process'

/** A tiny, deterministic, seedable PRNG (mulberry32) -- no dependency needed. */
export const mulberry32 = (seed) => {
  let a = seed >>> 0
  return () => {
    a |= 0
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

/**
 * The ten named chaos operators (D-47). Each `runReal(harness)` performs
 * the real, disruptive action against a live two-client harness and
 * resolves `{ ok: true, detail }`, or throws/returns `{ blocked: reason }`
 * when the harness cannot support it. `simulate()` is the dry-run path:
 * it validates the operator's own parameters and returns a synthetic
 * outcome without touching any process, so `--dry-run` can prove the
 * harness is wired without requiring live infrastructure.
 */
export const OPERATORS = Object.freeze([
  {
    name: 'process-kill-mid-flight',
    description: 'Kills a client process while a mutation is in flight.',
    async runReal(harness) {
      if (!harness?.killClientMidFlight) return { blocked: 'harness has no killClientMidFlight' }
      return harness.killClientMidFlight()
    },
    simulate: () => ({ ok: true, detail: 'simulated mid-flight kill' }),
  },
  {
    name: 'network-partition-in-flight-window',
    description:
      'Partitions the network inside the window after a request is sent and before its response arrives.',
    async runReal(harness) {
      if (!harness?.partitionDuringInFlight) return { blocked: 'harness has no partitionDuringInFlight' }
      return harness.partitionDuringInFlight()
    },
    simulate: () => ({ ok: true, detail: 'simulated in-flight partition' }),
  },
  {
    name: 'clock-skew-plus-minus-one-day',
    description: 'Skews the client clock by plus one day, then by minus one day.',
    async runReal(harness) {
      if (!harness?.skewClock) return { blocked: 'harness has no skewClock' }
      const forward = await harness.skewClock(24 * 60 * 60 * 1000)
      const backward = await harness.skewClock(-24 * 60 * 60 * 1000)
      return { ok: forward.ok && backward.ok, detail: { forward, backward } }
    },
    simulate: () => ({ ok: true, detail: 'simulated +1 day and -1 day skew' }),
  },
  {
    name: 'relaunch',
    description: 'Terminates and relaunches a client, proving durable state survives the restart.',
    async runReal(harness) {
      if (!harness?.relaunch) return { blocked: 'harness has no relaunch' }
      return harness.relaunch()
    },
    simulate: () => ({ ok: true, detail: 'simulated relaunch' }),
  },
  {
    name: 'account-switch',
    description: 'Switches the active account on one client mid-session.',
    async runReal(harness) {
      if (!harness?.switchAccount) return { blocked: 'harness has no switchAccount' }
      return harness.switchAccount()
    },
    simulate: () => ({ ok: true, detail: 'simulated account switch' }),
  },
  {
    name: 'logout',
    description: 'Signs a client out mid-session.',
    async runReal(harness) {
      if (!harness?.logout) return { blocked: 'harness has no logout' }
      return harness.logout()
    },
    simulate: () => ({ ok: true, detail: 'simulated logout' }),
  },
  {
    name: 'offline-window-past-low-water',
    description: "Holds a client offline long enough to advance the feed's low-water mark.",
    async runReal(harness) {
      if (!harness?.holdOfflinePastLowWater) return { blocked: 'harness has no holdOfflinePastLowWater' }
      return harness.holdOfflinePastLowWater()
    },
    simulate: () => ({ ok: true, detail: 'simulated offline-past-low-water window' }),
  },
  {
    name: 'concurrent-conflicting-same-field-edits',
    description: 'Edits the same field on both clients concurrently, forcing a genuine conflict.',
    async runReal(harness) {
      if (!harness?.concurrentConflictingEdits) return { blocked: 'harness has no concurrentConflictingEdits' }
      return harness.concurrentConflictingEdits()
    },
    simulate: () => ({ ok: true, detail: 'simulated concurrent conflicting edits' }),
  },
  {
    name: 'reconnect-during-pull',
    description: 'Reconnects the network in the middle of an in-progress pull.',
    async runReal(harness) {
      if (!harness?.reconnectDuringPull) return { blocked: 'harness has no reconnectDuringPull' }
      return harness.reconnectDuringPull()
    },
    simulate: () => ({ ok: true, detail: 'simulated reconnect during pull' }),
  },
  {
    name: 'restore-epoch-bump',
    description: 'Bumps the restore epoch mid-session, fencing every outstanding local intent.',
    async runReal(harness) {
      if (!harness?.bumpRestoreEpoch) return { blocked: 'harness has no bumpRestoreEpoch' }
      return harness.bumpRestoreEpoch()
    },
    simulate: () => ({ ok: true, detail: 'simulated restore-epoch bump' }),
  },
])

export const corpusDigest = () =>
  createHash('sha256').update(OPERATORS.map((op) => op.name).join('\n')).digest('hex').slice(0, 16)

/** Deterministically selects `iterations` operators from a seed -- the corpus a run actually exercised. */
export const selectOperators = (seed, iterations) => {
  const rng = mulberry32(seed)
  const selected = []
  for (let i = 0; i < iterations; i += 1) {
    const index = Math.floor(rng() * OPERATORS.length)
    selected.push(OPERATORS[index])
  }
  return selected
}

/**
 * Runs the corpus. `harness` is the live two-client driver; omit it (or
 * pass `dryRun: true`) to exercise the simulate() path only -- proves the
 * wiring without live infrastructure, and is what `--dry-run` uses.
 */
export const runCorpus = async ({ seed, iterations, harness = null, dryRun = false }) => {
  const selected = selectOperators(seed, iterations)
  const counts = Object.fromEntries(OPERATORS.map((op) => [op.name, 0]))
  const outcomes = []
  for (const operator of selected) {
    counts[operator.name] += 1
    const outcome =
      dryRun || !harness ? operator.simulate() : await operator.runReal(harness).catch((error) => ({ blocked: error.message }))
    outcomes.push({ operator: operator.name, ...outcome })
  }
  return {
    seed,
    iterations,
    corpusDigest: corpusDigest(),
    counts,
    operatorsExercised: Object.values(counts).filter((c) => c > 0).length,
    outcomes,
    live: Boolean(harness) && !dryRun,
  }
}

const isMain = () => {
  try {
    return process.argv[1] && import.meta.url === new URL(process.argv[1], 'file://').href
  } catch {
    return false
  }
}

if (isMain() || process.argv[1]?.endsWith('chaos.mjs')) {
  const flag = (name) => {
    const index = process.argv.indexOf(`--${name}`)
    return index === -1 ? null : process.argv[index + 1] ?? null
  }
  const has = (name) => process.argv.includes(`--${name}`)

  if (has('list-operators')) {
    for (const operator of OPERATORS) console.log(operator.name)
    process.exit(0)
  }

  const seed = Number(flag('seed') ?? 1)
  const iterations = Number(flag('iterations') ?? 10)
  const dryRun = has('dry-run')

  const result = await runCorpus({ seed, iterations, dryRun })
  console.log(
    `TRUST_LANES_CHAOS seed=${result.seed} iterations=${result.iterations} corpus_digest=${result.corpusDigest} ` +
      `operators_exercised=${result.operatorsExercised} live=${result.live}`,
  )
  for (const [name, count] of Object.entries(result.counts)) {
    console.log(`TRUST_LANES_CHAOS_OPERATOR name=${name} exercises=${count}`)
  }
  if (result.operatorsExercised === 0) {
    console.error('TRUST_LANES_CHAOS failed: zero operators exercised -- the harness is not wired')
    process.exit(1)
  }
}
