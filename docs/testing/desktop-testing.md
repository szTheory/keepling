# Desktop testing: which lane, and how little of it to run

Keepling's desktop proof is deliberately comprehensive. This document is about
the *other* question: when you have changed one file on your own Mac, what is
the smallest run that can actually observe that change?

The comprehensive suite is unchanged and stays the authority. Nothing here
reduces, skips, or makes conditional anything the phase gate
(`node tooling/verify-desktop-phase.mjs`) or CI (`.github/workflows/desktop.yml`)
runs.

## The lanes

| Command | Runner | Presents windows? | What it proves |
|---|---|---|---|
| `pnpm test:desktop` | vitest, 5 projects (`application`, `renderer`, `store`, `worker`, `performance`) | no | pure application/reducer logic, renderer components in jsdom, the real SQLite adapter, the worker protocol, performance measurement logic |
| `pnpm test:desktop:ipc` | vitest, `ipc` project | no | the hostile preload/main bridge contract |
| `pnpm test:desktop:e2e` | Playwright, `electron` project | **yes** (unless headless, below) | the real Electron app launched from the shipped entry point |
| `pnpm smoke:desktop:packaged` | Playwright, `packaged` project | **yes** | the packaged `.app` bytes |
| `node tooling/verify-macos-integration.mjs` | bespoke | **yes**, and posts real OS keystrokes | the real AX tree, real CGEvents, real system settings |
| `node tooling/verify-desktop-phase.mjs` | all of the above | yes | the gate — the authority, always comprehensive |

## Scoping a run to one file

Every lane takes a file-path substring filter, and **both** argument forms work:

```sh
pnpm test:desktop keyboardCommands       # 1 file, 19 tests
pnpm test:desktop -- keyboardCommands    # 1 file, 19 tests
pnpm test:desktop:ipc hostile-bridge
pnpm test:desktop:e2e keyboard-menus
```

### Why this needed fixing (03-17)

The `--` form used to silently run the *entire* suite — `pnpm test:desktop --
keyboardCommands` reported 18 files / 164 tests where the unprefixed form
reported 1 file / 19. The failure was silent, which is the real harm: a
scoped-looking command produced full-suite counts, and those counts were then
reported as though they were lane-scoped.

pnpm was not the culprit. pnpm appends script arguments verbatim, bare `--`
included. The runners lose them:

* **vitest** (cac) treats everything after a bare `--` as passthrough
  arguments, never as a test-name filter.
* **Playwright's `--project` is variadic**, so a bare positional after
  `--project electron` is parsed as a second *project* name
  (`Project(s) "keyboard-menus" not found`); after a bare `--`, the filter and
  even `--list` are ignored outright.

All three lanes now route through `tooling/run-tests.mjs`, which drops bare
`--` separators (announcing that it did) and always passes `--project=<name>`
so a trailing positional stays a positional. Flags that merely start with `--`
(`--list`, `--headed`, `--reporter=json`) are forwarded untouched.

Counts reported in summaries written **before** 03-17 against a `-- <name>`
command are full-suite counts, not lane-scoped ones. They are still valid
evidence; they are just not scoped.

## `pnpm test:changed` — run only what can observe your change

```sh
pnpm test:changed              # select from the working tree and run
pnpm test:changed --dry-run    # show the selection and its reasoning, run nothing
pnpm test:changed --include-manual                 # also run the screen-taking lanes
pnpm test:changed --dry-run --paths apps/desktop/main/windows/quick-entry-window.ts
```

It diffs staged + unstaged + untracked paths against `HEAD`, maps each path to
the lanes that can actually observe it, prints *why* each lane was chosen, and
runs exactly those.

Two rules govern the mapping, in this order:

1. **Never silently under-select.** All matching rules apply as a union, not
   first-match. A path matching *no* rule widens to **every** lane, and the
   reason is printed. A selector that quietly under-selects manufactures false
   confidence, which is worse than a slow run.
2. **Never silently seize the machine.** The macOS integration rows (real
   CGEvents, real system settings) and the Elixir server suite are *selected
   and printed* but **not executed** unless you pass `--include-manual`. They
   are reported as `NOT RUN`, with the exact command — an unrun lane is never
   counted as a pass.

