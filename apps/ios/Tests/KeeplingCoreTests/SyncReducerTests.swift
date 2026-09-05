import XCTest
@testable import KeeplingCore

/// Hand-written unit tests for `SyncReducer` (04-03-PLAN.md Task 2
/// `<behavior>`), independent of the 13 golden vector files, so a reducer
/// bug is diagnosable without a whole-file harness in the way.
final class SyncReducerTests: XCTestCase {
    private func makeMutation(
        id: String = "mutation-1",
        fingerprint: String = "fp-1",
        commandBytes: String = "{}",
        resourceKeys: [String] = ["task:task-1"],
        dependencies: [String] = [],
        acceptedAt: String = "2026-01-01T00:00:00Z",
        entityId: String = "task-1",
        revision: Int = 1
    ) -> SyncMutation {
        SyncMutation(
            mutationId: id,
            fingerprint: fingerprint,
            commandBytes: commandBytes,
            resourceKeys: resourceKeys,
            dependencies: dependencies,
            acceptedAt: acceptedAt,
            effectEntityId: entityId,
            effectSnapshot: SyncSnapshot(id: entityId, revision: revision, extra: ["title": .string("Title")])
        )
    }

    // MARK: - localAccept

    func testLocalAcceptWithValidMutationReturnsLocalSavedAndExactlyOneNewEntryEverywhere() throws {
        let mutation = makeMutation()
        let result = SyncReducer.localAccept(SyncReducerState(), mutation: mutation)
        let (outcome, state) = try result.get()

        XCTAssertEqual(outcome, "local_saved")
        XCTAssertEqual(state.journal.count, 1)
        XCTAssertEqual(state.journal[mutation.mutationId]?.outcome, "pending")
        XCTAssertEqual(state.outbox, [mutation])
        XCTAssertEqual(state.visible[mutation.effectEntityId], mutation.effectSnapshot)
        XCTAssertEqual(state.dependencies[mutation.mutationId], [])
    }

    func testLocalAcceptRejectsReusedMutationIdentityAndLeavesStateUnchanged() throws {
        let mutation = makeMutation()
        let (_, accepted) = try SyncReducer.localAccept(SyncReducerState(), mutation: mutation).get()

        let result = SyncReducer.localAccept(accepted, mutation: mutation)
        guard case .failure(.mutationIdentityReused) = result else {
            return XCTFail("expected mutationIdentityReused, got \(result)")
        }
    }

    func testLocalAcceptRejectsMissingDependencyAndLeavesStateUnchanged() {
        let mutation = makeMutation(id: "mutation-child", dependencies: ["mutation-missing"])
        let state = SyncReducerState()
        let result = SyncReducer.localAccept(state, mutation: mutation)
        guard case .failure(.orphanDependency) = result else {
            return XCTFail("expected orphanDependency, got \(result)")
        }
    }

    // MARK: - pull

    func testPullAppliesAtMost50ChangesAndAdvancesCursorOnlyToTheLastPage() throws {
        let firstPage = SyncPullPage(
            cursor: "cursor-1",
            changes: [SyncPullChange(entityId: "task-1", snapshot: SyncSnapshot(id: "task-1", revision: 1))]
        )
        let afterFirst = try SyncReducer.pull(SyncReducerState(), page: firstPage).get()
        XCTAssertEqual(afterFirst.cursor, "cursor-1")
        XCTAssertEqual(afterFirst.canonicalShadow["task-1"]?.revision, 1)

        let oversizedPage = SyncPullPage(
            cursor: "cursor-2",
            changes: (0..<51).map { SyncPullChange(entityId: "task-\($0)", snapshot: SyncSnapshot(id: "task-\($0)", revision: 1)) }
        )
        let oversizedResult = SyncReducer.pull(afterFirst, page: oversizedPage)
        guard case .failure(.pullPageTooLarge) = oversizedResult else {
            return XCTFail("expected pullPageTooLarge, got \(oversizedResult)")
        }

        let boundedPage = SyncPullPage(
            cursor: "cursor-3",
            changes: (0..<50).map { SyncPullChange(entityId: "other-\($0)", snapshot: SyncSnapshot(id: "other-\($0)", revision: 1)) }
        )
        let afterBounded = try SyncReducer.pull(afterFirst, page: boundedPage).get()
        XCTAssertEqual(afterBounded.cursor, "cursor-3")
        XCTAssertEqual(afterBounded.canonicalShadow.count, 51)
    }

    // MARK: - readyPushes

