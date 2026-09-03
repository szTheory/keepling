import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises'
import { dirname } from 'node:path'

/**
 * Durable selection of the Keepling server this Mac talks to.
 *
 * Enforces the SAME origin constraint `KeeplingSyncAdapter` already applies
 * in its constructor -- https, or loopback for local development -- but
 * applies it at the point of SELECTION as well, so a disallowed origin can
 * never be persisted and then silently fail later, and a tampered
 * configuration file degrades to "no server configured" (the app stays
 * fully usable offline) rather than to a plaintext-http destination.
 */

const ALLOWED_LOOPBACK_HOSTS = new Set(['127.0.0.1', 'localhost', '[::1]', '::1'])

const assertAllowedServerUrl = (value: unknown): string => {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error('Keepling server address must be a non-empty URL')
  }
  let parsed: URL
  try {
    parsed = new URL(value.trim())
  } catch {
    throw new Error('Keepling server address must be a valid URL')
  }
  const isLoopback = ALLOWED_LOOPBACK_HOSTS.has(parsed.hostname)
  if (parsed.protocol !== 'https:' && !(parsed.protocol === 'http:' && isLoopback)) {
    throw new Error('Keepling server must use HTTPS (or a loopback address for local development)')
  }
  return parsed.toString()
}

type ServerConfigurationOptions = {
  filePath: string
  read?: (path: string) => Promise<string | null>
  remove?: (path: string) => Promise<void>
  write?: (path: string, contents: string) => Promise<void>
}

const defaultRead = async (path: string): Promise<string | null> => {
  try {
    return await readFile(path, 'utf8')
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') return null
    throw error
  }
}

const defaultRemove = async (path: string): Promise<void> => {
  await rm(path, { force: true })
}

const defaultWrite = async (path: string, contents: string): Promise<void> => {
  await mkdir(dirname(path), { mode: 0o700, recursive: true })
  const temporary = `${path}.new`
  await writeFile(temporary, contents, { mode: 0o600 })
  await rename(temporary, path)
}

class FileServerConfiguration {
  readonly #filePath: string
  readonly #read: NonNullable<ServerConfigurationOptions['read']>
  readonly #remove: NonNullable<ServerConfigurationOptions['remove']>
  readonly #write: NonNullable<ServerConfigurationOptions['write']>

  constructor(options: ServerConfigurationOptions) {
    this.#filePath = options.filePath
    this.#read = options.read ?? defaultRead
    this.#remove = options.remove ?? defaultRemove
    this.#write = options.write ?? defaultWrite
  }

  /** Returns the configured base URL, or `null` when absent, unreadable, malformed, or no longer allowed. */
  async load(): Promise<string | null> {
    let raw: string | null
    try {
      raw = await this.#read(this.#filePath)
    } catch {
      return null
    }
    if (raw === null) return null
    try {
      const parsed = JSON.parse(raw) as { baseUrl?: unknown }
      return assertAllowedServerUrl(parsed.baseUrl)
    } catch {
      return null
    }
  }

  /** Validates first, writes second: a rejected address never reaches disk and never replaces a good one. */
  async save(baseUrl: string): Promise<string> {
    const allowed = assertAllowedServerUrl(baseUrl)
    await this.#write(this.#filePath, JSON.stringify({ baseUrl: allowed }))
    return allowed
  }

  async clear(): Promise<void> {
    await this.#remove(this.#filePath)
  }
}

export { assertAllowedServerUrl, FileServerConfiguration }
export type { ServerConfigurationOptions }
