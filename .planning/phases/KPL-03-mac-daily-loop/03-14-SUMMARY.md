---
phase: KPL-03-mac-daily-loop
plan: 14
subsystem: sync
tags: [oauth, rfc8252, pkce, electron, elixir, phoenix, zod, sqlite, device-grants]

requires:
  - phase: KPL-03-mac-daily-loop
    provides: "03-02 KeeplingSyncAdapter, SafeStorageCredentialAdapter, five-field namespace contract, fenced sign-out"
  - phase: KPL-03-mac-daily-loop
    provides: "03-11 real bootstrap() owning the native shell"
  - phase: KPL-03-mac-daily-loop
    provides: "03-13 GAP-1 closure precedent: credential adapter, removeLocalData IPC, hostile-bridge coverage pattern"
provides:
  - "Real runtime device-grant configuration (:keepling, :device_grants) with fail-fast pre-supervision validation"
  - "BrowserDelegatedAuthorization: RFC 8252 system-browser authorization with PKCE S256 and hostile-callback rejection"
  - "FileServerConfiguration: durable server selection with an https/loopback constraint applied at selection time"
  - "The real KeeplingSyncAdapter constructed in the shipped bootstrap, with keepling:// protocol registration and callback routing"
  - "A serialized best-effort synchronization trigger so the wired adapter is actually reached"
  - "Account IPC/preload contracts and a Settings account surface that structurally cannot carry a credential"
affects: [KPL-03-06 dogfood evidence, KPL-04 iPhone client, KPL-05 cross-adapter proof, infra/backup]

actuals:
  tokens: 28953
  tasks: 4
  commits: 9

tech-stack:
  added: []
  patterns:
    - "Browser-delegated authorization (RFC 8252): the desktop never renders a credential-entry field; the system browser owns authentication"
    - "Pre-supervision configuration validation: a server refuses to boot on absent/malformed configuration rather than failing later at a request"
    - "Injected side effects (browser open, clock, entropy, exchange, credential store) so an OAuth flow is fully testable without Electron"
    - "Trust-widening by exactly one named main-owned window, evaluated through the same closed isTrustedIpcSender policy"

key-files:
  created:
    - apps/desktop/main/adapters/auth.ts
    - apps/desktop/main/adapters/server-config.ts
    - apps/desktop/test/application/browser-delegated-auth.test.ts
  modified:
    - apps/server/config/runtime.exs
    - apps/server/lib/keepling/application.ex
    - apps/server/test/keepling_web/device_grant_controller_test.exs
    - infra/compose/compose.yml
    - apps/desktop/main/index.ts
    - apps/desktop/main/windows/settings-window.ts
    - apps/desktop/preload/contracts.ts
    - apps/desktop/preload/index.ts
    - apps/desktop/preload/utility-preload.ts
    - apps/desktop/renderer/settings.tsx
    - apps/desktop/store-worker/index.ts
    - apps/desktop/test/e2e/real-stack-sync.spec.ts
    - apps/desktop/test/ipc/hostile-bridge.test.ts

key-decisions:
  - "Authentication is delegated to the system browser (RFC 8252) rather than an in-app form, so passkeys, SSO, MFA, and password-manager autofill need zero desktop changes and no renderer ever sees a credential."
  - "A private-use scheme (keepling://auth/callback) is used rather than an RFC 8252 loopback redirect because the server's allowed_redirect?/2 is an exact-match allowlist and loopback needs an ephemeral port."
  - "issuer and origin default to the server's own endpoint URL; server_instance is required in prod (KEEPLING_DEVICE_GRANT_SERVER_INSTANCE) because it must be stable for the life of a server's data."
  - "The synchronization trigger is a hint, never a correctness dependency (D-18): it runs after the durable COMMIT, is serialized, and swallows failure."
  - "No requirement was marked complete. See the Requirements section for the per-ID reasoning."

patterns-established:
  - "Untrusted-callback handling: a private-use-scheme callback is validated for exact scheme/host/path, then matched against exactly one in-flight state, before any exchange or credential write"
  - "Capture-then-fence: a credential-dependent best-effort remote call reads its bearer token BEFORE the local fence clears it"

