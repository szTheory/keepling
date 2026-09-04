# Phase 4: Native iPhone Daily Loop - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-04
**Phase:** KPL-04-native-iphone-daily-loop
**Areas discussed:** Local store + iOS floor, Device proof + dogfood delivery, Swift orchestration reuse, Native touch + capture surface, Backup posture, Notification scope

**Mode:** advisor (USER-PROFILE.md present), calibration tier `minimal_decisive` (`vendor_philosophy: opinionated`), `NON_TECHNICAL_OWNER = false` (`technical_background: true` overrides inferred signals).

**Research:** The user explicitly requested a breadth-and-depth fan-out across stakeholder-role lenses with patterns/anti-patterns/footguns, external product and ecosystem research, and an adversarial pass before synthesis. Four `gsd-advisor-researcher` agents ran in parallel, one per selected area, and their findings were synthesized against project context before presentation.

---

## Area 1 — Local store + iOS floor

| Option | Description | Selected |
|--------|-------------|----------|
| GRDB + iOS 26, gate not bake-off | GRDB.swift behind `LocalStorePort` committed up front; spike becomes a one-sided G1–G8 acceptance gate whose only outcome is pass or fall back to raw `sqlite3` C API. SwiftData excluded as adapter and as fallback. iOS 26 floor. No SQLCipher. DB in app container. Closes OQ-004. | ✓ |
| Same, but keep the D-33 bake-off | GRDB presumptive, but the spike can genuinely re-open the choice as Phase 3 did for `node:sqlite`. | |
| Same, but iOS 27 floor | Take the beta toolchain for newer SwiftUI perf and toolbar APIs. | |

**User's choice:** GRDB + iOS 26, gate not bake-off.

**Notes:** The decisive framing was that the requirement is not "atomic writes" but *provable* atomicity across nine named `STRICT` tables plus a checksummed forward-only ledger that halts rather than resets — and SwiftData can express only the first of those three. Its store schema and migration checksums are Apple-owned and opaque, and the community remedy for a failed `ModelContainer` init is to delete the store, so D-37's "never auto-reset" is not expressible at all. `@Model` reference types also drag persistence records into view models against D-30.

The bake-off was dropped because D-33's open selection on Electron was justified by `node:sqlite` being an unproven runtime capability, whereas GRDB is eleven years old, MIT, zero-transitive-dep, and never hides SQL — so its failure mode is escapable in place. Choosing GRDB (iOS 13+) also dissolved OQ-004's coupling entirely, turning the floor into a pure SwiftUI/accessibility decision. iOS 27 was rejected as a public beta at ~0% install base since 2026-08-31: shipping release-grade migration and crash evidence on a beta toolchain is not reversible, while raising a floor later is.

Two findings surfaced by research and folded into CONTEXT.md: device backup as a stale-outbox replay vector (became its own question below), and the `.complete` vs `.completeUntilFirstUserAuthentication` file-protection distinction, where the stricter class causes `0xdead10cc` on background writes.

---

## Area 2 — Device proof + dogfood delivery

| Option | Description | Selected |
|--------|-------------|----------|
| Buy ADP now; two-lane evidence | $99/yr Apple Developer Program in Phase 4; development-signed direct install via `devicectl`; TestFlight deferred to Phase 6. Fast simulator lane (required) + physical-device lane gating phase acceptance with bounded retry/quarantine. Provenance binding + `KeeplingBuildDigest` read-back attestation instead of byte reproducibility. Criterion 5 flagged non-automatable with disclosure. | ✓ |
| Free provisioning + launchd treadmill | Stay at $0; nightly automated rebuild/reinstall absorbs the 7-day expiry. | |
| ADP now, but simulator-only evidence | Buy the membership for dogfooding, defer all device lanes to Phase 6. | |

**User's choice:** Buy ADP now; two-lane evidence.

**Notes:** The free path's 7-day profile expiry hard-stops the app from launching, which is precisely the recurring manual step the project's zero-human-UAT rule forbids — and it fails exactly when mobile capture matters most (a week away from the build Mac). $99/yr is the cheapest deletion of a manual checkpoint anywhere in the project, and it is the same signing identity Phase 6 needs, so Phase 4 evidence survives into release rather than repeating the Phase 3 D-25 unsigned-evidence deferral. Simulator-only was rejected because IOS-04 and criterion 1 say "on a physical iPhone" in so many words, so a simulator-only phase could not make its own headline claim.

A significant correction to the Phase 3 analogy emerged: iOS artifacts are **not** byte-reproducible because the CMS code signature carries a timestamp and per-build nonce. This must not be treated as a packaging defect the way 03-25 correctly treated the Electron build; the honest substitute is provenance binding plus `KeeplingBuildDigest` read-back attestation from the running process on the phone.

