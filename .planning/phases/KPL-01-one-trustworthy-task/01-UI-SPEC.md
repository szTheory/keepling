---
phase: KPL-01
slug: one-trustworthy-task
status: approved
shadcn_initialized: true
preset: "base-rhea / Base UI / Stone (effective code bLTj5vaS)"
created: 2026-08-30
reviewed_at: "2026-08-30T20:21:09Z"
---

# Phase KPL-01 — UI Design Contract

> Approved visual and interaction contract for One Trustworthy Task. Verified across all six UI quality dimensions and the post-verification UI-consideration probe.

---

## Design Intent

Keepling Web is a calm, task-first workspace, not an administration dashboard. Routine success stays quiet; uncertainty, conflict, and recovery remain visible until resolved. Things is the interaction-quality reference, but Keepling uses its own warm-neutral visual language and makes server acknowledgement, Today membership reasons, activity, and recovery more explicit.

The palette below is the exact Phase 1 implementation baseline, not a final brand or logo decision. Colors are exposed through semantic DTCG-compatible roles so a later brand phase can revise values without changing component meaning. No logo, custom wordmark, mascot, or final product icon is specified in this phase.

Sources: `01-CONTEXT.md` D-09–D-13, D-27–D-30, D-36–D-38, D-40–D-44, D-51–D-52, D-56–D-63; `docs/brand/BRAND-SEED.md`; initialized `apps/web/components.json`.

---

## Design System

| Property | Value | Source |
|----------|-------|--------|
| Tool | shadcn 4.19.0, copied/owned components added individually | Initialized project evidence |
| Preset | `base-rhea`, Base UI, Stone base, CSS variables, medium `0.5rem` radius, default/subtle menu | `components.json` and `shadcn info` |
| Component library | Base UI; retain native HTML semantics and do not create an ARIA grid | Initialized project + D-13 |
| Icon library | Lucide React, normally 18px at 1.75px stroke; icons always have text or an accessible name | `components.json`; default |
| Font | `system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif`; headings inherit | Brand seed + initialized CSS |
| Styling | Tailwind CSS v4 backed by semantic CSS custom properties; cross-platform truth lives in DTCG-compatible tokens, not utility class names | Repository/architecture guidance |
| Theme | Light and dark semantic values; follow explicit user choice, otherwise `prefers-color-scheme` | Brand seed default |

Component styling is quiet and structural: hairline separators, one raised detail surface, limited shadows, no gradients, glass, card grids, confetti, decorative productivity imagery, or perpetual animation. Pills are reserved for tags and short state/reason labels.

---

## Spacing Scale

Declared values (all layout spacing is a multiple of 4):

| Token | Value | Usage |
|-------|-------|-------|
| `space.xs` | 4px | Icon/text gap, reason-label internal gap |
| `space.sm` | 8px | Compact controls, row metadata, field help |
| `space.md` | 16px | Default control and form-field separation |
| `space.lg` | 24px | Pane padding and grouped form sections |
| `space.xl` | 32px | Major content groups |
| `space.2xl` | 48px | Empty-state and page-section separation |
| `space.3xl` | 64px | Authentication-page and wide-layout breathing room |

Exceptions: interactive targets are at least 44×44px even when the visible icon or completion control is smaller. One-pixel borders and the 2px focus ring are strokes, not spacing tokens. Task rows are at least 52px high.

---

## Typography

Use exactly four sizes and two weights. Do not introduce display fonts or extra weight steps.

| Role | Size | Weight | Line Height | Usage |
|------|------|--------|-------------|-------|
| Label | 14px | 600 | 1.4 | Field labels, section labels, metadata emphasis, buttons |
| Body | 16px | 400 | 1.5 | Task titles, form values, messages, navigation |
| Heading | 20px | 600 | 1.25 | Pane, dialog, and list-section headings |
| Display | 28px | 600 | 1.2 | Route title and authentication title only |

Use tabular numerals for dates, revision values, and technical details. User-entered task content always uses the body family and renders as untrusted plain text.

