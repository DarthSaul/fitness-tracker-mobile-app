import Foundation
import Testing
@testable import FitnessTracker

@Suite("RequestsViewModel")
@MainActor
struct RequestsViewModelTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeViewModel(
        incoming: [FollowRequestDTO] = [],
        outgoing: [FollowRequestDTO] = [],
        followers: [FollowListUserDTO] = [],
        following: [FollowListUserDTO] = []
    ) async -> (RequestsViewModel, SocialTestHarness) {
        let harness = SocialTestHarness()
        harness.client.handlers["GET /api/follow-requests"] = { endpoint in
            guard case .getFollowRequests(let direction) = endpoint else { return Data() }
            return try JSONCoding.encoder.encode(FollowRequestsResponseDTO(requests: direction == .incoming ? incoming : outgoing))
        }
        harness.client.stub(.getFollowers, response: FollowListResponseDTO(users: followers))
        harness.client.stub(.getFollowing, response: FollowListResponseDTO(users: following))
        let viewModel = RequestsViewModel(context: harness.context, now: { [now] in now })
        await viewModel.load()
        return (viewModel, harness)
    }

    @Test("approve, then follow back a private account → Requested")
    func approveThenFollowBack() async {
        let theo = SocialFactory.user("u-theo", visibility: .private)
        let request = SocialFactory.request("r1", user: theo)
        let (viewModel, harness) = await makeViewModel(incoming: [request])
        harness.client.stubJSON(.acceptFollowRequest(id: "r1"), #"{"follower":{"id":"u-theo","name":"Ann Lee","avatarUrl":null,"profileVisibility":"PRIVATE","username":"ann","since":"2026-10-02T12:00:00.000Z"}}"#)
        harness.client.stub(.follow(FollowBody(userId: "")), response: FollowResponseDTO(status: .requested, requestId: "f9"))

        #expect(viewModel.state(for: request) == .pending)
        await viewModel.approve(request)
        #expect(viewModel.state(for: request) == .approved)

        await viewModel.followBack(request)
        #expect(viewModel.state(for: request) == .followed(.requested))
    }

    @Test("approving someone I already follow skips Follow back")
    func approveAlreadyFollowing() async {
        let maya = SocialFactory.user("u-maya")
        let request = SocialFactory.request("r1", user: maya)
        let (viewModel, harness) = await makeViewModel(
            incoming: [request],
            following: [FollowListUserDTO(user: maya, since: now)]
        )
        harness.client.stubJSON(.acceptFollowRequest(id: "r1"), #"{"follower":{"id":"u-maya","name":null,"avatarUrl":null,"profileVisibility":"PUBLIC","username":"maya","since":"2026-10-02T12:00:00.000Z"}}"#)

        await viewModel.approve(request)
        #expect(viewModel.state(for: request) == .followed(.following))
    }

    @Test("approving a request that was already handled (404) counts as done")
    func approveNotFound() async {
        let request = SocialFactory.request("r1")
        let (viewModel, harness) = await makeViewModel(incoming: [request])
        harness.client.stubHTTPError(.acceptFollowRequest(id: "r1"), status: 404)
        await viewModel.approve(request)
        #expect(viewModel.state(for: request) == .approved)
    }

    @Test("decline shows Declined; a failure restores Approve")
    func decline() async {
        let request = SocialFactory.request("r1")
        let (viewModel, harness) = await makeViewModel(incoming: [request])
        harness.client.handlers["DELETE /api/follow-requests/r1"] = { _ in Data() }
        await viewModel.decline(request)
        #expect(viewModel.state(for: request) == .declined)

        let other = SocialFactory.request("r2")
        harness.client.stubHTTPError(.deleteFollowRequest(id: "r2"), status: 500)
        await viewModel.decline(other)
        #expect(viewModel.state(for: other) == .pending)
    }

    @Test("approved recently lists followers from the last 7 days")
    func approvedRecently() async {
        let recent = FollowListUserDTO(user: SocialFactory.user("u1"), since: now.addingTimeInterval(-2 * 86_400))
        let old = FollowListUserDTO(user: SocialFactory.user("u2"), since: now.addingTimeInterval(-9 * 86_400))
        let (viewModel, _) = await makeViewModel(followers: [recent, old])
        #expect(viewModel.approvedRecently.map(\.user.id) == ["u1"])
    }

    @Test("cancelling a sent request deletes it and shows Request again")
    func cancelSent() async {
        let request = SocialFactory.request("r5", user: SocialFactory.user("u5", visibility: .private), direction: .outgoing)
        let (viewModel, harness) = await makeViewModel(outgoing: [request])
        #expect(viewModel.sentTitle == "Sent · 1")
        harness.client.handlers["DELETE /api/follow-requests/r5"] = { _ in Data() }

        await viewModel.cancel(request)
        #expect(viewModel.cancelledSentIds.contains("r5"))
        #expect(viewModel.outgoingState(for: "u5") == .none)
    }
}
