---
phase: KPL-03-mac-daily-loop
reviewed: 2026-09-04T00:00:00Z
depth: standard
files_reviewed: 141
files_reviewed_list:
  - .github/workflows/desktop.yml
  - .gitignore
  - .npmrc
  - apps/desktop/forge.config.ts
  - apps/desktop/main/adapters/auth.ts
  - apps/desktop/main/adapters/credentials.ts
  - apps/desktop/main/adapters/server-config.ts
  - apps/desktop/main/adapters/server-refusal.ts
  - apps/desktop/main/adapters/sync.ts
  - apps/desktop/main/application/DesktopApplication.ts
  - apps/desktop/main/application/outbound-commands.ts
  - apps/desktop/main/application/presentation.ts
  - apps/desktop/main/application/sync-reachability.ts
  - apps/desktop/main/index.ts
  - apps/desktop/main/lifecycle.ts
  - apps/desktop/main/menu.ts
  - apps/desktop/main/menuLabels.ts
  - apps/desktop/main/protocol.ts
  - apps/desktop/main/recovery/remove-local-data.ts
  - apps/desktop/main/windows/foreground-app.ts
  - apps/desktop/main/windows/headless-presentation.ts
  - apps/desktop/main/windows/main-window.ts
  - apps/desktop/main/windows/mainWindowState.ts
  - apps/desktop/main/windows/quick-entry-window.ts
  - apps/desktop/main/windows/settings-window.ts
  - apps/desktop/migrations/0001_initial.sql
  - apps/desktop/migrations/0002_outbox_state.sql
  - apps/desktop/package.json
  - apps/desktop/performance-budgets.json
  - apps/desktop/playwright.config.ts
  - apps/desktop/preload/contracts.ts
  - apps/desktop/preload/index.ts
  - apps/desktop/preload/utility-preload.ts
  - apps/desktop/renderer/DesktopShell.tsx
  - apps/desktop/renderer/SyncStatusRow.tsx
  - apps/desktop/renderer/UtilitySyncStatusRow.tsx
  - apps/desktop/renderer/desktop.css
  - apps/desktop/renderer/desktopClientFacade.ts
  - apps/desktop/renderer/index.html
  - apps/desktop/renderer/keyboardCommands.ts
  - apps/desktop/renderer/main.tsx
  - apps/desktop/renderer/quick-entry.tsx
  - apps/desktop/renderer/settings.tsx
  - apps/desktop/store-worker/index.ts
  - apps/desktop/store-worker/local-store.ts
  - apps/desktop/test/application/browser-delegated-auth.test.ts
  - apps/desktop/test/application/client-facade-boundary.test.ts
  - apps/desktop/test/application/conflict-presentation.test.ts
  - apps/desktop/test/application/foreground-app.test.ts
  - apps/desktop/test/application/lifecycle.test.ts
  - apps/desktop/test/application/mainWindowState.test.ts
  - apps/desktop/test/application/menuLabels.test.ts
  - apps/desktop/test/application/offline-capture.test.ts
  - apps/desktop/test/application/outbound-commands.test.ts
  - apps/desktop/test/application/quick-entry-draft.test.ts
  - apps/desktop/test/application/recovery-presentation.test.ts
  - apps/desktop/test/application/server-refusal.test.ts
  - apps/desktop/test/application/state-matrix.test.tsx
  - apps/desktop/test/application/sync-presentation.test.ts
  - apps/desktop/test/application/sync-vectors.test.ts
  - apps/desktop/test/application/undo-reconciliation.test.ts
  - apps/desktop/test/e2e/accessibility.spec.ts
  - apps/desktop/test/e2e/daily-loop.spec.ts
  - apps/desktop/test/e2e/fixture-server-sync.spec.ts
  - apps/desktop/test/e2e/gap-closure.spec.ts
  - apps/desktop/test/e2e/keyboard-menus.spec.ts
  - apps/desktop/test/e2e/keyboard-quick-entry.spec.ts
  - apps/desktop/test/e2e/lifecycle.spec.ts
  - apps/desktop/test/e2e/sync-recovery.spec.ts
  - apps/desktop/test/fixtures/desktopClientFacade.ts
  - apps/desktop/test/fixtures/wired-app-harness.ts
  - apps/desktop/test/ipc/hostile-bridge.test.ts
  - apps/desktop/test/packaged/daily-loop.spec.ts
  - apps/desktop/test/packaged/offline-capture.spec.ts
  - apps/desktop/test/packaged/security.spec.ts
  - apps/desktop/test/performance/runtime.spec.ts
  - apps/desktop/test/real-stack/real-stack-sync.spec.ts
  - apps/desktop/test/renderer/keyboardCommands.test.ts
  - apps/desktop/test/renderer/sync-status-row.test.tsx
  - apps/desktop/test/renderer/workspace-tracer.test.tsx
  - apps/desktop/test/store/migrations-faults.test.ts
  - apps/desktop/test/store/offline-capture.test.ts
  - apps/desktop/test/store/outbound-mutations.test.ts
  - apps/desktop/test/store/outbox-state-migration.test.ts
  - apps/desktop/test/store/outbox-transmission.test.ts
  - apps/desktop/test/store/quick-entry-draft.test.ts
  - apps/desktop/test/store/undo-handles.test.ts
  - apps/desktop/tsconfig.json
  - apps/desktop/vite.harness.config.ts
  - apps/desktop/vite.main.config.ts
  - apps/desktop/vite.preload.config.ts
  - apps/desktop/vite.renderer.config.ts
  - apps/desktop/vite.utility-preload.config.ts
  - apps/desktop/vite.worker.config.ts
  - apps/desktop/vitest.config.ts
  - apps/server/config/runtime.exs
  - apps/server/lib/keepling/accounts/device_grant.ex
  - apps/server/lib/keepling/application.ex
  - apps/server/lib/keepling_web/auth.ex
  - apps/server/lib/keepling_web/command_discriminator.ex
  - apps/server/lib/keepling_web/controllers/command_controller.ex
  - apps/server/lib/keepling_web/controllers/device_grant_controller.ex
  - apps/server/lib/keepling_web/router.ex
  - apps/server/test/keepling_web/device_grant_command_test.exs
  - apps/server/test/keepling_web/device_grant_controller_test.exs
  - apps/web/e2e/support/backend.ts
  - apps/web/e2e/support/stack.ts
  - apps/web/src/adapters/browserClientFacade.test.tsx
  - apps/web/src/adapters/browserClientFacade.ts
  - apps/web/src/app/AppShell.tsx
  - apps/web/src/app/WorkspaceShell.test.tsx
  - apps/web/src/app/WorkspaceShell.tsx
  - docs/testing/desktop-dogfood.md
  - docs/testing/desktop-performance.md
  - docs/testing/desktop-testing.md
  - infra/compose/compose.yml
  - package.json
  - packages/contracts/openapi/keepling.yaml
  - packages/web-ui/package.json
  - packages/web-ui/src/ClientFacade.ts
  - packages/web-ui/src/capture/CaptureForm.tsx
  - packages/web-ui/src/recovery/SyncRecovery.tsx
  - packages/web-ui/src/tasks/ConflictResolver.tsx
  - packages/web-ui/src/tasks/TaskEditor.tsx
  - packages/web-ui/src/tasks/TaskList.tsx
  - packages/web-ui/src/workspace/Workspace.tsx
  - tooling/check-contracts.mjs
  - tooling/macos-integration/AXProbe.swift
  - tooling/macos-integration/HotkeyRival.swift
  - tooling/macos-integration/SystemSettings.swift
  - tooling/macos-integration/TccProbe.swift
  - tooling/measure-desktop-performance.mjs
  - tooling/package-desktop.mjs
  - tooling/run-local-stack.sh
  - tooling/run-tests.mjs
  - tooling/select-tests.mjs
  - tooling/smoke-desktop-packaged.mjs
  - tooling/test-changed.mjs
  - tooling/verify-desktop-harness.mjs
  - tooling/verify-desktop-phase.mjs
  - tooling/verify-macos-integration.mjs
  - tooling/verify-real-stack-desktop.mjs
