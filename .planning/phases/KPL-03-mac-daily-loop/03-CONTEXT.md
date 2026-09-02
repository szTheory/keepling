# Phase 3: Mac Daily Loop - Context

**Gathered:** 2026-09-02
**Status:** Ready for UI specification, research, and planning

<domain>
## Phase Boundary

Deliver Keepling for Mac as an installed, always-available Electron client for the supported personal GTD loop: quick capture, Inbox, Today, edit, complete/reopen, Trash/restore, and undo with complete keyboard operation. The client must remain useful without connectivity, commit its local projection and immutable outbox atomically before reporting success, survive renderer failure and full process relaunch, reconcile exact acknowledgements without duplication or silent overwrite, and present conflicts, authentication expiry, and unrecoverable states in calm human language.

Phase 3 owns the Mac window, menus, shortcuts, lifecycle, local persistence adapter, synchronization orchestration, credential adapter seam, narrow preload boundary, shared React presentation extraction, packaged artifact, and Mac-specific proof. Phoenix/PostgreSQL remains canonical and owns authorization, invariants, mutation idempotency, revisions, and the ordered synchronization feed. This phase does not make the renderer, Electron lifecycle, background execution, or network availability part of correctness.

</domain>

<decisions>
## Implementation Decisions

### Product model and domain language

- **D-01:** Use a quiet local-first Mac experience. The primary job is to capture or act on a commitment immediately, continue through network loss or server outage, and later understand whether the server accepted it and what—if anything—needs attention.
- **D-02:** Keep the user-facing domain vocabulary to `workspace`, `destination`, `task list`, `task`, `selection`, `detail`, `draft`, `saved on this Mac`, `pending change`, `server acceptance`, `conflict`, `last successful contact`, and `recovery action`. Do not expose IPC, SQLite rows, outbox entries, cursors, fingerprints, bootstrap internals, or transport retries.
- **D-03:** Distinguish three trust thresholds: a recoverable `draft` is not yet a task change; `Saved on this Mac` is earned only after the local projection and immutable outbox commit atomically; `Synced` is earned only after an exact matching server acknowledgement. — **Reversibility:** one-way — these meanings become a cross-surface trust contract and changing them later could make previously accepted states misleading.

### Window and workspace behavior

- **D-04:** Ship one primary resizable/restorable main window. Use the proven navigation → task list → detail composition when space permits, collapse the sidebar before squeezing the list/detail minimums, and use the existing routed one-surface behavior for genuinely narrow windows. Do not ship general multi-window task/list workflows in Phase 3.
- **D-05:** Keep one canonical task route and one selected task in the main window. List focus is independent from selection; list and detail scroll independently; selection, row removal, Back, and window recreation restore focus by stable task identity rather than DOM position.
- **D-06:** Restore validated on-screen bounds, fullscreen state, sidebar visibility, pane sizes, destination, surviving selected task, semantic scroll anchor, and a recoverable editor draft. Never restore transient dialogs, progress indicators, authentication prompts, or stale raw focus targets.
- **D-07:** Use the native titlebar/traffic lights and conventional App, File, Edit, View, Window, and Help menus. The window title may name Keepling and a coarse destination but never task content. Avoid frameless/custom titlebars, hover-only chrome, and private task text in Window menus or the app switcher.
- **D-08:** Follow system light/dark appearance by default and apply changes while running. Preserve semantic tokens, system typography, non-color state cues, forced/increased-contrast behavior, and Reduce Motion. Concentrate brand in the icon, selection, empty-state tone, and a few meaningful moments rather than repainting native chrome.

### Capture and keyboard workflow

