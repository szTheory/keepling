import { useEffect, useState, type ReactNode } from 'react'

import LoginForm from '@/features/auth/LoginForm'
import Reauthenticate, { type InterruptedIntent } from '@/features/auth/Reauthenticate'
import RecoveryReset from '@/features/auth/RecoveryReset'
import SetupForm from '@/features/auth/SetupForm'
import ActivityList from '@/features/activity/ActivityList'
import OrganizationFields, {
  OrganizationManager,
} from '@/features/organizations/OrganizationFields'
import TaskList from '@/features/lists/TaskList'
import TaskEditor from '@/features/tasks/TaskEditor'
import type { CommandAcknowledgement } from '@/api/keepling'

type AppRoutesProps = {
  authenticated: boolean
  authenticatedContent?: ReactNode
  csrfToken?: string
  interruption?: InterruptedIntent | null
  onAcknowledged?: (acknowledgement: CommandAcknowledgement) => void
  onAuthenticated?: (csrfToken: string) => void
  onAuthenticationRequired?: (
    intent: InterruptedIntent,
    resume: (csrfToken: string) => Promise<void>,
  ) => void
  onReauthenticated?: (interruption: InterruptedIntent, csrfToken: string) => void
}

const routeToken = (pathname: string, prefix: string) => {
  if (!pathname.startsWith(prefix)) return null
  const raw = pathname.slice(prefix.length)
  if (raw === '' || raw.includes('/')) return null
  try {
    return decodeURIComponent(raw)
  } catch {
    return null
  }
}

const decodeRoutePart = (raw: string | undefined) => {
  if (!raw) return null
  try {
    return decodeURIComponent(raw)
  } catch {
    return null
  }
}

const navigate = (pathname: string) => {
  window.history.replaceState({}, '', pathname)
  window.dispatchEvent(new PopStateEvent('popstate'))
}

function AppRoutes({
  authenticated,
  authenticatedContent,
  csrfToken,
  interruption,
  onAcknowledged = () => undefined,
  onAuthenticated = () => undefined,
  onAuthenticationRequired,
  onReauthenticated = () => undefined,
}: AppRoutesProps) {
  const [locationKey, setLocationKey] = useState(
    `${window.location.pathname}${window.location.search}`,
  )

  useEffect(() => {
    const update = () => setLocationKey(`${window.location.pathname}${window.location.search}`)
    window.addEventListener('popstate', update)
    return () => window.removeEventListener('popstate', update)
  }, [])

  const location = new URL(locationKey, window.location.origin)
  const { pathname } = location

  const handleAuthenticated = (nextCsrfToken: string) => {
    onAuthenticated(nextCsrfToken)
    navigate('/')
  }
  const setupToken = routeToken(pathname, '/setup/') ??
    (pathname === '/setup' ? location.searchParams.get('token') : null)
  if (setupToken) return <SetupForm token={setupToken} />

  const recoveryToken = routeToken(pathname, '/recover/') ??
    (pathname === '/recover' ? location.searchParams.get('token') : null)
  if (recoveryToken) {
    return <RecoveryReset onAuthenticated={handleAuthenticated} token={recoveryToken} />
  }

  if (interruption && csrfToken) {
    return (
      <>
        {authenticatedContent}
        <div className="fixed inset-0 z-50 overflow-y-auto bg-background/95 px-4 py-16">
          <div className="mx-auto max-w-2xl">
            <Reauthenticate
              csrfToken={csrfToken}
              interruption={interruption}
              onAuthenticated={onReauthenticated}
            />
          </div>
        </div>
      </>
    )
  }

  if (!authenticated || pathname === '/login') {
    if (authenticated) {
      return (
        <main className="p-6" id="main-content">
          <h1 className="text-[1.75rem] font-semibold">Already signed in</h1>
          <a className="mt-4 inline-flex min-h-11 items-center font-semibold text-primary underline" href="/">
            Return to Keepling
          </a>
        </main>
      )
    }
    return <LoginForm onAuthenticated={handleAuthenticated} />
  }

  if (pathname === '/today' && csrfToken) return <TaskList csrfToken={csrfToken} view="today" />
  if (pathname === '/upcoming' && csrfToken) return <TaskList csrfToken={csrfToken} view="upcoming" />
  if (pathname === '/completed' && csrfToken) return <TaskList csrfToken={csrfToken} view="completed" />
  if (pathname === '/inbox' && csrfToken) return <TaskList csrfToken={csrfToken} view="inbox" />

  if (pathname === '/projects' && csrfToken) {
    return <OrganizationManager csrfToken={csrfToken} kind="project" />
  }

  if (pathname === '/tags' && csrfToken) {
    return <OrganizationManager csrfToken={csrfToken} kind="tag" />
  }

  const assignmentMatch = pathname.match(/^\/tasks\/([^/]+)\/organizations$/)
  const assignmentTaskId = decodeRoutePart(assignmentMatch?.[1])
  if (assignmentTaskId && csrfToken) {
    return <OrganizationFields csrfToken={csrfToken} taskId={assignmentTaskId} />
  }

  const taskId = routeToken(pathname, '/tasks/')
  if (taskId && csrfToken) {
    return (
      <>
        {authenticatedContent ? <div className="hidden lg:block">{authenticatedContent}</div> : null}
        <div className="min-h-screen bg-card [&>main]:!static [&>main]:!min-h-0 [&>main]:!min-w-0 [&>main]:!w-auto [&>main]:!overflow-visible [&>main]:!border-0 lg:fixed lg:inset-y-0 lg:right-0 lg:z-20 lg:w-[calc(100%-41.5rem)] lg:min-w-[30rem] lg:overflow-y-auto lg:border-l lg:border-border">
          <TaskEditor
            csrfToken={csrfToken}
            onAcknowledged={onAcknowledged}
            onAuthenticationRequired={onAuthenticationRequired}
            onNavigate={navigate}
            taskId={taskId}
          />
          <ActivityList taskId={taskId} />
        </div>
      </>
    )
  }

  return authenticatedContent ?? (
    <main className="p-6" id="main-content">
      <h1 className="text-[1.75rem] font-semibold">Keepling</h1>
    </main>
  )
}

export default AppRoutes
