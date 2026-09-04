---
phase: KPL-03-mac-daily-loop
verified: 2026-09-04T12:00:00Z
status: gaps_found
score: 4/5 must-haves verified
behavior_unverified: 0
overrides_applied: 0
gaps:
  - truth: "The packaged Mac application supports quick capture, Inbox, Today, edit, complete/reopen, trash/restore, and undo with complete keyboard navigation, proven end to end by the automated macOS-layer lane (A1-A15) against the exact packaged artifact."
    status: failed
    reason: >
      Re-running the phase's own gate today (not trusting SUMMARY/UAT claims) shows the
      claim does not hold for the artifact actually built from HEAD (616fec0). `node
      tooling/verify-desktop-phase.mjs` finished `lanes=10 failed=2`, one of the two
      failures being `macos-integration: no macOS integration evidence exists for
      application digest 1a783aa6...` -- the gate's own digest-bound evidence cache has
      no recorded pass for the artifact it just built. Attempting to produce fresh
      evidence with `node tooling/verify-macos-integration.mjs --all` (the recording
      path) FAILED after row 1: `ROW id=A1 status=FAIL ... timed out waiting for the
      typed title to reach the capture field`, aborting rows A2-A15 (14 of 15 rows never
      ran). Re-running A1 alone passed cleanly (`--rows A1`, 10 cases, 5.4s) -- the same
      "passes standalone, flakes under --all" pattern the phase's own 03-UAT.md already
      recorded for row A9 (Gap 1, severity major, root_cause "not yet diagnosed"). Today's
      failure lands on a DIFFERENT row (A1, not A9), which is new evidence that the
      underlying interference is not row-A8-specific as 03-UAT.md's root-cause hypothesis
      suggested -- it recurs across different row pairings and is still unresolved despite
      03-18's SUMMARY claiming "150/150 row executions passed" across ten prior --all runs.
      Root cause: `apps/desktop/package.json`/`tooling/package-desktop.mjs` packaging is
      not reproducible across separate invocations (disclosed at QUAL-03/O-40 -- three
      separate `pnpm package:desktop` runs at one clean revision produced three different
      digests), so the digest-bound evidence cache the gate depends on goes stale on
      almost every fresh package, and the recording run needed to refresh it is itself an
      unresolved flake.
    severity: major
    artifacts:
      - path: "tooling/verify-macos-integration.mjs"
        issue: "Row A1 (and previously A9, per 03-UAT.md) times out under --all but passes standalone; the interference is order-dependent and not yet root-caused across rows"
      - path: "tooling/package-desktop.mjs"
        issue: "Packaging is not byte-reproducible across separate invocations (O-40), so recorded macOS-integration evidence for one digest cannot be reused by the next local build, defeating the gate's evidence-reuse design in ordinary local use"
    missing:
      - "Diagnose the cross-row --all interference as a class (not row-by-row); the 03-UAT.md instruction to 'fix the race, never re-record until a run happens to pass' still applies and is still open"
      - "Either make apps/desktop packaging reproducible so recorded evidence outlives a rebuild, or change the gate's evidence design so an unavoidably non-reproducible build does not make local re-verification structurally unable to pass"
    debug_session: ""
  - truth: "Desktop visual evidence exists at the breakpoints and accessibility modes 03-UI-SPEC.md requires (light/dark at five named breakpoints, 200% zoom, Increase Contrast/forced colors, Reduce Transparency, Reduce Motion)."
    status: failed
    reason: >
      Carried forward from 03-UAT.md test 12 (still true today): no snapshot directories
      and no `toHaveScreenshot`/`toMatchSnapshot` usage exist anywhere in apps/desktop
      (confirmed by fresh grep). The UI-SPEC's "Verification Evidence Required" section
      signed this dimension off as PASS with no corresponding lane ever built. The
      properties are proven behaviorally (accessibility.spec.ts covers 200% reflow, theme,
      forced-colors contrast, prefers-reduced-motion) but not by the pixel evidence the
      spec itself demands.
      severity: minor
    severity: minor
    artifacts:
      - path: ".planning/phases/KPL-03-mac-daily-loop/03-UI-SPEC.md"
        issue: "Verification Evidence Required section lists desktop visual snapshots at five breakpoints plus accessibility modes; no code implements them, and the UI-SPEC checker signed it off as PASS anyway"
    missing:
      - "Either build a desktop visual-snapshot lane, or formally amend the UI-SPEC to state these properties are proven behaviorally rather than by pixel comparison, and correct the erroneous PASS sign-off"
    debug_session: ""
