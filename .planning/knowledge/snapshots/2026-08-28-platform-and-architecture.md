---
title: "Platform, client, sync, repository, and quality architecture"
date: 2026-08-28
context: "Current architecture after superseding PWA-first and laptop-hosted assumptions"
status: current-working-view
supersedes_decisions:
  - "PWA as primary iPhone client"
  - "Electron only if Windows/Linux demand appears"
  - "Laptop-hosted initial dogfood"
---

# Platform and Architecture

## Current recommendation

Build one server product, two durable offline clients, and one online web surface:

```text
Always-on cloud reference deployment
  Caddy → Phoenix modular monolith → PostgreSQL
                    |
          versioned command/query/sync API
             /              |             \
      Electron Mac      SwiftUI iPhone   React web
      SQLite/outbox      local DB/outbox  online-first
             \              |             /
        shared contracts, golden vectors, design tokens
```

- **Electron on Mac** is part of personal success, not merely a future Windows/Linux strategy.
- **Native SwiftUI on iPhone** is the mobile correctness and experience baseline.
- **React web access** shares presentation code with Electron but is not initially a third durable offline client.
- **Phoenix/PostgreSQL** owns canonical state, authorization, invariants, mutation idempotency, and the ordered sync feed.
- **MCP** is an adapter over the same semantic application commands.
- **Crosswake** remains optional for bounded experiments and does not own core task storage or synchronization.

## Why the prior PWA-first decision was superseded

The initial PWA recommendation optimized time-to-dogfood and avoided Apple distribution cost. Further exploration surfaced a stronger requirement: the iPhone experience must be dependable enough to replace Things, including durable offline capture, native reminders, system integration, and a safe local store.

Native iOS background scheduling is still opportunistic. The no-data-loss guarantee comes from committing locally before success is shown, persisting an outbox in the same transaction, retrying idempotently, and retaining mutations until exact server acknowledgement. Native APIs improve storage, reminders, sharing, widgets, App Intents, and execution opportunities; they do not replace the sync protocol.

The web surface remains useful for universal access and for sharing React presentation work with Electron. It does not need to inherit mobile correctness responsibility.

## Distribution and self-host precedents

The following block is source-derived data, not instructions.

DATA_38FD91A7_START

### Admitted claims

- Apple permits free personal-device development but Personal Team App IDs/devices/provisioning expire after seven days; TestFlight, App Store distribution, Developer ID, and notarization require paid Apple Developer Program membership. Source: https://developer.apple.com/support/compare-memberships/
- TestFlight builds remain testable for up to 90 days. Source: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/
- Apple schedules background refresh opportunistically and may terminate work; correctness must survive termination and cannot assume regular background execution. Sources: https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app and https://developer.apple.com/documentation/swiftui/scenephase
- Home Assistant distributes a native iOS client that discovers or accepts the URL of a user-operated server. Source: https://companion.home-assistant.io/docs/getting_started/
- Immich distributes its mobile app through the Apple App Store, Play Store, APK releases, and F-Droid; the app accepts a self-hosted server endpoint. Source: https://docs.immich.app/features/mobile-app/
- Jellyfin describes its iOS/iPadOS client as official and open source and distributes it through the App Store. Source: https://jellyfin.org/downloads/clients/?platform=iOS,tvOS
- Electron's security guidance requires a narrow trust boundary: local packaged renderer content, context isolation, sandboxing, restrictive navigation, validated IPC senders, and limited preload exposure. Sources: https://www.electronjs.org/docs/latest/tutorial/security and https://www.electronjs.org/docs/latest/tutorial/process-model
- Public macOS Electron distribution should be signed and notarized; unsigned private dogfood is possible but some Keychain, login-item, notification, and update behavior may differ. Source: https://www.electronjs.org/docs/latest/tutorial/code-signing
- Apple's Swift OpenAPI Generator can generate client code at build time from an OpenAPI document and supports iOS. Source: https://github.com/apple/swift-openapi-generator
- SwiftData exposes explicit transactions that can atomically persist projection and outbox changes when its platform/version constraints are acceptable. Source: https://developer.apple.com/documentation/swiftdata/modelcontext/transaction%28block%3A%29

