---
phase: KPL-06
slug: portability-and-trust-release
status: draft
shadcn_initialized: true
preset: "base-rhea / Base UI / Stone (effective code bLTj5vaS) — inherited from apps/web, unchanged"
created: 2026-09-11
---

# Phase KPL-06 — UI Design Contract

> Design contract for the narrow UI surface Phase 6 actually touches. This phase is
> overwhelmingly non-UI (neutral export, CI/release evidence, signing/SBOM, governance docs,
> the trust oracle, operator recovery) — none of that has a screen and none of it is specified
> here. Only three surfaces render pixels this phase changes:
>
> 1. **D-38 / window 76 — the agent consent screen** (`AgentGrantList.tsx`, fed by
>    `device_grant_controller.ex:167-175` `grant_response/1` and `DeviceGrantSummary` in
>    `packages/contracts/openapi/keepling.yaml`).
> 2. **O-44 — `packages/web-ui/src/tasks/ConflictResolver.tsx`**, widened from a title-only
>    single-choice chooser to a per-field, lifecycle/Trash-aware chooser (coupled to O-43 per
>    D-37 — a durable refusal record the user cannot act on is not a fix).
> 3. **O-22 — `apps/desktop/renderer/DesktopShell.tsx` keyboard command dispatch**, routed
>    through `packages/web-ui/src/workspace/Workspace.tsx`'s `attemptNavigation` dirty-guard
>    instead of calling `facade.setRoute`/`facade.selectTask` directly.
>
> Everything else in this contract exists only to say **"no change"** explicitly, so the checker
> does not have to guess whether an omission is a gap or a decision.
>
> This document extends `01-UI-SPEC.md` (browser baseline) and `03-UI-SPEC.md` (desktop
> extension) verbatim. It declares **zero new tokens, zero new colors, zero new type sizes, and
> zero new shadcn components.** Where an interaction question remains genuinely open after
> reading both prior contracts, resolution follows Things (Cultured Code), per the standing
> project UI reference and 06-CONTEXT.md's explicit instruction.

---

## Design Intent

Unchanged. Keepling Web/Desktop remain a calm, task-first workspace; routine success stays
quiet, uncertainty/conflict/recovery stay visible until resolved. Phase 6 adds no new visual
language — it corrects two places where the existing contract's own principles ("state never
depends on color," "absent ≠ empty," "a durable record the user cannot act on is not a fix")
were not yet honored in shipped code. A phase named "Trust Release" fixing a trust-surface defect
must look and read exactly like the rest of the product, not like a bolt-on "security settings"
page — same list style, same typography scale, same copy voice.

Sources: `06-CONTEXT.md` D-37, D-38; `01-UI-SPEC.md` (baseline, unchanged); `03-UI-SPEC.md`
(desktop extension, unchanged); `05-UI-REVIEW.md` (origin of window 76 and the absent-vs-empty
rule); live source at `apps/web/src/features/agents/AgentGrantList.tsx`,
`packages/web-ui/src/tasks/ConflictResolver.tsx`, `apps/desktop/renderer/DesktopShell.tsx`,
`packages/web-ui/src/workspace/Workspace.tsx`.

---

## Design System

No change from `01-UI-SPEC.md`/`03-UI-SPEC.md`. Restated for this phase's own provenance record
rather than re-derived:

| Property | Value | Source |
|----------|-------|--------|
| Tool | shadcn 4.19.0, copied/owned components added individually | `pnpm --dir apps/web exec shadcn info`, re-run 2026-09-11 |
| Preset | `base-rhea`, Base UI, Stone base, CSS variables, default `0.5rem` radius, subtle menu accent, preset code `bLTj5vaS` | `apps/web/components.json` + `shadcn info`, unchanged since 03-UI-SPEC |
| Component library | Base UI; native HTML semantics; no custom ARIA grid | 01-UI-SPEC, unchanged |
| Icon library | Lucide React, 18px at 1.75px stroke, always with text or an accessible name | 01-UI-SPEC, unchanged |
| Font | `system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif` | 01-UI-SPEC, unchanged |
| Styling | Tailwind CSS v4 backed by semantic CSS custom properties | 01-UI-SPEC, unchanged |
| Theme | Light and dark semantic values; explicit choice, else `prefers-color-scheme` | 01-UI-SPEC, unchanged |

