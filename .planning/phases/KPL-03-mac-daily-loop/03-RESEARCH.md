# Phase KPL-03: Mac Daily Loop - Research

**Researched:** 2026-09-02
**Domain:** Electron macOS local-first client, SQLite durability, synchronization, and packaged-artifact proof
**Confidence:** HIGH for project architecture and sync semantics; MEDIUM for newly released Electron/runtime package choices

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

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

### Deferred Ideas (OUT OF SCOPE)

- General multi-window task/list workflows, detached editors, weekly-review windows, and Window-menu task titles; revisit only after a measured workflow cannot fit the primary window.
- Menu-bar extra, separate background helper, capture while the main app is fully terminated, and launch at login; these add signing, installation, upgrade, and split-brain surfaces.
- Cross-application Autofill/helper capture of browser, email, file, or selection context; defer until plain Quick Entry is proven and a privacy-reviewed need exists.
- Signing/notarization, public distribution, automatic updates, and update-stable Keychain claims; later release work must prove the same exact artifact under the signed path.
- OS notifications, reminders, and notification orchestration; routine synchronization is intentionally in-product and quiet.
- Application-layer database encryption, biometric app lock, cryptographic erasure, and remote wipe; Phase 3 documents the honest FileVault/permissions baseline and keeps the credential port replaceable.
- Windows/Linux Electron artifacts and platform-neutral window/shortcut abstraction; macOS is the Phase 3 proof target.
- Browser offline persistence or shared browser/Electron SQLite/OPFS machinery; the browser remains online-first.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MAC-01 | “User can capture, view Inbox and Today, edit, complete, reopen, trash, restore, and undo from the Electron Mac client.” [VERIFIED: `.planning/REQUIREMENTS.md:32-38`] | One `DesktopApplication` command path, durable SQLite acceptance transaction, shared React presentation, and native menu/window adapters. |
| MAC-02 | “User can perform the supported daily loop with complete keyboard navigation and quick entry.” [VERIFIED: `.planning/REQUIREMENTS.md:32-38`] | Native application menu/global shortcut adapters, focus-by-identity state, IME-safe key routing, resident Quick Entry window, and accessibility/E2E proof. |
| MAC-03 | “User can mutate tasks while offline, quit or lose the process, relaunch, and later reconcile without losing or duplicating accepted intent.” [VERIFIED: `.planning/REQUIREMENTS.md:32-38`] | `BEGIN IMMEDIATE` projection+journal+outbox transaction, one worker-owned connection, exact acknowledgement settlement, retained migration/crash fixtures, and hard-kill packaged tests. |
| MAC-04 | “User can inspect offline, syncing, conflict, authentication-expired, and unrecoverable states without reading logs.” [VERIFIED: `.planning/REQUIREMENTS.md:32-38`] | Main-owned closed presentation projection, bounded Sync & Recovery surface, recovery shell, conflict flow, and privacy-safe diagnostics. |
| MAC-05 | “User receives proof that the packaged installed application—not only a development renderer—preserves and synchronizes the local store.” [VERIFIED: `.planning/REQUIREMENTS.md:32-38`] | Exact `.app` executable launch, `app.isPackaged` assertion, no-dev-server/resource/security assertions, digest-bound hard-kill/relaunch/reconnect lane. |
| QUAL-03 | “Release promotion uses the exact revision and artifact previously tested; distribution jobs do not silently rebuild different bytes.” [VERIFIED: `.planning/REQUIREMENTS.md:69-75`] | Build once, hash the `.app`/ZIP, test those bytes outside the source tree, and retain the digest with test evidence. |
| QUAL-04 | “Important screens have representative user-level coverage for meaningful populated, empty, loading, offline, denied, stale, conflict, partial, retry, and unrecoverable states.” [VERIFIED: `.planning/REQUIREMENTS.md:69-75`] | Deterministic facade/store/network ports plus renderer component tests, Electron E2E, and a smaller packaged matrix. |
| SRV-02 | “User receives the same domain invariants through web, desktop, iPhone, API, and MCP entry points.” [VERIFIED: `.planning/REQUIREMENTS.md:18-25`] | Electron invokes released semantic server commands and sync contracts; it never reimplements canonical merge/invariant authority. Phase 3 proves only the Electron adapter increment. |
</phase_requirements>

## Summary

Phase 3 should be planned as a sequence of vertical trust proofs, not as “build renderer, then add persistence, then package.” The first executable slice must pin Electron, create a real packaged `.app`, run `node:sqlite` in a dedicated worker behind `LocalStorePort`, commit a capture projection plus immutable journal/outbox in one transaction, hard-kill the app, relaunch the same isolated profile, and reconcile the exact mutation once. This follows the locked phase decisions and closes the highest-cost unknown—whether the exact Electron/Node/SQLite combination survives packaging and crash recovery—before broad UI work. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:68-102`] [CITED: https://nodejs.org/download/release/v24.18.1/docs/api/sqlite.html]

Electron 44.0.0 embeds Node 24.18.1, while Node 24.18.1 still labels `node:sqlite` “Stability: 1.2 - Release candidate” and states that every `DatabaseSync` API executes synchronously. Therefore use a Node worker thread first, never the Electron main event loop, and make the adapter decision conditional on a packaged spike. [CITED: https://www.electronjs.org/blog/electron-44-0] [CITED: https://nodejs.org/download/release/v24.18.1/docs/api/sqlite.html] The fallback remains `better-sqlite3` only behind the same port and only after a failed gate; it should not be installed speculatively. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:68-76`]

