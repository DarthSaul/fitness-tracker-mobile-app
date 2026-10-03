import Foundation
import Testing
@testable import FitnessTracker

/// The two kinds of sign-out (API_CONTRACT_NOTIFICATIONS.md § Signing out):
/// a tapped Sign Out revokes the session and this phone's push token
/// server-side; a forced sign-out (dead refresh token) and the teardown after
/// account deletion only clear local state.
@Suite("SessionManager sign-out", .serialized)
@MainActor
struct SessionManagerSignOutTests {
    /// Its own Keychain namespace: other suites sign out in parallel and
    /// would otherwise delete this suite's refresh token mid-test.
    private let keychain = KeychainService(service: "me.fitness-app.tracker.tests.sign-out")

    private func makeManager(deviceToken: String? = "a1b2c3") async throws -> (SessionManager, MockAPIClient) {
        let manager = SessionManager(keychain: keychain, tokenStore: TokenStore())
        let client = MockAPIClient()
        manager.apiClient = client
        let defaults = try #require(UserDefaults(suiteName: "SessionManagerSignOutTests"))
        defaults.removePersistentDomain(forName: "SessionManagerSignOutTests")
        if let deviceToken {
            defaults.set(deviceToken, forKey: PushRegistrar.deviceTokenDefaultsKey)
        }
        manager.pushRegistrar = PushRegistrar(defaults: defaults, environment: .sandbox)
        try await keychain.save("refresh-123", for: .refreshToken)
        manager._setAuthStateForTesting(.authenticated(userId: "user-001"))
        return (manager, client)
    }

    private func logoutBodies(_ client: MockAPIClient) -> [LogoutBody] {
        client.sentEndpoints.compactMap {
            if case .logout(let body) = $0 { return body }
            return nil
        }
    }

    @Test("user sign-out sends the refresh and device tokens, then clears the Keychain")
    func userSignOutRevokes() async throws {
        let (manager, client) = try await makeManager()
        client.stubJSON(.logout(LogoutBody(refreshToken: "", deviceToken: nil)), #"{"success":true}"#)

        await manager.signOutByUser()

        #expect(logoutBodies(client) == [LogoutBody(refreshToken: "refresh-123", deviceToken: "a1b2c3")])
        #expect(manager.authState == .unauthenticated)
        await #expect(throws: KeychainError.self) { try await keychain.load(.refreshToken) }
    }

    @Test("user sign-out without an APNs token still revokes the refresh token")
    func userSignOutWithoutDeviceToken() async throws {
        let (manager, client) = try await makeManager(deviceToken: nil)
        client.stubJSON(.logout(LogoutBody(refreshToken: "", deviceToken: nil)), #"{"success":true}"#)

        await manager.signOutByUser()

        #expect(logoutBodies(client) == [LogoutBody(refreshToken: "refresh-123", deviceToken: nil)])
    }

    @Test("a failed logout request still signs out locally")
    func userSignOutOfflineStillSignsOut() async throws {
        let (manager, client) = try await makeManager()
        client.handlers["POST /api/auth/logout"] = { _ in throw APIError.network(URLError(.notConnectedToInternet)) }

        await manager.signOutByUser()

        #expect(manager.authState == .unauthenticated)
        await #expect(throws: KeychainError.self) { try await keychain.load(.refreshToken) }
    }

    @Test("forced sign-out calls no API and keeps the device registered")
    func forcedSignOutIsLocalOnly() async throws {
        let (manager, client) = try await makeManager()

        await manager.signOut()

        #expect(client.sentEndpoints.isEmpty)
        #expect(manager.authState == .unauthenticated)
        await #expect(throws: KeychainError.self) { try await keychain.load(.refreshToken) }
    }

    @Test("account deletion never calls logout")
    func deleteAccountSkipsLogout() async throws {
        let (manager, client) = try await makeManager()
        client.handlers["DELETE /api/auth/me"] = { _ in Data(#"{"success":true}"#.utf8) }

        try await manager.deleteAccount()

        #expect(logoutBodies(client).isEmpty)
        #expect(client.sentEndpoints.count == 1)
        #expect(manager.authState == .unauthenticated)
    }
}
