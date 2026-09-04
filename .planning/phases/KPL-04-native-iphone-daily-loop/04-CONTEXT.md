# Phase 4: Native iPhone Daily Loop - Context

**Gathered:** 2026-09-04
**Status:** Ready for UI specification, research, and planning

<domain>
## Phase Boundary

Deliver Keepling for iPhone as a native, installed SwiftUI client for the supported personal GTD loop: capture, Inbox, Today, edit, complete/reopen, Trash/restore, and undo through deliberate native touch. The client must own its own durable local projection and immutable outbox, commit them atomically before reporting success, survive process termination and relaunch, reconcile exact acknowledgements without duplication or silent overwrite, preserve account fencing, and present conflicts, authentication expiry, and unrecoverable states in the same calm human language the Mac client uses.

Phase 4 owns the Xcode/SwiftPM project under `apps/ios`, the Swift client orchestration (reducer, outbox, cursor, conflict handling), the local persistence adapter and its migration ledger, the generated Swift transport client and its mappers, native navigation/gesture/accessibility behavior, the iPhone presentation of the locked sync-state vocabulary, App Intents declared in the main target, the code-signing and device-install path, and the simulator plus physical-device evidence lanes.

Phoenix/PostgreSQL remains canonical and owns authorization, invariants, mutation idempotency, revisions, and the ordered synchronization feed. This phase does not make background execution, network availability, or any OS scheduling behavior part of correctness. It does not ship app extensions, widgets, Control Center controls, OS notifications, or reminders.

</domain>

<decisions>
## Implementation Decisions

### Local persistence adapter and iOS floor

- **D-01:** Use **GRDB.swift** behind a narrow `LocalStorePort` as the local store adapter, and **commit to it up front** rather than running an open adapter bake-off. The Phase 3 D-33 open selection was justified because `node:sqlite` was a genuinely unproven runtime capability; GRDB is an eleven-year-old MIT library with zero transitive dependencies that links system SQLite, ships in Signal iOS and DuckDuckGo, and never hides SQL — so its failure mode is escapable in place. — **Reversibility:** reversible — GRDB and the raw `sqlite3` C API produce identical SQLite files and consume identical SQL, so the migration ledger, table DDL, and every retained fixture port unchanged; only the connection/transaction wrapper is rewritten.
- **D-02:** **SwiftData is rejected** as the adapter and is explicitly **not** the fallback. Its store schema is Core-Data-owned and opaque (`Z`-prefixed tables, nullable FKs, no `STRICT`, no user-declared foreign keys), so D-35's nine strict tables with asserted foreign keys are **not expressible**. Its `VersionedSchema` checksums are Apple-owned and opaque, and the community remedy for a failed `ModelContainer` initialization is to delete the store, so D-37's "reject checksum drift and never auto-reset" is **not expressible**. `@Model` classes are reference types that structurally pull persistence records into view models, violating D-30. The requirement is not "atomic writes" — it is *provable* atomicity across nine named tables plus a checksummed forward-only ledger that halts rather than resets, and SwiftData can express one of those three. — **Reversibility:** one-way if adopted — exiting SwiftData means rewriting every row through an opaque store with no fixture lineage, which is why it is refused now rather than later.
- **D-03:** Mirror the Phase 3 storage invariants verbatim on iPhone: separate `STRICT` tables for namespace metadata, canonical shadow, visible projection, immutable command bytes/fingerprint, mutation journal, dependency edges, outbox, cursor, and conflicts (D-35); one `BEGIN IMMEDIATE` transaction for local mutation acceptance with `local_saved` emitted only after commit (D-36); an ordered immutable-SQL `schema_migrations(version, checksum, applied_at)` ledger that rejects drift and never auto-resets (D-37); WAL with one writer, finite busy handling, `synchronous=FULL`, and db + `-wal` + `-shm` treated as one durable unit (D-38); and no meaningful store work on the main thread (D-34).
- **D-04:** Run the adapter spike as a **one-sided acceptance gate**, not a selection. It can only pass or trigger the predeclared fallback. Gates:
  - **G1 Schema expressiveness** — all nine D-35 tables created `STRICT`, foreign keys asserted, `PRAGMA foreign_keys=ON` verified per connection, `integrity_check` and `foreign_key_check` clean.
  - **G2 Atomic acceptance** — local acceptance is exactly one `BEGIN IMMEDIATE`…`COMMIT` spanning projection, command bytes, journal, dependency edges, and outbox; the single-transaction claim is asserted through commit/rollback hooks, not inferred.
  - **G3 Crash recovery** — `SIGKILL` at N injected points inside the write; relaunch asserts no partial acceptance and no orphan outbox row; the durable unit moves and is retained as one unit.
  - **G4 Migration ledger** — own `schema_migrations` ledger; checksum drift and mid-apply failure both halt into the IOS-04 `unrecoverable` state; a build-time test proves `eraseDatabaseOnSchemaChange` appears nowhere in the tree; retained fresh-create and forward-migration fixtures per shipped lineage.
  - **G5 Threading** — debug precondition that no store work runs on the main thread; main-thread checker clean.
  - **G6 Durability posture** — WAL, `synchronous=FULL`, and finite busy timeout verified by PRAGMA readback at open.
  - **G7 Data protection** — on a physical device with a passcode set, the store file is `.completeUntilFirstUserAuthentication` (explicitly **not** `.complete`), and a background write while locked is proven not to take `SQLITE_IOERR` / `0xdead10cc`.
  - **G8 Settlement** — terminal acknowledgement verifies mutation identity and fingerprint, applies canonical/conflict state, terminalizes the journal, recomputes the projection, and deletes the exact outbox row in one transaction; duplicate replay is a no-op.
