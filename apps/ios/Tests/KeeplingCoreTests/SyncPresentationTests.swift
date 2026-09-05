import XCTest
@testable import KeeplingCore

/// Covers `SyncPresentation.derive` -- one authoritative presentation
/// projection (04-10-PLAN.md Task 1, D-41). An injected clock makes the
/// grace-period absorption boundary deterministic.
final class SyncPresentationTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Closed input union, one case per inherited state

    func testHealthyDerivesSilentSummary() {
        let summary = SyncPresentation.derive(.healthy(lastSuccessfulContact: "8 minutes ago"), now: epoch)
        XCTAssertEqual(summary.kind, .healthy)
        XCTAssertNil(summary.copy)
        XCTAssertNil(summary.count)
        XCTAssertTrue(summary.actions.isEmpty)
        XCTAssertEqual(summary.lastSuccessfulContact, "8 minutes ago")
    }

    func testEveryClosedInputKindProducesItsOwnNamedKind() {
        let inputs: [(SyncPresentationInput, SyncPresentationKind)] = [
            (.opening, .opening),
            (.preparing, .preparing),
            (.offline(), .offline),
            (.localAcceptance(), .localAcceptance),
            (.localSaveFailure, .localSaveFailure),
            (.retryableFailure(), .retryableFailure),
            (.uncertain(), .uncertain),
            (.rejected(), .rejected),
            (.conflict(), .conflict),
            (.authenticationFence(), .authenticationFence),
            (.unrecoverable(.integrityCheckFailed(version: 1, detail: "x")), .unrecoverable),
        ]
        for (input, expectedKind) in inputs {
            XCTAssertEqual(SyncPresentation.derive(input, now: epoch).kind, expectedKind, "\(input) should derive \(expectedKind)")
        }
    }

    // MARK: - Grace-period absorption (shared constant, injected clock)

    func testUpdatingOneMillisecondBeforeGracePeriodDerivesHealthy() {
        let startedAt = epoch.addingTimeInterval(-(SyncPassScheduler.activeGracePeriod - 0.001))
        let summary = SyncPresentation.derive(.updating(startedAt: startedAt), now: epoch)
        XCTAssertEqual(summary.kind, .healthy)
        XCTAssertNil(summary.copy)
    }

    func testUpdatingOneMillisecondAfterGracePeriodDerivesUpdatingWithRecoveryAction() {
        let startedAt = epoch.addingTimeInterval(-(SyncPassScheduler.activeGracePeriod + 0.001))
        let summary = SyncPresentation.derive(.updating(startedAt: startedAt), now: epoch)
        XCTAssertEqual(summary.kind, .updating)
        XCTAssertEqual(summary.copy, "Updating…")
        XCTAssertEqual(summary.actions.map(\.code), [.inspect])
    }

    // MARK: - Bounded counts

    func testPresentedCountsAreBoundedAndNeverUnbounded() {
        let summary = SyncPresentation.derive(.retryableFailure(pendingCount: 500), now: epoch)
        XCTAssertEqual(summary.count, SyncPresentation.maximumPresentedCount)
    }

    func testNegativeCountsClampToZero() {
        let summary = SyncPresentation.derive(.retryableFailure(pendingCount: -5), now: epoch)
        XCTAssertEqual(summary.count, 0)
    }

    // MARK: - Every surface reads the same derived summary object (D-41)

    func testAllThreeSurfacesReadTheIdenticalDerivedSummary() {
        let input = SyncPresentationInput.conflict(affectedCount: 2)
        let accessorySummary = SyncPresentation.derive(input, now: epoch)
        let inlineRowSummary = SyncPresentation.derive(input, now: epoch)
        let sheetSummary = SyncPresentation.derive(input, now: epoch)
        XCTAssertEqual(accessorySummary, inlineRowSummary)
        XCTAssertEqual(inlineRowSummary, sheetSummary)
    }

    // MARK: - Copy vocabulary (D-43 device substitution)

    func testEveryDerivedCopyStringMatchesTheInheritedMacTableWithIPhoneSubstitution() {
        XCTAssertEqual(SyncPresentation.derive(.offline(), now: epoch).copy, "Offline — showing tasks saved on this iPhone")
        XCTAssertEqual(SyncPresentation.derive(.localAcceptance(), now: epoch).copy, "Saved on this iPhone")
        XCTAssertEqual(
            SyncPresentation.derive(.retryableFailure(), now: epoch).copy,
            "Couldn’t reach the server. Your changes stay on this iPhone."
        )
        XCTAssertEqual(
            SyncPresentation.derive(.authenticationFence(), now: epoch).copy,
            "Sign in to continue syncing. Changes remain safe on this iPhone."
        )
        XCTAssertEqual(
            SyncPresentation.derive(.unrecoverable(.checksumDrift(version: 1)), now: epoch).copy,
            "Keepling can’t open the tasks saved on this iPhone. Your data was not replaced or removed."
        )
    }

    func testNoDerivedCopyStringContainsThisMac() {
        for copy in SyncPresentation.allDerivedCopyStrings(now: epoch) {
            XCTAssertFalse(copy.contains("this Mac"), "found forbidden 'this Mac' in: \(copy)")
        }
    }

    func testNoDerivedCopyStringClaimsGlobalCompleteness() {
        for copy in SyncPresentation.allDerivedCopyStrings(now: epoch) {
            XCTAssertFalse(copy.contains("Everything synced"), "found forbidden global-completeness claim in: \(copy)")
        }
    }

    // MARK: - Backend vocabulary never leaks into primary copy

    func testNoDerivedCopyStringContainsBackendVocabulary() {
        let forbidden = ["outbox", "cursor", "SQLite", "fingerprint", "bootstrap", "transport"]
        for copy in SyncPresentation.allDerivedCopyStrings(now: epoch) {
            for word in forbidden {
                XCTAssertFalse(copy.localizedCaseInsensitiveContains(word), "found forbidden backend vocabulary '\(word)' in: \(copy)")
            }
        }
    }

    // MARK: - Uncertain acceptance derives its own named state

    func testUncertainDerivesItsOwnNamedStateNeverHealthyNorRejected() {
        let summary = SyncPresentation.derive(.uncertain(pendingCount: 1), now: epoch)
        XCTAssertEqual(summary.kind, .uncertain)
        XCTAssertNotEqual(summary.kind, .healthy)
        XCTAssertNotEqual(summary.kind, .rejected)
        XCTAssertEqual(summary.actions.map(\.code), [.checkAgain])
    }

    // MARK: - StoreUnrecoverable mapping

    func testEveryStoreUnrecoverableCaseDerivesUnrecoverableWithInspectExportAndRemoveActions() {
        let cases: [StoreUnrecoverable] = [
            .checksumDrift(version: 1),
            .aheadOfLedger(foundVersion: 3, knownVersionCount: 2),
            .migrationMidApplyFailure(version: 2),
            .integrityCheckFailed(version: 1, detail: "corrupt"),
        ]
        for storeError in cases {
            let summary = SyncPresentation.derive(.unrecoverable(storeError), now: epoch)
            XCTAssertEqual(summary.kind, .unrecoverable)
            XCTAssertEqual(summary.actions.map(\.code), [.inspect, .export, .removeLocalData])
        }
    }

    // MARK: - Actionable-exception classification the accessory's priority order reads

    func testActionableExceptionClassification() {
        let exceptionKinds: [SyncPresentationInput] = [
            .localSaveFailure, .retryableFailure(), .uncertain(), .rejected(), .conflict(), .authenticationFence(),
            .unrecoverable(.checksumDrift(version: 1)),
        ]
        for input in exceptionKinds {
            XCTAssertTrue(SyncPresentation.derive(input, now: epoch).isActionableException, "\(input) must classify as actionable")
        }
        let nonExceptionKinds: [SyncPresentationInput] = [.healthy(), .opening, .preparing, .offline(), .localAcceptance()]
        for input in nonExceptionKinds {
            XCTAssertFalse(SyncPresentation.derive(input, now: epoch).isActionableException, "\(input) must not classify as actionable")
        }
    }
}
