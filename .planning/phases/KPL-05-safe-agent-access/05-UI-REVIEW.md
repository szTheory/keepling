# Phase 5 — UI Review

**Audited:** 2026-09-11
**Baseline:** Abstract 6-pillar standards (no UI-SPEC.md exists for this phase)
**Screenshots:** Not captured (no dev server running; code-only audit)

---

## Pillar Scores

| Pillar | Score | Key Finding |
|--------|-------|-------------|
| 1. Copywriting | 3/4 | Good specificity in errors and confirmations; minor ambiguity when server data unavailable |
| 2. Visuals | 3/4 | Clear hierarchy and agent distinction (icon + badge + text); minor refinements possible |
| 3. Color | 3/4 | Correct semantic token usage; could leverage more distinctive agent branding |
| 4. Typography | 4/4 | Consistent two-tier scale (xl headers, sm metadata); no off-scale utilities |
| 5. Spacing | 4/4 | All scale-based Tailwind classes; no arbitrary values |
| 6. Experience Design | 3/4 | Functional end-to-end; the decision inputs a revoke choice needs (scopes, last-used) are still unpublished by the server |

**Overall: 20/24** (Experience Design corrected 2→3 after withdrawing a false blocker; see Pillar 6)

---

## Top 3 Priority Fixes

1. **FIXED DURING THIS AUDIT — scope absence was rendered as a false claim.** `apps/web/src/api/keepling.ts:595` mapped `scope: grant.scope ?? []`, collapsing *"the server did not report a scope list"* into *"this grant holds no scopes."* `AgentGrantList.tsx:277` then rendered that as **"No scopes granted."** Because `grant_response/1` publishes no `scope` key at all today, **every agent row asserted the agent could do nothing** — on the screen where the user decides whether to revoke it, and while the agent in fact held `tasks.read`/`tasks.write`. The sibling fields were already honest (`authorizedAt`/`lastUsedAt` preserve `null` and render "Not yet reported"); scope alone was collapsed. Fixed by preserving `null` through the mapping and rendering "Not yet reported", with a mutation-tested case at `agent-grant-list.test.tsx`. **User impact:** HIGH — a false negative-permission claim on consent UI.

2. **Add scope, authorized_at, last_used_at fields to device-grant response** — The server endpoint exists but `KeeplingWeb.DeviceGrantController.grant_response/1` omits these fields. AgentGrantList.tsx is built to read them and handles their absence gracefully, but renders "No scopes granted" / "Not yet reported" / "Not yet used" in real deployment. Fix: Include scope array and timestamp fields in the response from `Keepling.Accounts.DeviceGrant.list/1`. **User impact:** HIGH — user cannot see what the agent can actually do or when it last acted.

3. **Clarify server-data absence in UI** — When scope/timestamp fields are unavailable (which is every real response today), "No scopes granted" may mislead the user into thinking the agent has zero access, rather than "we don't know yet". Fix: Render "Scopes not yet reported" or similar when optional fields are absent, to distinguish unknown from empty. **User impact:** MEDIUM — affects user understanding of authorization status.

---

## Detailed Findings

### Pillar 1: Copywriting (3/4)

**Strengths:**

- **Confirmation dialog is crystal-clear about consequences** — `apps/web/src/features/agents/AgentGrantList.tsx:356`: "will lose access to Keepling immediately. Its next request will be refused." This tells the user the exact outcome with no ambiguity.
- **Error messages are specific and reassuring** — Line 230: "Couldn't load AI agents. Nothing was changed." The "Nothing was changed" reassurance is excellent for destructive-action context.
- **Recovery state messages are accurate** — Lines 112, 145, 181: Messages like "Claude Code remains authorized." or "Claude Code revoked." use the actual grant label, not generic "the item".
- **Undo control explanations are thorough** — `apps/web/src/features/activity/ActivityList.tsx:213-219` provides specific reasons for each state: "This action can no longer be undone: the undo window expired" (not just "Undo not available").
- **No generic labels** — No "OK", "Submit", "Cancel", or "Click here". All buttons use specific action labels: "Revoke Claude Code", "Keep authorized", "Undo".
- **Loading state is specific** — Line 224: "Loading AI agents…" (not "Loading…").

**Issues:**

- **Ambiguous empty state when server data unavailable** — Lines 277-278 and 301-302 render "No scopes granted" and "Not yet reported" when the server omits these fields. A user seeing "No scopes granted" may infer the agent has zero access (correct interpretation) or may not realize this means "we don't know" (concerning interpretation). The SUMMARY acknowledges this is a server gap, not a frontend bug, but the user-facing message is honest-but-potentially-confusing.
  
  Example: If a user sees AgentGrantList today (with server fields absent), they read:
  - Scopes: "No scopes granted"
  - Last used: "Not yet used"
  
  They may conclude: "This agent has no access and has never acted." But the truth is: "We don't know what it can do, and we don't know if it's used this account."

