import XCTest
@testable import KeeplingCore

/// Drives `SyncReducer` -- not `GRDBLocalStore` -- through every golden
/// vector case bound to `sync-state-machine.schema.json`, proving Swift's
/// third independent reducer implementation agrees with the Elixir
/// reference model (`apps/server/lib/keepling/application/sync/reference_model.ex`)
/// and the TypeScript desktop consumer (`apps/desktop/test/application/sync-vectors.test.ts`).
///
/// DISCLOSED DEVIATION from 04-03-PLAN.md Task 3's literal action text
/// (recorded again in 04-03-SUMMARY.md): the plan's `<action>` names
/// `GRDBLocalStore` as the driven store, mirroring the desktop harness's
/// choice to drive its real SQLite-backed store rather than a separate pure
/// reducer. But `LocalMutation` (the store's tracer-era mutation shape,
/// `LocalStorePort.swift`) has no `dependencies` field, and `GRDBLocalStore`
/// does not implement `applyPull`, a fence-state reader, or
/// dependency-satisfied/lane-blocked `readyMutations` ordering -- extending
/// the durability-focused store built in Plans 04-01/04-02 to the reference
/// model's full semantics is materially larger, unauthorized-scope work.
/// `SyncReducer`/`SyncReducerState` (Task 2) is a field-for-field
/// reimplementation of the reference model's OWN state shape -- driving IT
/// is the comparison D-10 actually asks for (three implementations of the
/// SAME state machine), and is what this file does.
///
/// Only `packages/contracts/vectors/sync.json` binds
/// `sync-state-machine.schema.json` among the repository's 13 vector files
/// (verified by inspecting every file's `$schema` field) -- see
/// `packages/contracts/vectors/manifest.json` for the full per-file
/// consumer disposition and 04-03-SUMMARY.md for the supporting evidence.
/// This is therefore the one file this harness drives.
final class VectorConformanceTests: XCTestCase {
    private static let syncStateMachineSchemaRef = "../schemas/sync-state-machine.schema.json"

    /// Files this Swift harness is responsible for driving through
    /// `SyncReducer` -- the sync-state-machine-schema-bound subset of the
    /// vector files, not all of them (see the type doc comment and the
    /// manifest for why). The subset is selected by `$schema` below, not
    /// by this list; this list is the expected RESULT of that selection.
    private static let drivenFileNames: Set<String> = ["sync.json"]

    func testAllSyncStateMachineVectorFilesAreDrivenWithStructuralCaseCoverage() throws {
        let vectorsDirectory = try RepositoryRoot.vectorsDirectory()
        let fileManager = FileManager.default
        let allJSONFiles = try fileManager.contentsOfDirectory(atPath: vectorsDirectory.path)
            .filter { $0.hasSuffix(".json") && $0 != "manifest.json" }
            .sorted()

        // Bumped 13 -> 16 when CI run 34897943904 first executed this lane and
        // found the vectors 05-11 (mcp-injection, mcp-tools) and 06-08
        // (export-golden) had added. The hardcoded count is the POINT: a new
        // vector file must force someone to decide whether it is a
        // sync-state-machine vector this harness has to drive, and silently
        // accepting any count would remove the only thing that asks.
        XCTAssertEqual(allJSONFiles.count, 16, "expected 16 vector files, found \(allJSONFiles.count): \(allJSONFiles)")

        var executedFiles: [String] = []
        var totalExecutedCases = 0

        for fileName in allJSONFiles {
            let fileURL = vectorsDirectory.appendingPathComponent(fileName)
            let data = try Data(contentsOf: fileURL)
            let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let schemaRef = raw["$schema"] as? String

            guard schemaRef == Self.syncStateMachineSchemaRef else {
                // Not a sync-state-machine vector file (e.g. task lifecycle,
                // conflicts, organizations, undo, ...) -- those bind their
                // OWN schemas/reducers, owned by Elixir (and, for the one
                // TypeScript already drives, the desktop store). This Swift
                // target implements only SyncReducer, so it is not this
                // harness's file to execute. Recorded, never silently
                // skipped: every file in the directory is inspected above.
                continue
            }

            XCTAssertTrue(
                Self.drivenFileNames.contains(fileName),
                "\(fileName) binds sync-state-machine.schema.json but is not in VectorConformanceTests.drivenFileNames -- update the constant"
            )

            let executedCaseCount = try driveSyncStateMachineFile(raw: raw, fileName: fileName)
            totalExecutedCases += executedCaseCount
            executedFiles.append(fileName)
        }

        XCTAssertEqual(executedFiles, Array(Self.drivenFileNames).sorted())
        XCTAssertGreaterThan(totalExecutedCases, 0, "zero synchronization cases executed")

        try emitExecutedFileReport(executedFiles: executedFiles)
    }

