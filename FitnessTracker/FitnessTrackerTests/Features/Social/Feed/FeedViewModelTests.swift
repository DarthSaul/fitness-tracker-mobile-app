import Foundation
import Testing
@testable import FitnessTracker

@Suite("FeedViewModel")
@MainActor
struct FeedViewModelTests {
    private func makeViewModel(pageSize: Int = 2) -> (FeedViewModel, SocialTestHarness) {
        let harness = SocialTestHarness()
        harness.client.stubJSON(.getFollowRequests(direction: .incoming), #"{"requests":[]}"#)
        return (FeedViewModel(context: harness.context, pageSize: pageSize), harness)
    }

    private func feedPages(_ harness: SocialTestHarness) -> [PageQuery] {
        harness.sent { if case .getFeed(let page) = $0 { page } else { nil } }
    }

    @Test("loads the feed newest first and pages with the last post's raw cursor")
    func loadsAndPages() async {
        let (viewModel, harness) = makeViewModel()
        harness.client.handlers["GET /api/feed"] = { endpoint in
            guard case .getFeed(let page) = endpoint else { return Data() }
            let json = page.cursor == nil
                ? SocialFixtures.postsPageJSON([
                    SocialFixtures.postJSON(id: "p3", createdAt: "2026-10-02T12:00:03.300Z"),
                    SocialFixtures.postJSON(id: "p2", createdAt: "2026-10-02T12:00:02.200Z"),
                ])
                : SocialFixtures.postsPageJSON([SocialFixtures.postJSON(id: "p1", createdAt: "2026-10-02T12:00:01.100Z")])
            return Data(json.utf8)
        }

        await viewModel.loadIfNeeded()
        #expect(viewModel.feed.items.map(\.id) == ["p3", "p2"])

        await viewModel.feed.loadMore()
        #expect(viewModel.feed.items.map(\.id) == ["p3", "p2", "p1"])
        #expect(viewModel.feed.reachedEnd)
        #expect(feedPages(harness).last?.cursor == PageCursor(before: "2026-10-02T12:00:02.200Z", beforeId: "p2"))
    }

    @Test("an empty first page shows the empty state")
    func emptyFeed() async {
        let (viewModel, harness) = makeViewModel()
        harness.client.stubJSON(.getFeed(page: .firstPage), #"{"posts":[]}"#)
        await viewModel.loadIfNeeded()
        #expect(viewModel.isEmpty)
    }

    @Test("a failed load is an error, not the empty state")
    func errorIsNotEmpty() async {
        let (viewModel, harness) = makeViewModel()
        harness.client.stubHTTPError(.getFeed(page: .firstPage), status: 500)
        await viewModel.loadIfNeeded()
        #expect(!viewModel.isEmpty)
        #expect(viewModel.feed.loadError != nil)
    }

    @Test("loads incoming requests for the shortcut row")
    func loadsIncomingRequests() async {
        let (viewModel, harness) = makeViewModel()
        harness.client.stubJSON(.getFeed(page: .firstPage), #"{"posts":[]}"#)
        harness.client.stub(.getFollowRequests(direction: .incoming), response: FollowRequestsResponseDTO(requests: [
            SocialFactory.request("r1", user: SocialFactory.user("u1", name: "Theo Brandt")),
            SocialFactory.request("r2", user: SocialFactory.user("u2", name: "Ana Lucero")),
            SocialFactory.request("r3", user: SocialFactory.user("u3", name: "Rina Sato")),
        ]))
        await viewModel.loadIfNeeded()
        #expect(viewModel.incomingRequests.count == 3)
        #expect(viewModel.requestsSummary == "Theo, Ana and 1 other")
    }

    @Test("names summary reads naturally for 1, 2 and many")
    func namesSummary() {
        #expect(FeedViewModel.namesSummary([]) == "")
        #expect(FeedViewModel.namesSummary(["Theo"]) == "Theo")
        #expect(FeedViewModel.namesSummary(["Theo", "Ana"]) == "Theo and Ana")
        #expect(FeedViewModel.namesSummary(["Theo", "Ana", "Rina", "Dev"]) == "Theo, Ana and 2 others")
    }

    @Test("events from other screens update the feed")
    func appliesEvents() async {
        let (viewModel, harness) = makeViewModel(pageSize: 20)
        harness.client.stub(.getFeed(page: .firstPage), response: PostsResponseDTO(posts: [
            SocialFactory.post("a", author: SocialFactory.user("u-a")),
            SocialFactory.post("b", author: SocialFactory.user("u-b")),
        ]))
        await viewModel.loadIfNeeded()

        let created = SocialFactory.post("new", isMine: true)
        harness.context.events.send(.postCreated(created))
        #expect(viewModel.feed.items.first?.id == "new")

        var updated = SocialFactory.post("a", author: SocialFactory.user("u-a"))
        updated.reactions = [ReactionSummaryDTO(emoji: "💪", count: 1, mine: true)]
        harness.context.events.send(.postUpdated(updated))
        #expect(viewModel.feed.items.first { $0.id == "a" }?.reactions.count == 1)

        harness.context.events.send(.postDeleted(id: "new"))
        #expect(!viewModel.feed.items.contains { $0.id == "new" })

        harness.context.events.send(.userBlocked(userId: "u-b"))
        #expect(viewModel.feed.items.map(\.id) == ["a"])
    }

    @Test("refetches when loaded photo URLs have expired, not before")
    func refetchesExpiredPhotos() async throws {
        let (viewModel, harness) = makeViewModel()
        harness.client.stubJSON(.getFeed(page: .firstPage), SocialFixtures.postsPageJSON([
            SocialFixtures.postJSON(
                photos: #"[{"id":"ph1","url":"https://x/1.jpg","width":10,"height":10}]"#,
                photosExpireAt: "2026-10-02T12:15:00.000Z"
            ),
        ]))
        await viewModel.loadIfNeeded()
        let expiry = try #require(JSONCoding.parseISO8601("2026-10-02T12:15:00Z"))

        await viewModel.refreshIfPhotosExpired(now: expiry.addingTimeInterval(-600))
        #expect(feedPages(harness).count == 1)

        await viewModel.refreshIfPhotosExpired(now: expiry.addingTimeInterval(1))
        #expect(feedPages(harness).count == 2)
    }

    @Test("an unauthorized feed load signs out locally")
    func unauthorizedSignsOut() async {
        let (viewModel, harness) = makeViewModel()
        harness.client.stubUnauthorized(for: .getFeed(page: .firstPage))
        await viewModel.loadIfNeeded()
        #expect(harness.sessionManager.authState == .unauthenticated)
    }
}
