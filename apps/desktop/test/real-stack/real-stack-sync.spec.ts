import { createHash, randomBytes } from 'node:crypto'
import { mkdirSync, readFileSync } from 'node:fs'
import { mkdtemp, rm } from 'node:fs/promises'
import { createServer, request, type Server } from 'node:http'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { DatabaseSync } from 'node:sqlite'
import process from 'node:process'
import {
  test,
  expect,
  _electron as electron,
  type ElectronApplication,
  type Page,
} from '@playwright/test'

import {
  configuredPort,
  startBackend,
  stopBackend,
  type OwnedChild,
} from '../../../web/e2e/support/backend.ts'

/**
 * O-34/O-37: the PACKAGED Mac app against a REAL server.
 *
 * Every other desktop lane in this repository fakes its transport. The
 * packaged specs set `KEEPLING_TEST_SYNC_MODE` and exercise an inline stub;
 * `test/e2e/fixture-server-sync.spec.ts` drives a contract-faithful
 * in-process fixture. Useful, and not the same claim. Nothing had ever
 * verified that the adapter and the server AGREE -- and the first time
 * anything did, three real disagreements fell out at once (the device grant
 * could not mutate, the command body was missing `version`, and the client
 * kind was recorded as "web").
 *
 * So the rules here are deliberately narrow and are enforced by
 * `tooling/verify-real-stack-desktop.mjs`, not just by good intentions:
 *
 *   - `KEEPLING_TEST_SYNC_MODE` is NOT set, so the real `KeeplingSyncAdapter`
 *     runs. A lane that passes with the stub has proven nothing.
 *   - `fetch` is not stubbed, the transport is not mocked, and the base URL
 *     is not a non-resolving host. Real bytes reach real Phoenix on real
 *     PostgreSQL, through the SAME harness the web lane proves against
 *     (`apps/web/e2e/support/backend.ts`, imported rather than copied).
 *   - The executable is the packaged `.app` from the manifest, launched the
 *     way the other packaged specs launch it.
 *
 * WHAT IS AND IS NOT MODELLED. The "system browser" half of RFC 8252 is
 * played by this test: it establishes a browser session and drives the real
 * `/oauth/authorize`, because a real Safari window is not something a lane
 * can drive and because the app deliberately never sees that step. Every
 * byte on the APP's side of the boundary is real -- the app builds the
 * authorization URL, hands it to `shell.openExternal`, and receives the
 * `keepling://auth/callback` through its own real `open-url` handler.
 *
 * OUTCOMES ACTUALLY OBSERVED: `accepted` only. This lane deliberately does
 * NOT construct a server-side conflict or rejection. `mapAcknowledgement` in
 * the real adapter accepts only `accepted`/`already_satisfied` and throws on
 * the `conflict` and `rejected` the contract also declares (O-38); building a
 * case that trips it here would report someone else's defect as this lane's
 * failure. This lane proves the accepted path and says so.
 */

type PackageManifest = {
  applicationDigestSha256: string
  embeddedVersions: Record<string, string>
  executablePath: string
  sourceRevision: string
}

const manifestPath = process.env.KEEPLING_PACKAGE_MANIFEST
if (!manifestPath) throw new Error('KEEPLING_PACKAGE_MANIFEST is required for the real-stack lane')
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8')) as PackageManifest
const profileRoot = process.env.KEEPLING_TEST_USER_DATA_DIR
if (!profileRoot) throw new Error('KEEPLING_TEST_USER_DATA_DIR is required for the real-stack lane')

const HOST = '127.0.0.1'
const phoenixPort = configuredPort('KEEPLING_DESKTOP_E2E_PHOENIX_PORT', '4102')
const postgresPort = configuredPort('KEEPLING_DESKTOP_E2E_POSTGRES_PORT', '55433')
const gatePort = configuredPort('KEEPLING_DESKTOP_E2E_GATE_PORT', '4103')

const ownedChildren: OwnedChild[] = []
let temporaryRoot: string | undefined

/**
 * A real forwarding HTTP proxy in front of real Phoenix, and the ONLY way
 * this lane makes the server unreachable.
 *
 * It is not a fake server and it never answers on the server's behalf: it
 * pipes bytes to real Phoenix and pipes the real answer back. Closing it
 * makes the app's next connection fail with a genuine ECONNREFUSED, which
 * is what "the server is unreachable" actually is on a Mac whose network
 * dropped. Stopping and restarting Phoenix itself would model the same
 * thing far more slowly and far less deterministically.
 *
 * It also records what the server RECEIVED, which is how the exact-bytes
 * claim below is checked against the wire rather than against the client's
 * own opinion of what it sent.
 */
