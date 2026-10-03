import Foundation
import Testing
@testable import FitnessTracker

@Suite("Reactions rules")
struct ReactionsTests {
    private func r(_ emoji: String, _ count: Int, mine: Bool = false) -> ReactionSummaryDTO {
        ReactionSummaryDTO(emoji: emoji, count: count, mine: mine)
    }

    @Test("chips show the fixed five in order, then any others, hiding zero counts")
    func ordering() {
        let server = [r("😤", 1), r("🎉", 4), r("💪", 6), r("🔥", 3), r("🏆", 0)]
        #expect(Reactions.ordered(server).map(\.emoji) == ["💪", "🔥", "😤", "🎉"])
    }

    @Test("toggling adds or removes my reaction")
    func toggling() {
        let start = [r("💪", 2), r("🔥", 1, mine: true)]

        let added = Reactions.toggling("💪", in: start)
        #expect(added.first { $0.emoji == "💪" } == r("💪", 3, mine: true))

        let removed = Reactions.toggling("🔥", in: start)
        #expect(!removed.contains { $0.emoji == "🔥" }, "a chip at zero disappears")

        let new = Reactions.toggling("🏆", in: start)
        #expect(new.last == r("🏆", 1, mine: true))
    }

    @Test("the fixed set is exactly 💪 🔥 🏆 👏 😤")
    func fixedSet() {
        #expect(Reactions.quick == ["💪", "🔥", "🏆", "👏", "😤"])
    }

    @Test("top reaction is the most used")
    func top() {
        #expect(Reactions.top([r("💪", 2), r("🔥", 5), r("👏", 1)])?.emoji == "🔥")
        #expect(Reactions.top([]) == nil)
    }
}

@Suite("PostActions")
@MainActor
struct PostActionsTests {
    private func updates(_ log: SocialTestHarness.EventLog) -> [PostDTO] {
        log.events.compactMap { if case .postUpdated(let post) = $0 { post } else { nil } }
    }

    @Test("adding a reaction updates optimistically, then adopts the server's summary")
    func addReconciles() async {
        let harness = SocialTestHarness()
        let log = harness.recordEvents()
        harness.client.stub(
            .addReaction(postId: "post-1", emoji: "💪"),
            response: ReactionsResponseDTO(reactions: [ReactionSummaryDTO(emoji: "💪", count: 7, mine: true)])
        )
        let post = SocialFactory.post(reactions: [ReactionSummaryDTO(emoji: "💪", count: 5, mine: false)])

        await harness.context.postActions.toggleReaction("💪", on: post)

        let sent = updates(log)
        #expect(sent.count == 2)
        #expect(sent[0].reactions == [ReactionSummaryDTO(emoji: "💪", count: 6, mine: true)])
        #expect(sent[1].reactions == [ReactionSummaryDTO(emoji: "💪", count: 7, mine: true)])
    }

    @Test("toggling my own reaction sends DELETE")
    func removeSendsDelete() async {
        let harness = SocialTestHarness()
        harness.client.handlers["DELETE /api/posts/post-1/reactions/🔥"] = { _ in Data() }
        let post = SocialFactory.post(reactions: [ReactionSummaryDTO(emoji: "🔥", count: 1, mine: true)])

        await harness.context.postActions.toggleReaction("🔥", on: post)

        #expect(harness.client.callCount(for: .removeReaction(postId: "post-1", emoji: "🔥")) == 1)
        #expect(harness.client.callCount(for: .addReaction(postId: "post-1", emoji: "🔥")) == 0)
    }

    @Test("a failed toggle rolls back and shows a toast")
    func failureRollsBack() async {
        let harness = SocialTestHarness()
        let log = harness.recordEvents()
        harness.client.stubHTTPError(.addReaction(postId: "post-1", emoji: "👏"), status: 500)
        let post = SocialFactory.post()

        await harness.context.postActions.toggleReaction("👏", on: post)

        #expect(updates(log).last?.reactions == [])
        #expect(harness.context.toasts.current != nil)
    }

    @Test("a 404 means the post is gone everywhere")
    func notFoundDeletes() async {
        let harness = SocialTestHarness()
        let log = harness.recordEvents()
        harness.client.stubHTTPError(.addReaction(postId: "post-1", emoji: "👏"), status: 404)

        await harness.context.postActions.toggleReaction("👏", on: SocialFactory.post())

        #expect(log.events.contains { if case .postDeleted(let id) = $0 { id == "post-1" } else { false } })
    }

    @Test("deleting my post broadcasts the deletion; 404 counts as deleted")
    func deletePost() async {
        let harness = SocialTestHarness()
        let log = harness.recordEvents()
        harness.client.stubHTTPError(.deletePost(id: "post-1"), status: 404)

        let deleted = await harness.context.postActions.delete(SocialFactory.post(isMine: true))

        #expect(deleted)
        #expect(log.events.contains { if case .postDeleted = $0 { true } else { false } })
    }
}

@Suite("Follow button state")
struct FollowButtonStateTests {
    @Test("the contract's follow-button table")
    func table() {
        #expect(FollowButtonState(visibility: .public, outgoing: .none) == .follow)
        #expect(FollowButtonState(visibility: .private, outgoing: .none) == .request)
        #expect(FollowButtonState(visibility: .private, outgoing: .requested) == .requested)
        #expect(FollowButtonState(visibility: .public, outgoing: .requested) == .requested)
        #expect(FollowButtonState(visibility: .public, outgoing: .following) == .following)
        #expect(FollowButtonState(visibility: .private, outgoing: .following) == .following)
    }

    @Test("following is instant for public profiles and a request for private ones")
    func optimistic() {
        #expect(FollowButtonState.optimisticOutgoingAfterFollowing(visibility: .public) == .following)
        #expect(FollowButtonState.optimisticOutgoingAfterFollowing(visibility: .private) == .requested)
    }
}