The renderer boundary is a second independent proof: local packaged content, `nodeIntegration: false`, context isolation, renderer sandboxing, a restrictive CSP/custom application protocol, denied unexpected navigation/window creation/permissions, validated senders, and one runtime-validated method per semantic capability. Electron’s official security guidance explicitly recommends these controls and warns against exposing raw IPC. [CITED: https://www.electronjs.org/docs/latest/tutorial/security] [CITED: https://www.electronjs.org/docs/latest/tutorial/context-isolation] [CITED: https://www.electronjs.org/docs/latest/tutorial/sandbox]

**Primary recommendation:** Plan an initial packaged capture/relaunch tracer, then expand the same durable command path into synchronization/recovery, then into the complete daily loop and Mac lifecycle; do not defer packaging, IPC hardening, migration proof, or exact-artifact evidence to the final wave. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:96-102`]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Workspace, task list/detail, capture, conflict and recovery presentation | Browser / Client (Electron renderer) | Electron preload | React owns presentation and focus only; preload exposes closed capabilities. [VERIFIED: `apps/desktop/README.md:1-6`] |
| Local mutation acceptance and semantic command orchestration | Electron main-owned application | Database / Storage worker | `DesktopApplication` is the client authority; persistence executes behind `LocalStorePort`. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:57-76`] |
| Window, menu, Quick Entry, shortcut, appearance, resident lifecycle | Electron main | Browser / Client | These are OS/lifecycle adapters feeding the same application commands, never alternate business paths. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:18-56`] |
| SQLite projection, canonical shadow, journal, dependency graph, outbox, migrations | Database / Storage worker | Electron main-owned application | One serialized worker connection owns atomic persistence; main owns orchestration and recovery presentation. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:68-82`] |
| Synchronization scheduling, namespace fence, credentials | Electron main-owned application | API / Backend | Client schedules bounded work and retains local intent; server supplies namespace authority and canonical acceptance. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:36-67`] |
| Authorization, domain invariants, idempotency, revisions, merge/conflict decisions, ordered feed | API / Backend | PostgreSQL | Desktop consumes existing semantic commands/contracts and does not clone canonical authority. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:7-12,57-67`] |
| Packaged artifact build and digest-bound evidence | Build/release boundary | Electron application tiers | Exact built bytes must be launched outside source, tested, and identified by digest. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:96-102`] |

## Project Constraints (from AGENTS.md)

- Preserve the modular monolith and inward dependency direction; server domain code cannot depend on Phoenix transport, MCP, generated clients, UI, Electron, or client persistence. [VERIFIED: `AGENTS.md:5-20,90-102`]
- PostgreSQL remains canonical; desktop SQLite is a local projection/outbox, not another canonical service. [VERIFIED: `AGENTS.md:5-20`]
- Report client success only after projection and durable outbox commit atomically; delivery, sockets, background execution, timers, and graceful shutdown are never correctness assumptions. [VERIFIED: `AGENTS.md:5-20,90-102`]
- UI, API, Electron, and later MCP must use the same semantic application commands; no raw patch or database bypass. [VERIFIED: `AGENTS.md:90-102`]
- Keep Ecto schemas, generated wire DTOs, desktop SQLite rows, and renderer view models separate; deliberate duplication is preferred to cross-platform coupling. [VERIFIED: `AGENTS.md:90-102`]
- Do not emit task titles, notes, prompts, credentials, raw tokens, or arbitrary identifiers in diagnostics. [VERIFIED: `AGENTS.md:5-20,90-102`]
- Do not claim completion, safety, compatibility, restore health, or release readiness without fresh executable evidence at the relevant boundary. [VERIFIED: `AGENTS.md:90-102`]
- Use root Git/GSD only; never create nested repositories, submodules, or application-level planning roots. [VERIFIED: `AGENTS.md:83-89`]
- Use native tools first—pnpm workspaces for TypeScript—and do not introduce Nx, Turborepo, an ORM, Redis, Elasticsearch, Kubernetes, or a universal runtime/domain framework without measured need. [VERIFIED: `docs/architecture/REPOSITORY.md:62-72`]
- No project-local skill directories exist for this phase, so there are no additional project skill rules to apply. [VERIFIED: `AGENTS.md:62-66`]

## Standard Stack

### Core

| Library / runtime | Version | Purpose | Why Standard |
|-------------------|---------|---------|--------------|
| Electron | Pin `44.1.1` only after human verification and the packaged spike. **[WARNING: legitimacy gate marked SUS because the release is too new.]** | Main/preload/renderer runtime and Mac integration | The project locks Electron; the official 44 release embeds Chromium 152 and Node 24.18.1. Registry current was 44.1.1 on 2026-09-02. [CITED: https://www.electronjs.org/blog/electron-44-0] [CITED: https://releases.electronjs.org/release/v44.0.0] [VERIFIED: npm registry query] |
| Node `node:sqlite` | Embedded Node `24.18.1`; module stability `1.2` release candidate | Primary SQLite adapter candidate inside one worker | It is built into the pinned runtime, has `DatabaseSync`, prepared statements, timeout/defensive/foreign-key options, and `sqlite.backup`; its synchronous and pre-stable nature is why the spike is mandatory. [CITED: https://nodejs.org/download/release/v24.18.1/docs/api/sqlite.html] |
| React / React DOM | Quote from existing manifest: `"react": "^19.2.8"`, `"react-dom": "^19.2.8"` | Shared presentation | Reuse the proven web presentation seam while keeping browser and Electron adapters distinct. [VERIFIED: `apps/web/package.json:15-24`] |
| TypeScript | Quote from desktop-compatible existing web manifest: `"typescript": "~6.0.2"` | Strict cross-process types and mappers | Existing presentation tooling already uses strict TS-compatible packages; runtime validation remains separate. [VERIFIED: `apps/web/package.json:26-49`] |
| Zod | Pin `4.5.4` only after human verification. **[WARNING: legitimacy gate marked SUS because the release is too new.]** | Closed runtime validation on both preload and main sides | Official docs describe TypeScript-first parsing, zero external dependencies, and stable Zod 4; use strict objects/discriminated unions and reject unknown fields. [CITED: https://zod.dev/] [VERIFIED: npm registry query] |

### Supporting

| Library / runtime | Version | Purpose | When to Use |
|-------------------|---------|---------|-------------|
| `@electron-forge/cli` | `7.11.2` | Package the app | Electron recommends Forge; use direct Vite builds before Forge packaging rather than the experimental Forge Vite plugin. [VERIFIED: npm registry] [CITED: https://www.electronjs.org/docs/latest/tutorial/application-distribution] |
| `@electron-forge/maker-zip` | `7.11.2` | Produce a basic macOS ZIP containing the `.app` | Use for exact-artifact dogfood transport/evidence; signing/notarization remain deferred. [VERIFIED: npm registry] [CITED: https://www.electronforge.io/config/makers/zip] |
| Vite | Quote: `"vite": "^8.2.2"` | Renderer/main/preload/worker build inputs | Reuse the existing project tool directly; avoid `@electron-forge/plugin-vite` because its official docs still mark it experimental with minor-version breaking-change risk. [VERIFIED: `apps/web/package.json:43-48`] [CITED: https://www.electronforge.io/config/plugins/vite] |
| Vitest | Quote: `"vitest": "4.1.11"` | Pure reducer, facade, bridge schema, component, worker protocol tests | Keep combinatorial state-machine and fault tests below Electron E2E. [VERIFIED: `apps/web/package.json:43-48`] |
| Playwright | Quote: `"@playwright/test": "1.62.1"` | Electron E2E and exact packaged executable launch | Its Electron support is explicitly experimental, but `electron.launch({ executablePath })` can launch the built executable; always bind with lower-layer tests and artifact assertions. [VERIFIED: `apps/web/package.json:26-35`] [CITED: https://playwright.dev/docs/api/class-electron] |
| `better-sqlite3` | `13.0.3`, fallback only. **[WARNING: legitimacy gate marked SUS because the release is too new.]** | Replacement adapter if `node:sqlite` fails a declared gate | Do not install in Wave 0 merely as insurance; a native addon expands ABI/rebuild/package proof. The locked phase context predeclares it as the fallback. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:68-76`] [VERIFIED: npm registry query] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Worker thread for `node:sqlite` | Electron utility process | Stronger failure containment but adds a second serialization/protocol/version/lifecycle surface; promote only after a measured isolation need. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:104-111`] |
| `node:sqlite` | `better-sqlite3` | More mature external adapter but native ABI/rebuild/package complexity; use only if the pinned packaged spike fails stability, crash, performance, or architecture gates. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:68-76`] |
| Direct Vite builds + Forge package | Forge Vite plugin | The plugin integrates HMR/build entries but is officially experimental and may break in minor releases. [CITED: https://www.electronforge.io/config/plugins/vite] |
| Playwright-only development E2E | Playwright packaged executable plus OS-level/manual accessibility checks | Playwright can launch a binary but cannot prove VoiceOver/system menu/global shortcut behavior by DOM assertions alone. [CITED: https://playwright.dev/docs/api/class-electron] [ASSUMED] |

**Installation (after the two human-verification checkpoints):**

```bash
pnpm --filter @keepling/desktop add zod@4.5.4
pnpm --filter @keepling/desktop add -D electron@44.1.1 @electron-forge/cli@7.11.2 @electron-forge/maker-zip@7.11.2
```

Do not install `better-sqlite3` unless the adapter gate records why `node:sqlite` failed. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:68-76`]

## Package Legitimacy Audit

| Package | Registry | Age / latest publish | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|----------------------|-----------|-------------|---------|-------------|
| `electron` | npm | Created 2012-05-18; 44.1.1 published 2026-09-01 | 6,383,880/week | github.com/electron/electron | SUS (`too-new`) | Planner adds `checkpoint:human-verify` before pin/install; packaged spike remains mandatory. [VERIFIED: npm registry and GSD legitimacy gate] |
| `@electron-forge/cli` | npm | Created 2018-04-16; 7.11.2 modified 2026-07-02 | 1,194,100/week | github.com/electron/forge | OK | Approved. [VERIFIED: npm registry and GSD legitimacy gate] |
| `@electron-forge/maker-zip` | npm | Created 2018-04-16; 7.11.2 modified 2026-07-02 | 1,104,184/week | github.com/electron/forge | OK | Approved. [VERIFIED: npm registry and GSD legitimacy gate] |
| `zod` | npm | Created 2020-03-07; 4.5.4 published 2026-08-29 | 274,747,331/week | github.com/colinhacks/zod | SUS (`too-new`) | Planner adds `checkpoint:human-verify` before direct dependency. [VERIFIED: npm registry and GSD legitimacy gate] |
| `better-sqlite3` | npm | Created 2016-09-07; 13.0.3 published 2026-08-05 | 10,381,531/week | github.com/WiseLibs/better-sqlite3 | SUS (`too-new`) | Not installed initially; if fallback is activated, planner adds `checkpoint:human-verify` plus native packaged ABI lane. [VERIFIED: npm registry and GSD legitimacy gate] |

The registry returned no `scripts.postinstall` value for the audited packages. This is an observation from the query, not evidence that future versions cannot add scripts; re-run the audit at the exact lockfile change. [VERIFIED: npm registry query on 2026-09-02]

**Packages removed due to [SLOP] verdict:** none. [VERIFIED: GSD legitimacy gate]

**Packages flagged as suspicious [SUS]:** `electron`, `zod`, `better-sqlite3`. The planner must insert `checkpoint:human-verify` before each actual install; the fallback checkpoint is conditional. [VERIFIED: GSD legitimacy gate]

## Architecture Patterns

### System Architecture Diagram

```text
Mac input
  ├─ native menu / local shortcut ─────────────┐
  ├─ global Quick Entry shortcut ──────────────┤
  └─ React main/Quick Entry renderer ──────────┤
                                               v
                                    named ClientFacade operation
                                               |
                          validated request -> preload bridge
                                               |
                              sender + schema validation again
                                               v
                                      DesktopApplication
                     ┌─────────────────────────┼─────────────────────────┐
                     v                         v                         v
              LocalStorePort              SyncPort                CredentialPort
                     |                         |                         |
             dedicated worker                 |                  Electron safeStorage
                     |                         |
        BEGIN IMMEDIATE acceptance             +--> compatibility/bootstrap/feed/command API
        projection + journal + outbox          |             |
                     |                         |             v
                     v                         |       Phoenix application/domain
            committed local snapshot           |             |
                     |                         |             v
                     +--> renderer sequence <--+         PostgreSQL canonical
                              |
                    gap? -- yes --> refetch opaque snapshot
                              |
                             no
                              v
                         update view

Decision branches:
  local COMMIT fails -> no “Saved on this Mac”; preserve draft; recovery action
  exact ack matches mutation + fingerprint -> atomic terminal settlement/removal
  rejected/stale/conflict -> retain/recompute local truth; bounded Review surface
  auth/namespace fence -> stop pushes for that namespace; retain local intent
  migration/integrity/open failure -> recovery shell; never auto-create/reset
```

This flow is the locked dependency direction and trust model. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:7-12,36-82`]

### Recommended Project Structure

The locked directory roots are quoted verbatim: “`apps/desktop/main` for composition/lifecycle/windows, `apps/desktop/preload` for the bridge, `apps/desktop/renderer` for bootstrap, and a supervised store worker owned by the desktop application.” [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:57-67`]

```text
apps/desktop/
├── main/                   # composition, DesktopApplication, lifecycle, menus/windows
│   ├── application/        # semantic command orchestration + presentation projection
│   ├── adapters/           # sync, credentials, clock/IDs, OS integrations
│   └── windows/            # main and Quick Entry controllers
├── preload/                # one named, validated capability bridge
├── renderer/               # disposable React bootstrap(s)
├── store-worker/           # worker protocol, LocalStorePort adapter, SQL/migrations
├── migrations/             # immutable SQL plus checksum manifest
├── test/                   # pure, SQLite, IPC, Electron E2E, packaged smoke
└── package.json            # desktop-local commands and pinned runtime

packages/
├── web-ui/                 # extract only proven platform-free React seams
├── client-core-ts/         # pure sync/orchestration only where Phase 2 vectors prove sharing
└── api-client-ts/          # generated transport only
```

The specific leaf filenames are a planning recommendation, not an existing path contract. [ASSUMED]

### Pattern 1: Packaged walking skeleton first

**What:** Freeze the runtime/lockfile, package a minimal `.app`, open an isolated profile, accept one offline capture into SQLite, hard-kill, relaunch, read it locally, reconnect, verify exact acknowledgement once, and bind evidence to the artifact digest. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:96-102`]

**When to use:** Wave 0/1, before broad UI extraction or schema expansion. The spike decides `node:sqlite` versus the predeclared fallback. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:68-76`]

**Gate:** Require evidence for embedded versions, API availability, worker isolation, packaged module loading, atomicity, kill/relaunch recovery, WAL handling, migration fixtures, bounded latency, restrictive renderer configuration, and exact executable digest. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:68-102`]

