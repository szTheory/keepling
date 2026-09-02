# Phase 3: Mac Daily Loop - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-02
**Phase:** 3-Mac Daily Loop
**Areas discussed:** window and workspace behavior, capture and keyboard workflow, offline and synchronization trust, lifecycle and local protection, desktop architecture and developer ergonomics, SQLite and packaged local store, cross-area UI/UX coherence

---

## Window and Workspace Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Adaptive three-region workspace | One primary window with sidebar, task list, detail, canonical routes, adaptive collapse, and stable restoration | ✓ |
| List-first overlay editor | Calmer list emphasis but weaker simultaneous context and more dismissal/focus ambiguity | |
| General multi-window | Strong review/multitasking power with much larger lifecycle, privacy, and consistency surface | |
| Primary plus auxiliary windows | Bounded future compromise after the single-window contract is proven | |

**User's choice:** The user selected all areas for expert research and delegated the final coherent recommendation.
**Notes:** Prefer familiar Mac spatial behavior without importing configuration-heavy perspectives or exposing task content in window chrome.

---

## Capture and Keyboard Workflow

| Option | Description | Selected |
|--------|-------------|----------|
| Focused-app capture only | Lowest integration but fails interruption-free capture from another app | |
| Global Quick Entry only | Fast capture but weak discoverability and disconnected in-window behavior | |
| One command, two presentations | In-app and global Quick Entry share one semantic local transaction and menu contract | ✓ |
| Cross-app Autofill helper | Powerful context capture with privacy, permissions, signing, and compatibility cost | |

**User's choice:** Delegated to the evidence-backed recommendation.
**Notes:** Native menus are the discoverability authority. Standard text shortcuts remain standard; global shortcut collision and non-US layouts are explicit states/tests.

---

## Offline and Synchronization Trust

| Option | Description | Selected |
|--------|-------------|----------|
| Quiet global status only | Calm but cannot locate partial/actionable failures honestly | |
| Per-item state everywhere | Precise but noisy, unstable, and accessibility-hostile | |
| Sync activity center | Inspectable but risks backend-shaped dashboard theater | |
| Hierarchical hybrid | Quiet global summary, contextual exceptions, and bounded Sync & Recovery panel | ✓ |

**User's choice:** Delegated to the evidence-backed recommendation.
**Notes:** The model must distinguish recoverable draft, local commit, and exact server acknowledgement, and must never infer global success from one lane.

---

## Lifecycle and Local Protection

| Option | Description | Selected |
|--------|-------------|----------|
| Resident single-instance app | Native close/hide/quit behavior, fast reopen, background sync, and Quick Entry while running | ✓ |
| Quit with last window | Lower residency but slower capture and weaker Mac daily-companion behavior | |
| Separate helper/service | More isolation and launch-at-login potential with split-brain, signing, install, and upgrade complexity | |

**User's choice:** Delegated to the evidence-backed recommendation.
**Notes:** Close and quit are different; quit never waits for the network. Sign out, local removal, and server deletion are separate actions.

---

## Desktop Architecture and Developer Ergonomics

| Option | Description | Selected |
|--------|-------------|----------|
| Thin online Electron wrapper | Maximum web reuse but cannot meet local atomicity/relaunch requirements | |
| Renderer-owned state with generic IPC | Convenient early code but moves authority into the least-trusted process | |
| Main-owned local-first application | Narrow semantic facade, one sync/store authority, separate representations, deterministic ports and fixtures | ✓ |

**User's choice:** Delegated to the evidence-backed recommendation.
**Notes:** Phoenix remains canonical and idiomatic through thin transport adapters plus inward application commands/contexts. The desktop consumes contracts/vectors rather than cloning Elixir domain rules.

---

## SQLite and Packaged Local Store

| Option | Description | Selected |
|--------|-------------|----------|
| `node:sqlite` in a dedicated worker | Minimal dependency/ABI surface; conditional on the exact packaged Electron runtime gate | ✓, conditional |
| `better-sqlite3` behind the same port | Mature fallback with native-addon rebuild/packaging/signing cost | fallback |
| SQLite WASM/OPFS | Avoids Node ABI but conflicts with main-owned native file/recovery semantics | |

**User's choice:** Delegated to the evidence-backed recommendation.
**Notes:** Lock the port, transaction, schema, migration, WAL, fault, and artifact gates now; select the concrete adapter only after the exact pinned runtime spike.

---

## Cross-Area UI/UX Coherence

| Option | Description | Selected |
|--------|-------------|----------|
| Quiet local-first Mac workspace | Restored main window, separate Quick Entry, durable drafts, native menus/lifecycle, sync by exception | ✓ |
| Explicit-save document model | Strong inheritance from web but prompt-heavy and network-shaped | |
| Browser-parity wrapper | Least presentation work but insufficient Mac fit and architectural separation | |

**User's choice:** Delegated a one-shot recommendation considering product, technical, security, design, accessibility, DevOps/SRE, and developer-experience lenses.
**Notes:** Coherence depends on one state-language hierarchy and one main-owned truth projection; visual calm cannot hide correctness or recovery.

## the agent's Discretion

- Exact pane resizing, default window geometry, toolbar iconography, and coarse title copy.
- Exact sync grace/backoff constants and status-control presentation.
- Runtime validator and facade grouping behind the closed semantic boundary.
- Worker versus utility-process isolation after measurement.
- Final SQLite adapter after the exact packaged spike.
- Mac density aliases and motion tuning through the Phase 3 UI specification.

## Deferred Ideas

- General multi-window workflows and detached task windows.
- Menu-bar extra, separate helper, launch at login, and capture while fully quit.
- Cross-app Autofill/helper capture.
- Signing/notarization, automatic update, and public distribution claims.
- OS notifications/reminders.
- Application-layer database encryption, biometric lock, cryptographic erasure, and remote wipe.
- Windows/Linux packaging and browser-offline persistence.