requirements-completed: []

coverage:
  - id: D1
    description: "A running (non-test) server can issue and exchange device grants from real runtime configuration, and refuses to boot when that configuration is absent or malformed."
    requirement: "MAC-05"
    verification:
      - kind: integration
        ref: "apps/server/test/keepling_web/device_grant_controller_test.exs#real runtime configuration -- not test setup -- issues and exchanges an electron grant"
        status: pass
      - kind: integration
        ref: "apps/server/test/keepling_web/device_grant_controller_test.exs#a server whose device-grant configuration is absent or malformed refuses to boot"
        status: pass
    human_judgment: false
  - id: D2
    description: "Credentials are acquired by delegating authentication to the system browser: authorization code + PKCE S256, unpredictable state, keepling://auth/callback, exchanged at /oauth/token and persisted through SafeStorageCredentialAdapter."
    verification:
      - kind: unit
        ref: "apps/desktop/test/application/browser-delegated-auth.test.ts#BrowserDelegatedAuthorization (RFC 8252 system-browser delegation)"
        status: pass
      - kind: e2e
        ref: "apps/desktop/test/e2e/real-stack-sync.spec.ts#authorizes through the browser seam, captures offline, and reaches Synced only on an exact receipt"
        status: pass
    human_judgment: false
  - id: D3
    description: "An unsolicited or mismatched keepling:// callback is rejected without mutating stored credentials."
    verification:
      - kind: unit
        ref: "apps/desktop/test/application/browser-delegated-auth.test.ts#rejects %s without mutating stored credentials"
        status: pass
      - kind: unit
        ref: "apps/desktop/test/application/browser-delegated-auth.test.ts#rejects an unsolicited callback that arrives with no authorization in flight"
        status: pass
      - kind: unit
        ref: "apps/desktop/test/application/browser-delegated-auth.test.ts#rejects a replayed callback after a successful exchange"
        status: pass
    human_judgment: false
  - id: D4
    description: "The shipped bootstrap constructs the real KeeplingSyncAdapter; the inline null-returning stub survives only behind KEEPLING_TEST_SYNC_MODE."
    requirement: "MAC-03"
    verification:
      - kind: integration
        ref: "apps/desktop/test/ipc/hostile-bridge.test.ts#the shipped bootstrap constructs the REAL sync adapter, and the inline fixture survives only behind its explicit test gate (O-16)"
        status: pass
      - kind: other
        ref: "node -e assertion that apps/desktop/dist/main/index.cjs contains KeeplingSyncAdapter"
        status: pass
    human_judgment: false
  - id: D5
    description: "Synchronization namespace authority remains the complete five-field server-derived tuple; the desktop stores and echoes it verbatim and never asserts, derives, defaults, or overrides any field."
    verification:
      - kind: unit
        ref: "apps/desktop/test/application/browser-delegated-auth.test.ts#never lets a client-supplied namespace reach storage"
        status: pass
      - kind: unit
        ref: "apps/desktop/test/ipc/hostile-bridge.test.ts#never lets a renderer assert, derive, or override any of the five namespace fields"
        status: pass
    human_judgment: false
  - id: D6
    description: "No credential-entry field exists in any Electron renderer; the account surface is status plus actions only."
    verification:
      - kind: unit
        ref: "apps/desktop/test/ipc/hostile-bridge.test.ts#static-scans every renderer source for a credential-entry field"
        status: pass
      - kind: unit
        ref: "apps/desktop/test/ipc/hostile-bridge.test.ts#the connect request has EXACTLY one field (serverUrl) -- no credential can be smuggled through it"
        status: pass
    human_judgment: false
  - id: D7
    description: "Exact serialized command bytes are preserved across retry, and Synced is claimed only on an acknowledgement matching mutation identity and fingerprint."
    requirement: "MAC-03"
    verification:
      - kind: e2e
        ref: "apps/desktop/test/e2e/real-stack-sync.spec.ts#authorizes through the browser seam, captures offline, and reaches Synced only on an exact receipt"
        status: pass
      - kind: e2e
        ref: "apps/desktop/test/e2e/real-stack-sync.spec.ts#a receipt for a different mutation identity never settles anything and never claims Synced"
        status: pass
    human_judgment: false
  - id: D8
    description: "Refresh rotation, replay detection surfacing authentication expiry, and revocation on sign out behave as the server specifies."
    verification:
      - kind: e2e
        ref: "apps/desktop/test/e2e/real-stack-sync.spec.ts#rotates refresh tokens, surfaces a detected replay as authentication expiry, and revokes on sign out"
        status: pass
      - kind: e2e
        ref: "apps/desktop/test/e2e/real-stack-sync.spec.ts#a replayed refresh token expires authentication rather than retrying silently"
        status: pass
    human_judgment: false
  - id: D9
    description: "A packaged Keepling on a real Mac, pointed at a real server, authorizes through the system browser and reaches Synced."
    requirement: "MAC-05"
    verification: []
    human_judgment: true
    rationale: "Every automated proof above runs against source modules and a fixture server, or against the packaged bytes WITHOUT a server. No evidence exists of the packaged application synchronizing against a real Phoenix server on a real Mac. That is the outstanding half of MAC-05 and belongs with 03-06 Task 3's dogfood interval."

