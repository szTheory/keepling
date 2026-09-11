import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'

import AgentGrantList from '@/features/agents/AgentGrantList'

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    headers: { 'content-type': status >= 400 ? 'application/problem+json' : 'application/json' },
    status,
  })

const problem = (code = 'service_unavailable', status = 503) => ({
  code,
  recovery_action: 'check_again',
  retryable: true,
  status,
  title: 'Request could not be completed',
  type: `https://keepling.test/problems/${code}`,
})

const scopedAgent = {
  authorized_at: '2026-09-01T10:00:00Z',
  client_kind: 'mcp',
  generation: 1,
  id: 'grant-scoped',
  installation_id: 'installation-scoped',
  label: 'Claude Code',
  last_used_at: '2026-09-09T18:30:00Z',
  revoked: false,
  scope: ['tasks.read', 'tasks.write'],
}

const zeroScopeAgent = {
  authorized_at: '2026-09-02T10:00:00Z',
  client_kind: 'mcp',
  generation: 1,
  id: 'grant-zero-scope',
  installation_id: 'installation-zero-scope',
  label: 'Cowork',
  last_used_at: null,
  revoked: false,
  scope: [],
}

// The shape `GET /api/v1/account/device-grants` actually returns TODAY:
// `KeeplingWeb.DeviceGrantController.grant_response/1` publishes no `scope`
// key at all. That is not the same claim as `scope: []`.
const unreportedScopeAgent = {
  client_kind: 'mcp',
  generation: 1,
  id: 'grant-unreported-scope',
  installation_id: 'installation-unreported-scope',
  label: 'Codex',
  revoked: false,
}

const nonAgentGrant = {
  client_kind: 'electron',
  generation: 1,
  id: 'grant-electron',
  installation_id: 'installation-electron',
  label: 'Jon’s Mac',
  revoked: false,
}

const grantsResponse = (
  deviceGrants = [scopedAgent, zeroScopeAgent, unreportedScopeAgent, nonAgentGrant],
) =>
  jsonResponse({ device_grants: deviceGrants })

const deferred = <Value,>() => {
  let resolve!: (value: Value) => void
  const promise = new Promise<Value>((resolvePromise) => {
    resolve = resolvePromise
  })
  return { promise, resolve }
}

afterEach(() => vi.unstubAllGlobals())

