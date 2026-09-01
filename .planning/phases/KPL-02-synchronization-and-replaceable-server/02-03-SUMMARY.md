---
phase: KPL-02-synchronization-and-replaceable-server
plan: 03
subsystem: authentication
tags: [elixir, postgres, oauth-public-client, pkce, refresh-rotation, namespace-fencing]

requires:
  - phase: KPL-02-synchronization-and-replaceable-server
    plan: 01
    provides: durable outbox, journal, authentication-fencing, and exact acknowledgement reference semantics
  - phase: KPL-01-one-trustworthy-task
    provides: hash-only credential patterns, closed security audit vocabulary, and account application seam
provides:
  - Closed D-16 through D-21 account fencing and destructive-removal lifecycle vectors
  - Exact redirect/state/S256 PKCE authorization-code exchange for native public clients
  - Hash-only access and rotating refresh lineage with installation-scoped replay fencing
  - Server-authoritative five-field synchronization namespace
affects: [server-sync-cursor, desktop-offline-store, ios-offline-store, native-authentication]

actuals:
  tokens: 16857
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns: [closed account-lifecycle vectors, hash-only public-client grants, retained refresh lineage, installation-scoped generation fences]

key-files:
  created:
    - apps/server/lib/keepling/accounts/device_grant.ex
    - apps/server/priv/repo/migrations/20260901000200_add_device_grants.exs
    - packages/contracts/schemas/account-lifecycle.schema.json
    - packages/contracts/vectors/account-lifecycle.json
  modified:
    - apps/server/lib/keepling/accounts.ex
    - apps/server/lib/keepling/accounts/security_audit.ex
    - apps/server/test/keepling/accounts/device_grant_test.exs

key-decisions:
  - "Synchronization generation is installation-grant scoped so replay or revocation fences exactly one native installation without invalidating another."
  - "Issuer, origin, stable server instance, account subject, and generation come only from server configuration and locked rows; closed public-client requests reject extra secret or namespace assertion fields."
  - "Consumed refresh hashes remain as lineage evidence, and the first replay revokes and advances the family fence exactly once."

patterns-established:
  - "Public-client exchange: bind one-use code hash to exact redirect, unpredictable state, and S256 verifier before issuing opaque credentials."
  - "Replay fence: lock refresh lineage and grant together, retain consumed hashes, revoke the exact family, clear access authority, and increment its generation atomically."
  - "Namespace quarantine: credentials, shadow, cursor, conflicts, journal, drafts, and outbox share the complete issuer/origin/server/subject/generation tuple."

requirements-completed: [SRV-04, QUAL-05]

coverage:
  - id: D1
    description: "Account switching, duplicate subjects across servers, late acknowledgements, relaunch, authorization loss, and local removal preserve quarantined intent without cross-namespace delivery."
    requirement: SRV-04
    verification:
      - kind: other
        ref: "packages/contracts/vectors/account-lifecycle.json#12 executed cases"
        status: pass
      - kind: unit
        ref: "apps/server/test/keepling/accounts/device_grant_test.exs#account lifecycle vectors fence every namespace and preserve recoverable intent"
        status: pass
    human_judgment: false
  - id: D2
    description: "Native public clients exchange exact redirect/state/S256 PKCE codes for 15-minute access and hash-only rotating refresh credentials."
    requirement: SRV-04
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/accounts/device_grant_test.exs#authorization exchange validates exact redirect state and S256 PKCE and stores only hashes"
        status: pass
    human_judgment: false
  - id: D3
    description: "Refresh replay and explicit revocation fence only the affected installation while another installation remains authenticated."
    requirement: QUAL-05
    verification:
      - kind: integration
        ref: "apps/server/test/keepling/accounts/device_grant_test.exs#refresh rotation detects replay and atomically fences only that installation"
        status: pass
      - kind: integration
        ref: "mix test#123 passed including 1 property"
        status: pass
    human_judgment: false

duration: 12min
completed: 2026-09-01
status: complete
---

# Phase KPL-02 Plan 03: Account Fencing and Native Device Grants Summary

**Closed namespace-quarantine vectors now pair with exact PKCE public-client grants, hash-only rotating refresh lineage, and installation-scoped replay fencing.**

## Performance

- **Duration:** 12 min
- **Started:** 2026-09-01T06:07:04Z
- **Completed:** 2026-09-01T06:19:04Z
- **Tasks:** 2
- **Files modified:** 7 implementation and proof files

## Accomplishments

- Froze twelve storage-neutral D-16 through D-21 scenarios covering logout, uncertain revocation, relaunch, same-account recovery, A→B→A switching, duplicate subjects across servers, late acknowledgements, permanent authorization loss, local removal, and dirty drafts.
- Added native public-client authorization codes bound to an exact allow-listed redirect, unpredictable state, and S256 PKCE verifier without accepting browser cookies, passwords, shared secrets, or client-asserted namespace fields.
- Added opaque 15-minute access credentials plus 30-day inactivity and 90-day absolute refresh lineage, storing only SHA-256 hashes and retaining consumed hashes for replay detection.
- Made replay and explicit revocation clear access authority and increment only the affected installation generation while bounded security audit facts remain identifier-free.

## Task Commits

Each TDD task was committed as a RED test followed by its GREEN implementation:

