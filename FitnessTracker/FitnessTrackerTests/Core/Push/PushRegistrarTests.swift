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

    // MARK: - Sign-out suspension

    private let registerEndpoint = APIEndpoint.registerDevice(DeviceRegistrationBody(token: "", platform: "", environment: ""))

    @Test("sign-out waits for an in-flight registration, then blocks new ones")
    func suspendWaitsForInFlightAndBlocks() async throws {
        let (registrar, manager, client) = try makeRegistrar(authenticatedAs: nil)
        await registrar.didRegister(deviceToken: Data([0x01]))
        manager._setAuthStateForTesting(.authenticated(userId: "user-001"))

        client.holdNextResponse(for: registerEndpoint)
        let registration = Task { await registrar.registerIfPossible() }
        for _ in 0..<200 where !client.isHolding(registerEndpoint) { await Task.yield() }
        #expect(client.isHolding(registerEndpoint))

        var suspended = false
        let suspension = Task {
            await registrar.suspendRegistration()
            suspended = true
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(!suspended, "sign-out must not proceed while a registration is on the wire")

        client.release(registerEndpoint)
        await registration.value
        await suspension.value
        #expect(suspended)

        // A new registration (e.g. a fresh token) can't start mid sign-out.
        await registrar.didRegister(deviceToken: Data([0x02]))
        #expect(registrations(client).count == 1)

        // The local teardown lifts the suspension for the next session.
        registrar.resetRegistration()
        await registrar.registerIfPossible()
        #expect(registrations(client).count == 2)
    }

    // MARK: - Environment

    private func profile(apsEnvironment: String?) -> Data {
        let entitlement = apsEnvironment.map { "<key>aps-environment</key><string>\($0)</string>" } ?? ""
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>Entitlements</key><dict>\(entitlement)</dict></dict></plist>
        """
        // Real profiles wrap the plist in CMS signature bytes.
        return Data([0x30, 0x80, 0x06, 0x09]) + Data(plist.utf8) + Data([0x00, 0xA0, 0x82])
    }

    @Test("the environment follows the signed aps-environment, not the build configuration")
    func environmentFromSignedProfile() {
        #expect(PushEnvironment.resolve(isSimulator: false, provisioningProfile: profile(apsEnvironment: "development")) == .sandbox)
        #expect(PushEnvironment.resolve(isSimulator: false, provisioningProfile: profile(apsEnvironment: "production")) == .production)
        // App Store / TestFlight builds carry no embedded profile.
        #expect(PushEnvironment.resolve(isSimulator: false, provisioningProfile: nil) == .production)
        #expect(PushEnvironment.resolve(isSimulator: true, provisioningProfile: nil) == .sandbox)
    }

    @Test("aps-environment is read out of the signed profile blob")
    func parsesProfile() {
        #expect(PushEnvironment.apsEnvironment(inProvisioningProfile: profile(apsEnvironment: "production")) == "production")
        #expect(PushEnvironment.apsEnvironment(inProvisioningProfile: profile(apsEnvironment: nil)) == nil)
        #expect(PushEnvironment.apsEnvironment(inProvisioningProfile: Data("garbage".utf8)) == nil)
    }
}