`pnpm test:changed` is **not** the gate and is deliberately not wired into
`tooling/verify-desktop-phase.mjs` or any CI job. Every run prints the
authority:

```
node tooling/verify-desktop-phase.mjs
```

### Adding a rule

Edit `RULES` in `tooling/select-tests.mjs`. If you see an `UNMATCHED path`
line, that is the tool telling you a rule is missing — it has already widened
to everything for safety, so nothing was lost, but the next person deserves
the narrower answer.

## Headless E2E (`KEEPLING_TEST_HEADLESS=1`) — opt in, local only

```sh
KEEPLING_TEST_HEADLESS=1 pnpm test:desktop:e2e     # 52 tests, 41.6s, no windows
pnpm test:desktop:e2e                              # 57 tests, 1.1m, real windows (default)
pnpm test:desktop:e2e --grep @windowed             # only the specs that need a real window
```

Every window in this app is already constructed `show: false` and presented
later by an explicit `.show()`. Under the flag,
`apps/desktop/main/windows/headless-presentation.ts` neutralises exactly those
presentation methods (`show`, `showInactive`, `moveTop`) on
`BrowserWindow.prototype` and hides the Dock icon. Nothing else changes: the
whole main process, the real preload bridge, the real renderer, and the real
store run unchanged, and Playwright keeps driving the renderer over CDP.

The seam is installed in **both** entry points — the shipped
`apps/desktop/main/index.ts` *and* `apps/desktop/test/fixtures/wired-app-harness.ts`.
Without the second one, the two harness-launched specs would still have
thrown windows on the screen while the run claimed to be headless.

Measured, with the flag set (`BrowserWindow.getAllWindows()` inspected after
the renderer settles):

| `KEEPLING_TEST_HEADLESS` | main window `isVisible()` | Dock icon |
|---|---|---|
| `1` | `false` | hidden |
| unset | `true` | shown |

### Per-spec headless capability

| Spec | Launches | Headless? | Evidence |
|---|---|---|---|
| `accessibility.spec.ts` | `dist/main/index.cjs` | ✅ 11 passed | DOM/AX-role assertions and `setContentSize`, none of which need presentation |
| `daily-loop.spec.ts` | `dist/main/index.cjs` | ✅ 2 passed | user-visible roles only; `toBeFocused()` is DOM focus, which a hidden window still maintains |
| `gap-closure.spec.ts` | `dist/main/index.cjs` | ✅ 6 passed | real-wiring introspection, no presentation predicate |
| `keyboard-menus.spec.ts` | `dist-harness/harness.cjs` | ✅ 5 passed | inspects and clicks the real `Menu` via `application.evaluate`, which works unpresented |
| `keyboard-quick-entry.spec.ts` | `dist-harness/harness.cjs` | ❌ **`@windowed`** | its central predicate `isQuickEntryOpen()` → `QuickEntryWindowController.isOpen()` → `BrowserWindow.isVisible()` is precisely what headless suppresses. Measured: `:169` (`Command-Return commits…`) **fails outright** (asserts `isOpen() === true`), and the `isOpen() === false` assertions at `:122`/`:148` would pass **vacuously** — unable to tell "hidden after commit" from "never presented". Tagged, excluded headless, unchanged windowed. |
| `lifecycle.spec.ts` | `dist/main/index.cjs` | ✅ 12 passed | window count, `close`, `setBounds`/`getBounds` and Dock-activation events are all real on an unpresented window |
| `real-stack-sync.spec.ts` | — | ✅ 7 passed | never launches Electron |
| `sync-recovery.spec.ts` | — | ✅ 9 passed | never launches Electron |

A spec that cannot be trusted headless runs **windowed or not at all** — never
headless-and-weakened. The tag is per-test, so a new test added to a
`@windowed` file must opt in deliberately rather than inheriting a silent
exclusion.

### Not the default, and not in CI

`grepInvert` is `undefined` unless you opt in, so the phase gate and every CI
job run the full 57-test windowed suite exactly as before. CI has no screen to
take over and benefits from the windowed path being exercised.
