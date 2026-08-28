# Keepling Brand Seed

**Status:** provisional identity foundation; the name is selected, while legal clearance, logo, icon, and final system design remain future work.

## Brand essence

Keepling is a small, dependable familiar that quietly keeps commitments safe.

It should feel like a trusted personal object: warm enough to care about, precise enough to trust, and calm enough to disappear into a daily workflow. It is never a nagging productivity coach, corporate project system, magical AI oracle, or childish mascot.

## Positioning

For individuals who value Things-quality calm but need trustworthy automation and data ownership, Keepling is an open-source personal GTD system with durable native clients and safe, reversible programmatic access.

## Working message hierarchy

1. **Primary promise:** Keep what matters. Stay in control.
2. **Trust proof:** Your commitments remain available, portable, inspectable, and recoverable.
3. **Agent proof:** AI tools act through the same rules as you—bounded, visible, and undoable.
4. **Open-source proof:** Run it yourself; your task history is not held hostage.

Candidate supporting lines:

- A calm home for everything you mean to do.
- Keep every promise within reach.
- Quietly keeping what matters next.
- Your commitments, kept.

These are exploratory copy, not registered taglines.

## Values

- **Calm agency:** Help the user decide and act; do not optimize, shame, or seize control.
- **Earned trust:** Make state, consequences, conflicts, and recovery understandable.
- **Craft:** Small details, timing, spacing, copy, and error handling should feel intentional.
- **Stewardship:** Protect the user's commitments, history, privacy, and ability to leave.
- **Restraint:** Prefer a coherent core and quiet defaults over breadth and configuration theater.
- **Honesty:** Say what is local, synced, pending, inferred, conflicted, or unverified.

## Personality sliders

| Dimension | Keepling position |
|-----------|-------------------|
| Warm ↔ clinical | Warm, never sentimental |
| Playful ↔ severe | Gently playful, operationally serious |
| Quiet ↔ expressive | Quiet in product; more expressive in illustration/marketing |
| Familiar ↔ futuristic | Familiar and tactile |
| Human ↔ technical | Human-facing with technical rigor underneath |
| Guiding ↔ commanding | Guiding; user remains sovereign |

## Voice

Use plain, compact, specific language. Prefer verbs and concrete state. Sound like a capable companion who respects attention.

**Do:**

- “Saved on this Mac. Sync when you’re back online.”
- “Two tasks match ‘milk.’ Choose one to complete.”
- “This preview is stale. Nothing was changed.”
- “Backup restored and verified 14 minutes ago.”
- “Undo completion.”

**Do not:**

- “Oops! Something went wrong.”
- “Crush your goals.”
- “Let AI supercharge your productivity.”
- “Keepling thinks you should…”
- “Your task was probably synced.”

Tone adapts without changing character:

- **Routine:** quiet and almost invisible.
- **Success:** brief confirmation, no celebration tax.
- **Error/recovery:** direct, non-blaming, specific next action.
- **Agent action:** explicit actor, action, affected objects, and undo/confirmation state.
- **Operator tools:** terse, structured, copyable, and safe to share.

## Provisional color territory

The palette deliberately avoids Things blue, Todoist red, Linear-like monochrome developer styling, and violet/blue AI glow.

| Token role | Working name | Hex | Intended use |
|------------|--------------|-----|--------------|
| `brand.primary` | Marigold | `#F2B544` | App icon field, selected accents, warm moments |
| `brand.anchor` | Aubergine | `#3A243F` | Wordmark/icon mark, deep branded surfaces |
| `brand.canvas` | Parchment | `#FFF8E9` | Marketing and warm empty-state ground |
| `brand.secondary` | Lichen | `#78906B` | Restrained secondary accent; not a generic success color by default |
| `brand.ink` | Warm Ink | `#201B22` | Brand text and monochrome identity |

These are brand-source colors, not yet an accessible product token system. UI colors require semantic roles, dark-mode derivation, color-vision testing, contrast validation, high-contrast behavior, and non-color state cues before implementation. Native surfaces should remain largely system-neutral; brand color is concentrated in the app icon, selected states, illustration, empty states, and a few meaningful moments.

### Product UI seed

For early prototypes, use a quieter semantic surface system while reserving marigold for identity moments:

| Role | Light | Dark |
|------|-------|------|
| Canvas | `#F7F2E8` | `#1C1917` |
| Surface | `#FFFCF7` | `#24201D` |
| Primary text | `#211E1A` | `#F5EFE5` |
| Muted text | `#696158` | `#C7BBAE` |
| Interactive accent | `#6F4A63` | `#D29ABF` |
| Strong boundary | `#877B6D` | `#786F69` |

These values are creative seeds, not approved tokens. Validate WCAG 2.2 AA contrast in actual component pairings; never use color as the only status, selection, focus, or error cue.

## Typography

- Use platform system typography in the product: SF Pro/SF Mono on Apple platforms and the appropriate system stack in browser/Electron.
- Do not force one custom face across native controls at the cost of legibility or platform feel.
- A future wordmark may use a custom-drawn or licensed rounded grotesk with subtle human irregularity, but the product must not depend on it.
- Use tabular numerals and monospace only where data or operator output benefits.

## Symbol and icon principles

Working territory: a compact folded loop that suggests a lowercase `k`, a protective pocket, or an object gently held. It must work as a strong monochrome silhouette at 16 px before color or animation helps it.

Avoid:

- literal checkmarks, calendar grids, inbox trays, robots, brains, sparkles, wands, or chat bubbles;
- a Things-like blue rounded square or Todoist-like red completion mark;
- a literal cute animal that makes reliability feel unserious;
- fine-line detail that disappears in a menu bar, favicon, or notification.

The logo/icon phase should run a tournament with at least three genuinely different territories, blind small-size tests, monochrome tests, native-context mockups, and an explicit collision review before selection.

## Motion character

Motion communicates state and physical cause:

- Capture gently tucks or settles into place.
- Completion closes/releases with precise restraint; no confetti.
- Undo visibly restores continuity.
- Sync indicates direction and pending state without perpetual spinning.
- Conflicts pause and separate rather than shake or alarm.

Start with roughly 140–180 ms for small direct responses and tune by feel. Every animation needs a meaningful Reduce Motion substitute, and no correctness cue may depend on motion alone.

## Product-family usage

Preferred constructions:

- Keepling for iPhone
- Keepling for Mac
- Keepling Web
- Keepling MCP
- Keepling Server
- Keepling Cloud (only if hosted operations exist)

Avoid inventing sub-brand names for ordinary features.

## Competitive separation

- Do not describe Keepling primarily as a “todo app” or “AI assistant.”
- Lead with calm personal commitments, trust, offline availability, and safe programmability.
- Keep marketing warmer than developer infrastructure but more concrete than lifestyle/wellness language.
- Open source and self-hosting are trust proofs, not permission to make the product look like an admin dashboard.

## Unresolved before public reveal

- Comprehensive exact/phonetic trademark search, including proximity to Kipling and related software/services.
- GitHub organization/repository, App Store, domain, npm scope, Hex, and social namespace acquisition.
- Heard-once spelling/pronunciation and multilingual screens.
- Logo/icon tournament and accessible light/dark semantic color system.
- Professional legal review of the final mark and open-source trademark policy.

See the retained naming brief and evidence ledger at `.planning/knowledge/snapshots/2026-08-28-brand-and-naming-brief.md`.