---

## Color

The 60/30/10 ratio describes visual allocation, not a requirement to fill exactly ten percent of pixels. Stone/shadcn variables may supply low-emphasis borders and muted states, but the semantic values below control branded surfaces and actions.

| Role | Light | Dark | Usage |
|------|-------|------|-------|
| Dominant (60%) | Canvas `#F7F2E8` | Canvas `#1C1917` | App background and list pane |
| Secondary (30%) | Surface `#FFFCF7` | Surface `#24201D` | Detail pane, dialogs, menus, sidebar-selected neutral surface |
| Primary text | `#211E1A` | `#F5EFE5` | Headings, task titles, field values |
| Muted text | `#696158` | `#C7BBAE` | Metadata and helper copy; never required state alone |
| Accent (10%) | Aubergine `#6F4A63` with `#FFF8E9` foreground | Mauve `#D29ABF` with `#201B22` foreground | Primary CTA, selected-navigation marker, active Today control, links, focus ring |
| Destructive | `#A33B32` with white foreground | `#F2A39B` with `#24201D` foreground | Trash, revoke, and confirmed discard actions only |

Accent is reserved for: the Add task button, the currently selected navigation marker, active Today placement, inline links/recovery actions, and the 2px `:focus-visible` ring with 2px offset. It is not applied to every button, card, icon, tag, date, or success state. Marigold remains an identity/meaningful-moment seed and is not the Phase 1 generic action, warning, or focus color.

All semantic pairings must meet WCAG 2.2 AA in light and dark modes. State never depends on color: selected navigation also uses position/weight, Today reasons use text, destructive controls use explicit verbs, and conflict/error surfaces use an icon, heading, and message. Forced-colors mode must retain native outlines and boundaries.

---

## Responsive Workspace Contract

### Wide viewport — 1024px and above

Use a three-region list-and-detail workspace:

1. A 224px navigation sidebar with the global Add task control.
2. A task-list pane clamped between 360px and 440px.
3. A flexible detail pane with a 480px minimum content area and a form measure capped at 720px.

The selected task/editor is the workspace focal point: it occupies the largest readable area, uses the raised secondary surface, and carries the strongest heading hierarchy. Visual eye order is selected task/editor first, active list context and selected row second, and the global Add task control third. Navigation and inactive rows stay lower contrast so they orient without competing. When no task is selected, priority shifts to the active list first and Add task second; on narrow routes, the visible editor or list becomes the single focal surface.

The list and detail panes scroll independently. The route remains canonical: selecting a task updates the URL and browser history even when its editor appears beside the list. Pane boundaries use separators, not separate floating cards.

### Narrow viewport — below 1024px

Show one routed surface at a time. A compact header opens semantic navigation in a drawer. Selecting a task navigates to the same canonical task editor as a full page; browser Back returns to the prior list and stable scroll/focus position. Use 16px horizontal page padding below 640px and 24px from 640–1023px. No horizontal page scrolling is permitted at 320px CSS width.

Dirty navigation intercepts route changes, Back, nav selection, task selection, and logout with the same Save changes / Discard changes / Stay here decision. It never saves on blur.

### Navigation

Primary navigation order is Inbox, Today, Upcoming, Completed. Secondary navigation is Projects, Tags, Trash, then Settings/Sessions. Use native links inside `nav` landmarks. The active route has an accent edge/marker, semibold label, and `aria-current="page"`; color alone is insufficient. Long project/tag names truncate to one line in navigation, expose the full plain-text value on focus/hover, and remain fully visible in their management/editor views.

---

## Component Inventory

