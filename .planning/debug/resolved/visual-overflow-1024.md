---
status: resolved
trigger: "Full Phase 1 gate fails visual overflow contract at 1024px after final gap-closure fixes"
created: 2026-08-31T23:59:00Z
updated: 2026-08-31T20:08:40-04:00
---

# Debug Session: Visual Overflow at 1024px

## Symptoms

- **Expected:** At the 1024px visual-contract breakpoint, `document.documentElement.scrollWidth` is no greater than `clientWidth`.
- **Actual:** The test reports `scrollWidth: 1064` and `clientWidth: 1024`.
- **Error:** `expect(dimensions.scrollWidth).toBeLessThanOrEqual(dimensions.clientWidth)` fails in `apps/web/e2e/visual.spec.ts:56`.
- **Timeline:** The same 18-test Playwright suite passed before the post-review fix cycle; the failure appeared on the final combined Phase 1 gate.
- **Reproduction:** Run `./tooling/test-phase-1.sh --run`; 105 ExUnit and 129 Vitest pass, then Playwright fails only `UI-BACKSTOP-OVERFLOW` with 17/18 passing.

## Current Focus

hypothesis: confirmed — display:contents recovery wrappers invalidated the direct-child CSS selector, leaving the normal 1064px grid active at 1024px
test: completed — fresh automated overflow oracle passed after the checkpoint disposition authorizing automatic resolution without human visual confirmation
expecting: satisfied by the specified automated oracle across 1023/1024/1063/1064, light/dark themes, and 200% zoom
next_action: archive the resolved session; manual Inbox scrollbar verification remains pending advisory UAT and is not claimed
bug_class: bohrbug
reasoning_checkpoint:
  hypothesis: "The recovery boundary's two display:contents wrappers cause the existing #root > div.min-h-screen compact-grid selector to match nothing, so the normal 224px + 360px + 480px tracks remain active and force 1064px scroll width at a 1024px viewport."
  confirming_evidence:
    - "Fresh Playwright instrumentation reported rootDirectMatch=false at 1024px."
    - "The same run reported computed gridTemplateColumns='224px 360px 480px' and document scrollWidth=1064 with clientWidth=1024."
    - "Git history shows f5c5873 added two display:contents div wrappers after 726ab4f added the direct-child selector."
  falsification_test: "If a semantic selector matches the same grid but its computed columns remain 224px 360px 480px or scrollWidth remains above clientWidth at 1024–1063px, this hypothesis is false."
  fix_rationale: "A semantic class binds the compact rule to the layout role instead of incidental DOM ancestry, restoring the already-intended 224 + 320 + 480 = 1024 track sizing without changing recovery behavior."
  blind_spots: "The post-fix 1023px collapse, 1063px upper edge, 1064px normal-layout return, dark theme, zoom, and the rest of Phase 1 remain to be rerun."
  candidate_causes:
    - "code: hierarchy-dependent selector invalidated by later recovery wrappers (confirmed)"
    - "config: design-token minimums could independently exceed the declared seam even with a matching selector (refuted by 224 + 320 + 480 = 1024)"
    - "data: the 200-character task title could impose intrinsic width (refuted by break wrapping and the exact normal track sum)"
  and_gate: "no — the unmatched selector alone fully explains the exact 40px overflow; the long title and browser environment are not required."
tdd_checkpoint:

## Evidence

- timestamp: 2026-08-31T20:04:00-04:00
  checked: Phase 0 knowledge-base recall
  found: No .planning/debug/knowledge-base.md exists.
  implication: There is no prior local resolution to test first.

- timestamp: 2026-08-31T20:04:00-04:00
  checked: Saved Playwright failure screenshot and active CSS arithmetic
  found: At 1024px the screenshot's nav/list dividers are at x=224 and x=584, proving the list track remains 360px; the active compact rule requests 320px, while the normal tracks total 224 + 360 + 480 = 1064.
  implication: The exact 40px overflow comes from the normal three-column grid remaining active, not from text intrinsic width.

- timestamp: 2026-08-31T20:04:00-04:00
  checked: SBFL preconditions
  found: The Playwright suite has failing and passing tests but no per-test code coverage artifact/configuration.
  implication: SBFL is skipped because no coverage spectrum is available; deterministic DOM measurement is the next fault-localization step.

- timestamp: 2026-08-31T20:06:00-04:00
  checked: Fresh instrumented Playwright reproduction at 1024px
  found: The workspace computed gridTemplateColumns as 224px 360px 480px, rootDirectMatch was false, clientWidth was 1024, and scrollWidth was 1064; the test failed while the other 17 Playwright tests passed.
  implication: The compact media rule is not matching, and its absence exactly accounts for the observed overflow.

- timestamp: 2026-08-31T20:06:00-04:00
  checked: Git history around the selector and recovery boundary
  found: Commit 726ab4f added #root > div.min-h-screen; later commit f5c5873 inserted two div.contents wrappers around routed content.
  implication: DOM ancestry changed after the visual rule was written, invalidating the direct-child selector while display:contents kept the visual layout otherwise unchanged.