Criterion 5 ("daily use without opening Things") was explicitly identified as **not automatable** — an adoption outcome, not a testable claim — with the closest automatable proxy and its disclosure language recorded in CONTEXT.md D-22.

---

## Area 3 — Swift orchestration reuse

| Option | Description | Selected |
|--------|-------------|----------|
| Native reimpl + generated committed client + contract fix | Swift reducer reimplemented natively as the third vector consumer. `swift-openapi-generator` run as CLI with output committed; mandatory riders normalizing 35 `anyOf`-null sites to OpenAPI 3.1 unions and adding discriminators, plus a decode round-trip test over every vector payload. Conformance via `#filePath` resolution, set-equality coverage assertion, and `vectors/manifest.json`. Vector vocabulary extended for iOS lifecycle as a versioned addition before Swift is written. | ✓ |
| Same, but hand-write the transport | Skip the generator; hand-write URLSession DTOs against the contract. | |
| Same, but skip the contract normalization | Generate and commit as-is, relying only on the round-trip test. | |

**User's choice:** Native reimpl + generated committed client + contract fix.

**Notes:** The decisive discovery was that the golden vectors already have **two** independent consumers — `apps/server/lib/keepling/application/sync/reference_model.ex` and `apps/desktop/test/application/sync-vectors.test.ts` — so Swift is the third, not the second. N-version agreement against a shared specification is stronger correctness evidence than one shared binary, which would replace independent corroboration with a single point of uniform wrongness no conformance suite could detect. A Rust/UniFFI core also owns almost nothing unless it also owns persistence, which would reverse D-26/D-30; Signal and Mozilla run that pattern with full-time Rust plus per-platform teams, while the solo-maintainer base rate is Dropbox's C++ retreat.

