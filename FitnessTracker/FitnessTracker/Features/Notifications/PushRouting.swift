import Foundation
import Observation

/// The app-specific part of an APNs payload:
/// `{ aps, notificationId, type, target }`.
nonisolated struct PushPayload: Equatable, Sendable {
    let notificationId: String
    let type: NotificationType
    let target: NotificationTargetDTO

    /// Parses `userInfo`; nil when it isn't one of ours.
    init?(userInfo: [AnyHashable: Any]) {
        guard let notificationId = userInfo["notificationId"] as? String,
              let rawType = userInfo["type"] as? String
        else { return nil }
        self.notificationId = notificationId
        self.type = NotificationType(rawValue: rawType)
        let target = userInfo["target"] as? [String: Any] ?? [:]
        self.target = NotificationTargetDTO(
            postId: target["postId"] as? String,
            followId: target["followId"] as? String,
            workoutSessionId: target["workoutSessionId"] as? String,
            standaloneSessionId: target["standaloneSessionId"] as? String,
            scheduledWorkoutId: target["scheduledWorkoutId"] as? String
        )
    }

    init(notificationId: String, type: NotificationType, target: NotificationTargetDTO) {
        self.notificationId = notificationId
        self.type = type
        self.target = target
    }
}

/// Where a notification (push or inbox row) leads.
nonisolated enum NotificationDestination: Equatable {
    /// A path in the Friends tab.
    case friends([FriendsRoute])
    /// Workout reminders: Home shows the scheduled workout and the resume
    /// banner for an unfinished one.
    case home

    /// `actorId` comes from the inbox row (pushes don't carry it).
    static func `for`(type: NotificationType, target: NotificationTargetDTO, actorId: String?) -> NotificationDestination {
        switch type {
        case .postReaction:
            if let postId = target.postId { return .friends([.post(id: postId)]) }
            return .friends([.activity])
        case .followRequest:
            return .friends([.requests])
        case .newFollower, .followAccepted:
            if let actorId { return .friends([.profile(userId: actorId)]) }
            return .friends([.activity])
        case .workoutReminder, .workoutUnfinished:
            return .home
        case .unknown:
            return .friends([.activity])
        }
    }
}

/// Holds a tapped push until the signed-in UI can act on it. A tap while
/// signed out waits here through sign-in.
@Observable
@MainActor
final class PushRouter {
    private(set) var pending: PushPayload?
    /// Bumped when a push arrives while the app is open, so the signed-in
    /// UI refreshes the unread count.
    private(set) var foregroundRevision = 0

    func receive(_ payload: PushPayload) {
        pending = payload
    }

    func receivedInForeground() {
        foregroundRevision += 1
    }

    /// Takes the pending payload (once).
    func take() -> PushPayload? {
        defer { pending = nil }
        return pending
    }
}