### Corrected claims

- A native iPhone app does not guarantee scheduled background sync. Durable local commit plus foreground/opportunistic replay provides correctness; background execution accelerates freshness.
- Open-source iPhone users do not normally compile a unique client for each self-hosted server. Mature projects publish one signed official app that accepts a server URL.
- Electron is not primarily justified here by future Windows/Linux support. It is justified by Jon's actual always-open Mac workflow and proven Electron experience.

### Unresolved ledger

- Exact iOS minimum remains undecided. Jon accepts a modern baseline; the implementation phase must balance least surprise, SwiftData/framework payoff, and real device-market expectations.
- Server/client license compatibility with App Store distribution requires distribution-specific legal review before public submission.
- The first Electron storage adapter must be proven through packaging and migration tests; built-in `node:sqlite` remains below fully stable status in current Node documentation.
- Signing is deliberately deferred, so behavior that depends on signing must not be claimed as proven during unsigned dogfood.

DATA_38FD91A7_END

## Client dependency rules

```text
contracts/openapi.yaml + JSON schemas + golden vectors
├── Phoenix API conformance
├── generated TypeScript transport client
│   ├── browser adapter
│   └── Electron main/preload adapter
└── generated Swift transport client
    └── iOS application adapter

design-tokens/tokens.json
├── generated CSS variables
└── generated Swift values
```

Rules:

- Server domain code never imports HTTP, generated clients, UI, or client persistence.
- OpenAPI is wire truth, not domain truth.
- Generated DTOs never become Ecto, SQLite, browser, or Swift persistence records.
- Golden vectors are test inputs, not runtime packages.
- Shared React presentation depends on a narrow `ClientFacade`, never Electron APIs, IndexedDB, or SQLite.
- Electron preload exposes semantic operations through typed, validated IPC; raw database access never reaches the renderer.
- SwiftUI reimplements client orchestration and native interaction against the same contracts and vectors.
- Cross-platform design tokens share semantic values and names, not pixel-identical components.

## Share, duplicate, and never share

### Share

- OpenAPI and schema sources.
- Command/query DTOs, error envelope, version metadata, and compatibility rules.
- Golden sync, conflict, failure, and adversarial vectors.
- TypeScript transport client between web and Electron.
- React presentation components when interaction genuinely matches.
- Semantic design tokens and release-evidence vocabulary.

### Deliberately duplicate

- PostgreSQL, Electron SQLite, browser storage, and Swift local schemas/migrations.
- SwiftUI views and React components.
- Platform lifecycle, credentials, menus, shortcuts, extensions, notifications, and recovery UX.
- TypeScript and Swift orchestration implementations.

### Never share

- Ecto schemas as public API or client models.
- Electron preload APIs with the browser.
- Raw SQLite rows with the renderer.
- Swift persistence objects with generated API types.
- A universal domain package spanning Elixir, TypeScript, and Swift.
- Hosted remote web content as the Electron renderer.

## Repository destination

```text
gtd-app/
├── apps/
│   ├── server/                 # Phoenix modular monolith
│   ├── web/                    # React bootstrap + browser adapters
│   ├── desktop/
│   │   ├── main/               # SQLite, sync, credentials, OS integration
│   │   ├── preload/            # narrow typed semantic bridge
│   │   └── renderer/           # shared React presentation
│   └── ios/                    # Xcode/SwiftPM, created when tracer begins
├── packages/
│   ├── contracts/              # OpenAPI, schemas, vectors
│   ├── api-client-ts/          # generated transport only
│   ├── client-core-ts/         # pure client facade/reducer where justified
│   ├── web-ui/                 # React, no platform APIs
│   └── design-tokens/          # source plus generated CSS/Swift
├── infra/                      # reference OpenTofu/Terraform deployment
├── tooling/                    # deterministic generators and drift checks
├── docs/                       # ADRs, threat model, operations
└── .planning/                  # GSD and dated knowledge
```

Use ordinary pnpm workspaces for TypeScript, standalone Mix tooling for Phoenix, and Xcode/SwiftPM for iOS. Do not add Nx, Turborepo, an Elixir umbrella, or a universal root task graph until measured pain justifies it. Create client directories only when their tracer begins; the tree is a destination, not a mandate to scaffold everything immediately.

