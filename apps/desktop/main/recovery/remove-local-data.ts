/**
 * D-24 "Remove data from this Mac…" -- deliberately SEPARATE from sign out
 * (D-23, fences local intent then best-effort revokes) and from any server
 * deletion. This module never accepts, constructs, or has a code path that
 * could reach a server/sync port -- it is structurally impossible for this
 * function to send a server-deletion request, because no network or sync
 * capability is part of its input at all.
 *
 * Sequence (each step matches the plan's `<behavior>`/`<action>` exactly):
 *   1. Fence the namespace FIRST, before reading any counts, so no new
 *      Quick Entry / main-window write or sync push can race with removal
 *      (T-KPL03-05-03/MAC-05 concurrency).
 *   2. Snapshot bounded pending/conflicted counts under the fence.
 *   3. If local-only intent exists (pending mutations or open conflicts)
 *      AND the caller has not passed the second exact `confirmRemoveAnyway`
 *      confirmation, un-fence (so ordinary use -- and "Sync First" -- keeps
 *      working) and report the bounded counts back for that confirmation
 *      dialog. This is the ONLY way local-only intent can require a second
 *      confirmation: one-step removal is refused whenever there is
 *      anything not yet durably reflected on the server.
 *   4. Close the store BEFORE deleting its whole-unit file inventory
 *      (D-38: never unlink/copy a live database).
 *   5. Delete the explicit, bounded, namespace-scoped file inventory the
 *      store itself reports (never a directory wildcard/glob, so a sibling
 *      namespace can never be touched).
 *   6. Remove credentials AFTER the database files (D-24 explicit order).
 *   7. Verify every target is actually absent before reporting success --
 *      a partial external filesystem failure is reported as `failed` with
 *      the still-present paths so the caller can retry, never silently
 *      claimed as removed.
 *
 * This function makes NO cryptographic-erasure claim (D-25): "removed"
 * means the files were deleted and verified absent from the filesystem,
 * not that the underlying storage medium was wiped.
 */

type LocalDataStorePort = {
  close(): Promise<void> | void
  listConflicts?(): Promise<unknown[]> | unknown[]
  pendingMutations(): Promise<unknown[]> | unknown[]
  removeLocalFiles?(): Promise<{ remaining: string[]; removed: string[] }> | { remaining: string[]; removed: string[] }
  setSyncFence?(reason: string | null): Promise<void> | void
}

type LocalDataCredentialPort = {
  clear(): Promise<void> | void
}

type RemoveLocalDataInput = {
  /** The second, exact "Remove Local Changes Anyway" confirmation (D-24). */
  confirmRemoveAnyway: boolean
  credentials?: LocalDataCredentialPort
  localStore: LocalDataStorePort
}

type RemoveLocalDataOutcome =
  | { conflictedCount: number; kind: 'blocked_pending_intent'; pendingCount: number }
  | { kind: 'failed'; reason: string }
  | { kind: 'removed' }

const errorMessage = (error: unknown): string => (error instanceof Error ? error.message : String(error))

const removeLocalNamespaceData = async (input: RemoveLocalDataInput): Promise<RemoveLocalDataOutcome> => {
  // 1. Fence FIRST -- this is what makes a concurrent sync pass
  // (`readyMutations()` already checks this same fence) and a concurrent
  // Quick Entry/main-window write (guarded by the store's own
  // `#assertNotFenced()`) both lose the race against removal, rather than
  // removal losing the race against them.
  await input.localStore.setSyncFence?.('local_removal')

  // 2. Snapshot bounded counts under the fence.
  let pendingCount: number
  let conflictedCount: number
  try {
    const pending = await input.localStore.pendingMutations()
    const conflicts = input.localStore.listConflicts ? await input.localStore.listConflicts() : []
    pendingCount = pending.length
    conflictedCount = conflicts.length
  } catch (error) {
    await input.localStore.setSyncFence?.(null)
    return { kind: 'failed', reason: `could not read pending/conflicted counts: ${errorMessage(error)}` }
  }

  // 3. Local-only intent requires the second exact confirmation. Refuse
  // and un-fence otherwise -- "Sync First" and ordinary use must keep
  // working exactly as before this call was made.
  if ((pendingCount > 0 || conflictedCount > 0) && !input.confirmRemoveAnyway) {
    await input.localStore.setSyncFence?.(null)
    return { conflictedCount, kind: 'blocked_pending_intent', pendingCount }
  }

  // 4. Close BEFORE deleting the whole-unit file inventory (D-38).
  try {
    await input.localStore.close()
  } catch (error) {
    return { kind: 'failed', reason: `could not close the local store: ${errorMessage(error)}` }
  }

  // 5. Delete the explicit, bounded, namespace-scoped file inventory.
  if (!input.localStore.removeLocalFiles) {
    return { kind: 'failed', reason: 'local file removal is unavailable' }
  }
  let remaining: string[]
  try {
    remaining = (await input.localStore.removeLocalFiles()).remaining
  } catch (error) {
    return { kind: 'failed', reason: `local file removal failed: ${errorMessage(error)}` }
  }

  // 6. Credentials AFTER database files.
  try {
    await input.credentials?.clear()
  } catch (error) {
    return { kind: 'failed', reason: `credential removal failed: ${errorMessage(error)}` }
  }

  // 7. Verify absence -- never claim success on a partial failure.
  if (remaining.length > 0) {
    return { kind: 'failed', reason: `still present after removal: ${remaining.join(', ')}` }
  }
  return { kind: 'removed' }
}

export { removeLocalNamespaceData }
export type { LocalDataCredentialPort, LocalDataStorePort, RemoveLocalDataInput, RemoveLocalDataOutcome }
