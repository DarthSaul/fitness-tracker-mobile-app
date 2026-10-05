import Foundation
import OSLog

enum SafetyCopy {
    static let blockMessage =
        "They won't be able to find you or see your posts, and you won't see theirs. "
        + "Blocking also removes any follows between you, in both directions — unblocking won't restore them."
    static let reportThanks = "Thanks — we'll review this."
}

/// What's being reported: a post or a person (never both).
enum ReportTarget: Identifiable {
    case post(PostDTO)
    case user(PublicUserDTO)

    var id: String {
        switch self {
        case .post(let post): "post|\(post.id)"
        case .user(let user): "user|\(user.id)"
        }
    }

    /// The person to offer blocking afterwards.
    var user: PublicUserDTO {
        switch self {
        case .post(let post): post.author
        case .user(let user): user
        }
    }

    func body(reason: ReportReason, details: String?) -> ReportBody {
        switch self {
        case .post(let post): .post(post.id, reason: reason, details: details)
        case .user(let user): .user(user.id, reason: reason, details: details)
        }
    }
}

/// Block and unblock, broadcasting a block so every list drops the user's
/// content at once.
@MainActor
final class SafetyActions {
    private let context: SocialContext

    init(context: SocialContext) {
        self.context = context
    }

    /// `201` new or `200` already blocked: both success.
    @discardableResult
    func block(_ user: PublicUserDTO) async -> Bool {
        do {
            try await context.repository.block(userId: user.id)
        } catch {
            guard let failure = await context.failure(from: error) else { return false }
            Logger.data.error("Block failed: \(error)")
            context.toasts.show("Couldn't block \(user.displayName). \(failure.message)")
            return false
        }
        context.events.send(.userBlocked(userId: user.id))
        context.events.send(.followsChanged)
        context.toasts.show("Blocked \(user.displayName).")
        return true
    }

    @discardableResult
    func unblock(_ user: PublicUserDTO) async -> Bool {
        do {
            try await context.repository.unblock(userId: user.id)
            return true
        } catch {
            guard let failure = await context.failure(from: error) else { return false }
            context.toasts.show("Couldn't unblock \(user.displayName). \(failure.message)")
            return false
        }
    }
}