- **Error message is generic about root cause** — Line 230: "Couldn't load AI agents" doesn't explain why (which today is a server authentication gap). The error is technically accurate but opaque.

**Finding classification:** WARNING — Pillar is substantially met (good specificity), but room for clarity on unknown vs. empty states.

---

### Pillar 2: Visuals (3/4)

**Strengths:**

- **Clear visual hierarchy in agent list** — `apps/web/src/features/agents/AgentGrantList.tsx:268-290`:
  - Primary: Grant label (`text-xl font-semibold`)
  - Secondary: "AI agent" badge (`text-sm font-semibold`)
  - Tertiary: Metadata (Scopes, Authorized, Last used — `text-sm text-muted-foreground`)
  
  This follows the "calm single-column list" style mentioned in the plan (D-23) and matches Things.app conventions.

- **Agent actions visibly distinguished in history** — `apps/web/src/features/activity/ActivityList.tsx:182-195` renders agent facts with:
  - Icon (AgentActorIcon, lines 168-180)
  - Text label (grant label)
  - "AI agent" badge (lines 187-192)
  
  This is "more than colour alone" (plan requirement). Tests confirm it's queryable by accessible name (activity-list.test.tsx:392).

- **Revoke button position reveals-on-row pattern** — Button positioned on the right (line 319), following SessionList precedent. Destructive action is visible but not shouted.

- **Uncertain recovery state has visual presence** — Lines 240-257: Recovery box with status message and conditional retry button clearly signals the uncertain state.

- **Interleaved agent/user facts** — Activity facts from both agents and users render in one ordered list (activity-list.test.tsx:372-385). No separate "agent-only" tab or filter exists.

**Issues:**

- **No explicit heading for agent list** — Unlike SessionList (which has implied heading context from settings), AgentGrantList is just a `<ul>` (line 262). No `<h2>` or `<h3>` announces the section purpose. This is minor for a settings page, but SessionList includes heading context for comparison.

- **"AI agent" badge is visually subtle** — The badge uses neutral `border-border text-sm font-semibold` styling (line 269). It's text-based and distinguishes well, but could be more visually striking (e.g., background color, icon, or accent treatment) to make agent grants stand out at a glance.

**Finding classification:** WARNING — Hierarchy and distinction are correct; minor refinements possible.

---

### Pillar 3: Color (3/4)

**Strengths:**

- **Semantic token usage throughout** — All colors use Tailwind semantic tokens (`border`, `foreground`, `muted-foreground`, `primary`, `card`), never hardcoded hex values or RGB.
- **Destructive action clearly marked** — Revoke button uses `variant="destructive"` (red), distinguishing it from neutral outline buttons.
- **Consistent with SessionList** — AgentGrantList uses the exact same color palette and token names as SessionList, proving consistency across revocable-credential surfaces.
- **No color-only distinction** — Agent facts in ActivityList are distinguished by icon + text + badge, not by color alone (plan requirement T-05-49, activity-list.test.tsx:392).

**Issues:**

- **Neutral branding for agent elements** — The "AI agent" badge and agent-fact rendering use the same neutral border/foreground tokens as everything else. Could benefit from a positive accent color to make agent participation feel "welcome" rather than neutral.

- **No visual accent overuse** — This is good (no false positives), but also means no distinctive "agent" color for quick visual scanning of a long activity history.

**Finding classification:** WARNING — Tokens are correct; room for more distinctive agent branding.

---

### Pillar 4: Typography (4/4)

**Strengths:**

- **Consistent two-tier scale** — Only two font sizes used:
  - `text-xl` for primary labels (AgentGrantList: grant names, ActivityList: "Activity" heading)
  - `text-sm` for secondary content (metadata, badges, messages)
  - Maintains visual hierarchy without introducing noise.

- **Font weights used consistently** — `font-semibold` for labels and key metadata (grant label, "Scopes", "Authorized", actor names), regular for content. Clear information architecture.

- **No off-scale utilities** — The plan noted that `text-xs`, `gap-1.5`, `px-1.5 py-0.5` were found off-scale and fixed in commit `6c7ef99`. Current code contains no such violations.

- **Readable in all contexts** — Typography handles technical details (mutation IDs, timestamps) as well as user-facing explanations without competing scales.

**Finding classification:** PASS — 4/4. Exemplary consistency.

---

### Pillar 5: Spacing (4/4)

**Strengths:**

