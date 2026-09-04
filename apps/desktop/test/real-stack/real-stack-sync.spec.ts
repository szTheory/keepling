import { createHash, randomBytes, randomUUID } from 'node:crypto'
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
 * OUTCOMES ACTUALLY OBSERVED: `accepted` and `conflict`.
 *
 * 03-21 could only observe `accepted`, because the adapter threw on
 * anything else (O-38) and building a case that tripped it would have
 * reported someone else's defect as this lane's failure. 03-22 closed that,
 * so the third case below now makes the REAL server refuse a REAL second
 * writer's divergence and follows the answer all the way to the copy a
 * person reads. `rejected` (a 422 semantic refusal) is NOT constructed here
 * and is not claimed -- it is proved exhaustively at the unit boundary in
 * `test/application/server-refusal.test.ts`, which drives the server's own
 * problem bodies.
 *
 * COMMAND TYPES ACTUALLY OBSERVED on the wire: capture_task, edit_task,
 * complete_task, reopen_task, plan_for_today, unplan_task, trash_task,
 * restore_task. `move_today_task` (reordering within Today) has no desktop
 * surface and is not exercised.
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

/**
 * The "system browser" half of RFC 8252, which the app deliberately never
 * performs itself -- and, for the conflict case, the SECOND WRITER.
 *
 * The second writer is a real browser client against the REAL server on its
 * own port, deliberately NOT through the gate: it has to keep writing while
 * the app's connection is down, which is exactly the situation that
 * produces a divergence in real life. It is not a fixture and it does not
 * answer on the server's behalf -- it makes the server change the task, and
 * the server decides everything that follows.
 */
type BrowserClient = {
  cookie: string
  csrfToken: string
  request: (path: string, init?: RequestInit) => Promise<Response>
  signIn: () => Promise<void>
}

const createBrowserClient = (base: string): BrowserClient => ({
  cookie: '',
  csrfToken: '',
  async request(path: string, init: RequestInit = {}): Promise<Response> {
    const response = await fetch(new URL(path, base), {
      ...init,
      headers: {
        accept: 'application/json',
        origin: base,
        ...(this.cookie === '' ? {} : { cookie: this.cookie }),
        ...(this.csrfToken === '' ? {} : { 'x-csrf-token': this.csrfToken }),
        ...(init.headers as Record<string, string> | undefined),
      },
      redirect: 'manual',
    })
    const set = response.headers.getSetCookie?.() ?? []
    if (set.length > 0) this.cookie = set.map((value) => value.split(';')[0]).join('; ')
    return response
  },
  async signIn(): Promise<void> {
    const session = await this.request('/api/v1/test/session', {
      body: '{}',
      headers: { 'content-type': 'application/json' },
      method: 'POST',
    })
    if (session.status !== 200) throw new Error(`the real server refused a browser session: ${String(session.status)}`)
    this.csrfToken = (await session.json() as { csrf_token: string }).csrf_token
  },
})

const browser = createBrowserClient(`http://${HOST}:${String(gatePort)}`)
const secondWriter = createBrowserClient(`http://${HOST}:${String(phoenixPort)}`)

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


/**
 * The whole RFC 8252 dance, once. Every byte on the APP's side is real: it
 * builds the authorization URL, hands it to `shell.openExternal`, and takes
 * the `keepling://auth/callback` back through its own `open-url` handler.
 * Only the browser half is played here.
 */
