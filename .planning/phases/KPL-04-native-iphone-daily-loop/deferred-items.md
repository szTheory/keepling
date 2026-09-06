
## From Plan 04-16 (2026-09-06)

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
