import Foundation
import OSLog

/// Post actions shared by every screen that shows posts: optimistic reaction
/// toggles and deleting my own post. Changes are broadcast through
/// `SocialEvents`, so the feed, a profile and the single-post screen all
/// stay in step.
@MainActor
final class PostActions {
    /// Unowned: the context owns this object.
    private unowned let context: SocialContext
    /// "postId|emoji" pairs with a request on the wire. A second tap on the
    /// same chip waits for the first, so a rollback can't undo a newer toggle.
    private var inFlight: Set<String> = []

    init(context: SocialContext) {
        self.context = context
    }

    /// Toggles my `emoji` on `post`: updates every list immediately, then
    /// reconciles with the server's summary, or rolls back with a toast.
    func toggleReaction(_ emoji: String, on post: PostDTO) async {
        let key = "\(post.id)|\(emoji)"
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        let wasMine = Reactions.isMine(emoji, in: post.reactions)
        var optimistic = post
        optimistic.reactions = Reactions.toggling(emoji, in: post.reactions)
        context.events.send(.postUpdated(optimistic))

        do {
            if wasMine {
                try await context.repository.removeReaction(postId: post.id, emoji: emoji)
            } else {
                var reconciled = optimistic
                reconciled.reactions = try await context.repository.addReaction(postId: post.id, emoji: emoji)
                context.events.send(.postUpdated(reconciled))
            }
        } catch {
            guard let failure = await context.failure(from: error) else { return }
            Logger.data.error("Reaction toggle failed: \(error)")
            if failure == .notFound {
                // Deleted, or hidden by a block: it's gone everywhere.
                context.events.send(.postDeleted(id: post.id))
                context.toasts.show("This post is no longer available.")
            } else {
                context.events.send(.postUpdated(post))
                context.toasts.show(failure == .rateLimited ? failure.message : "Couldn't update your reaction.")
            }
        }
    }

    /// Deletes my post. Returns whether it's gone (`404` counts as gone).
    @discardableResult
    func delete(_ post: PostDTO) async -> Bool {
        do {
            try await context.repository.deletePost(id: post.id)
        } catch {
            guard let failure = await context.failure(from: error) else { return false }
            if failure != .notFound {
                context.toasts.show("Couldn't delete the post. \(failure.message)")
                return false
            }
        }
        context.events.send(.postDeleted(id: post.id))
        return true
    }
}
