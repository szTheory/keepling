---
phase: KPL-01
slug: one-trustworthy-task
review_type: ui
status: human_needed
audited: "2026-08-31"
baseline: 01-UI-SPEC.md
overall_score: 14
maximum_score: 24
screenshots: not_captured
needs_human_review: true
---

# Phase KPL-01 — UI Review

**Audited:** 2026-08-31  
**Baseline:** approved `01-UI-SPEC.md`, `01-CONTEXT.md`, and `docs/brand/BRAND-SEED.md`  
**Screenshots:** not captured — no Keepling dev server returned 200 on ports 3000, 5173, or 8080; port 8080 redirected to an unrelated dashboard  
**Automated evidence considered:** final recorded gate of 105 ExUnit, 129 Vitest, and 18 Playwright tests, including the 1023/1024/1063/1064 overflow neighbors, light/dark themes, 200% zoom, forced colors, focus, and Reduce Motion  
**Human evidence:** not supplied; the three manual UAT checks remain open

---

## Pillar Scores

| Pillar | Score | Key Finding |
|--------|-------|-------------|
| 1. Copywriting | 3/4 | Routine, empty, error, conflict, and recovery language is unusually specific, but dirty-navigation and some authentication copy diverge from the approved exact contract. |
| 2. Visuals | 1/4 | The contracted responsive shell is not implemented consistently; the narrow root Inbox has no primary navigation, and primary list routes do not use the wide three-region workspace. |
| 3. Color | 3/4 | Core light/dark semantic tokens match the contract, but hardcoded component colors bypass the destructive-foreground and supporting semantic token system. |
| 4. Typography | 3/4 | Most UI uses the four approved sizes and semibold/body weights, but the shared Button ships an extra 12px size and 500 weight. |
| 5. Spacing | 2/4 | The implementation repeatedly uses undeclared 12px and 20px intervals and the shared Button adds 6px/10px values outside the approved scale. |
| 6. Experience Design | 2/4 | Recovery/state coverage is strong, but hand-built alert dialogs omit the contracted Escape/focus-containment behavior and the automated visual oracle samples only part of the route matrix. |

**Overall: 14/24**

---

## Top 3 Priority Fixes

1. **Restore complete responsive navigation and workspace composition** — the narrow root Inbox currently blocks navigation to core task views, while wide Today/Upcoming/Completed routes lose the specified navigation/list/detail hierarchy — implement one shared responsive shell with a semantic narrow drawer and the contracted wide three-region layout.
2. **Replace hand-built modal surfaces with the approved accessible primitives** — dirty navigation and session confirmation need modal focus containment, Escape cancellation, trigger focus restoration, and exact contract copy — use the approved Alert Dialog/Drawer primitives and add keyboard/browser tests for each surface.
3. **Enforce the design tokens in shipped component variants** — off-scale spacing, the extra type size/weight, hardcoded destructive foreground, and fixed `41.5rem` arithmetic create contract drift — map component variants and workspace sizing to the declared semantic tokens and add a source-level contract test that rejects undeclared values.

---

## Detailed Findings

### Pillar 1: Copywriting (3/4)

