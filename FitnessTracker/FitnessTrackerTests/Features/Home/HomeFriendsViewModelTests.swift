import Foundation
import Testing
@testable import FitnessTracker

@Suite("Home FRIENDS section")
@MainActor
struct HomeFriendsViewModelTests {
    private func post(_ id: String, mine: Bool = false, author: String = "u-maya") -> PostDTO {
        SocialFactory.post(id, author: SocialFactory.user(author), isMine: mine)
    }

    @Test("shows the five newest posts by other people, skipping mine")
    func friendsOnly() {
        let feed = [post("p1"), post("mine", mine: true), post("p2"), post("p3"), post("p4"), post("p5"), post("p6")]
        #expect(HomeFriendsViewModel.friendsPosts(from: feed).map(\.id) == ["p1", "p2", "p3", "p4", "p5"])
    }

    @Test("loads from the feed and drops blocked users' posts")
    func loadsAndAppliesBlock() async {
        let harness = SocialTestHarness()
        harness.client.stub(.getFeed(page: .firstPage), response: PostsResponseDTO(posts: [
            post("p1", author: "u-maya"), post("p2", author: "u-dev"),
        ]))
        let viewModel = HomeFriendsViewModel(context: harness.context)

        await viewModel.load()
        #expect(viewModel.hasLoaded)
        #expect(viewModel.posts.map(\.id) == ["p1", "p2"])

        harness.context.events.send(.userBlocked(userId: "u-dev"))
        #expect(viewModel.posts.map(\.id) == ["p1"])

        harness.context.events.send(.postDeleted(id: "p1"))
        #expect(viewModel.posts.isEmpty)
    }

    @Test("a failed load reports an error instead of the empty state")
    func loadError() async {
        let harness = SocialTestHarness()
        harness.client.stubHTTPError(.getFeed(page: .firstPage), status: 500)
        let viewModel = HomeFriendsViewModel(context: harness.context)
        await viewModel.load()
        #expect(!viewModel.hasLoaded)
        #expect(viewModel.loadError != nil)
    }

    @Test("summaries follow the post type and never include week or day")
    func summaries() throws {
        let workout = try SocialFixtures.decode(PostDTO.self, SocialFixtures.postJSON(workout: #"{"programName":"Brick House"}"#))
        #expect(HomeFriendSummary.text(for: workout) == "finished a workout from Brick House")

        let standalone = try SocialFixtures.decode(PostDTO.self, SocialFixtures.postJSON(workout: #"{"programName":null}"#))
        #expect(HomeFriendSummary.text(for: standalone) == "finished a workout")

        let photo = try SocialFixtures.decode(PostDTO.self, SocialFixtures.postJSON(
            photos: #"[{"id":"a","url":"https://x/a.jpg","width":1,"height":1}]"#,
            photosExpireAt: "2026-10-02T12:15:00.000Z"
        ))
        #expect(HomeFriendSummary.text(for: photo) == "posted a photo")

        let text = try SocialFixtures.decode(PostDTO.self, SocialFixtures.postJSON())
        #expect(HomeFriendSummary.text(for: text) == "posted an update")
    }
}
