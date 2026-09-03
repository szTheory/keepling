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