- **KPL-UI-COPY-01 — WARNING** (`needs_human_review: false`): Most exact contract strings are present. Quick capture uses `What do you want to keep?`, `Destination: Inbox`, `Add to Today`, `Adding…`, and `Add task` in `apps/web/src/features/capture/QuickCapture.tsx:195`; task-list empty states match the approved table in `apps/web/src/features/lists/TaskList.tsx:57`; conflict copy matches in `apps/web/src/features/tasks/ConflictResolver.tsx:204`; and Trash matches in `apps/web/src/features/lists/TrashList.tsx:268`.
- **KPL-UI-COPY-02 — WARNING** (`needs_human_review: false`): The dirty-navigation copy is not the approved consequential-action text. The contract requires `Discard unsaved changes? These edits haven’t been saved.` with `Keep editing` and `Discard changes`; the task editor instead says `You have unsaved changes. Save them before leaving this task?` and adds a Save action at `apps/web/src/features/tasks/TaskEditor.tsx:826`. AppShell uses a third version, `Unsaved changes / Save changes before leaving this page?`, at `apps/web/src/app/AppShell.tsx:171`. Consolidate this into the single approved contract or formally revise the spec.
- **KPL-UI-COPY-03 — WARNING** (`needs_human_review: false`): Capture authentication recovery says `Sign in again. Keepling will check whether this task was saved.` at `apps/web/src/features/capture/QuickCapture.tsx:260`, rather than the specified `Sign in again to finish saving. Your changes are still here.` plus a visible `Sign in and continue` action. The global overlay may supply the action, but the local state does not communicate the exact preservation promise on its own.
- **KPL-UI-COPY-04 — WARNING** (`needs_human_review: true`): The brand asks for a capable, quiet companion voice. The strings are mechanically specific and avoid prohibited `Oops`, `Something went wrong`, `probably`, and celebratory productivity language, but whether repeated `Keepling will check…` phrases feel calm rather than system-heavy still requires human tone review.

### Pillar 2: Visuals (1/4)

- **KPL-UI-VIS-01 — BLOCKER** (`needs_human_review: false`): Narrow root Inbox navigation is absent. At `apps/web/src/App.tsx:94`, the mobile header exposes only the Keepling name and `Add task`; at `apps/web/src/App.tsx:102`, the only primary sidebar is `hidden` below `lg`. This makes Today, Upcoming, Completed, Trash, and Sessions unreachable through the UI from the default narrow route, breaking the daily loop. The UI-SPEC explicitly requires a compact header that opens semantic navigation in a drawer.
- **KPL-UI-VIS-02 — WARNING** (`needs_human_review: false`): The three-region workspace exists only in the root Inbox implementation (`apps/web/src/App.tsx:101`). Today, Upcoming, Completed, and `/inbox` route directly to a single-column `TaskList` at `apps/web/src/app/routes.tsx:251`, whose root is a centered full-page main at `apps/web/src/features/lists/TaskList.tsx:546`. This does not meet the wide navigation/list/detail composition or the specified focal hierarchy.
- **KPL-UI-VIS-03 — WARNING** (`needs_human_review: false`): Sessions uses a two-column shell at wide widths but leaves the `<aside>` visible in document flow below 1024 (`apps/web/src/app/AppShell.tsx:131`); the media rule merely changes `.keepling-workspace` to block (`apps/web/src/index.css:139`). This stacks the complete navigation above content instead of presenting the contracted compact header and drawer.
- **KPL-UI-VIS-04 — WARNING** (`needs_human_review: false`): The automated visual test is strong on root-Inbox overflow, theme, focus, zoom, and motion, but its viewport matrix remains on `/` (`apps/web/e2e/visual.spec.ts:35`). Only the long-text test later samples Projects and Sessions at 320px. It does not visually prove Today/Upcoming/Completed/Trash/editor/conflict/auth surfaces at the full 320/768/1024/1440 matrix required by the UI-SPEC.
- **KPL-UI-VIS-05 — WARNING** (`needs_human_review: true`): No current screenshots were available for this audit. Visual hierarchy, 60/30/10 allocation, perceived calm, clipping, and the manual 1024px Inbox scrollbar check remain unverified by a person.

### Pillar 3: Color (3/4)