excluded:
  - pnpm-lock.yaml (lockfile)
  - packages/contracts/generated/keepling.ts (generated code)
findings:
  critical: 0
  warning: 3
  info: 1
  total: 4
status: issues-found
---

# Phase KPL-03: Code Review Report

**Reviewed:** 2026-09-04
**Depth:** standard
**Files Reviewed:** 141 (2 excluded: lockfile, generated contract)
**Status:** issues_found

## Summary

This phase wires the Electron main/preload/renderer boundary, the SafeStorage
credential adapter, the browser-delegated OAuth/PKCE flow, the Phoenix
device-grant auth path, and the offline-first sync/outbox state machine end to
end for the first time. The code is unusually well hardened for a first
integration pass: every `ipcMain.handle` call is gated behind an exact
`WebContents`-id + main-frame + origin-URL sender check, every preload/main
schema is `.strict()` on both sides of the IPC boundary, the packaged
`app://renderer/` protocol handler resolves paths through a path-traversal
guard before any filesystem read, CSP is applied at the session level with no
`unsafe-inline` script source, `contextIsolation`/`sandbox`/`nodeIntegration`
are correctly set on every `BrowserWindow`, the OAuth flow uses PKCE S256 with
exact state matching and treats every browser callback as untrusted input, and
the Phoenix device-grant path uses hashed tokens, `secure_compare`, per-grant
generation bumping on revoke, and refresh-token replay detection with family
revocation. I did not find any injection, auth-bypass, or credential-handling
vulnerability that would block shipping.

