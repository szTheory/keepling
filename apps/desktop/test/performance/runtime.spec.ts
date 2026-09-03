import { describe, expect, it } from 'vitest'

import {
  compareMetricAgainstBudget,
  percentile,
  privacyScan,
  round,
  summarize,
} from '../../../../tooling/measure-desktop-performance.mjs'

/**
 * Unit tests for the D-43 measurement tooling's PURE statistics, privacy,
 * and regression-budget-comparison logic
 * (tooling/measure-desktop-performance.mjs). This deliberately does NOT
 * exercise the live Electron measurement path -- that path launches the
 * exact packaged executable and is verified by the plan's own `<verify>`
 * commands (`node tooling/measure-desktop-performance.mjs --manifest ...`),
 * not by this fast, deterministic vitest lane. Importing the module here
 * must never spawn Electron or touch process.argv -- see the entrypoint
 * guard at the bottom of measure-desktop-performance.mjs.
 */

describe('percentile / summarize', () => {
  it('computes p50 and p95 over a sorted sample set', () => {
    const sorted = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
    expect(percentile(sorted, 50)).toBe(50)
    expect(percentile(sorted, 95)).toBe(100)
  })

  it('returns NaN for an empty sample set rather than throwing', () => {
    expect(percentile([], 50)).toBeNaN()
  })

  it('summarize reports count, p50, p95, min, and max from unsorted input', () => {
    const summary = summarize([30, 10, 20])
    expect(summary).toMatchObject({ count: 3, max: 30, min: 10, p50: 20 })
  })
})

describe('privacyScan', () => {
  it('accepts closed metadata: digests, revisions, numbers, and plain metric names', () => {
    expect(() =>
      privacyScan({
        environment: { arch: 'arm64', platform: 'darwin' },
        source: { applicationDigestSha256: 'abc123', sourceRevision: 'deadbeef' },
        metrics: { cold_launch_to_local_interactive_ms: { p50: 268, unit: 'ms' } },
      }),
    ).not.toThrow()
  })

  it('rejects an absolute filesystem path leaking into evidence', () => {
    expect(() => privacyScan({ note: '/Users/jon/Library/Application Support/Keepling/namespace.sqlite3' })).toThrow(
      /privacy scan rejected/,
    )
  })

  it('rejects a URL leaking into evidence', () => {
    expect(() => privacyScan({ note: 'https://example.com/leak' })).toThrow(/privacy scan rejected/)
  })

  it('scans nested arrays and objects, not just top-level fields', () => {
    expect(() => privacyScan({ metrics: [{ detail: { path: 'file:///tmp/leak' } }] })).toThrow(/privacy scan rejected/)
  })
})

describe('compareMetricAgainstBudget', () => {
  const baselineBudgets = {
    metrics: {
      cold_launch_to_local_interactive_ms: {
        baseline: 200,
        budget: { kind: 'relative', value: 0.35 },
        rationale: 'test rationale',
        sampleFloor: 3,
        statistic: 'p95',
      },
      list_scroll_frame_p95_ms: {
        baseline: 10,
        budget: { kind: 'absolute', value: 8 },
        rationale: 'test rationale',
        sampleFloor: 30,
        statistic: 'p95',
      },
    },
  }

  it('fails closed when no budget entry exists for the metric', () => {
    const result = compareMetricAgainstBudget('unknown_metric', [1, 2, 3], baselineBudgets)
    expect(result.ok).toBe(false)
    expect(result.reason).toMatch(/missing budget/)
  })

  it('fails closed when the budget entry is missing rationale/baseline/sampleFloor', () => {
    const result = compareMetricAgainstBudget('incomplete', [1, 2, 3], {
      metrics: { incomplete: { baseline: 10 } },
    })
    expect(result.ok).toBe(false)
    expect(result.reason).toMatch(/incomplete budget/)
  })

  it('fails closed on insufficient samples, never comparing an under-sampled run', () => {
    const result = compareMetricAgainstBudget('cold_launch_to_local_interactive_ms', [200, 210], baselineBudgets)
    expect(result.ok).toBe(false)
    expect(result.reason).toMatch(/insufficient samples/)
  })

  it('passes when the current p95 is within a relative budget over baseline', () => {
    const result = compareMetricAgainstBudget('cold_launch_to_local_interactive_ms', [200, 205, 210], baselineBudgets)
    expect(result.ok).toBe(true)
  })

  it('fails when the current p95 exceeds a relative budget over baseline', () => {
    const result = compareMetricAgainstBudget('cold_launch_to_local_interactive_ms', [1000, 1000, 1000], baselineBudgets)
    expect(result.ok).toBe(false)
    expect(result.reason).toMatch(/exceeded budget/)
  })

  it('passes/fails correctly for an absolute-kind budget', () => {
    const withinBudget = compareMetricAgainstBudget(
      'list_scroll_frame_p95_ms',
      Array.from({ length: 30 }, () => 12),
      baselineBudgets,
    )
    expect(withinBudget.ok).toBe(true)

    const overBudget = compareMetricAgainstBudget(
      'list_scroll_frame_p95_ms',
      Array.from({ length: 30 }, () => 25),
      baselineBudgets,
    )
    expect(overBudget.ok).toBe(false)
  })

  it('a synthetic regression injected on top of real-shaped samples is rejected, proving the check is not vacuous', () => {
    const realShapedSamples = [195, 198, 201]
    const injectedRegression = realShapedSamples.map((value) => value * 10 + 5_000)
    const result = compareMetricAgainstBudget('cold_launch_to_local_interactive_ms', injectedRegression, baselineBudgets)
    expect(result.ok).toBe(false)
  })
})

describe('round', () => {
  it('rounds to 2 decimal places and passes NaN/Infinity through unchanged', () => {
    expect(round(1.2345)).toBe(1.23)
    expect(round(Number.NaN)).toBeNaN()
  })
})