- **KPL-UI-COLOR-01 — WARNING** (`needs_human_review: false`): The DTCG source and generated CSS match the approved canvas, surface, text, muted, accent, and destructive values in `packages/design-tokens/tokens.json` and `packages/design-tokens/css.css:24`. `apps/web/src/index.css:52` maps core roles into the shadcn variables, and dark values are present.
- **KPL-UI-COLOR-02 — WARNING** (`needs_human_review: false`): Supporting colors are duplicated as literals in `apps/web/src/index.css:60` and `apps/web/src/index.css:97` rather than generated semantic tokens. The contract says cross-platform truth belongs in DTCG-compatible tokens; these muted, border, input, sidebar, and chart values can drift independently.
- **KPL-UI-COLOR-03 — WARNING** (`needs_human_review: false`): The dirty-navigation destructive button hardcodes `text-white` at `apps/web/src/app/AppShell.tsx:192`. The approved dark destructive foreground is `#24201D`, so this bypasses the theme-specific pairing and should use a semantic destructive-foreground token.
- **KPL-UI-COLOR-04 — WARNING** (`needs_human_review: true`): Automated theme and forced-color assertions establish mechanics, not perceptual allocation or every rendered contrast pairing. Human review and/or an automated rendered contrast sweep is still required before claiming the 60/30/10 balance and WCAG AA across all routes.

### Pillar 4: Typography (3/4)

- **KPL-UI-TYPE-01 — WARNING** (`needs_human_review: false`): Production class scanning found the intended four principal sizes: 14px (`text-sm`), 16px (`text-base`), 20px (`text-xl`), and 28px (`text-[1.75rem]`), with semibold used for hierarchy and system fonts wired in `apps/web/src/index.css:129`.
- **KPL-UI-TYPE-02 — WARNING** (`needs_human_review: false`): The shared Button introduces `font-medium` (500) and an `xs` variant with `text-xs` (12px) at `apps/web/src/components/ui/button.tsx:6`. The contract permits exactly weights 400/600 and sizes 14/16/20/28. Even if the `xs` variant is not currently invoked, it is a shipped component API that permits off-contract UI.
- **KPL-UI-TYPE-03 — WARNING** (`needs_human_review: false`): The source scan found 60 `text-sm`, 17 `text-base`, 22 `text-xl`, ten 28px display uses, one `text-xs`, 114 `font-semibold`, and one `font-medium`. Remove the extra size/weight or amend the approved contract with explicit usage constraints.

### Pillar 5: Spacing (2/4)

- **KPL-UI-SPACE-01 — WARNING** (`needs_human_review: false`): The contract declares 4/8/16/24/32/48/64px. Production JSX contains at least 20 `mt-3`, 12 `gap-3`, seven `space-y-3`, five `mt-5`, four `space-y-5`, and two `py-5` occurrences—12px and 20px intervals that are not declared tokens. Representative lines include `apps/web/src/features/tasks/TaskEditor.tsx:789`, `apps/web/src/features/activity/ActivityList.tsx:165`, and `apps/web/src/features/sessions/SessionList.tsx:422`.
- **KPL-UI-SPACE-02 — WARNING** (`needs_human_review: false`): The shared Button adds 6px gaps and 10px padding (`gap-1.5`, `px-2.5`) at `apps/web/src/components/ui/button.tsx:24`, which are not even multiples of the contract’s 4px base.
- **KPL-UI-SPACE-03 — WARNING** (`needs_human_review: false`): Detail layout repeats a fixed `calc(100% - 41.5rem)` seam at `apps/web/src/app/routes.tsx:301` and `apps/web/src/features/tasks/TaskEditor.tsx:618`, while the approved semantic tokens already define 224px navigation, 360–440px list, and 480px detail minimums. Express the composition through those tokens so responsive fixes do not require synchronized magic arithmetic.
- **KPL-UI-SPACE-04 — WARNING** (`needs_human_review: false`): The root Inbox does honor the 52px row minimum (`min-h-[3.25rem]`) and most interactive call sites add `min-h-11`. However, the base Button variants themselves define 24–36px heights at `apps/web/src/components/ui/button.tsx:23`, leaving the 44px target dependent on every caller remembering an override.

### Pillar 6: Experience Design (2/4)