### Pattern 2: Functional core, imperative Electron shell

**What:** Keep orchestration/reducers/presentation projection as deterministic TypeScript over storage-neutral models; put Electron objects, Node workers, SQLite calls, network, safeStorage, clock/IDs, and OS signals behind ports. [VERIFIED: `docs/architecture/REPOSITORY.md:37-60`]

**When to use:** Every daily-loop command and synchronization transition. Phase 2 already provides a persistence-neutral reference reducer and vectors. Its source explicitly separates `"canonical_shadow"`, `"visible"`, `"journal"`, `"dependencies"`, `"outbox"`, `"cursor"`, and `"fence"`. [VERIFIED: `apps/server/lib/keepling/application/sync/reference_model.ex:1-29`]

### Pattern 3: Atomic local acceptance, exact terminal settlement

**What:** One worker-owned `BEGIN IMMEDIATE` transaction updates visible projection and writes immutable command bytes/fingerprint, journal, dependencies, and outbox. Only post-commit may the application emit local success. Exact acknowledgement settlement verifies both identity and fingerprint, updates canonical/conflict state, terminalizes the journal, replays projection, and deletes exactly that outbox row atomically. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:68-82`]

The existing reference vocabulary is quoted verbatim: outcomes are `"accepted"`, `"already_satisfied"`, `"rejected"`, `"stale"`, `"conflict"`; only `"accepted"` and `"already_satisfied"` satisfy dependencies; batch bounds are `50` pulled changes and `25` ready pushes. [VERIFIED: `apps/server/lib/keepling/application/sync/reference_model.ex:11-14`] Exact matching compares `"mutation_id"` and `"fingerprint"`. [VERIFIED: `apps/server/lib/keepling/application/sync/reference_model.ex:132-169`]

SQLite permits only one simultaneous writer; `BEGIN IMMEDIATE` starts the write transaction immediately and may return `SQLITE_BUSY` if another writer exists. [CITED: https://www.sqlite.org/lang_transaction.html] Therefore one writer connection plus finite busy handling is the simplest enforceable design. [CITED: https://www.sqlite.org/lang_transaction.html]

### Pattern 4: Subscription-before-snapshot presentation mirror

**What:** Preload subscribes to semantic updates before requesting the initial snapshot. Each update carries one monotonic local presentation sequence; any gap discards incremental assumptions and refetches the opaque snapshot. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:57-67`]

**When to use:** Main and Quick Entry renderer creation/reload. Renderer state may own transient focus/draft editing, but committed task/sync truth comes from `DesktopApplication`. [VERIFIED: `apps/desktop/README.md:1-6`]

### Pattern 5: Namespace-scoped store supervisor

**What:** Derive the selected namespace only from the five server-authoritative dimensions already frozen in Phase 2; open one namespace store, run checksum-verified migrations/invariants, and fence before logout/revocation or namespace switch. Never drain a prior namespace into a new one. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:48-56`]

**When to use:** Startup, sign-in/out, server/account switch, restore generation change, and local data removal. Destructive local removal closes the store first and treats the DB, `-wal`, `-shm`, drafts, caches, metadata and credentials as one verified removal set. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:48-56`]

### Pattern 6: Native adapters invoke semantic commands

