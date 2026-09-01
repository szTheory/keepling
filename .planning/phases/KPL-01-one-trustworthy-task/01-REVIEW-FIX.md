---
phase: KPL-01-one-trustworthy-task
fixed_at: 2026-09-01T02:39:27Z
review_path: .planning/phases/KPL-01-one-trustworthy-task/01-REVIEW.md
iteration: 4
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
commits:
  - 3b30503
  - be25a80
  - dc076f6
  - 31846e4
tests:
  - canonical Phase 1 gate: server 109/109, web unit 147/147, and Playwright 25/25 passed
  - contracts drift and production-route isolation: passed
  - repository web lint: passed
  - repository web TypeScript typecheck: passed
unresolved: []
---

# Phase KPL-01: Code Review Fix Report

**Fixed at:** 2026-09-01T02:39:27Z
**Source review:** `.planning/phases/KPL-01-one-trustworthy-task/01-REVIEW.md`
**Iteration:** 4

**Summary:**

- Findings in scope: 4
- Fixed: 4
- Skipped: 0

## Fixed Issues

### CR-01: Disposing a failed route continuation leaves later authentication recovery without a sign-in path

**Files modified:** `apps/web/src/app/AuthProvider.tsx`, `apps/web/src/features/auth/auth.test.tsx`
**Commit:** `3b30503`
**Status:** fixed: requires human verification
**Applied fix:** Continuation failure now belongs to each live continuation entry. Registration, individual disposal, route-scope disposal, and drain settlement derive the visible error latch and interruption from the surviving active entries. The regression rejects a route-owned resume, navigates away to dispose that owner, registers a fresh route interruption, proves the sign-in form replaces the stale retry-only surface, and proves the new continuation drains with the rotated CSRF token.

### WR-01: The compact-wide workspace is always one header taller than the viewport

**Files modified:** `apps/web/src/app/WorkspaceShell.tsx`, `apps/web/src/index.css`, `apps/web/e2e/responsive-route-matrix.spec.ts`
**Commit:** `be25a80`
**Status:** fixed
**Applied fix:** Removed the inherited full-viewport minimum from the workspace shell and constrained the compact-wide content to its calculated shell height with pane-local overflow. The real-stack matrix now covers 1024, 1063, 1064, and 1440 pixels, retains the navigation and pane-scroll contracts, and asserts the document never exceeds the viewport height or width.

### WR-02: The “exact semantic sync” test permits most generated token drift

**Files modified:** `apps/web/src/test/ui-contract.test.tsx`
**Commit:** `dc076f6`
**Status:** fixed
**Applied fix:** Replaced sampled generated-CSS fragments with deterministic reconstruction of the complete root token declarations, automatic dark-scheme selector, and explicit `.dark` selector from `tokens.json`, followed by an exact full-file comparison. Missing, stale, duplicated, reordered, or structurally altered generated CSS now fails the contract.

### WR-03: The CSP endpoint test never exercises a successful static response

**Files modified:** `apps/server/test/keepling_web/security_headers_test.exs`, `apps/server/priv/static/robots.txt`
**Commit:** `31846e4`
**Status:** fixed
**Applied fix:** Added a deterministic allow-listed static asset and a distinct endpoint test that requires a successful `200` response with exactly one CSP header. The existing API and not-found response coverage remains separate.

## Skipped Issues

None.

## Regression Evidence

- CR-01 RED: the new auth regression rendered the stale “Recovery needs another try” surface instead of “Sign in to continue.” GREEN: `auth.test.tsx` passed 21/21 after entry-scoped failure state was implemented.
- WR-01 RED: the compact-wide Playwright assertion observed `scrollHeight` 1118 at a 900-pixel viewport. GREEN: the focused boundary test passed at 1024, 1063, 1064, and 1440 pixels with document height bounded to the viewport.
- WR-02 had no production RED because the checked-in JSON and CSS were already synchronized; the defect was incomplete evidence. The strengthened full-output contract passed 12/12 UI contract tests and now covers every declaration and selector.
- WR-03 RED: `/robots.txt` returned 404 before the deterministic fixture existed. GREEN: the server suite passed 109/109 with successful-static, API, and not-found CSP coverage.

## Verification

Verification ran in the **main checkout**, as explicitly requested for this remediation workflow.

- `./tooling/test-phase-1.sh --run` passed after all fix commits: repository integrity, runtime-gated server compile, 109/109 ExUnit tests, production-route isolation, OpenAPI/TypeScript contract drift, web typecheck, 147/147 Vitest tests, and 25/25 Playwright tests.
- `pnpm lint:web` passed.
- `pnpm typecheck:web` passed.
- Focused Elixir formatting, targeted ESLint, and `git diff --check` passed before their respective finding commits.

---

_Fixed: 2026-09-01T02:39:27Z_
_Fixer: the agent (gsd-code-fixer)_
_Iteration: 4_
