import Foundation
import Observation
import OSLog
import UserNotifications

/// The APNs environment a build's device tokens belong to. A token registered
/// under the wrong one is rejected by APNs and revoked server-side, so this
/// follows the `aps-environment` the build was actually **signed** with, not
/// the build configuration: a Release build installed from Xcode is signed
/// for development and gets sandbox tokens.
nonisolated enum PushEnvironment: String, Sendable {
    case sandbox = "SANDBOX"
    case production = "PRODUCTION"

    static let current: PushEnvironment = {
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        let profile = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
            .flatMap { try? Data(contentsOf: $0) }
        return resolve(isSimulator: isSimulator, provisioningProfile: profile)
    }()

    /// - Simulator: sandbox (APNs simulator tokens are sandbox tokens).
    /// - No embedded provisioning profile: App Store / TestFlight distribution,
    ///   which Apple re-signs for production.
    /// - Otherwise the profile's `aps-environment` entitlement: `production`
    ///   (ad hoc / enterprise) or `development`.
    static func resolve(isSimulator: Bool, provisioningProfile: Data?) -> PushEnvironment {
        if isSimulator { return .sandbox }
        guard let provisioningProfile else { return .production }
        return apsEnvironment(inProvisioningProfile: provisioningProfile) == "production" ? .production : .sandbox
    }

    /// The `Entitlements.aps-environment` value from an
    /// `embedded.mobileprovision`. The file is a CMS-signed blob with the
    /// property list embedded as plain XML, so the plist is sliced out
    /// rather than verifying the signature (iOS already did, at install).
    static func apsEnvironment(inProvisioningProfile data: Data) -> String? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any]
        else { return nil }
        return entitlements["aps-environment"] as? String
    }
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
    /// Set while a user-initiated sign-out is in progress: no registration
    /// may start, so logout is the last server call for that user.
    private var isSuspended = false
    /// The registration request currently on the wire, if any. Sign-out waits
    /// for it so it can't land after logout and re-activate the token.
    private var inFlight: Task<Void, Never>?

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
        // One registration at a time: wait out any in flight, then re-check
        // (it may have registered this exact pair, or a sign-out may have begun).
        if let inFlight {
            await inFlight.value
            return await registerIfPossible()
        }
        guard !isSuspended, let deviceToken, let apiClient,
              case .authenticated(let userId) = sessionManager?.authState
        else { return }
        let key = "\(userId)|\(deviceToken)"
        guard key != registeredKey else { return }

        let body = DeviceRegistrationBody(
            token: deviceToken,
            platform: "IOS",
            environment: environment.rawValue
        )
        let task = Task {
            do {
                try await apiClient.send(.registerDevice(body))
                registeredKey = key
                Logger.app.info("Registered device for push (\(self.environment.rawValue, privacy: .public)).")
            } catch {
                Logger.app.error("Device registration failed: \(error.localizedDescription, privacy: .public)")
            }
            // Cleared by the task itself (both run on the main actor, and
            // this can't run before `inFlight = task` below), so anyone
            // awaiting it never wakes to a stale, finished task.
            inFlight = nil
        }
        inFlight = task
        await task.value
    }

    /// Called as a user-initiated sign-out begins, before logout is sent.
    /// Blocks new registrations and waits for one already on the wire, so
    /// logout's device revocation is the final server operation for this
    /// user. `resetRegistration()` (run by the local teardown) lifts it.
    func suspendRegistration() async {
        isSuspended = true
        await inFlight?.value
    }

    /// Forget which user the token was registered for, so the next sign-in
    /// registers again (moving the token to that user), and lift any
    /// sign-out suspension.
    func resetRegistration() {
        registeredKey = nil
        isSuspended = false
    }

    // MARK: - Helpers

    nonisolated static func hexString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