The findings below are real but narrow: an unaddressed SafeStorage key
re-encryption signal, a title-based (rather than id-based) task lookup after
capture that can target the wrong task when two tasks share a title, and a
weaker sender-trust check on the Quick Entry/Settings utility IPC surface than
the equivalent check on the main window's surface.

## Warnings

### WR-01: `shouldReEncrypt` from `safeStorage.decryptStringAsync` is silently discarded

**File:** `apps/desktop/main/adapters/credentials.ts:74-79`
**Issue:** Electron's `safeStorage.decryptStringAsync` returns
`{ result, shouldReEncrypt }`. `shouldReEncrypt: true` means the OS has
rotated the encryption key (or otherwise wants the ciphertext refreshed) and
the caller is expected to re-encrypt and persist the value on this read. The
adapter reads only `.result` and never inspects or acts on `shouldReEncrypt`:
```ts
async load(): Promise<string | null> {
  const encrypted = await this.#read(this.#filePath)
  if (encrypted === null) return null
  if (!await this.#safeStorage.isAsyncEncryptionAvailable()) throw new Error('credential_protection_unavailable')
  return (await this.#safeStorage.decryptStringAsync(encrypted)).result
}
```
Concretely: after a macOS Keychain/OS-level key rotation, the stored
`credential.enc` file keeps being decrypted with the old key material
indefinitely (a decrypt success today is not evidence this keeps working after
the *next* rotation), and the app never migrates to the rotated key as
Electron's own API contract expects. This is a slow-burn robustness/security
hygiene gap, not an exploitable vulnerability today.
**Fix:**
```ts
async load(): Promise<string | null> {
  const encrypted = await this.#read(this.#filePath)
  if (encrypted === null) return null
  if (!await this.#safeStorage.isAsyncEncryptionAvailable()) throw new Error('credential_protection_unavailable')
  const { result, shouldReEncrypt } = await this.#safeStorage.decryptStringAsync(encrypted)
  if (shouldReEncrypt) await this.store(result).catch(() => {})
  return result
}
```

### WR-02: Post-capture "add to Today" targets a task by title match, not by identity

