/// <reference types="node" />

import { readFileSync, readdirSync } from 'node:fs'
import { join, relative, resolve } from 'node:path'

import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import ts from 'typescript'
import { describe, expect, it, vi } from 'vitest'

import tokens from '../../../../packages/design-tokens/tokens.json'
import AppShell from '@/app/AppShell'

vi.mock('@/features/recovery/RecoveryStrip', () => ({
  default: () => <div>Recovery action</div>,
}))

vi.mock('@/features/sessions/SessionList', () => ({
  default: ({ onRequestLogout }: { onRequestLogout: () => void }) => (
    <button onClick={onRequestLogout} type="button">
      Log out this browser
    </button>
  ),
}))

const repositoryFile = (relativePath: string) =>
  readFileSync(resolve(process.cwd(), '../..', relativePath), 'utf8')

type TokenGroup = Record<string, { $value: string }>

const cssTokenName = (name: string) => name.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`)

const tokenDeclarations = (group: TokenGroup, prefix: string) =>
  Object.entries(group).map(
    ([name, token]) => `  --keepling-${prefix}-${cssTokenName(name)}: ${token.$value};`,
  )

const generateDesignTokenCss = (source: typeof tokens) => {
  const lightColorNames = Object.keys(source.color.light)
  const rootDeclarations = [
    ...tokenDeclarations(source.space, 'space'),
    ...tokenDeclarations(source.typography, 'type'),
    ...tokenDeclarations(source.layout, 'layout'),
    ...tokenDeclarations(source.motion, 'motion'),
    ...tokenDeclarations(source.color.light, 'color'),
    ...tokenDeclarations(source.color.dark, 'dark-color'),
  ].join('\n')
  const darkAliases = lightColorNames
    .map((name) => {
      const cssName = cssTokenName(name)
      return `    --keepling-color-${cssName}: var(--keepling-dark-color-${cssName});`
    })
    .join('\n')
  const explicitDarkAliases = darkAliases.replace(/^ {4}/gm, '  ')

  return `/* Generated from tokens.json. Keep values storage-neutral and semantic. */
:root {
${rootDeclarations}
}

@media (prefers-color-scheme: dark) {
  :root:not(.light) {
${darkAliases}
  }
}