- **D-09:** Implement one semantic capture command with two presentations: `Command-N` opens focused in-app capture, and a separately configurable global shortcut opens a small Quick Entry utility window while Keepling is running. Both call the same main-owned application operation and default visibly to Inbox with optional Today placement. — **Reversibility:** costly — menu commands, accessibility help, tests, and user muscle memory will bind to this capture model.
- **D-10:** Default the global Quick Entry shortcut to `Control-Option-Space`, but make it user-configurable and surface registration failure with a direct rebind action. Never silently lose the shortcut to a collision or assume one keyboard layout.
- **D-11:** Quick Entry opens title-first, returns focus to the prior app after successful local commit, and uses `Command-Return` to commit. Escape or `Command-W` hides a nonempty Quick Entry while preserving its durable draft; only an explicit `Discard Draft` action removes it, with confirmation when nonempty.
- **D-12:** Preserve standard text editing and macOS accelerators. `Command-Z` remains text undo whenever an editable control owns focus; semantic undo is a named visible action and menu command outside text editing. `Command-S` and `Command-Return` save an editor; a dirty Escape/navigation/close uses `Save changes`, `Discard changes`, and safe-default `Keep editing` rather than save-on-blur.
- **D-13:** Use Up/Down to move one stable list focus, Return to open the focused task, Escape to return from detail to the originating list context, and Tab for ordinary control traversal. After removal, focus the next row, then previous row, then list heading. Do not add bare J/K, Vim-style layers, or hidden hover-only commands.
- **D-14:** Place frequent semantic commands in native menus with their shortcuts: New Task, Quick Entry, Inbox, Today, Save, Complete/Reopen, Move to Trash, Restore, Undo last supported action, sidebar toggle, Sync & Recovery, and Settings. Destructive shortcuts operate only outside editable controls, ignore key repeat, do not fire during IME composition, and require ordinary confirmation policy.

### Offline and synchronization trust experience

- **D-15:** Use a hierarchical hybrid: healthy synchronization is quiet; a global summary is available on deliberate inspection; transient work appears only after a short grace period; actionable exceptions appear beside the affected task and in a bounded `Sync & Recovery` panel. Never badge every healthy task or claim “Everything synced” from one successful lane.
- **D-16:** Derive every renderer-visible synchronization summary from one authoritative main-owned presentation projection. Expose closed states, bounded counts, coarse times, and recovery actions through semantic IPC. Do not let the shell, rows, and recovery panel independently infer synchronization truth.
- **D-17:** Use these human-facing meanings:
  - opening local state: `Opening your tasks…`;
  - first local preparation: `Preparing your tasks for offline use…` without a false empty state;
  - ordinary catch-up: quiet, then `Updating…` if it outlives the grace period;
  - offline last-good: `Offline — showing tasks saved on this Mac`;
  - retryable server failure: `Couldn’t reach the server. Your changes stay on this Mac.` with `Retry`;
  - local acceptance: `Saved on this Mac`, adding `Sync when you’re back online` only when useful;
  - uncertain result: `Checking whether this change was accepted…`;
  - rejection: `The server didn’t accept this change. Your version is still on this Mac.` with `Review`;
  - conflict: `This task changed somewhere else. Choose what to keep.` while stating that other tasks can continue;
  - authentication fence: `Sign in to continue syncing. Changes remain safe on this Mac.` with a bounded count;
  - namespace mismatch: `These changes belong to a different account or server and won’t be sent here.` with `Inspect`, `Export`, and separately confirmed removal.
- **D-18:** Background synchronization is automatic, bounded, and battery-aware. Connectivity, foreground, wake, and unlock are retry hints—not proof of reachability. Pull at least one bounded page after reconnect/resume, then interleave pulls with ready-lane pushes using capped exponential backoff and jitter. No correctness step depends on a timer, socket, online flag, wake event, or graceful shutdown.
- **D-19:** Ship no OS notifications for routine save, ready, retry, reconnect, prolonged outage, or synchronization in Phase 3. Reminders and user-configurable high-value notifications belong to later scope; status remains in-product and privacy-safe.

### Lifecycle, drafts, and local protection