const signIn = async (application: ElectronApplication): Promise<Page> => {
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

  await settings.getByLabel('Keepling server address').fill(`http://${HOST}:${String(gatePort)}`)
  await settings.getByRole('button', { name: 'Connect…' }).click()

  const authorizationUrl = await expect
    .poll(
      async () =>
        application.evaluate(
          () => (globalThis as unknown as { __openedExternal: string[] }).__openedExternal[0] ?? null,
        ),
      { timeout: 30_000 },
    )
    .not.toBeNull()
    .then(async () =>
      application.evaluate(
        () => (globalThis as unknown as { __openedExternal: string[] }).__openedExternal[0] as string,
      ),
    )

  await browser.signIn()
  const authorize = await browser.request(
    authorizationUrl.slice(`http://${HOST}:${String(gatePort)}`.length),
  )
  expect(authorize.status, 'the real /oauth/authorize must redirect back to the app').toBe(302)
  const callbackUrl = authorize.headers.get('location') ?? ''
  expect(callbackUrl.startsWith('keepling://auth/callback?')).toBe(true)

  await application.evaluate(({ app }, url) => {
    app.emit('open-url', { preventDefault: () => undefined }, url)
  }, callbackUrl)

  // Polled, not read once: `handleCallback` clears the in-flight request
  // BEFORE awaiting the real token exchange over a real socket, so there is
  // a genuine window in which the pane reads "Signed out." Reloading is a
  // READ, not a nudge -- the authorization either happened in the main
  // process or it did not (O-39).
  await expect
    .poll(
      async () => {
        await settings.reload()
        return settings.getByTestId('account-state').innerText()
      },
      { intervals: [500], timeout: 60_000 },
    )
    .toBe('Connected.')
  return settings
}

/** What the SERVER holds for one task. Never the client's opinion of itself. */
const serverTask = async (taskId: string): Promise<{
  completed_at: string | null
  planned_on: string | null
  revision: number
  title: string
  trashed_at: string | null
}> => {
  const response = await browser.request(`/api/v1/tasks/${encodeURIComponent(taskId)}`)
  expect(response.status, 'the real server must know this task').toBe(200)
  return (await response.json()) as {
    completed_at: string | null
    planned_on: string | null
    revision: number
    title: string
    trashed_at: string | null
  }
}

/** The command types the SERVER actually received, recorded by the forwarding proxy. */
const receivedCommandTypes = (): string[] => [
  ...new Set(
    gate.bodies.flatMap(({ body, url }) => {
      if (!url.includes('/api/v1/commands/')) return []
      try {
        const type = (JSON.parse(body) as { type?: unknown }).type
        return typeof type === 'string' ? [type] : []
      } catch {
        return []
      }
    }),
  ),
]

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

    const settings = await signIn(application)

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


/**
 * O-41. Until 03-22, `type: 'capture_task'` was the only command desktop
 * production code could construct: `editTask`, `applyLifecycle` and
 * `moveToday` wrote the local projection and enqueued NOTHING, so
 * completing, reopening, trashing, restoring, retitling and moving to Today
 * were durable on this Mac and invisible to the server forever.
 *
 * Every assertion below reads what the SERVER holds -- `/api/v1/tasks/:id`
 * and the bodies the forwarding proxy saw arrive -- never the client's own
 * claim about itself. A client that reconciled nothing would still say
 * "Synced" if the row were the evidence.
 */