duration: 46 min
completed: 2026-09-02
status: complete
---

# Phase KPL-03 Plan 14: Reachable Server Synchronization Summary

**Real device-grant configuration with fail-fast boot validation, RFC 8252 browser-delegated PKCE authorization, and the real `KeeplingSyncAdapter` constructed in the shipped bootstrap — closing O-18 and O-16 and finding three latent bugs in code that had only ever run in tests.**

## Performance

- **Duration:** 46 min
- **Started:** 2026-09-03T02:20:00Z
- **Completed:** 2026-09-03T03:06:00Z
- **Tasks:** 4
- **Files modified:** 16 (3 created, 13 modified)

## Accomplishments

- **O-18 closed.** `:keepling, :device_grants` now comes from real runtime configuration in every environment. `/oauth/authorize` and `/oauth/token` are reachable outside test setup for the first time, and `Keepling.Application.validate_device_grants!/1` runs before supervision starts so an unconfigured or malformed server refuses to boot with a named `ArgumentError` instead of answering a silent 400 later.
- **O-16 closed at the shipped entry point.** `bootstrap()` registers the `keepling://` scheme, routes both `open-url` and the argv/`second-instance` path into one validation entry point, and constructs the real `KeeplingSyncAdapter` against a durably configured server. The inline null-returning fixture survives only behind the explicit `KEEPLING_TEST_SYNC_MODE` gate, verified against the packaged `dist/main/index.cjs` bytes.
- **Credential acquisition delegated to the system browser.** `BrowserDelegatedAuthorization` generates a fresh 32-byte verifier and unpredictable 32-byte state per authorization, derives an S256 challenge, and matches every callback against exactly one in-flight request. Nine hostile-callback cases prove rejection leaves stored credentials untouched.
- **Three latent bugs found and fixed** in code that had only ever run in tests (see Deviations).
- **Full desktop phase gate re-run:** `lanes=8 failed=0`, every lane at or above its recorded baseline.

## Task Commits

1. **Task 1: real server device-grant configuration (O-18)** — `fc9823d` (test, RED) → `4fc703e` (feat, GREEN)
2. **Task 2: browser-delegated PKCE authorization** — `f1b505c` (test, RED) → `1362aa7` (feat, GREEN)
3. **Task 3: wire the real adapter and account surface into bootstrap (O-16)** — `fbe6292` (test, RED) → `77fded8` (feat, GREEN)
4. **Task 4: prove the whole loop against a real stack** — `db54575` (test) → `3b3699e` (fix) → `c11c6b9` (feat)

## Verification Evidence (all fresh, run at final HEAD)

