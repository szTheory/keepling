#!/usr/bin/env node
/**
 * tooling/cross-adapter/electron-driver.mjs (06-05-PLAN.md Task 2)
 *
 * The live Electron leg: launches the PACKAGED Mac app
 * (`apps/desktop/out/**\/*.app`) against a disposable profile, drives it
 * through its real menu, its real Settings pane, and its real task list --
 * the same shipped surface a person uses -- and lets the real
 * `KeeplingSyncAdapter` talk to the real server this lane already booted.
 * No stubbed fetch, no placeholder host, no hand-injected bearer, no
 * `KEEPLING_TEST_SYNC_MODE`. `guardAgainstShortcuts` (extended onto this
 * file by 06-05-PLAN.md Task 1) checks that at every invocation, not just
 * once at authoring time.
 *
 * Modelled on `apps/desktop/test/real-stack/real-stack-sync.spec.ts`
 * (D-36): the same disposable-profile discipline, the same
 * `shell.openExternal` interception to play the "system browser" half of
 * RFC 8252, and the same small forwarding proxy used there to simulate a
 * dropped connection. The one structural difference is deliberate: that
 * spec boots its OWN Phoenix/PostgreSQL instance per test file, because it
 * owns the whole real-stack lane. This driver instead drives the app
 * against the ONE server `verify-cross-adapter-phase.mjs` already booted
 * for every leg, using the harness's own already-authenticated browser
 * session to play the browser half of sign-in -- so all four legs are
 * proven to agree about the SAME server revision, which is the entire
 * point of the cross-adapter lane (D-27).
 *
 * The forwarding proxy here exists for exactly one reason: the shared
 * `update_stale_expected_revision` scenario advances a task's revision OUT
 * OF BAND, between this adapter's own capture and its own `staleUpdate`
 * call, and a real UI-driven client can only be genuinely stale (rather
 * than told a revision it never held) by being unable to pull that change
 * before it acts -- exactly the offline-conflict technique
 * `real-stack-sync.spec.ts` already uses for its own conflict case.
 */
import { existsSync, readdirSync } from 'node:fs'
import { mkdtemp, rm } from 'node:fs/promises'
import { createServer, request as httpRequest } from 'node:http'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import process from 'node:process'
import { _electron as electron } from 'playwright'
import { blocked } from '../mcp-client/client.mjs'

const repositoryRoot = join(import.meta.dirname, '..', '..')

/** Waits for `fn()` to return a truthy value, polling on an interval. Throws on timeout -- this driver never silently gives up and reports success. */
const pollUntil = async (fn, { intervalMs = 500, label, timeoutMs = 30_000 } = {}) => {
  const deadline = Date.now() + timeoutMs
  for (;;) {
    // eslint-disable-next-line no-await-in-loop
    const value = await fn()
    if (value) return value
    if (Date.now() > deadline) throw new Error(`pollUntil timed out waiting for: ${label ?? 'condition'}`)
    // eslint-disable-next-line no-await-in-loop
    await new Promise((resolveTimeout) => setTimeout(resolveTimeout, intervalMs))
  }
}

/**
 * Locates the packaged executable under `apps/desktop/out/<platform>/
 * *.app/Contents/MacOS/<executable>`. Refuses to guess when the layout is
 * not exactly what `tooling/package-desktop.mjs` produces -- a silently
 * wrong executable path is worse than a loud BLOCKED.
 */
const findPackagedExecutable = (outRoot) => {
  const platformDirs = readdirSync(outRoot, { withFileTypes: true }).filter((entry) => entry.isDirectory())
  for (const platformDir of platformDirs) {
    const platformPath = join(outRoot, platformDir.name)
    const appBundle = readdirSync(platformPath, { withFileTypes: true }).find((entry) => entry.isDirectory() && entry.name.endsWith('.app'))
    if (!appBundle) continue
    const macosDir = join(platformPath, appBundle.name, 'Contents', 'MacOS')
    if (!existsSync(macosDir)) continue
    const executables = readdirSync(macosDir)
    if (executables.length === 1) return join(macosDir, executables[0])
  }
  throw blocked(`no packaged Electron executable found under ${outRoot} -- expected <platform>/*.app/Contents/MacOS/<name>`)
}

/**
 * A real forwarding HTTP proxy in front of the real server this lane
 * already booted -- never a fake server, never an answer on the server's
 * behalf. Closing it is the ONLY way this driver makes the app's
 * connection to the real server fail, exactly mirroring
 * `real-stack-sync.spec.ts`'s `createGate`.
 */
