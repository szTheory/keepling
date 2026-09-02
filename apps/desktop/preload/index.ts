import { contextBridge, ipcRenderer } from 'electron'
import { z } from 'zod'

import { desktopPresentationSchema } from './contracts.ts'

const captureRequestSchema = z.object({ title: z.string().trim().min(1).max(512) }).strict()
const taskSchema = z.object({
  id: z.string().min(1),
  syncStatus: z.enum(['saved_on_this_mac', 'synced']),
  title: z.string().min(1),
}).strict()
const snapshotSchema = z.object({ tasks: z.array(taskSchema) }).strict()
const localAcceptanceSchema = z.object({
  fingerprint: z.string().regex(/^[a-f0-9]{64}$/),
  mutationId: z.string().min(1),
  snapshot: snapshotSchema,
  status: z.literal('local_saved'),
}).strict()

const keepling = Object.freeze({
  capture: async (request: unknown) => localAcceptanceSchema.parse(
    await ipcRenderer.invoke('keepling:capture', captureRequestSchema.parse(request)),
  ),
  snapshot: async () => snapshotSchema.parse(await ipcRenderer.invoke('keepling:snapshot')),
  presentationSnapshot: async () => desktopPresentationSchema.parse(
    await ipcRenderer.invoke('keepling:presentation-snapshot'),
  ),
  subscribePresentation: (subscriber: (presentation: z.infer<typeof desktopPresentationSchema>) => void) => {
    const listener = (_event: Electron.IpcRendererEvent, value: unknown) => subscriber(desktopPresentationSchema.parse(value))
    ipcRenderer.on('keepling:presentation-changed', listener)
    return () => ipcRenderer.removeListener('keepling:presentation-changed', listener)
  },
})

contextBridge.exposeInMainWorld('keepling', keepling)

declare global {
  interface Window {
    keepling: typeof keepling
  }
}