| Task | Command | Result |
|---|---|---|
| 1 | `runtime-preflight.sh --exec -- mix test device_grant_test.exs device_grant_controller_test.exs` | **10 passed** (baseline 8; +2 new) |
| 1 | full `mix test` | **177 passed** (1 property, 176 tests), 0 failed |
| 2 | `pnpm typecheck:desktop && pnpm test:desktop` | clean; **16 files / 152 tests passed** (baseline 132; +20) |
| 3 | `pnpm typecheck:desktop && pnpm test:desktop:ipc && pnpm package:desktop && <bundle assertion>` | clean; **66 tests passed** (baseline 54; +12); package manifest emitted; `shipped bundle constructs the real adapter` |
| 4 | `node tooling/verify-desktop-phase.mjs` | **`lanes=8 failed=0` — gate PASSED** |
| — | `tooling/check-repository-integrity.sh` | passed |

### Final `verify-desktop-phase.mjs` lane counts

| Lane | Baseline | This run |
|---|---|---|
| typecheck-desktop | 1 | **1** |
| typecheck-web | 1 | **1** |
| unit-pure-vector-store-worker-performance | 132 | **152** |
| ipc-hostile-bridge | 54 | **66** |
| electron-e2e | 53 | **57** |
| package-once | 1 | **1** |
| packaged | 10 | **10** |
| privacy | 1 | **1** |

All 18 D-48 ownership rows PASS. Both `DEFERRED` items are unchanged and still non-passing by design.

## Files Created/Modified

- `apps/server/config/runtime.exs` — the real `:device_grants` block: issuer/origin derived from the endpoint URL (env-overridable), a server-derived stable `server_instance` (required in prod), and the exact-match `keepling://auth/callback` redirect allowlist.
- `apps/server/lib/keepling/application.ex` — `validate_device_grants!/1`, called before `Supervisor.start_link`, matching the existing compatibility-configuration precedent.
- `infra/compose/compose.yml` — supplies `KEEPLING_DEVICE_GRANT_SERVER_INSTANCE` so an existing deployment still boots.
- `apps/desktop/main/adapters/auth.ts` — `BrowserDelegatedAuthorization` (new).
- `apps/desktop/main/adapters/server-config.ts` — `FileServerConfiguration` + `assertAllowedServerUrl` (new).
- `apps/desktop/main/index.ts` — protocol registration, callback routing, real adapter construction, account IPC handlers, serialized sync trigger.
- `apps/desktop/main/windows/settings-window.ts` — `getWindow()` accessor plus null-on-close bookkeeping.
- `apps/desktop/preload/{contracts,index,utility-preload}.ts` — strict account contracts, parsed on both sides.
- `apps/desktop/renderer/settings.tsx` — Account section: status plus actions only.
- `apps/desktop/store-worker/index.ts` — routes the five previously unreachable sync operations.

## Decisions Made

See `key-decisions` in the frontmatter. The one worth restating: **authentication happens in the system browser, and that is a deliberate architectural commitment, not a workaround.** `/oauth/authorize` is `pipe_through [:api, :authenticated]`; delegating to the browser means whatever authenticates that session — Argon2id today, passkeys/SSO/MFA later — needs zero desktop changes, and WebAuthn works because it runs where platform-authenticator support actually exists.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The worker protocol never exposed five synchronization operations**

- **Found during:** Task 3, while wiring the real adapter.
- **Issue:** `NodeSqliteLocalStore` has always implemented `applyPull`, `readyMutations`, `acknowledgeSync`, `bindNamespace`, and `syncState`, but `store-worker/index.ts` never routed any of them and `WorkerLocalStore` never forwarded them. `DesktopApplication`'s optional-capability checks therefore silently degraded `runSyncPass()` to reconcile-only, and `activateNamespace()` threw `namespace binding is unavailable`. **Nothing could ever have been pushed to a server.** Unreachable before this plan because the shipped app had no real adapter to push through — precisely the "code that has only ever run in tests is not proven code" prediction.
- **Fix:** Routed all five in the worker protocol and forwarded them from `WorkerLocalStore`.
- **Files:** `apps/desktop/store-worker/index.ts`, `apps/desktop/main/index.ts`
- **Verification:** the real-stack loop pushes and settles through the real store; `pnpm test:desktop` 152 passed.
- **Committed in:** `77fded8`

