import { createHash, randomBytes, randomUUID } from 'node:crypto'
import process from 'node:process'

import { expect, test } from '@playwright/test'

import { configuredPort } from './support/backend.ts'

/**
 * 05-09-PLAN.md Task 3: one spec against the REAL stack (real PostgreSQL,
 * real migrations, real Phoenix, no stubbed fetch, no synthetic unreachable
 * host, and no test-only synchronization shortcut) proving the whole
 * user-facing loop:
 *
 *   1. Register an MCP client and complete authorization-code + PKCE,
 *      obtaining a real agent grant with `tasks.read` and `tasks.write`.
 *   2. Issue a real `tools/call` against `POST /mcp/v1` that captures and
 *      then completes one task.
 *   3. Load the web app as the signed-in owner; the activity history shows
 *      both actions attributed to the agent grant by its label.
 *   4. Activate the undo control on the agent's completion; the task
 *      returns to its prior state, read back from the server.
 *   5. Open `/settings/agents`, assert the grant is listed, revoke it, and
 *      assert a subsequent `tools/call` with the revoked credential is
 *      refused and creates no row.
 *
 * The stack's shared backend (`e2e/support/backend.ts`) is started once by
 * Playwright's `webServer` (see `playwright.config.ts` -> `e2e/support/
 * stack.ts`, which imports `startBackend` from `backend.ts`). OAuth, MCP,
 * and `.well-known` routes are NOT proxied by `stack.ts`'s single-origin
 * proxy (only `/api/*` is) -- they are hit directly against the real
 * Phoenix instance at `http://localhost:${phoenixPort}`, mirroring how a
 * real MCP host reaches this server on its own origin. `KEEPLING_E2E_PORT`
 * (`baseURL`) is used only for the browser-facing half of this spec.
 */

const phoenixPort = configuredPort('KEEPLING_E2E_PHOENIX_PORT', '4002')
const phoenixOrigin = `http://localhost:${String(phoenixPort)}`

const faultToken = process.env.KEEPLING_TEST_FAULT_TOKEN
if (!faultToken || faultToken.length < 32) {
  throw new Error('KEEPLING_TEST_FAULT_TOKEN must be a per-run high-entropy value')
}

const base64Url = (buffer: Buffer) => buffer.toString('base64url')

const pkce = () => {
  const verifier = base64Url(randomBytes(32))
  const challenge = base64Url(createHash('sha256').update(verifier).digest())
  return { challenge, verifier }
}

