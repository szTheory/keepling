import XCTest
import GRDB
@testable import KeeplingCore

/// Adversarial proof of D-04 G1 (durability posture verified per
/// connection, not per Configuration object) and G6 (WAL/synchronous/
/// busy-timeout proven by PRAGMA readback), plus foreign-key teeth and G5's
/// main-thread precondition.
///
/// Resolves 04-RESEARCH.md Open Question 3: `Configuration.prepareDatabase`
/// is the per-connection hook, and `DatabasePool` opens multiple reader
/// connections, so G1's "verified per connection" is satisfied ONLY by a
/// test that forces several reader connections open simultaneously and
/// reads the pragma on each -- a test that opens one reader does not
/// satisfy G1.
final class DurabilityPostureTests: XCTestCase {
    private func storePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("durability-posture-test.sqlite").path
    }

    private func offMain<T>(_ work: @escaping () throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<T, Error>!
        DispatchQueue.global().async {
            do { result = .success(try work()) } catch { result = .failure(error) }
            semaphore.signal()
        }
        semaphore.wait()
        return try result.get()
    }

    // MARK: G1 -- foreign_keys verified on SEVERAL concurrently-open reader connections

    func testForeignKeysAndDurabilityPostureAreEnabledOnEveryConcurrentlyOpenReaderConnection() throws {
        let store = try GRDBLocalStore(path: storePath())
        let readerCount = 3

        // Explicit reusable barrier (mirrors the Phase 1 concurrency-test
        // convention): every participant must have ENTERED its own
        // `dbPool.read` block -- proving DatabasePool actually opened
        // `readerCount` separate connections concurrently, not reused one
        // serially -- before any of them is allowed to return.
        let entered = DispatchGroup()
        let release = DispatchSemaphore(value: 0)
        for _ in 0..<readerCount { entered.enter() }

        let resultsLock = NSLock()
        var results: [(foreignKeys: Bool, journalMode: String, synchronous: Int, busyTimeoutMs: Int)] = []
        let allDone = DispatchGroup()
        for _ in 0..<readerCount {
            allDone.enter()
            DispatchQueue.global().async {
                let posture = try? store.__test_readPostureHoldingConnectionOpen(barrier: entered, releaseSignal: release)
                resultsLock.lock()
                if let posture { results.append(posture) }
                resultsLock.unlock()
                allDone.leave()
            }
        }

        XCTAssertEqual(entered.wait(timeout: .now() + 10), .success, "not all \(readerCount) readers opened concurrently within the timeout")
        for _ in 0..<readerCount { release.signal() }
        XCTAssertEqual(allDone.wait(timeout: .now() + 10), .success)

        XCTAssertEqual(results.count, readerCount)
        for posture in results {
            XCTAssertTrue(posture.foreignKeys, "PRAGMA foreign_keys must read back enabled on every pool connection")
            XCTAssertEqual(posture.journalMode.lowercased(), "wal")
            XCTAssertEqual(posture.synchronous, 2, "SQLite reports synchronous=FULL as integer 2")
            XCTAssertGreaterThan(posture.busyTimeoutMs, 0, "busy timeout must be a finite positive value")
        }
    }

    // MARK: G6 -- durability posture readback on a single connection (baseline)

    func testDurabilityPostureReadsBackFromAnOpenConnectionNotFromConfiguration() throws {
        let store = try GRDBLocalStore(path: storePath())
        let posture = try store.readDurabilityPosture()
        XCTAssertTrue(posture.foreignKeys)
        XCTAssertEqual(posture.journalMode.lowercased(), "wal")
        XCTAssertEqual(posture.synchronous, 2)
        XCTAssertGreaterThan(posture.busyTimeoutMs, 0)
    }

    // MARK: integrity_check / foreign_key_check clean on fresh store and forward-migration fixture

    func testIntegrityAndForeignKeyChecksAreCleanOnAFreshStore() throws {
        let store = try GRDBLocalStore(path: storePath())
        XCTAssertEqual(try store.integrityCheckResults(), ["ok"])
        XCTAssertTrue(try store.foreignKeyCheckViolations().isEmpty)
    }

    func testIntegrityAndForeignKeyChecksAreCleanOnTheForwardMigrationFixture() throws {
        let store = try GRDBLocalStore(path: try FixtureFactory.migration1FixtureCopy())
        XCTAssertEqual(try store.integrityCheckResults(), ["ok"])
        XCTAssertTrue(try store.foreignKeyCheckViolations().isEmpty)
    }

    // MARK: Foreign keys have teeth -- an orphan insert is rejected

    func testInsertingAChildRowWithANonexistentParentIsRejectedBySQLite() throws {
        let store = try GRDBLocalStore(path: storePath())
        XCTAssertThrowsError(
            try store.__test_executeRawSQL(
                "INSERT INTO mutation_journal(mutation_id, outcome) VALUES ('no-such-parent', 'pending')"
            )
        ) { error in
            guard let dbError = error as? DatabaseError, dbError.resultCode.primaryResultCode == .SQLITE_CONSTRAINT else {
                return XCTFail("expected a SQLite foreign-key constraint error, got \(error)")
            }
        }
    }

    // MARK: G5 -- main-thread precondition trips (observed via substitution, never a real trap)

    func testMainThreadPreconditionTripsWhenAStoreMethodIsCalledFromTheMainThread() throws {
        let store = try GRDBLocalStore(path: storePath())
        let tripped = expectation(description: "main-thread violation handler fired")
        GRDBLocalStore.mainThreadViolationHandler = { tripped.fulfill() }
        defer { GRDBLocalStore.mainThreadViolationHandler = nil }

        XCTAssertTrue(Thread.isMainThread, "this test itself must run on the main thread for the assertion to mean anything")
        _ = try? store.snapshot() // called directly on the main thread -- no offMain wrapper.

        wait(for: [tripped], timeout: 1)
    }
}
