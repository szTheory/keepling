import { normalize, resolve, sep } from 'node:path'

/**
 * Packaged local-content, navigation, permission, and IPC-sender policy for
 * the desktop shell (T-KPL03-10-01/02). Every renderer surface -- the main
 * window today, and any future utility window such as Quick Entry/Settings
 * (Plan 03-04's `preload/utility-preload.ts`, wired in a later plan) -- gets
 * this policy for free by construction: the navigation/window-open/
 * permission checks below are applied at the Electron `session` level in
 * `main/index.ts`, not per-BrowserWindow, so a new window created by a later
 * plan inherits the same restrictive defaults without editing this file.
 *
 * Every function here is pure (no live Electron objects in its signature) so
 * `test/ipc/hostile-bridge.test.ts` can exercise every hostile case directly
 * without launching a real Electron process.
 */

const APP_PROTOCOL_SCHEME = 'app'
const APP_PROTOCOL_HOST = 'renderer'
const APP_PROTOCOL_ORIGIN = `${APP_PROTOCOL_SCHEME}://${APP_PROTOCOL_HOST}`

const CONTENT_SECURITY_POLICY = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data:",
  "font-src 'self'",
  "connect-src 'self'",
  "object-src 'none'",
  "base-uri 'none'",
  "form-action 'none'",
  "frame-ancestors 'none'",
].join('; ')

/** Bounded error surfaced to the renderer for any security-policy rejection. Never exposes internal detail. */
class IpcSecurityError extends Error {
  readonly code: string

  constructor(code: string) {
    super(code)
    this.name = 'IpcSecurityError'
    this.code = code
  }
}

/**
 * Resolves a requested `app://renderer/<path>` URL to the real file it may
 * load, or `null` if the request escapes the packaged renderer root (path
 * traversal, wrong scheme, wrong host, or an absolute-path override).
 * Content substitution and directory-traversal navigation fail closed here
 * before any filesystem read happens.
 */
const resolvePackagedAssetPath = (requestUrl: string, rendererRoot: string): string | null => {
  let parsed: URL
  try {
    parsed = new URL(requestUrl)
  } catch {
    return null
  }
  if (parsed.protocol !== `${APP_PROTOCOL_SCHEME}:`) return null
  if (parsed.host !== APP_PROTOCOL_HOST && parsed.host !== '') return null

  const requestedPath = decodeURIComponent(parsed.pathname === '' || parsed.pathname === '/' ? '/index.html' : parsed.pathname)
  const normalizedRoot = resolve(rendererRoot)
  const candidate = normalize(resolve(normalizedRoot, `.${requestedPath}`))
  const isWithinRoot = candidate === normalizedRoot || candidate.startsWith(normalizedRoot + sep)
  return isWithinRoot ? candidate : null
}

/** Only same-origin `app://renderer/...` navigation is ever allowed (e.g. a reload). Everything else -- http(s), file, javascript:, data:, another app:// host -- fails closed. */
const isAllowedNavigationTarget = (url: string): boolean => {
  try {
    const parsed = new URL(url)
    return parsed.protocol === `${APP_PROTOCOL_SCHEME}:` && parsed.host === APP_PROTOCOL_HOST
  } catch {
    return false
  }
}

/** Explicit allowlist for links the app may hand off to the OS browser via `shell.openExternal`. Empty today -- ready for a future explicit, reviewed addition, never a wildcard. */
const EXTERNAL_LINK_ALLOWED_ORIGINS: ReadonlySet<string> = new Set()

const isAllowedExternalLinkTarget = (url: string): boolean => {
  try {
    const parsed = new URL(url)
    return (parsed.protocol === 'https:') && EXTERNAL_LINK_ALLOWED_ORIGINS.has(parsed.origin)
  } catch {
    return false
  }
}

/** Every Electron permission request (camera, microphone, geolocation, notifications, clipboard-read, etc.) is denied. The desktop shell needs none of them. */
const ALLOWED_PERMISSIONS: ReadonlySet<string> = new Set()

const shouldGrantPermission = (permission: string): boolean => ALLOWED_PERMISSIONS.has(permission)

type TrustedSenderInput = {
  isMainFrame: boolean
  senderFrameUrl: string | null
  senderId: number
  trustedSenderId: number
}

/**
 * The single sender/frame trust decision every `ipcMain` handler in
 * `main/index.ts` consults before touching `DesktopApplication`. A request
 * is trusted only when it comes from the exact expected `WebContents` id,
 * from that WebContents' MAIN frame (never a subframe -- a compromised
 * subframe, e.g. from an accidental navigation, must not inherit trust),
 * and from a frame whose URL is actually inside the packaged renderer
 * origin. A forged sender id, a subframe, or a frame URL outside `app://
 * renderer/` all fail closed.
 */
const isTrustedIpcSender = (input: TrustedSenderInput): boolean =>
  input.isMainFrame
  && input.senderId === input.trustedSenderId
  && input.senderFrameUrl !== null
  && (input.senderFrameUrl === APP_PROTOCOL_ORIGIN || input.senderFrameUrl.startsWith(`${APP_PROTOCOL_ORIGIN}/`))

/** Throws a bounded `IpcSecurityError` unless the sender is trusted. */
const assertTrustedIpcSender = (input: TrustedSenderInput): void => {
  if (!isTrustedIpcSender(input)) throw new IpcSecurityError('untrusted_sender')
}

/** Parses `value` against `schema`, converting any parse failure into a bounded `IpcSecurityError` -- never leaks raw Zod internals across the IPC boundary. */
const parseTrustedRequest = <Value>(schema: { parse: (value: unknown) => Value }, value: unknown): Value => {
  try {
    return schema.parse(value)
  } catch {
    throw new IpcSecurityError('invalid_request')
  }
}

export {
  APP_PROTOCOL_HOST,
  APP_PROTOCOL_ORIGIN,
  APP_PROTOCOL_SCHEME,
  CONTENT_SECURITY_POLICY,
  IpcSecurityError,
  assertTrustedIpcSender,
  isAllowedExternalLinkTarget,
  isAllowedNavigationTarget,
  isTrustedIpcSender,
  parseTrustedRequest,
  resolvePackagedAssetPath,
  shouldGrantPermission,
}
export type { TrustedSenderInput }