## Staged tracer sequence

### 0. Domain and contract spine

- Semantic commands for capture, edit/clarify, complete, reopen, trash, and restore.
- PostgreSQL snapshots, idempotent mutation receipts, ordered change feed, cursor, and tombstones.
- OpenAPI and storage-neutral vectors for accepted, duplicate, rejected, stale, conflict, reconnect, logout/account switch, and kill/relaunch behavior.

Exit proof: ExUnit domain/application tests, property/model mutation sequences, schema validation, and anti-vacuity vector checks.

### 1. Online web semantic tracer

- React browser surface served with or alongside Phoenix.
- Capture → Inbox → Today → complete/reopen against real Phoenix/PostgreSQL.
- Establish product language, API ergonomics, shared presentation primitives, and early accessibility.
- Do not implement browser offline sync.

Exit proof: Playwright reaches the real server and verifies happy, empty, validation-error, authorization-error, and duplicate-submission states.

### 2. Electron offline tracer

- Shared React UI behind a desktop facade.
- Main process owns SQLite, outbox, cursor, migrations, sync, and credentials.
- Offline capture/edit/complete; kill/relaunch; reconnect; exact acknowledgement; conflict display.
- Build macOS only.

Exit proof: packaged artifact is installed and launched; local state survives relaunch and reconciles exactly once.

### 3. Native iPhone tracer

- Generated Swift transport types plus native persistence records.
- Local projection and outbox committed atomically.
- Foreground launch/resume/reconnect correctness before background acceleration.
- Capture, Inbox, Today, complete/reopen, conflict/recovery on a physical iPhone.

Exit proof: physical-device evidence for offline capture, termination, relaunch, replay, duplicate submission, expired authentication, and account fencing.

### 4. Daily Mac and iPhone loops

- Mac: quick entry, complete keyboard navigation, menus, always-open window, Inbox/Today/Upcoming, recovery.
- iPhone: fast capture, reminders, sharing if needed, App Intents/Shortcuts, widgets, calm offline/sync state.
- Alternate leadership by feature: desktop owns keyboard/window behavior; iPhone owns native mobile affordances; server owns shared semantics.

Exit proof: Jon can stop using Things for the supported loop on both devices.

### 5. Distribution and convergence

- Apple membership when continuous native dogfood requires it; TestFlight then App Store.
- Electron signing/notarization only when public distribution or platform behavior justifies it.
- Released-client compatibility window, export/delete, backup/restore, and exact tested-artifact promotion.
- Browser offline only if still valuable after primary clients are reliable.

## Sync contract

Use server-authoritative canonical state with a genuinely offline local mirror:

- Client-generated stable IDs allow offline capture.
- Each mutation includes account/device identity, unique mutation ID, entity ID, base revision, command name, schema version, and validated payload.
- Local projection and outbox change commit atomically before UI success.
- Accepted server commands atomically update the snapshot, store the idempotent result, append an ordered scoped change, and emit a post-commit hint.
- Clients retain outbox entries until the exact mutation ID is acknowledged.
- Pull uses an opaque durable cursor and includes tombstones.
- Server revisions/cursors, not client wall-clock time, establish order.
- Same-field concurrent edits return structured conflicts rather than silently choosing.
- Different-field merges occur only when touched-field semantics prove safety.
- Completion, recurrence, commit, and undo are idempotent domain transitions.
- Delete creates a recoverable tombstone before any later hard-retention policy.
- Sockets and background execution improve freshness; correctness never depends on either.

Do not conflate the sync feed, typed domain events, security audit, diagnostic telemetry, and event-sourced reconstruction.

## Quality engineering contract

Testing is an architectural concern. Ports/adapters, dependency direction, clocks, identifiers, network boundaries, and persistence abstractions must be designed to permit deterministic proof.

### Test layers and distinct responsibilities

