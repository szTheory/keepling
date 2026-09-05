# Phase 4: Native iPhone Daily Loop - Research

**Researched:** 2026-09-04
**Domain:** Native SwiftUI iOS client — durable local persistence, sync-contract conformance, native touch/accessibility, Apple toolchain automation
**Confidence:** MEDIUM-HIGH (verified toolchain state on the build Mac and official-source library facts; several load-bearing SwiftUI/BackgroundTasks behaviors are only reproducible on-device or carry documented platform bugs, tagged accordingly)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

D-01 through D-49 in `04-CONTEXT.md` are locked and govern this research and the downstream plan. Highlights load-bearing for planning (full text is in `04-CONTEXT.md`, copied verbatim there — this is a pointer, not a paraphrase, to avoid drift):

- **D-01/D-02/D-05:** GRDB.swift is the committed local-store adapter behind `LocalStorePort`; SwiftData is rejected and is NOT the fallback; raw `sqlite3` via `libsqlite3.tbd` is the predeclared fallback, triggered only by G1–G6 failure or GRDB going unmaintained.
- **D-03/D-04:** Mirror Phase 3's storage invariants verbatim — nine `STRICT` tables, one `BEGIN IMMEDIATE` transaction for local acceptance, forward-only checksummed migration ledger, WAL + `synchronous=FULL` + finite busy handling, no main-thread store work. Run the adapter spike as a one-sided pass/fail acceptance gate (G1–G8), never a bake-off.
- **D-06:** iOS 26 deployment floor. Closes OQ-004.
- **D-07/D-08/D-09:** Store stays in the app container (never App Group); no SQLCipher — rely on file protection + Keychain `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; mark the durable unit `isExcludedFromBackup` AND prove replay-no-op via server mutation-identity/fingerprint checking.
- **D-10 through D-16:** Reimplement sync orchestration natively in Swift as the THIRD independent vector consumer (no shared FFI core in Phase 4). Generate the Swift wire client via `apple/swift-openapi-generator` CLI with committed output. Normalize `keepling.yaml` before generation (35 nullable-`anyOf` sites → OpenAPI 3.1 unions; add discriminators to `SyncFeedEnvelope.payload` and `ActivityChange`). Add a decode round-trip test over every vector payload. Vector conformance must be structural (set-equality of executed case names, `packages/contracts/vectors/manifest.json` cross-consumer gate), not asserted. Vector schema vocabulary extensions are one-way once Swift exists as a third consumer.
- **D-17 through D-24:** Purchase Apple Developer Program membership ($99/yr) in Phase 4. Install via development-signed `devicectl` + `xcodebuild -allowProvisioningUpdates`. Defer TestFlight to Phase 6. Two-lane evidence model: simulator lane gates every change, physical-device lane gates phase acceptance only. Bind evidence by provenance + read-back attestation (`KeeplingBuildDigest` Info.plist key), not byte reproducibility. Bind each of the five roadmap success criteria to a named lane with explicit disclosure of what is NOT proven (see D-22's per-criterion table in `04-CONTEXT.md`). On-device diagnostics carry no task content. No Phase 4 lane may depend on CI existing (no git remote; O-35).
- **D-25 through D-34:** Two-tab `TabView` (Today, Inbox) with per-tab `NavigationStack`; capture is a `.sheet`. Trailing swipe carries Complete/Reopen with full-swipe allowed; Trash never gets a swipe, only long-press context menu/detail. Every gesture is mirrored as a named control and `.accessibilityActions` entry. No pull-to-refresh, no drag-to-reorder. Use `tabViewBottomAccessory` (iOS 26) as the status/action strip with `.tabBarMinimizeBehavior(.onScrollDown)`. Semantic undo is a named, persistent, non-timered "Undo {Action}" control in the accessory, mirrored in the overflow menu; `applicationSupportsShakeToEdit = false`; `UndoManager` only for text-field editing; undo of an already-accepted mutation is a compensating semantic action, never a local retraction.
- **D-35 through D-37:** In-app capture sheet with durable draft; App Intents for Capture and Complete declared in the MAIN app target (not an extension), unit-tested via `perform()`/`resolveAndPerform()`, must not open a second store handle or strand a draft. Share Extension, WidgetKit, Control Center/Lock Screen, Spotlight-index, and terminated-app capture are explicitly DEFERRED (storage-architecture reasons, not UI reasons).
- **D-38 through D-44:** Synchronization state renders through one conditional `tabViewBottomAccessory`, absent when healthy, priority order actionable-exception > undoable-action > transient-work after a grace period. Full-screen `Sync & Recovery` sheet is the deliberate-inspection destination. No persistent nav-bar status glyph. Every summary derives from one authoritative presentation projection. One debounced `AccessibilityNotification.Announcement` per meaningful transition. Phase 3's copy vocabulary carries over unchanged except `Saved on this Mac` → `Saved on this iPhone`. Zero OS notifications of any kind in Phase 4.
- **D-45 through D-49:** Inherit Phase 1/3 semantic design contracts (colors, typography intent, spacing rhythm, plain-text rendering, focus safety, conflict/recovery meaning, copy voice); native feel outranks pixel parity. Generate a Swift token output from `packages/design-tokens/tokens.json`. Follow system light/dark; preserve Increase Contrast, Differentiate Without Color, Reduce Transparency, Reduce Motion. Accessibility is release evidence (`performAccessibilityAudit` + Dynamic Type/Reduce Motion/Differentiate-Without-Color snapshot matrix + safe-focus assertions), not a checklist. Explicitly rejected anti-patterns are listed in D-49 (gesture-only destructive actions, full-swipe-to-delete, pull-to-refresh-implies-correctness, toast-only undo, persistent healthy badges/spinners, App-Group-container store writer, OS notifications for routine sync, cargo-culted Mac keyboard semantics).

### Claude's Discretion

- Exact grace-period duration, backoff constants, and accessory-strip animation timing, within the locked state meanings and the Reduce Motion requirement.
- The precise priority-arbitration contract between the undo control and actionable sync exceptions in the shared accessory slot, and the layout arbitration between the accessory and any capture affordance in the bottom-trailing thumb zone.
- The exact "until superseded" lifetime rule for the undo control (per-list versus global scope).
- Swift module and target decomposition under `apps/ios`, provided the pure reducer is a separate target testable without UI and the store adapter sits behind `LocalStorePort`.
- The specific injected `SIGKILL` points for G3 and the exact fixture lineage retained for G4, provided coverage is adversarial rather than illustrative.
- Sheet detent choices, iconography, and empty-state composition within the inherited semantic and brand contracts.
- Whether the physical-device lane runs as a sub-lane of a single `verify-ios-phase.mjs`-style entry point or as a separately invoked script, provided evidence binding and refusal-on-mismatch behave as D-21 specifies.

### Deferred Ideas (OUT OF SCOPE)

- Share Extension for Safari/cross-app link capture (the most-missed deferral; requires an App Group storage redesign — its own future phase).
- WidgetKit widget, Control Center/Lock Screen controls, Spotlight-index surfaces, capture while fully terminated.
- OS notifications and task reminders (D-19/D-44 hold unchanged).
- TestFlight and App Store distribution (Phase 6).
- Drag-to-reorder and user-defined ordering on iPhone.
- Additional destinations beyond Inbox and Today (Upcoming, Anytime, Someday, projects as top-level).
- Shared FFI core (Rust/UniFFI) for the reducer — revisit only at N=4 consumers and a two-bug post-mortem.
- SQLCipher, biometric app lock, cryptographic erasure, remote wipe.
- iPad and Mac Catalyst layouts.
- Self-hosted CI runner with a tethered device.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-------------------|
| IOS-01 | User can capture, view Inbox and Today, edit, complete, reopen, trash, restore, and undo in a native SwiftUI iPhone client | Architecture Patterns (project structure, GRDB migration pattern), Validation Architecture (KeeplingUITests/CoreLoopTests), Common Pitfall 1 (tabViewBottomAccessory absence bug directly affects the undo/status affordance this requirement depends on) |
| IOS-02 | User can mutate tasks without connectivity, terminate the app, relaunch, and later reconcile without losing or duplicating accepted intent | GRDB WAL/migration code examples, Pattern 2 (STRICT tables + forward-only migrations), Validation Architecture (StorageTests/CrashRecoveryTests, G1-G8 gate mapping), Open Question 2 (table-count reconciliation against the desktop schema) |
| IOS-03 | User receives a platform-native touch, accessibility, Dynamic Type, and Reduce Motion experience for the supported daily loop | Don't Hand-Roll (`performAccessibilityAudit`), Validation Architecture (AccessibilityAuditTests), Security/Accessibility ASVS mapping is out of scope here but see UI-SPEC's Accessibility and Platform Contract |
| IOS-04 | User can distinguish local, syncing, conflict, authentication-expired, and unrecoverable states on a physical iPhone | Architecture Patterns (single authoritative presentation projection), Validation Architecture (SyncStateMatrixTests), Common Pitfall 1 (accessory-absence bug directly threatens this requirement's "healthy = silent" half) |
| SRV-02 (iPhone adapter proof) | User receives the same domain invariants through web, desktop, iPhone, API, and MCP entry points | Pattern 1 (vector-conformant reducer resolved from source tree), Common Pitfall 2 (nullable-anyOf decode defect must be resolved via D-13 before this proof is trustworthy), Validation Architecture (SyncVectorConformanceTests + real-stack lane) |

</phase_requirements>

## Summary

Phase 4's architecture is almost entirely pre-decided in `04-CONTEXT.md` (D-01 through D-49) — GRDB.swift behind `LocalStorePort`, iOS 26 floor, native `swift-openapi-generator`-produced client, a Swift-native reimplementation of the sync reducer proven against the same golden vectors as Elixir and TypeScript, a two-tab `TabView`/`NavigationStack` shell, and a two-lane (simulator + physical-device) evidence model. This research file exists to fill the gaps CONTEXT.md leaves open: exact tool versions on the actual build Mac, exact CLI invocations, and — most importantly — three concrete platform defects/limits discovered this session that materially affect planning:

1. **`tabViewBottomAccessory` cannot be programmatically hidden in current iOS 26.x.** Apple DTS has confirmed (as of iOS 26.1) there is no supported API to make the accessory visually absent at runtime — wrapping its content in `if condition { ... }` leaves an empty-but-present capsule. This directly threatens D-38/D-40's "absent when healthy, not merely quiet" requirement and needs a resolved workaround before planning tasks that assume true absence.
2. **`swift-openapi-generator`'s nullable-`anyOf` decode defect (issue #286)** is real, currently open upstream, and confirms D-13's normalization prerequisite is not optional — 35 sites in `keepling.yaml` must become OpenAPI 3.1 `type: [X, 'null']` unions before Swift generation is attempted, or generated types will fail to decode real server payloads at runtime with no compile-time signal.
3. **`xcodebuild -destination 'platform=iOS,id=<UDID>'` requires the hardware UDID, not the `devicectl` identifier** — the two identifier spaces are different and mixing them produces an opaque "no matching destination" failure. The physical-device lane script must resolve and use the correct ID for each tool.

The toolchain on this Mac is already the D-06-mandated floor (Xcode 26.6 / iOS SDK 26.5, confirmed live this session), `xcodegen` is installed (no Tuist), and no `apps/ios` Xcode project exists yet — Phase 4's first executable task is project scaffolding, not incremental extension.

**Primary recommendation:** Scaffold `apps/ios` with XcodeGen (a checked-in `project.yml`, not a hand-edited `.xcodeproj`) targeting iOS 26, split into a pure-Swift `KeeplingCore` package (reducer + `LocalStorePort` protocol, no UIKit/SwiftUI import) and an app target that depends on it — mirroring the Phase 3 `apps/desktop/main/application` vs `store-worker` split. Drive every lane (`xcodebuild build`, `xcodebuild test -destination 'platform=iOS Simulator,...'`, `xcodebuild test -destination 'platform=iOS,id=<UDID>'`, `devicectl device install/launch/process terminate`) from `tooling/verify-ios-phase.mjs` using the same `spawnSync`-and-parse pattern as `tooling/verify-desktop-phase.mjs`, never `pnpm`, since `apps/ios` is intentionally outside the pnpm workspace graph (D-context, native-tools-first rule).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Domain invariants, revision/idempotency authority, conflict/fencing decisions | API / Backend (Phoenix) | — | Canonical per PROJECT.md/AGENTS.md; iOS never re-derives acceptance |
| Sync reducer (pull/push/ack/fence state machine) | Client (iOS app) — pure Swift target | Backend (reference model, source of vectors) | D-10: N-version Swift reimplementation gated on shared golden vectors, not a shared binary |
| Durable local projection + outbox | Client (iOS app) — GRDB/SQLite layer | — | D-01..D-09; must survive hard termination independent of network |
| Wire contract / DTOs | Generated code (committed) | Backend (OpenAPI source of truth) | D-12/D-13; DTOs never become persistence records (D-30 inherited from Phase 3) |
| Auth token storage & refresh | Client (Keychain) | Backend (device-grant issuance) | Device-local secret; server owns issuance/rotation/revocation |
| Background acceleration | Client (BGTaskScheduler, best-effort) | — | D-22 Criterion 3: explicitly NOT a correctness dependency; foreground reconciliation is authoritative |
| Presentation/sync-state projection | Client (SwiftUI views, presentation-only) | — | D-41: UI infers no truth of its own; single authoritative projection like Phase 3's `ClientFacade` |
| Accessibility semantics (VoiceOver labels, Dynamic Type, touch targets) | Client (SwiftUI + XCUITest audits) | — | Platform-owned APIs, phase-owned verification |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| GRDB.swift | **7.11.1** (latest tag, released 2026-06-18) [ASSUMED — discovered via WebSearch, not yet independently confirmed against the GitHub Releases page in this session; treat as needing a fresh `git ls-remote --tags` check at execute time] | Local SQLite adapter behind `LocalStorePort` | D-01; eleven-year-old MIT library, zero transitive deps, links system SQLite, never hides SQL — chosen explicitly over SwiftData (D-02) |
| apple/swift-openapi-generator | **1.10.2** [ASSUMED — version string surfaced via a fetched Makefile example in the upstream repo, not cross-checked against a release tag list this session] | Generates Swift client types/operations from `keepling.yaml`, CLI-invoked, output committed | D-12; mirrors the committed-generated-output precedent already used for `packages/contracts/generated/keepling.ts` |
| apple/swift-openapi-runtime | Pinned to the generator's compatible minor (verify at generation time via the generator's own compatibility table) [ASSUMED] | Runtime support types (`OpenAPIValueContainer`, coders) consumed by generated code | Required companion package to swift-openapi-generator; not optional |
| apple/swift-openapi-urlsession | Latest compatible release [ASSUMED] | URLSession-based `ClientTransport` conformance | D-12 explicitly names URLSession transport with hand-written mappers |
| XCTest / XCUITest | Ships with Xcode 26.6 | Unit, integration, and UI-automation test target | Native, no third-party test framework needed or wanted |
| AppIntentsTesting | Ships with the iOS 26 SDK (Apple framework, WWDC25/26 sessions) [CITED: developer.apple.com/documentation/AppIntentsTesting] | Drives `AppIntent.perform()` through the same resolution path Siri/Shortcuts use, without UI automation | Directly satisfies D-35's "provable by unit-testing `perform()` directly" requirement more rigorously than calling `perform()` bare |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| XcodeGen | Installed at `/opt/homebrew/bin/xcodegen` [VERIFIED: `which xcodegen tuist` — xcodegen found, tuist not found, run 2026-09-04] | Generates `.xcodeproj` from a checked-in `project.yml` | Use for the Phase 4 project — deterministic, diffable, avoids Xcode's binary `.pbxproj` merge conflicts; Tuist is not installed and would add a second toolchain decision not currently justified |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| GRDB.swift | Raw `sqlite3` C API via `libsqlite3.tbd` | D-05's predeclared fallback; only triggered if GRDB fails G1–G6 gates or goes unmaintained — do not pre-build both |
| GRDB.swift | SwiftData | D-02 explicitly rejects it — opaque schema, opaque migration checksums, reference-type `@Model` violates presentation-boundary discipline |
| XcodeGen | Tuist | Tuist adds project-graph caching and module templating Phase 4 does not need; XcodeGen's flat YAML is closer in spirit to the repo's "native tools first, shallow dependency trees" rule and is already installed |
| swift-openapi-generator CLI (committed output) | Build Tool Plugin | Rejected by D-12: a build-plugin's output is not diff-reviewable, is not deterministic offline, and triggers Xcode build-tool-plugin trust prompts / `-skipPackagePluginValidation` friction |

**Installation (illustrative — exact versions to be pinned via `Package.resolved` at execute time):**
```yaml
# apps/ios/Package.swift (KeeplingCore package) — swift-tools-version: 6.3
dependencies: [
  .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
]
```
```bash
# One-time generator install (not vendored into the app target)
git clone https://github.com/apple/swift-openapi-generator.git /tmp/sog
cd /tmp/sog && git checkout 1.10.2 && swift build -c release
```

**Version verification:** No `npm view`/`pip index versions` equivalent exists for Swift Package Manager. The closest structural verification is `git ls-remote --tags <repo-url>` or the GitHub Releases API — **do this at execute time**, not from this research file, since both versions above are tagged `[ASSUMED]` (surfaced via WebSearch/training knowledge, not independently re-verified against the tag list in this session). Do not hand-pin these version numbers into `Package.swift` without that fresh check.

## Package Legitimacy Audit

The GSD `package-legitimacy check` seam supports npm/pypi/crates ecosystems only — Swift Package Manager is not covered, so this audit is manual, based on official-source signals gathered this session.

| Package | Registry | Age | Downloads/Popularity | Source Repo | Verdict | Disposition |
|---------|----------|-----|----------------------|--------------|---------|-------------|
| GRDB.swift | Swift Package Index / GitHub | ~11 years (per D-01, itself an already-vetted project decision) | Ships in Signal iOS and DuckDuckGo per D-01's own citation | github.com/groue/GRDB.swift | OK (manual) | Approved — already the phase's locked D-01 decision, not a discretionary choice for this research |
| apple/swift-openapi-generator, -runtime, -urlsession | GitHub (Apple org) | Apple first-party, GA since 2023 (`swift.org` 1.0 announcement) | Official Apple/Swift.org project | github.com/apple/swift-openapi-generator | OK | Approved |
| XcodeGen | Homebrew / GitHub | Long-established (yonaskolb/XcodeGen), already installed locally | Widely used in iOS CI tooling | github.com/yonaskolb/XcodeGen | OK | Approved |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

*GRDB and the Apple swift-openapi-* trio are discovered via official GitHub organizations and D-01's own prior vetting, not blind WebSearch — but the exact version numbers pinned above are still `[ASSUMED]` per the provenance rule and must be re-verified against the tag list before `Package.swift` is written.

## Architecture Patterns

### System Architecture Diagram

```
                         ┌────────────────────────────────────────────┐
                         │              iPhone app process              │
                         │                                              │
  User touch/gesture ──▶ │  SwiftUI Views (Today/Inbox/Detail/Capture)  │
                         │        │  (presentation-only; D-45)          │
                         │        ▼                                     │
                         │  Presentation Projection (single authority)  │◀── AccessibilityNotification.Announcement
                         │        │  D-41: UI infers no sync truth       │
                         │        ▼                                     │
                         │  ClientFacade-equivalent boundary            │
                         │        │                                     │
                         │        ▼                                     │
                         │  KeeplingCore (pure Swift target)            │
                         │   ┌─────────────┐   ┌────────────────────┐  │
                         │   │ Sync Reducer │──▶│  LocalStorePort     │  │
                         │   │ (D-10, vector│   │  protocol           │  │
                         │   │  conformant) │   └─────────┬──────────┘  │
                         │   └─────────────┘             │              │
                         │                                ▼              │
                         │                    ┌────────────────────┐    │
                         │                    │ GRDB adapter (D-01) │    │
                         │                    │ 9 STRICT tables +   │    │
                         │                    │ outbox + migrations │    │
                         │                    │ (WAL, synchronous=  │    │
                         │                    │  FULL, one writer)  │    │
                         │                    └─────────┬──────────┘    │
                         │                                │ file I/O     │
                         │                     app-container SQLite      │
                         │                     (NOT App Group; D-07)     │
                         └──────────────────────┬────────────────────────┘
                                                 │ URLSession (generated
                                                 │ swift-openapi client)
                                                 ▼
                         ┌────────────────────────────────────────────┐
                         │   Phoenix / PostgreSQL (canonical, Phase 1/2)│
                         │   sync feed, command idempotency, conflicts  │
                         └────────────────────────────────────────────┘

  BGTaskScheduler (background) ──▶ same reducer/store path as foreground,
                                   invoked with an injected task handle;
                                   NEVER a correctness dependency (D-22 C3)
