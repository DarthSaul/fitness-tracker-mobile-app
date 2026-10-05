import Foundation
@testable import FitnessTracker

/// A `SocialContext` on a `MockAPIClient`, signed in as `user-me`.
@MainActor
struct SocialTestHarness {
    let client = MockAPIClient()
    let sessionManager: SessionManager
    let context: SocialContext

    init(userId: String = "user-me") {
        sessionManager = SessionManager(
            keychain: KeychainService(service: "me.fitness-app.tracker.tests.social"),
            tokenStore: TokenStore()
        )
        sessionManager._setAuthStateForTesting(.authenticated(userId: userId))
        sessionManager.apiClient = client
        context = SocialContext(repository: SocialRepository(apiClient: client), sessionManager: sessionManager)
    }

    /// Endpoints of one kind that were sent, e.g. `sent { if case .follow(let b) = $0 { b } else { nil } }`.
    func sent<T>(_ extract: (APIEndpoint) -> T?) -> [T] {
        client.sentEndpoints.compactMap(extract)
    }

    /// Collects every event broadcast on the context.
    final class EventLog {
        var events: [SocialEvent] = []
    }

    func recordEvents() -> EventLog {
        let log = EventLog()
        context.events.subscribe(log) { log.events.append($0) }
        return log
    }
}

enum SocialFactory {
    static func user(
        _ id: String = "user-ann",
        name: String? = "Ann Lee",
        username: String = "ann",
        visibility: ProfileVisibility = .public
    ) -> PublicUserDTO {
        PublicUserDTO(id: id, name: name, avatarUrl: nil, profileVisibility: visibility, username: username)
    }

    static func post(
        _ id: String = "post-1",
        author: PublicUserDTO = user(),
        createdAt: String = "2026-10-02T12:00:00.000Z",
        isMine: Bool = false,
        reactions: [ReactionSummaryDTO] = [],
        photosExpireAt: Date? = nil
    ) -> PostDTO {
        PostDTO(
            id: id,
            author: author,
            body: "Hello",
            createdAt: WireTimestamp(raw: createdAt, date: JSONCoding.parseISO8601(createdAt) ?? .now),
            editedAt: nil,
            isMine: isMine,
            photos: [],
            photosExpireAt: photosExpireAt,
            reactions: reactions,
            workout: nil
        )
    }

    static func request(
        _ id: String = "req-1",
        user: PublicUserDTO = user(),
        direction: FollowRequestDirection = .incoming
    ) -> FollowRequestDTO {
        FollowRequestDTO(id: id, user: user, direction: direction, createdAt: .now)
    }

    static func notification(
        _ id: String,
        type: NotificationType,
        status: NotificationStatus = .unread,
        createdAt: String = "2026-10-02T12:00:00.000Z",
        actor: PublicUserDTO? = user(),
        target: NotificationTargetDTO = .empty,
        data: NotificationDataDTO = NotificationDataDTO()
    ) -> NotificationItemDTO {
        NotificationItemDTO(
            id: id,
            type: type,
            status: status,
            createdAt: WireTimestamp(raw: createdAt, date: JSONCoding.parseISO8601(createdAt) ?? .now),
            actor: actor,
            target: target,
            data: data
        )
    }
}