**What:** Menu items, keyboard shortcuts, Quick Entry, Dock activation, wake/reconnect hints, and renderer controls all call the same `DesktopApplication` operations. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:18-46,57-67`]

Electron supplies `requestSingleInstanceLock()` and documents resident control through `window-all-closed`, `before-quit`, and `will-quit`; on macOS, command-line launches can bypass the OS single-instance behavior, so the explicit lock is still required. [CITED: https://www.electronjs.org/docs/latest/api/app]

### Recommended MVP plan slices

1. **Runtime, contracts, and evidence harness:** human-verify new packages; freeze runtime/embedded versions; add desktop commands, isolated profiles, deterministic ports, schemas and test runners. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:96-102`]
2. **Packaged offline capture tracer:** worker-owned store, schema ledger, atomic capture, local snapshot, minimal hardened main/preload/renderer, package/hash/hard-kill/relaunch test; make adapter decision here. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:57-82,96-102`]
3. **Exact synchronization and namespace recovery:** compatibility/bootstrap/feed/push/lookup, credential port, auth/namespace fences, exact ack, conflict/rejection/uncertain states, Sync & Recovery projection. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:36-67`]
4. **Mac workspace daily loop:** extract facade-driven presentation; Inbox/Today/detail/edit/lifecycle/trash/restore/undo; native menus; focus restoration; main-window lifecycle. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:18-35,83-95`]
5. **Quick Entry and resident lifecycle:** configurable global shortcut, collision/rebind, durable Quick Entry draft, prior-app focus return, close-versus-quit and Dock recreation. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:18-56`]
6. **Adversarial and exact-artifact gate:** migration lineage, store faults, renderer crash/sequence gaps, IME/layout, accessibility/theme, sync faults, packaged security/resources, artifact digest, and daily-use runbook. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:83-102`]

### Anti-Patterns to Avoid

- **Renderer-owned intent or networking:** reload/crash would become a correctness boundary; route every accepted mutation through main-owned durable orchestration. [VERIFIED: `apps/desktop/README.md:1-6`]
- **Generic IPC (`send(channel, payload)` or raw event callbacks):** Electron explicitly warns to expose one method per message and strip event objects. [CITED: https://www.electronjs.org/docs/latest/tutorial/context-isolation] [CITED: https://www.electronjs.org/docs/latest/tutorial/security]
- **SQLite on the main event loop:** `DatabaseSync` is entirely synchronous; worker isolation is required. [CITED: https://nodejs.org/download/release/v24.18.1/docs/api/sqlite.html]
- **Optimistic success before COMMIT:** violates the cross-surface meaning of “Saved on this Mac.” [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:15-17,68-82`]
- **Delete/reinsert outbox on retry:** destroys exact immutable identity and dependency evidence; retain until exact terminal settlement. [VERIFIED: `apps/server/lib/keepling/application/sync/reference_model.ex:31-59,96-169`]
- **One database per representation or attached multi-database transaction:** SQLite WAL transactions across attached databases are atomic per database, not as a set. Keep acceptance-critical tables in one namespace DB. [CITED: https://www.sqlite.org/wal.html]
- **Copying a live WAL database:** the `-wal` and `-shm` are quasi-persistent companions; use `sqlite.backup` or close before whole-unit movement. [CITED: https://www.sqlite.org/wal.html] [CITED: https://nodejs.org/download/release/v24.18.1/docs/api/sqlite.html]
- **Packaged proof through `electron .`:** Electron’s official Playwright tutorial reports `app.isPackaged === false` for development launch. Launch the built executable path and assert true. [CITED: https://www.electronjs.org/docs/latest/tutorial/automated-testing] [CITED: https://playwright.dev/docs/api/class-electron]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Runtime IPC validation | Ad hoc `typeof` chains scattered across preload/main | One audited Zod schema set parsed on both sides | Closed objects, shared inferred types, consistent rejection, zero transitive runtime dependencies; package requires checkpoint. [CITED: https://zod.dev/] |
| Packaging | Custom copy/rename/sign shell pipeline | Electron Forge CLI and ZIP maker | Electron officially recommends Forge; it binds Electron packager conventions and produces a real `.app`/distributable. [CITED: https://www.electronjs.org/docs/latest/tutorial/application-distribution] |
| Database backup/snapshot | `cp` of a live `.sqlite` file | `sqlite.backup()` / SQLite online backup API, or close then move the entire DB+WAL+SHM unit | Live file copies can corrupt on failure and omit WAL state; backup creates a database snapshot. [CITED: https://www.sqlite.org/backup.html] [CITED: https://nodejs.org/download/release/v24.18.1/docs/api/sqlite.html] |
| Sync semantics | A second desktop-specific conflict/idempotency algorithm | Phase 2 contracts/vectors plus released server commands | Server remains merge/invariant authority; clients share behavior, not persistence records. [VERIFIED: `packages/contracts/schemas/sync-state-machine.schema.json:1-110`] |
| Credential encryption | Custom crypto or a synchronous global credential object | Async `CredentialPort` backed by Electron `safeStorage` | Electron supplies platform-backed encryption; macOS consistency requires signing, so Phase 3 must state the unsigned limitation. [CITED: https://www.electronjs.org/docs/latest/api/safe-storage] |
| Global shortcut collision handling | Automatic silent fallback | `globalShortcut.register()` result plus explicit rebind UI | Electron can fail registration and documents a macOS non-QWERTY issue; collision/layout fixtures are required. [CITED: https://www.electronjs.org/docs/latest/api/global-shortcut] [CITED: https://www.electronjs.org/docs/latest/tutorial/keyboard-shortcuts] |
| Canonical server rules | Client-side clones of task invariants/merge rules | Generated transport DTOs, released semantic operations, exact acknowledgements | Required for SRV-02 and compatible released clients. [VERIFIED: `.planning/REQUIREMENTS.md:18-25,112-124`] |

**Key insight:** Hand-written infrastructure at the trust boundaries—IPC, packaging, crypto, backup, sync merge—is more dangerous than deliberate domain-specific orchestration. Keep custom code in the small semantic application/reducer/mapping layer where Keepling’s exact trust vocabulary actually differs. [VERIFIED: `AGENTS.md:90-102`]

## Common Pitfalls

### Pitfall 1: Treating shutdown as the durability boundary

**What goes wrong:** A mutation appears successful but disappears after renderer/main termination because the app buffered it or waited to persist at quit. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:48-56`]

**Why it happens:** Desktop lifecycle hooks feel like a convenient flush point, but Electron/OS termination is not guaranteed and the phase explicitly forbids graceful shutdown as a commit protocol. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:48-56`]

**How to avoid:** Commit projection+journal+outbox before returning success; make quit only a bounded checkpoint/close path. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:68-82`]

**Warning signs:** fire-and-forget worker messages, “flush on quit,” renderer-local accepted state, or tests that only use graceful close. [ASSUMED]

### Pitfall 2: Blocking Electron main with synchronous SQLite

**What goes wrong:** menus, focus, Quick Entry, appearance changes, and renderer IPC stall during database work. [ASSUMED]

**Why it happens:** Node’s `DatabaseSync` methods are all synchronous. [CITED: https://nodejs.org/download/release/v24.18.1/docs/api/sqlite.html]

**How to avoid:** Create one dedicated Node worker with a bounded, runtime-validated message protocol and serialize writes on its connection. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:68-76`]

**Warning signs:** importing `node:sqlite` in main composition/window modules or measuring long main-loop gaps under migration/checkpoint load. [ASSUMED]

### Pitfall 3: Assuming WAL removes `SQLITE_BUSY`

**What goes wrong:** contention faults appear only under quick-entry/main concurrency, checkpointing, or retained fixtures. [ASSUMED]

**Why it happens:** WAL improves reader/writer concurrency but SQLite still has one writer, and `BEGIN IMMEDIATE` can return `SQLITE_BUSY`. [CITED: https://www.sqlite.org/lang_transaction.html] [CITED: https://www.sqlite.org/wal.html]

**How to avoid:** One writer, short transactions, finite `timeout`, explicit busy outcome/retry, and adversarial fixtures. Node 24’s `DatabaseSync` `timeout` defaults to `0`, so configure and measure a finite value rather than inheriting it. [CITED: https://nodejs.org/download/release/v24.18.1/docs/api/sqlite.html]

**Warning signs:** infinite retries, UI spinner without a safe action, multiple write-capable connections, or tests with no busy injection. [ASSUMED]

### Pitfall 4: Losing exact identity during retry/relaunch

**What goes wrong:** duplicate canonical effects or a mismatched acknowledgement removes the wrong local work. [VERIFIED: `apps/server/lib/keepling/application/sync/reference_model.ex:96-169`]

**Why it happens:** code regenerates mutation IDs/bytes after ambiguous delivery or settles on mutation ID without fingerprint. [VERIFIED: `packages/contracts/schemas/sync-state-machine.schema.json:68-93`]

**How to avoid:** Persist immutable bytes before send, calculate SHA-256 once, reuse exact bytes/identity for send/lookup/retry, and atomically settle only when both match. [VERIFIED: `apps/server/lib/keepling/application/sync/reference_model.ex:31-59,132-191`]

**Warning signs:** JSON reserialization on retry, replacement outbox rows, or ack handlers that accept unknown mutations. [ASSUMED]

### Pitfall 5: Renderer inference drift

**What goes wrong:** toolbar, row, and recovery panel disagree about whether work is offline, pending, synced, or conflicted. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:36-46`]

**Why it happens:** each component combines online flags, elapsed timers, and last responses independently. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:36-46`]

**How to avoid:** One main-owned closed presentation projection; renderer only presents snapshot/sequence updates. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:36-46,57-67`]

**Warning signs:** `navigator.onLine`, socket state, or component-local pending counters deciding trust copy. [ASSUMED]

### Pitfall 6: Broad preload convenience API

**What goes wrong:** an XSS or compromised renderer can reach arbitrary filesystem/network/IPC/credential capabilities. [CITED: https://www.electronjs.org/docs/latest/tutorial/security]

**Why it happens:** exposing `ipcRenderer.send/on/invoke`, event objects, channel parameters, or unvalidated object bags. Electron explicitly calls raw exposure unsafe. [CITED: https://www.electronjs.org/docs/latest/tutorial/context-isolation]

**How to avoid:** one named async method per semantic operation, request and response parse on both sides, sender-frame allowlist, local packaged content, restrictive CSP/custom protocol, sandbox, and navigation/window/permission denial. [CITED: https://www.electronjs.org/docs/latest/tutorial/security]

**Warning signs:** renderer imports `electron`, string channel arguments, `any`, or bridge callbacks receiving Electron events. [ASSUMED]

### Pitfall 7: Development E2E masquerading as packaged proof

**What goes wrong:** tests pass through Vite/dev paths but the `.app` fails due to ASAR/resources, embedded Node ABI, worker paths, security flags, app data paths, or lifecycle differences. [ASSUMED]

**Why it happens:** Electron’s Playwright tutorial launches development mode and demonstrates `app.isPackaged === false`. [CITED: https://www.electronjs.org/docs/latest/tutorial/automated-testing]

**How to avoid:** `package:desktop` once; hash it; copy/launch outside source; pass the executable path to Playwright; assert `app.isPackaged`, packaged protocol/CSP, no dev server, worker/SQLite versions, isolated profile, hard kill/relaunch, and digest equality. [CITED: https://playwright.dev/docs/api/class-electron] [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:96-102`]

**Warning signs:** E2E args point at source `main.ts/js`, tests rebuild before launch, or no artifact digest is retained. [ASSUMED]

### Pitfall 8: Over-sharing browser code

**What goes wrong:** Electron inherits browser session/fetch/unknown-delivery authority or UI components import platform adapters. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:149-186`]

**Why it happens:** reusing `AppShell`/submission code wholesale is faster initially than extracting presentation contracts. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:161-186`]

**How to avoid:** Extract only view components/facade types demonstrated by both consumers; keep browser and desktop adapters separate. [VERIFIED: `docs/architecture/REPOSITORY.md:37-60`]

**Warning signs:** shared UI imports browser API clients, Electron IPC, persistence records, or auth/session lifecycle. [ASSUMED]

### Pitfall 9: Shortcut and focus tests using only US-QWERTY DOM events

**What goes wrong:** global Quick Entry fails silently or destructive commands fire during IME composition; row removal/recreation strands focus. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:18-35,83-102`]

**Why it happens:** Electron documents a longstanding global shortcut issue on macOS non-QWERTY layouts, and DOM-only tests do not exercise native registration. [CITED: https://www.electronjs.org/docs/latest/tutorial/keyboard-shortcuts]

**How to avoid:** Persist registration failure with rebind; test native menu/global registration separately from renderer key handling; guard repeat/composition/editable ownership; restore by stable identity. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:18-35`]

**Warning signs:** silent accelerator substitution, only `keydown` tests, focus indices, or bare `Command-Z` handlers in the renderer root. [ASSUMED]

### Pitfall 10: Silent store reset on migration/open/integrity failure

**What goes wrong:** local-only intent is discarded and an empty workspace is presented as healthy. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:48-56`]

**Why it happens:** development-oriented “delete and recreate” recovery is accidentally shipped. [ASSUMED]

**How to avoid:** checksum migration ledger, transactional forward migrations, startup invariant/quick-check, retained lineage fixtures, recovery shell, and explicit separately confirmed local-data removal. STRICT-table types are included in `integrity_check`/`quick_check`. [CITED: https://www.sqlite.org/stricttables.html]

**Warning signs:** catch blocks that unlink the DB, fallback to `:memory:`, or render an empty state after open failure. [ASSUMED]

## Code Examples

These are implementation skeletons, not new wire contracts. Values that are already canonical are quoted beside their source; proposed local names are marked `[ASSUMED]` and must be frozen in implementation tests.

### Worker-owned atomic acceptance

Canonical transaction/storage terms are quoted verbatim from the locked context: `BEGIN IMMEDIATE`, `local_saved`, `synchronous=FULL`, and tables for “namespace metadata, canonical shadow, visible projection, immutable command bytes/fingerprint, mutation journal, dependency edges, outbox, cursor, and conflicts.” [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:68-82`] The reference reducer returns `"local_saved"` only after building journal/dependencies/outbox/visible state. [VERIFIED: `apps/server/lib/keepling/application/sync/reference_model.ex:31-59`]

```typescript
// Source pattern: SQLite transaction docs + locked D-35/D-36.
// Illustrative LocalStorePort method and local SQL names are [ASSUMED].
function acceptLocalMutation(input: LocalMutation): LocalAcceptance {
  db.exec("BEGIN IMMEDIATE");
  try {
    insertImmutableCommand.run(input.commandBytes, input.fingerprint);
    insertJournal.run(input.mutationId, input.acceptedAt);
    insertDependencies(input.mutationId, input.dependencies);
    applyVisibleProjection(input.effect);
    insertOutbox.run(input.mutationId);
    db.exec("COMMIT");
    return { status: "local_saved", snapshot: readWorkspaceSnapshot() };
  } catch (error) {
    db.exec("ROLLBACK");
    throw classifyLocalStoreFailure(error);
  }
}
```

### Exact acknowledgement settlement

Canonical acknowledgement outcomes are quoted verbatim: `"accepted"`, `"already_satisfied"`, `"rejected"`, `"stale"`, `"conflict"`. [VERIFIED: `packages/contracts/schemas/sync-state-machine.schema.json:84-93`] The mutation shape requires `"mutation_id"`, `"fingerprint"`, `"command_bytes"`, `"resource_keys"`, `"dependencies"`, `"accepted_at"`, and `"effect"`. [VERIFIED: `packages/contracts/schemas/sync-state-machine.schema.json:68-83`]

```typescript
// Source pattern: existing ReferenceModel exact_match?/settlement.
// Local adapter method names are [ASSUMED].
function settleExactAcknowledgement(ack: Acknowledgement): void {
  db.exec("BEGIN IMMEDIATE");
  try {
    const queued = requireQueuedMutation(ack.mutation_id);
    if (!timingSafeEqualText(queued.fingerprint, ack.fingerprint)) {
      throw new AcknowledgementMismatch();
    }
    applyCanonicalOrConflict(ack.outcome, ack.snapshot);
    terminalizeJournal(ack.mutation_id, ack.outcome, ack.snapshot);
    recomputeVisibleProjection();
    deleteExactOutboxRow(ack.mutation_id, ack.fingerprint);
    db.exec("COMMIT");
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}
```

### Narrow context-isolated preload bridge

Electron’s official pattern is one filtered method per IPC message and no raw `ipcRenderer` exposure. [CITED: https://www.electronjs.org/docs/latest/tutorial/context-isolation] The proposed local method/channel names below are [ASSUMED] and must remain private implementation details, never user vocabulary.

```typescript
// preload bundle; proposed private names are [ASSUMED]
contextBridge.exposeInMainWorld("keepling", {
  capture: async (unknownInput: unknown) => {
    const request = CaptureRequest.parse(unknownInput);
    const unknownResponse = await ipcRenderer.invoke("desktop:capture", request);
    return LocalAcceptance.parse(unknownResponse);
  },
  subscribe: (listener: (update: unknown) => void) => {
    const handler = (_event: Electron.IpcRendererEvent, payload: unknown) =>
      listener(PresentationUpdate.parse(payload));
    ipcRenderer.on("desktop:presentation", handler);
    return () => ipcRenderer.removeListener("desktop:presentation", handler);
  },
});
```

Main handlers must independently validate the sender and parse the request again; preload validation is defense in depth, not authority. [CITED: https://www.electronjs.org/docs/latest/tutorial/security]

### Subscribe before snapshot and recover sequence gaps

The ordering and gap behavior are locked by D-29. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:57-67`]

```typescript
// Proposed facade names are [ASSUMED].
const unsubscribe = facade.subscribe((update) => {
  if (update.sequence !== currentSequence + 1) {
    void facade.getWorkspaceSnapshot().then(replaceSnapshot);
    return;
  }
  applyUpdate(update);
});

const initial = await facade.getWorkspaceSnapshot();
replaceSnapshot(initial);
```

### Contract-derived detail validation

The canonical detail limits are quoted verbatim: title `512`, notes `50_000`, fields `:title` and `:notes`; the domain errors are `:title_required` and `:title_too_long`. [VERIFIED: `apps/server/lib/keepling/domain/task.ex:9-12,55-63`] The released OpenAPI shape is closed and uses title min `1`/max `512`, notes max `50000`. [VERIFIED: `packages/contracts/openapi/keepling.yaml:2958-2968`]

```typescript
// Local validation mirrors released bounds for immediate feedback;
// server/domain remains authoritative.
const TaskDetailValues = z.strictObject({
  title: z.string().min(1).max(512).optional(),
  notes: z.string().max(50_000).optional(),
});
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Electron renderer with Node integration or broad preload globals | Sandboxed renderer, context isolation, no Node integration, narrow context bridge, sender validation, CSP/navigation/window/permission controls | Context isolation default since Electron 12; sandbox default since Electron 20 | Treat defaults as explicit audited configuration and test packaged effective values. [CITED: https://www.electronjs.org/docs/latest/tutorial/security] |
| External SQLite native addon as automatic default | Spike Electron 44’s embedded Node 24.18.1 `node:sqlite` behind a worker/port; external addon only as fallback | Node SQLite became release candidate in Node 24.15.0 | Removes native addon ABI if it passes, but pre-stable API and synchronous behavior require exact packaged proof. [CITED: https://nodejs.org/download/release/v24.18.1/docs/api/sqlite.html] |
| Development-renderer E2E treated as desktop evidence | Separate pure/SQLite/IPC/Electron/package lanes; package lane launches the exact executable | Phase contract | Catches ASAR/resource/embedded-runtime/lifecycle faults without pushing combinatorics into expensive E2E. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:96-102`] |
| Copying a live SQLite file | Online backup API or closed whole-unit movement | SQLite backup API | Produces a coherent snapshot and avoids incomplete WAL copies. [CITED: https://www.sqlite.org/backup.html] |
| Browser and desktop sharing transport/session authority | Platform-free React presentation behind `ClientFacade`; platform adapters remain separate | Repository contract | Shares expensive UI meaning without coupling offline/lifecycle correctness. [VERIFIED: `docs/architecture/REPOSITORY.md:37-60`] |

**Deprecated/outdated for this phase:**

- Forge’s Vite plugin is not deprecated, but its official docs mark it experimental and allow minor-version breaking changes; do not make it a critical build dependency in Phase 3. [CITED: https://www.electronforge.io/config/plugins/vite]
- SQLite WASM/OPFS is explicitly rejected for the main-owned native store. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:68-76`]
- Frameless/custom titlebars, generic multi-window task workflows, browser offline persistence, notifications, signing/notarization, auto-update, launch-at-login, and application-layer DB encryption are out of scope. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:204-216`]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Playwright plus targeted manual/OS checks is sufficient for Phase 3 accessibility/menu/global-shortcut evidence; no separate UI automation framework is required. [ASSUMED] | Standard Stack / Validation | Could require adding a macOS accessibility automation lane or a narrower human checkpoint. |
| A2 | Proposed leaf folders/files under the locked `apps/desktop` roots are an effective decomposition. [ASSUMED] | Recommended Project Structure | Planner may need different leaf boundaries to fit build/package constraints. |
| A3 | The current web presentation can be extracted incrementally without a large browser regression rewrite. [ASSUMED] | Architecture | May require smaller deliberate duplication before a stable shared package seam emerges. |

## Open Questions

1. **Does `node:sqlite` pass the exact packaged adapter gate?**
   - What we know: Electron 44 embeds Node 24.18.1; `node:sqlite` is release candidate, synchronous, and has the required prepared statement/timeout/backup primitives. [CITED: https://www.electronjs.org/blog/electron-44-0] [CITED: https://nodejs.org/download/release/v24.18.1/docs/api/sqlite.html]
   - What's unclear: packaged crash recovery, worker lifecycle, real workload latency, checkpoint behavior, and API sufficiency on Keepling fixtures. [VERIFIED: `.planning/knowledge/OPEN-QUESTIONS.md:5-16`]
   - Recommendation: resolve in the first packaged tracer; activate `better-sqlite3` only with a recorded failed gate and fresh legitimacy/native-ABI proof. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:68-76`]

2. **How much React presentation is truly platform-free?**
   - What we know: workspace, capture, lifecycle, conflict, and recovery assets are reusable foundations, while browser submission/session authority is not. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:161-186`]
   - What's unclear: the smallest extraction that does not destabilize Phase 1 web behavior. [ASSUMED]
   - Recommendation: extract facade types and one capture/list/detail vertical slice first; duplicate a small adapter-specific wrapper when sharing would leak platform assumptions. [VERIFIED: `docs/architecture/REPOSITORY.md:48-60`]

3. **What is the final evidence for “daily-use ready”?**
   - What we know: the roadmap requires Jon to use the supported Mac loop without opening Things for those actions. [VERIFIED: `.planning/ROADMAP.md:164-176`]
   - What's unclear: duration and defect threshold are not locked for Phase 3. [ASSUMED]
   - Recommendation: plan a bounded dogfood acceptance checklist and evidence log after automated gates; do not convert subjective polish into a claim of data safety. [VERIFIED: `AGENTS.md:90-102`]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| macOS | Packaged Mac artifact and native behavior | ✓ | 26.6.2 arm64 | None; phase target is macOS. [VERIFIED: local `sw_vers`/`uname` probe 2026-09-02] |
| Node.js | pnpm/build/test tooling | ✓ | 22.14.0 | Electron carries its own Node 24.18.1 at runtime. [VERIFIED: local probe] [CITED: https://www.electronjs.org/docs/latest/tutorial/tutorial-prerequisites] |
| pnpm | Workspace installation/scripts | ✓ | 10.33.0 | None; root manifest pins `"packageManager": "pnpm@10.33.0"`. [VERIFIED: `package.json:1-4`] |
| Xcode command-line tools | macOS packaging/tool inspection | ✓ | Xcode 26.6 | Signing/notarization is deferred. [VERIFIED: local `xcodebuild -version` probe] |
| `codesign` | Inspect packaged signing posture | ✓ | system `/usr/bin/codesign` | Phase 3 may remain unsigned and must state limitations. [VERIFIED: local command probe] |
| SQLite CLI | Fixture inspection/debug only | ✓ | 3.51.0 | Tests must use the embedded runtime adapter, not assume CLI equivalence. [VERIFIED: local `sqlite3 --version` probe] |
| Docker | Real Phoenix/PostgreSQL sync E2E | ✓ | 29.5.2 | Existing local-stack scripts. [VERIFIED: local `docker --version` probe] |
| Elixir/Mix | Existing server/contract verification | ✓ | local asdf provides Elixir 1.20.2/OTP 29 and 1.19.5/OTP 28 | Use project-pinned tool version during execution. [VERIFIED: local `mix --version` probe] |

**Missing dependencies with no fallback:** none discovered. [VERIFIED: local environment probes]

**Missing dependencies with fallback:** Electron/Forge/Zod are intentionally not installed yet; Wave 0 installs exact human-verified pins. [VERIFIED: current manifests and package audit]

## Validation Architecture

Nyquist validation is enabled: `.planning/config.json` contains `"nyquist_validation": true`. [VERIFIED: `.planning/config.json`]

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Vitest `4.1.11` for pure/component/worker/IPC contract tests; Playwright `1.62.1` for Electron E2E and packaged executable tests; real SQLite for adapter/migration/fault fixtures. [VERIFIED: `apps/web/package.json:26-49`] |
| Config file | Desktop configs do not exist yet — Wave 0 creates desktop Vitest and Playwright configs without mutating the existing web configs. [VERIFIED: repository file scan 2026-09-02] |
| Quick run command | `pnpm test:desktop` (locked desired command; Wave 0 implementation required). [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:96-102`] |
| Full suite command | `pnpm test:desktop && pnpm test:desktop:ipc && pnpm test:desktop:e2e && pnpm smoke:desktop:packaged` (locked command vocabulary; Wave 0 implementation required). [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:96-102`] |

### Test Layer Responsibilities

| Layer | Owns | Must not be the only proof for |
|-------|------|--------------------------------|
| Pure Vitest | Desktop reducer, presentation projection, scheduler/backoff, namespace state, mappers, Phase 2 vectors, focus-by-identity decisions | SQLite durability or Electron process boundaries. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:96-102`] |
| Real SQLite worker tests | Transactions, exact settlement, migration checksums/lineages, WAL, busy/disk/read-only/corruption faults, backup/removal | Packaged resource/ABI/path behavior. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:68-82,96-102`] |
| Hostile IPC tests | Both-side schema validation, sender rejection, unknown field/operation rejection, clone-safe responses, sequence-gap snapshot recovery | Native menu/global shortcut and installed lifecycle. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:57-67,96-102`] |
| Electron E2E | Windows, menus, keyboard/IME guards, offline/relaunch/conflict/auth, renderer crash, resident close/Dock recreation | Exact installed artifact unless launched by digest-bound executable path. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:83-102`] |
| Packaged smoke | Embedded versions, `app.isPackaged`, resources/custom protocol/CSP/sandbox, worker/SQLite loading, offline commit, hard kill/relaunch, exact reconnect, digest | Full combinatorial UI/state matrix. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:96-102`] |
| Physical Mac accessibility/dogfood | VoiceOver, Full Keyboard Access, non-US layouts/dead keys, global shortcut collision, appearance/contrast/motion, prior-app focus return | Deterministic data-safety semantics already covered below. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:83-102`] |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| MAC-01 | Capture, Inbox/Today, edit, complete/reopen, trash/restore, undo all invoke the durable semantic facade | component + SQLite integration + Electron E2E | `pnpm test:desktop -- daily-loop && pnpm test:desktop:e2e -- daily-loop` [ASSUMED command filter] | ❌ Wave 0 |
| MAC-02 | Complete keyboard navigation, menu validation, Quick Entry, IME/repeat/editable guards, stable focus restoration | component + Electron E2E + physical Mac acceptance | `pnpm test:desktop:e2e -- keyboard-quick-entry` [ASSUMED command filter] | ❌ Wave 0 |
| MAC-03 | Offline atomic accept, hard kill/relaunch, exact retry/ack, no loss/duplication | real SQLite + sync vectors + packaged hard-kill | `pnpm test:desktop -- offline-relaunch && pnpm smoke:desktop:packaged -- offline-relaunch` [ASSUMED command filter] | ❌ Wave 0 |
| MAC-04 | Closed offline/updating/retry/rejection/conflict/auth/namespace/store-failure states and safe actions | reducer + component + Electron E2E | `pnpm test:desktop -- recovery-presentation && pnpm test:desktop:e2e -- sync-recovery` [ASSUMED command filter] | ❌ Wave 0 |
| MAC-05 | Built `.app` preserves/migrates/syncs local store outside source with no dev server | packaged artifact | `pnpm smoke:desktop:packaged` | ❌ Wave 0 |
| QUAL-03 | Exact tested revision/artifact digest is promoted without rebuild | package/evidence script | `pnpm package:desktop && pnpm smoke:desktop:packaged` | ❌ Wave 0 |
| QUAL-04 | Important screens cover populated/empty/loading/offline/denied/stale/conflict/partial/retry/unrecoverable | component scenario matrix + Electron representative flows | `pnpm test:desktop -- state-matrix && pnpm test:desktop:e2e -- representative-states` [ASSUMED command filter] | ❌ Wave 0 |
| SRV-02 | Electron adapter reaches same server semantic invariants and exact contracts | generated contract drift + real Phoenix/PostgreSQL adapter E2E | `pnpm contracts:check && pnpm test:desktop:e2e -- real-stack` [ASSUMED command filter] | Partial: contracts/server exist; desktop proof ❌ |

### Sampling Rate

- **Per task commit:** `pnpm typecheck:desktop && pnpm test:desktop` once Wave 0 exists. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:96-102`]
- **Per wave merge:** add `pnpm test:desktop:ipc && pnpm test:desktop:e2e`; any store/runtime/package dependency change also runs the packaged smoke. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:96-102`]
- **Phase gate:** full desktop suite, exact packaged artifact lane, privacy/security assertions, physical Mac accessibility checklist, and bounded dogfood acceptance before `$gsd-verify-work`. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:83-102`]