const createGate = (targetOrigin, gatePort) => {
  const target = new URL(targetOrigin)
  let server
  const build = () =>
    createServer((incoming, outgoing) => {
      const upstream = httpRequest(
        {
          headers: incoming.headers,
          host: target.hostname,
          method: incoming.method,
          path: incoming.url,
          port: target.port,
        },
        (response) => {
          outgoing.writeHead(response.statusCode ?? 502, response.headers)
          response.pipe(outgoing)
        },
      )
      upstream.once('error', () => outgoing.destroy())
      incoming.pipe(upstream)
    })
  return {
    close: async () => {
      const current = server
      server = undefined
      if (!current) return
      current.closeAllConnections()
      await new Promise((resolveClose) => current.close(() => resolveClose()))
    },
    open: async () => {
      if (server) return
      const next = build()
      await new Promise((resolveOpen, reject) => {
        next.once('error', reject)
        next.listen(gatePort, '127.0.0.1', () => resolveOpen())
      })
      server = next
    },
  }
}

/**
 * Plays the "system browser" half of RFC 8252 with the harness's OWN
 * already-authenticated session, so the desktop client's device grant is
 * issued against the SAME account and the SAME server revision every other
 * leg observes. Every byte on the app's side is real: it builds the
 * authorization URL itself, hands it to `shell.openExternal`, and receives
 * the `keepling://auth/callback` through its own real `open-url` handler.
 */
const signIn = async (application, gateOrigin, sessionCookie) => {
  const patched = await application.evaluate(({ shell }) => {
    globalThis.__openedExternal = []
    try {
      shell.openExternal = async (url) => {
        globalThis.__openedExternal.push(url)
      }
      return true
    } catch {
      return false
    }
  })
  if (!patched) throw new Error('electron-driver: shell.openExternal was not interceptable')

  const [settings] = await Promise.all([
    application.waitForEvent('window', { predicate: (page) => page.url().includes('view=settings') }),
    application.evaluate(({ Menu }) => {
      const find = (items) => {
        for (const item of items) {
          if (item.label === 'Settings…') return item
          const nested = item.submenu ? find(item.submenu.items) : null
          if (nested) return nested
        }
        return null
      }
      const item = find(Menu.getApplicationMenu()?.items ?? [])
      if (!item) throw new Error('Settings menu item not found')
      item.click()
    }),
  ])
  await settings.waitForLoadState('domcontentloaded')
  await settings.getByLabel('Keepling server address').fill(gateOrigin)
  await settings.getByRole('button', { name: 'Connect…' }).click()

  const authorizationUrl = await pollUntil(
    () => application.evaluate(() => globalThis.__openedExternal?.[0] ?? null),
    { label: 'shell.openExternal to be called with the authorization URL', timeoutMs: 30_000 },
  )

  const authorize = await fetch(authorizationUrl, { headers: { Cookie: sessionCookie }, redirect: 'manual' })
  if (authorize.status !== 302) throw new Error(`electron-driver: /oauth/authorize returned ${String(authorize.status)} instead of a redirect`)
  const callbackUrl = authorize.headers.get('location') ?? ''
  if (!callbackUrl.startsWith('keepling://auth/callback')) {
    throw new Error(`electron-driver: unexpected authorization callback: ${callbackUrl}`)
  }

  await application.evaluate(({ app }, url) => {
    app.emit('open-url', { preventDefault: () => undefined }, url)
  }, callbackUrl)

  await pollUntil(
    async () => {
      await settings.reload()
      const state = await settings.getByTestId('account-state').innerText()
      return state === 'Connected.'
    },
    { label: 'the Settings pane to report Connected.', timeoutMs: 60_000 },
  )

  return settings
}

/** Reads the SERVER's own view of a task, straight through the real origin this lane booted -- never the app's own opinion of itself (D-27). */
const readServerTask = async (origin, sessionCookie, taskId) => {
  const response = await fetch(`${origin}/api/v1/tasks/${encodeURIComponent(taskId)}`, { headers: { Cookie: sessionCookie } })
  if (response.status !== 200) return null
  return response.json()
}

const findTaskIdByTitle = async (origin, sessionCookie, title) => {
  const response = await fetch(`${origin}/api/v1/inbox`, { headers: { Cookie: sessionCookie } })
  if (response.status !== 200) throw new Error(`electron-driver: GET /api/v1/inbox returned ${String(response.status)}`)
  const body = await response.json()
  return body.tasks?.find((task) => task.title === title)?.id ?? null
}

/**
 * Launches the packaged app once and returns the four-function adapter
 * `runSharedScenarioSet` calls, plus `teardown()` for the caller to run in
 * a `finally` block. `capture` mints its OWN task id nowhere explicit --
 * the real outbox does that internally -- so this adapter instead
 * DISCOVERS the id the app minted by matching the title it just typed
 * back out of the server's own inbox, exactly like
 * `real-stack-sync.spec.ts`'s own assertions do.
 */
