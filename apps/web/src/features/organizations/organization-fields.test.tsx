import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'

import AppRoutes from '@/app/routes'
import OrganizationFields, { OrganizationManager } from '@/features/organizations/OrganizationFields'

const taskId = '018d8b40-2f10-7b1a-9d71-263f4af77001'
const archivedProjectId = '018d8b40-2f10-7b1a-9d71-263f4af77002'
const activeProjectId = '018d8b40-2f10-7b1a-9d71-263f4af77003'
const archivedTagId = '018d8b40-2f10-7b1a-9d71-263f4af77004'
const activeTagId = '018d8b40-2f10-7b1a-9d71-263f4af77005'

const task = {
  captured_at: '2026-08-30T20:00:00Z',
  id: taskId,
  inbox_state: 'inbox',
  notes: '',
  project: { archived: true, id: archivedProjectId, name: 'Old home' },
  revision: 3,
  tags: [{ archived: true, id: archivedTagId, name: 'Old errand' }],
  title: 'Buy batteries',
}

const organizations = [
  {
    archived: true,
    assignable: false,
    id: archivedProjectId,
    kind: 'project',
    name: 'Old home',
    revision: 2,
  },
  {
    archived: false,
    assignable: true,
    id: activeProjectId,
    kind: 'project',
    name: 'Home',
    revision: 1,
  },
  {
    archived: true,
    assignable: false,
    id: archivedTagId,
    kind: 'tag',
    name: 'Old errand',
    revision: 2,
  },
  {
    archived: false,
    assignable: true,
    id: activeTagId,
    kind: 'tag',
    name: 'Errand',
    revision: 1,
  },
] as const

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    headers: { 'content-type': status >= 400 ? 'application/problem+json' : 'application/json' },
    status,
  })

const problem = (code: string, title: string, extensions: Record<string, unknown> = {}) => ({
  code,
  detail: title,
  recovery_action: 'review_organizations',
  retryable: false,
  status: 409,
  title,
  type: `/problems/${code}`,
  ...extensions,
})

afterEach(() => {
  vi.unstubAllGlobals()
  window.history.replaceState({}, '', '/')
})