### Wave 0 Gaps

- [ ] Desktop package/build/config with locked commands: `dev:desktop`, `typecheck:desktop`, `test:desktop`, `test:desktop:ipc`, `test:desktop:e2e`, `package:desktop`, `smoke:desktop:packaged`. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:96-102`]
- [ ] Pure test harness consuming `packages/contracts/vectors/sync.json` and schema, with cross-runtime equality to the existing reference model. [VERIFIED: `packages/contracts/schemas/sync-state-machine.schema.json:1-110`]
- [ ] Real SQLite worker fixture factory with deterministic IDs/clock, fault controls, fresh-create and retained forward-migration lineages. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:68-82,96-102`]
- [ ] Hostile preload/main bridge fixture including invalid sender, extra fields, unknown operation, non-cloneable value, sequence gap, renderer reload/crash. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:57-67,96-102`]
- [ ] Isolated per-test Electron user-data/profile paths; never use Jon’s real Keepling data. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:96-102`]
- [ ] Package-once harness that locates the `.app` executable, hashes artifact inputs/output, copies/launches outside source, asserts `app.isPackaged`, and retains evidence. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:96-102`]
- [ ] Accessibility/state-matrix fixtures inheriting the approved `03-UI-SPEC.md` exact interaction/copy contract. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-UI-SPEC.md`]