This phase adds **no new packages, no new tokens, no new components** to `packages/design-tokens`
or `apps/web`. Everything below reuses the Phase 1/3 spacing scale, typography scale, and color
roles verbatim.

---

## Component Inventory

Enumerated by `pnpm --dir apps/web exec shadcn info` — 3 components — `shadcn@4.19.0` —
2026-09-11. Unchanged from `01-UI-SPEC.md`/`03-UI-SPEC.md`: `alert-dialog`, `button`, `drawer`.
This phase's three surfaces are all existing local product components (`AgentGrantList`,
`ConflictResolver`, `DesktopShell`) extended in place — no new shadcn primitive is required for
any of D-38, O-44, or O-22. If a widened `ConflictResolver` needs a per-field radio-style choice
control, reuse the existing native `<input type="radio">`/`<fieldset>` pattern already established
for the Phase 1 organization pickers rather than adding `radio-group` — this keeps the inventory
at 3 unless a real accessibility gap is found during implementation, in which case adding
`radio-group` individually (never `add --all`) is pre-approved and must be recorded in the
Registry Safety table below at that time.

---

## Spacing Scale

Unchanged — reuse `01-UI-SPEC.md`'s scale verbatim (`space.xs` 4px through `space.3xl` 64px, 44×44px
minimum touch targets, 52px minimum row height). No new spacing value is introduced by this phase.

---

## Typography

Unchanged — reuse `01-UI-SPEC.md`'s four sizes (Label 14/600, Body 16/400, Heading 20/600, Display
28/600) and two weights verbatim. Agent-grant scope/timestamp values and conflict field values are
Body (16/400); the "AI agent" badge and per-field labels are Label (14/600) — the same roles
`AgentGrantList.tsx` and `ConflictResolver.tsx` already use elsewhere on their own screens.

---

## Color

Unchanged — reuse `01-UI-SPEC.md`'s 60/30/10 roles and `03-UI-SPEC.md`'s desktop extension
verbatim. No new semantic color is introduced. Specifically for this phase's three surfaces:

- **Agent consent screen:** the "AI agent" badge, scope chips, and timestamp values stay on the
  existing neutral `border`/`foreground`/`muted-foreground` tokens (05-UI-REVIEW Pillar 3 already
  flagged the badge as visually subtle and this phase does not change that — it is a content-truth
  fix, not a rebrand). The **Revoke** action keeps `variant="destructive"`, unchanged.
- **Conflict resolver:** each field's `Your version`/`Current version` labels and the selected
  choice use the existing accent (10%) role for the selected radio/marker — never color alone; the
  label text and a `Selected` visual marker (border + weight, matching 01-UI-SPEC's "state never
  depends on color" rule) carry the meaning.
- **O-22 fix:** purely behavioral; introduces no new visual state.

---

## The three touched surfaces

### 1. Agent consent screen (D-38 / window 76)

**Contract, extending `AgentGrantList.tsx`'s existing absent-vs-empty pattern (05-UI-REVIEW's
fix, which this phase must never regress):**

| Field | Absent (server never reported / not yet computed) | Empty (server reported, genuinely none) | Present |
|-------|------|-------|---------|
| Scopes | `Not yet reported` (renders when the wire value is `null`, never when it is `[]`) | `No scopes granted` (renders only when the wire value is a literal `[]`) | Chips, one per scope string, in the existing `<code>` chip style at `AgentGrantList.tsx:286` |
| Authorized | `Not yet reported` (wire value `null`) | *(not applicable — an existing grant always has an authorization instant; this field is never legitimately empty)* | `exactAuthorizedTime`-formatted `<time>`, unchanged formatting |
| Last used | `Not yet used` (wire value `null` AND the grant has genuinely never been used — see below) | *(not applicable — see below)* | `exactAuthorizedTime`-formatted `<time>`, unchanged formatting |