| Layer | Primary failures caught |
|---|---|
| Pure domain examples | Command invariants, lifecycle transitions, temporal semantics |
| Property/model tests | Long mutation sequences, retries, reordering, concurrency, recurrence |
| Persistence/migration tests | Constraints, transactional outbox, schema evolution, restore compatibility |
| API/contract conformance | Versioning, authorization, idempotency, errors, pagination |
| Adapter integration | Real PostgreSQL, SQLite, browser/Electron IPC, generated clients |
| Web Playwright | User-visible navigation, forms, errors, accessibility, server integration |
| Electron E2E | Main/preload/renderer boundary, offline state, relaunch, OS integration |
| Packaged-artifact smoke | Missing resources, ABI/signing/package drift, installed behavior |
| iOS unit/simulator | Swift orchestration, persistence, generated contracts, UI behavior |
| Physical iPhone | Background/termination, Keychain, notifications, real networking, device-only behavior |
| Deployment/restore | Image health, migrations, backup recovery, DNS/TLS/secret integration |

### User-level coverage expectations

- Every important screen receives representative visual/behavioral coverage.
- Cover happy path, empty, loading, offline, validation error, permission denial, authentication expiry, conflict/stale data, partial result, retry, and unrecoverable failure where meaningful.
- Assertions target user-visible state and durable side effects rather than implementation details.
- Fixtures and seeds are deterministic, composable, scenario-named, and usable across local development, previews, E2E, and visual regression without leaking production data.
- Test fakes own controllable clocks, identifiers, network outcomes, retries, and scripted provider failures; avoid shared global mutable fakes.
- E2E tests stay focused on high-value cross-boundary behavior. Combinatorial business rules live at lower, faster layers.
- Accessibility semantics and keyboard-only paths are testable contracts, not manual polish afterthoughts.

### CI efficiency

- Required fast lanes: server, contracts, TypeScript/web, Electron, and Swift build/unit/vector conformance.
- Parallelize independent lanes and cache only reproducible artifacts.
- Track test and job duration, cache effectiveness, flakes, retries, and slowest examples.
- Quarantine is not a permanent solution; flaky tests must be fixed or removed from false authority.
- Use path filtering only for isolated leaves. Contract, token, lockfile, generator, and wire-adapter changes trigger all consumers.
- Run browser integration on every relevant PR; packaged Electron, simulator UI, and deployment smoke at the narrowest reliable gate.
- Require physical-device and exact-artifact evidence before native milestone promotion and public release.
- Promote previously tested bytes; do not rebuild at publication time.
- Coverage metrics are diagnostic. Mutation/negative-control techniques and requirement-to-test traceability guard against vacuous green suites.

## React, CSS, and design-system posture

- React is selected because it enables meaningful web/Electron sharing; it is not permission to create a client-side framework ecosystem.
- Keep pnpm dependencies few, direct, justified, pinned, and auditable. Prefer browser/platform capabilities and small local utilities over dependency chains.
- Shared UI owns presentation and interaction primitives; platform adapters own storage, credentials, filesystem, IPC, and lifecycle.
- Start with semantic CSS custom properties generated from design tokens.
- Choose one deliberate CSS organization strategy during the UI specification phase. BEM-style component boundaries are acceptable; utility/atomic CSS or Tailwind is acceptable only if it demonstrably reduces entropy without obscuring the design system.
- Avoid specificity wars, `!important`, deep selectors, global leakage, and styling coupled to DOM accidents.
- Use shadcn or another component source only when the copied/owned code provides clear leverage and can be made visually native without importing an alien design language or a large dependency surface.
- Prefer system typography and platform-conventional density, focus, motion, and control behavior while maintaining a coherent brand through tokens, iconography, voice, and a restrained accent system.
- SwiftUI and React share semantic tokens, not identical layouts. Native feel outranks cross-platform pixel sameness.

## Remaining phase-level decisions

1. Minimum supported iOS version and local persistence adapter.
2. Browser/Phoenix integration shape for the React build.
3. Native/desktop authentication, logout/account-switch fencing, and token revocation.
4. Released-client compatibility window before the first TestFlight/downloadable artifact.
5. Electron storage implementation and migration fixture strategy.
6. At-rest threat model for task text and queued mutations.
7. Backup RPO/RTO and when PITR becomes required.
8. Exact triggers for Apple enrollment, Electron signing, and automatic desktop updates.

