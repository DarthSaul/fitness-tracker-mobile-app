import Foundation
import Testing
@testable import FitnessTracker

@Suite("SessionManager profile")
@MainActor
struct SessionManagerProfileTests {
    private func makeManager(authenticatedAs userId: String? = "user-001") -> (SessionManager, MockAPIClient) {
        let manager = SessionManager(keychain: KeychainService(), tokenStore: TokenStore())
        let client = MockAPIClient()
        manager.apiClient = client
        // loadProfile() guards on .authenticated — install it directly here so
        // tests don't have to fake a JWT + Keychain write to flip the state.
        if let userId {
            manager._setAuthStateForTesting(.authenticated(userId: userId))
        }
        return (manager, client)
    }

    private let fixtureProfile = UserProfile(
        id: "user-001", email: "jane@example.com",
        name: "Jane Appleseed", avatarUrl: nil
    )

    @Test("loadProfile populates userProfile from /api/auth/me")
    func loadProfilePopulates() async throws {
        let (manager, client) = makeManager()
        client.stub(.getMe, response: fixtureProfile)

        await manager.loadProfile()

        #expect(manager.userProfile == fixtureProfile)
    }

    @Test("loadProfile swallows errors and leaves userProfile nil")
    func loadProfileSwallowsErrors() async throws {
        let (manager, client) = makeManager()
        client.handlers["GET /api/auth/me"] = { _ in
            throw APIError.httpError(statusCode: 500, message: nil, data: Data())
        }

        await manager.loadProfile()

        #expect(manager.userProfile == nil)
    }

    @Test("loadProfile is a no-op when apiClient was never wired")
    func loadProfileNoOpWithoutClient() async throws {
        let manager = SessionManager(keychain: KeychainService(), tokenStore: TokenStore())
        // Intentionally do not assign apiClient.

        await manager.loadProfile()

        #expect(manager.userProfile == nil)
    }

    @Test("signOut clears userProfile")
    func signOutClearsProfile() async throws {
        let (manager, client) = makeManager()
        client.stub(.getMe, response: fixtureProfile)
        await manager.loadProfile()
        #expect(manager.userProfile == fixtureProfile)

        await manager.signOut()

        #expect(manager.userProfile == nil)
    }
}
