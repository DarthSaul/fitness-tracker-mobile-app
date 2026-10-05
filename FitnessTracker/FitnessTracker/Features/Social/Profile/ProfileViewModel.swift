import Foundation
import Observation
import OSLog

/// A user's profile (design-spec 09 / 10), including "My profile" (the
/// caller's own id). Posts load only when they'd be visible: a `PRIVATE`
/// profile I don't follow shows the lock card without calling the posts
/// route (which would `403 profile_private`).
@Observable
@MainActor
final class ProfileViewModel {
    let userId: String
    private(set) var profile: UserProfileDTO?
    private(set) var isLoading = false
    /// The profile is gone: unknown, deleted, or hidden by a block
    /// (indistinguishable by design).
    private(set) var isGone = false
    private(set) var loadError: APIFailure?
    private(set) var posts: KeysetPaginator<PostDTO>
    private(set) var isRespondingToRequest = false
    /// Set when this user is blocked from here; the screen pops.
    private(set) var didBlock = false

    private let context: SocialContext

    init(userId: String, context: SocialContext) {
        self.userId = userId
        self.context = context
        self.posts = Self.makePaginator(userId: userId, context: context)
        context.events.subscribe(self) { [weak self] event in
            self?.apply(event)
        }
    }

    private static func makePaginator(userId: String, context: SocialContext) -> KeysetPaginator<PostDTO> {
        KeysetPaginator(
            pageSize: 20,
            endRule: .shortPage,
            cursor: \.cursor,
            onUnauthorized: { await context.handleUnauthorized() },
            fetch: { try await context.repository.fetchUserPosts(userId: userId, page: $0) }
        )
    }

    var isSelf: Bool { profile?.relationship.isSelf ?? (userId == context.currentUserId) }

    var postsAreLocked: Bool { profile?.postsAreLocked ?? false }

    // MARK: - Loading

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let loaded = try await context.repository.fetchProfile(userId: userId)
            profile = loaded
            isGone = false
            if loaded.postsAreLocked {
                posts.reset()
            } else {
                await posts.refresh()
                if posts.loadError.map(APIFailure.init) == .profilePrivate {
                    // The rule changed between the two calls (they went
                    // private, or removed me): show the lock.
                    await reloadProfileOnly()
                }
            }
        } catch {
            guard let failure = await context.failure(from: error) else { return }
            if failure == .notFound {
                isGone = true
                profile = nil
            } else {
                loadError = failure
            }
        }
    }

    private func reloadProfileOnly() async {
        if let loaded = try? await context.repository.fetchProfile(userId: userId) {
            profile = loaded
            if loaded.postsAreLocked { posts.reset() }
        }
    }

    // MARK: - Follow state

    /// Bound to the FollowButton. Following a public profile (or being
    /// approved later) opens the posts; unfollowing a private one locks them.
    var outgoing: FollowState {
        get { profile?.relationship.outgoing ?? .none }
        set {
            guard var updated = profile else { return }
            let old = updated.relationship.outgoing
            updated.relationship.outgoing = newValue
            if old != .following, newValue == .following { updated.followerCount += 1 }
            if old == .following, newValue != .following { updated.followerCount = max(0, updated.followerCount - 1) }
            profile = updated
            if updated.postsAreLocked {
                posts.reset()
            } else if !posts.hasLoaded {
                Task { await posts.refresh() }
            }
        }
    }

    /// Accept or decline their pending request to me.
    func respondToRequest(accept: Bool) async {
        guard let requestId = profile?.relationship.incomingRequestId else { return }
        isRespondingToRequest = true
        defer { isRespondingToRequest = false }
        let actions = FollowActions(context: context)
        let succeeded = accept
            ? await actions.accept(requestId: requestId)
            : await actions.decline(requestId: requestId)
        guard succeeded, var updated = profile else { return }
        updated.relationship.incomingRequestId = nil
        updated.relationship.incoming = accept ? .following : .none
        profile = updated
    }

    // MARK: - Events

    private func apply(_ event: SocialEvent) {
        switch event {
        case .postCreated(let post) where post.author.id == userId:
            posts.insertAtTop(post)
        case .postUpdated(let post):
            posts.replace(post)
        case .postDeleted(let id):
            posts.remove(id: id)
        case .userBlocked(let blockedId) where blockedId == userId:
            didBlock = true
        default:
            break
        }
    }
}