type Gate = {
  bodies: Array<{ body: string; url: string }>
  close: () => Promise<void>
  open: () => Promise<void>
}

const createGate = (): Gate => {
  const bodies: Array<{ body: string; url: string }> = []
  let server: Server | undefined

  const build = () =>
    createServer((incoming, outgoing) => {
      const chunks: Buffer[] = []
      incoming.on('data', (chunk: Buffer) => chunks.push(chunk))
      incoming.on('end', () => {
        if (chunks.length > 0) {
          bodies.push({ body: Buffer.concat(chunks).toString('utf8'), url: incoming.url ?? '' })
        }
      })
      const upstream = request(
        {
          headers: incoming.headers,
          host: HOST,
          method: incoming.method,
          path: incoming.url,
          port: phoenixPort,
        },
        (response) => {
          outgoing.writeHead(response.statusCode ?? 502, response.headers)
          response.pipe(outgoing)
        },
      )
      upstream.once('error', () => {
        outgoing.destroy()
      })
      incoming.pipe(upstream)
    })

  return {
    bodies,
    close: async () => {
      const current = server
      server = undefined
      if (!current) return
      current.closeAllConnections()
      await new Promise<void>((resolvePromise) => current.close(() => resolvePromise()))
    },
    open: async () => {
      if (server) return
      const next = build()
      await new Promise<void>((resolvePromise, reject) => {
        next.once('error', reject)
        next.listen(gatePort, HOST, () => resolvePromise())
      })
      server = next
    },
  }
}

const gate = createGate()

/** The "system browser" half of RFC 8252, which the app deliberately never performs itself. */
const browser = {
  cookie: '',
  async request(path: string, init: RequestInit = {}): Promise<Response> {
    const base = `http://${HOST}:${String(gatePort)}`
    const response = await fetch(new URL(path, base), {
      ...init,
      headers: {
        accept: 'application/json',
        origin: base,
        ...(this.cookie === '' ? {} : { cookie: this.cookie }),
        ...(init.headers as Record<string, string> | undefined),
      },
      redirect: 'manual',
    })
    const set = response.headers.getSetCookie?.() ?? []
    if (set.length > 0) this.cookie = set.map((value) => value.split(';')[0]).join('; ')
    return response
  },
}

test.beforeAll(async () => {
  test.setTimeout(600_000)
  // Short prefix on purpose: PostgreSQL's Unix-domain socket path has a
  // 103-byte limit, and macOS's per-user temporary directory already spends
  // most of it. A descriptive prefix here makes `initdb` succeed and
  // `postgres` die at startup with "could not create any Unix-domain
  // sockets" -- measured.
  temporaryRoot = await mkdtemp(join(tmpdir(), 'kpl-ds-'))
  await startBackend({
    faultToken: randomBytes(32).toString('hex'),
    onUnexpectedExit: (reason) => {
      // A backend that dies mid-run is a LOUD failure, never a lane that
      // quietly continues against nothing.
      process.stderr.write(`REAL_STACK backend_exited reason=${reason}\n`)
    },
    ownedChildren,
    phoenixPort,
    postgresPort,
    secretKeyBase: randomBytes(64).toString('hex'),
    temporaryRoot,
  })
  await gate.open()
})

test.afterAll(async () => {
  await gate.close()
  await stopBackend(ownedChildren)
  if (temporaryRoot) await rm(temporaryRoot, { force: true, recursive: true })
})

const launch = async (profilePath: string): Promise<ElectronApplication> =>
  electron.launch({
    args: [`--user-data-dir=${profilePath}`],
    env: {
      ...process.env,
      KEEPLING_EXPECT_PACKAGED: '1',
      KEEPLING_TEST_USER_DATA_DIR: profilePath,
      // KEEPLING_TEST_SYNC_MODE is deliberately ABSENT. Setting it here
      // would run the inline stub and this whole lane would prove nothing.
    },
    executablePath: manifest.executablePath,
    timeout: 60_000,
  })

