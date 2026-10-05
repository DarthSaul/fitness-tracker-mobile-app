import Foundation
import Testing
@testable import FitnessTracker

@Suite("PeopleViewModel")
@MainActor
struct PeopleViewModelTests {
    private let maya = SocialFactory.user("u-maya", name: "Maya Ortiz", username: "maya.lifts")
    private let dev = SocialFactory.user("u-dev", name: "Dev Patel", username: "devpulls")
    private let coach = SocialFactory.user("u-coach", name: "Coach Caulfield", username: "coachc", visibility: .private)

    private func makeViewModel() -> (PeopleViewModel, SocialTestHarness) {
        let harness = SocialTestHarness()
        let viewModel = PeopleViewModel(context: harness.context, debounce: .zero)
        viewModel.tab = .find
        return (viewModel, harness)
    }

    @Test("a query under 2 characters never searches")
    func shortQuery() async {
        let (viewModel, harness) = makeViewModel()
        viewModel.query = "@m"
        viewModel.queryChanged()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(harness.client.callCount(for: .searchUsers(query: "")) == 0)
        #expect(viewModel.searchedQuery == nil)
    }

    @Test("search sends the trimmed query, @ included")
    func search() async {
        let (viewModel, harness) = makeViewModel()
        harness.client.stub(.searchUsers(query: ""), response: UsersWithRelationshipResponseDTO(users: [
            UserWithRelationshipDTO(user: maya, relationship: RelationshipDTO(isSelf: false, outgoing: .none, incoming: .following, incomingRequestId: nil)),
        ]))
        await viewModel.search("@maya")
        let queries: [String] = harness.sent { if case .searchUsers(let q) = $0 { q } else { nil } }
        #expect(queries == ["@maya"])
        #expect(viewModel.results.count == 1)

        viewModel.setOutgoing(.following, forResult: maya.id)
        #expect(viewModel.results[0].relationship.outgoing == .following)
    }

    @Test("a rate-limited search says try again later")
    func rateLimited() async {
        let (viewModel, harness) = makeViewModel()
        harness.client.stubHTTPError(.searchUsers(query: ""), status: 429)
        await viewModel.search("maya")
        #expect(viewModel.searchError == .rateLimited)
    }

    @Test("lists filter locally and label mutual follows")
    func lists() async {
        let (viewModel, harness) = makeViewModel()
        let now = Date.now
        harness.client.stub(.getFollowers, response: FollowListResponseDTO(users: [
            FollowListUserDTO(user: maya, since: now), FollowListUserDTO(user: dev, since: now),
        ]))
        harness.client.stub(.getFollowing, response: FollowListResponseDTO(users: [
            FollowListUserDTO(user: maya, since: now), FollowListUserDTO(user: coach, since: now),
        ]))
        await viewModel.loadLists()

        #expect(viewModel.followersTitle == "Followers · 2")
        #expect(viewModel.followerSubtitle(viewModel.followers[0]) == "@maya.lifts · Mutual")
        #expect(viewModel.followerSubtitle(viewModel.followers[1]) == "@devpulls · Follows you")
        #expect(viewModel.followingSubtitle(viewModel.following[1]) == "@coachc · Private")

        viewModel.tab = .followers
        viewModel.query = "@dev"
        #expect(viewModel.filteredFollowers.map(\.user.id) == ["u-dev"])
        viewModel.query = "ortiz"
        #expect(viewModel.filteredFollowers.map(\.user.id) == ["u-maya"])
    }

    @Test("removing a follower drops them from the list")
    func removeFollower() async {
        let (viewModel, harness) = makeViewModel()
        harness.client.stub(.getFollowers, response: FollowListResponseDTO(users: [FollowListUserDTO(user: dev, since: .now)]))
        harness.client.stub(.getFollowing, response: FollowListResponseDTO(users: []))
        harness.client.handlers["DELETE /api/followers/u-dev"] = { _ in Data() }
        await viewModel.loadLists()
        await viewModel.removeFollower(viewModel.followers[0])
        #expect(viewModel.followers.isEmpty)
    }
}