    // MARK: - Driving one sync-state-machine file

    private func driveSyncStateMachineFile(raw: [String: Any], fileName: String) throws -> Int {
        guard let cases = raw["cases"] as? [[String: Any]] else {
            XCTFail("\(fileName) has no cases array")
            return 0
        }

        let declaredCaseNames = Set(cases.compactMap { $0["name"] as? String })
        var executedCaseNames = Set<String>()

        for caseObject in cases {
            guard let name = caseObject["name"] as? String else {
                XCTFail("\(fileName) has a case with no name")
                continue
            }
            try runCase(caseObject, fileName: fileName)
            executedCaseNames.insert(name)
        }

        // D-15: coverage is STRUCTURAL. The executed case-name set must
        // equal the declared case-name set, so a case the harness silently
        // fails to run (rather than fails LOUDLY while running) still
        // fails this assertion.
        XCTAssertEqual(
            executedCaseNames, declaredCaseNames,
            "\(fileName): executed case set does not equal declared case set; missing \(declaredCaseNames.subtracting(executedCaseNames))"
        )

        return cases.count
    }

    private func runCase(_ caseObject: [String: Any], fileName: String) throws {
        guard let name = caseObject["name"] as? String,
              let actions = caseObject["actions"] as? [[String: Any]],
              let expect = caseObject["expect"] as? [String: Any]
        else {
            XCTFail("\(fileName) case is malformed: \(caseObject)")
            return
        }

        var state = SyncReducerState()
        var observedReadyPushes: [String] = []

        for action in actions {
            guard let type = action["type"] as? String else {
                XCTFail("[\(fileName)/\(name)] action has no type")
                continue
            }

            switch type {
            case "local_accept":
                guard let mutationObject = action["mutation"] as? [String: Any] else {
                    return XCTFail("[\(fileName)/\(name)] local_accept has no mutation")
                }
                let mutation = try decodeMutation(mutationObject)
                switch SyncReducer.localAccept(state, mutation: mutation) {
                case .success(let result): state = result.state
                case .failure(let error): XCTFail("[\(fileName)/\(name)] local_accept failed: \(error)")
                }

            case "pull":
                guard let pageObject = action["page"] as? [String: Any] else {
                    return XCTFail("[\(fileName)/\(name)] pull has no page")
                }
                let page = try decodePullPage(pageObject)
                switch SyncReducer.pull(state, page: page) {
                case .success(let next): state = next
                case .failure(let error): XCTFail("[\(fileName)/\(name)] pull failed: \(error)")
                }

            case "ready_pushes":
                switch SyncReducer.readyPushes(state) {
                case .success(let ready): observedReadyPushes.append(contentsOf: ready.map(\.mutationId))
                case .failure(let error): XCTFail("[\(fileName)/\(name)] ready_pushes failed: \(error)")
                }

            case "acknowledge":
                guard let acknowledgementObject = action["acknowledgement"] as? [String: Any] else {
                    return XCTFail("[\(fileName)/\(name)] acknowledge has no acknowledgement")
                }
                let acknowledgement = try decodeAcknowledgement(acknowledgementObject)
                switch SyncReducer.acknowledge(state, acknowledgement: acknowledgement) {
                case .success(let next): state = next
                case .failure(let error): XCTFail("[\(fileName)/\(name)] acknowledge failed: \(error)")
                }

            case "fence":
                let reason = action["reason"] as? String
                state = SyncReducer.fence(state, reason: reason)

            case "relaunch":
                // `SyncReducer` is a pure in-memory reducer with nothing to
                // reopen -- a relaunch of a pure state value is a
                // structural no-op (state carries over unchanged), which is
                // exactly what every vector case exercising `relaunch`
                // expects to observe (retained pending intent). Real
                // cross-process durability of this same state is proven
                // separately by 04-02-SUMMARY.md's `CrashRecoveryTests`
                // against the real GRDB-backed store.
                break

            default:
                XCTFail("[\(fileName)/\(name)] unrecognized action type: \(type)")
            }
        }

        let expectedCursor = expect["cursor"] as? String
        let expectedOutbox = (expect["outbox"] as? [String]) ?? []
        let expectedReadyPushes = (expect["ready_pushes"] as? [String]) ?? []

        XCTAssertEqual(state.cursor, expectedCursor, "[\(fileName)/\(name)] cursor mismatch")
        XCTAssertEqual(state.outbox.map(\.mutationId), expectedOutbox, "[\(fileName)/\(name)] outbox mismatch")
        XCTAssertEqual(observedReadyPushes, expectedReadyPushes, "[\(fileName)/\(name)] ready_pushes mismatch")
    }

