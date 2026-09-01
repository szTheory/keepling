# GSD Debug Knowledge Base

Resolved debug sessions. Used by `gsd-debugger` to surface known-pattern hypotheses at the start of new investigations.

---

## visual-overflow-1024 — Recovery wrappers disabled the compact Inbox grid selector
- **Date:** 2026-08-31
- **Error patterns:** UI-BACKSTOP-OVERFLOW, scrollWidth 1064, clientWidth 1024, horizontal overflow, 1024px breakpoint
- **Root cause(s):** The 1024px compact-grid rule used the hierarchy-dependent selector `#root > div.min-h-screen`; later `display: contents` recovery wrappers made that selector match nothing, leaving 224px + 360px + 480px normal tracks active and producing exactly 1064px scroll width.
- **Fix:** Added the semantic `keepling-inbox-workspace` class, targeted the compact media rule to it, and expanded visual regression viewports with 1023/1063/1064 boundary neighbors.
- **Files changed:** apps/web/src/App.tsx, apps/web/src/index.css, apps/web/e2e/visual.spec.ts
- **Why not caught:** The visual regression gate originally sampled 1024px but did not include adjacent responsive boundary neighbors, allowing selector/layout coupling introduced after the rule to survive until the final combined Phase 1 gate.
- **Recurrence guard:** Regression test `apps/web/e2e/visual.spec.ts` — `@visual-contract UI-BACKSTOP-OVERFLOW proves reflow, themes, focus, and motion independently` — covers 1023/1024/1063/1064 widths, light/dark themes, and 200% zoom.
---