1. **Task 1 RED: failing account lifecycle vectors** - `f660a31` (test)
2. **Task 1 GREEN: frozen namespace fencing contract** - `5bc620a` (feat)
3. **Task 2 RED: failing native grant lifecycle tests** - `75a0922` (test)
4. **Task 2 GREEN: rotating device grants and replay fencing** - `339b32c` (feat)

## Files Created/Modified

- `packages/contracts/schemas/account-lifecycle.schema.json` - Closed Draft 2020-12 account lifecycle shape.
- `packages/contracts/vectors/account-lifecycle.json` - Twelve synthetic namespace, quarantine, recovery, and removal cases.
- `apps/server/test/keepling/accounts/device_grant_test.exs` - Executable lifecycle reducer plus PostgreSQL-backed code, rotation, replay, expiry, and isolation proof.
- `apps/server/priv/repo/migrations/20260901000200_add_device_grants.exs` - Grant, refresh lineage, constraint, index, and closed audit persistence.
- `apps/server/lib/keepling/accounts/device_grant.ex` - Native public-client issuance, exchange, access authentication, rotation, replay detection, revocation, listing, and namespace construction.
- `apps/server/lib/keepling/accounts.ex` - Inward application delegates for the grant seam.
- `apps/server/lib/keepling/accounts/security_audit.ex` - Identifier-free device-grant event vocabulary.

## Decisions Made

- Scoped synchronization generation to one installation grant because a replayed or revoked phone must not invalidate an independently authorized Mac.
- Constructed namespace authority only from server configuration and locked database values; request maps are closed so an ignored client secret or asserted issuer cannot be mistaken for authority.
- Retained consumed refresh hashes as lineage evidence while making repeated presentation idempotent after the first family fence.
- Left database encryption, biometric lock, remote wipe, sender constraints, and cryptographic erasure to later packaged platform-adapter evidence per D-23.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] Extended the closed security-audit vocabulary**
- **Found during:** Task 2 implementation
- **Issue:** Grant issue, rotation, replay revocation, and explicit revocation needed bounded audit facts, but the plan's file list did not include the existing closed audit module.
- **Fix:** Added four identifier-free event types to the application vocabulary and database constraint; no credential or arbitrary identifier enters logs, telemetry, or audit metadata.
- **Files modified:** `apps/server/lib/keepling/accounts/security_audit.ex`, `apps/server/priv/repo/migrations/20260901000200_add_device_grants.exs`
- **Verification:** Focused grant tests and the 123-test server suite passed.
- **Committed in:** `339b32c`

**2. [Rule 1 - Bug] Made repeated refresh replay fencing idempotent**
- **Found during:** Task 2 threat-mitigation review
- **Issue:** A repeatedly presented consumed refresh hash could advance the installation generation more than once after the family was already revoked.
- **Fix:** The locked lineage now advances and audits only the first replay fence; subsequent presentations return the same closed replay result without changing generation.
- **Files modified:** `apps/server/lib/keepling/accounts/device_grant.ex`, `apps/server/test/keepling/accounts/device_grant_test.exs`
- **Verification:** The replay test presents the consumed token twice and proves generation remains exactly 2 while the other installation remains at generation 1.
- **Committed in:** `339b32c`

**3. [Rule 2 - Missing critical functionality] Rejected extra public-client authority fields**
- **Found during:** Task 2 threat-mitigation review
- **Issue:** Ignoring extra `client_secret` or namespace assertion fields could let a caller mistakenly treat them as accepted authority.
- **Fix:** Authorization and exchange requests now require exact closed key sets; issuer, origin, server instance, subject, and generation remain server-derived.
- **Files modified:** `apps/server/lib/keepling/accounts/device_grant.ex`, `apps/server/test/keepling/accounts/device_grant_test.exs`
- **Verification:** Focused tests reject synthetic client secrets and client-asserted issuers before code issuance.
- **Committed in:** `339b32c`

---

**Total deviations:** 3 auto-fixed (1 Rule 1, 2 Rule 2)
**Impact on plan:** All fixes enforce the declared spoofing, elevation-of-privilege, and privacy mitigations without adding a transport or platform persistence boundary.

## Issues Encountered

- The first RED run lacked `KEEPLING_TEST_DATABASE_URL`; verification moved to an owned disposable PostgreSQL 18.6 cluster and reran from migrations before any RED commit.
- Context7 was unavailable through MCP and the approved CLI fallback was not installed, so pinned Ecto `Repo.transact/2` semantics were verified directly against the checked-out Ecto 3.14.0 source before implementing commit-on-replay behavior.

## Known Stubs

None. The scan found no TODO/FIXME/placeholder paths or empty values flowing to a UI; D-23 platform protection claims remain deliberately outside this server-only plan rather than stubbed.

## User Setup Required

None - native transport and deployment wiring consume the server-authoritative grant configuration in later plans.

## Next Phase Readiness

- Plan 02-02 can consume the exported issuer/origin/server-instance/subject/generation namespace without importing the Ecto grant schema.
- Desktop and iPhone plans have executable quarantine, logout, removal, and grant-lifetime truth without inheriting a shared local persistence representation.
- No claim is made yet about FileVault/Data Protection coverage, database encryption, biometric lock, remote wipe, sender constraints, or cryptographic erasure.

---
*Phase: KPL-02-synchronization-and-replaceable-server*
*Completed: 2026-09-01*

## Self-Check: PASSED

- All four created contract, migration, and grant artifacts plus this summary exist on disk.
- All four RED/GREEN task commits are present in Git history.
- Coverage metadata parsed successfully with all three deliverables backed by passing automated evidence.
