#!/usr/bin/env node

import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import process from 'node:process'

const repositoryRoot = resolve(import.meta.dirname, '..')
const failures = []
const passes = []

const readRequired = (relativePath) => {
  try {
    return readFileSync(resolve(repositoryRoot, relativePath), 'utf8')
  } catch (error) {
    failures.push(`${relativePath}: required input is missing or unreadable (${error.code ?? 'read_error'})`)
    return null
  }
}

const readJson = (relativePath) => {
  const source = readRequired(relativePath)
  if (source == null) return null
  try {
    return JSON.parse(source)
  } catch {
    failures.push(`${relativePath}: expected valid JSON`)
    return null
  }
}

const requirePattern = (relativePath, source, pattern, description) => {
  if (source == null) return
  if (!pattern.test(source)) {
    failures.push(`${relativePath}: missing ${description}`)
    return
  }
  passes.push(`${relativePath}: ${description}`)
}

const forbidPattern = (relativePath, source, pattern, description) => {
  if (source == null) return
  if (pattern.test(source)) {
    failures.push(`${relativePath}: forbidden ${description}`)
    return
  }
  passes.push(`${relativePath}: no ${description}`)
}

const requireScript = (manifestPath, manifest, name, expectedPattern) => {
  const script = manifest?.scripts?.[name]
  if (typeof script !== 'string' || !expectedPattern.test(script)) {
    failures.push(`${manifestPath}: script ${name} is missing or does not resolve to its non-watch lane`)
    return
  }
  if (/\bwatch\b|--watch|passWithNoTests|pass-with-no-tests/i.test(script)) {
    failures.push(`${manifestPath}: script ${name} enables watch or zero-test success`)
    return
  }
  passes.push(`${manifestPath}: script ${name}`)
}

const verifyBuildConfig = () => {
  const rootManifest = readJson('package.json')
  const desktopManifest = readJson('apps/desktop/package.json')

  const rootScripts = {
    'dev:desktop': /apps\/desktop\s+dev/,
    'package:desktop': /apps\/desktop\s+package/,
    'smoke:desktop:packaged': /apps\/desktop\s+smoke:packaged/,
    'test:desktop': /apps\/desktop\s+test/,
    'test:desktop:e2e': /apps\/desktop\s+test:e2e/,
    'test:desktop:ipc': /apps\/desktop\s+test:ipc/,
    'typecheck:desktop': /apps\/desktop\s+typecheck/,
  }
  for (const [name, pattern] of Object.entries(rootScripts)) {
    requireScript('package.json', rootManifest, name, pattern)
  }

  const desktopScripts = {
    build: /build:main.*build:preload.*build:renderer.*build:worker/,
    package: /package-desktop\.mjs/,
    'smoke:packaged': /smoke-desktop-packaged\.mjs/,
    test: /vitest\s+run.*--project/,
    'test:e2e': /playwright\s+test.*--project\s+electron/,
    'test:ipc': /vitest\s+run.*--project\s+ipc/,
    typecheck: /tsc.*--noEmit/,
  }
  for (const [name, pattern] of Object.entries(desktopScripts)) {
    requireScript('apps/desktop/package.json', desktopManifest, name, pattern)
  }

  const forge = readRequired('apps/desktop/forge.config.ts')
  requirePattern('apps/desktop/forge.config.ts', forge, /maker-zip/, 'macOS ZIP maker')
  requirePattern('apps/desktop/forge.config.ts', forge, /asar:\s*true/, 'ASAR packaging')
  for (const role of ['main', 'preload', 'renderer', 'worker']) {
    const path = `apps/desktop/vite.${role}.config.ts`
    const config = readRequired(path)
    requirePattern(path, config, new RegExp(`(?:${role}|dist/${role})`, 'i'), `${role} process boundary`)
    forbidPattern(path, config, /watch:\s*true|--watch/, 'watch-mode build')
  }

  const tsconfig = readRequired('apps/desktop/tsconfig.json')
  for (const entry of ['main', 'preload', 'renderer', 'store-worker']) {
    requirePattern('apps/desktop/tsconfig.json', tsconfig, new RegExp(`"${entry}/`), `${entry} TypeScript entry coverage`)
  }
}

