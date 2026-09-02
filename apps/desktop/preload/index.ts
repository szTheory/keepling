import { contextBridge, ipcRenderer } from 'electron'
import { z } from 'zod'

import {
  captureRequestSchema,
  conflictSchema,
  decideSequenceOutcome,
  desktopPresentationSchema,
  editRequestSchema,
  lifecycleRequestSchema,
  localAcceptanceSchema,
  moveTodayRequestSchema,
  resolveConflictRequestSchema,
  snapshotSchema,
  undoResultSchema,
} from './contracts.ts'

type DesktopPresentation = z.infer<typeof desktopPresentationSchema>

// D-29 sequence contract: the presentation-push listener is registered here,
// at preload module load -- before any renderer script runs and before any
// caller ever calls `subscribePresentation` -- so there is no window in
// which a push can arrive unobserved. `lastSequence` is preload-private
// state; `subscribePresentation` below only ever adds/removes subscriber
// callbacks, it never re-registers this listener.
let lastPresentationSequence: number | null = null
const presentationSubscribers = new Set<(presentation: DesktopPresentation) => void>()

const deliverPresentation = (presentation: DesktopPresentation): void => {
  for (const subscriber of presentationSubscribers) subscriber(presentation)
}

/** Opaque recovery: fetches the authoritative current presentation from main and delivers it, discarding any assumption about what was missed. Used both for the initial baseline and for closing a detected sequence gap. */
const refetchAuthoritativePresentation = async (): Promise<void> => {
  let value: DesktopPresentation
  try {
    value = desktopPresentationSchema.parse(await ipcRenderer.invoke('keepling:presentation-snapshot'))
  } catch {
    return
  }
  lastPresentationSequence = value.sequence
  deliverPresentation(value)
}

ipcRenderer.on('keepling:presentation-changed', (_event, raw) => {
  let value: DesktopPresentation
  try {
    value = desktopPresentationSchema.parse(raw)
  } catch {
    // A malformed push (from a compromised/buggy main) is dropped, never
    // handed to the renderer and never crashes it.
    return
  }
  const outcome = decideSequenceOutcome(lastPresentationSequence, value.sequence)
  if (outcome === 'ignore_stale') return
  if (outcome === 'refetch') {
    void refetchAuthoritativePresentation()
    return
  }
  lastPresentationSequence = value.sequence
  deliverPresentation(value)
})

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
  subscribePresentation: (subscriber: (presentation: DesktopPresentation) => void) => {
    presentationSubscribers.add(subscriber)
    // Deliver an immediate baseline to the new subscriber (main-owned
    // authoritative truth) rather than leaving it to wait for the next
    // commit's push -- this is the "subscription precedes snapshot"
    // guarantee: by the time this resolves, the module-level listener
    // above has already been live since preload load, so nothing pushed
    // in between can be missed.
    void refetchAuthoritativePresentation()
    return () => {
      presentationSubscribers.delete(subscriber)
    }
  },
})

contextBridge.exposeInMainWorld('keepling', keepling)

declare global {
  interface Window {
    keepling: typeof keepling
  }
}
