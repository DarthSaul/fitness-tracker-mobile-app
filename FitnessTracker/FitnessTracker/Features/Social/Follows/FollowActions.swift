import Foundation
import OSLog

/// What the follow button shows, from `outgoing` and the target's privacy
/// (API_CONTRACT_SOCIAL.md § Following):
///
/// | outgoing | profile | button |
/// |---|---|---|
/// | none | PUBLIC | Follow |
/// | none | PRIVATE | Request |
/// | requested | — | Requested (tap cancels) |
/// | following | — | Following (tap unfollows, after confirming) |
nonisolated enum FollowButtonState: Equatable {
    case follow
    case request
    case requested
    case following

    init(visibility: ProfileVisibility, outgoing: FollowState) {
        switch outgoing {
        case .following: self = .following
        case .requested: self = .requested
        case .none: self = visibility == .public ? .follow : .request
        }
    }

    var title: String {
        switch self {
        case .follow: "Follow"
        case .request: "Request"
        case .requested: "Requested"
        case .following: "Following"
        }
    }

    /// The optimistic `outgoing` after tapping Follow/Request: instant for a
    /// public profile, a pending request for a private one.
    static func optimisticOutgoingAfterFollowing(visibility: ProfileVisibility) -> FollowState {
        visibility == .public ? .following : .requested
    }
}

/// Follow, unfollow and request actions with optimistic results. Each
/// returns the relationship to show, or nil when it failed (after a toast),
/// in which case the caller rolls back to what it had.
@MainActor
final class FollowActions {
    private let context: SocialContext

    init(context: SocialContext) {
        self.context = context
    }

    /// Follow (public) or request (private). `200` and `201` are both success.
    func follow(_ user: PublicUserDTO) async -> FollowState? {
        do {
            let response = try await context.repository.follow(userId: user.id)
            context.events.send(.followsChanged)
            return response.status
        } catch {
            await report(error, action: "follow \(user.displayName)")
            return nil
        }
    }

    /// Unfollow, or cancel a pending request. `204` even when not following.
    func unfollow(_ user: PublicUserDTO) async -> FollowState? {
        do {
            try await context.repository.unfollow(userId: user.id)
            context.events.send(.followsChanged)
            return FollowState.none
        } catch {
            await report(error, action: "update your follow")
            return nil
        }
    }

    /// Accept their request. A `404` means it was already handled
    /// (accepted, cancelled or declined elsewhere): treat it as done.
    func accept(requestId: String) async -> Bool {
        do {
            try await context.repository.acceptFollowRequest(id: requestId)
        } catch {
            guard let failure = await context.failure(from: error) else { return false }
            if failure != .notFound {
                context.toasts.show("Couldn't approve the request. \(failure.message)")
                return false
            }
        }
        context.events.send(.followsChanged)
        return true
    }

    /// Decline their request (silently; they aren't notified).
    func decline(requestId: String) async -> Bool {
        do {
            try await context.repository.deleteFollowRequest(id: requestId)
        } catch {
            guard let failure = await context.failure(from: error) else { return false }
            if failure != .notFound {
                context.toasts.show("Couldn't decline the request. \(failure.message)")
                return false
            }
        }
        context.events.send(.followsChanged)
        return true
    }

    private func report(_ error: any Error, action: String) async {
        guard let failure = await context.failure(from: error) else { return }
        Logger.data.error("Follow action failed: \(error)")
        switch failure {
        case .rateLimited:
            context.toasts.show(failure.message)
        case .notFound:
            context.toasts.show("This account is no longer available.")
        default:
            context.toasts.show("Couldn't \(action). Try again.")
        }
    }
}