| Component | Contract |
|-----------|----------|
| App shell | Semantic header/nav/main landmarks; wide three-region layout and narrow routed layout |
| Quick capture | Global title field, visible Inbox destination, optional Add to Today checkbox/switch, Add task action; separate from full editor |
| Task list | `ul`/`li`, never ARIA grid; fixed semantic sections, stable keyed rows, explicit Load more |
| Task row | 44px completion button, title, metadata/reason text, overflow actions; whole row is not a nested button |
| Task editor | Explicit Save changes and Cancel editing; Inbox adds Save & move out of Inbox; no save-on-blur |
| Organization fields | One project combobox and multi-tag picker; archived assignments remain named but cannot be newly chosen |
| Date fields | Planned date and Deadline are separate civil-date fields; show account timezone helper text |
| Recovery strip | Persistent latest eligible action with exact Undo action; toast may only supplement it |
| State panel | Persistent inline information for updating, unknown result, auth expiry, stale cursor, conflict, and unrecoverable failure |
| Conflict resolver | Inline at the top of the editor, not a transient dialog; compares affected fields only |
| Activity list | Newest first; actor, semantic action, exact outcome, accepted account-timezone time, recovery state; explicit Load earlier activity |
| Dirty-work dialog | Save changes, Discard changes, Stay here; initial focus on Stay here |
| Session list | Current marker, editable label, client kind, created time, coarse recent activity, Revoke session |
| Empty state | Text-led and compact; no logo or mascot dependency |

Use shadcn official components only where they add accessible behavior: Button, Dialog/Alert Dialog, Drawer, Dropdown Menu, Popover, Select/Combobox, Checkbox, Input, Textarea, Label, Separator, Skeleton, and Tooltip. Add each individually. Keep task rows, lists, status panels, activity, and recovery surfaces as small local components rather than forcing them into generic cards.

---

## Core Interaction Contracts

### Capture and editing

- Quick capture always shows `Destination: Inbox`; navigation context never changes it. The only optional placement control is `Add to Today`.
- Title is required. Use an auto-growing plain-text field up to three visible lines; notes use a multiline textarea. Never interpret task content as markup.
- Submitted text remains visible and editable only after the current request resolves. During submission, label the action `Adding…` or `Saving…`, prevent accidental duplicate activation in the view, and retain the original mutation identity for status checks/retry.
- Do not clear quick capture, close the editor, remove a row, or claim success until the server returns the exact acknowledgement.
- On validation failure, place a concise error next to the affected field, focus the first invalid field after the summary is announced, and preserve every field.
- Inbox editors show both `Save changes` and `Save & move out of Inbox`. Ordinary Save never implies clarification.
- Planned date and Deadline remain visually separate. Show `Dates use {Account timezone}`. If planned is after deadline, preserve both and show the non-blocking message `Planned date is after the deadline. Both dates will be saved.`

### Lists and lifecycle

- Inbox is a flat newest-first list with no reorder affordance.
- Today has fixed Overdue and Today headings. Each row states why it appears: `Planned`, `Deadline`, `Overdue deadline`, or a combined phrase such as `Planned today · Deadline Sep 2`.
- Today ordering supports pointer drag as an enhancement and an always-available row menu with `Move earlier` and `Move later`. Keyboard users never need drag-and-drop. The row moves only after acknowledgement. A scoped-order conflict keeps the accepted order visible and offers Refresh.
- Upcoming is read-only, grouped by future account civil date. A row can state a Today reason and a later deadline without collapsing them.
- A newly completed task moves, after acknowledgement, into the expanded Completed today section at the bottom of the current list, newest first. Older completions appear in the Completed route grouped by completion date.
- Trash stays a separate secondary route. Restore removes the acknowledged row from Trash, keeps the user in Trash, and announces actual destinations, for example `Task restored to Inbox and Today.`
- Initial loading never renders an empty state. Background refresh retains the last accepted rows and adds `Updating…`; refresh failure retains those rows and offers `Retry updating {view}`.
- Pagination is always a visible button: `Load more tasks` or `Load earlier activity`. On success, focus the first appended row/activity item.

### Mutation acknowledgement and recovery

