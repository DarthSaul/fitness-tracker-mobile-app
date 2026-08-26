import Foundation
import Testing
@testable import FitnessTracker

/// KEYCHAIN CAVEAT: there is no keychain protocol — `SessionManager.didSignIn`
/// writes the refresh token into the *real simulator keychain* (existing house
/// precedent; SessionManager tests instantiate a real `KeychainService`). Every
/// test that completes `didSignIn` must run its sign-in and assertions inside
/// `withSessionTeardown` so the keychain is cleared even when the body throws.
@Suite("AuthRepository email flows")
@MainActor
struct AuthRepositoryEmailTests {
    /// Runs the body, then always tears the session down — a thrown error must
    /// not leave the refresh token behind in the simulator keychain.
    private func withSessionTeardown(
        _ manager: SessionManager, _ body: () async throws -> Void
    ) async throws {
        do {
            try await body()
        } catch {
            await manager.signOut()
            throw error
        }
        await manager.signOut()
    }
    private func makeRepository() -> (AuthRepository, SessionManager, MockAPIClient) {
        let manager = SessionManager(keychain: KeychainService(), tokenStore: TokenStore())
        let client = MockAPIClient()
        manager.apiClient = client
        manager._setAuthStateForTesting(.unauthenticated)
        let repository = AuthRepository(apiClient: client, sessionManager: manager)
        return (repository, manager, client)
    }

    private let fixtureProfile = UserProfile(
        id: "user-001", email: "jane@example.com",
        name: "Jane Appleseed", avatarUrl: nil
    )

    /// `didSignIn` extracts the `sub` claim, so token fixtures must be
    /// real-JWT-shaped (header.base64url-payload.signature).
    private func makeAccessToken(sub: String) -> String {
        let payload = Data(#"{"sub":"\#(sub)"}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(payload).signature"
    }

    // MARK: - Sign in

    @Test("sign-in success persists tokens and authenticates")
    func signInSuccessAuthenticates() async throws {
        let (repository, manager, client) = makeRepository()
        let accessToken = makeAccessToken(sub: "user-001")
        client.handlers["POST /api/auth/native/email/signin"] = { _ in
            Data(#"{"accessToken":"\#(accessToken)","refreshToken":"refresh-abc"}"#.utf8)
        }
        client.stub(.getMe, response: fixtureProfile)

        try await withSessionTeardown(manager) {
            try await repository.signInWithEmail(email: "jane@example.com", password: "testpass123")

            #expect(manager.authState == .authenticated(userId: "user-001"))
            #expect(manager.userProfile == fixtureProfile)
        }
    }

    @Test("sign-in 401 propagates and leaves the session signed out")
    func signInInvalidCredentialsPropagates() async throws {
        let (repository, manager, client) = makeRepository()
        client.handlers["POST /api/auth/native/email/signin"] = { _ in
            throw APIError.httpError(statusCode: 401, message: "Invalid email or password.", data: Data())
        }

        // APIError's Equatable compares .httpError by status code only.
        await #expect(throws: APIError.httpError(statusCode: 401, message: nil, data: Data())) {
            try await repository.signInWithEmail(email: "jane@example.com", password: "wrong")
        }

        #expect(manager.authState == .unauthenticated)
    }

    // MARK: - Sign up

    @Test("sign-up requiring confirmation returns the outcome without touching the session")
    func signUpConfirmationRequired() async throws {
        let (repository, manager, client) = makeRepository()
        client.handlers["POST /api/auth/native/email/signup"] = { _ in
            Data(#"{"confirmationRequired":true}"#.utf8)
        }

        let outcome = try await repository.signUpWithEmail(
            email: "jane@example.com", password: "testpass123", name: "Jane"
        )

        #expect(outcome == .confirmationRequired)
        #expect(manager.authState == .unauthenticated)
    }

    @Test("sign-up with tokens signs straight in")
    func signUpWithTokensSignsIn() async throws {
        let (repository, manager, client) = makeRepository()
        let accessToken = makeAccessToken(sub: "user-001")
        client.handlers["POST /api/auth/native/email/signup"] = { _ in
            Data(#"{"confirmationRequired":false,"accessToken":"\#(accessToken)","refreshToken":"refresh-abc"}"#.utf8)
        }
        client.stub(.getMe, response: fixtureProfile)

        try await withSessionTeardown(manager) {
            let outcome = try await repository.signUpWithEmail(
                email: "jane@example.com", password: "testpass123", name: nil
            )

            #expect(outcome == .signedIn)
            #expect(manager.authState == .authenticated(userId: "user-001"))
        }
    }

    @Test("sign-up claiming no confirmation but missing tokens throws the contract error")
    func signUpMissingTokensThrows() async throws {
        let (repository, manager, client) = makeRepository()
        client.handlers["POST /api/auth/native/email/signup"] = { _ in
            Data(#"{"confirmationRequired":false}"#.utf8)
        }

        await #expect(throws: AuthError.self) {
            _ = try await repository.signUpWithEmail(
                email: "jane@example.com", password: "testpass123", name: nil
            )
        }

        #expect(manager.authState == .unauthenticated)
    }

    // MARK: - Reset & resend

    @Test("password reset posts the email to the web reset route")
    func requestPasswordResetHitsEndpoint() async throws {
        let (repository, _, client) = makeRepository()
        client.handlers["POST /api/auth/email/reset-password"] = { endpoint in
            guard case .requestPasswordReset(let body) = endpoint,
                  body.email == "jane@example.com"
            else {
                throw APIError.missingHandler(path: "unexpected reset body")
            }
            return Data(#"{"success":true}"#.utf8)
        }

        try await repository.requestPasswordReset(email: "jane@example.com")
    }

    @Test("resend confirmation posts the email to the resend route")
    func resendConfirmationHitsEndpoint() async throws {
        let (repository, _, client) = makeRepository()
        client.handlers["POST /api/auth/native/email/resend-confirmation"] = { endpoint in
            guard case .resendConfirmationEmail(let body) = endpoint,
                  body.email == "jane@example.com"
            else {
                throw APIError.missingHandler(path: "unexpected resend body")
            }
            return Data(#"{"success":true}"#.utf8)
        }

        try await repository.resendConfirmationEmail(email: "jane@example.com")
    }
}