- **D-05:** The predeclared fallback is the **raw `sqlite3` C API** via system `libsqlite3.tbd` behind the same `LocalStorePort`. Its exact trigger: any of G1–G6 failing on the pinned Xcode/Swift toolchain, GRDB failing to build against that toolchain, or upstream going unmaintained (no release *and* no maintainer response to a filed correctness issue across two OS majors).
- **D-06:** Set the deployment floor at **iOS 26**. Choosing GRDB dissolves OQ-004's coupling entirely — GRDB supports iOS 13+, so nothing persistence-related rides on the floor and it becomes a pure SwiftUI/accessibility decision. iOS 26 is roughly 86.6% of active devices as of August 2026, has mature Observation, settled App Intents/ScenePhase/List/accessibility APIs, the current design system, and a released Xcode. iOS 27 has been public beta only since 2026-08-31 at approximately zero install base; producing release-grade migration and crash evidence on a beta toolchain is not reversible, whereas raising a floor later is. **This closes OQ-004.**
- **D-07:** Keep the database in the **app container, not an App Group container**. SQLite in a shared group container is a documented corruption and jetsam hazard, and no Phase 4 surface requires cross-process store access.
- **D-08:** At-rest posture: **no SQLCipher**. Rely on iOS file protection for the store and Keychain `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` for credentials, and state honestly what that does and does not protect — the same disclosure discipline as Phase 3 D-25. — **Reversibility:** costly — adding SQLCipher later is a mechanical whole-file re-encrypt, but removing it once shipped is not.
- **D-09:** Mark the store's durable unit (`db`, `-wal`, `-shm`) `isExcludedFromBackup` **and** separately prove that server mutation-identity plus fingerprint checking makes any replay a no-op. An iCloud or iTunes restore is a stale-outbox replay vector that can resurrect commands into a fenced account; belt and braces means a restored iPhone starts from a clean local store and re-bootstraps from the server, and even a hand-restored store cannot double-apply. Carry this as an explicit IOS-02 adversarial fixture. — **Reversibility:** costly — the backup-exclusion flag is trivially reversible, but the replay-no-op proof is the thing that makes either posture safe and must exist regardless.

### Client orchestration, transport, and conformance