**The absent-vs-empty distinction is preserved by construction, not by convention:** `scope` stays
a nullable array (`null` = server did not report; `[]` = server reported zero scopes) exactly as
05-UI-REVIEW fixed it. This phase's job is to make the server actually publish real values instead
of a nullable placeholder — once `grant_response/1` publishes the real `scope` array (already
persisted on `Keepling.Accounts.DeviceGrant`, per RESEARCH.md's Pitfall 5 finding, no schema
change needed for this field), `null` becomes structurally unreachable for `scope` and the row
always renders either chips or `No scopes granted`, honestly.

**`last_used_at` has a genuine third state this phase must not collapse into either existing
copy string.** RESEARCH.md Pitfall 5 verified: no `last_used_at` column and no write path exist
today. Until the write path lands, **`Not yet used` is only honest for a grant where "never used"
is a proven fact** (e.g., a freshly authorized grant with zero recorded activity). For an
*existing* grant where the server genuinely cannot say whether it has been used (no column exists
yet to answer the question), render **`Not yet reported`** — the same "unknown" copy already used
for scope — never `Not yet used`, which asserts a fact nobody measured. Concretely: `lastUsedAt:
null` must map to `Not yet reported` (unknown), and a real future zero-activity state (once the
column exists and a grant provably has zero rows) maps to a distinct, explicitly zero-activity
copy string, `Not yet used`. **Do not ship a single `null` → `Not yet used` mapping** — that is
exactly the same class of collapse 05-UI-REVIEW fixed for scope, applied to a different field.

**Copywriting (new/updated only — everything else in `AgentGrantList.tsx` is unchanged):**

| Element | Exact copy |
|---------|------------|
| Scope unknown | Not yet reported |
| Scope genuinely none | No scopes granted |
| Authorized-at unknown | Not yet reported |
| Last-used unknown (no measurement capability yet) | Not yet reported |
| Last-used genuinely zero (measurement exists, grant has zero recorded activity) | Not yet used |

No new dialog, no new route, no new component. `revoke` confirmation copy is unchanged from
05-UI-REVIEW's already-audited "will lose access to Keepling immediately. Its next request will be
refused."

**Accessibility:** unchanged from the existing audited implementation (icon-free text distinction,
`role="status"` regions, `aria-live` announcements) — no new accessible-name or live-region
requirement is introduced by publishing real values into an existing shape.

### 2. Multi-field, lifecycle-aware conflict resolver (O-44, coupled to O-43 per D-37)

**Current defect, confirmed against source:** `ConflictResolver.tsx` renders exactly one field
(`conflict.mine` / `conflict.current`, both bare strings implying "title") with two whole-conflict
choices, `Use mine`/`Use current`. D-37 rules this "is not separable" from O-43 — a refusal that
lands in a durable table the person cannot act on is not a fix, so this contract covers both the
data model the resolver renders and the interaction it offers.

**Contract, extended from `01-UI-SPEC.md`'s existing Conflict Resolution section (heading, body,
`Keep editing`, six-line notes disclosure, "choice state uses label, border, and selected
control — not color alone" all carry over verbatim):**

- **Per-field, not per-conflict.** The resolver renders one row per affected field (title, notes,
  planned date, deadline, project, tags — whatever the conflict payload actually names), each with
  its own `Your version` / `Current version` values and its own `Use mine` / `Use current` choice.
  A field the conflict payload does not name is not shown — absent fields are not rendered as
  empty rows (same "absent ≠ empty" discipline as D-38).
- **Lifecycle/Trash divergence gets its own row, not a title diff.** Where the underlying conflict
  is a lifecycle disagreement (e.g., one side completed the task, the other trashed it — the class
  O-44 names as uncovered), render a row labeled with the lifecycle field name (e.g.,
  `Completion`/`Trash status`), with `Your version` and `Current version` stated in plain lifecycle
  language (`Completed`, `Active`, `Trashed`, `Restored`) rather than raw enum values or a diff of
  unrelated title text standing in for it. **Things reference (open interaction question, resolved
  per project standing instruction):** Things never shows a diff view for its own local
  conflicts — it is single-writer per device and has no server-mediated conflict UI to borrow
  from directly, so no Things-derived visual pattern applies here beyond the general principle
  already locked in 01-UI-SPEC (plain-text values, label + border for selection, no color-only
  state) — that principle is what this bullet applies to the new lifecycle row.
