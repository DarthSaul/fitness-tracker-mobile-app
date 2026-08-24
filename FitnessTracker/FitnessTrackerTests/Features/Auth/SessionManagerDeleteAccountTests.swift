import Foundation
import Testing
@testable import FitnessTracker

@Suite("SessionManager delete account")
@MainActor
struct SessionManagerDeleteAccountTests {
    private func makeManager(authenticatedAs userId: String? = "user-001") -> (SessionManager, MockAPIClient) {
        let manager = SessionManager(keychain: KeychainService(), tokenStore: TokenStore())
        let client = MockAPIClient()
        manager.apiClient = client
        if let userId {
            manager._setAuthStateForTesting(.authenticated(userId: userId))
        }
        return (manager, client)
    }

    private let fixtureProfile = UserProfile(
        id: "user-001", email: "jane@example.com",
        name: "Jane Appleseed", avatarUrl: nil
    )

    /// Seeds the cached profile so teardown tests can assert it gets cleared
    /// (or survives) alongside authState.
    private func seedProfile(_ manager: SessionManager, _ client: MockAPIClient) async {
        client.stub(.getMe, response: fixtureProfile)
        await manager.loadProfile()
        #expect(manager.userProfile == fixtureProfile)
    }

    @Test("200 tears down the session")
    func successTearsDownSession() async throws {
        let (manager, client) = makeManager()
        await seedProfile(manager, client)
        client.handlers["DELETE /api/auth/me"] = { _ in Data(#"{"success":true}"#.utf8) }

        try await manager.deleteAccount()

        #expect(manager.authState == .unauthenticated)
        #expect(manager.userProfile == nil)
    }

    @Test("404 is treated as success and tears down the session")
    func notFoundTreatedAsSuccess() async throws {
        let (manager, client) = makeManager()
        await seedProfile(manager, client)
        client.handlers["DELETE /api/auth/me"] = { _ in
            throw APIError.httpError(statusCode: 404, message: "User not found", data: Data())
        }

        try await manager.deleteAccount()

        #expect(manager.authState == .unauthenticated)
        #expect(manager.userProfile == nil)
    }

    @Test("500 rethrows and leaves the session intact")
    func serverErrorLeavesSessionIntact() async throws {
        let (manager, client) = makeManager()
        await seedProfile(manager, client)
        client.handlers["DELETE /api/auth/me"] = { _ in
            throw APIError.httpError(statusCode: 500, message: "Failed to delete account. Please try again.", data: Data())
        }

        // APIError's Equatable compares .httpError by status code only.
        await #expect(throws: APIError.httpError(statusCode: 500, message: nil, data: Data())) {
            try await manager.deleteAccount()
        }

        #expect(manager.authState == .authenticated(userId: "user-001"))
        #expect(manager.userProfile == fixtureProfile)
    }

    @Test("network error rethrows and leaves the session intact")
    func networkErrorLeavesSessionIntact() async throws {
        let (manager, client) = makeManager()
        await seedProfile(manager, client)
        client.handlers["DELETE /api/auth/me"] = { _ in
            throw APIError.network(URLError(.notConnectedToInternet))
        }

        await #expect(throws: APIError.self) {
            try await manager.deleteAccount()
        }

        #expect(manager.authState == .authenticated(userId: "user-001"))
        #expect(manager.userProfile == fixtureProfile)
    }

    @Test("unauthorized propagates without teardown")
    func unauthorizedPropagatesWithoutTeardown() async throws {
        let (manager, client) = makeManager()
        await seedProfile(manager, client)
        client.stubUnauthorized(for: .deleteAccount)

        // SessionManager must not conflate "session dead" with "account
        // deleted" — signing out on .unauthorized is the caller's decision.
        await #expect(throws: APIError.unauthorized) {
            try await manager.deleteAccount()
        }

        #expect(manager.authState == .authenticated(userId: "user-001"))
        #expect(manager.userProfile == fixtureProfile)
    }
}