- **D-10:** **Reimplement the sync orchestration natively in Swift**, gated on the shared golden vectors. The vectors already have two independent consumers — `apps/server/lib/keepling/application/sync/reference_model.ex` and `apps/desktop/test/application/sync-vectors.test.ts` — so Swift is the **third**, not the second. N-version agreement against a shared specification is stronger correctness evidence than one shared binary, which would replace independent corroboration with a single point of uniform wrongness that no conformance suite could detect. This ratifies `docs/architecture/REPOSITORY.md`'s stated duplication position on evidence, not on assertion.
- **D-11:** **No shared FFI core in Phase 4.** A Rust/UniFFI (or KMP, or WASM) core owns almost nothing unless it also owns persistence, which would reverse D-26 and D-30; it adds a fourth toolchain, cross-compiled binary artifacts, and a new supply chain to a repository whose rule is native tools first and shallow dependency trees; and the teams that succeed with it (Signal's libsignal, Mozilla's application-services) run full-time Rust plus per-platform teams, while the solo-maintainer base rate is Dropbox's C++ retreat. Revisit only when N=4 consumers exist (MCP in Phase 5, plus the `apps/android` stub) **and** a post-mortem shows at least two semantic bugs fixed independently in at least two runtimes — and then extract the pure reducer only, never storage or transport. — **Reversibility:** reversible now, one-way later — extraction is cheap before persistence sits behind the boundary and very expensive after.
- **D-12:** Produce the Swift wire client with **apple/swift-openapi-generator run as a CLI, with the generated output committed to the repository**, mirroring the already-committed `packages/contracts/generated/keepling.ts`. Committed output is diff-reviewable (a build plugin's output is not), makes builds deterministic and offline, and avoids Xcode build-tool-plugin trust prompts and `-skipPackagePluginValidation` friction. Use a URLSession transport and hand-written mappers from wire DTO to client model; generated DTOs never become persistence records (D-30).
- **D-13:** **Normalize the contract before generating** — this is a prerequisite, not a nice-to-have. `packages/contracts/openapi/keepling.yaml` uses `anyOf: [X, {type: 'null'}]` in 35 places, and that nullable-`$ref` cluster is an open, milestone-blocked generator defect (apple/swift-openapi-generator#286, "did not decode into any child schema"). Separately, five of the six `oneOf`s carry no `discriminator`, so decoding is first-match-wins across structurally overlapping variants such as `SyncTaskSnapshot` versus `SyncOrganizationSnapshot`. Required changes: rewrite the 35 nullable sites as OpenAPI 3.1 unions `type: [X, 'null']`, and add `discriminator` to the `SyncFeedEnvelope.payload` and `ActivityChange` oneOfs. This is contract hygiene with no semantic change and it benefits the TypeScript consumer too. — **Reversibility:** costly — the contract is a released compatibility surface, so changes go through the project's expand/migrate/age-out/contract discipline even when semantically neutral.
- **D-14:** Add a **decode round-trip test over every wire payload appearing in the 13 vector files**, so a generator regression fails CI rather than failing on a phone.
- **D-15:** Make vector conformance **structural, not asserted** — the same instinct as Phase 3's monotonic outbox state:
  - Resolve vector files at test compile time from the source tree via `#filePath` → repository root → `packages/contracts/vectors/*.json`. Do **not** use SwiftPM `.copy` resources; a copy is a drift vector and its paths cannot escape the target directory.
  - Assert `Set(executedCaseNames) == Set(json.cases)` per file, so a skipped or unhandled action type **fails** rather than silently reducing coverage. An unknown `action.type` is an explicit test failure, which the closed vocabulary in `sync-state-machine.schema.json` makes checkable.
  - Add `packages/contracts/vectors/manifest.json` mapping each of the 13 files to its required consumers `[elixir, typescript, swift]`, with one gate that fails if any listed consumer does not execute a file. This is what converts three independent implementations from a divergence liability into corroborating evidence.
  - Regenerate the Swift client in CI and fail on any diff against the committed output.
- **D-16:** The vector schema vocabulary is **one-way once a third consumer exists**. Extend it for iOS lifecycle concerns — background execution, expired authentication, account-switch fencing on resume — as a **versioned addition before Swift is written against it**, never as a v1 mutation afterward. — **Reversibility:** one-way — three runtimes and their retained fixtures bind to the vocabulary, so a v1 mutation would silently invalidate existing Elixir and TypeScript conformance evidence.

### Delivery, signing, and dogfood availability

- **D-17:** **Purchase the Apple Developer Program membership ($99/yr) in Phase 4.** Free personal-team provisioning expires profiles after seven days, at which point the app hard-stops launching — which is precisely the recurring manual step the project forbids, and it fails exactly when it matters most (a week away from the build Mac is when mobile capture matters). The paid membership also unlocks App Groups, keychain access groups, and the Data Protection entitlement, and it is the same signing identity Phase 6 requires, so Phase 4 evidence survives into release instead of repeating the Phase 3 D-25 unsigned-evidence deferral.
- **D-18:** Install to the device by **development-signed direct install via `devicectl`**, using `xcodebuild -allowProvisioningUpdates` so profile management is unattended. This is both the daily dogfood path and the evidence-lane path.
- **D-19:** **Defer TestFlight to Phase 6.** Upload and processing latency plus 90-day build expiry buy no evidentiary value here. TestFlight and the App Store are the Phase 6 public-distribution path, following the Home Assistant and Jellyfin pattern: one official signed app that accepts a user-supplied server URL, with public source.

### Evidence model and honest claims

- **D-20:** Use a **two-lane split**. A fast **simulator lane** is the required gate on every change. A separate **physical-device lane** (`xcodebuild test -destination 'platform=iOS,id=UDID'` plus `devicectl` install/launch/terminate, against real Phoenix on real PostgreSQL through a Mac-hosted forwarding proxy that records arrival order) gates **phase acceptance, not every commit**, with bounded retry and quarantine so its flake can never erode trust in the fast gate. `devicectl device process terminate` is the exact on-device analogue of the Phase 3 hard-kill.
- **D-21:** Bind evidence by **provenance plus read-back attestation**, not by byte reproducibility. iOS artifacts are inherently not byte-reproducible because the CMS code signature carries a timestamp and per-build nonce — this is **not** a packaging defect to be fixed the way 03-25 correctly fixed the Electron build. Instead: record git revision, `xcodebuild -version` and SDK, signing identity fingerprint, provisioning profile UUID, `CFBundleVersion`, the SHA-256 of the exported `.ipa`, an advisory SHA-256 of the `.app` bundle excluding `_CodeSignature/` and `embedded.mobileprovision`, and the lane's own source digest. Inject a `KeeplingBuildDigest` Info.plist key at build time; the device lane reads it back **from the running process on the phone** and refuses the run on mismatch. Identity is proven by attestation, which is what makes stale evidence refusable.
- **D-22:** Bind each success criterion to a named lane and disclose the gap explicitly rather than smuggling in a manual checkpoint:
  - **Criterion 1** (core loop on a physical iPhone) — physical-device XCUITest against the installed signed build. No disclosure needed.
  - **Criterion 2** (offline, termination, relaunch, expired auth, fencing, duplicate replay, conflict) — physical-device lane; auth expiry, fencing, replay, and conflict driven server-side through the recording proxy. Disclose: "OS-initiated jetsam under memory pressure is not induced; termination is proven by signal-based hard kill, which is the stricter no-notice case."
  - **Criterion 3** (background is only acceleration) — structural guarantee plus on-device foreground launch/resume/reconnect restore; background handler logic proven by invoking the same handler with an injected task. Disclose: "Real `BGTaskScheduler` wake scheduling is not asserted — Apple schedules opportunistically and it is not assertable; the claim is that correctness does not require it."
  - **Criterion 4** (Dynamic Type, VoiceOver semantics, touch targets, Reduce Motion) — simulator matrix across content-size categories with `performAccessibilityAudit(for: [.contrast, .dynamicType, .textClipped, .hitRegion, .elementDetection, .sufficientElementDescription, .trait])`, label/trait/value assertions, and ≥44pt frame assertions, plus one device confirmation run. Disclose: "VoiceOver speech output and real screen-reader gesture navigation are not captured; accessibility semantics, audit findings, and rendered layout are."
  - **Criterion 5** (daily use without opening Things) — **not automatable; flagged as such.** Closest automatable proxy: the supported loop is installed on the physical device under a non-expiring profile and every action in it passes the device lane bound to the shipped build. Disclose: "Automation proves the loop is available and correct on the device; sustained daily adoption is owner dogfood feedback, not a gate." D-17 exists precisely to remove the mechanical obstacle to this criterion.
- **D-23:** On-device diagnostics carry **no task content**. Emit structured local logs keyed by outbox operation identity, state transition, and error class only — never titles, notes, drafts, tokens, cursors, or fingerprints — retrievable over USB. This preserves QUAL-05 and D-44 while making a bad day on the phone reconstructable.
- **D-24:** Be honest about CI. This repository has no git remote and no workflow has ever executed (tracked as O-35), so all Phase 4 lanes are Mac-local tooling invoked the way `tooling/verify-desktop-phase.mjs` is. A self-hosted runner with a tethered phone is the eventual shape; **nothing in Phase 4 may depend on CI existing.**

### Navigation, gesture, and touch model

- **D-25:** Use a two-tab `TabView` (**Today**, **Inbox**) with a per-tab `NavigationStack`, list→detail push, and capture presented as a `.sheet` with `.presentationDetents`. Inbox and Today are the only locked destinations, so two tabs is the least-surprising iOS spatial model and keeps both loops one thumb-tap apart. Reject a Things-style single stack rooted on a lists home screen for this phase — it costs a tap on every switch between the two loops used hourly and deepens the focus-restoration surface after row removal. Revisit only when the destination count exceeds roughly four.
- **D-26:** Trailing swipe carries **Complete/Reopen** with `allowsFullSwipe: true`. **Trash never gets full-swipe** — it is reachable through the long-press context menu and the detail view only. The reversible action gets the cheap gesture; the irreversible one never does.
- **D-27:** Every gesture is **mirrored as a named control** in the detail view and in `.accessibilityActions`. There are no gesture-only commands, so Switch Control, Voice Control, and Full Keyboard Access reach everything. This is the touch expression of Phase 3 D-13's rejection of hidden hover-only commands.
- **D-28:** **No pull-to-refresh** and **no drag-to-reorder** in Phase 4. Pull-to-refresh would falsely imply the user can command synchronization correctness, contradicting D-15 and D-16; reordering is not in the phase's locked capability set.
- **D-29:** Use iOS 26's `tabViewBottomAccessory` as the iPhone's status and action strip. It is the native replacement for the single scarcest thing the iPhone lacks relative to the Mac client — a menu bar — and `.tabBarMinimizeBehavior(.onScrollDown)` comes with it.

### Undo on iPhone

- **D-30:** Semantic undo is a **named, persistent "Undo *{Action}*" control** in the conditional bottom accessory, persisting until superseded by the next undoable semantic action or explicitly dismissed — **no timer** — and mirrored as a named item in the nav-bar overflow menu. This is the direct native re-expression of Phase 3 D-12's "semantic undo is a named visible action, not a hidden gesture." — **Reversibility:** costly — the affordance binds to accessibility identifiers, tests, and muscle memory; the documented fallback is overflow-menu-only undo, never a gesture.
- **D-31:** Set `applicationSupportsShakeToEdit = false`. Shake-to-undo is undiscoverable, user-disableable in Settings, and untestable, so it can never carry a locked semantic command.
- **D-32:** Use `UndoManager` **only** for text editing inside capture and detail fields. This preserves the Phase 3 D-12 split in which platform text undo and semantic undo never collide.
- **D-33:** **Reject transient toast/snackbar undo.** Timer-based dismissal is an accessibility failure — VoiceOver and Switch Control users routinely cannot reach it in time — it is unprovable without flake in XCUITest, and it contradicts D-41's requirement that recovery copy durably name the next safe action.
- **D-34:** Undo of an action whose outbox entry has already been accepted by the server must express as a **compensating semantic action**, not a local retraction, and must reconcile through the server-issued handle exactly as the Mac client does.

### Capture surfaces

- **D-35:** **In scope:** the in-app capture sheet (title-first, durable draft per D-11, explicit `Discard Draft` with confirmation when nonempty), `.keyboardShortcut` support for hardware keyboards, and **App Intents for Capture and Complete declared in the main app target**, pinned to main-process execution. Declaring intents in the main target buys Shortcuts, Siri, Action Button, and Spotlight action surfaces for roughly one file, with no new target, no App Group, and no second process touching the store — and they are provable by unit-testing `perform()` directly rather than through unautomatable Siri UI.
- **D-36:** **Deferred:** Share Extension, WidgetKit widget, Control Center and Lock Screen controls, Spotlight-index surfaces, and capture while the app is fully terminated. Extensions are a **storage-architecture decision, not a UI one** — serving them requires moving the store into an App Group container, a documented corruption and jetsam (`0xDEAD10CC`) hazard that Signal published `SQLCipherVsSharedData` about, and a second consumer of a concurrency model Phases 2 and 3 tuned for exactly one process. The honest cost is that **Safari-link capture is the deferral most likely to send Jon back to Things**, which is a real risk to criterion 5; the counterweight is that shipping it here threatens criteria 2 and 3, the trust criteria, and trust is the project's spine. If link capture proves a daily habit during dogfooding, the correct response is a dedicated phase that redesigns store access for multiple processes — not a bolt-on.
- **D-37:** The App Intent must not open a second store handle, and its foregrounding behavior must not strand a durable draft.

### Synchronization state presentation on iPhone

- **D-38:** Present synchronization state through **one conditional `tabViewBottomAccessory`** that is **absent when healthy** and otherwise shows, in strict priority order: actionable exception → undoable action → transient work, the last only after the grace period elapses. This is the exact native re-expression of Phase 3 D-15's hierarchical hybrid, with no persistent chrome and no badge or spinner noise.
- **D-39:** Provide a full-screen **`Sync & Recovery` sheet** as the deliberate-inspection destination, reachable from the accessory strip, from a persistent overflow-menu row on **both** tabs so the path exists even when everything is quiet, and by deep link from any per-task exception row. Per-task exceptions render inline beside the affected task only.
- **D-40:** Reject a persistent status glyph in the navigation bar. A permanently visible synchronization indicator is exactly the ambient-noise pattern D-15 forbids, and it consumes navigation-bar space needed at accessibility Dynamic Type sizes. The overflow-menu row covers the same inspection need silently.
- **D-41:** Every renderer-visible synchronization summary derives from the single authoritative presentation projection (D-16 inherited). The UI infers no synchronization truth of its own.
- **D-42:** Emit **one debounced `AccessibilityNotification.Announcement` per meaningful transition**, debounced at the projection layer rather than per view, with `.high` priority reserved for actionable exceptions. This is the iOS analogue of D-42's single polite live region and its prohibition on announcement storms.
- **D-43:** Phase 3 D-17's copy vocabulary and its named recovery actions (Retry / Review / Choose what to keep / Sign in / Inspect + Export + separately confirmed removal) carry over **unchanged**, with exactly one device-specific substitution: `Saved on this Mac` → **`Saved on this iPhone`**. The Mac's `Sync & Recovery` panel becomes the iPhone's `Sync & Recovery` full-screen sheet. — **Reversibility:** one-way — D-03's trust thresholds are a cross-surface contract, and changing these meanings would make previously accepted states misleading on two clients at once.
- **D-44:** **D-19 holds unchanged: zero OS notifications in Phase 4** — none for routine save, ready, retry, reconnect, prolonged outage, or synchronization, and no reminders or scheduled local notifications of any kind. Status stays in-product and privacy-safe, exactly as on Mac. This keeps the push entitlement, the notification permission prompt, and the associated privacy surface entirely out of this phase. Reminders and any user-configurable high-value notification become their own later phase. Note explicitly: an earlier architecture snapshot cited "native reminders" among the reasons native iOS beat a PWA — that remains a valid long-term reason for the platform choice and is **not** a Phase 4 scope grant.

### Design, accessibility, and inherited contracts

- **D-45:** Inherit the Phase 1 and Phase 3 semantic design contracts — semantic colors, typography intent, spacing rhythm, plain-text rendering, focus safety, conflict/recovery component meaning, and copy voice — and create iPhone-specific density and layout aliases only through the Phase 4 UI contract. Native feel outranks pixel parity with the Mac or web surfaces, but shared component meaning and state semantics may not drift.
- **D-46:** Generate a **Swift token output** from `packages/design-tokens/tokens.json`, which currently emits CSS only. The architecture document already anticipates "source plus generated CSS/Swift."
- **D-47:** Follow system light/dark appearance and apply changes while running; preserve non-color state cues, Increase Contrast, Differentiate Without Color, Reduce Transparency, and Reduce Motion alternatives. Concentrate brand in the icon, selection, empty-state tone, and a few meaningful moments rather than repainting native chrome (D-08 inherited).
- **D-48:** Accessibility is release evidence, not a checklist. Prove it with `performAccessibilityAudit` on every supported screen plus snapshot tests across accessibility Dynamic Type sizes, `accessibilityReduceMotion`, and `accessibilityDifferentiateWithoutColor` environment overrides, and assert safe focus after row removal and sheet dismissal.
- **D-49:** Explicitly rejected anti-patterns: gesture-only destructive actions; full-swipe on an irreversible action; pull-to-refresh implying user-triggered correctness; toast-only undo; per-task healthy badges or perpetual spinners; a second process writing the store from an App Group container; OS notifications for routine synchronization; and cargo-culting Mac keyboard semantics onto touch.

### Claude's Discretion

- Exact grace-period duration, backoff constants, and accessory-strip animation timing, within the locked state meanings and the Reduce Motion requirement.
- The precise priority-arbitration contract between the undo control and actionable sync exceptions in the shared accessory slot, and the layout arbitration between the accessory and any capture affordance in the bottom-trailing thumb zone.
- The exact "until superseded" lifetime rule for the undo control (per-list versus global scope).
- Swift module and target decomposition under `apps/ios`, provided the pure reducer is a separate target testable without UI and the store adapter sits behind `LocalStorePort`.
- The specific injected `SIGKILL` points for G3 and the exact fixture lineage retained for G4, provided coverage is adversarial rather than illustrative.
- Sheet detent choices, iconography, and empty-state composition within the inherited semantic and brand contracts.
- Whether the physical-device lane runs as a sub-lane of a single `verify-ios-phase.mjs`-style entry point or as a separately invoked script, provided evidence binding and refusal-on-mismatch behave as D-21 specifies.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Product, scope, and requirements

- `.planning/PROJECT.md` — product promise, constraints, platform commitments, and the personal dogfood success criterion.
- `.planning/REQUIREMENTS.md` — IOS-01 through IOS-04 and the Phase 4 slice of SRV-02.
- `.planning/ROADMAP.md` — fixed Phase 4 goal and its five success criteria; Phase 6 owns release posture and cross-client verification.
- `.planning/knowledge/OPEN-QUESTIONS.md` — OQ-004 (iOS floor and SwiftData sufficiency), **closed by D-06 and D-01/D-02 in this document**.
- `.planning/knowledge/DECISIONS.md` — D-005 supersedes PWA-first with Electron Mac plus native SwiftUI iPhone.
- `.planning/research/SUMMARY.md` — normalized platform, dependency, and quality posture.

### Architecture and prior-phase decisions

- `docs/architecture/REPOSITORY.md` — monorepo boundaries, dependency direction, the deliberately-shared versus deliberately-duplicated lists, the prohibition on a universal domain package, and the native-tools-first rule.
- `.planning/knowledge/snapshots/2026-08-28-platform-and-architecture.md` — native SwiftUI rationale, background-execution limits, the layering diagram, and the pre-existing note that the iOS floor and persistence adapter were phase decisions.
- `.planning/phases/KPL-03-mac-daily-loop/03-CONTEXT.md` — **D-01 through D-48**, the direct antecedent of nearly every decision here. D-03 trust thresholds, D-15 through D-19 sync presentation and copy, D-26 through D-32 client architecture, D-33 through D-38 storage invariants, D-39 through D-42 design and accessibility, D-43 through D-48 performance, privacy, and proof.
- `.planning/phases/KPL-02-synchronization-and-replaceable-server/02-CONTEXT.md` — synchronization, fencing, compatibility, recovery, state, privacy, and user-language decisions.
- `.planning/phases/KPL-02-synchronization-and-replaceable-server/02-01-SUMMARY.md` — reference reducer, durable queue and dependency model, storage-neutral vector proof.
- `.planning/phases/KPL-02-synchronization-and-replaceable-server/02-03-SUMMARY.md` — installation grants and the five-field account/server namespace fencing tuple.
- `.planning/phases/KPL-02-synchronization-and-replaceable-server/02-11-SUMMARY.md` — native PKCE authorization-code flow, opaque credential rotation, installation revocation, and server-derived bearer namespace. `client_id=iphone` is already contemplated here.
- `apps/ios/README.md` — the existing stub stating that the iPhone client independently implements durable local projection/outbox behavior against shared golden vectors.

### Contracts, vectors, and reference implementations

- `packages/contracts/openapi/keepling.yaml` — released wire operations and closed DTO/error contracts. **Requires the D-13 normalization before Swift generation.**
- `packages/contracts/generated/keepling.ts` — the committed-generated-output precedent the Swift client mirrors.
- `packages/contracts/schemas/sync-state-machine.schema.json` — closed reference synchronization vocabulary; makes unknown-action-type failure checkable.
- `packages/contracts/vectors/` — all 13 golden vector files (`sync`, `conflicts`, `undo`, `recovery`, `lifecycle`, `editing`, `trash-restore`, `task-dates`, `activity`, `organizations`, `compatibility`, `account-lifecycle`, `redaction`).
- `apps/server/lib/keepling/application/sync/reference_model.ex` — the Elixir vector consumer; first independent implementation.
- `apps/desktop/test/application/sync-vectors.test.ts` — the TypeScript vector consumer; second independent implementation and the model for the Swift harness.
- `apps/server/test/support/sync_scenario.ex` — server-side scenario support.

### Desktop precedent for evidence and orchestration

- `tooling/verify-desktop-phase.mjs` — the 11-lane phase gate whose structure the iOS gate mirrors.
- `tooling/verify-real-stack-desktop.mjs` — the real-Phoenix/real-PostgreSQL lane with the forwarding proxy that records arrival order.
- `tooling/smoke-desktop-packaged.mjs` and `tooling/package-desktop.mjs` — the manifest-and-digest binding pattern that D-21 adapts to attestation.
- `tooling/verify-macos-integration.mjs` and `tooling/macos-integration/` — the real-OS row-based evidence lane.
- `docs/testing/desktop-testing.md` and `docs/testing/desktop-dogfood.md` — the testing-layer doctrine and dogfood evidence conventions.

### Design and brand

- `docs/brand/BRAND-SEED.md` — brand authority for calm agency, earned trust, voice, color territory, typography, motion, and native restraint.
- `packages/design-tokens/tokens.json` — DTCG semantic token source; **Phase 4 adds the Swift output** (D-46).
- `.planning/phases/KPL-01-one-trustworthy-task/01-UI-SPEC.md` — approved semantic design, component, copy, focus, and accessibility contracts to inherit.
- `.planning/phases/KPL-03-mac-daily-loop/03-UI-SPEC.md` — the Mac design contract, including its per-dimension evidence table convention added by 03-27.

### Presentation semantics worth reading, not porting

- `apps/web/src/features/recovery/RecoveryStrip.tsx` — persistent recovery-action presentation.
- `apps/web/src/features/tasks/ConflictResolver.tsx` — user-visible structured conflict resolution.
- `apps/web/src/features/capture/QuickCapture.tsx` — capture behavior and exact-delivery recovery seam.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **Golden vectors (13 files) plus the closed state-machine schema** — already proven runtime-neutral by two independent consumers. These are the primary reusable asset of this phase and the mechanism by which Swift correctness is gated rather than asserted.
- **`packages/contracts/openapi/keepling.yaml`** — a complete released wire contract, so no API design work is required; only the D-13 normalization and Swift generation.
- **Phase 3's storage DDL, migration ledger design, and adversarial fixture catalogue (D-48)** — the SQL and the fixture *scenarios* port to GRDB nearly unchanged even though no code is shared, which is what makes GRDB lower-risk than SwiftData for a Swift novice.
- **`packages/design-tokens/tokens.json`** — semantic visual intent already expressed in a DTCG source; Phase 4 adds a Swift emitter rather than re-deciding the palette.
- **The desktop tooling pattern** — `verify-desktop-phase.mjs` and its sub-lanes are a working template for a `verify-ios-phase` entry point, including refusal-on-stale-evidence and non-vacuity measurement.
- **Phase 2 device-grant transport** — PKCE authorization code, refresh rotation with replay detection, per-installation revocation, and the five-field namespace tuple already exist server-side with `client_id=iphone` contemplated.

### Established Patterns

- Server domain and application rules remain independent of transport, records, generated clients, UI, and client persistence. The iPhone must not clone Elixir domain invariants or infer canonical acceptance locally.
- Four deliberate representations with explicit mappers, and generated DTOs never becoming persistence records.
- Immutable commands, fingerprints, stable mutation identities, exact terminal acknowledgements, structured conflicts, and ordered feed coverage all already exist and are the contract the Swift client implements against.
- Correctness properties are made **structural** where possible rather than asserted in a test — Phase 3's monotonic outbox transmission state is the model, and D-15's set-equality coverage assertion is its Phase 4 analogue.
- Evidence is bound to an artifact and stale evidence is refused rather than reused; disclosures state exactly what a checkmark does and does not prove.
- Tests use deterministic clocks, identities, and injected faults, and treat user-visible or server-read state as truth rather than a client-side status label.

### Integration Points

- Create the Xcode/SwiftPM project under `apps/ios` (currently a README only). Keep it outside the pnpm workspace graph per the native-tools-first rule.
- Consume `packages/contracts/openapi/keepling.yaml` through committed generated Swift; consume `packages/contracts/vectors/*.json` directly from the source tree in the conformance target.
- Attach to the existing bearer-authenticated compatibility, bootstrap, feed, and command APIs; register `client_id=iphone` against the Phase 2 device-grant flow.
- Add `packages/contracts/vectors/manifest.json` and the cross-runtime consumer gate, which touches the Elixir and TypeScript harnesses as well as Swift.
- Extend `packages/design-tokens` with a Swift emitter alongside the existing CSS output.
- Add an iOS phase-gate entry point in `tooling/` following the desktop precedent, plus a device-lane script wrapping `xcodebuild` and `devicectl`.

</code_context>

<specifics>
## Specific Ideas

- **The N-version argument is the spine of D-10.** The vectors already have two agreeing independent consumers; a shared binary core would *replace* independent corroboration with a single point of uniform wrongness that no conformance suite could ever detect. Duplication here is an evidence strategy, not merely a convenience.
- **GRDB is chosen partly because it never hides SQL.** For a maintainer who is not a Swift specialist, an escapable library whose semantics match the ones he already wrote adversarial fixtures against is lower-risk than an Apple framework whose store schema and migration checksums he cannot inspect.
- **Signal's `SQLCipherVsSharedData` writeup** is the direct evidence behind D-07 and D-36: SQLite in an App Group container is a documented corruption and jetsam class, which is why extensions are treated as a storage decision rather than a UI decision.
- **`tabViewBottomAccessory` is the menu-bar replacement.** It is the only iPhone surface that can be genuinely *absent* when healthy and still appear in a fixed, learnable place when something is actionable — which is the whole of D-15.
- **App Intents in the main target are the high-leverage capture move** — Shortcuts, Siri, Action Button, and Spotlight for roughly one file, with no new process and unit-testable `perform()`.
- **iOS builds are not byte-reproducible and that is not a defect.** The CMS signature carries a timestamp and nonce. Attestation-by-read-back is the honest substitute for Phase 3's digest binding, and the distinction should be stated plainly rather than papered over.
- **Criterion 5 is honestly not automatable.** The plan says so out loud and buys the Apple Developer Program specifically to remove the mechanical obstacle (profile expiry) to the adoption it cannot test.
- **Safari-link capture is the acknowledged weak point.** It is the deferral most likely to send Jon back to Things, and the plan records that trade openly rather than pretending the gap does not exist.
- Reference products consulted for the interaction model: Things for iPhone (Magic Plus, quick find, swipe semantics, Today/Inbox model, and its own release-note lessons), OmniFocus, Todoist, Apple Reminders, Bear, Linear mobile, and Ivory — with particular attention to how each handles undo on a phone, since that is the weakest analogue from the Mac phase.

</specifics>

<deferred>
## Deferred Ideas

- **Share Extension** for Safari and cross-app link capture — the single most-missed deferral. Belongs in its own phase that redesigns store access for multiple processes (App Group container, cross-process SQLite locking, credential exposure to a lower-trust process), not a bolt-on to Phase 4.
- **WidgetKit widget, Control Center and Lock Screen controls, Spotlight-index surfaces**, and capture while the app is fully terminated — same reasoning: each is a separate process with its own view of the store and credentials, and each is effectively unprovable without human UAT.
- **OS notifications and task reminders** — D-19 holds unchanged (D-44). Reminders remain a valid long-term reason for the native platform choice but are not a Phase 4 scope grant; they need their own phase with a permission flow, lifecycle-tied scheduling and cancellation semantics, and their own accessibility and privacy surface.
- **TestFlight and App Store distribution** — Phase 6, following the Home Assistant / Jellyfin pattern of one official signed app accepting a user-supplied server URL.
- **Drag-to-reorder and user-defined ordering** on iPhone — not in the phase's locked capability set; revisit when ordering becomes a product capability rather than a list affordance.
- **Additional destinations beyond Inbox and Today** (Upcoming, Anytime, Someday, projects as top-level destinations) — the two-tab model is chosen for exactly two locked destinations; revisit the navigation model when the count exceeds roughly four.
- **Shared FFI core (Rust/UniFFI) for the reducer** — revisit only at N=4 consumers (after MCP in Phase 5 and any Android work) **and** only if a post-mortem shows at least two semantic bugs fixed independently in at least two runtimes. Extract the pure reducer only, never storage or transport.
- **SQLCipher / application-layer database encryption, biometric app lock, cryptographic erasure, remote wipe** — Phase 4 documents the honest file-protection and Keychain baseline and keeps the credential port replaceable.
- **iPad and Mac Catalyst layouts** — iPhone is the Phase 4 proof target.
- **Self-hosted CI runner with a tethered device** — the eventual shape, but O-35 means no workflow has ever run and nothing in Phase 4 may depend on CI existing.

</deferred>

---

*Phase: 4-Native iPhone Daily Loop*
*Context gathered: 2026-09-04*