- **D-20:** Run as one resident single-instance Mac application. A second launch activates the existing instance. Closing the main window resolves dirty work, destroys or hides the renderer window, and leaves the main-owned local store, bounded sync owner, and global Quick Entry available; Dock activation recreates the window. `Command-H` uses native hide.
- **D-21:** `Command-Q` persists window/draft state, stops starting new network work, performs bounded cancellation/checkpoint/connection close, and exits without waiting for server acknowledgement. Every reported-success mutation is already durable, so shutdown is never a commit protocol.
- **D-22:** Startup opens the selected namespace-scoped local store, runs forward-only validated migrations, checks required invariants, reconstructs only from durable state, and exposes the local projection before network reconciliation finishes. Migration, integrity, permission, read-only, or disk-full failure opens a narrow recovery shell and never silently creates a fresh store or deletes the old one.
- **D-23:** Preserve Phase 2 account fencing exactly: issuer, origin, stable server instance, account subject, and synchronization generation select separate namespaces. Logout fences before revocation and retains local intent truthfully. A different account or server never drains, merges, or rewrites the prior namespace.
- **D-24:** `Remove data from this Mac…` is separate from sign out and server deletion. State that it removes local tasks, drafts, and sign-in from this Mac but does not delete server data; show bounded pending/conflicted counts; default to Cancel/Keep data; offer Sync first where possible; require a second explicit `Remove anyway…` when local-only intent exists; close the store before removing credentials, database, WAL/SHM, temp files, caches, indexes, and namespace metadata; verify absence; do not claim cryptographic erasure.
- **D-25:** Put credential handling behind an asynchronous replaceable port and exercise Electron `safeStorage` in the packaged client, but make unsigned dogfood limitations explicit. Phase 3 may claim least-privilege permissions plus FileVault/macOS account protection for plaintext task/outbox data; it may not claim update-stable Keychain identity, cryptographic erasure, launch-at-login, automatic updates, or public distribution security before signed/notarized evidence.

### Desktop process and package architecture

- **D-26:** Use a main-owned local-first `DesktopApplication` as the only client-side authority. The dependency flow is `React presentation → ClientFacade → validated preload bridge → DesktopApplication → LocalStorePort / SyncPort / CredentialPort`. The renderer is a disposable view mirror, never the owner of accepted intent, credentials, migrations, or synchronization. — **Reversibility:** costly — relaxing this boundary would move durable authority across privilege/process boundaries and invalidate packaged recovery and security evidence.
- **D-27:** Expose named asynchronous consumer operations such as workspace snapshot, capture, edit, complete, reopen, trash, restore, undo, resolve conflict, sign in/out, switch namespace, inspect recovery, and remove local data. Do not expose generic IPC, channel names, SQL, filesystem paths, Electron event objects, database handles, arbitrary fetch, raw credentials, or unrestricted platform APIs.
- **D-28:** Runtime-validate clone-safe requests and responses on both sides of preload, reject unknown operations and fields, validate IPC senders, enable context isolation and sandboxing, load only packaged local renderer content under a restrictive CSP/navigation/permission policy, and deny unexpected window creation or navigation.
- **D-29:** Subscribe before fetching the initial renderer snapshot. Tag semantic updates with a monotonic local presentation sequence; a sequence gap triggers an opaque snapshot refetch. Renderer reload loses transient focus at worst, never a committed mutation.
- **D-30:** Keep four deliberate representations with explicit mappers: generated OpenAPI wire DTOs, storage-neutral client/sync models, SQLite records, and renderer view models. Do not reuse Ecto schemas, server migrations, generated transport DTOs, or SQLite rows as another layer’s domain model.
- **D-31:** Keep Phoenix controllers thin over existing application commands and synchronization contexts. The desktop implements the released client state machine against shared contracts/vectors; it must not clone Elixir domain invariants or infer canonical acceptance locally.
- **D-32:** Prefer ordinary pnpm workspaces and a small replaceable package layout: `apps/desktop/main` for composition/lifecycle/windows, `apps/desktop/preload` for the bridge, `apps/desktop/renderer` for bootstrap, and a supervised store worker owned by the desktop application. Extract `packages/web-ui`, `packages/client-core-ts`, and `packages/api-client-ts` only at demonstrated seams; do not add a universal framework, Nx, Turborepo, an ORM, or shared persistence models.

### SQLite and migration strategy

