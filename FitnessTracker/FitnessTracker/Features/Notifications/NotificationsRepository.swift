import Foundation

/// The notifications API (API_CONTRACT_NOTIFICATIONS.md).
@MainActor
final class NotificationsRepository {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    /// Newest first. An **empty** page is the end of the list.
    func fetch(status: NotificationListFilter, page: PageQuery) async throws -> [NotificationItemDTO] {
        let response: NotificationsResponseDTO = try await apiClient.send(.getNotifications(status: status, page: page))
        return response.notifications
    }

    /// The same number the push sends as `badge`.
    func unreadCount() async throws -> Int {
        let response: CountResponseDTO = try await apiClient.send(.getUnreadNotificationCount)
        return response.count
    }

    func setStatus(id: String, _ status: NotificationStatus) async throws -> NotificationItemDTO {
        let response: NotificationResponseDTO = try await apiClient.send(
            .updateNotification(id: id, body: UpdateNotificationBody(status: status))
        )
        return response.notification
    }

    /// Marks everything up to `before` (the newest `createdAt` on screen,
    /// sent back exactly as received) as read.
    func markAllRead(before: String?) async throws {
        let _: CountResponseDTO = try await apiClient.send(.markAllNotificationsRead(MarkAllReadBody(before: before)))
    }

    func preferences() async throws -> NotificationPreferencesDTO {
        try await apiClient.send(.getNotificationPreferences)
    }

    func updatePreferences(_ body: UpdateNotificationPreferencesBody) async throws -> NotificationPreferencesDTO {
        try await apiClient.send(.updateNotificationPreferences(body))
    }
}