describe('agent grant management', () => {
  it('lists only agent-kind grants with their exact scopes, filtering out non-agent client kinds', async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValueOnce(grantsResponse())
    vi.stubGlobal('fetch', fetchMock)

    render(<AgentGrantList csrfToken="csrf" />)

    expect(await screen.findByText('Claude Code')).toBeVisible()
    expect(screen.getByText('Cowork')).toBeVisible()
    expect(screen.queryByText('Jon’s Mac')).not.toBeInTheDocument()
    expect(screen.getByText('tasks.read')).toBeVisible()
    expect(screen.getByText('tasks.write')).toBeVisible()
  })

  it('renders a zero-scope grant as holding no scopes, never a scope name', async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValueOnce(grantsResponse())
    vi.stubGlobal('fetch', fetchMock)

    render(<AgentGrantList csrfToken="csrf" />)

    const cowork = await screen.findByText('Cowork')
    const row = cowork.closest('li')
    expect(row).not.toBeNull()
    expect(row).toHaveTextContent('No scopes granted')
    expect(row).not.toHaveTextContent('tasks.')
  })

  it('reports an omitted scope list as unreported, never as holding no scopes', async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValueOnce(grantsResponse())
    vi.stubGlobal('fetch', fetchMock)

    render(<AgentGrantList csrfToken="csrf" />)

    const codex = await screen.findByText('Codex')
    const row = codex.closest('li')
    expect(row).not.toBeNull()
    // The distinction this asserts is the point: the server publishing no
    // scope key means we do not know what this agent may do. Rendering that
    // as "No scopes granted" would state, on the screen where the user
    // decides whether to revoke, that the agent can do nothing.
    expect(row).not.toHaveTextContent('No scopes granted')
    expect(row).toHaveTextContent('Not yet reported')
    expect(row).not.toHaveTextContent('tasks.')
  })

  it('shows the no-agents empty state without rendering an empty table', async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValueOnce(grantsResponse([nonAgentGrant]))
    vi.stubGlobal('fetch', fetchMock)

    render(<AgentGrantList csrfToken="csrf" />)

    expect(await screen.findByText('No AI agents are authorized.')).toBeVisible()
    expect(screen.queryByRole('list', { name: 'Authorized AI agents' })).not.toBeInTheDocument()
  })

  it('confirms revocation naming the agent, traps focus, and restores the trigger on cancel', async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValueOnce(grantsResponse())
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<AgentGrantList csrfToken="csrf" />)

    const trigger = await screen.findByRole('button', { name: 'Revoke Claude Code' })
    await user.click(trigger)

    const dialog = screen.getByRole('alertdialog', { name: 'Revoke Claude Code?' })
    expect(dialog).toHaveTextContent(
      'Claude Code will lose access to Keepling immediately. Its next request will be refused.',
    )
    await waitFor(() =>
      expect(screen.getByRole('button', { name: 'Keep authorized' })).toHaveFocus(),
    )
    await user.keyboard('{Escape}')
    await waitFor(() => expect(trigger).toHaveFocus())
    expect(fetchMock.mock.calls.filter(([, init]) => init?.method === 'DELETE')).toHaveLength(0)
  })

  it('revokes an agent and removes its row after a confirmed commit', async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(grantsResponse())
      .mockResolvedValueOnce(
        jsonResponse({ installation_id: 'installation-scoped', status: 'device_grant_revoked' }),
      )
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<AgentGrantList csrfToken="csrf" />)

    await user.click(await screen.findByRole('button', { name: 'Revoke Claude Code' }))
    await user.click(screen.getByRole('button', { name: 'Revoke agent' }))

    expect(await screen.findByText('Claude Code revoked.')).toBeVisible()
    expect(screen.queryByText('Claude Code')).not.toBeInTheDocument()
    const deleteCalls = fetchMock.mock.calls.filter(([, init]) => init?.method === 'DELETE')
    expect(deleteCalls).toHaveLength(1)
    expect(String(deleteCalls[0]![0])).toBe('/api/v1/account/device-grants/installation-scoped')
  })

  it('reports an uncertain revocation as still authorized only after inventory proves presence', async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(grantsResponse())
      .mockResolvedValueOnce(jsonResponse(problem(), 503))
      .mockResolvedValueOnce(grantsResponse())
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<AgentGrantList csrfToken="csrf" />)

    await user.click(await screen.findByRole('button', { name: 'Revoke Claude Code' }))
    await user.click(screen.getByRole('button', { name: 'Revoke agent' }))

    expect(await screen.findByText('Claude Code remains authorized.')).toBeVisible()
    expect(screen.getByText('Claude Code')).toBeVisible()
  })

  it('proves an after-commit revocation from absence without retrying DELETE', async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(grantsResponse())
      .mockResolvedValueOnce(jsonResponse(problem(), 503))
      .mockResolvedValueOnce(grantsResponse([zeroScopeAgent, nonAgentGrant]))
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<AgentGrantList csrfToken="csrf" />)

    await user.click(await screen.findByRole('button', { name: 'Revoke Claude Code' }))
    await user.click(screen.getByRole('button', { name: 'Revoke agent' }))

    expect(await screen.findByText('Claude Code revoked.')).toBeVisible()
    expect(screen.queryByText('Claude Code')).not.toBeInTheDocument()
    expect(fetchMock.mock.calls.filter(([, init]) => init?.method === 'DELETE')).toHaveLength(1)
  })

  it('keeps an unreadable revocation unknown and Check again repeats only the inventory read', async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(grantsResponse())
      .mockResolvedValueOnce(jsonResponse(problem(), 503))
      .mockRejectedValueOnce(new TypeError('inventory unavailable'))
      .mockResolvedValueOnce(grantsResponse([zeroScopeAgent, nonAgentGrant]))
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<AgentGrantList csrfToken="csrf" />)

    await user.click(await screen.findByRole('button', { name: 'Revoke Claude Code' }))
    await user.click(screen.getByRole('button', { name: 'Revoke agent' }))

    expect(
      await screen.findByText('Keepling could not confirm whether Claude Code was revoked.'),
    ).toBeVisible()
    await user.click(screen.getByRole('button', { name: 'Check revocation again' }))

    expect(await screen.findByText('Claude Code revoked.')).toBeVisible()
  })

  it('reconciles an authentication-after-commit revocation without replaying DELETE', async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(grantsResponse())
      .mockResolvedValueOnce(jsonResponse(problem('recent_authentication_required', 401), 401))
      .mockResolvedValueOnce(grantsResponse([zeroScopeAgent, nonAgentGrant]))
    vi.stubGlobal('fetch', fetchMock)
    const onAuthenticationRequired = vi.fn()
    const user = userEvent.setup()

    render(<AgentGrantList csrfToken="csrf" onAuthenticationRequired={onAuthenticationRequired} />)

    await user.click(await screen.findByRole('button', { name: 'Revoke Claude Code' }))
    await user.click(screen.getByRole('button', { name: 'Revoke agent' }))
    await waitFor(() => expect(onAuthenticationRequired).toHaveBeenCalledOnce())
    const [, resume] = onAuthenticationRequired.mock.calls[0] as [unknown, () => Promise<void>]
    await resume()

    expect(await screen.findByText('Claude Code revoked.')).toBeVisible()
  })

  it('retries a revocation after reauthentication when inventory proves it was not accepted', async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(grantsResponse())
      .mockResolvedValueOnce(jsonResponse(problem('recent_authentication_required', 401), 401))
      .mockResolvedValueOnce(grantsResponse())
      .mockResolvedValueOnce(
        jsonResponse({ installation_id: 'installation-scoped', status: 'device_grant_revoked' }),
      )
    vi.stubGlobal('fetch', fetchMock)
    const onAuthenticationRequired = vi.fn()
    const user = userEvent.setup()

    render(<AgentGrantList csrfToken="csrf" onAuthenticationRequired={onAuthenticationRequired} />)

    await user.click(await screen.findByRole('button', { name: 'Revoke Claude Code' }))
    await user.click(screen.getByRole('button', { name: 'Revoke agent' }))
    await waitFor(() => expect(onAuthenticationRequired).toHaveBeenCalledOnce())
    const [, resume] = onAuthenticationRequired.mock.calls[0] as [
      unknown,
      (csrfToken: string) => Promise<void>,
    ]
    await resume('fresh-csrf')

    expect(await screen.findByText('Claude Code revoked.')).toBeVisible()
    expect(screen.queryByText('Claude Code')).not.toBeInTheDocument()
  })

  it('serializes a slow revocation and keeps the busy grant disabled until settlement', async () => {
    const slowRevoke = deferred<Response>()
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(grantsResponse())
      .mockImplementationOnce(() => slowRevoke.promise)
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<AgentGrantList csrfToken="csrf" />)

    await user.click(await screen.findByRole('button', { name: 'Revoke Claude Code' }))
    await user.click(screen.getByRole('button', { name: 'Revoke agent' }))

    expect(screen.getByRole('button', { name: 'Revoke Cowork' })).toBeDisabled()

    slowRevoke.resolve(
      jsonResponse({ installation_id: 'installation-scoped', status: 'device_grant_revoked' }),
    )
    await waitFor(() => expect(screen.getByRole('button', { name: 'Revoke Cowork' })).toBeEnabled())
  })
})
