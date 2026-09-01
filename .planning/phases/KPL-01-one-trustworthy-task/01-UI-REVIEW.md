# Phase KPL-01 — UI Review

**Audited:** 2026-09-01
**Baseline:** approved `01-UI-SPEC.md`
**Screenshots:** not captured (no Keepling dev server at ports 3000, 5173, or 8080; port 8080 served an unrelated Traefik dashboard)
**Audit mode:** fresh code audit plus current automated UI evidence; subjective external observations are non-gating dogfood

---

## Pillar Scores

| Pillar | Score | Key Finding |
|--------|-------|-------------|
| 1. Copywriting | 4/4 | Exact capture, dirty-work, session, empty, error, and recovery language matches the contract; prohibited vague or celebratory copy was not found. |
| 2. Visuals | 3/4 | Responsive hierarchy, modal structure, landmarks, and long-content geometry are automated; subjective aesthetic taste remains outside the deterministic score. |
| 3. Color | 4/4 | Light/dark semantic roles match the approved palette; accent, destructive, boundary, focus, and non-color state cues are structurally enforced. |
| 4. Typography | 4/4 | Production TSX is restricted to the declared 14/16/20/28px scale and 400/600 weights by an exhaustive AST-backed contract test. |
| 5. Spacing | 4/4 | Production TSX uses the declared 4px-derived scale, 44px targets, 52px task rows, and approved responsive pane minimums with documented semantic exceptions only. |
| 6. Experience Design | 3/4 | Loading, empty, error, conflict, authentication, unknown-delivery, disabled, recovery, modal, and responsive flows are automated; specific OS assistive-technology and password-manager products remain optional dogfood. |

**Overall: 22/24**

---

## Optional Dogfood Observations

1. **Complete the perceptual route/theme/zoom review** — Automated geometry cannot establish calm hierarchy, legibility, or visually awkward wrapping — Review the UI-SPEC matrix at 320/768/1024/1064/1440px in light/dark, 200% zoom, forced colors, and Reduce Motion, including the 1024px Inbox scrollbar check.
2. **Complete real VoiceOver traversal** — DOM roles, focus containment, and live regions can pass while announcements remain confusing in an actual screen reader — Traverse capture, validation, conflict, authentication expiry, uncertain delivery, pagination, lifecycle, undo, and Sessions with VoiceOver and keyboard.
3. **Complete real password-manager and OS recovery validation** — DOM-level autocomplete and reveal assertions do not prove third-party AutoFill or OS integration behavior — Exercise paste, AutoFill, reveal, one-use recovery, and interrupted authentication before and after submission with a real password manager.

These observations can improve product taste and compatibility but are not Phase 1 acceptance gaps. No automated UI-contract defect remains in this re-audit, and the canonical phase UAT requires zero human checkpoints.

---

## Detailed Findings

### Pillar 1: Copywriting (4/4)

- **PASS:** Dirty navigation implements `Discard unsaved changes?`, `These edits haven’t been saved.`, `Save changes`, `Discard changes`, and safe initial `Keep editing` exactly in `apps/web/src/app/AppShell.tsx:223` and `apps/web/src/features/tasks/TaskEditor.tsx:851`.
- **PASS:** Current-browser logout distinguishes saved and dirty states with explicit consequences in `apps/web/src/app/AppShell.tsx:246`; other-session revocation names the target and uses `Keep session active` / `Revoke session` in `apps/web/src/features/sessions/SessionList.tsx:500`.
- **PASS:** Capture exposes `Destination: Inbox`, `Add to Today`, `Adding…`, unknown-result copy, and exact authentication-recovery copy in `apps/web/src/features/capture/QuickCapture.tsx:227`.
- **PASS:** Source scans found no `Oops`, `Something went wrong`, `probably`, `Click Here`, or celebratory productivity language. Generic safe fallbacks name the affected action and state that nothing changed.

### Pillar 2: Visuals (3/4)

- **PASS:** The responsive focal hierarchy is structural: persistent navigation begins at 1064px, 1024–1063px retains list/detail with drawer navigation, and below 1024px shows one routed surface (`apps/web/src/index.css:171`, `apps/web/src/index.css:193`, `apps/web/src/index.css:221`).
- **PASS:** The editor/detail surface uses a hairline boundary and raised semantic surface instead of card-grid decoration (`apps/web/src/index.css:207`). The shell supplies navigation/main regions and a skip link (`apps/web/src/app/WorkspaceShell.tsx:47`, `apps/web/src/app/WorkspaceShell.tsx:80`, `apps/web/src/app/WorkspaceShell.tsx:130`).
- **PASS:** Consequential overlays use the shared Base UI Alert Dialog with backdrop, focus ownership, semantic title/description, and limited motion (`apps/web/src/components/ui/alert-dialog.tsx:35`).
- **PASS:** Browser evidence covers overflow and hostile long text at 320/768/1023/1024/1063/1064/1440px, both themes, 200% zoom, forced colors, and Reduce Motion (`apps/web/e2e/visual.spec.ts:3`; `apps/web/e2e/responsive-route-matrix.spec.ts:56`).
- **NOTE:** This audit did not award the subjective fourth visual point. The deterministic route/theme/zoom/overflow contract is covered by `@uat-reflow`; an optional perceptual dogfood pass can still improve taste without blocking Phase 1.

### Pillar 3: Color (4/4)