| State | Presentation and action |
|-------|-------------------------|
| Not submitted | No remote-state claim; dirty editor shows `Unsaved changes` |
| In flight | Keep draft/row in place; show action-specific progress text beside the control |
| Acknowledged | Apply returned canonical snapshot, announce concise result in a polite live region, and expose eligible undo in the persistent recovery strip |
| Result unknown | Persistent panel: `Checking whether your change was saved…` with `Check again`; never say failed or mint a new mutation identity |
| Authentication required | `Sign in again to finish saving. Your changes are still here.` with `Sign in and continue`; preserve draft and submitted identity |
| Stale cursor/view | Keep last accepted content; `This view changed while you were reading it.` with `Refresh view` |
| Conflict | Open the persistent inline resolver; do not overwrite either version |
| Unrecoverable | Name the failed operation, confirm what is still preserved, and give the next safe action or support-details disclosure |

Only one latest eligible domain undo is shown persistently across routes. Use a precise phrase such as `Task completed. Undo completion` or `Task moved to Trash. Undo trash`; never expose the opaque handle. Native browser text undo remains untouched—Cmd/Ctrl-Z is not bound to domain undo.

### Focus and keyboard behavior

- Use logical DOM/Tab order, native Enter activation, Escape to cancel/close, and Cmd/Ctrl-Enter to submit the active capture/editor form.
- Every interactive control has a visible 2px accent `:focus-visible` ring with 2px offset; no focus outline is clipped by pane overflow.
- Preserve focus by stable task identity during refresh. When an acknowledged action removes the focused row, focus the next row, then previous row, then list heading.
- Opening a task focuses its route heading only on narrow navigation; on wide layouts, preserve the selected row and move editor focus only after explicit keyboard activation.
- Dialogs return focus to their trigger. The conflict resolver focuses its heading, then returns to the initiating Save action or first affected field after resolution.
- Outcome announcements use a single polite live region and never steal focus. Authentication expiry and destructive confirmations use assertive announcement only when immediate attention is required.

### Conflict resolution

Render conflict resolution inline above the task form so it survives route layout changes and remains visible until addressed. Heading: `This task changed somewhere else.` Body: `Review the affected fields before saving again.`

For each affected field, show labeled `Your version` and `Current version` plain-text values plus `Use mine` and `Use current`. Preserve all nonconflicting draft fields. Allow `Keep editing` to return to the form without mutation. Resolution submits a new mutation identity against the latest revision. Long notes collapse after six lines with a keyboard-operable `Show full value` disclosure. Choice state uses label, border, and selected control—not color alone.

### Motion

Use 160ms ease-out for direct hover/focus/row acknowledgement and at most 180ms for drawers/dialogs. Completion, restore, and acknowledged list movement may use opacity plus no more than 4px translation. No correctness is encoded only in motion. Under `prefers-reduced-motion: reduce`, use immediate changes or an opacity transition no longer than 100ms; disable smooth scrolling, drag animation, skeleton pulsing, and decorative transitions.

---

## Copywriting Contract

### Primary and form actions

| Element | Exact copy |
|---------|------------|
| Global primary CTA | Add task |
| Quick-capture prompt | What do you want to keep? |
| Capture destination | Destination: Inbox |
| Optional placement | Add to Today |
| Editor primary | Save changes |
| Inbox clarification | Save & move out of Inbox |
| Editor secondary | Cancel editing |
| Reauthentication | Sign in and continue |

### Empty states

| View | Heading | Body / next step |
|------|---------|------------------|
| Inbox | Inbox is clear | Captured tasks appear here until you move them out. Add task. |
| Today | Nothing for Today | Add a task or choose an existing task to make it part of today. |
| Upcoming | Nothing upcoming | Tasks with future planned dates or deadlines appear here. |
| Completed | Nothing completed yet | Completed tasks will appear here with their accepted completion date. |
| Trash | Trash is empty | Tasks moved to Trash stay recoverable here. |
| Activity | No activity yet | Accepted changes to this task will appear here. |

### Error and recovery states