- **KPL-UI-XD-01 — WARNING** (`needs_human_review: false`): State modeling is the implementation’s strongest area. Loading is distinct from authoritative empty; last-good data is retained for updating/failure; unknown delivery uses read-only `Check again`; authentication, stale order/cursor, conflict, undo, Trash restore, and session reconciliation are separately represented. The recorded 129 Vitest and 18 Playwright cases provide meaningful behavioral support.
- **KPL-UI-XD-02 — WARNING** (`needs_human_review: false`): Dirty-navigation and session confirmation are hand-built `role="alertdialog"` overlays (`apps/web/src/features/tasks/TaskEditor.tsx:826`, `apps/web/src/app/AppShell.tsx:171`, and `apps/web/src/features/sessions/SessionList.tsx:459`). They set initial focus, but these implementations have no dialog-level keyboard handler or focus-containment code, so Escape cancellation and Tab trapping required by the Accessibility Contract are not established. The approved design system explicitly allows Alert Dialog for this behavior.
- **KPL-UI-XD-03 — WARNING** (`needs_human_review: false`): The code-only UI contract test checks landmark presence, target class names, initial Stay focus, and CSS strings (`apps/web/src/test/ui-contract.test.tsx:59`), but it does not assert modal Escape, focus wrap, trigger focus return, drawer behavior, or narrow Back/scroll restoration. Expand the browser oracle around those interaction contracts.
- **KPL-UI-XD-04 — WARNING** (`needs_human_review: true`): VoiceOver and end-to-end keyboard continuity across capture, validation, conflict, authentication recovery, pagination, lifecycle, undo, and Sessions remain pending. DOM roles and focused unit assertions do not prove the assistive-technology experience.
- **KPL-UI-XD-05 — WARNING** (`needs_human_review: true`): Manual review at 320/768/1024/1440, light/dark, 200% zoom, forced colors, and Reduce Motion remains pending. Automated geometry passed—including the strengthened 1024px oracle—but no human confirmation of perceived reflow, focus visibility, motion quality, or the Inbox scrollbar exists.
- **KPL-UI-XD-06 — WARNING** (`needs_human_review: true`): Password-manager and OS behavior for paste, AutoFill, reveal, one-use recovery, and authentication-expiry continuation remains pending. The implementation uses appropriate autocomplete attributes, but no real password-manager result is claimed.

---

## Registry Safety

`apps/web/components.json` is initialized for shadcn and declares `registries: {}`. The approved UI-SPEC lists no third-party blocks. Registry audit: 0 third-party blocks required checking; no registry flags.

---

## Human Review Required

| Check | needs_human_review | Status |
|-------|--------------------|--------|
| VoiceOver and keyboard continuity across the full recovery/lifecycle matrix | true | Pending — not claimed as passed |
| Reflow, both themes, 200% zoom, forced colors, Reduce Motion, and manual 1024px Inbox scrollbar inspection | true | Pending — not claimed as passed |
| Password-manager/OS paste, AutoFill, reveal, one-use recovery, and authentication-expiry continuation | true | Pending — not claimed as passed |

The phase remains `human_needed`. Automated success does not close these checks.

---

## Files Audited

- Contract and project context: `AGENTS.md`, `docs/brand/BRAND-SEED.md`, `01-CONTEXT.md`, `01-UI-SPEC.md`, all `01-01` through `01-23` PLAN/SUMMARY pairs, `01-VERIFICATION.md`, and `.planning/debug/resolved/visual-overflow-1024.md`.
- Shell, routing, and tokens: `apps/web/src/App.tsx`, `apps/web/src/app/AppShell.tsx`, `apps/web/src/app/AuthProvider.tsx`, `apps/web/src/app/routes.tsx`, `apps/web/src/index.css`, `apps/web/components.json`, `packages/design-tokens/tokens.json`, and `packages/design-tokens/css.css`.
- Production UI: all current files under `apps/web/src/features/`, `apps/web/src/components/`, `apps/web/src/commands/`, and `apps/web/src/api/keepling.ts`.
- UI tests: all current `*.test.ts` / `*.test.tsx` files under `apps/web/src/` and all Playwright files under `apps/web/e2e/`, with particular attention to `visual.spec.ts`, `phase1.spec.ts`, auth/recovery suites, conflict recovery, Today-order recovery, session reconciliation, and the UI-contract test.

