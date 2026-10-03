import Foundation
import Testing
@testable import FitnessTracker

@Suite("PushRegistrar device registration")
@MainActor
struct PushRegistrarTests {
    private func makeDefaults(_ name: String = #function) throws -> UserDefaults {
        let suite = "PushRegistrarTests.\(name)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func registrations(_ client: MockAPIClient) -> [DeviceRegistrationBody] {
        client.sentEndpoints.compactMap {
            if case .registerDevice(let body) = $0 { return body }
            return nil
        }
    }

    private func makeRegistrar(
        environment: PushEnvironment = .sandbox,
        authenticatedAs userId: String? = "user-001"
    ) throws -> (PushRegistrar, SessionManager, MockAPIClient) {
        let registrar = PushRegistrar(defaults: try makeDefaults(), environment: environment)
        let manager = SessionManager(keychain: KeychainService(), tokenStore: TokenStore())
        let client = MockAPIClient()
        client.stubJSON(.registerDevice(DeviceRegistrationBody(token: "", platform: "", environment: "")), #"{"id":"d1"}"#)
        if let userId { manager._setAuthStateForTesting(.authenticated(userId: userId)) }
        registrar.configure(sessionManager: manager, apiClient: client)
        return (registrar, manager, client)
    }

    @Test("the APNs token is sent as lowercase hex with IOS and the build's environment")
    func registersHexToken() async throws {
        let (registrar, _, client) = try makeRegistrar(environment: .production)

        await registrar.didRegister(deviceToken: Data([0xAB, 0x01, 0xFF]))

        let sent = registrations(client)
        #expect(sent.count == 1)
        #expect(sent.first?.token == "ab01ff")
        #expect(sent.first?.platform == "IOS")
        #expect(sent.first?.environment == "PRODUCTION")
    }

    @Test("a token that arrives before sign-in registers once the session is up")
    func waitsForSession() async throws {
        let (registrar, manager, client) = try makeRegistrar(authenticatedAs: nil)
        await registrar.didRegister(deviceToken: Data([0x01]))
        #expect(registrations(client).isEmpty)

        manager._setAuthStateForTesting(.authenticated(userId: "user-001"))
        await registrar.registerIfPossible()
        #expect(registrations(client).count == 1)
    }

    @Test("the same user + token isn't re-posted within a launch, but is after a sign-out")
    func dedupesUntilReset() async throws {
        let (registrar, _, client) = try makeRegistrar()
        await registrar.didRegister(deviceToken: Data([0x01]))
        await registrar.registerIfPossible()
        #expect(registrations(client).count == 1)

        registrar.resetRegistration()
        await registrar.registerIfPossible()
        #expect(registrations(client).count == 2)
    }

    @Test("Debug builds register in the sandbox")
    func debugIsSandbox() {
        #if DEBUG
        #expect(PushEnvironment.current == .sandbox)
        #else
        #expect(PushEnvironment.current == .production)
        #endif
    }
}
