
## From Plan 04-16 (2026-09-06)

> **RESOLVED 2026-09-07.** The ledger counts were repaired (see the commit
> `fix(planning): reconcile the windows ledger with its own JSON entries`)
> and two of the three items below were appended to `.planning/WINDOWS.md`.
> The third -- "device lane BLOCKED, the iPhone is locked" -- was NOT
> appended, because it is no longer true: the device lane subsequently ran
> green on a physical iPhone (22 tests, 0 failures, `** TEST SUCCEEDED **`,
> build digest 801e7602c4dfd3a150c35fb234e8bdc0). Recording it as an open
> window would have been a false entry.
>
> The diagnosis below is also corrected: the frontmatter did not disagree
> with the rendered table -- both said 56/1-open and agreed with each other.
> It was the JSON block, which is the ledger's authoritative source, that
> carried five further entries (57-61) neither had been re-rendered from.


- **`.planning/WINDOWS.md` frontmatter counts disagree with its entries.**
  `gsd-tools windows append` refuses with: frontmatter open/waived/fixed/total=1/49/6/56 but
  entries yield 6/49/6/61. The file was last committed by `e501e19` (Plan 03-22), well before this
  plan, so this is pre-existing and out of Plan 04-16's scope. Consequence: this plan's three
  BLOCKED items could not be appended to the ledger and are recorded only in
  `04-16-SUMMARY.md` and `docs/testing/ios-dogfood.md`. Repair the counts, then append:
  - `unrun-verify` — device lane BLOCKED, the iPhone is locked (tooling/ios-lanes/device.mjs)
  - `unmet-truth` — the server-driven half of D-22 Criterion 2 is blocked by the app's transport
    guard (tooling/verify-real-stack-ios.mjs)
  - `skipped-test` — G7's locked-device write has no programmatic lock control
    (apps/ios/Tests/StorageTests/DataProtectionTests.swift)
