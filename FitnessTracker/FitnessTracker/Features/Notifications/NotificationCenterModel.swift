import Foundation
import Observation
import OSLog
import UserNotifications

/// Session-wide notification state:
/// - the unread count behind the bell badge and the app icon badge;
/// - the timezone, sent after every sign-in and whenever it changes
///   (without one, no workout reminder ever fires);
/// - routing a tapped push to its target, then marking it read.
@Observable
@MainActor
final class NotificationCenterModel {
    private(set) var unreadCount = 0

    let repository: NotificationsRepository
    private let sessionManager: SessionManager
    private let badgeSetter: @MainActor (Int) -> Void
    private var lastSentTimezone: String?

    init(
        repository: NotificationsRepository,
        sessionManager: SessionManager,
        badgeSetter: @escaping @MainActor (Int) -> Void = { count in
            UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
        }
    ) {
        self.repository = repository
        self.sessionManager = sessionManager
        self.badgeSetter = badgeSetter
    }

    // MARK: - Unread count

    func refreshUnreadCount() async {
        do {
            setUnread(try await repository.unreadCount())
        } catch {
            if APIFailure(error) == .unauthorized { await sessionManager.signOut() }
            Logger.app.error("Unread count failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Applies a known count locally (after marking items read) without
    /// another round trip.
    func setUnread(_ count: Int) {
        unreadCount = max(0, count)
        badgeSetter(unreadCount)
    }

    // MARK: - Timezone

    /// Sends `TimeZone.current.identifier` (an IANA name, never an offset)
    /// if it differs from what this session last sent.
    func syncTimezone(_ timezone: TimeZone = .current) async {
        let identifier = timezone.identifier
        guard identifier != lastSentTimezone else { return }
        do {
            _ = try await repository.updatePreferences(UpdateNotificationPreferencesBody(timezone: identifier))
            lastSentTimezone = identifier
        } catch {
            if APIFailure(error) == .unauthorized { await sessionManager.signOut() }
            Logger.app.error("Timezone sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