- **D-33:** Define a narrow `LocalStorePort` first. Prefer the pinned Electron runtime’s `node:sqlite` inside one dedicated Node worker only if an exact packaged spike passes API stability, correctness, crash recovery, performance, and architecture gates. Predeclare `better-sqlite3` behind the same port as the fallback when `node:sqlite` fails a required gate. Reject SQLite WASM/OPFS for this main-owned native desktop store. — **Reversibility:** costly — changing the adapter later is feasible behind the port but still requires migration, packaging, crash, and artifact evidence across every retained fixture.
- **D-34:** Never run meaningful synchronous database work on Electron’s main/UI event loop. Serialize writes through one worker-owned connection. Use a utility process only if measured isolation or failure containment justifies its extra protocol/version surface.
- **D-35:** Use separate strict tables for namespace metadata, canonical shadow, visible projection, immutable command bytes/fingerprint, mutation journal, dependency edges, outbox, cursor, and conflicts. Enable and assert foreign keys; use prepared statements and bounded values; avoid a client ORM that obscures SQL invariants.
- **D-36:** Local mutation acceptance uses one `BEGIN IMMEDIATE` transaction to update the visible projection and insert the immutable command, journal, dependencies, and outbox; emit `local_saved` only after commit. Terminal acknowledgement atomically verifies mutation identity and fingerprint, applies canonical/conflict state, terminalizes the journal, recomputes projection, and removes the exact outbox row.
- **D-37:** Store ordered immutable SQL migrations with a `schema_migrations(version, checksum, applied_at)` ledger. Apply each migration transactionally, reject checksum drift, and retain deterministic fresh-create plus forward-migration fixtures for every supported packaged schema lineage. Never auto-reset on migration or integrity failure.
- **D-38:** Use WAL with one writer, finite busy handling, `synchronous=FULL`, default/observed checkpoint behavior until measurement earns tuning, and treat the database, `-wal`, and `-shm` as one durable unit. Never copy or unlink a live database; use the SQLite backup API or close the connection before whole-unit movement/removal.

### Design, accessibility, and microcopy

- **D-39:** Apply the design pillars together: usefulness/JTBD, correctness and earned trust, calm attention, native Mac fit, accessibility, information hierarchy, visual craft, performance, privacy/security, resilience, reversibility, and developer/test ergonomics. A visually calm state may not hide an actionable correctness problem.
- **D-40:** Inherit Phase 1 semantic colors, typography intent, spacing rhythm, plain-text rendering, focus safety, conflict/recovery components, and copy voice. Create Mac-specific density/layout aliases only through the Phase 3 UI contract; native feel outranks pixel parity, but shared component meaning and state semantics may not drift.
- **D-41:** Routine success stays silent or brief. Recovery copy names what is durable, where it is, what did not happen, and the next safe action. Avoid celebrations, backend terms, vague `Something went wrong`, probabilistic `probably synced`, perpetual spinners, generic red banners, and admin-dashboard event logs.
- **D-42:** Accessibility is release evidence: logical navigation/list/detail groups; semantic lists/forms/headings; visible keyboard focus distinct from selection; one debounced polite live region per window for meaningful transitions; no per-acknowledgement announcement storm; VoiceOver, Full Keyboard Access, 200% zoom/reflow, Increase Contrast, Differentiate Without Color, Reduce Transparency, Reduce Motion, system theme changes while open, non-US layouts, IME/dead keys, and safe focus after row removal/dialog/window recreation.

### Performance, privacy, developer experience, and proof

