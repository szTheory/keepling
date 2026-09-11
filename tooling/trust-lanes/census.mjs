#!/usr/bin/env node
// tooling/trust-lanes/census.mjs (D-48, 06-12-PLAN.md Task 2)
//
// The thin-day census. Records, per day: locally-originated mutations,
// distinct task identifiers touched, offline minutes, completed sync
// rounds, and distinct screens reached. A day whose mutation count falls
// below MUTATION_FLOOR is a THIN DAY -- exposure was insufficient that day,
// and this module's whole job is to say so rather than let a quiet
// fortnight read as a clean one.
//
// This module records EXPOSURE. It never records or infers adoption, and
// it is never a measure of whether the owner likes the product (D-52) --
// the existing dogfood contract (docs/testing/trust-soak.md) already rules
// that sustained daily use has no checklist, no sign-off, and nobody
// counts it; this file's only job is the separate, narrower claim about
// how much real usage exercised the invariants on a given day.

import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import process from 'node:process'

/** A day below this many locally-originated mutations is a THIN day. */
export const MUTATION_FLOOR = 3

export const CENSUS_FIELDS = Object.freeze([
  'mutationsOriginatedLocally',
  'distinctTaskIdsTouched',
  'offlineMinutes',
  'syncRoundsCompleted',
  'distinctScreensReached',
])

/** Classifies one day's record. Every CENSUS_FIELDS key must be present and numeric. */
export const classifyDay = (day) => {
  for (const field of CENSUS_FIELDS) {
    if (typeof day[field] !== 'number' || Number.isNaN(day[field])) {
      throw new Error(`census.mjs: day record is missing numeric field "${field}"`)
    }
  }
  const thin = day.mutationsOriginatedLocally < MUTATION_FLOOR
  return { ...day, thin }
}

/** Loads a ledger of { date: DayRecord } from disk, or an empty ledger if absent. */
export const loadLedger = (path) => {
  if (!existsSync(path)) return {}
  try {
    return JSON.parse(readFileSync(path, 'utf8'))
  } catch {
    return {}
  }
}

export const saveLedger = (path, ledger) => {
  writeFileSync(path, `${JSON.stringify(ledger, null, 2)}\n`)
}

/** Records one day's observation into the ledger (upsert by date), returning the classified record. */
export const recordDay = (ledger, date, observation) => {
  const classified = classifyDay(observation)
  ledger[date] = classified
  return classified
}

/** Summarizes a ledger: total days, thin days, and the non-thin-day rate the gate's pass condition reads. */
export const summarize = (ledger) => {
  const days = Object.values(ledger)
  const thinDays = days.filter((d) => d.thin).length
  return {
    totalDays: days.length,
    thinDays,
    nonThinDays: days.length - thinDays,
    nonThinRate: days.length === 0 ? 0 : (days.length - thinDays) / days.length,
  }
}

const isMain = () => {
  try {
    return process.argv[1] && import.meta.url === new URL(process.argv[1], 'file://').href
  } catch {
    return false
  }
}

if (isMain() || process.argv[1]?.endsWith('census.mjs')) {
  const has = (name) => process.argv.includes(`--${name}`)

  if (has('self-check')) {
    // A synthetic ledger exercising both a thin day and a clean day, proving
    // this module can tell them apart -- the whole reason it exists.
    const ledger = {}
    recordDay(ledger, '2026-01-01', {
      mutationsOriginatedLocally: 1,
      distinctTaskIdsTouched: 1,
      offlineMinutes: 0,
      syncRoundsCompleted: 1,
      distinctScreensReached: 1,
    })
    recordDay(ledger, '2026-01-02', {
      mutationsOriginatedLocally: 12,
      distinctTaskIdsTouched: 5,
      offlineMinutes: 30,
      syncRoundsCompleted: 4,
      distinctScreensReached: 3,
    })
    const summary = summarize(ledger)
    const day1Thin = ledger['2026-01-01'].thin === true
    const day2Clean = ledger['2026-01-02'].thin === false
    console.log(
      `TRUST_LANES_CENSUS self_check=1 total_days=${summary.totalDays} thin_days=${summary.thinDays} ` +
        `day1_labeled_thin=${day1Thin} day2_labeled_thin=${!day2Clean}`,
    )
    if (!day1Thin || !day2Clean) {
      console.error('TRUST_LANES_CENSUS self-check failed: could not distinguish a thin day from a clean one')
      process.exit(1)
    }
    process.exit(0)
  }

  console.log('usage: node tooling/trust-lanes/census.mjs --self-check')
  process.exit(1)
}
