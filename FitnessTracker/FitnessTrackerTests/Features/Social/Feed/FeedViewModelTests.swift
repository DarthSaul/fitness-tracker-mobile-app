import Foundation
import Testing
@testable import FitnessTracker

@Suite("FeedViewModel")
@MainActor
struct FeedViewModelTests {
    private func makeViewModel(
        pageSize: Int = 2,
        canPost: @escaping @MainActor () -> Bool = { true }
    ) -> (FeedViewModel, MockAPIClient, SessionManager) {
        let client = MockAPIClient()
        let manager = SessionManager(keychain: KeychainService(service: "me.fitness-app.tracker.tests.feed"), tokenStore: TokenStore())
        manager._setAuthStateForTesting(.authenticated(userId: "user-me"))
        let viewModel = FeedViewModel(
            repository: FeedRepository(apiClient: client),
            sessionManager: manager,
            pageSize: pageSize,
            canPost: canPost
        )
        return (viewModel, client, manager)
    }

    private func feedPages(_ client: MockAPIClient) -> [PageQuery] {
        client.sentEndpoints.compactMap {
            if case .getFeed(let page) = $0 { return page }
            return nil
        }
    }

    private func createBodies(_ client: MockAPIClient) -> [CreatePostBody] {
        client.sentEndpoints.compactMap {
            if case .createPost(let body) = $0 { return body }
            return nil
        }
    }

    // MARK: - Feed

    @Test("loads the feed newest first and pages with the last post's cursor")
    func loadsAndPages() async throws {
        let (viewModel, client, _) = makeViewModel()
        client.handlers["GET /api/feed"] = { endpoint in
            guard case .getFeed(let page) = endpoint else { return Data() }
            let json: String
            if page.cursor == nil {
                json = SocialFixtures.postsPageJSON([
                    SocialFixtures.postJSON(id: "p3", createdAt: "2026-10-02T12:00:03.300Z"),
                    SocialFixtures.postJSON(id: "p2", createdAt: "2026-10-02T12:00:02.200Z"),
                ])
            } else {
                json = SocialFixtures.postsPageJSON([
                    SocialFixtures.postJSON(id: "p1", createdAt: "2026-10-02T12:00:01.100Z"),
                ])
            }
            return Data(json.utf8)
        }

        await viewModel.feed.refresh()
        #expect(viewModel.feed.items.map(\.id) == ["p3", "p2"])

        await viewModel.feed.loadMore()
        #expect(viewModel.feed.items.map(\.id) == ["p3", "p2", "p1"])
        #expect(viewModel.feed.reachedEnd)
        #expect(feedPages(client).last?.cursor == PageCursor(before: "2026-10-02T12:00:02.200Z", beforeId: "p2"))
    }

    @Test("an empty first page is an empty, loaded feed")
    func emptyFeed() async {
        let (viewModel, client, _) = makeViewModel()
        client.stubJSON(.getFeed(page: .firstPage), #"{"posts":[]}"#)
        await viewModel.feed.refresh()
        #expect(viewModel.feed.hasLoaded)
        #expect(viewModel.feed.items.isEmpty)
        #expect(viewModel.feed.reachedEnd)
    }

    @Test("an unauthorized feed load signs out (forced, no logout call)")
    func unauthorizedSignsOut() async {
        let (viewModel, client, manager) = makeViewModel()
        client.stubUnauthorized(for: .getFeed(page: .firstPage))
        await viewModel.feed.refresh()
        #expect(manager.authState == .unauthenticated)
        #expect(client.callCount(for: .logout(LogoutBody(refreshToken: "", deviceToken: nil))) == 0)
    }

    @Test("refetches when loaded photo URLs have expired, not before")
    func refetchesExpiredPhotos() async throws {
        let (viewModel, client, _) = makeViewModel()
        client.stubJSON(.getFeed(page: .firstPage), SocialFixtures.postsPageJSON([
            SocialFixtures.postJSON(
                photos: #"[{"id":"ph1","url":"https://x/1.jpg","width":10,"height":10}]"#,
                photosExpireAt: "2026-10-02T12:15:00.000Z"
            ),
        ]))
        await viewModel.feed.refresh()
        let expiry = try #require(JSONCoding.parseISO8601("2026-10-02T12:15:00Z"))

        await viewModel.refreshIfPhotosExpired(now: expiry.addingTimeInterval(-600))
        #expect(feedPages(client).count == 1)

        await viewModel.refreshIfPhotosExpired(now: expiry.addingTimeInterval(1))
        #expect(feedPages(client).count == 2)
    }

    // MARK: - Composer

    @Test("posting sends the trimmed body and inserts the new post at the top")
    func postInsertsAtTop() async throws {
        let (viewModel, client, _) = makeViewModel()
        client.stubJSON(.getFeed(page: .firstPage), SocialFixtures.postsPageJSON([SocialFixtures.postJSON(id: "old")]))
        client.stubJSON(
            .createPost(CreatePostBody(body: "x")),
            SocialFixtures.postJSON(id: "new", body: "Hello", isMine: true)
        )
        await viewModel.feed.refresh()

        viewModel.draft = "  Hello \n"
        await viewModel.submit()

        #expect(createBodies(client) == [CreatePostBody(body: "Hello")])
        #expect(viewModel.feed.items.map(\.id) == ["new", "old"])
        #expect(viewModel.draft.isEmpty)
        #expect(viewModel.postError == nil)
    }

    @Test("a blank or over-long draft can't be posted")
    func draftValidation() async {
        let (viewModel, client, _) = makeViewModel()
        viewModel.draft = "   \n "
        #expect(!viewModel.canSubmit)
        await viewModel.submit()
        #expect(createBodies(client).isEmpty)

        viewModel.draft = String(repeating: "a", count: SocialRules.postBodyMax)
        #expect(viewModel.canSubmit)
        // 💪 is two UTF-16 units, which is how the server counts.
        viewModel.draft = String(repeating: "a", count: SocialRules.postBodyMax - 1) + "💪"
        #expect(viewModel.isDraftTooLong)
        #expect(!viewModel.canSubmit)
    }

    @Test("a rate-limited post keeps the draft and says try again later")
    func rateLimitedPost() async {
        let (viewModel, client, _) = makeViewModel()
        client.stubHTTPError(.createPost(CreatePostBody(body: "x")), status: 429, message: "Too many requests")
        viewModel.draft = "Hello"
        await viewModel.submit()
        #expect(viewModel.draft == "Hello")
        #expect(viewModel.postError == APIFailure.rateLimited.message)
        #expect(createBodies(client).count == 1, "no automatic retry")
    }

    @Test("the terms gate blocks posting when it says no")
    func termsGateBlocks() async {
        let (viewModel, client, _) = makeViewModel(canPost: { false })
        viewModel.draft = "Hello"
        await viewModel.submit()
        #expect(createBodies(client).isEmpty)
    }
}
