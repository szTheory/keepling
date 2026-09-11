#!/usr/bin/env node

/**
 * O-40 / QUAL-03 / MAC-05 (06-02 Task 3 wording correction): proves (or
 * disproves) that packaging the desktop app produces byte-identical output
 * across SEPARATE `pnpm package:desktop` invocations, ON ONE MACHINE, AT
 * ONE REVISION. That is the entire scope of the claim this lane measures --
 * it is a single-machine, single-revision nondeterminism canary, NOT a
 * cross-machine or cross-revision reproducibility guarantee. Describing the
 * property as machine-independent would be the same over-broad claim O-40
 * itself corrected once already (a digest computed on one machine
 * legitimately need not match one computed on a different machine or
 * runner image, and this lane says nothing about that case).
 *
 * This tool is deliberately NOT allowed to declare a pass by comparing
 * nothing, comparing a tree to itself, or silently downgrading an
 * unreadable entry to "same". `--self-test` proves the comparator can see a
 * real difference (content, mode, and symlink-target) on synthetic input
 * before it is ever trusted on a real packaged bundle -- the same
 * SELF-TEST-EVIDENCE idiom `tooling/verify-macos-integration.mjs` already
 * uses.
 *
 * No dependency is added: node:crypto, node:fs, node:path, node:child_process
 * and node:os only. The `@electron/asar` CLI used to descend into `.asar`
 * archives is already present in the desktop toolchain, not newly added.
 */

