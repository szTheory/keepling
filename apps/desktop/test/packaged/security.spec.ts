import { existsSync, mkdirSync, readdirSync, readFileSync, realpathSync } from 'node:fs'
import { join } from 'node:path'
import { test, expect, _electron as electron, type ElectronApplication } from '@playwright/test'

/**
 * Packaged security/privacy boundary proof (D-45/D-46/D-48, MAC-03/MAC-04/
 * MAC-05, T-KPL03-06-04). Every assertion here runs against the SAME exact
 * copied `.app` the manifest selects -- never a rebuild, never a dev
 * server, never `dist/` inside the source tree. Unlike `test/ipc/
 * hostile-bridge.test.ts` (which proves the pure security-decision
 * functions in isolation), this file proves those decisions are ACTUALLY
 * wired into the real packaged runtime: session-level CSP, the custom
 * `app://renderer` protocol, sandboxed/no-Node-integration webPreferences,
 * and deny-by-default navigation/window-open/permission handlers.
 *
 * KNOWN, DISCLOSED SCOPE LIMIT (see 03-06-SUMMARY.md): `main/adapters/
 * credentials.ts#SafeStorageCredentialAdapter` is built and unit-tested
 * (03-02) but is NOT constructed or passed to `DesktopApplication` in
 * `main/index.ts#bootstrap()` -- grep confirms zero references. It is
 * therefore not present in the packaged main bundle at all (Vite only
 * bundles what `main/index.ts` actually imports), and this file cannot
 * exercise it against the real packaged runtime. This is NOT a stub or a
 * skipped case being hidden -- it is a genuinely unreachable feature,
 * structurally identical to GAP-1 (O-1/O-11/O-12; see `.continue-here.md`).
 * This file instead proves what IS reachable: the OS Keychain-backed
 * `safeStorage` primitive itself is available in the packaged runtime (a
 * real, necessary precondition for the adapter to ever work once wired),
 * and that no plaintext credential-shaped content is ever written to the
 * packaged profile during ordinary use.
 */

type PackageManifest = {
  applicationDigestSha256: string
  copiedApplicationPath: string
  embeddedVersions: Record<string, string>
  executablePath: string
  sourceRevision: string
}

const manifestPath = process.env.KEEPLING_PACKAGE_MANIFEST
if (!manifestPath) throw new Error('KEEPLING_PACKAGE_MANIFEST is required for packaged tests')
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8')) as PackageManifest
const profileRoot = process.env.KEEPLING_TEST_USER_DATA_DIR
if (!profileRoot) throw new Error('KEEPLING_TEST_USER_DATA_DIR is required for packaged tests')

const allocateProfile = (lane: string): string => {
  const profilePath = join(profileRoot, `security-${lane.replaceAll(/[^a-z0-9-]/gi, '-')}`)
  mkdirSync(profilePath, { recursive: true })
  return profilePath
}

const launch = async (profilePath: string): Promise<ElectronApplication> => electron.launch({
  args: [`--user-data-dir=${profilePath}`],
  env: {
    ...process.env,
    KEEPLING_EXPECT_PACKAGED: '1',
    KEEPLING_TEST_SYNC_MODE: 'offline',
    KEEPLING_TEST_USER_DATA_DIR: profilePath,
  },
  executablePath: manifest.executablePath,
  timeout: 30_000,
})

test('the packaged runtime reports app.isPackaged and the main window loads only from the app://renderer protocol', async () => {
  const application = await launch(allocateProfile('is-packaged-protocol'))
  try {
    const window = await application.firstWindow()
    const isPackaged = await application.evaluate(({ app }) => app.isPackaged)
    expect(isPackaged).toBe(true)
    expect(window.url()).toMatch(/^app:\/\/renderer\//)
  } finally {
    await application.close()
  }
})

test('the packaged session serves a Content-Security-Policy header, and the renderer has no Node integration or generic IPC escape hatch', async () => {
  const application = await launch(allocateProfile('csp-sandbox'))
  try {
    const window = await application.firstWindow()

    // `net.fetch` from the MAIN process does not route through the same
    // custom-protocol handling a BrowserWindow navigation does (it throws
    // net::ERR_UNKNOWN_URL_SCHEME for the privileged `app://` scheme), so
    // this captures the REAL response the renderer's own navigation
    // receives via Playwright's CDP-backed response listener -- proving the
    // header the browsing context actually gets, not a synthetic fetch.
    const [response] = await Promise.all([
      window.waitForResponse((candidate) => candidate.url().startsWith('app://renderer/index.html')),
      window.reload(),
    ])
    const headers = await response.allHeaders()
    const csp = headers['content-security-policy']
    expect(csp).toBeDefined()
    expect(csp).toContain("default-src 'self'")
    expect(csp).toContain("object-src 'none'")
    expect(csp).toContain("frame-ancestors 'none'")

    // Real functional proof of sandbox + contextIsolation + nodeIntegration:
    // false -- not a read of the BrowserWindow constructor options (which a
    // later refactor could silently drop while still "reading" true), but
    // that Node globals are genuinely absent from the renderer's own global
    // scope.
    const nodeSurface = await window.evaluate(() => ({
      hasProcess: typeof (globalThis as unknown as { process?: unknown }).process !== 'undefined',
      hasRequire: typeof (globalThis as unknown as { require?: unknown }).require !== 'undefined',
    }))
    expect(nodeSurface).toEqual({ hasProcess: false, hasRequire: false })

    // The preload bridge exposes only the named `keepling`/`keeplingUtility`
    // surface -- never a generic ipcRenderer.invoke/send escape hatch (the
    // same invariant `test/ipc/hostile-bridge.test.ts`'s static scan proves
    // at the source level; this proves it in the actual packaged renderer).
    const bridgeSurface = await window.evaluate(() => ({
      exposesIpcRenderer: typeof (globalThis as unknown as { ipcRenderer?: unknown }).ipcRenderer !== 'undefined',
      exposesKeepling: typeof (globalThis as unknown as { keepling?: unknown }).keepling === 'object',
    }))
    expect(bridgeSurface).toEqual({ exposesIpcRenderer: false, exposesKeepling: true })
  } finally {
    await application.close()
  }
})

test('the packaged main window denies unexpected navigation and window creation', async () => {
  const application = await launch(allocateProfile('navigation-window'))
  try {
    const window = await application.firstWindow()
    const urlBefore = window.url()
    const windowCountBefore = await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows().length)

    await window.evaluate(() => window.open('https://attacker.example'))
    await window.waitForTimeout(200)
    expect(await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows().length)).toBe(windowCountBefore)

    // will-navigate is denied at the BrowserWindow level (main-window.ts);
    // the document location must be unchanged after the attempt settles.
    await window.evaluate((target) => {
      window.location.href = target
    }, 'https://attacker.example/')
    await window.waitForTimeout(200)
    expect(window.url()).toBe(urlBefore)
  } finally {
    await application.close()
  }
})