| State | Exact copy / action |
|-------|---------------------|
| Initial load failure | `Couldn’t load {view}. Your tasks weren’t changed.` — Retry loading {view} |
| Background refresh failure | `Couldn’t update this view. Showing the last loaded version.` — Retry updating {view} |
| Unknown mutation result | `Checking whether your change was saved…` — Check again |
| Authentication expired | `Sign in again to finish saving. Your changes are still here.` — Sign in and continue |
| Conflict | `This task changed somewhere else. Review the affected fields before saving again.` — Review changes |
| Stale pagination cursor | `This view changed before more items could load.` — Refresh view |
| Reorder conflict | `Today changed elsewhere. Refresh the list before moving this task.` — Refresh Today |
| Generic safe fallback | `Couldn’t {action}. Nothing was changed.` — use a named action-object label such as `Retry saving task`, only when the server contract proves rejection/no effect |

Never use `Oops`, `Something went wrong`, `probably`, or celebratory productivity language.

### Consequential and destructive actions

| Action | Confirmation approach and exact copy |
|--------|--------------------------------------|
| Move one task to Trash | No pre-confirmation because the action is recoverable; after acknowledgement show `Task moved to Trash. Undo trash` persistently |
| Discard editor changes | Alert dialog: `Discard unsaved changes? These edits haven’t been saved.` Actions: `Keep editing` and destructive `Discard changes` |
| Log out with dirty work | Alert dialog: `Log out and discard unsaved changes? Saved tasks will remain in Keepling.` Actions: `Stay here` and destructive `Discard changes and log out` |
| Revoke another session | Alert dialog: `Revoke {session label}? Keepling on that device will need to sign in again.` Actions: `Keep session active` and destructive `Revoke session` |
| Revoke current session | Use the logout flow and name that the current browser will sign out |
| Archive project/tag | Inline confirmation naming what changes; `Archive {name}? It won’t appear in new assignments.` Existing assignments remain visible. A blocked project archive names the unfinished-task count and changes nothing |

There is no hard-delete or purge control in Phase 1.

---

## Activity and Technical Detail

- Activity is a compact newest-first list, not a timeline illustration. Each item reads as `{Actor} {semantic action}` followed by exact outcome and accepted time.
- Render acceptance time in the account timezone as a visible exact value, for example `Aug 30, 2026, 3:18 PM EDT`, using a `<time datetime="…">`; relative text may supplement but never replace it.
- Long title/note changes are collapsed. A `Show change` disclosure reveals labeled old/new plain-text values.
- Revision and mutation identifiers appear only inside a `Technical details` disclosure or conflict/support view, with dedicated Copy buttons. Opaque undo handles never render.
- Archived projects/tags retain their names and an `Archived` text label in task/activity history.
- Activity failures are not inferred from absence. Authentication failures and diagnostic records never appear as task activity.

---

## Accessibility Contract

- Meet WCAG 2.2 AA for the supported task lifecycle, authentication, conflict, undo, organization, and session flows.
- Use native headings, landmarks, lists, forms, fieldsets, links, buttons, checkboxes, labels, and `<time>` elements. Do not use a custom ARIA grid for task lists.
- Every icon-only action has an action-and-object accessible name such as `Complete “Call dentist”`, `Open actions for “Call dentist”`, or `Restore “Call dentist”`.
- Completion state, Today reason, selected navigation, archived status, warning, conflict, and errors always have visible text or equivalent semantics in addition to color/icon/motion.
- Controls remain usable at 200% browser zoom and text-only zoom; reflow at 320px has no two-dimensional scrolling.
- Validation summaries link to fields; help and error IDs remain associated through retries.
- Dialog/drawer focus is trapped only while modal, Escape follows native cancellation expectations, and destructive defaults never receive initial focus.
- Test keyboard-only capture, edit, clarification, Today reorder, complete/reopen, trash/restore, undo, conflict resolution, reauthentication, pagination, and session revocation.

---

## UI Considerations

