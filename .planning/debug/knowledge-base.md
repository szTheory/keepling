# GSD Debug Knowledge Base

Resolved debug sessions. Used by `gsd-debugger` to surface known-pattern hypotheses at the start of new investigations.

---

## gate-b-private-deploy-proof — Native Linux credential ownership and restored database selection
- **Date:** 2026-09-30
- **Error patterns:** image-compose-deploy, private verification step failed, verify-deploy.sh, mode 0600, restored_login
- **Root cause(s):** Host-owned mode-0600 credential was unreadable by the release UID on Linux; independently Compose replaced the restored database URL with its source secret before release runtime configuration loaded.
- **Fix:** Stream the private credential through stdin; select a disposable database_url secret before startup; assert current_database() before positive and negative authentication checks.
- **Files changed:** tooling/verify-deploy.sh
- **Why not caught:** Docker Desktop masked native Linux ownership behavior, and the previous restored-login assertion did not verify the connected database. Native Linux image-compose-deploy caught the ownership failure.
- **Recurrence guard:** tooling/verify-deploy.sh recovery_fixture_login and prove_recovery_login_fixture enforce restored database identity, preserve credential mode via stdin, and check both valid and invalid credentials. Local proof passed; parent independently confirmed native Linux image-compose-deploy, phase2-verified-image, phase2-privacy, and all required checks passed after push of 4dd7e3c.
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
