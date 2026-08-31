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
  it('submits one project and many tags by stable ID while retaining archived history', async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const path = String(input)
      if (path === '/api/v1/inbox') return jsonResponse({ tasks: [task] })
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
        if (path === '/api/v1/inbox') return jsonResponse({ tasks: [task] })
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
})

describe('organization management routes', () => {
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