**2. [Rule 1 - Bug] The fenced sign-out could never authenticate its own revocation**

- **Found during:** Task 4, by the real-stack sign-out proof (it failed with `revoked: []`).
- **Issue:** Sign-out fences local intent and clears the credential **before** best-effort remote revocation (correct, D-25). But the revocation adapter read its bearer token from storage, which was already cleared, so it failed `authentication_required` and `signOut` swallowed it. Remote revocation would silently never have happened on a real server.
- **Fix:** Capture the bearer token **before** sign-out and revoke with an adapter bound to that captured token. The fence order is unchanged.
- **Files:** `apps/desktop/main/index.ts`, `apps/desktop/test/e2e/real-stack-sync.spec.ts`
- **Verification:** `real-stack-sync.spec.ts#rotates refresh tokens... and revokes on sign out` asserts `server.revoked === ['installation-loop']`.
- **Committed in:** `3b3699e`

**3. [Rule 2 - Missing Critical] Nothing triggered a synchronization pass in ordinary use**

- **Found during:** Task 4, reviewing whether MAC-03's "later reconcile" was genuinely true.
- **Issue:** Wiring the adapter is not sufficient. No code path called `runSyncPass()` outside the authorization callback, so a capture made after startup would sit in the outbox indefinitely — the adapter would be reachable-but-never-reached, the same defect class this plan exists to close.
- **Fix:** A serialized, best-effort trigger after each durably committed mutation and once at startup. It is a **hint, never a correctness dependency** (D-18): every trigger site runs after the local COMMIT, failure is swallowed, exact bytes stay in the outbox, and passes never overlap.
- **Files:** `apps/desktop/main/index.ts`, `apps/desktop/test/ipc/hostile-bridge.test.ts`
- **Verification:** `hostile-bridge.test.ts` asserts the serialization guard and all five trigger sites; gate re-run PASSED.
- **Committed in:** `c11c6b9`

### Scope adjustments (declared files)

**4. `apps/server/config/dev.exs` was not modified.** The plan listed it for the "local default for dev" behavior. `runtime.exs` is evaluated for every environment, so the dev default lives there in one place rather than being split across two files. Nothing is missing; the file simply needed no change.

**5. Three files outside `files_modified` were changed, each required:**

- `apps/desktop/preload/utility-preload.ts` — **Rule 3 (blocking).** `renderer/settings.tsx` (a declared file) loads the *utility* preload, not `preload/index.ts`, so the account surface was unreachable from Settings without it. It imports the same schemas from the declared `preload/contracts.ts`, so there is still exactly one contract definition.
- `apps/desktop/main/windows/settings-window.ts` — **Rule 3 (blocking).** A `getWindow()` accessor was needed so the account handlers could include the Settings window's exact `WebContents` id in the trusted-sender set.
- `infra/compose/compose.yml` — **Rule 3 (blocking, self-inflicted).** The new fail-fast validation would have prevented an existing compose deployment from booting.
- `apps/desktop/store-worker/index.ts` — see deviation 1.

---

**Total deviations:** 3 auto-fixed (2 Rule 1 bugs, 1 Rule 2 missing-critical) plus 5 scope adjustments (4 Rule 3 blocking, 1 no-op).
**Impact on plan:** No scope creep. Deviations 1 and 3 were each necessary for the plan's own stated truth ("the shipped bootstrap constructs the real `KeeplingSyncAdapter`") to mean anything in practice; deviation 2 restored a locked decision that was silently non-functional.

## Requirements

**No requirement was marked complete.** This is deliberate, and it agrees with `requirements.ready-ids`, which independently reports all three as blocked.

