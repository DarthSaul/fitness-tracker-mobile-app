import Foundation
import Observation
import OSLog
import UserNotifications

/// The APNs environment a build's device tokens belong to. A token registered
/// under the wrong one is rejected by APNs and revoked server-side, so this is
/// fixed at build time: Debug builds run against the sandbox; Release builds
/// (TestFlight, App Store) against production.
nonisolated enum PushEnvironment: String, Sendable {
    case sandbox = "SANDBOX"
    case production = "PRODUCTION"

    static let current: PushEnvironment = {
        #if DEBUG
        return .sandbox
        #else
        return .production
        #endif
    }()
}

/// Owns this device's APNs token and keeps the server's registration current.
///
/// `POST /api/devices/register` is idempotent and is called on **every**
/// launch once APNs hands over a token and a user is signed in (whichever
/// comes second), and again after each sign-in — signing in as someone else
/// moves the token to that user.
///
/// The token is also persisted so a user-initiated sign-out can send it to
/// `POST /api/auth/logout` even if this launch's APNs callback hasn't fired.
@Observable
@MainActor
final class PushRegistrar {
    static let deviceTokenDefaultsKey = "apnsDeviceTokenHex"

    /// Lowercase hex APNs token, or nil before APNs has issued one.
    private(set) var deviceToken: String?

    private let defaults: UserDefaults
    private let environment: PushEnvironment
    private weak var sessionManager: SessionManager?
    private var apiClient: (any APIClientProtocol)?
    /// "userId|token" last registered this launch, so the same pair isn't
    /// re-posted every time a tab reappears.
    private var registeredKey: String?

    init(defaults: UserDefaults = .standard, environment: PushEnvironment = .current) {
        self.defaults = defaults
        self.environment = environment
        self.deviceToken = defaults.string(forKey: Self.deviceTokenDefaultsKey)
    }

    func configure(sessionManager: SessionManager, apiClient: any APIClientProtocol) {
        self.sessionManager = sessionManager
        self.apiClient = apiClient
    }

    // MARK: - APNs callbacks

    func didRegister(deviceToken data: Data) async {
        let hex = Self.hexString(from: data)
        deviceToken = hex
        defaults.set(hex, forKey: Self.deviceTokenDefaultsKey)
        await registerIfPossible()
    }

    func didFailToRegister(error: any Error) {
        Logger.app.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - Permission

    /// Asks for alert/badge/sound permission the first time a signed-in user
    /// reaches the app. iOS shows the prompt only once; later calls are no-ops.
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            Logger.app.error("Notification permission request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Server registration

    /// Registers the current token for the signed-in user, unless that exact
    /// pair was already registered this launch. Failures are logged and left
    /// for the next launch: registration is best-effort.
    func registerIfPossible() async {
        guard let deviceToken, let apiClient,
              case .authenticated(let userId) = sessionManager?.authState
        else { return }
        let key = "\(userId)|\(deviceToken)"
        guard key != registeredKey else { return }

        let body = DeviceRegistrationBody(
            token: deviceToken,
            platform: "IOS",
            environment: environment.rawValue
        )
        do {
            try await apiClient.send(.registerDevice(body))
            registeredKey = key
            Logger.app.info("Registered device for push (\(self.environment.rawValue, privacy: .public)).")
        } catch {
            Logger.app.error("Device registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Forget which user the token was registered for, so the next sign-in
    /// registers again (moving the token to that user).
    func resetRegistration() {
        registeredKey = nil
    }

    // MARK: - Helpers

    nonisolated static func hexString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