- **PASS:** The DTCG source contains the exact approved light/dark canvas, surface, text, muted, boundary, accent, and destructive roles (`packages/design-tokens/tokens.json:36`, `packages/design-tokens/tokens.json:50`).
- **PASS:** Tailwind roles map to semantic product tokens, including destructive foreground and focus ring (`apps/web/src/index.css:52`). Hardcoded color scan found values only in the canonical token source/generated output and unused shadcn chart variables, not shipped TSX component styling.
- **PASS:** Accent use remains purposeful. Selected navigation also has `aria-current`, weight, and edge position (`apps/web/src/app/WorkspaceShell.tsx:51`); errors, conflicts, destructive actions, and Today reasons retain explicit text.
- **PASS:** Forced-colors mode restores a native high-contrast outline (`apps/web/src/index.css:248`). Fresh UI contract evidence confirms semantic source/output synchronization and theme/focus rules.

### Pillar 4: Typography (4/4)

- **PASS:** The declared system font stack is applied in `apps/web/src/index.css:8`. Production uses `text-sm` (14px), `text-base` (16px), `text-xl` (20px), and the documented `text-[1.75rem]` display exception (28px).
- **PASS:** Production weights are limited to normal/inherited 400 and `font-semibold` 600. Off-contract `text-xs` and `font-medium` are rejected across every production TSX class region (`apps/web/src/test/ui-contract.test.tsx:25`, `apps/web/src/test/ui-contract.test.tsx:235`).
- **PASS:** The AST scan documents each arbitrary typography utility with its UI-SPEC value and reason (`apps/web/src/test/ui-contract.test.tsx:54`). Fresh result: 12/12 contract tests passed.

### Pillar 5: Spacing (4/4)

- **PASS:** The source contract fixes spacing at 4/8/16/24/32/48/64px and interactive targets at 44px (`apps/web/src/test/ui-contract.test.tsx:137`).
- **PASS:** Shared buttons retain the 44px minimum while sizes vary only through declared gaps and padding (`apps/web/src/components/ui/button.tsx:6`). Task rows use the explicitly allowed 52px minimum (`apps/web/src/features/lists/TaskList.tsx:464`).
- **PASS:** Workspace panes enforce the approved 360–440px list and 480px detail minimums without the removed 320px fallback or fixed arithmetic (`apps/web/src/index.css:193`, `apps/web/src/test/ui-contract.test.tsx:378`).
- **PASS:** The production-wide AST gate rejects off-scale spacing, undersized targets, and undocumented arbitrary utilities; its small allowlist records a contract value and reason (`apps/web/src/test/ui-contract.test.tsx:25`, `apps/web/src/test/ui-contract.test.tsx:54`). Fresh result: 12/12 passed.

### Pillar 6: Experience Design (3/4)

- **PASS:** Production explicitly covers loading, retained-content updating, authoritative empty, load/update error, validation, stale cursor/order, conflict, authentication required, unknown delivery, retry, disabled/single-flight, and persistent recovery states. Representative evidence: `apps/web/src/features/lists/TaskList.tsx:604`, `apps/web/src/features/tasks/ConflictResolver.tsx:206`, and `apps/web/src/features/recovery/MutationRecoveryPanel.tsx:8`.
- **PASS:** Automated evidence covers safe initial focus, focus wrap, Escape, trigger focus restoration, exact copy, dirty-draft retention, and session endpoint distinction (`apps/web/e2e/modal-keyboard.spec.ts:23`).
- **PASS:** Narrow Back restores row focus/scroll, drawer navigation is keyboard reachable, tested routes have one main landmark, and serious/critical axe violations are rejected (`apps/web/e2e/responsive-route-matrix.spec.ts:16`, `apps/web/e2e/responsive-route-matrix.spec.ts:100`, `apps/web/e2e/responsive-route-matrix.spec.ts:126`).
- **PASS:** Fresh `ui-contract.test.tsx` execution passed 12/12. Upstream fresh evidence records 146/146 Vitest, 108/108 ExUnit, and 25/25 Playwright after the isolated startup-listener flake passed focused and on full rerun.
- **NOTE:** Real VoiceOver listening quality and behavior of particular password-manager/OS combinations are not claimed by DOM automation. Phase 1 instead gates the falsifiable interoperability boundary—accessible semantics, keyboard/focus behavior, autocomplete/paste/reveal, one-use recovery, and exact continuation—through `@uat-accessibility` and `@uat-auth-interop`.

---

## Registry Safety

Registry audit: 0 third-party blocks checked, no flags. `apps/web/components.json` is initialized; the UI-SPEC records only official `@shadcn` usage and no configured third-party registries (`01-UI-SPEC.md:309`).

---

## Files Audited

- `AGENTS.md`; `docs/brand/BRAND-SEED.md`
- Phase `01-CONTEXT.md`, approved `01-UI-SPEC.md`, prior `01-UI-REVIEW.md`, and canonical `01-VERIFICATION.md`
- `01-01-PLAN.md` through `01-27-PLAN.md`; `01-01-SUMMARY.md` through `01-26-SUMMARY.md`
- `packages/design-tokens/tokens.json` and `packages/design-tokens/css.css`
- All production `.tsx` and CSS sources under `apps/web/src`
- Relevant Vitest component/UI evidence under `apps/web/src`
- Phase 1 Playwright evidence under `apps/web/e2e`, including visual, responsive-route, and modal-keyboard suites

## Verification Run

`pnpm --filter @keepling/web test --run src/test/ui-contract.test.tsx` — **12/12 passed** on 2026-09-01.

No implementation file was modified during this audit.
