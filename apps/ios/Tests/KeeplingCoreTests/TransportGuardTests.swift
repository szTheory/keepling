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

    /// 04-18-PLAN.md Task 2. The adapter gained a credential seam so it can
    /// authenticate as a native client. Holding a credential must buy NO
    /// relaxation of the transport rule: the promise this phase makes is that
    /// the guard was extended by nothing, and a promise about a security guard
    /// is prose until a test refuses the counter-example.
    func testCredentialProviderDoesNotRelaxTheGuardForANonLoopbackHTTPHost() {
        XCTAssertThrowsError(
            try KeeplingSyncAdapter(
                baseURL: URL(string: "http://192.168.1.50:4113")!,
                credentialProvider: { "a-real-looking-bearer-credential" }
            )
        ) { error in
            XCTAssertEqual(error as? KeeplingSyncAdapter.ConfigurationError, .insecureBaseURL)
        }
    }

    /// The same base URL over HTTPS IS accepted with a credential -- so the
    /// case above is proving the SCHEME rule, not merely that the constructor
    /// rejects everything it is handed.
    func testCredentialProviderIsAcceptedOverHTTPSToTheSameHost() throws {
        _ = try KeeplingSyncAdapter(
            baseURL: URL(string: "https://192.168.1.50:4113")!,
            credentialProvider: { "a-real-looking-bearer-credential" }
        )
    }
}
