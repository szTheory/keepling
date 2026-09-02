import { contextBridge, ipcRenderer } from 'electron'
import { z } from 'zod'

import { desktopPresentationSchema } from './contracts.ts'

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
const snapshotSchema = z.object({ tasks: z.array(taskSchema) }).strict()
const localAcceptanceSchema = z.object({
  fingerprint: z.string().regex(/^[a-f0-9]{64}$/),
  mutationId: z.string().min(1),
  snapshot: snapshotSchema,
  status: z.literal('local_saved'),
}).strict()
const editRequestSchema = z.object({
  notes: z.string().max(50_000),
  taskId: z.string().min(1),
  title: z.string().trim().min(1).max(512),
}).strict()
const lifecycleRequestSchema = z.object({
  kind: z.enum(['complete', 'reopen', 'restore', 'trash']),
  taskId: z.string().min(1),
}).strict()
const moveTodayRequestSchema = z.object({
  planned: z.boolean(),
  taskId: z.string().min(1),
}).strict()
const conflictSchema = z.object({
  conflictId: z.string().min(1),
  current: z.string(),
  mine: z.string(),
  taskId: z.string().min(1),
}).strict()
const undoResultSchema = z.object({ applied: z.boolean(), snapshot: snapshotSchema }).strict()
const resolveConflictRequestSchema = z.object({
  choice: z.enum(['current', 'mine']),
  conflictId: z.string().min(1),
}).strict()

const keepling = Object.freeze({
  capture: async (request: unknown) => localAcceptanceSchema.parse(
    await ipcRenderer.invoke('keepling:capture', captureRequestSchema.parse(request)),
  ),
  snapshot: async () => snapshotSchema.parse(await ipcRenderer.invoke('keepling:snapshot')),
  presentationSnapshot: async () => desktopPresentationSchema.parse(
    await ipcRenderer.invoke('keepling:presentation-snapshot'),
  ),
  editTask: async (request: unknown) => snapshotSchema.parse(
    await ipcRenderer.invoke('keepling:edit-task', editRequestSchema.parse(request)),
  ),
  lifecycleTask: async (request: unknown) => snapshotSchema.parse(
    await ipcRenderer.invoke('keepling:lifecycle-task', lifecycleRequestSchema.parse(request)),
  ),
  moveToday: async (request: unknown) => snapshotSchema.parse(
    await ipcRenderer.invoke('keepling:move-today', moveTodayRequestSchema.parse(request)),
  ),
  undoLastAction: async () => undoResultSchema.parse(
    await ipcRenderer.invoke('keepling:undo-last-action'),
  ),
  listConflicts: async () => z.array(conflictSchema).parse(
    await ipcRenderer.invoke('keepling:list-conflicts'),
  ),
  resolveConflict: async (request: unknown) => snapshotSchema.parse(
    await ipcRenderer.invoke('keepling:resolve-conflict', resolveConflictRequestSchema.parse(request)),
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