---

# Phase KPL-03: Mac Daily Loop Verification Report

**Phase Goal:** Jon can dogfood the core loop in an always-open Electron Mac client, including durable offline work and process relaunch.
**Verified:** 2026-09-04T12:00:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification (a prior automated-evidence UAT pass exists at 03-UAT.md and is reconciled below, not re-litigated from scratch)

**Goal format note:** `03-19-PLAN.md`-style checking aside, the phase goal in ROADMAP.md
("Jon can dogfood the core loop...") is not written in strict `As a X, I want to Y, so
that Z.` MVP user-story form. This is the established phrasing convention across every
phase in this project's ROADMAP.md (Phases 1, 2, 4, 5, 6 all use the same non-canonical
form), not a defect unique to this phase, so verification proceeded against the phase's
five explicit **Success Criteria** rather than refusing outright.

## Goal Achievement

### Observable Truths (ROADMAP.md Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Packaged Mac app supports capture, Inbox, Today, edit, complete/reopen, trash/restore, undo, with complete keyboard navigation | ✗ FAILED (for the "complete keyboard nav" clause, at HEAD, today) | Core loop itself PASSES fresh (packaged lane 11/11, real-stack-sync 5/5, electron-e2e 65/66 with the 1 failure proven a flake by standalone re-run). The keyboard/VoiceOver A1-A15 lane's own recording run (`--all`) FAILED today at row A1, aborting 14 rows; the gate's digest-bound evidence cache has no valid record for today's build. See Gap 1. |
| 2 | Local projection/outbox commit atomically; kill/relaunch retains every accepted local intent | ✓ VERIFIED | Fresh run: `LANE name=packaged status=PASS cases=11`, offline-capture packaged/e2e specs pass; `LANE name=real-stack-sync status=PASS cases=5` proves capture survives against real Phoenix/PostgreSQL |
| 3 | Reconnect acknowledges each mutation exactly by identity, never duplicates, shows structured conflicts | ✓ VERIFIED (with the disclosure REQUIREMENTS.md MAC-03 already records: rejection/expired-handle proven at the unit boundary, not the real-stack lane) | real-stack-sync lane proves arrival order and capture acceptance against a real server; `test/application/undo-reconciliation.test.ts`, `server-refusal.ts` classification, and `sync-recovery.spec.ts` conflict e2e cover the rest |
| 4 | Renderer has no raw DB/filesystem/credential/unrestricted-IPC access; packaged-artifact tests prove the actual boundary | ✓ VERIFIED | Fresh run: `LANE name=ipc-hostile-bridge status=PASS cases=75`, `LANE name=privacy status=PASS cases=1`; `test/packaged/security.spec.ts` in the packaged lane; code review found no injection/auth-bypass/credential vulnerability (03-REVIEW.md, 0 Critical) |
| 5 | Jon can use the supported Mac loop daily without opening Things for those actions | ✓ VERIFIED (capability-level; the *sustained dogfood record* itself is explicitly Phase 6 Success Criterion 5, not this phase's) | Truths 1-4 collectively establish the capability exists end to end against the packaged artifact; `docs/testing/desktop-dogfood.md` and the recorded zero-human-UAT decision (03-06-SUMMARY.md) document the automated-evidence substitute for a manual daily-use log |

**Score:** 4/5 truths verified (0 present-but-behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `apps/desktop/main/**` | Main-owned application/store/sync/credential boundary | ✓ VERIFIED | 141-file review found it wired end to end; `bootstrap()` in `main/index.ts` constructs the real adapters (SafeStorage, KeeplingSyncAdapter), not test doubles |
| `apps/desktop/preload/contracts.ts`, `main/protocol.ts` | Strict zod schemas + sender/frame-bound IPC trust | ✓ VERIFIED | `ipc-hostile-bridge` lane 75/75 cases pass fresh; code review confirms `.strict()` on both sides and `isTrustedIpcSender` gating every `ipcMain.handle` on the main window (WR-03 notes the Quick Entry/Settings utility surface uses a narrower WebContents-identity-only check — see Anti-Patterns) |
| `tooling/package-desktop.mjs`, `tooling/smoke-desktop-packaged.mjs` | Immutable manifest, digest-bound, refuses rebuild/dev-server reuse | ✓ VERIFIED, ⚠️ non-reproducible builds | `package-once`/`packaged` lanes pass fresh (12.6s, 11 cases); however repeated invocations produce different `applicationDigestSha256` values (O-40, confirmed by REQUIREMENTS.md disclosure and by this verification's own two packaging runs producing `1a783aa6...` and `b1e438ea...` at the same git HEAD) |
| `tooling/verify-macos-integration.mjs` | 15-row physical-accessibility lane against the real AXUIElement tree | ⚠️ ORPHANED EVIDENCE for the current artifact | Rows individually pass (`--without-accessibility-trust` 4/4, `--rows A1` 10/10 standalone); the full `--all` recording run FAILED today at row A1, so no valid rows=15 evidence exists for HEAD's artifact digest right now — see Gap 1 |
| `apps/desktop/test/e2e/accessibility.spec.ts` (visual/appearance modes) | Snapshot evidence at 5 breakpoints + zoom/contrast/transparency/motion per 03-UI-SPEC.md | ✗ MISSING | No `toHaveScreenshot`/`toMatchSnapshot` usage or snapshot directory anywhere in `apps/desktop` (fresh grep, 0 hits) — see Gap 2 |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `apps/desktop/renderer/desktopClientFacade.ts` | `apps/desktop/main/application/DesktopApplication.ts` | IPC (`window.keepling.*`) | ✓ WIRED | Exercised end to end by the packaged and real-stack-sync lanes, which assert server-side receipt, not client-reported state |
| `apps/desktop/main/adapters/sync.ts` (`KeeplingSyncAdapter`) | real Phoenix `/api/v1/*` | HTTPS, generated OpenAPI client | ✓ WIRED, DATA FLOWS | `real-stack-sync` lane (fresh, 5/5) proves bytes reach a live Phoenix + PostgreSQL 18.6 instance and are read back via `/api/v1/inbox`, not asserted from the client's own state |
| `apps/desktop/main/adapters/credentials.ts` (`SafeStorageCredentialAdapter`) | `main/index.ts` `bootstrap()` | direct construction | ✓ WIRED | Confirmed by `git grep SafeStorageCredentialAdapter -- apps` resolving to `main/index.ts`, matching the `.continue-here.md` verification instruction and REQUIREMENTS.md MAC-01 disclosure |

### Behavioral Spot-Checks / Full Gate Run

| Behavior | Command | Result | Status |
|---|---|---|---|
| Full anti-vacuous desktop phase gate | `node tooling/verify-desktop-phase.mjs` | `Desktop phase gate summary: lanes=10 failed=2` — FAIL on `electron-e2e` (1 test) and `macos-integration` (no evidence for current digest) | ✗ FAIL (see below for disposition) |
| Single failing e2e test re-run in isolation | `pnpm test:desktop:e2e -- -g "dialog focus: opening the Quick Entry discard-draft confirmation"` | `1 passed (2.1s)` | ✓ PASS — confirms the full-gate failure was a flake under parallel load, not a product defect |
| macOS integration lane, rows needing no Accessibility grant | `node tooling/verify-macos-integration.mjs --without-accessibility-trust` | `rows=4 failed=0 cases=13` | ✓ PASS |
| macOS integration lane, full recording run | `node tooling/verify-macos-integration.mjs --all` | `ROW id=A1 status=FAIL ... timed out`; `15 row(s) were requested but 1 reported` | ✗ FAIL |
| Row A1 alone (checking for flake vs. regression) | `node tooling/verify-macos-integration.mjs --rows A1` | `ROW id=A1 status=PASS cases=10 duration_ms=5450` | ✓ PASS standalone — same "passes alone, flakes under --all" shape as 03-UAT.md's existing A9 finding |
| Production code debt-marker scan | `grep -rn "TBD\|FIXME\|XXX" apps/desktop/{main,renderer,store-worker,preload}` | no matches | ✓ PASS |
| Requirement traceability | `grep -n "Phase 3" .planning/REQUIREMENTS.md` | MAC-01..05, QUAL-03, QUAL-04, SRV-02 all listed and checked | ✓ PASS |

**Disposition of the fresh gate failures:** the phase's automated gate, run today from a
clean tree at HEAD (616fec0), does **not** report clean (`lanes=10 failed=2`). One
failure (electron-e2e) is confirmed a flake by an isolated re-run. The other
(macos-integration) is a real, reproducible-today instance of the exact defect class
03-UAT.md already flagged as an open, major-severity, "not yet diagnosed" issue (there:
row A9; today: row A1) — this verification does not discover a new category of problem,
but it does contradict the "gate: lanes=9/10 failed=0" claims embedded in several
REQUIREMENTS.md checkmarks (MAC-01/02/04, QUAL-04) taken as currently true rather than
true-at-a-past-digest. Those checkmarks describe evidence that existed for a specific,
now-superseded artifact digest; they are not reproducible on demand against the artifact
this repository builds today.

### Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
|---|---|---|---|---|
| MAC-01 | 03-01, 03-03, 03-06, 03-12, 03-13, 03-24 | Capture/Inbox/Today/edit/complete/reopen/trash/restore/undo | ✓ SATISFIED | Packaged + real-stack-sync + e2e daily-loop, fresh |
| MAC-02 | 03-03, 03-04, 03-06, 03-15, 03-16, 03-18, 03-20, 03-21 | Complete keyboard navigation + quick entry | ⚠️ PARTIALLY SATISFIED | Core keyboard/menu/Quick Entry flows pass (electron-e2e, IPC lanes); the physical macOS A1-A15 lane's full-pass evidence is stale for the current digest (Gap 1) |
| MAC-03 | 03-01, 03-02, 03-04, 03-14, 03-21, 03-22, 03-23, 03-24 | Offline mutate, kill, relaunch, reconcile without loss/duplication | ✓ SATISFIED, with the disclosure REQUIREMENTS.md itself already records (no-duplication is structural via monotonic outbox state; rejection/expired-handle proven at unit boundary) | real-stack-sync + packaged hard-kill lanes fresh |
| MAC-04 | 03-02, 03-03, 03-05, 03-10, 03-13, 03-14, 03-19, 03-22 | Inspect offline/syncing/conflict/auth-expired/unrecoverable without logs | ✓ SATISFIED | state-matrix + accessibility + sync-recovery e2e, fresh electron-e2e pass (net of the one confirmed flake) |
| MAC-05 | 03-01, 03-02, 03-05, 03-10, 03-11, 03-14, 03-21 | Packaged app (not dev renderer) preserves and synchronizes | ✓ SATISFIED, with disclosure (proven for captures/accepted-outcome only, per REQUIREMENTS.md O-38/O-41) | packaged + real-stack-sync, fresh |
| QUAL-03 | 03-01, 03-06, 03-07, 03-08, 03-12 | Exact tested revision/artifact promoted; no silent rebuild | ✓ SATISFIED for local promotion refusal; ✗ NOT reproducible builds (O-40, confirmed independently by this verification) | package-once/packaged lanes fresh; CI clause unexecuted (no git remote), already disclosed |
| QUAL-04 | 03-03, 03-05, 03-09, 03-10, 03-13, 03-15, 03-18, 03-19, 03-20 | Populated/empty/loading/offline/denied/stale/conflict/partial/retry/unrecoverable states | ✓ SATISFIED for coverage that exists; visual-snapshot evidence dimension is missing (Gap 2) | state-matrix.test.tsx, accessibility.spec.ts |
| SRV-02 (Electron adapter proof, this phase's scope) | 03-02, 03-06, 03-09, 03-12, 03-14, 03-21 | Electron adapter uses generated contracts + server invariants | ✓ SATISFIED for this phase's scope | real-stack-sync fresh; REQUIREMENTS.md explicitly defers full SRV-02 completion to Phase 5's cross-adapter proof — not a Phase 3 gap |

No orphaned requirement IDs: every ID declared across the 24 plans' `requirements:`
frontmatter (MAC-01..05, QUAL-03, QUAL-04, SRV-02) matches an entry in REQUIREMENTS.md's
Phase 3 traceability rows, and every Phase-3-tagged REQUIREMENTS.md row is claimed by at
least one plan.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| `apps/desktop/main/adapters/credentials.ts` | 74-79 | `shouldReEncrypt` from `safeStorage.decryptStringAsync` discarded (03-REVIEW.md WR-01) | ⚠️ Warning | Credential file never migrates after an OS-level key rotation; not exploitable today |
| `apps/desktop/renderer/desktopClientFacade.ts`, `main/windows/quick-entry-window.ts` | 133-151, 112-123 | Post-capture "add to Today" resolves the new task by title match with a `?? tasks[0]!` fallback (03-REVIEW.md WR-02) | ⚠️ Warning | Two tasks sharing a title can cause the wrong task to be added to Today; unmatched capture can silently mutate an unrelated task |
| `apps/desktop/main/windows/quick-entry-window.ts` | 84-89 | Quick Entry/Settings IPC sender check omits the main-frame/origin checks the main window's equivalent check enforces (03-REVIEW.md WR-03) | ⚠️ Warning | Inconsistent trust boundary; not currently exploitable given the deny-all navigation policy |
| `apps/desktop/main/application/DesktopApplication.ts` | 685-691 | `reconcile()` discards the store-open error without logging it (03-REVIEW.md IN-01) | ℹ️ Info | Operability only, not correctness |
| `.planning/phases/KPL-03-mac-daily-loop/03-06-PLAN.md` | 16 | `autonomous: false` left stale after Task 3 was superseded in place by 03-15 (per `.continue-here.md`) | ℹ️ Info | Documentation-only; does not affect shipped behavior |

None of these are debt markers (`TBD`/`FIXME`/`XXX`) and none block the phase per the
code review's own `status: issues-found` (0 Critical) verdict; carried here for
completeness, not as new blockers.

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|---|---|---|
| 1 | Signed/notarized credential continuity | Phase 6 | Phase 6 SC2 ("Exact server, web, packaged Electron, native archive... evidence is bound to one revision"); explicitly deferred and disclosed as unproven throughout Phase 3 (03-UAT.md test 13) |
| 2 | CI execution of `.github/workflows/desktop.yml` | Phase 6 (or whenever a remote is added) | 03-UAT.md test 14, O-35; no git remote exists by standing constraint, so this cannot be phase-blocking here |
| 3 | Sustained real-world dogfood record ("Jon has completed a sustained Mac+iPhone dogfood period...") | Phase 6 SC5 | Phase 3 SC5 is read here as capability-level (the loop works end to end); the multi-week usage record is explicitly Phase 6's own success criterion |
| 4 | QUAL-03 "distribution jobs do not silently rebuild different bytes" (CI clause) | Phase 6 | REQUIREMENTS.md QUAL-03 note: "re-verify in Phase 6 against a real remote before any release claim" |

### Human Verification Required

None. Every must-have in this report was checked by running the project's own automated
evidence commands directly in this session (`tooling/verify-desktop-phase.mjs`,
`tooling/verify-macos-integration.mjs`, `pnpm test:desktop:e2e`, targeted greps), per the
project's zero-human-UAT constraint. No item required a person.

### Gaps Summary

The core daily loop, offline durability, security boundary, and sync-reconciliation
claims (Success Criteria 2, 3, 4, and the capability half of 5) are solidly proven by
fresh runs of the project's own real-server and packaged-artifact lanes today, not merely
by trusting SUMMARY.md prose. Two gaps remain, both narrower than the whole phase and
both already partially known from 03-UAT.md rather than newly invented here:

1. **Major — the macOS-layer keyboard/VoiceOver lane cannot currently produce a fresh,
   valid full pass for the artifact this repository builds at HEAD.** This verification
   independently reproduced the "passes standalone, fails under `--all`" pattern
   03-UAT.md already flagged (there on row A9; here on row A1), and additionally found
   that the packaging non-reproducibility already disclosed under QUAL-03 (O-40) means
   the gate's own evidence-reuse mechanism has no valid record to reuse against today's
   build. Practically: Success Criterion 1's "complete keyboard navigation" claim rests
   on evidence recorded against a prior artifact digest, not a claim this environment can
   currently reproduce on demand.
2. **Minor — no desktop visual-snapshot evidence exists**, despite 03-UI-SPEC.md
   requiring it and a checker having signed it off as PASS. Carried forward unresolved
   from 03-UAT.md.

Both gaps were already known to the project (03-UAT.md, 03-REVIEW.md context); this
report's contribution is confirming both remain live against the current tree with fresh
command output, and finding that the first gap's blast radius is wider than previously
scoped (a different row, not just A9, and a root cause tied to build non-reproducibility
rather than row-A8-specific interference alone).

---

_Verified: 2026-09-04T12:00:00Z_
_Verifier: Claude (gsd-verifier)_