- **The durable refusal record (O-43's half) must be visible from here.** If a refusal has no live
  conflict UI shown yet (e.g., the person is not currently viewing the affected task when a pull
  refuses to overwrite their unresolved local value), it must not silently vanish. Reuse the
  existing **Recovery strip** contract from `01-UI-SPEC.md` (`Persistent latest eligible action`):
  a refused-and-durably-recorded change surfaces there with copy naming the task and offering
  navigation to its now-inline conflict resolver, exactly the same way an eligible Undo already
  surfaces. No new UI surface — the existing recovery strip's job widens to include this class.
- **Independent per-field resolution, one submission.** Choosing `Use mine`/`Use current` per row
  stages that field's choice; nothing mutates until the person confirms the whole set (reuse the
  existing single `Save`-equivalent submission point in the surrounding editor — do not add a
  second explicit confirm step per row, matching 01-UI-SPEC's "no save-on-blur, no premature
  claim" discipline).
- **Nonconflicting fields are preserved exactly as `01-UI-SPEC.md` already requires** — this
  contract only widens which fields participate in the compared set; it does not change what
  happens to fields outside that set.

**Copywriting (extends the existing heading/body verbatim; adds per-field labels only):**

| Element | Exact copy |
|---------|------------|
| Heading (unchanged) | This task changed somewhere else. |
| Body (unchanged) | Review the affected fields before saving again. |
| Per-field label pattern | `{Field name}` — e.g. `Title`, `Notes`, `Planned date`, `Deadline`, `Project`, `Tags`, `Completion`, `Trash status` |
| Per-field values (unchanged pattern) | `Your version` / `Current version` |
| Per-field choice (unchanged pattern) | `Use mine` / `Use current` |
| Recovery-strip surfacing (new) | `{Task title} changed while you were away. Review the conflict.` — action: `Review conflict` |

**Accessibility:** each field row is its own labeled group (`fieldset`/`legend` or
`role="group"`/`aria-labelledby`) so a screen-reader user can tell which value belongs to which
field — the current single unlabeled pair of paragraphs does not scale past one field and must not
ship unchanged into a multi-field resolver. Radio-style choice per row, not two disconnected
buttons, so assistive tech reports it as one mutually-exclusive per-field decision (matching
native `<fieldset>`/`<input type="radio">` semantics, consistent with the Component Inventory
note above).

### 3. Guarded keyboard navigation (O-22)

**Current defect, confirmed against source:** `DesktopShell.tsx`'s `new-task`, `go-inbox`, and
`go-today` command handlers call `facade.setRoute(...)` directly; `Workspace.tsx`'s
`attemptNavigation` — the function that checks `dirty` and opens the `Discard unsaved changes?`
dialog before navigating — is never consulted for these keyboard paths, even though mouse-driven
navigation (row/nav-link clicks) already goes through it.

**Contract — this is a behavioral fix with a zero-pixel-change UI surface, restated here because
D-37 treats it as coupled to a data-loss class, not because it needs new visual design:**

- Every keyboard command in `DesktopShell.tsx` that would change route or selected task
  (`new-task`, `go-inbox`, `go-today`, and any future command of the same shape) must route
  through the same `attemptNavigation` path `Workspace.tsx` already exposes to mouse navigation —
  not call `facade.setRoute`/`facade.selectTask` directly.
- When the editor is dirty, the keyboard command must produce the **exact same dialog** already
  specified in `01-UI-SPEC.md`/`03-UI-SPEC.md`: heading `Discard Unsaved Changes?`, body `These
  edits haven't been saved.`, actions `Save Changes` / destructive `Discard Changes` / safe `Keep
  Editing`, initial focus `Keep Editing`. No new copy, no new dialog variant — the defect is that
  keyboard shortcuts currently bypass this dialog entirely, not that the dialog itself needs
  changing.
- After the dialog resolves (save, discard, or cancel), the originally-requested navigation
  either completes or is abandoned exactly as it already does for the mouse path — no new
  post-dialog state is introduced.

No new copywriting, no new color, no new component. This entry exists in this UI-SPEC solely so
the checker and executor can verify the fix against a named contract rather than trusting an
unrecorded behavioral patch.

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|--------------|
| Official `@shadcn` | `alert-dialog`, `button`, `drawer` (unchanged) | Official registry only; `shadcn info` re-verified 2026-09-11, no drift from 03-UI-SPEC |
| Third-party | None | Not applicable — `registries` remains empty in `apps/web/components.json` |

No new registry or block is introduced by this phase. If implementation finds a genuine
accessibility gap that only a `radio-group` primitive closes (see Component Inventory), it must be
added individually, from the official registry only, and this table amended before the phase
closes — never `add --all`.

---

## UI Considerations

Shape-rooted coverage for the three touched surfaces only; everything else in the product's UI
considerations is unchanged from `01-UI-SPEC.md`/`03-UI-SPEC.md` and is not re-probed here.

| Category | Element(s) | Status | Resolution / Reason |
|----------|------------|--------|----------------------|
| Empty | Agent list | ✅ explicit | Unchanged — `01-UI-SPEC.md`'s "No AI agents are authorized." `role="status"` empty state, not re-touched by this phase |
| Populated | Agent list, conflict resolver | ✅ explicit | Agent rows: existing list pattern, now with real (not null-defaulted) scope/timestamp values. Conflict resolver: one row per affected field, per the contract above |
| Partial | Agent list (per-field unknown), conflict resolver (per-field independent choice) | ✅ explicit | Absent-vs-empty distinction table above (agent list); nonconflicting fields preserved, nonparticipating fields simply absent (conflict resolver) |
| Zero / one / many | Conflict resolver fields | ✅ explicit | Zero affected fields cannot occur (a conflict always names at least one); one field renders one row; many fields render one row each, same geometry, no card grid |
| Error | Conflict resolver submission | ✅ explicit | Reuses `01-UI-SPEC.md`'s existing rejected/uncertain-result copy (`Checking whether your change was saved…`, etc.) — unchanged, not duplicated here |
| Overflow / long text | Conflict resolver per-field values | 🧪 backstop | Reuses `01-UI-SPEC.md`'s existing six-line-collapse-with-disclosure pattern per field, now applied per row instead of once; held-out long-text fixtures extend to notes/project/tag field rows |

---

## Verification Evidence Required

- **D-38:** a test proving `grant_response/1` publishes real `scope` (array, never `null` once the
  field is wired) and that `AgentGrantList.tsx` renders `No scopes granted` only for a literal
  `[]` and `Not yet reported` only for `null` on any field where `null` remains reachable
  (`authorizedAt`/`lastUsedAt` until their respective write paths exist) — a mutation-tested
  regression mirroring 05-UI-REVIEW's existing `agent-grant-list.test.tsx` case, extended rather
  than replaced.
- **O-44/O-43:** fixture-driven tests proving (a) a multi-field conflict renders one row per
  affected field with correct per-row values, (b) a lifecycle/Trash-divergence conflict renders
  its own labeled row rather than being silently dropped or misrendered as a title diff, (c) an
  unresolved refusal with no open conflict UI appears in the recovery strip and navigates to the
  resolver, (d) per-field choices submit as one set without touching nonconflicting fields.
- **O-22:** an Electron E2E case proving `Command-1`/`Command-2`/New Task-shortcut navigation while
  the editor is dirty opens the exact `Discard Unsaved Changes?` dialog (not a silent navigate),
  and that resolving it produces the same outcome as the equivalent mouse-driven navigation
  already covered.
- Visual regression is **not** required beyond the above — none of the three fixes changes layout,
  color, or type scale; existing 03-UI-SPEC appearance-matrix coverage remains sufficient.

---

## Checker Sign-Off

- [ ] Dimension 1 Copywriting: PENDING
- [ ] Dimension 2 Visuals: PENDING
- [ ] Dimension 3 Color: PENDING
- [ ] Dimension 4 Typography: PENDING
- [ ] Dimension 5 Spacing: PENDING
- [ ] Dimension 6 Registry Safety: PENDING

**Approval:** draft — awaiting `gsd-ui-checker` review.