The contract normalization was kept because the landmine is in the contract, not the tool: `keepling.yaml` uses `anyOf: [X, {type: 'null'}]` in 35 places, and that nullable-`$ref` cluster is an open, milestone-blocked generator defect (apple/swift-openapi-generator#286). Five of six `oneOf`s carry no discriminator, making decoding first-match-wins across structurally overlapping variants such as `SyncTaskSnapshot` vs `SyncOrganizationSnapshot`. The normalization is semantically neutral and benefits the TypeScript consumer too.

Conformance was deliberately made structural rather than asserted, in the spirit of Phase 3's monotonic outbox state: `#filePath` source-tree resolution instead of SwiftPM `.copy` resources (a copy is a drift vector), set-equality coverage so a skipped action type fails rather than silently reducing coverage, and a `vectors/manifest.json` consumer gate.

One genuinely one-way item was flagged: the vector schema vocabulary freezes once a third consumer exists, so iOS lifecycle extensions must be versioned additions made *before* Swift is written against it.

---

## Area 4 — Native touch + capture surface

| Option | Description | Selected |
|--------|-------------|----------|
| Two-tab + persistent named Undo + App Intents only | `TabView`(Today, Inbox) + per-tab `NavigationStack`; full-swipe Complete only, Trash via context menu/detail; no pull-to-refresh, no reorder. Undo = persistent named control in `tabViewBottomAccessory` + overflow mirror, no timer, shake disabled. Capture = in-app sheet + `.keyboardShortcut` + App Intents in the main target. Share Extension / widget / Control Center deferred. Sync = conditional accessory, absent when healthy, + `Sync & Recovery` sheet reachable from overflow even when quiet. "Saved on this iPhone". | ✓ |
| Same, but include a Share Extension | Accept App Group container, cross-process SQLite locking, and a second outbox consumer to close the Safari-link gap now. | |
| Same, but overflow-menu-only Undo | Drop the persistent accessory strip; undo lives solely in the nav-bar overflow menu. | |

**User's choice:** Two-tab + persistent named Undo + App Intents only.

**Notes:** The reframe that settled the extension question: extensions are a **storage-architecture decision, not a UI one**. Serving them requires moving the store into an App Group container — a documented corruption and jetsam (`0xDEAD10CC`) hazard that Signal published `SQLCipherVsSharedData` about — and a second consumer of a concurrency model Phases 2 and 3 tuned for exactly one process. The adversarial pass conceded honestly that Safari-link capture is the deferral most likely to send Jon back to Things, threatening criterion 5; the counterweight is that shipping it here threatens criteria 2 and 3, the trust criteria. If link capture proves a daily habit in dogfooding, the correct response is a dedicated phase that redesigns store access for multiple processes.

App Intents declared in the **main app target** were the high-leverage compromise: Shortcuts, Siri, Action Button, and Spotlight action surfaces for roughly one file, with no new target, no App Group, no second process touching the store, and unit-testable `perform()` rather than unautomatable Siri UI.

Undo was the weakest Mac analogue since the iPhone has no menu bar. The persistent named control in `tabViewBottomAccessory` won on two independent grounds: it is the direct native re-expression of D-12's "named visible action, not a hidden gesture," and timed toast dismissal is both an accessibility failure (VoiceOver and Switch Control users routinely cannot reach it) and unprovable-without-flake in XCUITest. Shake-to-undo was rejected as undiscoverable, user-disableable, and untestable — it can never carry a locked semantic command. The documented fallback if the strip proves visually noisy is overflow-menu-only undo, never a gesture.

Pull-to-refresh was rejected specifically because it would falsely imply the user can command synchronization correctness, contradicting D-15/D-16.

---

## Area 5 — Device backup and the stale-outbox replay vector

| Option | Description | Selected |
|--------|-------------|----------|
| Exclude store from backup + prove server no-op | Mark db/-wal/-shm `isExcludedFromBackup` **and** prove server mutation-identity+fingerprint makes replay a no-op. Explicit IOS-02 adversarial fixture. | ✓ |
| Allow backup, rely on server idempotency alone | Let the store ride in backups so a restored phone keeps offline work that never reached the server. | |
| Exclude from backup only | Excluded store, no additional replay fixture. | |

**User's choice:** Exclude store from backup + prove server no-op.

**Notes:** Belt and braces. A restored iPhone starts from a clean local store and re-bootstraps from the server, and even a hand-restored store cannot double-apply into a fenced account. Costs one explicit IOS-02 adversarial fixture. This gray area was surfaced by the Area 1 research rather than anticipated in the original area list.

---

## Area 6 — Notification scope (does D-19 hold?)

| Option | Description | Selected |
|--------|-------------|----------|
| D-19 holds unchanged — zero notifications | No OS notifications for any sync state, and no reminders or scheduled local notifications at all this phase. Keeps push entitlement, permission prompt, and privacy surface entirely out of Phase 4. | ✓ |
| D-19 holds for sync, but reminders are in scope | Ship scheduled local notifications for task reminders, citing the architecture snapshot's "native reminders" rationale for choosing native iOS. | |
| D-19 holds, but allow one authentication-fence notification | Single narrow exception for stranded mutations after auth expiry. | |

**User's choice:** D-19 holds unchanged — zero notifications.

**Notes:** Asked explicitly because a 2026-08-28 architecture snapshot cited "native reminders" among the reasons native iOS beat a PWA, which could have been read as a standing scope grant. It is not: it remains a valid long-term platform-choice rationale, and reminders become their own later phase with a permission flow, lifecycle-tied scheduling and cancellation semantics, and their own accessibility and privacy surface.

---

## Claude's Discretion

- Exact grace-period duration, backoff constants, and accessory-strip animation timing within the locked state meanings and Reduce Motion.
- Priority-arbitration contract between the undo control and actionable sync exceptions in the shared accessory slot; layout arbitration between the accessory and any capture affordance in the bottom-trailing thumb zone.
- The "until superseded" lifetime rule for the undo control (per-list vs global).
- Swift module and target decomposition under `apps/ios`, provided the pure reducer is separately testable and the store sits behind `LocalStorePort`.
- Injected `SIGKILL` points for G3 and the exact retained fixture lineage for G4, provided coverage is adversarial rather than illustrative.
- Sheet detents, iconography, and empty-state composition within the inherited semantic and brand contracts.
- Whether the device lane is a sub-lane of a single iOS phase-gate entry point or a separately invoked script, provided evidence binding and refusal-on-mismatch behave as specified.

## Deferred Ideas

- Share Extension for Safari/cross-app link capture — own phase, requires multi-process store redesign. Acknowledged as the most-missed deferral.
- WidgetKit widget, Control Center / Lock Screen controls, Spotlight-index surfaces, capture while fully terminated.
- OS notifications and task reminders — own phase.
- TestFlight and App Store distribution — Phase 6.
- Drag-to-reorder and user-defined ordering on iPhone.
- Additional destinations beyond Inbox and Today; revisit the two-tab navigation model above roughly four destinations.
- Shared FFI core (Rust/UniFFI) for the reducer — revisit only at N=4 consumers **and** on evidence of ≥2 semantic bugs fixed independently in ≥2 runtimes; pure reducer only.
- SQLCipher / application-layer encryption, biometric app lock, cryptographic erasure, remote wipe.
- iPad and Mac Catalyst layouts.
- Self-hosted CI runner with a tethered device (blocked by O-35 — no git remote, no workflow has ever run).
