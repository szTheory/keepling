---
phase: "04"
slug: "native-iphone-daily-loop"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-09-04"
---

# Phase 04 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `04-RESEARCH.md` § Validation Architecture.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest / XCUITest (Xcode 26.6, iOS SDK 26.5, Swift 6.3.3 — no third-party test framework) |
| **Config file** | `apps/ios/project.yml` (XcodeGen) — does not exist yet; Wave 0 deliverable |
| **Quick run command** | `xcodebuild test -project apps/ios/Keepling.xcodeproj -scheme Keepling -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:KeeplingCoreTests` |
| **Full suite command** | `node tooling/verify-ios-phase.mjs` (wraps the full simulator suite + the physical-device lane, mirroring `tooling/verify-desktop-phase.mjs`) |
| **Estimated runtime** | ~30s quick lane · ~8–12 min full gate |

---

## Sampling Rate

- **After every task commit:** Run the quick lane (`-only-testing:KeeplingCoreTests`, pure Swift, no UI).
- **After every plan wave:** Run the full simulator suite including `KeeplingUITests` and the accessibility audit matrix.
- **Before `/gsd-verify-work`:** Full suite green on simulator AND the physical-device lane green (D-20 two-lane split).
- **Max feedback latency:** 60 seconds for the quick lane.

---

## Per-Task Verification Map

> Seeded from the research requirement→test map. Task IDs are filled in by
> `/gsd-validate-phase` once PLAN.md task numbering is final.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| TBD | TBD | TBD | IOS-01 | — | Core loop operations are durable and account-scoped | e2e (XCUITest) | `xcodebuild test -project apps/ios/Keepling.xcodeproj -scheme Keepling -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:KeeplingUITests/CoreLoopTests` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | IOS-02 | — | Hard termination never loses or duplicates a queued mutation | store/persistence | `xcodebuild test -project apps/ios/Keepling.xcodeproj -scheme Keepling -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:StorageTests/CrashRecoveryTests` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | IOS-03 | — | Accessibility affordances present under Dynamic Type / VoiceOver / Reduce Motion | accessibility audit | `xcodebuild test -project apps/ios/Keepling.xcodeproj -scheme Keepling -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:KeeplingUITests/AccessibilityAuditTests` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | IOS-04 | — | Local/syncing/conflict/auth-expired/unrecoverable states are distinguishable and never silently degrade | state-matrix e2e | `xcodebuild test -project apps/ios/Keepling.xcodeproj -scheme Keepling -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:KeeplingUITests/SyncStateMatrixTests` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | SRV-02 | — | Swift adapter upholds the same domain invariants as the server reference model | vector conformance + real-stack | `xcodebuild test -project apps/ios/Keepling.xcodeproj -scheme Keepling -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:KeeplingCoreTests/SyncVectorConformanceTests` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `apps/ios/project.yml` — XcodeGen project definition (nothing but `README.md` exists in `apps/ios` today)
- [ ] `apps/ios/Package.swift` — `KeeplingCore` SPM package (GRDB.swift, swift-openapi-generator)
- [ ] `apps/ios/Tests/KeeplingCoreTests/` — SRV-02 vector conformance stubs
- [ ] `apps/ios/Tests/StorageTests/` — IOS-02 durability/crash-recovery stubs
- [ ] `apps/ios/Tests/KeeplingUITests/` — IOS-01, IOS-03, IOS-04 stubs
- [ ] `tooling/verify-ios-phase.mjs` — phase gate mirroring `tooling/verify-desktop-phase.mjs` `runLane`/`inputDigestFor` (every lane must report a positive case count or fail)
- [ ] `packages/contracts/vectors/manifest.json` — cross-consumer vector coverage gate

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Physical-device confirmation of the core loop | IOS-01, IOS-02 | Simulator cannot prove real-hardware background execution, real network transitions, or real provisioning | Automated via `xcodebuild test -destination 'platform=iOS,id=<hardware-UDID>' -allowProvisioningUpdates` plus `devicectl device process terminate` — device attachment is the only human step |

*Everything else has automated verification. Per project constraint there is no human UAT: the physical-device lane is scripted, not tapped.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s (quick lane)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