test('the packaged session denies an unrequested-permission surface (geolocation) by default', async () => {
  const application = await launch(allocateProfile('permissions'))
  try {
    const window = await application.firstWindow()
    const outcome = await window.evaluate(
      () => new Promise((resolve) => {
        navigator.geolocation.getCurrentPosition(
          () => resolve('granted'),
          (error: GeolocationPositionError) => resolve(`denied:${error.code}`),
          { timeout: 5_000 },
        )
      }),
    )
    expect(outcome).not.toBe('granted')
  } finally {
    await application.close()
  }
})

test('the packaged worker/SQLite runtime loads its worker script and migration from the packaged resources layout, not the source tree', async () => {
  const application = await launch(allocateProfile('worker-sqlite-layout'))
  try {
    const isPackaged = await application.evaluate(({ app }) => app.isPackaged)
    const resourcesPath = await application.evaluate(() => process.resourcesPath)
    expect(isPackaged).toBe(true)
    expect(existsSync(join(resourcesPath, 'worker', 'index.cjs'))).toBe(true)
    expect(existsSync(join(resourcesPath, 'migrations', '0001_initial.sql'))).toBe(true)
    expect(resourcesPath.includes('apps/desktop/main')).toBe(false)
    // macOS resolves `/var` -> `/private/var` for real filesystem paths, so
    // compare realpaths rather than a raw prefix (the manifest's tmpdir()
    // path and the packaged process's own resolved resourcesPath otherwise
    // legitimately differ only by that symlink).
    expect(realpathSync(resourcesPath).startsWith(realpathSync(manifest.copiedApplicationPath))).toBe(true)

    // A live round trip through that exact worker/migration pair: if the
    // packaged path resolution were wrong, this capture would throw or the
    // task would never appear rather than silently no-op.
    const window = await application.firstWindow()
    await window.getByLabel('What do you want to keep?').fill('Prove the worker path')
    await window.getByRole('button', { name: 'Add Task' }).click()
    await expect(window.getByText('Prove the worker path')).toBeVisible()
  } finally {
    await application.close()
  }
})

test('safeStorage is available in the packaged runtime, and no plaintext credential-shaped content is written to the packaged profile', async () => {
  const profilePath = allocateProfile('safe-storage-privacy')
  const application = await launch(profilePath)
  try {
    const window = await application.firstWindow()
    await window.getByLabel('What do you want to keep?').fill('Exercise the packaged profile')
    await window.getByRole('button', { name: 'Add Task' }).click()
    await expect(window.getByText('Exercise the packaged profile')).toBeVisible()

    // A real, necessary precondition for `SafeStorageCredentialAdapter`
    // (03-02) to ever work once wired: the OS Keychain-backed primitive it
    // depends on is genuinely present in this packaged process, not merely
    // assumed.
    const encryptionAvailable = await application.evaluate(({ safeStorage }) => safeStorage.isEncryptionAvailable())
    expect(encryptionAvailable).toBe(true)

    // Privacy-negative surface: nothing under the packaged profile ever
    // contains an obviously-plaintext bearer/access-token-shaped string.
    // This is scoped to what this plan's normal daily-loop use can produce
    // today (capture/edit/complete text only) -- it does not, and cannot,
    // prove a credential adapter that isn't wired keeps a real token safe.
    const suspiciousFiles: string[] = []
    const walk = (directory: string) => {
      for (const entry of readdirSync(directory, { withFileTypes: true })) {
        const path = join(directory, entry.name)
        if (entry.isDirectory()) {
          walk(path)
          continue
        }
        if (!entry.isFile()) continue
        const content = readFileSync(path, 'utf8').toLowerCase()
        if (/bearer\s+[a-z0-9._-]{16,}/.test(content) || content.includes('"access_token"')) {
          suspiciousFiles.push(path)
        }
      }
    }
    if (existsSync(profilePath)) walk(profilePath)
    expect(suspiciousFiles).toEqual([])
  } finally {
    await application.close()
  }
})