- **D-43:** Prioritize time-to-local-interactive and input latency. Bundle local assets, defer nonessential setup, never block the main or renderer thread with database/network work, measure cold/warm launch, Quick Entry open-to-focus, local commit latency, list scroll, idle CPU/memory, wake/reconnect work, WAL size/checkpoint cost, and packaged footprint before optimizing.
- **D-44:** Diagnostic events contain closed lifecycle/sync operation and outcome codes, bounded counts, coarse timings, artifact/schema versions, and low-cardinality process roles only. Never log task text, drafts, commands, credentials, tokens, cursors, fingerprints, raw identifiers, server URLs, database paths, or arbitrary window titles.
- **D-45:** Provide ordinary commands such as `dev:desktop`, `typecheck:desktop`, `test:desktop`, `test:desktop:ipc`, `test:desktop:e2e`, `package:desktop`, and `smoke:desktop:packaged`. Development uses isolated temporary profiles, inspectable main/worker processes, renderer HMR, deterministic clocks/IDs/network/credential ports, scenario-named privacy-safe fixtures, and no dependence on a developer’s real Keepling data.
- **D-46:** Test in layers: pure reducer/state-machine and Phase 2 vectors; real SQLite transaction/migration/fault fixtures; hostile preload/main contract tests; Electron E2E for offline/relaunch/menu/keyboard/conflict/lifecycle behavior; then an installed packaged-artifact lane. Keep combinatorial semantics below E2E and reserve packaged tests for ABI/resources/process/lifecycle/OS failures.
- **D-47:** The packaged gate launches exact built bytes outside the source tree with no dev server, asserts packaged/local-content/security configuration, migrates retained fixtures, commits offline, hard-kills, relaunches, reconnects exactly once, and binds evidence to the artifact digest. An Electron/runtime/storage dependency bump cannot merge until the relevant packaged lane passes.
- **D-48:** Adversarial fixtures include shortcut collision/rebinding, non-US layout and IME composition, invalid restored display bounds, renderer crash after local commit but before UI acknowledgement, quit during a database transaction, result loss after server commit, quick-entry/main-window concurrency, close-versus-quit residency, wake/reconnect, remote removal of the focused task, authentication revocation with pending mutations, IPC sequence gaps, theme/accessibility changes mid-dialog, conflict with a durable draft, `SQLITE_BUSY`, disk-full/read-only, migration failure, corruption without auto-reset, and local removal with pending work.

### the agent's Discretion

- Exact pane-resize affordance, default/restored window bounds, toolbar iconography, and coarse destination title copy within the native-window contract.
- Exact synchronization grace duration, capped backoff constants, status-control placement, and popover versus inspector presentation within the locked state meanings.
- Exact runtime-validation implementation and facade method grouping, provided named least-privilege capabilities and closed shapes remain intact.
- Whether store work begins in a worker thread or utility process, provided no meaningful synchronous database work blocks Electron’s main event loop and failure recovery remains deterministic.
- The final SQLite adapter only after the exact pinned-runtime packaged spike applies D-33’s gates.
- Exact Mac density aliases and animation timing through the Phase 3 UI specification, while retaining semantic tokens, accessible focus/targets, and Reduce Motion.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Product, scope, and retained architecture

- `.planning/PROJECT.md` — product promise, constraints, and personal dogfood success criterion.
- `.planning/REQUIREMENTS.md` — MAC-01 through MAC-05, QUAL-03/04, and incremental SRV-02 proof.
- `.planning/ROADMAP.md` — fixed Phase 3 goal and success criteria; Phase 2’s deferred outer acceptance remains separate.
- `.planning/research/SUMMARY.md` — normalized platform, dependency, and quality posture.
- `.planning/knowledge/snapshots/2026-08-28-platform-and-architecture.md` — Electron/local-first ownership, sharing boundaries, staging, and unresolved storage/signing questions.
- `.planning/knowledge/OPEN-QUESTIONS.md` — OQ-005 SQLite adapter, OQ-008 at-rest posture, and OQ-010 signing trigger.
- `docs/architecture/REPOSITORY.md` — monorepo boundaries, dependency direction, deliberate sharing/duplication, and native-tool preference.
- `apps/desktop/README.md` — main/preload/renderer ownership statement.

### Brand and UI foundation

- `docs/brand/BRAND-SEED.md` — current brand authority for calm agency, earned trust, voice, color territory, typography, motion, and native restraint.
- `.planning/phases/KPL-01-one-trustworthy-task/01-UI-SPEC.md` — approved semantic design, responsive workspace, component, copy, focus, and accessibility contracts to inherit intentionally.
- `.planning/phases/KPL-01-one-trustworthy-task/01-UI-REVIEW.md` — verified strengths and remaining real VoiceOver/perceptual/password-manager dogfood limits.
- `packages/design-tokens/tokens.json` — current DTCG-compatible semantic token source.

### Synchronization, authorization, and recovery