- timestamp: 2026-08-31T20:04:42-04:00
  checked: Guardrail revert half with only the production fix removed
  found: The hardened target test failed again at 1024px with Expected <= 1024, Received 1064.
  implication: The semantic class/selector change, rather than test weakening or unrelated state, is causally necessary for the fix.

- timestamp: 2026-08-31T20:06:15-04:00
  checked: Reapply half of revert-and-reconfirm guardrail
  found: The hardened target Playwright test passed after the exact semantic class/selector fix was reapplied.
  implication: The fix is both necessary and sufficient for the automated reproduction.

- timestamp: 2026-08-31T20:06:15-04:00
  checked: Fresh full ./tooling/test-phase-1.sh --run gate
  found: Repository integrity passed; runtime preflight passed; 105 ExUnit tests, contract drift, TypeScript typecheck, 129 Vitest tests, and all 18 Playwright tests passed.
  implication: The original failure is resolved without regressions in the complete Phase 1 executable boundary.

- timestamp: 2026-08-31T20:08:40-04:00
  checked: Post-checkpoint automated overflow oracle
  found: pnpm --filter @keepling/web exec playwright test e2e/visual.spec.ts --grep UI-BACKSTOP-OVERFLOW passed 1/1 on fresh execution; the oracle covers 1023/1024/1063/1064 boundary neighbors, light/dark themes, and 200% zoom.
  implication: Automatic resolution is supported by fresh executable evidence. No human visual confirmation was performed; the manual Inbox scrollbar check remains pending advisory UAT.

## Eliminated

- hypothesis: The 200-character task title creates unbreakable intrinsic width.
  evidence: The screenshot wraps the title, and measured overflow equals the normal grid minimum sum exactly.
  timestamp: 2026-08-31T20:06:00-04:00

- hypothesis: The compact grid arithmetic itself still exceeds 1024px.
  evidence: Its declared tracks total 224 + 320 + 480 = 1024; the live browser instead computed the unreduced 360px middle track.
  timestamp: 2026-08-31T20:06:00-04:00

## Resolution

root_cause: The 1024px compact-grid rule used the hierarchy-dependent selector #root > div.min-h-screen; later display:contents recovery wrappers made that selector match nothing, leaving 224px + 360px + 480px normal tracks active and producing exactly 1064px scroll width.
fix: Added the semantic keepling-inbox-workspace class, targeted the compact media rule to it, and expanded visual regression viewports with 1023/1063/1064 boundary neighbors.
verification:
  target_test: { result: pass, command: "pnpm --filter @keepling/web exec playwright test e2e/visual.spec.ts --grep UI-BACKSTOP-OVERFLOW", result_detail: "1 passed; includes 1023/1024/1063/1064 boundary neighbors in light and dark themes plus 200% zoom" }
  mutation_check: { result: skipped, reason_if_skipped: "No Stryker configuration or dependency exists in the repository." }
  no_op_deletion: { result: pass, deletion_justified_by_rca: false, result_detail: "The fix adds a semantic layout class and retargets an existing media rule; it does not delete or short-circuit behavior." }
  adjacent_tests: { result: pass, suites_run: ["./tooling/test-phase-1.sh --run: repository integrity, 105 ExUnit, contracts, TypeScript, 129 Vitest, 18 Playwright"] }
  revert_and_reconfirm: { result: pass, bug_returned_on_revert: true, fixed_on_reapply: true, result_detail: "Revert produced scrollWidth=1064/clientWidth=1024; reapply produced 1 passing target test." }
  guardrail_verdict: accepted
  checkpoint_disposition: { result: accepted_automatically, basis: "User explicitly authorized automatic forward progress using the specified automated oracle and full Phase 1 gate.", human_visual_confirmation: "not performed and not claimed", pending_uat: "Manual Inbox horizontal-scrollbar check at 1024px remains advisory." }
files_changed:
  - apps/web/src/App.tsx
  - apps/web/src/index.css
  - apps/web/e2e/visual.spec.ts
oracle_type: specified — the UI-BACKSTOP-OVERFLOW contract directly requires scrollWidth <= clientWidth at supported responsive breakpoints.
commit: cc0e8ff

## Prevention

- **Code branch:** The compact-grid rule depended on incidental direct-child DOM ancestry. Recovery wrappers changed that ancestry while preserving visual layout through `display: contents`, so the selector silently stopped matching. The layout role now has the semantic `keepling-inbox-workspace` class.
- **Config/data branches:** The compact token arithmetic totals exactly 1024px, and long task text wraps; neither independently caused the overflow. The AND-gate is no: the unmatched selector alone produced the exact 40px excess.
- **Why not caught:** The visual regression gate originally sampled 1024px but did not include adjacent responsive boundary neighbors, allowing selector/layout coupling introduced after the rule to survive until the final combined Phase 1 gate.
- **Recurrence guard:** `apps/web/e2e/visual.spec.ts` test `@visual-contract UI-BACKSTOP-OVERFLOW proves reflow, themes, focus, and motion independently` now checks 1023/1024/1063/1064 widths in light and dark themes plus 200% zoom; it passed on fresh execution at resolution time.
- **Advisory UAT:** A manual Inbox scrollbar check at 1024px remains pending. This session does not claim human visual confirmation.