.dark {
${explicitDarkAliases}
}
`
}

const productionSource = (relativePath: string) =>
  repositoryFile(relativePath)
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/^\s*\/\/.*$/gm, '')

const offScaleFeatureUtilities =
  /\b(?:text-xs|font-medium|gap-(?:1\.5|2\.5|3|5)|space-[xy]-(?:1\.5|2\.5|3|5)|m[trblxy]?-(?:1\.5|2\.5|3|5)|p[trblxy]?-(?:1\.5|2\.5|3|5)|text-white)\b/

const productionTsxFiles = () => {
  const sourceRoot = resolve(process.cwd(), 'src')
  const files: string[] = []
  const visit = (directory: string) => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name)
      if (entry.isDirectory()) {
        if (entry.name !== 'test' && entry.name !== 'generated') visit(path)
      } else if (
        entry.name.endsWith('.tsx') &&
        !entry.name.endsWith('.test.tsx') &&
        !entry.name.endsWith('.spec.tsx')
      ) {
        files.push(path)
      }
    }
  }

  visit(sourceRoot)
  return files.sort()
}

const classNameRegions = (path: string) => {
  const source = readFileSync(path, 'utf8')
  const sourceFile = ts.createSourceFile(path, source, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX)
  const regions: string[] = []
  const visit = (node: ts.Node) => {
    if (
      ts.isJsxAttribute(node) &&
      node.name.getText(sourceFile) === 'className' &&
      node.initializer
    ) {
      regions.push(node.initializer.getText(sourceFile))
    }
    ts.forEachChild(node, visit)
  }

  visit(sourceFile)
  return regions.join('\n')
}

const semanticArbitraryClassAllowlist = {
  'duration-[var(--keepling-motion-overlay)]': {
    contract: '180ms',
    reason: 'Dialog and drawer motion use the named overlay duration token.',
  },
  'hover:bg-[color-mix(in_oklch,var(--secondary),var(--foreground)_5%)]': {
    contract: 'secondary',
    reason: 'The quiet secondary hover derives from semantic theme roles.',
  },
  'leading-[1.2]': {
    contract: '1.2',
    reason: 'Display titles use the UI-SPEC display line height.',
  },
  'min-h-[3.25rem]': {
    contract: '52px',
    reason: 'Task rows have the UI-SPEC 52px minimum independent of control targets.',
  },
  'min-h-[var(--keepling-layout-target)]': {
    contract: '44px',
    reason: 'Interactive controls consume the named minimum-target token.',
  },
  'text-[1.75rem]': {
    contract: '28px',
    reason: 'Route and authentication titles use the UI-SPEC display size.',
  },
  'text-[length:var(--keepling-type-heading)]': {
    contract: '20px',
    reason: 'Shell headings consume the named heading token.',
  },
  'text-[length:var(--keepling-type-label)]': {
    contract: '14px',
    reason: 'Navigation and control labels consume the named label token.',
  },
  'w-[min(22rem,calc(100vw-var(--keepling-space-xl)))]': {
    contract: '32px',
    reason: 'The modal navigation drawer preserves the named narrow-screen gutter.',
  },
  'w-[var(--keepling-layout-target)]': {
    contract: '44px',
    reason: 'Icon buttons consume the named minimum-target token.',
  },
  'w-[var(--keepling-space-2xl)]': {
    contract: '48px',
    reason: 'The large icon button consumes a declared spacing token.',
  },
  'z-[60]': {
    contract: 'stacking-only',
    reason: 'The skip link stacking level is not a spatial or typography value.',
  },
} as const

describe('approved Phase 1 UI contract', () => {
  it('opens semantic primary navigation in a modal drawer and restores trigger focus', async () => {
    const user = userEvent.setup()
    window.history.replaceState({}, '', '/today')
    render(<AppShell csrfToken="csrf" onLoggedOut={vi.fn()} />)

    const trigger = screen.getByRole('button', { name: 'Open navigation' })
    await user.click(trigger)

    const navigation = screen.getByRole('navigation', { name: 'Primary navigation' })
    for (const label of [
      'Inbox',
      'Today',
      'Upcoming',
      'Projects',
      'Tags',
      'Completed',
      'Trash',
      'Sessions',
    ]) {
      expect(within(navigation).getByRole('link', { name: label })).toBeInTheDocument()
    }
    expect(within(navigation).getByRole('link', { name: 'Today' })).toHaveAttribute(
      'aria-current',
      'page',
    )
    await waitFor(() => {
      expect(within(navigation).getByRole('link', { name: 'Inbox' })).toHaveFocus()
    })

    await user.tab({ shift: true })
    await waitFor(() => {
      expect(screen.getByRole('button', { name: 'Close navigation' })).toHaveFocus()
    })
    await user.keyboard('{Escape}')
    expect(trigger).toHaveFocus()
  })

  it('keeps DTCG source and generated CSS in exact semantic sync', () => {
    const generatedTokens = repositoryFile('packages/design-tokens/css.css')
    expect(generatedTokens).toBe(generateDesignTokenCss(tokens))
    expect(Object.values(tokens.space).map(({ $value }) => $value)).toEqual([
      '4px',
      '8px',
      '16px',
      '24px',
      '32px',
      '48px',
      '64px',
    ])
    expect(Object.values(tokens.typography).map(({ $value }) => $value)).toEqual([
      '14px',
      '16px',
      '20px',
      '28px',
    ])
    expect(tokens.layout).toMatchObject({
      compactWideStart: { $value: '1024px' },
      detailMin: { $value: '480px' },
      listMax: { $value: '440px' },
      listMin: { $value: '360px' },
      nav: { $value: '224px' },
      persistentNavStart: { $value: '1064px' },
      target: { $value: '44px' },
    })
    expect(tokens.motion).toMatchObject({
      direct: { $value: '160ms' },
      overlay: { $value: '180ms' },
      reduced: { $value: '100ms' },
    })
    expect(tokens.color.light).toMatchObject({
      border: { $value: '#877b6d' },
      destructiveText: { $value: '#ffffff' },
      muted: { $value: '#eee8de' },
      secondary: { $value: '#fffcf7' },
    })
    expect(tokens.color.dark).toMatchObject({
      border: { $value: '#786f69' },
      destructiveText: { $value: '#24201d' },
      muted: { $value: '#312b27' },
      secondary: { $value: '#24201d' },
    })
  })

  it('keeps shared buttons and consequential surfaces on declared visual values', () => {
    const button = productionSource('apps/web/src/components/ui/button.tsx')
    const consequentialSurfaces = [
      'apps/web/src/components/ui/alert-dialog.tsx',
      'apps/web/src/app/WorkspaceShell.tsx',
      'apps/web/src/app/AppShell.tsx',
      'apps/web/src/features/tasks/TaskEditor.tsx',
    ]
      .map(productionSource)
      .join('\n')

    expect(button).toContain('text-sm font-semibold')
    expect(button).toContain('min-h-[var(--keepling-layout-target)]')
    expect(button).toContain('text-destructive-foreground')
    expect(button).not.toMatch(/\b(?:text-xs|font-medium|gap-1\.5|p[lr]-2\.5|h-[6-9]|size-[6-9])\b/)
    expect(consequentialSurfaces).not.toMatch(/\b(?:text-white|font-medium|text-xs)\b/)
    expect(consequentialSurfaces).not.toContain('41.5rem')

    const css = productionSource('apps/web/src/index.css')
    for (const variable of [
      'secondary',
      'secondary-foreground',
      'muted',
      'accent',
      'accent-foreground',
      'destructive-foreground',
      'border',
      'input',
    ]) {
      expect(css).toMatch(
        new RegExp(`--${variable}: var\\(--keepling-color-[a-z-]+\\);`),
      )
    }
  })

  it('keeps every authentication surface on the declared type and spacing scales', () => {
    const authentication = [
      'apps/web/src/features/auth/LoginForm.tsx',
      'apps/web/src/features/auth/Reauthenticate.tsx',
      'apps/web/src/features/auth/RecoveryReset.tsx',
      'apps/web/src/features/auth/SetupForm.tsx',
    ]
      .map(productionSource)
      .join('\n')

    expect(authentication).not.toMatch(offScaleFeatureUtilities)
    expect(authentication).not.toMatch(/\b(?:h|size)-(?:6|7|8|9|10)\b/)
    expect(authentication).not.toMatch(/\bmin-h-(?:6|7|8|9|10)\b/)
  })

  it('keeps list, activity, and organization surfaces on the declared scales', () => {
    for (const relativePath of [
      'apps/web/src/features/activity/ActivityList.tsx',
      'apps/web/src/features/lists/TaskList.tsx',
      'apps/web/src/features/lists/TrashList.tsx',
      'apps/web/src/features/organizations/OrganizationFields.tsx',
    ]) {
      const match = productionSource(relativePath).match(offScaleFeatureUtilities)
      expect(match?.[0], `${relativePath}: ${match?.[0]}`).toBeUndefined()
    }
  })

  it('rejects visual-contract drift across every production TSX class region', () => {
    const tokenTruth = `${JSON.stringify(tokens)}\n${repositoryFile('.planning/phases/KPL-01-one-trustworthy-task/01-UI-SPEC.md')}`
    for (const [utility, exception] of Object.entries(semanticArbitraryClassAllowlist)) {
      expect(exception.reason, `${utility} requires a semantic reason`).not.toHaveLength(0)
      if (exception.contract !== 'stacking-only') {
        expect(tokenTruth, `${utility} must cite a declared token value`).toContain(exception.contract)
      }
    }

    for (const path of productionTsxFiles()) {
      const source = classNameRegions(path)
      const repositoryPath = relative(resolve(process.cwd(), '../..'), path)
      const offScale = source.match(offScaleFeatureUtilities)?.[0]
      expect(offScale, `${repositoryPath}: ${offScale}`).toBeUndefined()
      const fixedWorkspace = source.includes('41.5rem') ? '41.5rem' : undefined
      expect(fixedWorkspace, `${repositoryPath}: ${fixedWorkspace}`).toBeUndefined()

      const smallTarget = source.match(/\b(?:h|size)-(?:6|7|8|9|10)\b/)?.[0]
      expect(smallTarget, `${repositoryPath}: ${smallTarget}`).toBeUndefined()

      const arbitraryUtilities = source.match(/[^\s"'`]+-\[[^\]\s]+\][^\s"'`]*/g) ?? []
      for (const utility of arbitraryUtilities) {
        if (utility.startsWith('[') || utility.includes('aria-[') || utility.includes('data-[')) {
          continue
        }
        expect(
          utility in semanticArbitraryClassAllowlist,
          `${repositoryPath}: undocumented arbitrary utility ${utility}`,
        ).toBe(true)
      }
    }
  })

  it('exposes reachable landmarks, navigation, 44px targets, and one live region', () => {
    window.history.replaceState({}, '', '/settings/sessions')
    render(<AppShell csrfToken="csrf" onLoggedOut={vi.fn()} />)

    expect(screen.getByRole('banner')).toBeInTheDocument()
    const navigation = screen.getByRole('navigation', { name: 'Keepling' })
    for (const label of [
      'Inbox',
      'Today',
      'Upcoming',
      'Completed',
      'Projects',
      'Tags',
      'Trash',
      'Sessions',
    ]) {
      expect(within(navigation).getByRole('link', { name: label })).toBeInTheDocument()
    }
    expect(within(navigation).getByRole('link', { name: 'Sessions' })).toHaveAttribute(
      'aria-current',
      'page',
    )
    expect(screen.getByRole('main')).toHaveAttribute('id', 'main-content')
    expect(screen.getByRole('status')).toHaveAttribute('aria-live', 'polite')

    for (const link of within(navigation).getAllByRole('link')) {
      expect(link).toHaveClass('min-h-[var(--keepling-layout-target)]')
    }
  })

  it('keeps dirty-navigation choice exact and initially focuses Keep editing', async () => {
    const user = userEvent.setup()
    window.history.replaceState({}, '', '/settings/sessions')
    render(<AppShell csrfToken="csrf" hasDirtyWork onLoggedOut={vi.fn()} />)

    await user.click(screen.getByRole('link', { name: 'Inbox' }))

    const dialog = screen.getByRole('alertdialog', { name: 'Discard unsaved changes?' })
    expect(dialog).toHaveTextContent('These edits haven’t been saved.')
    expect(within(dialog).getByRole('button', { name: 'Save changes' })).toBeInTheDocument()
    expect(within(dialog).getByRole('button', { name: 'Discard changes' })).toBeInTheDocument()
    await waitFor(() =>
      expect(within(dialog).getByRole('button', { name: 'Keep editing' })).toHaveFocus(),
    )
  })

  it('makes current-browser logout explicit and preserves dirty-work choices', async () => {
    const user = userEvent.setup()
    window.history.replaceState({}, '', '/settings/sessions')
    render(<AppShell csrfToken="csrf" hasDirtyWork onLoggedOut={vi.fn()} />)

    const trigger = screen.getByRole('button', { name: 'Log out this browser' })
    await user.click(trigger)

    const dialog = screen.getByRole('alertdialog', { name: 'Log out this browser?' })
    expect(dialog).toHaveTextContent(
      'Unsaved edits remain unless you save them before this browser signs out.',
    )
    expect(within(dialog).getByRole('button', { name: 'Save changes' })).toBeVisible()
    expect(
      within(dialog).getByRole('button', { name: 'Discard changes and log out' }),
    ).toBeVisible()
    await waitFor(() =>
      expect(within(dialog).getByRole('button', { name: 'Keep editing' })).toHaveFocus(),
    )
    await user.keyboard('{Escape}')
    await waitFor(() => expect(trigger).toHaveFocus())
  })

  it('encodes theme, forced-color, zoom/reflow, focus, and reduced-motion contracts', () => {
    const css = `${repositoryFile('packages/design-tokens/css.css')}\n${repositoryFile('apps/web/src/index.css')}`

    expect(css).toContain('@media (prefers-color-scheme: dark)')
    expect(css).toContain('@media (forced-colors: active)')
    expect(css).toContain('@media (prefers-reduced-motion: reduce)')
    expect(css).toContain('@media (min-width: 1024px)')
    expect(css).toContain('@media (min-width: 1064px)')
    expect(css).toContain('outline: 2px solid var(--ring)')
    expect(css).toContain('min-width: 0')
    expect(css).toContain('overflow-x: hidden')
  })

  it('keeps the canonical workspace free of 320px fallbacks and fixed-width arithmetic', () => {
    const css = repositoryFile('apps/web/src/index.css')
    const routes = repositoryFile('apps/web/src/app/routes.tsx')
    const editor = repositoryFile('apps/web/src/features/tasks/TaskEditor.tsx')

    expect(css).toContain(
      'grid-template-columns: minmax(var(--keepling-layout-list-min), var(--keepling-layout-list-max)) minmax(var(--keepling-layout-detail-min), 1fr)',
    )
    expect(`${css}\n${routes}\n${editor}`).not.toContain('41.5rem')
    expect(css).not.toMatch(/(?:320px|20rem)/)
  })

  it('routes authenticated list and task surfaces through one shell-owned main landmark', () => {
    const app = repositoryFile('apps/web/src/App.tsx')
    const routes = repositoryFile('apps/web/src/app/routes.tsx')
    const shell = repositoryFile('apps/web/src/app/WorkspaceShell.tsx')

    expect(app).toContain('routeContent={routeContent}')
    expect(routes).toContain("renderAuthenticatedContent(listLayout('inbox'))")
    expect(routes).toContain('<TaskEditor')
    expect(routes).toContain('embedded')
    expect(shell).toContain('<main')
    expect(shell).toContain('id="main-content"')
    expect(routes).not.toMatch(/return withInterruption\(\s*<(?:TaskList|TaskEditor)/)
  })
})