- `.planning/phases/KPL-02-synchronization-and-replaceable-server/02-CONTEXT.md` — D-01 through D-54 synchronization, fencing, compatibility, recovery, state, privacy, and user-language decisions.
- `.planning/phases/KPL-02-synchronization-and-replaceable-server/02-01-SUMMARY.md` — reference reducer, durable queue/dependency model, and storage-neutral vector proof.
- `.planning/phases/KPL-02-synchronization-and-replaceable-server/02-03-SUMMARY.md` — installation grant and account/server namespace fencing.
- `.planning/phases/KPL-02-synchronization-and-replaceable-server/02-05-SUMMARY.md` — authenticated synchronization transport and trust-state vocabulary.
- `.planning/phases/KPL-02-synchronization-and-replaceable-server/02-11-SUMMARY.md` — native PKCE, opaque credential rotation, installation revocation, and server-derived bearer namespace.
- `packages/contracts/vectors/sync.json` — cross-runtime synchronization scenarios and expected state transitions.
- `packages/contracts/schemas/sync-state-machine.schema.json` — closed reference synchronization vocabulary.
- `packages/contracts/openapi/keepling.yaml` — released wire operations and closed DTO/error contracts.

### Existing presentation and semantic command seams

- `apps/web/src/app/AppShell.tsx` — dirty-work, navigation, logout, recovery, and shell ownership to adapt rather than duplicate blindly.
- `apps/web/src/app/WorkspaceShell.tsx` — current semantic navigation/list/detail composition and responsive behavior.
- `apps/web/src/features/capture/QuickCapture.tsx` — browser capture behavior and exact-delivery recovery seam.
- `apps/web/src/commands/submission.ts` — immutable exact submission/lookup/retry semantics that must not become Electron persistence authority.
- `apps/web/src/features/recovery/RecoveryStrip.tsx` — persistent recovery-action presentation.
- `apps/web/src/features/tasks/ConflictResolver.tsx` — user-visible structured conflict resolution.
- `apps/web/src/api/keepling.ts` — current wire-to-browser mapping and evidence that generated DTOs and presentation models are already distinct.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `WorkspaceShell` and `AppShell`: proven navigation/list/detail, dirty-work, focus, modal, and recovery behavior; Phase 3 should extract stable presentation contracts behind a facade rather than import browser transport/lifecycle assumptions.
- `QuickCapture`, task editor/list/lifecycle/conflict/recovery components: tested semantic UI and microcopy foundations for the main workspace and Quick Entry presentation.
- `commands/submission.ts`: useful exact-identity acknowledgement classification and recovery concepts, but Electron must move authority into durable main-owned orchestration.
- Generated TypeScript contract plus sync schemas/vectors: wire and cross-runtime truth for the Electron adapter and store tests.
- DTCG token source and UI contract tests: reusable semantic visual intent, light/dark values, spacing/type scale, forced-colors behavior, and drift enforcement.

### Established Patterns

- Server domain/application rules remain independent of Phoenix transport, Ecto records, generated clients, UI, and client persistence.
- Immutable commands, fingerprints, stable mutation identities, exact terminal acknowledgements, structured conflicts, and ordered feed coverage already exist.
- Browser presentation already separates generated wire DTOs from `BrowserTask` and other view-oriented shapes.
- UI state is explicit and persistent for unknown delivery, authentication expiry, conflict, recovery, and destructive confirmation; routine success is quiet.
- Tests use deterministic clocks/identities/faults and user-visible evidence rather than treating network response timing as truth.

### Integration Points

- Add desktop composition, preload, renderer bootstrap, store worker, packaging, and exact-artifact evidence under `apps/desktop`.
- Extract only proven shared React presentation/facade types into packages while keeping browser and Electron adapters separate.
- Consume generated transport in the main-owned sync adapter; map explicitly into local records and renderer view models.
- Drive local orchestration with Phase 2 vectors and attach to the existing bearer-authenticated compatibility/bootstrap/feed/command APIs.
- Feed native menus, Quick Entry, window restoration, lifecycle, and Sync & Recovery through the same `DesktopApplication` operations used by the renderer.

</code_context>

<specifics>
## Specific Ideas

