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

## Lane discovery (`tooling/ios-lanes/*.mjs`)

`tooling/verify-ios-phase.mjs` globs `tooling/ios-lanes/*.mjs` and loads one
lane definition per file -- lanes are never declared inline in the runner, so
a later plan adds its lane by adding a file, never by editing the runner (this
keeps parallel plans in the same wave from colliding on one file). A lane
file that fails to load is a runner failure, never a skipped lane.
