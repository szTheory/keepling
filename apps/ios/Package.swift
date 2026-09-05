// swift-tools-version: 6.3
// Keepling for iPhone -- KeeplingCore package.
//
// Dependency pins resolved 2026-09-04 via `git ls-remote --tags` against
// each upstream repository at Task 2 execute time (04-01-PLAN.md), NOT
// copied from 04-RESEARCH.md's `[ASSUMED]` guesses (7.11.1 / 1.10.2 were
// correct-by-luck for GRDB but stale for the generator trio):
//
//   git ls-remote --tags https://github.com/groue/GRDB.swift.git
//     -> highest stable tag: 7.11.1
//   git ls-remote --tags https://github.com/apple/swift-openapi-generator.git
//     -> highest stable tag: 1.13.1 (RESEARCH.md's 1.10.2 guess is four
//        minors behind)
//   git ls-remote --tags https://github.com/apple/swift-openapi-runtime.git
//     -> highest stable tag: 1.12.1
//   git ls-remote --tags https://github.com/apple/swift-openapi-urlsession.git
//     -> highest stable tag: 1.3.1
//
// swift-openapi-generator 1.13.1's own Package.swift declares
// `.package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.11.0")`
// and swift-openapi-urlsession 1.3.1 declares the same floor -- 1.12.1 and
// 1.3.1 both satisfy that constraint.
import PackageDescription

let package = Package(
    name: "KeeplingCore",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(name: "KeeplingCore", targets: ["KeeplingCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", exact: "1.12.1"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession.git", exact: "1.3.1"),
    ],
    targets: [
        // KeeplingCore is deliberately pure Swift: no UIKit, no SwiftUI.
        // This is the headless, simulator-free unit-test surface
        // (04-RESEARCH.md "Recommended Project Structure").
        .target(
            name: "KeeplingCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ],
            path: "Sources/KeeplingCore"
        ),
        .testTarget(
            name: "KeeplingCoreTests",
            dependencies: ["KeeplingCore"],
            path: "Tests/KeeplingCoreTests"
        ),
        .testTarget(
            name: "StorageTests",
            dependencies: ["KeeplingCore"],
            path: "Tests/StorageTests"
        ),
    ]
)
