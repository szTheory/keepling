import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises'
import { createRequire } from 'node:module'
import { dirname } from 'node:path'

import type { CredentialPort } from '../application/DesktopApplication.ts'

const require = createRequire(import.meta.url)

type SafeStoragePort = Pick<
  Electron.SafeStorage,
  'decryptStringAsync' | 'encryptStringAsync' | 'isAsyncEncryptionAvailable'
>

type SafeStorageCredentialOptions = {
  filePath: string
  read?: (path: string) => Promise<Buffer | null>
  remove?: (path: string) => Promise<void>
  safeStorage?: SafeStoragePort
  write?: (path: string, encrypted: Buffer) => Promise<void>
}

const defaultRead = async (path: string): Promise<Buffer | null> => {
  try {
    return await readFile(path)
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') return null
    throw error
  }
}

const defaultRemove = async (path: string): Promise<void> => {
  await rm(path, { force: true })
}

const defaultWrite = async (path: string, encrypted: Buffer): Promise<void> => {
  await mkdir(dirname(path), { recursive: true, mode: 0o700 })
  const temporary = `${path}.new`
  await writeFile(temporary, encrypted, { mode: 0o600 })
  await rename(temporary, path)
}

class SafeStorageCredentialAdapter implements CredentialPort {
  readonly #filePath: string
  readonly #read: NonNullable<SafeStorageCredentialOptions['read']>
  readonly #remove: NonNullable<SafeStorageCredentialOptions['remove']>
  readonly #safeStorage: SafeStoragePort
  readonly #write: NonNullable<SafeStorageCredentialOptions['write']>

  constructor(options: SafeStorageCredentialOptions) {
    this.#filePath = options.filePath
    this.#read = options.read ?? defaultRead
    this.#remove = options.remove ?? defaultRemove
    this.#safeStorage = options.safeStorage ?? (require('electron') as typeof Electron.CrossProcessExports).safeStorage
    this.#write = options.write ?? defaultWrite
  }

  async load(): Promise<string | null> {
    const encrypted = await this.#read(this.#filePath)
    if (encrypted === null) return null
    if (!await this.#safeStorage.isAsyncEncryptionAvailable()) throw new Error('credential_protection_unavailable')
    return (await this.#safeStorage.decryptStringAsync(encrypted)).result
  }

  async store(value: string): Promise<void> {
    if (value.length === 0) throw new Error('credential value must not be empty')
    if (!await this.#safeStorage.isAsyncEncryptionAvailable()) throw new Error('credential_protection_unavailable')
    const encrypted = await this.#safeStorage.encryptStringAsync(value)
    await this.#write(this.#filePath, encrypted)
  }

  async clear(): Promise<void> {
    await this.#remove(this.#filePath)
  }

  settingsDisclosure(): { copy: string; kind: 'unsigned_dogfood' } {
    return {
      copy: 'This unsigned dogfood build may not keep sign-in through an app replacement. Your tasks and pending changes remain saved on this Mac.',
      kind: 'unsigned_dogfood',
    }
  }
}

export { SafeStorageCredentialAdapter }
export type { SafeStorageCredentialOptions, SafeStoragePort }