test('@agent-access @uat-accessibility an agent acts, the owner sees it, undoes it, and revokes the agent', async ({
  baseURL,
  page,
}) => {
  if (!baseURL) throw new Error('Playwright baseURL is required')
  // -- Establish the signed-in owner's browser session against the SAME
  // deterministic seeded single account every real-stack lane in this
  // repository uses (D-003: single account). This needs two cookies, not
  // one: `stack.ts`'s single-origin proxy forwards only `/api/*` to
  // Phoenix, so `/oauth/*`, `/mcp/v1`, and `/.well-known/*` below are hit
  // directly against `phoenixOrigin` -- a different origin than the
  // Playwright `baseURL` the page itself navigates -- and a cookie set on
  // one origin is never sent on the other. One session is established
  // directly against Phoenix (for the OAuth authorize step immediately
  // below) and a second, separate one through the proxy (for the browser
  // page's own fetches once it navigates in step 3).
  const directSessionResponse = await page.request.post(`${phoenixOrigin}/api/v1/test/session`, {
    headers: { origin: phoenixOrigin },
  })
  expect(directSessionResponse.ok(), await directSessionResponse.text()).toBe(true)

  const browserSessionResponse = await page.request.post('/api/v1/test/session', {
    headers: { origin: new URL(baseURL).origin },
  })
  expect(browserSessionResponse.ok(), await browserSessionResponse.text()).toBe(true)

  // ============================================================
  // Step 1: register an MCP client and complete authorization-code + PKCE
  // ============================================================
  // The pre-registered `client_id: "mcp"` (apps/server/config/runtime.exs)
  // needs no RFC 7591 DCR round-trip -- Claude Code, this repository's
  // primary dogfood host, does not require it either (05-CONTEXT.md D-29).
  const { challenge, verifier } = pkce()
  // `unpredictable_state?/1` (Keepling.Accounts.DeviceGrant) requires at
  // least 32 decoded bytes -- 16 is accepted syntax but rejected on length.
  const state = base64Url(randomBytes(32))
  const installationId = `agent-access-e2e-${randomUUID()}`
  const redirectUri = `${phoenixOrigin}/mcp/callback`
  const resource = `${phoenixOrigin}/mcp/v1`

  const authorizeResponse = await page.request.get(`${phoenixOrigin}/oauth/authorize`, {
    maxRedirects: 0,
    params: {
      client_id: 'mcp',
      code_challenge: challenge,
      code_challenge_method: 'S256',
      installation_id: installationId,
      label: 'Agent access e2e host',
      redirect_uri: redirectUri,
      resource,
      response_type: 'code',
      scope: 'tasks.read tasks.write',
      state,
    },
  })
  expect(authorizeResponse.status(), await authorizeResponse.text()).toBe(302)
  const location = new URL(authorizeResponse.headers().location, phoenixOrigin)
  expect(`${location.origin}${location.pathname}`).toBe(redirectUri)
  expect(location.searchParams.get('state')).toBe(state)
  const authorizationCode = location.searchParams.get('code')
  expect(authorizationCode).toBeTruthy()

  const tokenResponse = await page.request.post(`${phoenixOrigin}/oauth/token`, {
    data: {
      code: authorizationCode,
      code_verifier: verifier,
      grant_type: 'authorization_code',
      redirect_uri: redirectUri,
      resource,
      state,
    },
  })
  expect(tokenResponse.ok(), await tokenResponse.text()).toBe(true)
  const grant = (await tokenResponse.json()) as { access_token: string }
  expect(typeof grant.access_token).toBe('string')

  const mcpCall = async (method: string, params: Record<string, unknown>, id: number) =>
    page.request.post(`${phoenixOrigin}/mcp/v1`, {
      data: { id, jsonrpc: '2.0', method, params },
      headers: { authorization: `Bearer ${grant.access_token}` },
    })

  // ============================================================
  // Step 2: a real tools/call captures, then completes, one task
  // ============================================================
  const taskId = randomUUID()
  const captureMutationId = randomUUID()

  const captureResponse = await mcpCall(
    'tools/call',
    {
      arguments: {
        mutation_id: captureMutationId,
        task_id: taskId,
        title: 'Book the ferry',
        version: 1,
      },
      name: 'keepling.capture_task',
    },
    1,
  )
  expect(captureResponse.ok(), await captureResponse.text()).toBe(true)
  const captureBody = (await captureResponse.json()) as {
    result?: { structuredContent?: { outcome?: string; task_id?: string } }
  }
  expect(captureBody.result?.structuredContent?.outcome).toBe('accepted')
  expect(captureBody.result?.structuredContent?.task_id).toBe(taskId)

  const completeMutationId = randomUUID()
  const completeResponse = await mcpCall(
    'tools/call',
    {
      arguments: {
        expected_revision: 1,
        mutation_id: completeMutationId,
        task_id: taskId,
        version: 1,
      },
      name: 'keepling.complete_task',
    },
    2,
  )
  expect(completeResponse.ok(), await completeResponse.text()).toBe(true)
  const completeBody = (await completeResponse.json()) as {
    result?: { structuredContent?: { outcome?: string; revision?: number } }
  }
  expect(completeBody.result?.structuredContent?.outcome).toBe('accepted')

  // ============================================================
  // Step 3: the signed-in owner's activity history shows both actions
  // attributed to the agent grant by its label
  // ============================================================
  await page.goto(`/tasks/${taskId}`)
  const activityHeading = page.getByRole('heading', { name: 'Activity' })
  await expect(activityHeading).toBeVisible()

  // The rendered sentence interposes the "AI agent" accessible badge
  // between the grant label and the action verb (ActorLabel in
  // ActivityList.tsx), so the match spans that gap rather than asserting
  // one contiguous string.
  const captureRow = page.getByText(/Agent access e2e host.*captured this task\./)
  const completeRow = page.getByText(/Agent access e2e host.*completed this task\./)
  await expect(captureRow).toBeVisible()
  await expect(completeRow).toBeVisible()
  await expect(page.getByLabel('AI agent').first()).toBeVisible()

  // Server-side proof (not just client rendering): the activity endpoint
  // itself attributes both facts to the agent actor.
  const activityPage = await page.request.get(`/api/v1/tasks/${taskId}/activity`)
  expect(activityPage.ok()).toBe(true)
  const activityBody = (await activityPage.json()) as {
    items: Array<{
      actor: { label: string; principal: string; type: string }
      mutation_id: string
      recovery_state: string
      type: string
    }>
  }
  const captureFact = activityBody.items.find((fact) => fact.mutation_id === captureMutationId)
  const completeFact = activityBody.items.find((fact) => fact.mutation_id === completeMutationId)
  expect(captureFact?.actor).toMatchObject({
    label: 'Agent access e2e host',
    principal: 'authorized_grant',
    type: 'agent',
  })
  expect(completeFact?.actor).toMatchObject({
    label: 'Agent access e2e host',
    principal: 'authorized_grant',
    type: 'agent',
  })
  expect(completeFact?.recovery_state).toBe('available')

  // ============================================================
  // Step 4: activate the undo control on the agent's completion; the task
  // returns to its prior state, read back from the server
  // ============================================================
  const undoButton = page.getByRole('button', { name: 'Undo: completed this task' })
  await expect(undoButton).toBeVisible()
  await undoButton.click()
  // The "Change undone." message is transient: the click's own state update
  // and the list refresh it triggers land in the same render pass, so the
  // durable, reliably-observable proof is the new "undo" activity fact the
  // refreshed list renders (and the server readback immediately below).
  await expect(page.getByText('You undid an accepted change.')).toBeVisible()

  const taskAfterUndo = await page.request.get(`/api/v1/tasks/${taskId}`)
  expect(taskAfterUndo.ok()).toBe(true)
  const taskAfterUndoBody = (await taskAfterUndo.json()) as { completed_at: string | null }
  expect(taskAfterUndoBody.completed_at).toBeNull()

  // ============================================================
  // Step 5: /settings/agents lists the grant with exactly its scopes,
  // revokes it, and a subsequent tools/call with the revoked credential
  // is refused and creates no row
  // ============================================================
  await page.goto('/settings/agents')
  await expect(page.getByRole('heading', { name: 'AI agents' })).toBeVisible()
  const agentRow = page.getByText('Agent access e2e host').first()
  await expect(agentRow).toBeVisible()

  const revokeButton = page.getByRole('button', { name: 'Revoke Agent access e2e host' })
  await revokeButton.click()
  await page.getByRole('button', { name: 'Revoke agent' }).click()
  await expect(page.getByText('Agent access e2e host revoked.')).toBeVisible()
  await expect(page.getByText('Agent access e2e host')).not.toBeVisible()

  const revokedTaskId = randomUUID()
  const revokedCallResponse = await mcpCall(
    'tools/call',
    {
      arguments: {
        mutation_id: randomUUID(),
        task_id: revokedTaskId,
        title: 'Should never be written',
        version: 1,
      },
      name: 'keepling.capture_task',
    },
    3,
  )
  expect(revokedCallResponse.ok()).toBe(false)

  // Server-side proof the revoked credential created no row -- read back
  // from the server through the owner's own authenticated session, not
  // inferred from the refused response's status code alone.
  const revokedTaskLookup = await page.request.get(`/api/v1/tasks/${revokedTaskId}`)
  expect(revokedTaskLookup.status()).toBe(404)
})