import { createHash } from 'node:crypto'
import {
  chmodSync,
  cpSync,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  readlinkSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs'
import { tmpdir } from 'node:os'
import { join, relative, resolve } from 'node:path'
import process from 'node:process'
import { spawnSync } from 'node:child_process'

const repositoryRoot = resolve(import.meta.dirname, '..')
const desktopRoot = join(repositoryRoot, 'apps', 'desktop')
const reportPath = join(desktopRoot, 'out', 'reproducibility-report.json')

const fail = (message) => {
  console.error(`Package reproducibility check failed: ${message}`)
  process.exit(1)
}

// ---------------------------------------------------------------------------
// Tree comparison -- mirrors tooling/package-desktop.mjs's `hashDirectory`
// traversal EXACTLY: sorted readdirSync with withFileTypes, relative path
// plus octal lstat mode plus symlink target plus file content. Nothing here
// may exclude an entry, a directory, a mode bit or a symlink target to make
// a difference disappear -- that is the vacuous pass this tool exists to
// prevent.
// ---------------------------------------------------------------------------

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex')

/** Walks a directory tree into a flat map of relativePath -> entry descriptor. */
const walkTree = (root) => {
  const entries = new Map()
  const visit = (directory) => {
    for (const entry of readdirSync(directory, { withFileTypes: true }).sort((left, right) => left.name.localeCompare(right.name))) {
      const path = join(directory, entry.name)
      const relativePath = relative(root, path)
      const metadata = lstatSync(path)
      const mode = metadata.mode.toString(8)
      if (entry.isDirectory()) {
        entries.set(relativePath, { mode, type: 'dir' })
        visit(path)
      } else if (entry.isSymbolicLink()) {
        entries.set(relativePath, { linkTarget: readlinkSync(path), mode, type: 'symlink' })
      } else {
        entries.set(relativePath, { contentHash: sha256(readFileSync(path)), mode, type: 'file' })
      }
    }
  }
  visit(root)
  return entries
}

/**
 * Compares two directory trees entry-by-entry. Returns every entry's
 * disposition (not just the differing ones), so `comparedEntries` is a
 * proof that a real comparison happened, not just a count of failures.
 */
const compareTrees = (pathA, labelA, pathB, labelB) => {
  const mapA = walkTree(pathA)
  const mapB = walkTree(pathB)
  const allPaths = [...new Set([...mapA.keys(), ...mapB.keys()])].sort()
  const diffs = []
  for (const path of allPaths) {
    const a = mapA.get(path)
    const b = mapB.get(path)
    if (!a) {
      diffs.push({ detail: `present only in ${labelB}`, kind: `only-in-${labelB}`, path })
      continue
    }
    if (!b) {
      diffs.push({ detail: `present only in ${labelA}`, kind: `only-in-${labelA}`, path })
      continue
    }
    if (a.type !== b.type) {
      diffs.push({ detail: `${labelA}=${a.type} ${labelB}=${b.type}`, kind: 'type-differs', path })
      continue
    }
    if (a.mode !== b.mode) {
      diffs.push({ detail: `${labelA}=${a.mode} ${labelB}=${b.mode}`, kind: 'mode-differs', path })
      continue
    }
    if (a.type === 'symlink') {
      if (a.linkTarget !== b.linkTarget) {
        diffs.push({ detail: `${labelA}=${a.linkTarget} ${labelB}=${b.linkTarget}`, kind: 'link-differs', path })
      }
      continue
    }
    if (a.type === 'file' && a.contentHash !== b.contentHash) {
      diffs.push({ detail: `${labelA}=${a.contentHash.slice(0, 12)} ${labelB}=${b.contentHash.slice(0, 12)}`, kind: 'content-differs', path })
    }
  }
  return { comparedEntries: allPaths.length, diffs }
}

// ---------------------------------------------------------------------------
// .asar descent
// ---------------------------------------------------------------------------

const asarExtract = (archivePath, destination) => {
  const result = spawnSync('pnpm', ['--dir', 'apps/desktop', 'exec', 'asar', 'extract', archivePath, destination], {
    cwd: repositoryRoot,
    encoding: 'utf8',
  })
  return result.status === 0 && !result.error
}

/**
 * When a `.asar` archive differs at the container level, descend into it and
 * name the differing MEMBER, not just the archive. If extraction is
 * unavailable for any reason, the original diff is replaced with an explicit
 * `asar-extract-unavailable` entry -- NEVER silently downgraded to "same".
 */
const descendIntoAsar = (diff, pathA, pathB) => {
  const scratchRoot = mkdtempSync(join(tmpdir(), 'keepling-repro-asar-'))
  try {
    const archiveA = join(pathA, diff.path)
    const archiveB = join(pathB, diff.path)
    const extractedA = join(scratchRoot, 'a')
    const extractedB = join(scratchRoot, 'b')
    if (!existsSync(archiveA) || !existsSync(archiveB)) {
      return [{ ...diff, kind: 'asar-extract-unavailable', detail: 'archive missing on one side' }]
    }
    if (!asarExtract(archiveA, extractedA) || !asarExtract(archiveB, extractedB)) {
      return [{ ...diff, kind: 'asar-extract-unavailable', detail: 'asar extract failed or is unavailable' }]
    }
    const { diffs: memberDiffs } = compareTrees(extractedA, 'a', extractedB, 'b')
    if (memberDiffs.length === 0) {
      // The container differed but no extracted member did -- something at
      // the archive-header level moved (entry order, header padding, etc).
      // Reporting this as "same" would be exactly the vacuous pass this
      // tool exists to prevent.
      return [{ ...diff, kind: 'asar-container-differs', detail: 'no extracted member differed; archive header/layout differs' }]
    }
    return memberDiffs.map((memberDiff) => ({ ...memberDiff, path: `${diff.path}!${memberDiff.path}` }))
  } finally {
    rmSync(scratchRoot, { force: true, recursive: true })
  }
}

// ---------------------------------------------------------------------------
// Self-test: proves the comparator can SEE a real difference before it is
// ever trusted on a real packaged bundle.
// ---------------------------------------------------------------------------

const runSelfTest = () => {
  const cases = []
  const check = (description, condition, detail = '') => {
    cases.push({ description, ok: Boolean(condition), detail })
    console.log(`SELFTEST_CASE ok=${condition ? 'true' : 'false'} description=${JSON.stringify(description)}${condition ? '' : ` detail=${JSON.stringify(detail)}`}`)
  }

  const scratchRoot = mkdtempSync(join(tmpdir(), 'keepling-repro-selftest-'))
  try {
    const treeA = join(scratchRoot, 'tree-a')
    const treeB = join(scratchRoot, 'tree-b')
    mkdirSync(join(treeA, 'nested'), { recursive: true })
    writeFileSync(join(treeA, 'nested', 'file.txt'), 'hello world')
    writeFileSync(join(treeA, 'nested', 'exec.sh'), '#!/bin/sh\necho hi\n', { mode: 0o755 })
    writeFileSync(join(treeA, 'nested', 'archive.asar'), 'not-a-real-archive-just-a-placeholder-entry')
    symlinkSync('file.txt', join(treeA, 'nested', 'link'))

    // Identical copy -- must report zero differences on a positive count.
    cpSync(treeA, treeB, { dereference: false, recursive: true, verbatimSymlinks: true })
    const identical = compareTrees(treeA, 'a', treeB, 'b')
    check('an identical copy reports differing_entries=0', identical.diffs.length === 0, JSON.stringify(identical.diffs))
    check('an identical copy still reports a positive compared_entries', identical.comparedEntries > 0, String(identical.comparedEntries))

    // Mutate three distinct entries: content, mode, symlink target.
    const bytes = readFileSync(join(treeB, 'nested', 'file.txt'), 'utf8')
    writeFileSync(join(treeB, 'nested', 'file.txt'), `${bytes.slice(0, -1)}X`)
    chmodSync(join(treeB, 'nested', 'exec.sh'), 0o644)
    rmSync(join(treeB, 'nested', 'link'))
    symlinkSync('exec.sh', join(treeB, 'nested', 'link'))

    const mutated = compareTrees(treeA, 'a', treeB, 'b')
    const byPath = new Map(mutated.diffs.map((diff) => [diff.path, diff]))
    check(
      'mutating one byte of file content is reported as content-differs at its exact path',
      byPath.get('nested/file.txt')?.kind === 'content-differs',
      JSON.stringify(byPath.get('nested/file.txt')),
    )
    check(
      'mutating one mode bit is reported as mode-differs at its exact path',
      byPath.get('nested/exec.sh')?.kind === 'mode-differs',
      JSON.stringify(byPath.get('nested/exec.sh')),
    )
    check(
      'mutating one symlink target is reported as link-differs at its exact path',
      byPath.get('nested/link')?.kind === 'link-differs',
      JSON.stringify(byPath.get('nested/link')),
    )
    check('exactly three entries differ, nothing more and nothing less', mutated.diffs.length === 3, JSON.stringify(mutated.diffs))
    check('the untouched .asar-named placeholder entry is still reported as same', !byPath.has('nested/archive.asar'), JSON.stringify(byPath.get('nested/archive.asar')))
  } finally {
    rmSync(scratchRoot, { force: true, recursive: true })
  }

  const failed = cases.filter((entry) => !entry.ok).length
  console.log(`PACKAGE_REPRODUCIBILITY_SELFTEST cases=${cases.length} failed=${failed}`)
  process.exit(failed === 0 ? 0 : 1)
}

// ---------------------------------------------------------------------------
// Real build comparison
// ---------------------------------------------------------------------------

/** The exact tracked-input set `tooling/package-desktop.mjs` computes -- a
 * reproducibility claim about a dirty tree is meaningless, so this tool
 * refuses on the same terms packaging itself does. */
const trackedInputs = () => {
  const result = spawnSync(
    'git',
    [
      '-C',
      repositoryRoot,
      'ls-files',
      '-z',
      'apps/desktop',
      '.npmrc',
      'package.json',
      'pnpm-lock.yaml',
      'pnpm-workspace.yaml',
      'tooling/package-desktop.mjs',
      'tooling/smoke-desktop-packaged.mjs',
    ],
    { encoding: 'utf8' },
  )
  return result.stdout.split('\0').filter(Boolean).sort()
}

const refuseIfDirty = () => {
  const inputs = trackedInputs()
  if (inputs.length === 0) fail('the package input set is empty')
  const dirty = spawnSync('git', ['-C', repositoryRoot, 'status', '--porcelain', '--untracked-files=no', '--', ...inputs], {
    encoding: 'utf8',
  })
  if (dirty.stdout.trim() !== '') {
    fail(`a reproducibility claim about a dirty tree is meaningless -- package inputs must be committed first:\n${dirty.stdout.trim()}`)
  }
}

const packageOnce = (buildNumber) => {
  const result = spawnSync('pnpm', ['package:desktop'], { cwd: repositoryRoot, encoding: 'utf8' })
  if (result.status !== 0 || result.error) {
    fail(`build ${buildNumber} (pnpm package:desktop) exited ${result.status ?? 'without status'}${result.stderr ? `: ${result.stderr.trim().slice(-2000)}` : ''}`)
  }
  const match = (result.stdout ?? '').match(/Desktop package manifest: (.+)/)
  if (!match) fail(`build ${buildNumber} did not print a "Desktop package manifest:" line`)
  const manifestPath = match[1].trim()
  let manifest
  try {
    manifest = JSON.parse(readFileSync(manifestPath, 'utf8'))
  } catch (error) {
    fail(`build ${buildNumber}'s manifest at ${manifestPath} could not be read: ${error instanceof Error ? error.message : String(error)}`)
  }
  return { manifest, manifestPath }
}

const runBuilds = (buildCount) => {
  if (buildCount < 2) fail(`--builds must be at least 2 to prove reproducibility, got ${buildCount}`)
  refuseIfDirty()

  const builds = []
  for (let i = 1; i <= buildCount; i += 1) {
    console.log(`Building ${i}/${buildCount} (separate process)...`)
    builds.push(packageOnce(i))
  }

  const allDiffs = []
  let comparedEntries = 0
  const baseline = builds[0]
  for (let i = 1; i < builds.length; i += 1) {
    const labelA = 'build-1'
    const labelB = `build-${i + 1}`
    const { comparedEntries: pairCompared, diffs } = compareTrees(
      baseline.manifest.copiedApplicationPath,
      labelA,
      builds[i].manifest.copiedApplicationPath,
      labelB,
    )
    comparedEntries += pairCompared
    for (const diff of diffs) {
      if (diff.kind === 'content-differs' && diff.path.endsWith('.asar')) {
        allDiffs.push(...descendIntoAsar(diff, baseline.manifest.copiedApplicationPath, builds[i].manifest.copiedApplicationPath))
      } else {
        allDiffs.push(diff)
      }
    }
  }

  const distinctDigests = [...new Set(builds.map((build) => build.manifest.applicationDigestSha256))]

  mkdirSync(join(desktopRoot, 'out'), { recursive: true })
  writeFileSync(
    reportPath,
    `${JSON.stringify(
      {
        builds: builds.map((build, index) => ({
          applicationDigestSha256: build.manifest.applicationDigestSha256,
          buildNumber: index + 1,
          executableDigestSha256: build.manifest.executableDigestSha256,
          manifestPath: build.manifestPath,
        })),
        comparedEntries,
        differingEntries: allDiffs.length,
        diffs: allDiffs,
        generatedAt: new Date().toISOString(),
      },
      null,
      2,
    )}\n`,
    'utf8',
  )

  const cappedDiffs = allDiffs.slice(0, 50)
  for (const diff of cappedDiffs) {
    console.log(`REPRO_DIFF path=${diff.path} kind=${diff.kind} detail=${diff.detail}`)
  }
  if (allDiffs.length > cappedDiffs.length) {
    console.log(`REPRO_DIFF truncated=${allDiffs.length - cappedDiffs.length}`)
  }

  console.log(
    `PACKAGE_REPRODUCIBILITY builds=${buildCount} compared_entries=${comparedEntries} differing_entries=${allDiffs.length} digests=${distinctDigests.join(',')}`,
  )

  const passed = allDiffs.length === 0 && distinctDigests.length === 1 && comparedEntries > 0
  process.exit(passed ? 0 : 1)
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

const args = process.argv.slice(2)
if (args.includes('--self-test')) {
  runSelfTest()
} else {
  const buildsFlagIndex = args.indexOf('--builds')
  const buildCount = buildsFlagIndex === -1 ? 3 : Number(args[buildsFlagIndex + 1])
  if (!Number.isInteger(buildCount)) fail('--builds requires an integer argument')
  runBuilds(buildCount)
}