- The coherent reference is Things-like calm and speed combined with stronger local acceptance, explicit conflict/recovery, and inspectability. Things contributes useful lessons in quick entry, menu/keyboard discoverability, sidebar restraint, and optional complexity; its release history also warns about shortcut layouts, stale focus, overscroll, minimum widths, and excessive animation.
- Mail/Notes/OmniFocus-style sidebar/list/detail behavior is the familiar Mac navigation model; Keepling should take the spatial convention without importing configuration-heavy perspectives or administrative chrome.
- Linear’s delayed pending-count pattern supports hiding routine synchronization until it is slow or actionable, while its overwrite-prone offline model is exactly what Keepling’s expected revisions and structured conflicts must avoid.
- Notion’s move from cache-like SQLite toward durable dependency-aware offline storage validates the storage direction, while selective-download and broad workspace complexity are unnecessary for Keepling’s bounded personal dataset.
- Joplin and VS Code support process/runtime separation, local-first fixtures, and layered adapters; their broad shared backend/service surfaces warn against letting persistence models or generic services become universal domain truth.
- Official platform evidence: [Apple designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/), [keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards), [accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), and [state restoration](https://developer.apple.com/documentation/AppKit/restoring-your-app-s-state-with-appkit); [Electron process model](https://www.electronjs.org/docs/latest/tutorial/process-model), [security](https://www.electronjs.org/docs/latest/tutorial/security), [context isolation](https://www.electronjs.org/docs/latest/tutorial/context-isolation), [IPC](https://www.electronjs.org/docs/latest/tutorial/ipc), [performance](https://www.electronjs.org/docs/latest/tutorial/performance), [menus](https://www.electronjs.org/docs/latest/tutorial/menus), [keyboard shortcuts](https://www.electronjs.org/docs/latest/tutorial/keyboard-shortcuts/), [safeStorage](https://www.electronjs.org/docs/latest/api/safe-storage), [packaging](https://www.electronjs.org/docs/latest/tutorial/tutorial-packaging), and [automated testing](https://www.electronjs.org/docs/latest/tutorial/automated-testing).
- Official storage evidence: [Node SQLite](https://nodejs.org/api/sqlite.html), [SQLite transactions](https://www.sqlite.org/lang_transaction.html), [WAL](https://www.sqlite.org/wal.html), and [online backup](https://www.sqlite.org/backup.html). Planning must recheck API stability and every version-sensitive claim against the exact pinned Electron runtime and packaged artifact.
- Direct peer evidence: [Things Quick Entry](https://culturedcode.com/things/support/articles/2249437/), [keyboard shortcuts](https://culturedcode.com/things/support/articles/2785159/), [multiple windows](https://culturedcode.com/things/support/articles/2803580/), and [release notes](https://culturedcode.com/things/support/articles/1100684/); [OmniFocus capture](https://support.omnigroup.com/documentation/omnifocus/universal/4.3.3/en/capture-methods/); [Todoist quick add](https://www.todoist.com/help/todoist/features/use-task-quick-add-in-todoist-va4Lhpzz); [Linear offline behavior](https://linear.app/docs/get-the-app); [Notion offline architecture](https://www.notion.com/blog/how-we-made-notion-available-offline); and [Joplin architecture](https://joplinapp.org/help/dev/spec/architecture/) and [synchronization](https://joplinapp.org/help/dev/spec/sync/).

</specifics>

<deferred>
## Deferred Ideas

- General multi-window task/list workflows, detached editors, weekly-review windows, and Window-menu task titles; revisit only after a measured workflow cannot fit the primary window.
- Menu-bar extra, separate background helper, capture while the main app is fully terminated, and launch at login; these add signing, installation, upgrade, and split-brain surfaces.
- Cross-application Autofill/helper capture of browser, email, file, or selection context; defer until plain Quick Entry is proven and a privacy-reviewed need exists.
- Signing/notarization, public distribution, automatic updates, and update-stable Keychain claims; later release work must prove the same exact artifact under the signed path.
- OS notifications, reminders, and notification orchestration; routine synchronization is intentionally in-product and quiet.
- Application-layer database encryption, biometric app lock, cryptographic erasure, and remote wipe; Phase 3 documents the honest FileVault/permissions baseline and keeps the credential port replaceable.
- Windows/Linux Electron artifacts and platform-neutral window/shortcut abstraction; macOS is the Phase 3 proof target.
- Browser offline persistence or shared browser/Electron SQLite/OPFS machinery; the browser remains online-first.

</deferred>

---

*Phase: 3-Mac Daily Loop*
*Context gathered: 2026-09-02*