test('every mutation a person can perform reaches real Phoenix and reconciles against real PostgreSQL', async () => {
  test.setTimeout(600_000)
  const profilePath = join(profileRoot, 'real-stack-mutations')
  mkdirSync(profilePath, { recursive: true })
  await gate.open()
  const application = await launch(profilePath)

  try {
    const window = await application.firstWindow()
    await expect(window.getByRole('heading', { name: 'Inbox' })).toBeVisible()
    await signIn(application)

    const title = 'Book the ferry'
    await window.getByLabel('What do you want to keep?').fill(title)
    await window.getByRole('button', { name: 'Add Task' }).click()
    await expect(window.getByText('Synced')).toHaveCount(1, { timeout: 60_000 })

    // The identity comes from the SERVER, so everything below is anchored to
    // the row PostgreSQL actually holds.
    const inbox = (await (await browser.request('/api/v1/inbox')).json()) as {
      tasks: Array<{ id: string; title: string }>
    }
    const taskId = inbox.tasks.find((task) => task.title === title)!.id
    expect(taskId, 'the real server must hold the captured task').toBeTruthy()
    expect((await serverTask(taskId)).revision).toBe(1)

    // Every non-capture mutation, driven through the SHIPPED UI -- the same
    // controls a person presses, not an IPC call.
    const editedTitle = 'Book the ferry to Mull'
    await window.getByText(title).click()
    await window.locator('#task-editor-title').fill(editedTitle)
    await window.keyboard.press('Meta+s')
    await expect(window.getByRole('heading', { name: editedTitle })).toBeVisible()
    await expect.poll(async () => (await serverTask(taskId)).title, { timeout: 60_000 }).toBe(editedTitle)

    await window.getByRole('button', { name: 'Complete' }).click()
    await expect.poll(async () => (await serverTask(taskId)).completed_at, { timeout: 60_000 }).not.toBeNull()

    await window.getByRole('button', { name: 'Reopen' }).click()
    await expect.poll(async () => (await serverTask(taskId)).completed_at, { timeout: 60_000 }).toBeNull()

    await window.getByRole('button', { name: 'Add to Today' }).click()
    await expect.poll(async () => (await serverTask(taskId)).planned_on, { timeout: 60_000 }).not.toBeNull()

    await window.getByRole('button', { name: 'Today', exact: true }).click()
    await window.getByText(editedTitle).click()
    await window.getByRole('button', { name: 'Remove from Today' }).click()
    await expect.poll(async () => (await serverTask(taskId)).planned_on, { timeout: 60_000 }).toBeNull()

    await window.getByRole('button', { name: 'Inbox', exact: true }).click()
    await window.getByText(editedTitle).click()
    await window.getByRole('button', { name: 'Move to Trash' }).click()
    await expect.poll(async () => (await serverTask(taskId)).trashed_at, { timeout: 60_000 }).not.toBeNull()

    await window.getByRole('button', { name: 'Trash', exact: true }).click()
    await window.getByText(editedTitle).click()
    await window.getByRole('button', { name: 'Restore' }).click()
    await expect.poll(async () => (await serverTask(taskId)).trashed_at, { timeout: 60_000 }).toBeNull()

    // The outbox drained: nothing is left that this Mac still intends to
    // send. "Synced" on a row is a claim; an empty outbox is the fact.
    await expect.poll(() => readOutbox(profilePath).length, { timeout: 60_000 }).toBe(0)

    const observedTypes = receivedCommandTypes()
    for (const type of [
      'capture_task', 'edit_task', 'complete_task', 'reopen_task',
      'plan_for_today', 'unplan_task', 'trash_task', 'restore_task',
    ]) {
      expect(observedTypes, `the server never received a ${type} command`).toContain(type)
    }

    const final = await serverTask(taskId)
    expect(final.title).toBe(editedTitle)
    // Seven accepted mutations after the capture, each of which the server
    // bumps by one. A client whose commands were refused would sit at 1.
    expect(final.revision).toBeGreaterThan(1)

    console.log(
      `REAL_STACK_MUTATIONS command_types=${observedTypes.sort().join(',')} ` +
        `final_revision=${String(final.revision)} outbox=0 digest=${manifest.applicationDigestSha256}`,
    )
  } finally {
    await application.close()
  }
})

/**
 * O-41's ordering rule, and O-38 end to end.
 *
 * Ordering: an edit to a task whose capture has not yet been acknowledged
 * must not overtake it. Proved against the bodies the SERVER received, in
 * arrival order -- not against the client's outbox, which is the thing
 * being tested.
 *
 * Conflict: the divergence is created by a REAL SECOND WRITER changing the
 * task through the REAL server while this Mac is disconnected. No fixture
 * asserts a conflict and `KEEPLING_TEST_SYNC_MODE` is not set anywhere in
 * this file; the server decides, on its own three-way merge, that the two
 * versions cannot be reconciled.
 */
