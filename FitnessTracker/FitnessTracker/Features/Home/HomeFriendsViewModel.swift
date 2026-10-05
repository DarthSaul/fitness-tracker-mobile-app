import Foundation
import Observation
import OSLog

/// Home's FRIENDS section: the five most recent posts from people I follow,
/// newest first. My own posts are left out (the feed includes them).
@Observable
@MainActor
final class HomeFriendsViewModel {
    static let limit = 5

    private(set) var posts: [PostDTO] = []
    private(set) var hasLoaded = false
    private(set) var loadError: APIFailure?

    private let context: SocialContext

    init(context: SocialContext) {
        self.context = context
        context.events.subscribe(self) { [weak self] event in
            self?.apply(event)
        }
    }

    func load() async {
        loadError = nil
        do {
            // One feed page is enough to find five posts by others in all but
            // the most prolific-poster cases.
            let page = try await context.repository.fetchFeed(page: PageQuery(limit: 20, cursor: nil))
            posts = Self.friendsPosts(from: page)
            hasLoaded = true
        } catch {
            loadError = await context.failure(from: error)
            Logger.data.error("Home friends section failed: \(error)")
        }
    }

    static func friendsPosts(from feed: [PostDTO]) -> [PostDTO] {
        Array(feed.filter { !$0.isMine }.prefix(limit))
    }

    private func apply(_ event: SocialEvent) {
        switch event {
        case .postUpdated(let post):
            if let index = posts.firstIndex(where: { $0.id == post.id }) { posts[index] = post }
        case .postDeleted(let id):
            posts.removeAll { $0.id == id }
        case .userBlocked(let userId):
            posts.removeAll { $0.author.id == userId }
        case .followsChanged:
            // Following or unfollowing changes whose posts belong here.
            Task { await load() }
        case .postCreated:
            break
        }
    }
}

/// The one-line summary for a Home row. ADR 001: a shared workout carries
/// only the program's name, so the summary never includes week or day.
nonisolated enum HomeFriendSummary {
    static func text(for post: PostDTO) -> String {
        if let workout = post.workout {
            if let program = workout.programName, !program.isEmpty {
                return "finished a workout from \(program)"
            }
            return "finished a workout"
        }
        if !post.photos.isEmpty {
            return post.photos.count == 1 ? "posted a photo" : "posted \(post.photos.count) photos"
        }
        return "posted an update"
    }
}