describe('organization assignment fields', () => {
  const acceptedAssignment = (body: string) => {
    const request = JSON.parse(body) as { mutation_id: string }
    return {
      mutation_id: request.mutation_id,
      outcome: 'accepted',
      revision: 4,
      snapshot: {
        ...task,
        project: { archived: false, id: activeProjectId, name: 'Home' },
        revision: 4,
      },
      task_id: taskId,
      warnings: [],
    }
  }

  const beginAssignment = async (user: ReturnType<typeof userEvent.setup>) => {
    await user.selectOptions(await screen.findByRole('combobox', { name: 'Project' }), activeProjectId)
    await user.click(screen.getByRole('button', { name: 'Save assignments' }))
  }

  it('submits one project and many tags by stable ID while retaining archived history', async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const path = String(input)
      if (path === `/api/v1/tasks/${taskId}`) return jsonResponse(task)
      if (path === '/api/v1/organizations') return jsonResponse({ organizations })
      if (path === '/api/v1/commands/assign-task-organizations') {
        const request = JSON.parse(String(init?.body)) as { mutation_id: string }
        return jsonResponse({
          mutation_id: request.mutation_id,
          outcome: 'accepted',
          revision: 4,
          snapshot: {
            ...task,
            project: { archived: false, id: activeProjectId, name: 'Home' },
            revision: 4,
            tags: [
              { archived: true, id: archivedTagId, name: 'Old errand' },
              { archived: false, id: activeTagId, name: 'Errand' },
            ],
          },
          task_id: taskId,
          warnings: [],
        })
      }
      throw new Error(`Unexpected request ${path}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<OrganizationFields csrfToken="csrf" taskId={taskId} />)

    const project = await screen.findByRole('combobox', { name: 'Project' })
    expect(project).toHaveValue(archivedProjectId)
    expect(within(project).getByRole('option', { name: 'Old home — Archived' })).toBeVisible()
    expect(within(project).queryByRole('option', { name: /Old errand/ })).not.toBeInTheDocument()

    expect(screen.getByText('Old errand')).toBeVisible()
    expect(screen.getByText('Archived', { selector: '[data-organization-status]' })).toBeVisible()
    expect(screen.getByRole('checkbox', { name: 'Old errand — Archived' })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: 'Old errand — Archived' })).toBeEnabled()

    await user.selectOptions(project, activeProjectId)
    await user.click(screen.getByRole('checkbox', { name: 'Errand' }))
    await user.click(screen.getByRole('button', { name: 'Save assignments' }))

    const assignmentCall = fetchMock.mock.calls.find(
      ([input]) => String(input) === '/api/v1/commands/assign-task-organizations',
    )
    const request = JSON.parse(String(assignmentCall?.[1]?.body)) as Record<string, unknown>

    expect(request).toMatchObject({
      base_values: { project_id: archivedProjectId, tag_ids: [archivedTagId] },
      expected_revision: 3,
      fields: {
        project_id: activeProjectId,
        tag_ids: [archivedTagId, activeTagId],
      },
      task_id: taskId,
      version: 1,
    })
    expect(JSON.stringify(request)).not.toContain('Old home')
    expect(JSON.stringify(request)).not.toContain('Errand')
    expect(await screen.findByRole('status')).toHaveTextContent('Task assignments saved.')
  })

  it('keeps a stale conflict visible and preserves the chosen IDs', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (input: RequestInfo | URL) => {
        const path = String(input)
        if (path === `/api/v1/tasks/${taskId}`) return jsonResponse(task)
        if (path === '/api/v1/organizations') return jsonResponse({ organizations })
        if (path === '/api/v1/commands/assign-task-organizations') {
          return jsonResponse(
            problem('task_assignment_conflict', 'Task assignments changed elsewhere', {
              affected_fields: ['project_id'],
              current_revision: 4,
            }),
            409,
          )
        }
        throw new Error(`Unexpected request ${path}`)
      }),
    )
    const user = userEvent.setup()

    render(<OrganizationFields csrfToken="csrf" taskId={taskId} />)

    const project = await screen.findByRole('combobox', { name: 'Project' })
    await user.selectOptions(project, activeProjectId)
    await user.click(screen.getByRole('button', { name: 'Save assignments' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Task assignments changed elsewhere',
    )
    expect(project).toHaveValue(activeProjectId)
  })

  it('retains exact bytes through before-acceptance authentication and continuation', async () => {
    const bodies: string[] = []
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const path = String(input)
      if (path === `/api/v1/tasks/${taskId}`) return jsonResponse(task)
      if (path === '/api/v1/organizations') return jsonResponse({ organizations })
      if (path === '/api/v1/commands/assign-task-organizations') {
        const body = String(init?.body)
        bodies.push(body)
        return bodies.length === 1
          ? jsonResponse(
              problem('authentication_required', 'Authentication required', {
                recovery_action: 'sign_in',
                status: 401,
              }),
              401,
            )
          : jsonResponse(acceptedAssignment(body))
      }
      if (path.startsWith('/api/v1/mutations/')) {
        return jsonResponse(problem('mutation_not_found', 'Mutation not found', { status: 404 }), 404)
      }
      throw new Error(`Unexpected request ${path}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const onAuthenticationRequired = vi.fn()
    const user = userEvent.setup()
    render(
      <OrganizationFields
        csrfToken="expired-csrf"
        onAuthenticationRequired={onAuthenticationRequired}
        taskId={taskId}
      />,
    )

    await beginAssignment(user)
    await user.click(await screen.findByRole('button', { name: 'Sign in and continue' }))
    const [intent, resume] = onAuthenticationRequired.mock.calls[0] as [
      { authentication: string; kind: string; mutationId: string },
      (csrfToken: string) => Promise<void>,
    ]
    expect(intent).toMatchObject({ authentication: 'sign_in', kind: 'submitted-unknown' })
    await resume('new-session-csrf')

    expect(await screen.findByRole('status')).toHaveTextContent('Task assignments saved.')
    expect(bodies).toHaveLength(2)
    expect(bodies[1]).toBe(bodies[0])
  })

  it('reconciles an after-commit authentication replacement with the original identity', async () => {
    const bodies: string[] = []
    let stored: ReturnType<typeof acceptedAssignment> | null = null
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const path = String(input)
      if (path === `/api/v1/tasks/${taskId}`) return jsonResponse(task)
      if (path === '/api/v1/organizations') return jsonResponse({ organizations })
      if (path === '/api/v1/commands/assign-task-organizations') {
        const body = String(init?.body)
        bodies.push(body)
        stored ??= acceptedAssignment(body)
        return bodies.length === 1
          ? jsonResponse(
              problem('authentication_required', 'Authentication required', {
                recovery_action: 'sign_in',
                status: 401,
              }),
              401,
            )
          : jsonResponse(stored)
      }
      if (path.startsWith('/api/v1/mutations/')) return jsonResponse(stored)
      throw new Error(`Unexpected request ${path}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const onAuthenticationRequired = vi.fn()
    const user = userEvent.setup()
    render(
      <OrganizationFields
        csrfToken="expired-csrf"
        onAuthenticationRequired={onAuthenticationRequired}
        taskId={taskId}
      />,
    )

    await beginAssignment(user)
    await user.click(await screen.findByRole('button', { name: 'Sign in and continue' }))
    const [, resume] = onAuthenticationRequired.mock.calls[0] as [unknown, (csrf: string) => Promise<void>]
    await resume('new-session-csrf')

    expect(await screen.findByRole('status')).toHaveTextContent('Task assignments saved.')
    expect(bodies).toHaveLength(1)
  })

  it('looks up an accepted assignment receipt after response loss without resending', async () => {
    const bodies: string[] = []
    let stored: ReturnType<typeof acceptedAssignment> | null = null
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const path = String(input)
      if (path === `/api/v1/tasks/${taskId}`) return jsonResponse(task)
      if (path === '/api/v1/organizations') return jsonResponse({ organizations })
      if (path === '/api/v1/commands/assign-task-organizations') {
        const body = String(init?.body)
        bodies.push(body)
        stored = acceptedAssignment(body)
        throw new TypeError('response lost after acceptance')
      }
      if (path.startsWith('/api/v1/mutations/')) return jsonResponse(stored)
      throw new Error(`Unexpected request ${path}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    render(<OrganizationFields csrfToken="csrf" taskId={taskId} />)

    await beginAssignment(user)
    await user.click(await screen.findByRole('button', { name: 'Check again' }))

    expect(await screen.findByRole('status')).toHaveTextContent('Task assignments saved.')
    expect(bodies).toHaveLength(1)
    const mutationId = (JSON.parse(bodies[0] ?? '{}') as { mutation_id: string }).mutation_id
    expect(fetchMock.mock.calls.some(([input]) =>
      String(input) === `/api/v1/mutations/${mutationId}`,
    )).toBe(true)
  })

  it('checks a 5xx unknown receipt before replaying the immutable assignment bytes', async () => {
    const bodies: string[] = []
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const path = String(input)
      if (path === `/api/v1/tasks/${taskId}`) return jsonResponse(task)
      if (path === '/api/v1/organizations') return jsonResponse({ organizations })
      if (path === '/api/v1/commands/assign-task-organizations') {
        const body = String(init?.body)
        bodies.push(body)
        return bodies.length === 1
          ? jsonResponse(problem('service_unavailable', 'Service unavailable', { status: 503 }), 503)
          : jsonResponse(acceptedAssignment(body))
      }
      if (path.startsWith('/api/v1/mutations/')) {
        return jsonResponse(problem('mutation_not_found', 'Mutation not found', { status: 404 }), 404)
      }
      throw new Error(`Unexpected request ${path}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    render(<OrganizationFields csrfToken="csrf" taskId={taskId} />)

    await beginAssignment(user)
    await user.click(await screen.findByRole('button', { name: 'Check again' }))

    expect(await screen.findByRole('status')).toHaveTextContent('Task assignments saved.')
    expect(bodies).toHaveLength(2)
    expect(bodies[1]).toBe(bodies[0])
  })
})

describe('organization management routes', () => {
  it('reconciles accepted response loss for create, rename, archive, and unarchive by exact identity', async () => {
    const stored = new Map<string, Record<string, unknown>>()
    const commandBodies = new Map<string, string[]>()

    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const path = String(input)
      if (path === '/api/v1/organizations') return jsonResponse({ organizations })

      if (path.startsWith('/api/v1/mutations/')) {
        const mutationId = path.slice('/api/v1/mutations/'.length)
        const acknowledgement = stored.get(mutationId)
        if (!acknowledgement) throw new Error(`Missing stored mutation ${mutationId}`)
        return jsonResponse(acknowledgement)
      }

      if (path.startsWith('/api/v1/commands/')) {
        const body = String(init?.body)
        commandBodies.set(path, [...(commandBodies.get(path) ?? []), body])
        const request = JSON.parse(body) as {
          expected_revision?: number
          kind?: 'project' | 'tag'
          mutation_id: string
          name?: string
          organization_id: string
        }
        const original = organizations.find(
          (organization) => organization.id === request.organization_id,
        )

        const snapshot =
          path.endsWith('/create-organization')
            ? {
                archived: false,
                assignable: true,
                id: request.organization_id,
                kind: request.kind,
                name: request.name,
                revision: 1,
              }
            : path.endsWith('/rename-organization')
              ? {
                  ...original,
                  name: request.name,
                  revision: (request.expected_revision ?? 0) + 1,
                }
              : path.endsWith('/archive-organization')
                ? {
                    ...original,
                    archived: true,
                    assignable: false,
                    revision: (request.expected_revision ?? 0) + 1,
                  }
                : {
                    ...original,
                    archived: false,
                    assignable: true,
                    revision: (request.expected_revision ?? 0) + 1,
                  }

        stored.set(request.mutation_id, {
          mutation_id: request.mutation_id,
          organization_id: request.organization_id,
          outcome: 'accepted',
          revision: snapshot.revision,
          snapshot,
        })
        throw new TypeError('response lost after acceptance')
      }

      throw new Error(`Unexpected request ${path}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<OrganizationManager csrfToken="csrf" kind="project" />)

    await user.type(await screen.findByLabelText('New project name'), 'Garden')
    await user.click(screen.getByRole('button', { name: 'Create project' }))
    await user.click(await screen.findByRole('button', { name: 'Check again' }))
    expect(await screen.findByRole('status')).toHaveTextContent('Project created.')

    const homeName = screen.getByLabelText('Rename Home')
    await user.clear(homeName)
    await user.type(homeName, 'House')
    await user.click(within(homeName.closest('li')!).getByRole('button', { name: 'Save name' }))
    await user.click(await screen.findByRole('button', { name: 'Check again' }))
    expect(await screen.findByRole('status')).toHaveTextContent('Home renamed.')

    await user.click(screen.getByRole('button', { name: 'Archive House' }))
    await user.click(screen.getByRole('button', { name: 'Confirm archive House' }))
    await user.click(await screen.findByRole('button', { name: 'Check again' }))
    expect(await screen.findByRole('status')).toHaveTextContent('House archived.')

    await user.click(screen.getByRole('button', { name: 'Unarchive Old home' }))
    await user.click(await screen.findByRole('button', { name: 'Check again' }))
    expect(await screen.findByRole('status')).toHaveTextContent('Old home unarchived.')

    for (const path of [
      '/api/v1/commands/create-organization',
      '/api/v1/commands/rename-organization',
      '/api/v1/commands/archive-organization',
      '/api/v1/commands/unarchive-organization',
    ]) {
      const [body] = commandBodies.get(path) ?? []
      expect(commandBodies.get(path)).toHaveLength(1)
      const mutationId = (JSON.parse(body ?? '{}') as { mutation_id?: string }).mutation_id
      expect(fetchMock.mock.calls.some(([input]) =>
        String(input) === `/api/v1/mutations/${mutationId}`,
      )).toBe(true)
    }
  })

  it('creates with generated identities and names exact project archive blockers', async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const path = String(input)
      if (path === '/api/v1/organizations') return jsonResponse({ organizations })
      if (path === '/api/v1/commands/create-organization') {
        const request = JSON.parse(String(init?.body)) as {
          mutation_id: string
          organization_id: string
        }
        return jsonResponse(
          {
            mutation_id: request.mutation_id,
            organization_id: request.organization_id,
            outcome: 'accepted',
            revision: 1,
            snapshot: {
              archived: false,
              assignable: true,
              id: request.organization_id,
              kind: 'project',
              name: 'Garden',
              revision: 1,
            },
          },
          201,
        )
      }
      if (path === '/api/v1/commands/archive-organization') {
        return jsonResponse(
          problem('project_archive_blocked', 'Project has active unfinished tasks', {
            active_unfinished_task_count: 2,
          }),
          409,
        )
      }
      throw new Error(`Unexpected request ${path}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<OrganizationManager csrfToken="csrf" kind="project" />)

    await user.type(await screen.findByLabelText('New project name'), 'Garden')
    await user.click(screen.getByRole('button', { name: 'Create project' }))

    const createCall = fetchMock.mock.calls.find(
      ([input]) => String(input) === '/api/v1/commands/create-organization',
    )
    const createRequest = JSON.parse(String(createCall?.[1]?.body)) as Record<string, unknown>
    expect(createRequest).toMatchObject({ kind: 'project', name: 'Garden', version: 1 })
    expect(createRequest.organization_id).toMatch(/^[0-9a-f-]{36}$/)
    expect(createRequest.mutation_id).toMatch(/^[0-9a-f-]{36}$/)

    await user.click(screen.getByRole('button', { name: 'Archive Home' }))
    expect(screen.getByText("Archive Home? It won’t appear in new assignments.")).toBeVisible()
    await user.click(screen.getByRole('button', { name: 'Confirm archive Home' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Home still has 2 active unfinished tasks. Nothing changed.',
    )
    expect(screen.getByDisplayValue('Home')).toBeVisible()
  })

  it('surfaces unarchive collisions and exposes routed Projects and Tags management', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (input: RequestInfo | URL) => {
        const path = String(input)
        if (path === '/api/v1/organizations') return jsonResponse({ organizations })
        if (path === '/api/v1/commands/unarchive-organization') {
          return jsonResponse(
            problem(
              'active_organization_name_collision',
              'That active name is already in use',
            ),
            409,
          )
        }
        throw new Error(`Unexpected request ${path}`)
      }),
    )
    const user = userEvent.setup()

    const { unmount } = render(<OrganizationManager csrfToken="csrf" kind="tag" />)
    await user.click(await screen.findByRole('button', { name: 'Unarchive Old errand' }))
    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Old errand remains archived because an active tag already uses that name.',
    )
    unmount()

    window.history.replaceState({}, '', '/projects')
    const projects = render(<AppRoutes authenticated csrfToken="csrf" />)
    expect(await screen.findByRole('heading', { name: 'Projects' })).toBeVisible()
    projects.unmount()

    window.history.replaceState({}, '', '/tags')
    render(<AppRoutes authenticated csrfToken="csrf" />)
    expect(await screen.findByRole('heading', { name: 'Tags' })).toBeVisible()
  })
})