| ID | Marked? | Reasoning |
|---|---|---|
| **MAC-03** | No | The blocking reason recorded in `REQUIREMENTS.md` ("`later reconcile` requires sync, which is not wired") is now **resolved**: the shipped app constructs the real adapter, triggers passes, retries byte-identical bytes, and settles only on an exact identity+fingerprint receipt. But `03-06` also declares MAC-03 and has **no SUMMARY** (its Task 3 physical dogfood checkpoint is outstanding), so the shared-ID gate correctly blocks it. Ready to mark once `03-06` completes. |
| **MAC-04** | No | **Not fully proven by this plan.** `authentication_required` is now genuinely reachable (a failed authorization callback and a detected refresh replay both surface it), and conflict/offline/unrecoverable states already existed. But the shipped app publishes **no `syncing` state** during a pass — `runSyncPass()` emits no presentation — so one of the five states this requirement names is still not inspectable. That is a real remaining gap, recorded below as **O-19**. |
| **MAC-05** | No | The `synchronizes` half is proven at module level against a fixture server, and the packaged bytes are proven to *construct* the real adapter — but **no evidence exists of the packaged application synchronizing against a real Phoenix server on a real Mac.** That is coverage entry D9 (`human_judgment: true`) and belongs with `03-06` Task 3's dogfood interval. |

**MAC-02 and QUAL-04 were not touched.** They remain owned by plan 03-15.

## Known Stubs

None. No hardcoded empty value, placeholder string, or unwired component was introduced.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: new-network-surface | `apps/desktop/main/index.ts` | `keepling://` is now a registered system-wide URL scheme for this app. Registration is first-come on macOS and cannot be exclusively claimed. This is the residual disclosed in the plan's threat model (T-KPL03-14-01): PKCE S256 plus exact state matching reduce interception to a denial of service — an intercepted code is unusable without the verifier, which never leaves the process. |
| threat_flag: new-network-endpoint | `apps/server/config/runtime.exs` | `/oauth/authorize` and `/oauth/token` become reachable on a real server for the first time. Both were already implemented and adversarially tested; only their configuration was missing. |

## Issues Encountered

- **The plan's Task 1 `<verify>` command cannot run as written in this environment.** `mix test` needs `KEEPLING_TEST_DATABASE_URL`/`KEEPLING_TEST_SECRET_KEY_BASE`, which `runtime-preflight.sh` does not supply (only `test-phase-1.sh` and friends do). Evidence above was produced by running the identical `mix test` invocation through `runtime-preflight.sh --exec` against a disposable PostgreSQL 18.6 instance, mirroring `test-phase-1.sh`'s `start_phase_database`. The committed verify command was left unedited.
- The `.tool-versions` digest guard in `runtime-preflight.sh` held throughout; all four preserved untracked paths are untouched.

## New Open Item

**O-19 — the `syncing` state is not surfaced.** `DesktopApplication.runSyncPass()` publishes no presentation, so a user cannot inspect "currently synchronizing" without reading logs. Every other MAC-04 state (offline, conflict, authentication-expired, unrecoverable) is reachable. This is small and self-contained but was outside this plan's authorized files and behaviors, and marking MAC-04 without it would be a false claim. Recommend folding it into 03-15 or a short follow-up.

## Next Phase Readiness

- **`infra/backup/` now protects something real.** A configured server can issue grants, a packaged Mac can authorize through the browser, and captured tasks reach PostgreSQL — so a user's data exists somewhere other than one local SQLite file.
- **Remaining before phase verification:** `03-06` Task 3 (human dogfood on a physical Mac against the packaged digest), `03-15` (MAC-02/QUAL-04), O-19, and the still-stale `pnpm test:phase-1` regression gate (not re-run since 03-02).
- **New prod requirement for operators:** `KEEPLING_DEVICE_GRANT_SERVER_INSTANCE` must be set, and must change when restoring onto a replacement host that should open a new synchronization namespace. Compose defaults it to the deployment host.

## Self-Check: PASSED

- `apps/desktop/main/adapters/auth.ts` — FOUND
- `apps/desktop/main/adapters/server-config.ts` — FOUND
- `apps/desktop/test/application/browser-delegated-auth.test.ts` — FOUND
- Commits `fc9823d`, `4fc703e`, `f1b505c`, `1362aa7`, `fbe6292`, `77fded8`, `db54575`, `3b3699e`, `c11c6b9` — all FOUND in `git log`
- All four task `<verify>` commands re-run at final HEAD; all pass.

---
*Phase: KPL-03-mac-daily-loop*
*Completed: 2026-09-02*
