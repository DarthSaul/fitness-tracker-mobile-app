import UIKit
import OSLog

/// UIKit hooks SwiftUI doesn't expose: the APNs device-token callbacks.
/// Attached via `@UIApplicationDelegateAdaptor` in `FitnessTrackerApp`.
///
/// Remote-notification registration runs on every launch (the token can
/// change, and registration is how the server learns it's still live). It
/// doesn't need the user's alert permission; that's requested separately
/// once they're signed in.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set by `FitnessTrackerApp` once its services exist. A token that
    /// arrives first is buffered and handed over when this is set.
    var pushRegistrar: PushRegistrar? {
        didSet { flushPendingToken() }
    }

    private var pendingToken: Data?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        pendingToken = deviceToken
        flushPendingToken()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        pushRegistrar?.didFailToRegister(error: error)
    }

    private func flushPendingToken() {
        guard let pushRegistrar, let token = pendingToken else { return }
        pendingToken = nil
        Task { await pushRegistrar.didRegister(deviceToken: token) }
    }
}