const verifyTestConfig = () => {
  const vitestPath = 'apps/desktop/vitest.config.ts'
  const vitest = readRequired(vitestPath)
  for (const project of ['application', 'renderer', 'store', 'worker', 'ipc']) {
    requirePattern(vitestPath, vitest, new RegExp(`name:\\s*['"]${project}['"]`), `${project} named project`)
  }
  requirePattern(vitestPath, vitest, /passWithNoTests:\s*false/, 'explicit zero-test refusal')
  requirePattern(vitestPath, vitest, /include:\s*\[[^\]]*(?:test|spec)/s, 'explicit non-watch test discovery')
  forbidPattern(vitestPath, vitest, /passWithNoTests:\s*true|watch:\s*true|--watch/, 'watch or zero-test success')

  const playwrightPath = 'apps/desktop/playwright.config.ts'
  const playwright = readRequired(playwrightPath)
  for (const project of ['electron', 'packaged']) {
    requirePattern(playwrightPath, playwright, new RegExp(`name:\\s*['"]${project}['"]`), `${project} Playwright project`)
  }
  requirePattern(playwrightPath, playwright, /workers:\s*1/, 'serial stateful execution')
  requirePattern(playwrightPath, playwright, /fullyParallel:\s*false/, 'parallelism disabled')
  requirePattern(playwrightPath, playwright, /screenshot:\s*['"]only-on-failure['"]/, 'failure screenshots')
  requirePattern(playwrightPath, playwright, /trace:\s*['"]retain-on-failure['"]/, 'failure traces')
  requirePattern(playwrightPath, playwright, /mkdtempSync\([\s\S]*tmpdir\(\)/, 'disposable system-temporary profile allocation')
  requirePattern(playwrightPath, playwright, /KEEPLING_FORBIDDEN_USER_DATA_DIR/, 'normal Keepling profile rejection contract')
  requirePattern(playwrightPath, playwright, /assertDisposableProfile/, 'per-launch disposable-profile guard')
  forbidPattern(playwrightPath, playwright, /reuseExistingServer:\s*true|webServer:|passWithNoTests|--watch/, 'development server, watch, or zero-test success')

  const packagePath = 'tooling/package-desktop.mjs'
  const packageSource = readRequired(packagePath)
  for (const field of [
    'sourceRevision',
    'inputDigestSha256',
    'applicationDigestSha256',
    'zipDigestSha256',
    'executableDigestSha256',
    'embeddedVersions',
    'executablePath',
    'copiedApplicationPath',
  ]) {
    requirePattern(packagePath, packageSource, new RegExp(`\\b${field}\\b`), `${field} package-manifest field`)
  }
  requirePattern(packagePath, packageSource, /electron-forge[\s\S]*make/, 'single Forge make producer')
  requirePattern(packagePath, packageSource, /mkdtempSync\([\s\S]*tmpdir\(\)/, 'external copied application')
  requirePattern(packagePath, packageSource, /createHash\(['"]sha256['"]\)/, 'SHA-256 artifact hashing')

  const smokePath = 'tooling/smoke-desktop-packaged.mjs'
  const smoke = readRequired(smokePath)
  requirePattern(smokePath, smoke, /--manifest/, 'manifest-only input')
  requirePattern(smokePath, smoke, /copiedApplicationPath/, 'copied application consumption')
  requirePattern(smokePath, smoke, /executablePath/, 'manifest-selected executable')
  requirePattern(smokePath, smoke, /app\.isPackaged/, 'packaged-runtime assertion')
  requirePattern(smokePath, smoke, /applicationDigestSha256/, 'application digest verification')
  requirePattern(smokePath, smoke, /executableDigestSha256/, 'executable digest verification')
  requirePattern(smokePath, smoke, /assertOutsideRepository/, 'source-tree rejection')
  requirePattern(smokePath, smoke, /--user-data-dir/, 'disposable packaged profile')
  forbidPattern(smokePath, smoke, /electron-forge|pnpm\s+(?:run\s+)?(?:build|package|make)|vite|localhost|127\.0\.0\.1|webServer/, 'build or development-server path')
}

const usage = () => {
  console.error('Usage: node tooling/verify-desktop-harness.mjs --build-config | --test-config | --all')
  process.exitCode = 2
}

const mode = process.argv[2]
if (process.argv.length !== 3 || !['--build-config', '--test-config', '--all'].includes(mode)) {
  usage()
} else {
  if (mode === '--build-config' || mode === '--all') verifyBuildConfig()
  if (mode === '--test-config' || mode === '--all') verifyTestConfig()

  for (const pass of passes) console.log(`PASS ${pass}`)
  if (failures.length > 0) {
    for (const failure of failures) console.error(`FAIL ${failure}`)
    console.error(`Desktop harness verification failed: ${failures.length} invariant(s) missing`)
    process.exitCode = 1
  } else {
    console.log(`Desktop harness verification passed: ${passes.length} invariants`)
  }
}