- **All spacing uses scale-based Tailwind utilities:**
  - List items: `py-6` (AgentGrantList:264, ActivityList:312)
  - Gaps: `gap-2` (AgentGrantList:267), `gap-4` (AgentGrantList:265), `gap-x-4 gap-y-1` (ActivityList:316)
  - Margins: `mt-4` (AgentGrantList:273), `mb-4` (AgentGrantList:240)
  - Padding: `px-2 py-1` (badge; line 269), `p-4` (card; line 229)
  - Vertical rhythm: `space-y-4` (ActivityList:341), `space-y-2` (details; line 117)

- **No arbitrary values** — Grep for `\[.*px\]\|\[.*rem\]` in the component files returns no results. All spacing is from the declared scale.

- **Flex gap instead of margin manipulation** — Components use `gap` in flex layouts, avoiding the fragility of margin-based spacing.

**Finding classification:** PASS — 4/4. Excellent scale adherence.

---

### Pillar 6: Experience Design (2/4)

**Strengths (unit-tested and proven in isolation):**

- **Loading states with correct semantics:**
  - AgentGrantList:224: `role="status"` announces "Loading AI agents…"
  - ActivityList:533: `aria-live="polite"` announces "Loading activity…"
  - Tests: agent-grant-list.test.tsx doesn't explicitly test loading, but ActivityList tests (activity-list.test.tsx) verify loading announcements.

- **Error states with recovery path:**
  - AgentGrantList:228-234: Card with message + "Retry loading AI agents" button
  - ActivityList:540-553: Identical pattern
  - Both follow ErrorBoundary conventions.

- **Empty states without empty table:**
  - AgentGrantList:260: `role="status"` "No AI agents are authorized." (not a `<ul>`; plan requirement met)
  - Tests verify: agent-grant-list.test.tsx:95-103

- **Disabled states during operations:**
  - AgentGrantList:321: Revoke button `disabled={busyInstallationId !== null || recovery !== null}`
  - ActivityList:277: Undo button `disabled={state.kind === 'checking' || state.kind === 'submitting'}`

- **Confirmation for destructive revocation:**
  - AgentGrantList:336-362: AlertDialog with clear title, description, and two actions
  - Focus management: initialFocus="Keep authorized" (line 358), finalFocus=revokeTriggerRef (line 357)
  - SessionList precedent matched exactly.

- **Uncertain recovery handling (not optimistic removal):**
  - AgentGrantList:205-212: When revoke fails with 5xx error, shows recovery box asking to reconcile, doesn't remove row optimistically.
  - Tests: agent-grant-list.test.tsx:149-165, 186-207
  - Matches SessionList pattern (lines 90-149).

- **Per-fact undo for agent actions:**
  - ActivityList:197-296: ActivityUndoControl component
  - Reuses existing getMutation + undoTask path (lines 229, 242-245)
  - Handles all recovery states with appropriate messages (lines 210-221)
  - Tested end-to-end against real stack: activity-list.test.tsx:417-445, plus e2e/agent-access.spec.ts:step 4 (passing)

- **Accessibility throughout:**
  - aria-label on agent badge (ActivityList:188): "AI agent" — proves it's not color-only
  - aria-label on undo button (ActivityList:276): "Undo: {actionCopy[activity.type]}" — specific context
  - aria-atomic and aria-live on message regions (AgentGrantList:364-366, ActivityList:533)
  - Focus trapping in AlertDialog (SessionList pattern)
  - All interactive elements reachable by keyboard

- **Agent/user facts interleaved, not separated:**
  - ActivityList:572-584 renders all activities in one list
  - No filter or tab switcher exists
  - Test: activity-list.test.tsx:372-385

**Critical Issues:**

1. ~~**Server authentication gap blocks AgentGrantList end-to-end**~~ — **WITHDRAWN. This finding was false.** It was taken from `05-09-SUMMARY.md` Deviation 2 without checking the current tree. That gap was recorded as Broken Windows entry **#66 and closed by plan 05-13**, which added owner-session routes rather than widening a pipeline:
   - `apps/server/lib/keepling_web/router.ex:146` — `get "/account/device-grants"` through `[:api, :authenticated]`
   - `apps/server/lib/keepling_web/router.ex:152` — `delete "/account/device-grants/:installation_id"` through `[:api, :authenticated, :mutation]`
   - `apps/web/src/api/keepling.ts:600,616` — the client calls exactly those owner-session paths, not the bearer-only ones.
   - The bearer-only `/api/v1/device-grants` routes still exist and still reject cookies **deliberately** (`device_grant_controller_test.exs:328`). Two routes, one credential class each. `/settings/agents` is reachable and functional for the signed-in user.