## Security Domain

Security enforcement is enabled at ASVS level 1 in `.planning/config.json`. [VERIFIED: `.planning/config.json`] OWASP describes ASVS as a basis for testing application technical security controls; the project page identifies 5.0.0 as current stable. [CITED: https://owasp.org/www-project-application-security-verification-standard/]

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V1 Architecture / threat modeling | yes | Main-owned authority, least-privilege ports, renderer as disposable mirror, namespace threat model. [VERIFIED: `apps/desktop/README.md:1-6`] |
| V2 Authentication | yes | Existing native PKCE/device-grant transport; async credential port; no raw credentials in renderer. [VERIFIED: `packages/contracts/openapi/keepling.yaml:1656-1708`] |
| V3 Session Management | yes | Server-derived installation grant namespace, rotation/revocation, auth fence retaining local intent. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:48-67`] |
| V4 Access Control | yes | Server remains authorization authority; renderer gets only named semantic operations; IPC sender validation. [CITED: https://www.electronjs.org/docs/latest/tutorial/security] |
| V5 Validation / encoding | yes | Zod parse on both preload/main sides; generated closed DTOs; prepared SQL; plain-text task rendering; restrictive CSP. [CITED: https://zod.dev/] [CITED: https://www.electronjs.org/docs/latest/tutorial/security] |
| V6 Stored Cryptography | yes, credentials only | Electron `safeStorage` behind replaceable port; no custom crypto; explicitly no encrypted task DB or cryptographic-erasure claim. [CITED: https://www.electronjs.org/docs/latest/api/safe-storage] [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:48-56,204-216`] |
| V7 Error/Logging and V8 Data Protection | yes | Closed low-cardinality codes/counts/coarse timings; deny task text, drafts, commands, credentials, tokens, cursors, fingerprints, raw IDs/URLs/paths/titles. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:83-102`] |
| V9 Communication / V13 API | yes | HTTPS/bearer generated transport, compatibility negotiation, exact command identity and ordered feed; no arbitrary renderer fetch. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:57-67`] |
| V12 Files/Resources / V14 Configuration | yes | Namespace-scoped application data, safe removal order, custom packaged protocol, CSP, sandbox/fuses/config assertions, no dev server in artifact. [CITED: https://www.electronjs.org/docs/latest/tutorial/security] |

### Known Threat Patterns for Electron + SQLite

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Compromised renderer invokes privileged APIs | Elevation of privilege | sandbox + context isolation + no Node integration + one-method bridge + sender/request/response validation. [CITED: https://www.electronjs.org/docs/latest/tutorial/security] |
| Navigation/window escape loads attacker content | Spoofing / elevation | packaged local content/custom protocol, restrictive CSP, deny unexpected navigation/window creation, deny permissions, allowlist external URLs. [CITED: https://www.electronjs.org/docs/latest/tutorial/security] |
| SQL injection or malformed IPC reaches persistence | Tampering | strict runtime schemas, prepared statements/bound values, bounded sizes, no SQL/DB handles in renderer. [CITED: https://nodejs.org/download/release/v24.18.1/docs/api/sqlite.html] |
| Ack spoof/mismatch removes intent | Tampering / repudiation | exact mutation ID + timing-safe fingerprint match inside atomic settlement; unknown/mismatch leaves state unchanged. [VERIFIED: `apps/server/lib/keepling/application/sync/reference_model.ex:96-169`] |
| Account/server switch drains prior work | Information disclosure / tampering | five-part namespace fence, fence before revocation, independent stores, inspect/export/separately confirmed removal. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:48-56`] |
| Live DB copy/removal loses WAL state | Tampering / denial of service | online backup API or close connection before whole-unit move/removal; verify absence; never auto-reset. [CITED: https://www.sqlite.org/wal.html] [CITED: https://www.sqlite.org/backup.html] |
| Resource exhaustion via unbounded values/retries/feed | Denial of service | closed schema bounds, Node SQLite limits/finite timeout, capped pages/pushes/backoff, bounded counts, one writer. [CITED: https://nodejs.org/download/release/v24.18.1/docs/api/sqlite.html] [VERIFIED: `apps/server/lib/keepling/application/sync/reference_model.ex:11-14`] |
| Sensitive diagnostics/window metadata | Information disclosure | allowlisted diagnostics and coarse titles/destinations only; automated negative privacy tests. [VERIFIED: `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md:83-102`] |
| Unsigned credential-store identity changes | Spoofing / availability | state the limitation; do not claim update-stable Keychain behavior until signed/notarized evidence. Electron says macOS apps should be code signed for consistent `safeStorage`. [CITED: https://www.electronjs.org/docs/latest/api/safe-storage] |

## Sources

### Primary (HIGH confidence project-local)

- `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md` — locked Phase 3 product, process, storage, UI, security, test and package decisions.
- `.planning/phases/KPL-03-mac-daily-loop/03-UI-SPEC.md` — approved Mac visual, interaction, copy, accessibility and state contract.
- `.planning/REQUIREMENTS.md` and `.planning/ROADMAP.md` — requirement wording, phase goal and success criteria.
- `docs/architecture/REPOSITORY.md` and `AGENTS.md` — repository dependency/boundary/enforcement rules.
- `packages/contracts/schemas/sync-state-machine.schema.json`, `packages/contracts/vectors/sync.json`, `apps/server/lib/keepling/application/sync/reference_model.ex` — exact cross-runtime sync vocabulary and behavior.
- `packages/contracts/openapi/keepling.yaml`, `apps/server/lib/keepling/domain/task.ex` — released transport and domain bounds.

### Official documentation (MEDIUM confidence via verified web search)

- https://www.electronjs.org/docs/latest/tutorial/security — Electron security checklist, sender/navigation/window/permission/CSP controls.
- https://www.electronjs.org/docs/latest/tutorial/context-isolation — narrow context bridge and TypeScript pattern.
- https://www.electronjs.org/docs/latest/tutorial/sandbox — renderer sandbox model.
- https://www.electronjs.org/docs/latest/api/app — single-instance and lifecycle events.
- https://www.electronjs.org/docs/latest/api/global-shortcut and https://www.electronjs.org/docs/latest/tutorial/keyboard-shortcuts — registration and macOS layout caveat.
- https://www.electronjs.org/docs/latest/api/safe-storage — credential storage and macOS signing limitation.
- https://www.electronjs.org/docs/latest/tutorial/application-distribution and https://www.electronforge.io/config/makers/zip — Forge packaging and ZIP artifact.
- https://www.electronjs.org/docs/latest/tutorial/automated-testing and https://playwright.dev/docs/api/class-electron — Electron test layers and packaged executable launch support.
- https://www.electronjs.org/blog/electron-44-0 and https://releases.electronjs.org/release/v44.0.0 — embedded Chromium/Node/V8 and macOS floor.
- https://nodejs.org/download/release/v24.18.1/docs/api/sqlite.html — exact embedded Node SQLite stability and API surface.
- https://www.sqlite.org/lang_transaction.html, https://www.sqlite.org/wal.html, https://www.sqlite.org/stricttables.html, https://www.sqlite.org/backup.html — transaction, WAL, strict typing and backup semantics.
- https://zod.dev/ — runtime schema parsing and version requirements.
- https://owasp.org/www-project-application-security-verification-standard/ — current ASVS basis/version.

### Registry and seam evidence

- npm registry queries on 2026-09-02 for current versions, creation/modified dates, repositories, and `scripts.postinstall` observations.
- GSD `package-legitimacy check` on 2026-09-02 for Electron, Forge CLI/ZIP maker, Zod, and better-sqlite3.
- GSD research-plan/cache and classify-confidence seams; websearch-verified official docs classify MEDIUM.

### Tertiary (LOW confidence)

- No community-only technical claims are used as planning authority. Assumptions are isolated in the Assumptions Log.

## Metadata

**Confidence breakdown:**

- Standard stack: **MEDIUM** — official docs and current registry were checked, but Electron 44.1.1 and Zod 4.5.4 are newly published and require human verification; final SQLite adapter awaits the packaged spike.
- Architecture: **HIGH** — process, storage, sync, UI, recovery and repository responsibilities are locked in project artifacts and backed by implemented Phase 2 contracts/reference code.
- Pitfalls: **HIGH/MEDIUM** — project-specific failure modes are locked; Electron/Node/SQLite mechanics are from current official documentation, while a few test-tool coverage limits remain assumed.
- Validation: **HIGH** for required layers/behaviors, **MEDIUM** for exact proposed desktop test filenames/filters because Wave 0 does not exist.
- Security: **HIGH** for required boundary controls and project privacy constraints, **MEDIUM** for final packaged fuse/protocol details until the runtime spike freezes them.

**Research date:** 2026-09-02

**Valid until:** 2026-09-09 for Electron/Node/package versions; 2026-10-02 for stable project/SQLite architecture. Re-run registry, legitimacy, embedded-version, Electron security and packaged lanes on any runtime/storage dependency bump.
