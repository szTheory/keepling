---
phase: "3"
slug: "mac-daily-loop"
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-09-02"
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Vitest 4.1.11 for pure, component, worker, and IPC tests; Playwright 1.62.1 for Electron E2E and packaged executable tests; real SQLite adapter and migration fixtures |
| **Config file** | Desktop configs do not exist yet — Wave 0 creates desktop Vitest and Playwright configs without mutating `apps/web` configs |
| **Quick run command** | `pnpm typecheck:desktop && pnpm test:desktop` |
| **Full suite command** | `pnpm test:desktop && pnpm test:desktop:ipc && pnpm test:desktop:e2e && pnpm smoke:desktop:packaged` |
| **Estimated runtime** | Measure during Wave 0; keep pure and adapter feedback under 30 seconds and record packaged-lane duration separately |

---

## Sampling Rate

- **After every task commit:** Run the task's narrow desktop typecheck, Vitest, IPC, SQLite, or contract command; use `pnpm typecheck:desktop && pnpm test:desktop` as the default fast lane once Wave 0 exists.
- **After every plan wave:** Run `pnpm test:desktop:ipc && pnpm test:desktop:e2e`; any store, runtime, packaging, or dependency change also runs `pnpm smoke:desktop:packaged`.
- **Before `$gsd-verify-work`:** The full desktop suite, exact packaged-artifact lane, privacy/security assertions, physical Mac accessibility checklist, and bounded dogfood acceptance must be green.
- **Max feedback latency:** 30 seconds for pure and adapter sampling where possible; Electron E2E and packaged lanes report measured duration separately.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 03-W0-01 | Wave 0 | 0 | MAC-01 | T-03-renderer | Daily-loop mutations cross the semantic facade and never expose persistence handles to the renderer | component + SQLite integration + Electron E2E | `pnpm test:desktop -- daily-loop && pnpm test:desktop:e2e -- daily-loop` | ❌ W0 | ⬜ pending |
| 03-W0-02 | Wave 0 | 0 | MAC-02 | T-03-input | Keyboard, menu, Quick Entry, IME, repeat, editable guards, and focus restoration stay within the intended command surface | Electron E2E + physical Mac | `pnpm test:desktop:e2e -- keyboard-quick-entry` | ❌ W0 | ⬜ pending |
| 03-W0-03 | Wave 0 | 0 | MAC-03 | T-03-ack | Atomic local acceptance survives hard kill and exact acknowledgement never loses or duplicates intent | real SQLite + sync vectors + packaged hard-kill | `pnpm test:desktop -- offline-relaunch && pnpm smoke:desktop:packaged -- offline-relaunch` | ❌ W0 | ⬜ pending |
| 03-W0-04 | Wave 0 | 0 | MAC-04 | T-03-recovery | Offline, retry, rejection, conflict, auth, namespace, and store failures remain closed and recoverable | reducer + component + Electron E2E | `pnpm test:desktop -- recovery-presentation && pnpm test:desktop:e2e -- sync-recovery` | ❌ W0 | ⬜ pending |
| 03-W0-05 | Wave 0 | 0 | MAC-05 | T-03-package | The built `.app` retains and migrates data outside source and operates without a development server | packaged artifact | `pnpm smoke:desktop:packaged` | ❌ W0 | ⬜ pending |
| 03-W0-06 | Wave 0 | 0 | QUAL-03 | T-03-supply | The exact tested revision and artifact digest are promoted without rebuilding | package + evidence script | `pnpm package:desktop && pnpm smoke:desktop:packaged` | ❌ W0 | ⬜ pending |
| 03-W0-07 | Wave 0 | 0 | QUAL-04 | T-03-state | Important screens cover populated, empty, loading, offline, denied, stale, conflict, partial, retry, and unrecoverable states | component matrix + Electron flows | `pnpm test:desktop -- state-matrix && pnpm test:desktop:e2e -- representative-states` | ❌ W0 | ⬜ pending |
| 03-W0-08 | Wave 0 | 0 | SRV-02 | T-03-transport | The Electron adapter uses generated contracts and the same server semantic invariants as other transports | contract drift + real-stack Electron E2E | `pnpm contracts:check && pnpm test:desktop:e2e -- real-stack` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Add the desktop package/build configuration and locked root commands: `dev:desktop`, `typecheck:desktop`, `test:desktop`, `test:desktop:ipc`, `test:desktop:e2e`, `package:desktop`, and `smoke:desktop:packaged`.
- [ ] Add a pure test harness that consumes `packages/contracts/vectors/sync.json` and its schema with cross-runtime equality to the existing reference model.
- [ ] Add a real SQLite worker fixture factory with deterministic IDs and clock, fault controls, fresh-create coverage, and retained forward-migration lineages.
- [ ] Add hostile preload/main bridge fixtures for invalid sender, extra fields, unknown operation, non-cloneable values, sequence gaps, renderer reload, and renderer crash.
- [ ] Isolate every Electron test in a disposable user-data/profile directory; never use Jon's real Keepling data.
- [ ] Add a package-once harness that locates the `.app` executable, hashes artifact inputs and output, launches a copy outside source, asserts `app.isPackaged`, and retains evidence.
- [ ] Add accessibility and state-matrix fixtures that preserve the approved `03-UI-SPEC.md` interaction and copy contract.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| VoiceOver, Full Keyboard Access, appearance/contrast, Reduce Motion, and non-US/dead-key behavior | MAC-02, QUAL-04 | Requires macOS assistive technologies, physical keyboard layouts, and visual/auditory judgment | Exercise capture, Inbox, Today, edit, completion, trash/restore, undo, conflicts, and recovery states with VoiceOver and Full Keyboard Access; repeat shortcut tests under a non-US layout and dead-key/IME input; record deviations. |
| Global Quick Entry collision and prior-app focus restoration | MAC-02 | Requires interaction with real installed applications and user-level shortcut ownership | Install the packaged build, test the configured shortcut against existing global shortcuts, invoke from multiple foreground apps, cancel and submit, and verify focus returns to the originating app. |
| Bounded daily dogfood acceptance | MAC-01, MAC-05 | “Daily-use ready” requires real use across natural interruptions not fully represented by automation | Use the packaged app for the defined bounded dogfood interval without Things for scoped actions; record accepted mutations, relaunches, offline periods, conflicts, and any fallback to Things. |
| Signed/notarized credential continuity | MAC-03, MAC-05 | Stable macOS Keychain identity cannot be claimed from an unsigned development artifact | After signing/notarization is available, upgrade between two signed packaged builds and prove credentials and namespace binding remain available without exposing secrets. Until then, record this as unproven. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies.
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify.
- [ ] Wave 0 covers all MISSING references.
- [ ] No watch-mode flags.
- [ ] Pure and adapter feedback latency is under 30 seconds where possible and slower lanes record measured duration.
- [ ] `nyquist_compliant: true` set in frontmatter.

**Approval:** pending