> Shape-rooted state coverage resolved using the compiled UI-consideration probe. Empty/error copy references the Copywriting Contract instead of duplicating it.

Probe input: 8 authored UI surfaces with explicit element-kind confirmation. Result: 48/48 applicable considerations resolved — 32 explicit, 16 backstop, 0 unresolved. The six content/state categories below are explicit truths; overflow and long-text remain evidence-bearing test backstops.

| Category | Element(s) | Status | Resolution / Reason |
|----------|------------|--------|---------------------|
| Empty | Quick capture, editor forms, task/activity lists | ✅ explicit | Blank forms retain labels/help and a disabled submit until valid; authoritative zero-result lists render the view-specific empty copy above; loading never masquerades as empty |
| Loading | Navigation, editor, lists, interactive controls | ✅ explicit | Initial route load uses structure-matched static skeletons and a named loading status; submit controls use action-specific progress text; background refresh preserves accepted content with `Updating…` |
| Error | Forms, lists, navigation, controls | ✅ explicit | Field errors remain adjacent and summarized; load/refresh/unknown/auth/conflict states use distinct persistent messages and exact recovery actions from the Copywriting Contract |
| Populated | Task and activity collections | ✅ explicit | Lists use semantic rows with separators, fixed view grouping, stable identities, explicit reason metadata, and Load more rather than card grids or infinite scroll |
| Partial | Forms and collections | ✅ explicit | Missing optional fields render as absent rather than placeholder facts; last accepted rows remain during partial refresh; nonconflicting draft fields survive validation, auth, and conflict resolution |
| Zero / one / many | Task and activity collections | ✅ explicit | Zero uses authoritative empty states; one keeps the same headings/row geometry; many paginates with explicit Load more and deterministic focus on the first appended item |
| Overflow | Lists, navigation, static status/activity content | 🧪 backstop | Visual tests at 320/768/1024/1440px cover two-line task-title clamp, one-line nav truncation with full accessible value, wrapped state copy, independent pane scrolling, and no horizontal page overflow |
| Long text | Capture/editor, task rows, nav, activity, controls | 🧪 backstop | Held-out accessibility/visual tests use 200-character titles, 10k-character notes, long project/tag/session labels, and long localized-style action text; full content remains editable/readable and action labels reflow without clipping |

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| Official `@shadcn` | `button` installed; additional approved primitives must be added individually as needed | Official registry only; initialized and verified 2026-08-30 |
| Third-party | None | Not applicable — `registries` is empty in `components.json` as of 2026-08-30 |

Do not use `add --all`. Any later third-party registry or block is outside this contract until `shadcn view`, dry-run/diff, dependency/license/provenance review, flagged-pattern scan, and explicit developer approval are recorded.

---

## Verification Evidence Required

- Representative Playwright coverage against real Phoenix/PostgreSQL for populated, authoritative empty, initial loading, background updating/failure, validation, stale cursor/order, conflict, expired authentication, unknown delivery, retry, and duplicate submission states.
- Keyboard and focus-restoration assertions for row removal, Load more, dirty navigation, conflict resolution, dialogs/drawers, and narrow-route Back behavior.
- Visual snapshots for both themes at 320, 768, 1024, and 1440px, plus Reduce Motion and forced-colors checks.
- Automated contrast checks on actual rendered semantic pairings, including muted text, disabled controls, destructive controls, focus rings, and dark mode.
- Copy assertions distinguish acknowledged, unknown, rejected, stale, conflict, and authentication-required results; no test may treat a missing response as failure.
- Untrusted-content fixtures prove titles, notes, project/tag names, and activity values render as text rather than executable markup.

---

## Checker Sign-Off

- [x] Dimension 1 Copywriting: PASS
- [x] Dimension 2 Visuals: PASS
- [x] Dimension 3 Color: PASS
- [x] Dimension 4 Typography: PASS
- [x] Dimension 5 Spacing: PASS
- [x] Dimension 6 Registry Safety: PASS

**Approval:** approved — 2026-08-30T20:21:09Z