    func testReadyPushesPreservesFIFOWithinAResourceKeyWhileDisjointKeysProgressIndependently() throws {
        let mutationA = makeMutation(id: "mutation-a", resourceKeys: ["task:a", "shared"], entityId: "a")
        let mutationB = makeMutation(id: "mutation-b", resourceKeys: ["task:b", "shared"], entityId: "b")
        let mutationC = makeMutation(id: "mutation-c", resourceKeys: ["task:c"], entityId: "c")

        var state = SyncReducerState()
        state = try SyncReducer.localAccept(state, mutation: mutationA).get().state
        state = try SyncReducer.localAccept(state, mutation: mutationB).get().state
        state = try SyncReducer.localAccept(state, mutation: mutationC).get().state

        let ready = try SyncReducer.readyPushes(state).get()
        XCTAssertEqual(ready.map(\.mutationId), ["mutation-a", "mutation-c"])
    }

    func testReadyPushesIsBoundedAt25() throws {
        var state = SyncReducerState()
        var mutations: [SyncMutation] = []
        for index in 0..<30 {
            let mutation = makeMutation(id: "mutation-\(index)", resourceKeys: ["task:\(index)"], entityId: "task-\(index)")
            mutations.append(mutation)
            state = try SyncReducer.localAccept(state, mutation: mutation).get().state
        }
        let ready = try SyncReducer.readyPushes(state).get()
        XCTAssertEqual(ready.count, 25)
        XCTAssertEqual(ready.map(\.mutationId), mutations.prefix(25).map(\.mutationId))
    }

    // MARK: - dependency satisfaction

    func testOnlyAcceptedAndAlreadySatisfiedOutcomesSatisfyADependency() throws {
        for (outcome, satisfies) in [
            (SyncTerminalOutcome.accepted, true),
            (.alreadySatisfied, true),
            (.rejected, false),
            (.stale, false),
            (.conflict, false),
        ] {
            let parent = makeMutation(id: "parent", resourceKeys: ["task:parent"], entityId: "parent")
            let child = makeMutation(id: "child", resourceKeys: ["task:child"], dependencies: ["parent"], entityId: "child")

            var state = SyncReducerState()
            state = try SyncReducer.localAccept(state, mutation: parent).get().state
            state = try SyncReducer.localAccept(state, mutation: child).get().state
            state = try SyncReducer.acknowledge(
                state,
                acknowledgement: SyncAcknowledgementInput(
                    mutationId: "parent", fingerprint: parent.fingerprint, outcome: outcome,
                    snapshot: SyncSnapshot(id: "parent", revision: 2)
                )
            ).get()

            let ready = try SyncReducer.readyPushes(state).get()
            let childIsReady = ready.contains { $0.mutationId == "child" }
            XCTAssertEqual(childIsReady, satisfies, "outcome \(outcome) should satisfy=\(satisfies)")
        }
    }

    // MARK: - Result-based API

    func testEveryEntryPointReturnsAResultRatherThanThrowing() {
        // Compile-time proof: `Result<_, SyncReducerError>` is the return
        // type of every mutating entry point below (a `throws` signature
        // would not type-check against these assignments).
        let localAccept: (SyncReducerState, SyncMutation) -> Result<(outcome: String, state: SyncReducerState), SyncReducerError> = SyncReducer.localAccept
        let pull: (SyncReducerState, SyncPullPage) -> Result<SyncReducerState, SyncReducerError> = SyncReducer.pull
        let readyPushes: (SyncReducerState) -> Result<[SyncMutation], SyncReducerError> = SyncReducer.readyPushes
        let acknowledge: (SyncReducerState, SyncAcknowledgementInput) -> Result<SyncReducerState, SyncReducerError> = SyncReducer.acknowledge
        _ = (localAccept, pull, readyPushes, acknowledge)
    }

    // MARK: - Idempotent replay

    func testApplyingTheSameTerminalAcknowledgementTwiceProducesTheSameState() throws {
        let mutation = makeMutation()
        var state = try SyncReducer.localAccept(SyncReducerState(), mutation: mutation).get().state
        let acknowledgement = SyncAcknowledgementInput(
            mutationId: mutation.mutationId, fingerprint: mutation.fingerprint, outcome: .accepted,
            snapshot: SyncSnapshot(id: mutation.effectEntityId, revision: 2)
        )
        state = try SyncReducer.acknowledge(state, acknowledgement: acknowledgement).get()
        let replayed = try SyncReducer.acknowledge(state, acknowledgement: acknowledgement).get()
        XCTAssertEqual(replayed, state)
    }
}
