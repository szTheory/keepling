import { contextBridge, ipcRenderer } from 'electron'
import { z } from 'zod'

import {
  accountConnectOutcomeSchema,
  accountConnectRequestSchema,
  accountStatusSchema,
} from './contracts.ts'

/**
 * Narrow preload bridge for the Quick Entry and Settings utility windows
 * (D-27/D-28). This is a SEPARATE file from `apps/desktop/preload/index.ts`
 * (owned by Plan 03-10 for this wave) so Plan 03-04 can ship a durable,
 * validated draft/shortcut surface without touching that file. It exposes
 * only named, clone-safe, runtime-validated operations -- no generic IPC,
 * no raw Electron objects, no filesystem/database access.
 */
const draftSchema = z.object({
  addToToday: z.boolean(),
  title: z.string().max(512),
}).strict()

const captureRequestSchema = z.object({
  addToToday: z.boolean().optional(),
  title: z.string().trim().min(1).max(512),
}).strict()

const taskSchema = z.object({
  completedAt: z.string().nullable().optional(),
  id: z.string().min(1),
  notes: z.string().optional(),
  planned: z.boolean().optional(),
  syncStatus: z.enum(['saved_on_this_mac', 'synced']),
  title: z.string().min(1),
  trashedAt: z.string().nullable().optional(),
}).strict()

const localAcceptanceSchema = z.object({
  fingerprint: z.string().regex(/^[a-f0-9]{64}$/),
  mutationId: z.string().min(1),
  snapshot: z.object({ tasks: z.array(taskSchema) }).strict(),
  status: z.literal('local_saved'),
}).strict()

const shortcutStatusSchema = z.object({
  accelerator: z.string().min(1),
  registered: z.boolean(),
}).strict()

const keeplingUtility = Object.freeze({
  capture: async (request: unknown) => localAcceptanceSchema.parse(
    await ipcRenderer.invoke('keepling:quick-entry:capture', captureRequestSchema.parse(request)),
  ),
  saveDraft: async (request: unknown) => {
    await ipcRenderer.invoke('keepling:quick-entry:save-draft', draftSchema.parse(request))
  },
  getDraft: async () => z.union([draftSchema, z.null()]).parse(
    await ipcRenderer.invoke('keepling:quick-entry:get-draft'),
  ),
  clearDraft: async () => {
    await ipcRenderer.invoke('keepling:quick-entry:clear-draft')
  },
  getShortcutStatus: async () => shortcutStatusSchema.parse(
    await ipcRenderer.invoke('keepling:quick-entry:get-shortcut-status'),
  ),
  setShortcut: async (accelerator: string) => shortcutStatusSchema.parse(
    await ipcRenderer.invoke('keepling:quick-entry:set-shortcut', z.string().min(1).parse(accelerator)),
  ),
  // O-16 gap closure: the Settings account surface. These schemas are the
  // SAME ones `preload/contracts.ts` defines and `main/index.ts` parses
  // again on the privileged side -- one contract, parsed twice.
  //
  // `accountConnect` takes a server address and NOTHING else: authentication
  // is delegated to the system browser (RFC 8252), so no Electron renderer
  // ever renders or transports a password, passkey, token, authorization
  // code, or PKCE verifier.
  accountConnect: async (request: unknown) => accountConnectOutcomeSchema.parse(
    await ipcRenderer.invoke('keepling:account:connect', accountConnectRequestSchema.parse(request)),
  ),
  accountDisconnect: async () => accountStatusSchema.parse(
    await ipcRenderer.invoke('keepling:account:disconnect'),
  ),
  accountStatus: async () => accountStatusSchema.parse(
    await ipcRenderer.invoke('keepling:account:status'),
  ),
  hide: () => ipcRenderer.send('keepling:quick-entry:hide'),
  requestDiscard: () => ipcRenderer.send('keepling:quick-entry:discard'),
  onFocusTitle: (subscriber: () => void) => {
    const listener = () => subscriber()
    ipcRenderer.on('keepling:quick-entry:focus-title', listener)
    return () => {
      ipcRenderer.removeListener('keepling:quick-entry:focus-title', listener)
    }
  },
  onShortcutStatus: (subscriber: (status: z.infer<typeof shortcutStatusSchema>) => void) => {
    const listener = (_event: Electron.IpcRendererEvent, value: unknown) => subscriber(shortcutStatusSchema.parse(value))
    ipcRenderer.on('keepling:quick-entry:shortcut-status', listener)
    return () => {
      ipcRenderer.removeListener('keepling:quick-entry:shortcut-status', listener)
    }
  },
})

contextBridge.exposeInMainWorld('keeplingUtility', keeplingUtility)

declare global {
  interface Window {
    keeplingUtility: typeof keeplingUtility
  }
}