@Suite("ProfileViewModel")
@MainActor
struct ProfileViewModelTests {
    private func profileJSON(id: String, visibility: String, outgoing: String, isSelf: Bool = false) -> String {
        """
        {"id":"\(id)","name":"Coach","avatarUrl":null,"profileVisibility":"\(visibility)","username":"coachc",
         "isSelf":\(isSelf),"outgoing":"\(outgoing)","incoming":"none","incomingRequestId":null,
         "bio":null,"followerCount":10,"followingCount":2,"activeProgram":{"name":"Arm Farm 2"},"completedWorkoutCount":null}
        """
    }

    @Test("a private profile I don't follow shows the lock without calling posts")
    func lockedSkipsPosts() async {
        let harness = SocialTestHarness()
        harness.client.stubJSON(.getUser(id: "u-coach"), profileJSON(id: "u-coach", visibility: "PRIVATE", outgoing: "requested"))
        let viewModel = ProfileViewModel(userId: "u-coach", context: harness.context)
        await viewModel.load()
        #expect(viewModel.postsAreLocked)
        #expect(harness.client.callCount(for: .getUserPosts(userId: "u-coach", page: .firstPage)) == 0)
        #expect(viewModel.profile?.stats.workoutCountRow == nil)
        #expect(viewModel.profile?.stats.activeProgramRow == "Arm Farm 2")
    }

    @Test("a public profile loads its posts")
    func publicLoadsPosts() async {
        let harness = SocialTestHarness()
        harness.client.stubJSON(.getUser(id: "u-coach"), profileJSON(id: "u-coach", visibility: "PUBLIC", outgoing: "none"))
        harness.client.stubJSON(.getUserPosts(userId: "u-coach", page: .firstPage), SocialFixtures.postsPageJSON([SocialFixtures.postJSON()]))
        let viewModel = ProfileViewModel(userId: "u-coach", context: harness.context)
        await viewModel.load()
        #expect(!viewModel.postsAreLocked)
        #expect(viewModel.posts.items.count == 1)
    }

    @Test("following a public profile bumps the follower count")
    func followCount() async {
        let harness = SocialTestHarness()
        harness.client.stubJSON(.getUser(id: "u-coach"), profileJSON(id: "u-coach", visibility: "PUBLIC", outgoing: "none"))
        harness.client.stubJSON(.getUserPosts(userId: "u-coach", page: .firstPage), #"{"posts":[]}"#)
        let viewModel = ProfileViewModel(userId: "u-coach", context: harness.context)
        await viewModel.load()
        viewModel.outgoing = .following
        #expect(viewModel.profile?.followerCount == 11)
        viewModel.outgoing = .none
        #expect(viewModel.profile?.followerCount == 10)
    }

    @Test("a 404 shows the account as gone, never as blocked")
    func gone() async {
        let harness = SocialTestHarness()
        harness.client.stubHTTPError(.getUser(id: "u-x"), status: 404)
        let viewModel = ProfileViewModel(userId: "u-x", context: harness.context)
        await viewModel.load()
        #expect(viewModel.isGone)
        #expect(viewModel.loadError == nil)
    }

    @Test("blocking this user from anywhere closes the profile")
    func blockCloses() async {
        let harness = SocialTestHarness()
        let viewModel = ProfileViewModel(userId: "u-coach", context: harness.context)
        harness.context.events.send(.userBlocked(userId: "u-coach"))
        #expect(viewModel.didBlock)
    }
}

@Suite("SocialSettingsViewModel")
@MainActor
struct SocialSettingsViewModelTests {
    @Test("a failed privacy change rolls back and shows a toast")
    func rollback() async {
        let harness = SocialTestHarness()
        harness.client.stub(.getMe, response: UserProfile(
            id: "user-me", email: "s@example.com", name: nil, avatarUrl: nil, profileVisibility: .private
        ))
        await harness.sessionManager.loadProfile()
        harness.client.stubHTTPError(.updateMe(UpdateMeBody()), status: 500)
        let viewModel = SocialSettingsViewModel(context: harness.context)

        await viewModel.setPrivate(false)

        #expect(viewModel.isPrivate)
        #expect(harness.context.toasts.current != nil)
    }

    @Test("a profile with no visibility yet reads as private (the default)")
    func defaultPrivate() {
        let harness = SocialTestHarness()
        #expect(SocialSettingsViewModel(context: harness.context).isPrivate)
    }
}