**File:** `apps/desktop/renderer/desktopClientFacade.ts:133-151`, `apps/desktop/main/windows/quick-entry-window.ts:112-123`
**Issue:** `window.keepling.capture()` (the preload `localAcceptanceSchema`,
`apps/desktop/preload/contracts.ts:63-68`) returns `mutationId`/`fingerprint`/
`snapshot`/`status` but never the id of the task that was just created. Both
capture call sites that need to immediately act on the new task (main-window
"Add to Today" checkbox, and Quick Entry's `addToToday`) recover the id by
searching the returned snapshot for a task whose *title* matches the
just-submitted title:
```ts
// desktopClientFacade.ts
let task = tasks.find((candidate) => candidate.title === input.title.trim()) ?? tasks[0]!
```
```ts
// quick-entry-window.ts
const taskId = acceptance.snapshot.tasks.find((task) => task.title === trimmed)?.id
```
`tasks`/`snapshot.tasks` is the full workspace (`SELECT ... FROM
visible_projection ORDER BY rowid`, `local-store.ts:773-789`), so if any
earlier task shares the exact trimmed title with the one just captured (a
common case for short recurring titles like "Follow up" or "Call back"),
`.find()` returns the *first* (oldest) match rather than the new task. In
`desktopClientFacade.ts` this is compounded by the `?? tasks[0]!` fallback: if
for any reason no title match is found, the code falls back to the very first
task in the entire list and applies "Add to Today" to a completely unrelated,
arbitrary task with no error surfaced to the user.
**Fix:** Have `capture()` return the created task's id (e.g. add `taskId` to
`LocalAcceptance`/`localAcceptanceSchema`, populated from the already-known
`mutation.taskId` in `DesktopApplication.capture`/`acceptCapture`), and use
that id directly instead of a title search on both call sites. At minimum,
drop the `?? tasks[0]!` fallback in `desktopClientFacade.ts` so an unmatched
capture never silently mutates an unrelated task.

### WR-03: Quick Entry/Settings utility IPC sender check omits the main-frame/origin checks the main window's equivalent check enforces

**File:** `apps/desktop/main/windows/quick-entry-window.ts:84-89`
**Issue:** Every `ipcMain.handle`/`ipcMain.on` channel registered by
`QuickEntryWindowController` is guarded by:
```ts
#assertTrustedSender(sender: Electron.WebContents): void {
  const isOwnWindow = this.#window !== null && sender === this.#window.webContents
  if (!isOwnWindow && !this.#trustedSenders.has(sender)) {
    throw new Error('untrusted Quick Entry sender')
  }
}
```
This only checks `WebContents` identity. It does not check the
`event.senderFrame`/`isMainFrame`/frame-URL conditions that `main/protocol.ts`
`isTrustedIpcSender` (used by every channel in `main/index.ts`, including the
`keepling:utility:*` account channels registered directly in `main/index.ts`)
applies — i.e. a subframe of the Quick Entry or Settings `WebContents` would
pass this check, whereas the equivalent channel on the main window's
`WebContents` or the account channels would reject it. Given the strict
`will-navigate`/`setWindowOpenHandler` deny-all policy and the fact that these
windows only ever load the packaged `app://renderer/...?view=quick-entry`
content with no third-party iframes, this is not currently exploitable, but it
is an inconsistency in the security boundary that later code (which might add
an iframe, or a webview, to one of these two windows) could silently rely on
without realizing the frame check is missing here.
**Fix:** Reuse `isTrustedIpcSender`/`assertTrustedIpcSender` from
`main/protocol.ts` (passing `event.senderFrame`/`event.sender.mainFrame`) in
`QuickEntryWindowController#assertTrustedSender` instead of a bespoke
`WebContents`-identity-only check, so every IPC surface in the app enforces
the same trust policy.

## Info

### IN-01: `reconcile()` catches and discards the store-open error without using it

**File:** `apps/desktop/main/application/DesktopApplication.ts:685-691`
**Issue:**
```ts
try {
  pending = await this.#localStore.pendingMutations()
} catch (error) {
  this.publishPresentation({ kind: 'store_unavailable' })
  return { settled: 0 }
}
```
`error` is bound but never read; the underlying failure reason (e.g. the
`StoreFailureCode` classification `local-store.ts` already computes) is
dropped rather than logged or attached to the published presentation, making
this specific failure harder to diagnose from a bug report than it needs to
be. Not a correctness bug (the closed `store_unavailable` recovery state is
still published correctly).
**Fix:** Log `error` (or thread a `classifyStoreFailure(error)`-derived code
into a diagnostic event) before returning, for operability rather than
correctness.

---

_Reviewed: 2026-09-04_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
