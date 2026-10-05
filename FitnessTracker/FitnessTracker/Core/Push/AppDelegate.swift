import UIKit
import OSLog
import UserNotifications

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

    /// Receives tapped pushes. Set by `FitnessTrackerApp`; created here so a
    /// cold-launch tap (delivered right after launch) is never lost.
    let pushRouter = PushRouter()

    private var pendingToken: Data?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Must be set before launch finishes to receive the tap that
        // launched the app.
        UNUserNotificationCenter.current().delegate = self
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

// MARK: - Notification taps

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// A push tapped from the lock screen or Notification Center.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let payload = PushPayload(userInfo: userInfo) else { return }
        await MainActor.run { pushRouter.receive(payload) }
    }

    /// A push arriving while the app is open: show it as a banner and
    /// refresh the unread count.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run { pushRouter.receivedInForeground() }
        return [.banner, .list, .sound, .badge]
    }
}