test('an offline edit never overtakes its capture, and a conflict the real server raises reaches the shipped window', async () => {
  test.setTimeout(600_000)
  const profilePath = join(profileRoot, 'real-stack-conflict')
  mkdirSync(profilePath, { recursive: true })
  await gate.open()
  const application = await launch(profilePath)
  const arrivalsBefore = gate.bodies.length

  try {
    const window = await application.firstWindow()
    await expect(window.getByRole('heading', { name: 'Inbox' })).toBeVisible()
    await signIn(application)

    // -- ORDERING ---------------------------------------------------------
    // Capture AND edit while the server is unreachable, so both are queued
    // before either can be delivered.
    await gate.close()
    const original = 'Ferry booking'
    await window.getByLabel('What do you want to keep?').fill(original)
    await window.getByRole('button', { name: 'Add Task' }).click()
    await expect(window.getByText(original)).toHaveCount(1)

    const mine = 'Ferry booking — mine'
    await window.getByText(original).click()
    await window.locator('#task-editor-title').fill(mine)
    await window.keyboard.press('Meta+s')
    await expect(window.getByRole('heading', { name: mine })).toBeVisible()

    await expect.poll(() => readOutbox(profilePath).length, { timeout: 30_000 }).toBe(2)
    const queued = readOutbox(profilePath)
    expect(JSON.parse(queued[0]!.commandBytes)).toMatchObject({ type: 'capture_task' })
    expect(JSON.parse(queued[1]!.commandBytes)).toMatchObject({ type: 'edit_task' })
    const taskId = queued[0]!.taskId

    await gate.open()
    await expect(window.getByText('Synced')).toHaveCount(1, { timeout: 90_000 })
    await expect.poll(() => readOutbox(profilePath).length, { timeout: 60_000 }).toBe(0)

    // What the SERVER received, in the order it received it.
    const arrivals = gate.bodies
      .slice(arrivalsBefore)
      .filter(({ url }) => url.includes('/api/v1/commands/'))
      .map(({ body }) => (JSON.parse(body) as { task_id?: string; type: string }))
      .filter((command) => command.task_id === taskId)
    expect(arrivals.map((command) => command.type)).toEqual(['capture_task', 'edit_task'])
    expect(await serverTask(taskId).then((task) => task.title)).toBe(mine)

    // -- A REAL CONFLICT --------------------------------------------------
    const baseline = await serverTask(taskId)
    await gate.close()

    const conflicting = 'Ferry booking — retitled on this Mac'
    await window.getByText(mine).click()
    await window.locator('#task-editor-title').fill(conflicting)
    await window.keyboard.press('Meta+s')
    await expect(window.getByRole('heading', { name: conflicting })).toBeVisible()

    // A REAL second writer, through the REAL server, while this Mac cannot
    // reach it. Nothing here answers on the server's behalf.
    await secondWriter.signIn()
    const elsewhere = 'Ferry booking — changed on the phone'
    const secondWrite = await secondWriter.request('/api/v1/commands/edit-task', {
      body: JSON.stringify({
        base_values: { title: baseline.title },
        expected_revision: baseline.revision,
        fields: { title: elsewhere },
        mutation_id: randomUUID(),
        task_id: taskId,
        version: 1,
      }),
      headers: { 'content-type': 'application/json' },
      method: 'POST',
    })
    expect(secondWrite.status, 'the second writer must really change the task').toBe(200)
    expect((await serverTask(taskId)).title).toBe(elsewhere)

    // Reconnect. The app's queued edit is now based on a value the server
    // has moved past, and the server's own three-way merge refuses it.
    await gate.open()

    const statusCopy = window.locator('#sync-status-row [data-sync-copy]')
    await expect(statusCopy).toHaveText(
      'This task changed somewhere else. Choose what to keep. Other tasks can continue.',
      { timeout: 90_000 },
    )
    await expect(window.locator('#sync-status-row')).toHaveAttribute('data-sync-status', 'conflict')
    // The remedy is live, not a label (O-42).
    await expect(window.locator('#sync-status-row button[data-recovery-action="review_conflict"]')).toHaveText(
      'Review Conflict',
    )
    // The MISDIAGNOSIS this closes: before O-38 the 409 threw, the pass
    // failed, and this is the row a person got instead.
    await expect(window.getByText('Couldn’t reach the server. Your changes stay on this Mac.')).toHaveCount(0)

    // Both versions are offered, from the SERVER's own conflict body.
    await expect(window.getByRole('heading', { name: 'This task changed somewhere else.' })).toBeVisible()
    await expect(window.getByText(`Your version: ${conflicting}`)).toBeVisible()
    await expect(window.getByText(`Current version: ${elsewhere}`)).toBeVisible()

    // The refused command is terminal: it does not sit in the outbox being
    // retried forever against a server that has already decided.
    await expect.poll(() => readOutbox(profilePath).length, { timeout: 60_000 }).toBe(0)
    // And the server was NOT overwritten by the refused edit.
    expect((await serverTask(taskId)).title).toBe(elsewhere)

    console.log(
      `REAL_STACK_CONFLICT ordering=capture_task,edit_task outcomes=conflict conflicts=1 ` +
        `second_writer=real digest=${manifest.applicationDigestSha256}`,
    )
  } finally {
    await application.close()
  }
})
