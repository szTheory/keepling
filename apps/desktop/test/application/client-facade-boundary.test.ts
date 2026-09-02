import { readFileSync, readdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

import { describe, expect, it } from 'vitest'

/**
 * Freezes the presentation-only ClientFacade boundary (D-26/D-27/D-30,
 * docs/architecture/REPOSITORY.md "Shared React UI -> narrow ClientFacade,
 * never Electron/browser implementation details"). Every source file under
 * `packages/web-ui/src` must stay free of browser transport/session/history
 * and Electron/preload/storage/lifecycle imports.
 */

const repoRoot = fileURLToPath(new URL('../../../../', import.meta.url))
const webUiSrc = join(repoRoot, 'packages', 'web-ui', 'src')

const listSourceFiles = (root: string): string[] => {
  const files: string[] = []
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    const entryPath = join(root, entry.name)
    if (entry.isDirectory()) {
      files.push(...listSourceFiles(entryPath))
    } else if (/\.(ts|tsx)$/.test(entry.name)) {
      files.push(entryPath)
    }
  }
  return files
}

const forbiddenPatterns: Array<{ label: string; pattern: RegExp }> = [
  { label: "import from 'electron'", pattern: /from ['"]electron['"]/ },
  { label: 'ipcRenderer usage', pattern: /ipcRenderer/ },
  { label: 'contextBridge usage', pattern: /contextBridge/ },
  { label: 'node:sqlite import', pattern: /node:sqlite/ },
  { label: 'better-sqlite3 import', pattern: /better-sqlite3/ },
  { label: 'preload module import', pattern: /\/preload\// },
  { label: 'desktop main module import', pattern: /apps\/desktop\/main\// },
  { label: 'store-worker module import', pattern: /store-worker/ },
  { label: 'raw fetch call', pattern: /\bfetch\(/ },
  { label: 'XMLHttpRequest usage', pattern: /XMLHttpRequest/ },
  { label: 'document.cookie usage', pattern: /document\.cookie/ },
  { label: 'localStorage usage', pattern: /\blocalStorage\b/ },
  { label: 'sessionStorage usage', pattern: /\bsessionStorage\b/ },
  { label: 'window.history usage', pattern: /window\.history/ },
  { label: 'browser session/submission import', pattern: /@\/(api\/keepling|commands\/submission)/ },
  { label: 'same-origin credentials literal', pattern: /credentials:\s*['"]same-origin['"]/ },
]

describe('ClientFacade presentation-only import boundary', () => {
  it('finds the shared web-ui package on disk', () => {
    expect(() => readdirSync(webUiSrc)).not.toThrow()
  })

  it('keeps packages/web-ui/src free of browser and Electron platform imports', () => {
    const files = listSourceFiles(webUiSrc)
    expect(files.length).toBeGreaterThan(0)

    const violations: string[] = []
    for (const file of files) {
      const source = readFileSync(file, 'utf8')
      for (const { label, pattern } of forbiddenPatterns) {
        if (pattern.test(source)) {
          violations.push(`${file.replace(repoRoot, '')}: ${label}`)
        }
      }
    }

    expect(violations).toEqual([])
  })

  it('exposes only named snapshot/subscription and task/navigation/recovery operations', () => {
    const facadeSource = readFileSync(join(webUiSrc, 'ClientFacade.ts'), 'utf8')

    expect(facadeSource).toContain('interface ClientFacade')
    for (const member of [
      'captureTask(',
      'getSnapshot(',
      'selectTask(',
      'subscribe(',
      'getRecoveryAvailability(',
      'subscribeRecovery(',
    ]) {
      expect(facadeSource).toContain(member)
    }

    // No generic escape hatches: no raw IPC-shaped, channel-shaped, or `any`-typed members.
    expect(facadeSource).not.toMatch(/\bany\b/)
    expect(facadeSource).not.toMatch(/channel/i)
  })

  it('keeps the desktop workspace-tracer fixture free of Electron/preload imports', () => {
    const fixturePath = join(dirname(fileURLToPath(import.meta.url)), '..', 'fixtures', 'desktopClientFacade.ts')
    const source = readFileSync(fixturePath, 'utf8')

    for (const { label, pattern } of forbiddenPatterns.filter(
      ({ label }) => label !== 'store-worker module import' && label !== 'desktop main module import',
    )) {
      expect(source, `fixture should not contain: ${label}`).not.toMatch(pattern)
    }
  })
})
