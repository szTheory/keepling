# Keepling for iPhone

**Phase:** 4 (Native iPhone Daily Loop)
**Technology:** native SwiftUI, GRDB.swift local persistence, a committed
`swift-openapi-generator`-produced Swift wire client.

The iPhone client independently implements durable local projection/outbox
behavior against the same wire contract as the desktop and web clients. It
shares semantic tokens and wire contracts -- not React components, Ecto
schemas, or desktop persistence models.

## Project generation (XcodeGen, never hand-edit the `.xcodeproj`)

`Keepling.xcodeproj` is generated from the checked-in `project.yml` and is
git-ignored. Regenerate it after any `project.yml` change:

```sh
xcodegen generate --spec apps/ios/project.yml --project apps/ios
```

## Build and test

```sh
xcodebuild -project apps/ios/Keepling.xcodeproj -scheme Keepling \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' build

node tooling/verify-ios-phase.mjs           # all lanes
node tooling/verify-ios-phase.mjs --lane core-unit
```

## Deliberate divergence from the `apps/desktop` convention: no pnpm

`apps/ios` is **outside the pnpm workspace graph on purpose** (native-tools-
first rule). There is no `apps/ios/package.json`, and no root script here
delegates through `pnpm --dir apps/ios` or `pnpm --filter`. Every iOS
command is a direct `xcodebuild`/`xcodegen`/`devicectl` spawn inside a
`tooling/*.mjs` wrapper (`tooling/verify-ios-phase.mjs`,
`tooling/generate-ios-client.mjs`), mirroring `tooling/verify-desktop-phase.mjs`'s
structure but never its pnpm delegation. Do not "fix" this by adding an
`apps/ios/package.json` -- that would put a native Xcode project inside a
JS workspace it was deliberately kept out of.

## Resolved dependency pins (04-01-PLAN.md Task 2)

Resolved via `git ls-remote --tags` against each upstream repository at
execute time, not copied from 04-RESEARCH.md's `[ASSUMED]` guesses:

