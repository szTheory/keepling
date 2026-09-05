import AuthenticationServices
import KeeplingCore
import SwiftUI
import UIKit

/// The concrete RFC 8252 system-browser presenter for `DeviceGrantClient`.
/// Lives HERE, not in `KeeplingCore`, because `KeeplingCore` is
/// deliberately pure Swift (`Package.swift`'s own stated constraint) --
/// `ASPresentationAnchor` is `UIWindow` on iOS, a UIKit type, so this
/// class is the seam where the UIKit dependency this flow structurally
/// needs actually lives.
@MainActor
final class ASWebAuthenticationSessionPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func present(authorizationURL: URL, callbackURLScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: callbackURLScheme
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? URLError(.unknown))
                }
            }
            session.presentationContextProvider = self
            // D-08's own posture applies here too: this is the ONE
            // moment the account's own web session is used, and never
            // shared beyond the redirect this session captures.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            _ = session.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIWindow()
    }
}

/// D-43 (04-CONTEXT.md): Phase 3's reauthentication copy vocabulary
/// carries over unchanged, with the one device-specific substitution
/// already applied elsewhere (`Saved on this iPhone`). This surface keeps
/// the exact inherited control label -- `Sign In and Continue` -- rather
/// than inventing an iPhone-specific phrase for the same action.
public struct SignInFlow: View {
    public enum Phase: Equatable {
        case signedOut
        case authorizing
        case signedIn
        case failed(String)
    }

    @State private var phase: Phase = .signedOut
    private let serverBaseURL: URL
    private let client: DeviceGrantClient
    private let callbackURLScheme: String
    private let presenter = ASWebAuthenticationSessionPresenter()

    public init(serverBaseURL: URL, client: DeviceGrantClient, callbackURLScheme: String = "keeplingios") {
        self.serverBaseURL = serverBaseURL
        self.client = client
        self.callbackURLScheme = callbackURLScheme
    }

    public var body: some View {
        VStack(spacing: 16) {
            switch phase {
            case .signedOut, .failed:
                Button("Sign In and Continue") {
                    Task { await beginSignIn() }
                }
            case .authorizing:
                ProgressView()
            case .signedIn:
                Text("Signed in")
            }
        }
        .padding()
    }

    @MainActor
    private func beginSignIn() async {
        phase = .authorizing
        let authorizationURL = client.beginAuthorization(serverBaseURL: serverBaseURL)
        do {
            let callbackURL = try await presenter.present(authorizationURL: authorizationURL, callbackURLScheme: callbackURLScheme)
            _ = try await client.completeAuthorization(callbackURL: callbackURL)
            phase = .signedIn
        } catch {
            phase = .failed(String(describing: error))
        }
    }
}
