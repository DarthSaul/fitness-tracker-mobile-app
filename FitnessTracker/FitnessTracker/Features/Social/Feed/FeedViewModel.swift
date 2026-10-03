import Foundation
import Observation
import OSLog

/// Drives the Friends feed (design-spec 01): the following feed, the
/// incoming follow-request shortcut row, and keeping both in step with
/// changes made elsewhere (`SocialEvents`).
///
/// Photo URLs are signed for 15 minutes, so a feed holding expired URLs is
/// refetched when the screen comes back (`refreshIfPhotosExpired`) rather
/// than showing broken images.
@Observable
@MainActor
final class FeedViewModel {
    let feed: KeysetPaginator<PostDTO>
    /// Pending requests to me, newest first, for the shortcut row.
    private(set) var incomingRequests: [FollowRequestDTO] = []

    private let context: SocialContext

    init(context: SocialContext, pageSize: Int = 20) {
        self.context = context
        self.feed = KeysetPaginator(
            pageSize: pageSize,
            endRule: .shortPage,
            cursor: \.cursor,
            onUnauthorized: { await context.handleUnauthorized() },
            fetch: { try await context.repository.fetchFeed(page: $0) }
        )
        context.events.subscribe(self) { [weak self] event in
            self?.apply(event)
        }
    }

    // MARK: - Loading

    func loadIfNeeded() async {
        async let posts: Void = feed.loadIfNeeded()
        async let requests: Void = loadRequests()
        _ = await (posts, requests)
    }

    func refresh() async {
        async let posts: Void = feed.refresh()
        async let requests: Void = loadRequests()
        _ = await (posts, requests)
    }

    func loadRequests() async {
        do {
            incomingRequests = try await context.repository.fetchFollowRequests(direction: .incoming)
        } catch {
            _ = await context.failure(from: error)
            // The row is a shortcut (Activity always reaches requests), so a
            // failure just leaves it as it was.
            Logger.data.error("Incoming requests failed: \(error)")
        }
    }

    /// Refetches from the top when any loaded post's photo URLs have expired.
    func refreshIfPhotosExpired(now: Date = .now) async {
        guard feed.items.contains(where: { $0.photosExpired(at: now) }) else { return }
        await feed.refresh()
    }

    // MARK: - Derived

    /// The empty state (design-spec 11): loaded, and nothing to show.
    var isEmpty: Bool {
        feed.hasLoaded && feed.items.isEmpty && feed.loadError == nil
    }

    /// "Theo, Ana and 1 other".
    var requestsSummary: String {
        Self.namesSummary(incomingRequests.map(\.user.firstName))
    }

    static func namesSummary(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default:
            let others = names.count - 2
            return "\(names[0]), \(names[1]) and \(others) other\(others == 1 ? "" : "s")"
        }
    }

    // MARK: - Events

    private func apply(_ event: SocialEvent) {
        switch event {
        case .postCreated(let post):
            feed.insertAtTop(post)
        case .postUpdated(let post):
            feed.replace(post)
        case .postDeleted(let id):
            feed.remove(id: id)
        case .userBlocked(let userId):
            feed.removeAll { $0.author.id == userId }
            incomingRequests.removeAll { $0.user.id == userId }
        case .followsChanged:
            Task { await loadRequests() }
        }
    }
}