| Package | Resolved tag | Note |
|---|---|---|
| [groue/GRDB.swift](https://github.com/groue/GRDB.swift) | `7.11.1` | D-01's committed local-store adapter |
| [apple/swift-openapi-generator](https://github.com/apple/swift-openapi-generator) | `1.13.1` | RESEARCH.md guessed `1.10.2` -- four minors stale |
| [apple/swift-openapi-runtime](https://github.com/apple/swift-openapi-runtime) | `1.12.1` | satisfies the generator's own `from: 1.11.0` floor |
| [apple/swift-openapi-urlsession](https://github.com/apple/swift-openapi-urlsession) | `1.3.1` | satisfies the same floor |

## Generated Swift wire client (D-12, committed, never a build-tool plugin)

`Sources/KeeplingCore/Transport/Generated/` is produced by the pinned
`swift-openapi-generator` CLI from `packages/contracts/openapi/keepling.yaml`
and **committed** -- the same precedent as `packages/contracts/generated/keepling.ts`.
A build-tool plugin was explicitly rejected (D-12): its output is not
diff-reviewable and is not deterministic offline.

Regenerate after any contract change:

```sh
node tooling/generate-ios-client.mjs          # writes the committed output
node tooling/generate-ios-client.mjs --check  # verifies it is current (CI-safe, no writes)
```

The generator CLI itself is built from source once (not vendored into the
app target) and is expected at `.build-tools/swift-openapi-generator`
(git-ignored) or at the path named by `KEEPLING_SWIFT_OPENAPI_GENERATOR_BIN`:

```sh
git clone --branch 1.13.1 https://github.com/apple/swift-openapi-generator.git /tmp/sog
cd /tmp/sog && swift build -c release --product swift-openapi-generator
mkdir -p <repo-root>/.build-tools
cp .build/release/swift-openapi-generator <repo-root>/.build-tools/swift-openapi-generator
```

### Nullable-`$ref` schema pattern

`packages/contracts/openapi/keepling.yaml` normalizes every OpenAPI-3.0-style
`anyOf: [X, {type: 'null'}]` nullable site to an OpenAPI 3.1 `type: [X, 'null']`
union. For a plain type this is direct. For a nullable **reference**
(`$ref`), wrapping the reference in `oneOf`/`anyOf` alongside `{type: 'null'}`
was tried and empirically verified (against this exact pinned generator) to
silently drop the referencing property from the generated Swift struct
entirely -- not merely decode it non-optionally. Per
swift-openapi-generator's own `Handling-nullable-schemas.md`, nullability of
a `$ref` propagates from the **target schema's own type**, so every nullable
reference site instead points at a small parallel `Nullable<Base>` schema
(`NullableRevision`, `NullableCivilDate`, `NullableSyncCursor`,
`NullableOrganizationIdentity`, `NullableActivityIdentity`,
`NullableActivityCursor`, `NullableTaskViewCursor`,
`NullableTaskOrganizationReference`) that restates the base schema's shape
under a direct `type: [X, 'null']` union. Do not "simplify" a nullable
reference site back to a `oneOf`/`anyOf`-null wrapper -- it will compile and
regenerate the TypeScript client fine, but will silently vanish the property
from the Swift client.

## KeeplingCore: pure Swift, no UIKit/SwiftUI import

`Sources/KeeplingCore` is a plain Swift Package library target with no
`import UIKit`/`import SwiftUI` anywhere -- the headless, simulator-free unit
test surface (`KeeplingCoreTests`). `Sources/Keepling` is the SwiftUI app
target that depends on it.

## Generated Swift design tokens (committed, never a build-tool plugin)

`Sources/Keepling/DesignTokens/GeneratedTokens.swift` is produced from
`packages/design-tokens/tokens.json` by `tooling/emit-swift-tokens.mjs` and
**committed**, following the same precedent as the wire client above --
diff-reviewable, deterministic offline output, not a build-time plugin.
`Sources/Keepling/DesignTokens/TokenSemantics.swift` is the hand-written
semantic layer built on top of it.

Regenerate after any `packages/design-tokens/tokens.json` change:

```sh
node tooling/emit-swift-tokens.mjs          # writes the committed output
node tooling/emit-swift-tokens.mjs --check  # verifies it is current (CI-safe, no writes)
```

The `design-tokens` lane (`node tooling/verify-ios-phase.mjs --lane design-tokens`)
runs this same `--check` on every gate invocation, so a stale committed
token file fails the phase gate rather than silently drifting from
`tokens.json`.

## Project layout

```
apps/ios/
  project.yml                    -- XcodeGen spec (source of truth; .xcodeproj is git-ignored)
  Package.swift                  -- KeeplingCore Swift Package (pure Swift, no UIKit/SwiftUI)
  Sources/
    KeeplingCore/                -- reducer, transport port, GRDB local store, App Intents support
      Transport/Generated/       -- committed swift-openapi-generator output
    Keepling/                    -- the SwiftUI app target
      DesignTokens/              -- committed generated tokens + hand-written semantics
      App/                       -- KeeplingApp.swift (entry point, #if DEBUG state-injection seam)
      Capture/ Inbox/ Today/ Detail/ SyncRecovery/ Undo/ Workspace/ -- feature modules
  Tests/
    KeeplingCoreTests/           -- headless unit tests, no simulator dependency
    StorageTests/                -- GRDB durability/migration/data-protection tests
    AppIntentsTests/             -- App Intents perform()-level tests
    KeeplingUITests/             -- XCUITest suites (daily loop, accessibility, state matrix, overflow)
```

## Generate-then-build workflow

1. Edit `project.yml`, `packages/contracts/openapi/keepling.yaml`, or
   `packages/design-tokens/tokens.json` as needed.
2. Regenerate whichever committed output changed (`xcodegen generate`,
   `node tooling/generate-ios-client.mjs`, and/or
   `node tooling/emit-swift-tokens.mjs`).
3. Build/test with `xcodebuild` or the phase gate below. Never hand-edit
   `Keepling.xcodeproj` or any file under `Sources/**/Generated/`.

## Lane inventory (`tooling/verify-ios-phase.mjs`)

The phase gate discovers one lane per file under `tooling/ios-lanes/`.
`docs/testing/ios-testing.md` documents what each lane proves; the current
inventory (`node tooling/verify-ios-phase.mjs --requirements` maps each
phase requirement to its lanes):

`accessibility`, `accessory-probe`, `app-intents`, `auth`, `core-loop`,
`core-unit`, `decode-roundtrip`, `design-tokens`, `device`,
`durability-posture`, `lifecycle`, `overflow-longtext`, `privacy`,
`state-matrix`, `storage`, `storage-gates`, `sync-pass`,
`sync-presentation`, `tracer-e2e`, `transport`, `undo`,
`vector-conformance`.

`device` is the one lane bound to physical hardware rather than the
Simulator. It reports `BLOCKED` (never a silent skip, never a pass) until
Plan 04-16 completes the device-install checkpoint it currently halts at
-- see `tooling/ios-lanes/device.mjs` and `tooling/ios-lanes/README.md`.

## Disclosures

Every gap this phase has disclosed -- what a lane proves and what it
explicitly does not -- is consolidated in one place:
`docs/testing/ios-testing.md`'s "Consolidated disclosures" section. Read
it before citing any green checkmark from this app as more coverage than
it provides.

## Lane discovery (`tooling/ios-lanes/*.mjs`)

`tooling/verify-ios-phase.mjs` globs `tooling/ios-lanes/*.mjs` and loads one
lane definition per file -- lanes are never declared inline in the runner, so
a later plan adds its lane by adding a file, never by editing the runner (this
keeps parallel plans in the same wave from colliding on one file). A lane
file that fails to load is a runner failure, never a skipped lane.
