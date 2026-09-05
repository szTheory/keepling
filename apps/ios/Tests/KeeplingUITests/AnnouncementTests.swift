import XCTest
import KeeplingCore

/// Covers `AnnouncementDebouncer` -- exactly one debounced accessibility
/// announcement per meaningful synchronization-state transition, with
/// `.high` priority reserved for actionable exceptions and routine
/// local-acceptance transitions batched into a bounded summary rather than
/// announced individually (04-10-PLAN.md Task 1, D-42). A plain unit test
/// (no `XCUIApplication` launch) -- `AnnouncementDebouncer` is pure Swift
/// logic with no UIKit/SwiftUI dependency, so it needs no simulator
/// process; it lives in this target per the plan's own file placement.
final class AnnouncementTests: XCTestCase {
    private struct Recorded: Equatable {
        let message: String
        let priority: AnnouncementPriority
    }

    private func makeDebouncer() -> (AnnouncementDebouncer, () -> [Recorded]) {
        var recorded: [Recorded] = []
        let debouncer = AnnouncementDebouncer { message, priority in
            recorded.append(Recorded(message: message, priority: priority))
        }
        return (debouncer, { recorded })
    }

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testOneAnnouncementPerMeaningfulTransition() {
        let (debouncer, recorded) = makeDebouncer()
        debouncer.process(SyncPresentation.derive(.offline(), now: epoch))
        debouncer.process(SyncPresentation.derive(.conflict(affectedCount: 1), now: epoch))
        XCTAssertEqual(recorded().count, 2)
    }

    func testRepeatingTheSameKindEmitsNoSecondAnnouncement() {
        let (debouncer, recorded) = makeDebouncer()
        debouncer.process(SyncPresentation.derive(.offline(), now: epoch))
        debouncer.process(SyncPresentation.derive(.offline(), now: epoch))
        debouncer.process(SyncPresentation.derive(.offline(), now: epoch))
        XCTAssertEqual(recorded().count, 1, "the same state repeating is not a meaningful transition")
    }

    func testHighPriorityIsReservedForActionableExceptions() {
        let (debouncer, recorded) = makeDebouncer()
        debouncer.process(SyncPresentation.derive(.conflict(affectedCount: 1), now: epoch))
        XCTAssertEqual(recorded().last?.priority, .high)
    }

    func testNonExceptionTransitionsAreNormalPriority() {
        let (debouncer, recorded) = makeDebouncer()
        debouncer.process(SyncPresentation.derive(.offline(), now: epoch))
        XCTAssertEqual(recorded().last?.priority, .normal)
    }

    func testRoutineAcknowledgementsBatchRatherThanAnnouncingEachOne() {
        let (debouncer, recorded) = makeDebouncer()
        debouncer.process(SyncPresentation.derive(.localAcceptance(), now: epoch))
        debouncer.process(SyncPresentation.derive(.localAcceptance(), now: epoch))
        debouncer.process(SyncPresentation.derive(.localAcceptance(), now: epoch))
        XCTAssertEqual(recorded().count, 0, "batched acceptances are silent until flushed")
        debouncer.process(SyncPresentation.derive(.healthy(), now: epoch))
        XCTAssertEqual(recorded().count, 1)
        XCTAssertEqual(recorded().first?.message, "3 changes saved on this iPhone")
        XCTAssertEqual(recorded().first?.priority, .normal)
    }

    func testFlushBatchedAcceptancesIfNeededEmitsWhenPending() {
        let (debouncer, recorded) = makeDebouncer()
        debouncer.process(SyncPresentation.derive(.localAcceptance(), now: epoch))
        XCTAssertTrue(debouncer.flushBatchedAcceptancesIfNeeded())
        XCTAssertEqual(recorded().count, 1)
        XCTAssertEqual(recorded().first?.message, "1 change saved on this iPhone")
    }

    func testFlushBatchedAcceptancesIfNeededIsANoOpWithNothingPending() {
        let (debouncer, recorded) = makeDebouncer()
        XCTAssertFalse(debouncer.flushBatchedAcceptancesIfNeeded())
        XCTAssertEqual(recorded().count, 0)
    }

    func testNoAnnouncementCarriesTaskContentOnlyBoundedCounts() {
        // T-04-10-03: batched acknowledgements never carry task titles.
        let (debouncer, recorded) = makeDebouncer()
        for _ in 0..<5 {
            debouncer.process(SyncPresentation.derive(.localAcceptance(), now: epoch))
        }
        debouncer.flushBatchedAcceptancesIfNeeded()
        XCTAssertEqual(recorded().first?.message, "5 changes saved on this iPhone")
    }
}
