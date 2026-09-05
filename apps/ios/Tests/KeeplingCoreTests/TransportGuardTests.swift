import XCTest
import OpenAPIURLSession
@testable import KeeplingCore

/// T-04-05-04: a non-HTTPS base URL is rejected unless its host is
/// `127.0.0.1` or `localhost` -- reimplemented identically from
/// `apps/desktop/main/adapters/sync.ts`'s constructor guard
/// (`baseUrl.protocol !== 'https:' && baseUrl.hostname !== '127.0.0.1' &&
/// baseUrl.hostname !== 'localhost'`).
final class TransportGuardTests: XCTestCase {
    func testHTTPBaseURLWithNonLoopbackHostIsRejected() {
        XCTAssertThrowsError(try KeeplingSyncAdapter(baseURL: URL(string: "http://keepling.example.com")!)) { error in
            XCTAssertEqual(error as? KeeplingSyncAdapter.ConfigurationError, .insecureBaseURL)
        }
    }

    func testHTTPBaseURLAgainst127001IsAccepted() throws {
        _ = try KeeplingSyncAdapter(baseURL: URL(string: "http://127.0.0.1:4000")!)
    }

    func testHTTPBaseURLAgainstLocalhostIsAccepted() throws {
        _ = try KeeplingSyncAdapter(baseURL: URL(string: "http://localhost:4000")!)
    }

    func testHTTPSBaseURLIsAccepted() throws {
        _ = try KeeplingSyncAdapter(baseURL: URL(string: "https://keepling.example.com")!)
    }
}