```

### Recommended Project Structure

```
apps/ios/
├── project.yml                     # XcodeGen source of truth (committed, not .xcodeproj by hand)
├── Package.swift                   # KeeplingCore SPM package (pure Swift, no UIKit/SwiftUI import)
├── Sources/
│   ├── KeeplingCore/                # reducer, LocalStorePort protocol, mappers — unit-testable headless
│   │   ├── Sync/                    # reducer + state machine matching sync-state-machine.schema.json
│   │   ├── Storage/                 # LocalStorePort protocol + GRDB adapter (+ raw-sqlite3 fallback seam)
│   │   ├── Transport/               # generated Swift client (committed) + hand-written DTO↔model mappers
│   │   └── AppIntents/              # Capture/Complete intents (main-target-declared per D-35, logic here)
│   └── Keepling/                    # SwiftUI app target
│       ├── App/                     # App entry, ScenePhase handling, BGTaskScheduler registration
│       ├── Today/ Inbox/ Detail/    # per D-25 two-tab NavigationStack screens
│       ├── Capture/                 # capture sheet (D-35)
│       ├── SyncRecovery/            # tabViewBottomAccessory + full-screen sheet (D-38/D-39)
│       └── DesignTokens/            # generated Swift token file (D-46 emitter output, committed)
├── Tests/
│   ├── KeeplingCoreTests/           # pure-Swift unit tests, vector conformance (D-15), no simulator needed
│   ├── StorageTests/                # GRDB G1-G8 gate tests, crash/SIGKILL injection
│   └── KeeplingUITests/             # XCUITest — simulator required
└── README.md                        # already exists; update after scaffolding
```

### Pattern 1: Vector-conformant reducer, resolved from source tree (D-15)

**What:** Load `packages/contracts/vectors/*.json` at test compile/run time via a `#filePath`-derived repository-root walk, never via SwiftPM `.copy` resources.
**When to use:** Every `KeeplingCoreTests` vector-conformance test.
**Example:**
```swift
// Pattern mirrors apps/desktop/test/application/sync-vectors.test.ts's per-vector loop.
// Source: repository pattern (apps/desktop test), re-expressed per D-15's "resolve at test
// compile time from the source tree via #filePath" requirement — no official upstream URL,
// this is a project-specific pattern, not a framework API. [ASSUMED shape; verify exact
// #filePath-to-repo-root walk at execute time against the actual apps/ios test target layout]
func repositoryRoot(from file: StaticString = #filePath) -> URL {
    var url = URL(fileURLWithPath: "\(file)")
    while url.lastPathComponent != "keepling" { url.deleteLastPathComponent() }
    return url
}

func loadVectorFile(_ name: String) throws -> SyncVectorFile {
    let path = repositoryRoot()
        .appendingPathComponent("packages/contracts/vectors/\(name).json")
    let data = try Data(contentsOf: path)
    return try JSONDecoder().decode(SyncVectorFile.self, from: data)
}
```

### Pattern 2: GRDB STRICT table + migration registered forward-only

**What:** Migrations use GRDB's `DatabaseMigrator`, each migration is a named forward-only step; no `eraseDatabaseOnSchemaChange` anywhere (D-04 G4 build-time test proves this).
**When to use:** Every schema change to the 9-table D-35 layout, mirroring `apps/desktop/migrations/0001_initial.sql` and `0002_outbox_state.sql` almost verbatim as DDL text.
**Example:**
```swift
// Source: GRDB.swift official migration guide pattern (github.com/groue/GRDB.swift —
// "Migrations" section of README.md). [CITED: github.com/groue/GRDB.swift README]
var migrator = DatabaseMigrator()
#if DEBUG
// migrator.eraseDatabaseOnSchemaChange = true   // NEVER enabled — D-04 G4 asserts this absent
#endif
migrator.registerMigration("v1_initial") { db in
    try db.execute(sql: """
        CREATE TABLE schema_migrations (
          version INTEGER PRIMARY KEY,
          checksum TEXT NOT NULL CHECK (length(checksum) = 64),
          applied_at TEXT NOT NULL
        ) STRICT;
        -- ... remaining 8 tables mirror apps/desktop/migrations/0001_initial.sql column-for-column
        """)
}
try migrator.migrate(dbQueue)
```
The exact DDL for the 9 tables should be adapted line-for-line from
`apps/desktop/migrations/0001_initial.sql` [VERIFIED: apps/desktop/migrations/0001_initial.sql:1-70 — read this session; contains `schema_migrations`, `namespace_metadata`, `canonical_shadow`, `visible_projection`, `immutable_commands`, `mutation_journal`, `mutation_dependencies`, `outbox`, `sync_cursor`, `conflicts`, `last_local_action` — 11 `CREATE TABLE ... STRICT` statements, not 9; D-35's "nine tables" appears to undercount by 2 (`sync_cursor` and `last_local_action` are additional singleton tables in the desktop schema). **Flag for the planner:** confirm with the user whether iOS's D-35 nine-table set intentionally excludes `last_local_action` (iOS uses a different undo-persistence shape per D-30's "named persistent control," not a `last_local_action` singleton) or whether the count is simply imprecise in CONTEXT.md.] and `0002_outbox_state.sql` [VERIFIED: apps/desktop/migrations/0002_outbox_state.sql:1-45 — read this session; adds `outbox.state TEXT NOT NULL DEFAULT 'queued' CHECK (state IN ('queued','in_flight','uncertain'))` via `ALTER TABLE`, with pre-existing rows set to `'uncertain'` on upgrade — this monotonic three-state outbox model is exactly what iOS's outbox column must replicate for D-34's undo-as-compensating-action semantics].

### Pattern 3: App Intent declared in main target, tested via AppIntentsTesting

**What:** `CaptureTaskIntent`/`CompleteTaskIntent` conforming to `AppIntent`, `perform()` calling into `KeeplingCore` directly (no second process, no App Group — D-35/D-37).
**When to use:** Shortcuts/Siri/Action Button/Spotlight capture surface.
**Example:**
```swift
// Source: developer.apple.com/documentation/AppIntentsTesting (WWDC25/26 sessions).
// [CITED: developer.apple.com/documentation/AppIntentsTesting]
import AppIntentsTesting
import XCTest

final class CaptureIntentTests: XCTestCase {
    func testCaptureAddsToInbox() async throws {
        let intent = CaptureTaskIntent()
        intent.title = "Call dentist"
        // AppIntentsTesting drives the same resolution path Siri/Shortcuts use —
        // resolveAndPerform ensures dependency injection happens, unlike bare perform().
        let result = try await intent.resolveAndPerform()
        XCTAssertEqual(result.value?.destination, .inbox)
    }
}
```

### Anti-Patterns to Avoid

- **Conditionally emptying `tabViewBottomAccessory` content and calling it "hidden":** Per Apple DTS confirmation (iOS 26.1, forum thread 803404), an `if` inside `.tabViewBottomAccessory { }` leaves an empty-but-still-present capsule — it is not visually absent. D-38/D-40's "absent when healthy" claim is currently **not directly implementable** with the documented API. See Common Pitfalls and Open Questions below — this needs a resolved workaround before Task planning, not after.
- **Vendoring `.xcactivitylog`/`.xcodeproj` binary diffs as the source of truth:** Use XcodeGen's `project.yml` exactly as the desktop phase used committed manifests over hand-maintained binaries.
- **Trusting `xcodebuild`'s destination resolution to auto-match a `devicectl` UDID:** it does not (see Pitfall 3).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SQLite migration ledger / STRICT-table wrapper | A bespoke raw-`sqlite3` wrapper as the primary path | GRDB.swift's `DatabaseQueue`/`DatabasePool` + `DatabaseMigrator` (D-01) | GRDB already solves transaction wrapping, WAL configuration, and busy-timeout handling without hiding SQL; raw C API is the explicitly predeclared fallback only |
| OpenAPI→Swift codegen | A hand-written DTO layer parsing `keepling.yaml` | `swift-openapi-generator` CLI, committed output | D-12; hand-rolling a second contract parser is exactly the drift the committed-generator pattern exists to prevent |
| Accessibility QA | Manual VoiceOver walkthroughs as the primary gate | `XCUIApplication.performAccessibilityAudit(for:)` (Xcode 15+, ships with Xcode 26.6) | Automatable, fails the test on any finding — required given the zero-manual-UAT constraint |
| Background task simulation | Waiting for real opportunistic `BGTaskScheduler` firing during CI | `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"..."]` in the debugger, or direct handler invocation with an injected `BGAppRefreshTask` in XCTest | Real scheduling is opportunistic and explicitly not assertable (D-22 C3 disclosure) |
| App Intent UI-driven testing | Driving Siri/Shortcuts through XCUITest UI automation | `AppIntentsTesting` framework's `resolveAndPerform()` | Exercises the same resolution path without unautomatable Siri UI |

**Key insight:** Every "don't hand-roll" item in this phase already has a first-party (Apple or GRDB) tool that is more correctness-proven than a bespoke Swift equivalent would be on a first native-iOS phase for this codebase — the phase's own D-04 gate structure (pass/fail, not a bake-off) reflects the same philosophy already applied to the toolchain choices above.

## Common Pitfalls

### Pitfall 1: `tabViewBottomAccessory` cannot be made truly absent (iOS 26.0–26.1)
**What goes wrong:** Code that renders `if hasNoActionableState { EmptyView() } else { StatusView() }` inside `.tabViewBottomAccessory { }` still reserves and displays an empty accessory capsule — D-38's "absent when healthy" is violated visually even though the semantic content is correctly empty.
**Why it happens:** [CITED: developer.apple.com/forums/thread/803404] Apple DTS confirmed as of iOS 26.1 there is "no supported way... to programmatically hide the bottom accessory in a tab view with the APIs currently available." Multiple FB numbers are filed (FB20587621, FB20603246, FB20425139, FB20772048) — unresolved as of this session.
**How to avoid:** Do not treat "absent" as achievable purely through the SwiftUI accessory API. Options to evaluate at plan time (Claude's Discretion territory, but the planner must pick one explicitly, not silently assume the naive approach works): (a) verify empirically on iOS 26.5/26.6 whether the specific regression still reproduces (the forum reports 26.1 regressed from an "inconsistent" 26.0 baseline — the exact behavior on this repo's pinned SDK 26.5 needs a same-session snapshot test before relying on either behavior); (b) if still broken, use `.tabViewBottomAccessory(isEnabled:content:)`'s `isEnabled` parameter (distinct from conditionally emptying content) if it actually suppresses the reserved space — this needs an on-device/simulator snapshot check, not an assumption; (c) disclose the gap explicitly in the phase's evidence model exactly as D-22 discloses the `BGTaskScheduler` gap, rather than asserting a passing snapshot test that isn't actually testing absence.
**Warning signs:** A snapshot/XCUITest asserting "accessory view is absent" that only checks for empty *text content* rather than absent *frame/hit-testable area* will pass even though the capsule visually persists — this is a likely false-green test-writing pitfall unique to this defect.

### Pitfall 2: nullable-`anyOf` decode failures at runtime, not compile time
**What goes wrong:** [CITED: github.com/apple/swift-openapi-generator/issues/286] Fields declared as `anyOf: [X, {type: 'null'}]` decode to "The anyOf structure did not decode into any child schema" when the server returns an actual null — this is a *runtime* `DecodingError`, invisible until a real payload with a null field is exercised.
**Why it happens:** OpenAPI 3.0-style nullable modeling via `anyOf` with a null-type sibling schema is not what the generator's `oneOf`/`anyOf` decode strategy expects; OpenAPI 3.1's `type: [X, 'null']` union form is.
**How to avoid:** D-13's normalization (35 sites in `keepling.yaml` rewritten to 3.1 unions, discriminators added to the two named `oneOf`s) must land and be regenerated-and-diffed *before* any Swift decode-round-trip test is trusted. D-14's "decode round-trip test over every wire payload in the 13 vector files" is the correct gate — but it only catches the defect if the vector files actually contain a null value for every nullable field, which should be spot-checked, not assumed.
**Warning signs:** A decode round-trip test suite that passes 100% while every vector's nullable field happens to be non-null in every fixture is a coverage gap, not a proof.

### Pitfall 3: `xcodebuild -destination 'platform=iOS,id=...'` vs `devicectl` identifier mismatch
**What goes wrong:** [CITED: multiple sources including cameroncooke/XcodeBuildMCP documentation] `xcodebuild` matches on the device's hardware UDID; `devicectl` uses its own device identifier space. Passing a `devicectl`-obtained ID into `xcodebuild -destination` fails with "Unable to find a device matching the provided destination specifier," and unlike `xcodebuild`, `devicectl` itself does not accept a `-destination` specifier at all — it always wants an explicit device ID of its own kind.
**Why it happens:** The two Apple CLI tools evolved independently (`xcodebuild` predates `devicectl`) and were never unified on one identifier scheme.
**How to avoid:** The device-lane script (D-20/D-22's physical-device lane) must resolve both IDs once (`xcrun xctrace list devices` or `xcrun devicectl list devices` for the devicectl ID; `xcodebuild -showdestinations` or the classic UDID from `system_profiler`/`ideviceinfo`-equivalent for the hardware UDID) and pass the correct one to each tool — never assume they're interchangeable.
**Warning signs:** A device-lane script hard-coding one ID string and passing it to both `xcodebuild test` and `devicectl device install` will work for one and silently fail (or worse, target the wrong device) for the other unless explicitly tested against a real attached iPhone.

### Pitfall 4: SQLite in an App Group container (jetsam / `0xDEAD10CC`)
**What goes wrong:** [ASSUMED — D-context already cites Signal's `SQLCipherVsSharedData` writeup for this; not independently re-fetched this session] Cross-process SQLite access via an App Group container is a documented corruption and jetsam-termination (`0xDEAD10CC`, "process was killed because it held a file lock or SQLite database lock during suspension") hazard.
**Why it happens:** iOS terminates a suspended process that still holds a file lock another process needs, and SQLite's file locking model does not gracefully degrade across that suspend boundary in a shared container.
**How to avoid:** D-07 already keeps the store in the app container, not an App Group — this is correctly closed by the phase's own decisions. The risk resurfaces only if a *later* phase adds a Share Extension or widget without redesigning storage access (D-36 defers exactly this).
**Warning signs:** Any future task that reaches for `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)` for the SQLite path is reopening this hazard — flag it in code review.

### Pitfall 5: `synchronous=FULL` + WAL checkpoint stalls perceived as "the app is frozen"
**What goes wrong:** [ASSUMED] `synchronous=FULL` (required by D-38 durability posture) forces an `fsync` on every commit; on a phone under memory/thermal pressure, WAL checkpoint operations can introduce visible latency spikes if triggered on a path the UI is waiting on.
**Why it happens:** iOS's storage subsystem shares I/O bandwidth with backgrounded system processes (Spotlight indexing, backups) more aggressively than desktop macOS.
**How to avoid:** D-34's "no meaningful store work on the main thread" already addresses the direct freeze risk; ensure the G5 threading gate's main-thread-checker assertion specifically covers WAL checkpoint callback paths, not just the write transaction itself.
**Warning signs:** Intermittent, hard-to-reproduce UI stalls correlated with capture/complete actions but not visible in a fast simulator (simulator I/O does not model real flash storage contention) — this is the kind of defect the physical-device lane exists to catch and the simulator lane cannot.

## Code Examples

### GRDB DatabasePool WAL configuration matching D-38 durability posture
```swift
// Source: GRDB.swift README "Advanced DatabasePool" / Configuration docs.
// [CITED: github.com/groue/GRDB.swift — README, "Enabling WAL Mode" and "Configuration" sections]
var config = Configuration()
config.busyMode = .timeout(5.0)  // finite busy handling per D-38 "finite busy handling"
let dbPool = try DatabasePool(path: databasePath, configuration: config)
try dbPool.write { db in
    // Verify PRAGMA readback at open per D-04 G6.
    try db.execute(sql: "PRAGMA synchronous = FULL")
    let journalMode = try String.fetchOne(db, sql: "PRAGMA journal_mode") // expect "wal"
    let fkStatus = try Int.fetchOne(db, sql: "PRAGMA foreign_keys")       // expect 1, verified per connection (G1)
    precondition(journalMode == "wal" && fkStatus == 1)
}
```

### Data Protection class assertion on the store file (D-context G7)
```swift
// Source: Apple File System Programming Guide / FileManager attribute API.
// [CITED: developer.apple.com/documentation/foundation/fileprotectiontype]
let attrs = try FileManager.default.attributesOfItem(atPath: storeURL.path)
let protection = attrs[.protectionKey] as? FileProtectionType
precondition(protection == .completeUntilFirstUserAuthentication,
             "Store file must be .completeUntilFirstUserAuthentication, never .complete (D-context G7)")
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| Core Data / SwiftData as the default local-store choice for new iOS apps | GRDB or raw SQLite for apps needing provable schema/migration control | SwiftData introduced 2023 (WWDC23); its opacity limitations (D-02) remain unresolved as of iOS 26 | Confirms D-01/D-02's reasoning is not a stale 2023 objection — the opacity gap is still current |
| `.xcodeproj` binary format hand-edited in Xcode | Generated from `project.yml` (XcodeGen) or `Project.swift` (Tuist) for teams wanting diffable, mergeable project state | Long-standing community practice, no recent change | Matches this repo's committed-manifest philosophy already used for `packages/contracts/generated/` |
| UITest-driven Siri/Shortcuts verification | `AppIntentsTesting` framework, `resolveAndPerform()` | Formalized WWDC25/26 | Makes D-35's "provable by unit-testing perform() directly" claim stronger than it would have been pre-framework — use it, not bare `perform()` |

**Deprecated/outdated:**
- Hand-rolled Siri/Shortcuts UI-automation tests for App Intents: superseded by `AppIntentsTesting`, which is faster and does not depend on system UI automation permissions.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | GRDB.swift latest tag is 7.11.1 (2026-06-18) | Standard Stack | Wrong pinned version in `Package.swift`; low risk, mechanically corrected by `git ls-remote --tags` at execute time |
| A2 | swift-openapi-generator current release is 1.10.2 | Standard Stack | Same as A1 — mechanically correctable, but the generator's nullable-`anyOf` behavior (Pitfall 2) should be re-verified against whatever version is actually pinned, since generator behavior around D-13's normalization is the load-bearing claim, not the exact version number |
| A3 | The `#filePath`-to-repository-root walk pattern shown in Pattern 1 is the right Swift idiom for D-15's "resolve at test compile time from source tree" requirement | Architecture Patterns | If Swift's `#filePath` resolves differently under `xcodebuild test` sandboxing than assumed, the vector-loading test harness needs a different resolution strategy (e.g., an environment variable pointing at repo root, set by the test runner script) |
| A4 | Whether `.tabViewBottomAccessory(isEnabled:content:)`'s `isEnabled` parameter actually suppresses the reserved layout space (vs. only disabling interaction) is unverified this session | Common Pitfalls (Pitfall 1) | If `isEnabled: false` does not remove the reserved space either, D-38/D-40's "absent when healthy" claim needs either a UIKit-interop workaround or an explicit disclosed-gap treatment before planning proceeds — this should be resolved with a same-session throwaway snapshot test at plan or execute time, not assumed either way |
| A5 | apple/swift-openapi-runtime and -urlsession version compatibility windows track the generator's minor version 1:1 | Standard Stack | If they don't, `swift build` fails at compile time with a clear diagnostic — low risk, self-revealing |

**If this table is empty:** N/A — see rows above.

## Open Questions (RESOLVED)

All three questions below were resolved at plan time; each carries the plan and task that closes it. A fourth resolution covering the `[ASSUMED]` version pins follows.

1. **Can `tabViewBottomAccessory` actually be made visually absent on the pinned iOS SDK 26.5, or must D-38/D-40 be re-scoped/disclosed?**
   - What we know: Apple DTS confirmed no supported hide API as of iOS 26.1; multiple FB reports are open and unresolved.
   - What's unclear: Whether the exact SDK 26.5/Xcode 26.6 combination pinned on this Mac reproduces the bug, and whether `isEnabled: false` (a different code path than conditional content) behaves differently.
   - Recommendation: Before writing any accessory-strip task, spike a minimal `TabView` + `.tabViewBottomAccessory(isEnabled: $isEnabled) { ... }` on the simulator and assert on the rendered frame height/hit-test region, not just content — resolve this as a Wave 0 spike, not a discovered defect mid-implementation.
   - **RESOLVED — `04-04-PLAN.md` Task 1: "Measure whether the bottom accessory can be genuinely absent, and commit the answer."** The question is *not* answered by assumption in this research file; the plan converts it into a committed measurement on the pinned SDK. `Tests/KeeplingUITests/AccessoryAbsenceProbeTests.swift` measures three named configurations (conditional content, conditional modifier, `isEnabled:` overload — recording explicitly if that overload does not exist on SDK 26.5) and asserts on rendered frame height and hit-testable region plus the tab bar's top edge, never on text content, which is exactly the false-green this file warned about. The outcome is written into one named constant, `apps/ios/Sources/Keepling/SyncRecovery/AccessoryHostability.swift`, with two cases — absence achievable via a named configuration, or absence not achievable on this SDK — plus the measured SDK version string; Plan 04-10 reads that single value rather than scattering conditionals. **Disclosed fallback if absence turns out to be unachievable:** the capability is set to not-achievable, the probe test is kept asserting the measured non-zero frame (so a future SDK fix fails loudly and prompts the upgrade), and `docs/testing/ios-testing.md` records a per-dimension disclosure — citing the DTS forum thread and the four Feedback numbers — stating that the accessory reserves layout space when healthy and that it then renders as an empty, non-interactive, accessibility-hidden strip carrying no text, glyph, or count. Repurposing the reserved space into a healthy status badge is explicitly forbidden (D-40's ambient-noise rejection).

2. **Does the D-35 "nine tables" count match the actual schema iOS should carry, given the desktop schema (verified this session) has 11 `CREATE TABLE ... STRICT` statements?**
   - What we know: `apps/desktop/migrations/0001_initial.sql` defines `schema_migrations`, `namespace_metadata`, `canonical_shadow`, `visible_projection`, `immutable_commands`, `mutation_journal`, `mutation_dependencies`, `outbox`, `sync_cursor`, `conflicts`, `last_local_action` — 11 tables.
   - What's unclear: D-35 names nine categories ("namespace metadata, canonical shadow, visible projection, immutable command bytes/fingerprint, mutation journal, dependency edges, outbox, cursor, and conflicts") which appears to fold `schema_migrations` in separately (per D-37) and omit `last_local_action` (iOS undo is a different persistent-control shape per D-30, not a `last_local_action` singleton) — so 9 + `schema_migrations` + no `last_local_action` = 10, still one short of an exact match, or the desktop's `sync_cursor` and D-35's "cursor" category are the same thing counted once.
   - Recommendation: Have the planner enumerate the exact 9 (or 10, or 11) `CREATE TABLE` statements iOS will ship, table by table, against D-35's prose list, as an explicit plan-time checklist — do not let the ambiguity ride into implementation.
   - **RESOLVED — `04-01-PLAN.md` Task 3: "End-to-end 'capture one task on this iPhone' — one path only."** The plan decides for all 11 tables, including `sync_cursor` and `last_local_action`: D-35's prose "nine tables" enumerates nine *categories*, names the migration ledger separately under D-37, and carrying `last_local_action` costs one table while keeping the schema a literal mirror of the desktop's — which is what D-03's "mirror verbatim" asks for and what keeps the retained desktop fixtures portable. The decision is recorded in the plan's SUMMARY, and the task's verify greps `Migration0001Initial.swift` for exactly 11 `CREATE TABLE` statements (any other count fails), with an acceptance criterion that every table name matches `apps/desktop/migrations/0001_initial.sql` exactly. A related decision is recorded there too: the stored `visible_projection.sync_status` enum keeps the desktop's `'saved_on_this_mac'` value, since D-43's `this Mac` → `this iPhone` substitution is presentation-layer only and a divergent stored enum would break vector and fixture portability.

3. **What exact GRDB API expresses `PRAGMA foreign_keys=ON` "verified per connection" (D-04 G1) under `DatabasePool`'s multi-connection model?**
   - What we know: GRDB's `Configuration.prepareDatabase` closure runs once per opened connection and is the documented hook for per-connection PRAGMAs.
   - What's unclear: Exact GRDB API surface for `DatabasePool` (which opens multiple reader connections) vs `DatabaseQueue` (single connection) — G1's "per connection" language needs the pool variant confirmed, since D-04 gates hinge on this being provably true for every connection, not just the writer.
   - Recommendation: Resolve during G1 gate implementation with a test that opens several pool connections and asserts `PRAGMA foreign_keys` on each, not just the writer.
   - **RESOLVED — `04-02-PLAN.md` Task 3: "Per-connection foreign keys, durability posture readback, and main-thread discipline (G1, G5, G6)."** The answer the plan records: `Configuration.prepareDatabase` is the per-connection hook, and because `DatabasePool` opens multiple reader connections, G1's "verified per connection" is only satisfied by a test that forces several reader connections open *simultaneously* and reads the pragma on each. `Tests/StorageTests/DurabilityPostureTests.swift` holds concurrent reads open behind an explicit barrier so the pool is genuinely forced past one connection, and asserts on every one — the plan states outright that a test opening a single reader does not satisfy G1 and must not be written as if it does. It also proves the keys have teeth (an orphan-parent insert must be rejected) rather than merely being declared, and adds `integrity_check`/`foreign_key_check` on both a fresh store and the committed forward-migration fixture.

4. **Are the `[ASSUMED]` GRDB.swift (7.11.1) and swift-openapi-generator (1.10.2) version pins correct? — RESOLVED by deferral to execute-time resolution.**
   - **RESOLVED — `04-01-PLAN.md` Task 2: "Scaffold apps/ios with resolved dependency pins and generate the committed Swift wire client."** The plan resolves both pins before any manifest is written, by running `git ls-remote --tags` against `github.com/groue/GRDB.swift` and `github.com/apple/swift-openapi-generator` and pinning the highest stable tag each repository actually publishes, with the resolved tags and the raw `git ls-remote` output quoted in the SUMMARY. `apple/swift-openapi-runtime` and `-urlsession` are then pinned to the versions the resolved generator release declares compatible.
   - **The version numbers written in this research file are not to be copied.** `7.11.1` and `1.10.2` are guesses recorded in the Assumptions Log (A1, A2), surfaced via WebSearch and never cross-checked against a tag list. They exist here only as provenance-tagged placeholders; hand-pinning either number into `Package.swift` is a defect. Note also that the load-bearing claim in Pitfall 2 is the generator's nullable-`anyOf` *behavior*, not its version string — re-verify that behavior against whatever version is actually resolved.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode | All iOS build/test lanes | ✓ [VERIFIED: `xcodebuild -version`, run 2026-09-04] | 26.6 (Build 17F113) | — |
| iOS SDK | Deployment floor (D-06) | ✓ [VERIFIED: `xcrun --sdk iphoneos --show-sdk-version`, run 2026-09-04] | 26.5 | — |
| Swift toolchain | Compilation | ✓ [VERIFIED: `swift --version`, run 2026-09-04] | swift-driver 1.148.6, Swift 6.3.3 (swiftlang-6.3.3.1.3) | — |
| XcodeGen | Project generation | ✓ [VERIFIED: `which xcodegen`, run 2026-09-04] | installed at `/opt/homebrew/bin/xcodegen` (exact version not queried this session) | — |
| Tuist | Alternative project generation | ✗ [VERIFIED: `which tuist`, run 2026-09-04 — not found] | — | Not needed; XcodeGen is the chosen tool (see Alternatives Considered) |
| iOS Simulator runtimes (iPhone 16/17 family) | Simulator lane (required gate) | ✓ [VERIFIED: `xcrun simctl list devicetypes`, run 2026-09-04 — iPhone 16/16e/16 Plus/16 Pro/16 Pro Max, iPhone 17/17e/17 Pro/17 Pro Max/Air device types present] | — | — |
| Physical iPhone attached via `devicectl` | Physical-device lane (phase-acceptance gate, D-20) | Not probed this session — no device was attached/queried | — | None; D-20 makes this lane required for phase acceptance, not every commit — if genuinely unavailable at execute time, this blocks Criterion 1/2/3 evidence and must be surfaced to the user, not silently skipped |
| Apple Developer Program membership ($99/yr, D-17) | Non-expiring provisioning, App Groups/Keychain entitlements | Not verified this session — requires an out-of-band account check | — | If not yet purchased, D-17 makes this a phase-blocking prerequisite, not a nice-to-have; surface early |

**Missing dependencies with no fallback:**
- A currently-attached, trusted physical iPhone for the device lane — required for phase acceptance (D-20/D-22), not verified present this session.
- Confirmed active Apple Developer Program membership — D-17 requires purchasing this *in* Phase 4 if not already done; the planner should add an explicit early task/checkpoint for this rather than assuming it exists.

**Missing dependencies with fallback:**
- None identified; the simulator lane fully covers Criterion 4 evidence and most of Criteria 1–2 per D-22's explicit lane-binding table.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest / XCUITest (Xcode 26.6, ships with the SDK — no third-party test framework) |
| Config file | `apps/ios/project.yml` (XcodeGen scheme/target definitions) — none exists yet; this is a Wave 0 deliverable |
| Quick run command | `xcodebuild test -project apps/ios/Keepling.xcodeproj -scheme Keepling -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:KeeplingCoreTests` |
| Full suite command | `xcodebuild test -project apps/ios/Keepling.xcodeproj -scheme Keepling -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'` (all targets) plus the physical-device invocation for phase-gate: `xcodebuild test -project apps/ios/Keepling.xcodeproj -scheme Keepling -destination 'platform=iOS,id=<hardware-UDID>' -allowProvisioningUpdates` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|--------------------|-------------|
| IOS-01 | Capture/Inbox/Today/edit/complete/reopen/trash/restore/undo via native touch | XCUITest, simulator (required gate) + physical-device confirmation | `xcodebuild test ... -only-testing:KeeplingUITests/CoreLoopTests` | ❌ Wave 0 |
| IOS-02 | Offline mutation, termination, relaunch, reconcile without loss/duplication | Store/persistence unit tests (G3 SIGKILL injection) + physical-device lane (real proxy-recorded server) | `xcodebuild test ... -only-testing:StorageTests/CrashRecoveryTests`; device lane: `devicectl device process terminate` + relaunch | ❌ Wave 0 |
| IOS-03 | Dynamic Type, VoiceOver, touch targets, Reduce Motion | Accessibility audit + Dynamic Type snapshot matrix | `xcodebuild test ... -only-testing:KeeplingUITests/AccessibilityAuditTests` (calls `performAccessibilityAudit(for: [.contrast, .dynamicType, .textClipped, .hitRegion, .elementDetection, .sufficientElementDescription, .trait])`) | ❌ Wave 0 |
| IOS-04 | Distinguish local/syncing/conflict/auth-expired/unrecoverable states | State-matrix XCUITest against injected fixture states, physical-device confirmation | `xcodebuild test ... -only-testing:KeeplingUITests/SyncStateMatrixTests` | ❌ Wave 0 |
| SRV-02 (iPhone adapter proof) | Same domain invariants via Swift adapter | Vector conformance (structural, D-15) + real-server contract test | `xcodebuild test ... -only-testing:KeeplingCoreTests/SyncVectorConformanceTests`; real-stack lane analogous to `tooling/verify-real-stack-desktop.mjs` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** Quick run — pure-Swift `KeeplingCoreTests` on the simulator (no UI, seconds-scale, mirrors `apps/desktop`'s fast lane).
- **Per wave merge:** Full simulator suite including `KeeplingUITests` and the accessibility audit matrix.
- **Phase gate:** Full suite green on simulator AND the physical-device lane (`xcodebuild test -destination 'platform=iOS,id=<UDID>'` + `devicectl`) green before `/gsd-verify-work`, per D-20's two-lane split.

### Wave 0 Gaps

- [ ] `apps/ios/project.yml` — XcodeGen project definition; nothing in `apps/ios` besides `README.md` exists yet [VERIFIED: `ls /Users/jon/projects/keepling/apps/ios` — only `README.md` present, run 2026-09-04]
- [ ] `apps/ios/Package.swift` — `KeeplingCore` SPM package
- [ ] `apps/ios/Tests/KeeplingCoreTests/VectorConformanceTests.swift` — covers SRV-02 iPhone adapter proof and D-15
- [ ] `apps/ios/Tests/StorageTests/` — covers IOS-02, the G1–G8 gates
- [ ] `apps/ios/Tests/KeeplingUITests/` — covers IOS-01, IOS-03, IOS-04
- [ ] `tooling/verify-ios-phase.mjs` — phase-gate entry point mirroring `tooling/verify-desktop-phase.mjs`'s `runLane`/`inputDigestFor` pattern [VERIFIED: tooling/verify-desktop-phase.mjs:1-95 — read this session; the `runLane` helper requires every lane to report a positive case count or fail, with `spawnSync`, tracked-input digests, and no "assume it passed" fallback — this exact contract should be reused for the iOS gate]
- [ ] `packages/contracts/vectors/manifest.json` — D-15's cross-consumer coverage gate, touches Elixir/TypeScript/Swift harnesses together
- [ ] Framework install: none needed beyond Xcode itself; GRDB and swift-openapi-generator are added via `Package.swift`/generator CLI as part of Wave 0 scaffolding

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-------------------|
| V2 Authentication | yes | Device-grant PKCE flow already implemented server-side (Phase 2); iOS stores tokens in Keychain, never UserDefaults/plist |
| V3 Session Management | yes | Refresh-token rotation with replay detection already server-owned (Phase 2 D-decisions); iOS must fence local intent on sign-out (D-copywriting "Sign out" row) |
| V4 Access Control | no (client) | Server-owned; iOS never makes an authorization decision locally |
| V5 Input Validation | yes | Generated Swift DTOs from the (normalized, D-13) OpenAPI contract enforce shape; task titles/notes render as untrusted plain text only (UI-SPEC: "never interpreted as markup") |
| V6 Cryptography | yes | Rely on iOS Data Protection + Keychain `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (D-08) — never hand-roll crypto; explicitly no SQLCipher (D-08, honestly disclosed) |
| V8 Data Protection | yes | `.completeUntilFirstUserAuthentication` file protection on the store (D-04 G7); backup exclusion (`isExcludedFromBackup`, D-09) plus replay-no-op proof as belt-and-braces |
| V9 Communication | yes | URLSession over HTTPS to the existing bearer-authenticated API; no new transport surface |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|----------------------|
| Restored/duplicated iCloud or iTunes backup replaying a stale outbox into a fenced account | Repudiation / Elevation of Privilege | D-9's adversarial fixture: server-side mutation-identity + fingerprint checking makes replay a no-op even if backup exclusion is somehow bypassed |
| Cross-process SQLite corruption via App Group container (`0xDEAD10CC`) | Denial of Service | D-07: keep store in app container only; no Share Extension/widget until storage is redesigned (D-36) |
| Token/credential leakage into on-device diagnostics or App Intent metadata | Information Disclosure | D-23: diagnostics carry no task content; structured logs keyed by operation identity/state/error class only |
| Nullable-`anyOf` decode defect silently accepting malformed/null server payloads as a different variant (first-match-wins `oneOf`) | Tampering (client trusts wrong parsed shape) | D-13's discriminator addition to `SyncFeedEnvelope.payload` and `ActivityChange` — resolves the structural ambiguity, not just the nullable defect |
| Expired/invalid bearer token silently retried instead of surfaced | Repudiation | D-context: 401 is its own tagged state (inherited Phase 3 pattern), never collapsed into a per-mutation rejection |

## Sources

### Primary (HIGH confidence)
- Live toolchain probes on this Mac: `xcodebuild -version`, `xcrun --sdk iphoneos --show-sdk-version`, `swift --version`, `which xcodegen tuist`, `xcrun simctl list devicetypes` — run 2026-09-04, this session.
- `apps/desktop/migrations/0001_initial.sql` and `0002_outbox_state.sql` — read in full this session; ground truth for the schema iOS's D-35 tables must mirror.
- `tooling/verify-desktop-phase.mjs` — read this session; the `runLane`/`inputDigestFor` pattern the iOS gate should reuse.
- `apps/desktop/test/application/sync-vectors.test.ts` — read this session; the model for the Swift vector-conformance harness.
- `.planning/phases/KPL-04-native-iphone-daily-loop/04-CONTEXT.md` and `04-UI-SPEC.md` — the authoritative, already-locked decision set for this phase.
- `developer.apple.com/documentation/AppIntentsTesting` — official Apple documentation.

### Secondary (MEDIUM confidence)
- github.com/apple/swift-openapi-generator/issues/286 — official upstream issue tracker, confirms D-13's nullable-`anyOf` defect claim.
- developer.apple.com/forums/thread/803404 — Apple DTS engineer response confirming `tabViewBottomAccessory` has no supported hide API as of iOS 26.1.
- github.com/groue/GRDB.swift README — WAL/migration/foreign-key patterns.
- cameroncooke/XcodeBuildMCP documentation (via WebSearch) — `xcodebuild`/`devicectl` UDID-vs-identifier distinction.

### Tertiary (LOW confidence)
- GRDB.swift exact latest version (7.11.1) and swift-openapi-generator exact version (1.10.2) — surfaced via WebSearch/training-adjacent lookups, not independently cross-checked against a release-tag list this session; both flagged `[ASSUMED]` in the Assumptions Log and must be re-verified at execute time.

## Metadata

**Confidence breakdown:**
- Standard stack: MEDIUM — architecture and library *choice* is HIGH (already locked in CONTEXT.md, independently corroborated by official sources), but exact version pins are LOW/ASSUMED pending a fresh registry check at execute time.
- Architecture: HIGH — directly mirrors the already-shipped, already-verified Phase 3 desktop patterns (migrations, vector conformance, phase-gate script structure), all read from source this session.
- Pitfalls: MEDIUM-HIGH — the three headline pitfalls (`tabViewBottomAccessory` hide bug, nullable-`anyOf` decoder defect, `xcodebuild`/`devicectl` identifier mismatch) are each confirmed via an official or semi-official source (Apple forum/DTS response, upstream GitHub issue, established tooling documentation), not speculation.

**Research date:** 2026-09-04
**Valid until:** ~2026-10-04 (30 days) for architecture/pattern claims; **~2026-09-11 (7 days) for the `tabViewBottomAccessory` bug status specifically** — this is an actively-tracked Apple Feedback item that could be resolved in a point SDK update at any time, and the planner should re-check before committing to a workaround strategy if execution starts more than a week after this research.