    // MARK: - Decoding vector JSON into SyncReducer inputs

    private func decodeSnapshot(_ object: [String: Any]) throws -> SyncSnapshot {
        guard let id = object["id"] as? String, let revisionNumber = object["revision"] as? NSNumber else {
            throw DecodingFailure(context: "snapshot", object: object)
        }
        var extra: [String: SyncJSON] = [:]
        for (key, value) in object where key != "id" && key != "revision" {
            extra[key] = SyncJSON.from(value)
        }
        return SyncSnapshot(id: id, revision: revisionNumber.intValue, extra: extra)
    }

    private func decodeMutation(_ object: [String: Any]) throws -> SyncMutation {
        guard let mutationId = object["mutation_id"] as? String,
              let fingerprint = object["fingerprint"] as? String,
              let commandBytes = object["command_bytes"] as? String,
              let resourceKeys = object["resource_keys"] as? [String],
              let dependencies = object["dependencies"] as? [String],
              let acceptedAt = object["accepted_at"] as? String,
              let effect = object["effect"] as? [String: Any],
              let entityId = effect["entity_id"] as? String,
              let snapshotObject = effect["snapshot"] as? [String: Any]
        else {
            throw DecodingFailure(context: "mutation", object: object)
        }
        return SyncMutation(
            mutationId: mutationId, fingerprint: fingerprint, commandBytes: commandBytes,
            resourceKeys: resourceKeys, dependencies: dependencies, acceptedAt: acceptedAt,
            effectEntityId: entityId, effectSnapshot: try decodeSnapshot(snapshotObject)
        )
    }

    private func decodePullPage(_ object: [String: Any]) throws -> SyncPullPage {
        guard let cursor = object["cursor"] as? String, let changes = object["changes"] as? [[String: Any]] else {
            throw DecodingFailure(context: "pull page", object: object)
        }
        let decodedChanges = try changes.map { change -> SyncPullChange in
            guard let entityId = change["entity_id"] as? String, let snapshotObject = change["snapshot"] as? [String: Any] else {
                throw DecodingFailure(context: "pull change", object: change)
            }
            return SyncPullChange(entityId: entityId, snapshot: try decodeSnapshot(snapshotObject))
        }
        return SyncPullPage(cursor: cursor, changes: decodedChanges)
    }

    private func decodeAcknowledgement(_ object: [String: Any]) throws -> SyncAcknowledgementInput {
        guard let mutationId = object["mutation_id"] as? String,
              let fingerprint = object["fingerprint"] as? String,
              let outcomeRaw = object["outcome"] as? String,
              let outcome = SyncTerminalOutcome(rawValue: outcomeRaw),
              let snapshotObject = object["snapshot"] as? [String: Any]
        else {
            throw DecodingFailure(context: "acknowledgement", object: object)
        }
        return SyncAcknowledgementInput(
            mutationId: mutationId, fingerprint: fingerprint, outcome: outcome,
            snapshot: try decodeSnapshot(snapshotObject)
        )
    }

    private struct DecodingFailure: Error, CustomStringConvertible {
        let context: String
        let object: [String: Any]
        var description: String { "could not decode \(context) from \(object)" }
    }

    // MARK: - Cross-consumer manifest gate evidence

    /// Emits a machine-readable executed-file record so
    /// `tooling/check-contracts.mjs`'s cross-consumer gate can prove (never
    /// merely assume) which manifest-listed files this Swift consumer
    /// actually executed, rather than trusting a hand-maintained list.
    private func emitExecutedFileReport(executedFiles: [String]) throws {
        let repositoryRoot = try RepositoryRoot.resolve()
        let reportsDirectory = repositoryRoot.appendingPathComponent("tooling/vector-conformance-reports")
        try FileManager.default.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
        let report: [String: Any] = ["consumer": "swift", "executedFiles": executedFiles.sorted()]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        try data.write(to: reportsDirectory.appendingPathComponent("swift.json"))
    }
}