2. **Server response omits `scope`, `authorized_at`, `last_used_at`** — `KeeplingWeb.DeviceGrantController.grant_response/1` (`device_grant_controller.ex:167-175`) returns only `client_kind`, `generation`, `id`, `installation_id`, `label`, `revoked`.
   - **Consequence:** all three fields render "Not yet reported" for every agent.
   - **Now honest, after the fix above.** Before it, the scope line actively asserted zero permissions.
   - **Impact on user:** the two facts that should drive a revoke decision — what this agent may do, and when it last did anything — are unavailable. The UI is truthful about not knowing, which is the most it can do from `apps/web`.

3. **Activity undo for agent facts is proven end-to-end.** `e2e/agent-access.spec.ts` steps 1-4 pass (PKCE authorization, `tools/call`, activity attribution, undo reversal). Step 5 was rewritten by 05-13 and now asserts a strictly stronger post-revoke condition scoped to the `Authorized AI agents` list.

**Finding classification:** 3/4 — The implementation is accessible, unit-tested, and matches the `SessionList` precedent it was meant to match. It is not 4/4 because the surface cannot yet tell the user what an agent is permitted to do or when it last acted, and a revoke decision made without those facts is a guess. That is an `apps/server` gap, not a frontend defect — but it is a real limit on the experience, so it is scored as one rather than excused.

---

## Files Audited

- `apps/web/src/features/agents/AgentGrantList.tsx` (372 lines) — Agent grant list with scopes, timestamps, and revoke control
- `apps/web/src/features/agents/agent-grant-list.test.tsx` (280 lines) — Unit tests covering list, empty state, zero-scope, confirmation, uncertain recovery, and reauthentication
- `apps/web/src/features/activity/ActivityList.tsx` (637 lines) — Modified to add ActorLabel, AgentActorIcon, and ActivityUndoControl for agent-aware rendering
- `apps/web/src/features/activity/activity-list.test.tsx` (446+ lines) — Extended with agent interleaving, distinction, undo control, and recovery-state tests
- `apps/web/src/api/keepling.ts` (lines 47-66, 392-401, 587-620) — Added WireAgentGrantSummary type extension, AgentGrant type, listDeviceGrants, revokeDeviceGrant
- `apps/web/src/app/routes.tsx` (lines 10, 364-373) — Mounted AgentGrantList at `/settings/agents` with csrfToken prop
- `apps/web/e2e/agent-access.spec.ts` — Real-stack end-to-end proof (steps 1-4 pass; step 5 blocked by server gap)

---

## Summary

**Phase 5 shipped a consent-and-authorization UI that is well-crafted, unit-tested, and follows the established `SessionList` precedent with high fidelity.** Copywriting is specific, accessibility is thorough, and state handling (loading, error, empty, disabled, confirmation, recovery, undo) is comprehensive. Typography and spacing hold a consistent scale with no arbitrary values.

**The audit found one real frontend defect, and it was on the highest-stakes line of the surface.** The scope field collapsed *unreported* into *empty*, so every agent row read "No scopes granted" — a false statement that the agent held no permissions, on the screen built for deciding whether to revoke it. The sibling timestamp fields were already honest about absence; scope alone was not. Fixed, with a mutation-tested case proving the assertion is not vacuous.

**One remaining gap is real but externally owned.** `grant_response/1` does not publish `scope`, `authorized_at`, or `last_used_at`, so the user still cannot see what an agent may do or when it last acted. The UI now says so plainly instead of guessing. Closing it is an `apps/server` change: publish the three fields and update `packages/contracts/openapi/keepling.yaml`, after which the component picks them up with no rework.

**A note on this audit's own reliability.** Its original first finding — "session cookies are rejected, `/settings/agents` is non-functional, CRITICAL" — was **false**. It was read out of `05-09-SUMMARY.md`, which describes the tree as it stood before plan 05-13 closed that gap (Broken Windows #66) by adding owner-session routes. A summary records what was true when it was written; the router records what is true now. **Audit the tree, not the paperwork** — and treat a phase's own summaries as history rather than as current state.

**Scoring:** Copy, visuals, and color are 3/4 on quality with room for refinement. Typography and spacing are 4/4. Experience Design is 3/4 — the surface works end to end, but a revoke decision made without scopes or last-used is a guess, and that limit is scored rather than excused.

**Missing design contract.** This phase shipped frontend with no `UI-SPEC.md`, which is Broken Windows entry **#67** and the reason this retroactive audit exists. The absence has a cost visible in the findings above: with no contract, "what should an agent row show, and what should it say when it does not know" was never settled before the code was written, and the answer got decided by a `?? []` default instead. The fix is procedural, not cosmetic — a frontend phase gets a UI-SPEC before execution, not an audit after it.