export async function createElectronAdapter({ origin, sessionCookie }) {
  const repositoryRootPath = repositoryRoot
  const outRoot = join(repositoryRootPath, 'apps', 'desktop', 'out')
  const executablePath = findPackagedExecutable(outRoot)

  const profileRoot = await mkdtemp(join(tmpdir(), 'keepling-cross-adapter-electron-'))
  const gatePort = 42_531 + (process.pid % 500)
  const gateOrigin = `http://127.0.0.1:${String(gatePort)}`
  const gate = createGate(origin, gatePort)
  await gate.open()

  const application = await electron.launch({
    args: [`--user-data-dir=${profileRoot}`],
    env: {
      ...process.env,
      KEEPLING_EXPECT_PACKAGED: '1',
      KEEPLING_TEST_USER_DATA_DIR: profileRoot,
      // KEEPLING_TEST_SYNC_MODE is deliberately ABSENT -- the real adapter
      // must run, or this leg proves nothing (guardAgainstShortcuts also
      // refuses this file if it ever sets it).
    },
    executablePath,
    timeout: 60_000,
  })

  let window
  try {
    window = await application.firstWindow()
    await window.getByRole('heading', { name: 'Inbox' }).waitFor({ timeout: 30_000 })
    await signIn(application, gateOrigin, sessionCookie)
  } catch (error) {
    await application.close().catch(() => {})
    await rm(profileRoot, { force: true, recursive: true }).catch(() => {})
    await gate.close().catch(() => {})
    throw error
  }

  const titlesByTaskId = new Map()

  const waitForServerRevision = (taskId, predicate, label) =>
    pollUntil(
      async () => {
        const task = await readServerTask(origin, sessionCookie, taskId)
        return task && predicate(task) ? task : null
      },
      { label, timeoutMs: 60_000 },
    )

  const openTask = async (taskId) => {
    const title = titlesByTaskId.get(taskId)
    if (!title) throw new Error(`electron-driver: no locally known title for task ${taskId}`)
    await window.getByText(title).first().click()
    await window.getByRole('heading', { name: title }).waitFor({ timeout: 15_000 })
  }

  return {
    async capture(title) {
      await gate.open()
      await window.getByLabel('What do you want to keep?').fill(title)
      await window.getByRole('button', { name: 'Add Task' }).click()
      await window.getByText(title).first().waitFor({ timeout: 15_000 })
      const taskId = await pollUntil(() => findTaskIdByTitle(origin, sessionCookie, title), {
        label: `the server's inbox to hold a task titled "${title}"`,
        timeoutMs: 30_000,
      })
      titlesByTaskId.set(taskId, title)
      await gate.close()
      return { code: null, ok: true, taskId }
    },

    async complete(taskId) {
      await gate.open()
      await openTask(taskId)
      await window.getByRole('button', { name: 'Complete', exact: true }).click()
      const task = await waitForServerRevision(taskId, (candidate) => candidate.completed_at !== null, `task ${taskId} to be completed on the server`)
      await gate.close()
      return { code: null, finalRevision: task.revision, ok: true }
    },

    async reopen(taskId) {
      await gate.open()
      await openTask(taskId)
      await window.getByRole('button', { name: 'Reopen', exact: true }).click()
      const task = await waitForServerRevision(taskId, (candidate) => candidate.completed_at === null, `task ${taskId} to be reopened on the server`)
      await gate.close()
      return { code: null, finalRevision: task.revision, ok: true }
    },

    /**
     * The stale-expected-revision probe. The gate is assumed CLOSED
     * already -- left that way by this same adapter's own `capture` call
     * for this scenario -- so this client still believes the task open
     * and still holds the revision it observed at capture. It reaches for
     * the SAME action a person unaware of the out-of-band churn would
     * reach for next: Complete.
     */
    async staleUpdate(taskId) {
      await openTask(taskId)
      await window.getByRole('button', { name: 'Complete', exact: true }).click()
      await window.getByText('Saved on this Mac').first().waitFor({ timeout: 15_000 })
      await gate.open()
      // Either outcome settles the local intent: accepted (a real
      // over-write bug, revision keeps climbing) or refused (revision
      // stays exactly where the out-of-band advance left it, 3, and
      // completed_at stays null). Poll until the server stops looking
      // like the pre-settlement state (revision 3, still open) OR long
      // enough to conclude the refusal held.
      const settled = await pollUntil(
        async () => {
          const task = await readServerTask(origin, sessionCookie, taskId)
          if (!task) return null
          if (task.completed_at !== null) return { accepted: true, task }
          if (task.revision === 3) {
            // Give the queued command a moment to actually reach the
            // server and settle before concluding refusal -- a
            // still-`queued` local intent racing this read would
            // otherwise be misread as "refused" before it ever tried.
            await new Promise((resolveDelay) => setTimeout(resolveDelay, 2_000))
            const recheck = await readServerTask(origin, sessionCookie, taskId)
            if (recheck && recheck.completed_at === null && recheck.revision === 3) return { accepted: false, task: recheck }
          }
          return null
        },
        { label: `task ${taskId}'s stale complete to settle (accepted or refused)`, timeoutMs: 60_000 },
      )
      return {
        code: settled.accepted ? null : 'task_lifecycle_conflict',
        finalRevision: settled.task.revision,
        ok: settled.accepted,
      }
    },

    async teardown() {
      await application.close().catch(() => {})
      await gate.close().catch(() => {})
      await rm(profileRoot, { force: true, recursive: true }).catch(() => {})
    },
  }
}