/** Reads the durable outbox out of the app's own SQLite file, without disturbing it. */
const readOutbox = (profilePath: string) => {
  const database = new DatabaseSync(join(profilePath, 'namespace.sqlite3'), { readOnly: true })
  try {
    return database
      .prepare(
        `SELECT immutable_commands.command_bytes AS commandBytes,
                immutable_commands.fingerprint AS fingerprint,
                immutable_commands.mutation_id AS mutationId,
                immutable_commands.task_id AS taskId
         FROM outbox JOIN immutable_commands USING (mutation_id)
         ORDER BY outbox.sequence`,
      )
      .all() as Array<{
      commandBytes: string
      fingerprint: string
      mutationId: string
      taskId: string
    }>
  } finally {
    database.close()
  }
}

test('the packaged app authorizes, captures offline, reconnects, and reaches Synced against real Phoenix and real PostgreSQL', async () => {
  test.setTimeout(600_000)
  const profilePath = join(profileRoot, 'real-stack-sync')
  mkdirSync(profilePath, { recursive: true })
  const application = await launch(profilePath)

  try {
    const window = await application.firstWindow()
    await expect(window.getByRole('heading', { name: 'Inbox' })).toBeVisible()

    // The app hands the authorization URL to the SYSTEM BROWSER. Capture it
    // instead of opening a real browser window; everything the app itself
    // does -- building the URL, the PKCE verifier, the state -- is real and
    // untouched.
    const patched = await application.evaluate(({ shell }) => {
      ;(globalThis as unknown as { __openedExternal: string[] }).__openedExternal = []
      try {
        shell.openExternal = async (url: string) => {
          ;(globalThis as unknown as { __openedExternal: string[] }).__openedExternal.push(url)
        }
        return true
      } catch {
        return false
      }
    })
    expect(patched, 'shell.openExternal must be interceptable to drive the browser half').toBe(true)

    // Open the real Settings window through the real application menu.
    const [settings] = await Promise.all([
      application.waitForEvent('window', {
        predicate: (page: Page) => page.url().includes('view=settings'),
      }),
      application.evaluate(({ Menu }) => {
        const find = (items: Electron.MenuItem[]): Electron.MenuItem | null => {
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

    // Real server selection through the real UI. No credential field exists
    // in this or any renderer, by design (RFC 8252).
    await expect(settings.getByTestId('account-state')).toHaveText(
      'No Keepling server is configured on this Mac.',
    )
    await settings.getByLabel('Keepling server address').fill(`http://${HOST}:${String(gatePort)}`)
    await settings.getByRole('button', { name: 'Connect…' }).click()

    const authorizationUrl = await expect
      .poll(async () =>
        application.evaluate(
          () => (globalThis as unknown as { __openedExternal: string[] }).__openedExternal[0] ?? null,
        ),
      )
      .not.toBeNull()
      .then(async () =>
        application.evaluate(
          () => (globalThis as unknown as { __openedExternal: string[] }).__openedExternal[0] as string,
        ),
      )

    // The browser half, against the REAL server: establish a session, then
    // drive the REAL /oauth/authorize with the app's own PKCE challenge and
    // state, and take the real redirect back.
    const session = await browser.request('/api/v1/test/session', {
      body: '{}',
      headers: { 'content-type': 'application/json' },
      method: 'POST',
    })
    expect(session.status, 'the real server must establish a browser session').toBe(200)

    const authorize = await browser.request(
      authorizationUrl.slice(`http://${HOST}:${String(gatePort)}`.length),
    )
    expect(authorize.status, 'the real /oauth/authorize must redirect back to the app').toBe(302)
    const callbackUrl = authorize.headers.get('location') ?? ''
    expect(callbackUrl.startsWith('keepling://auth/callback?')).toBe(true)

    // Hand the callback to the app through its OWN real `open-url` handler --
    // the same path macOS uses when the browser returns.
    await application.evaluate(({ app }, url) => {
      app.emit('open-url', { preventDefault: () => undefined }, url)
    }, callbackUrl)

    // The Settings pane reads account status on mount and after its own
    // actions; nothing pushes a change into it when the browser callback
    // lands, so it keeps showing "Finish signing in..." until it re-reads.
    // Reloading is a READ, not a nudge to the app -- the authorization
    // either happened in the main process or it did not. Filed as an open
    // item rather than fixed here; it is a staleness defect in a pane, not
    // part of O-34.
    await settings.reload()
    await expect(settings.getByTestId('account-state')).toHaveText('Connected.', { timeout: 30_000 })

    // The five-field namespace is SERVER-derived. The client configured
    // 127.0.0.1:<gate>; the origin the app now holds is the one the SERVER
    // supplied, and they are deliberately different values.
    const serverOrigin = `http://localhost:${String(phoenixPort)}`
    await expect(settings.getByTestId('account-server')).toHaveText(`Signed in to ${serverOrigin}`)

    // 1. CAPTURE WHILE THE SERVER IS UNREACHABLE.
    await gate.close()
    const offlineTitle = 'Book the ferry from a Mac with no network'
    await window.getByLabel('What do you want to keep?').fill(offlineTitle)
    await window.getByRole('button', { name: 'Add Task' }).click()
    await expect(window.getByText(offlineTitle)).toHaveCount(1)
    await expect(window.getByText('Saved on this Mac').first()).toBeVisible()
    await expect(window.getByText('Synced')).toHaveCount(0)

    // The durable intent, read out of the app's own store.
    const pending = await expect
      .poll(() => readOutbox(profilePath).length, { timeout: 15_000 })
      .toBe(1)
      .then(() => readOutbox(profilePath)[0]!)
    expect(pending.fingerprint).toBe(createHash('sha256').update(pending.commandBytes).digest('hex'))
    expect(JSON.parse(pending.commandBytes)).toEqual({
      mutation_id: pending.mutationId,
      task_id: pending.taskId,
      title: offlineTitle,
      type: 'capture_task',
      version: 1,
    })

    // 2. THE SERVER GENUINELY DOES NOT HAVE IT. Not "the client did not say
    // Synced" -- the server itself has no such mutation.
    await gate.open()
    const beforeReconnect = await browser.request(`/api/v1/mutations/${pending.mutationId}`)
    expect(beforeReconnect.status, 'the server must not know a mutation it never received').toBe(404)
    await gate.close()
    await gate.open()

    // 3. RECONNECT. A second capture is the trigger; both flush in one pass.
    const onlineTitle = 'Captured once the network came back'
    await window.getByLabel('What do you want to keep?').fill(onlineTitle)
    await window.getByRole('button', { name: 'Add Task' }).click()

    await expect(window.getByText('Synced')).toHaveCount(2, { timeout: 60_000 })
    await expect.poll(() => readOutbox(profilePath).length, { timeout: 30_000 }).toBe(0)

    // 4. THE EXACT SERIALIZED BYTES WERE RETRIED, verified against what the
    // server actually received rather than against the client's own claim.
    const captured = gate.bodies.filter(({ url }) => url.includes('/commands/capture-task'))
    expect(captured.map(({ body }) => body)).toContain(pending.commandBytes)

    // 5. THE RECEIPT IS EXACT: same mutation identity, same task identity.
    const receipt = await browser.request(`/api/v1/mutations/${pending.mutationId}`)
    expect([200, 201]).toContain(receipt.status)
    const receiptBody = (await receipt.json()) as {
      mutation_id: string
      outcome: string
      task_id: string
    }
    expect(receiptBody.mutation_id).toBe(pending.mutationId)
    expect(receiptBody.task_id).toBe(pending.taskId)
    // Recorded, not assumed: this lane only ever exercises the accepted path.
    expect(receiptBody.outcome).toBe('accepted')

    // 6. THE BYTES REACHED REAL POSTGRESQL, read back through the server's
    // own API rather than inferred from the client's row.
    const inbox = (await (await browser.request('/api/v1/inbox')).json()) as {
      tasks: Array<{ id: string; title: string }>
    }
    const titles = inbox.tasks.map((task) => task.title)
    expect(titles).toContain(offlineTitle)
    expect(titles).toContain(onlineTitle)

    const runtime = await application.evaluate(({ app }) => ({
      isPackaged: app.isPackaged,
      versions: process.versions,
    }))
    expect(runtime.isPackaged).toBe(true)
    expect(runtime.versions.electron).toBe(manifest.embeddedVersions.electron)

    console.log(
      `REAL_STACK_SYNC synced=2 pushed_exact_bytes=1 outcomes=accepted server_origin=${serverOrigin} ` +
        `digest=${manifest.applicationDigestSha256} executable=${manifest.executablePath}`,
    )
  } finally {
    await application.close()
  }
})
