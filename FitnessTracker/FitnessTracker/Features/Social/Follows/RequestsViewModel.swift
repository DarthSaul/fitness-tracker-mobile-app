import Foundation
import Observation
import OSLog

/// Follow requests (design-spec 07): received and sent, with a per-row state
/// machine for received ones:
///
///     pending ──Approve──► approved ──Follow back──► following / requested
///        └──────✕──────► declined (gone on the next load)
@Observable
@MainActor
final class RequestsViewModel {
    enum Tab: Hashable { case received, sent }

    enum RowState: Equatable {
        case pending
        case approved
        /// After "Follow back" (or when I already followed them):
        /// `.following` for a public account, `.requested` for a private one.
        case followed(FollowState)
        case declined
    }

    var tab: Tab = .received
    private(set) var received: [FollowRequestDTO] = []
    private(set) var sent: [FollowRequestDTO] = []
    /// Accepted followers from the last 7 days ("APPROVED RECENTLY").
    private(set) var approvedRecently: [FollowListUserDTO] = []
    private(set) var rowStates: [String: RowState] = [:]
    /// My outgoing state toward each user, from my following list and sent
    /// requests, so Follow back / Following shows correctly.
    private(set) var outgoing: [String: FollowState] = [:]
    private(set) var cancelledSentIds: Set<String> = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var loadError: APIFailure?
    private(set) var workingIds: Set<String> = []

    private let context: SocialContext
    private let now: () -> Date

    init(context: SocialContext, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.now = now
        context.events.subscribe(self) { [weak self] event in
            if case .userBlocked(let userId) = event {
                self?.received.removeAll { $0.user.id == userId }
                self?.sent.removeAll { $0.user.id == userId }
                self?.approvedRecently.removeAll { $0.user.id == userId }
            }
        }
    }

    // MARK: - Loading

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            async let incoming = context.repository.fetchFollowRequests(direction: .incoming)
            async let outgoingRequests = context.repository.fetchFollowRequests(direction: .outgoing)
            async let followers = context.repository.fetchFollowers()
            async let following = context.repository.fetchFollowing()
            let (incomingList, sentList, followerList, followingList) = try await (incoming, outgoingRequests, followers, following)

            received = incomingList
            sent = sentList
            cancelledSentIds = []
            rowStates = Dictionary(uniqueKeysWithValues: incomingList.map { ($0.id, RowState.pending) })

            var outgoingMap: [String: FollowState] = [:]
            for user in followingList { outgoingMap[user.id] = .following }
            for request in sentList { outgoingMap[request.user.id] = .requested }
            outgoing = outgoingMap

            let cutoff = now().addingTimeInterval(-7 * 86_400)
            approvedRecently = followerList.filter { $0.since >= cutoff }
            hasLoaded = true
        } catch {
            loadError = await context.failure(from: error)
            Logger.data.error("Requests load failed: \(error)")
        }
    }

    // MARK: - Derived

    var receivedTitle: String { "Received · \(received.count)" }
    var sentTitle: String { "Sent · \(sent.count)" }

    func state(for request: FollowRequestDTO) -> RowState {
        rowStates[request.id] ?? .pending
    }

    func outgoingState(for userId: String) -> FollowState {
        outgoing[userId] ?? .none
    }

    // MARK: - Received actions

    func approve(_ request: FollowRequestDTO) async {
        workingIds.insert(request.id)
        defer { workingIds.remove(request.id) }
        rowStates[request.id] = .approved
        if await FollowActions(context: context).accept(requestId: request.id) {
            // Already following them? Skip straight to that.
            let mine = outgoingState(for: request.user.id)
            rowStates[request.id] = mine == .none ? .approved : .followed(mine)
        } else {
            rowStates[request.id] = .pending
        }
    }

    func decline(_ request: FollowRequestDTO) async {
        workingIds.insert(request.id)
        defer { workingIds.remove(request.id) }
        rowStates[request.id] = .declined
        if !(await FollowActions(context: context).decline(requestId: request.id)) {
            rowStates[request.id] = .pending
        }
    }

    func followBack(_ request: FollowRequestDTO) async {
        workingIds.insert(request.id)
        defer { workingIds.remove(request.id) }
        let optimistic = FollowButtonState.optimisticOutgoingAfterFollowing(visibility: request.user.profileVisibility)
        rowStates[request.id] = .followed(optimistic)
        if let result = await FollowActions(context: context).follow(request.user) {
            rowStates[request.id] = .followed(result)
            outgoing[request.user.id] = result
        } else {
            rowStates[request.id] = .approved
        }
    }

    /// Bindable outgoing state for a FollowButton (approved-recently rows).
    func setOutgoing(_ state: FollowState, for userId: String) {
        outgoing[userId] = state
    }

    // MARK: - Sent actions

    /// Cancels my request (tap on "Requested"). The row stays, showing
    /// "Request" again, until the next load.
    func cancel(_ request: FollowRequestDTO) async {
        workingIds.insert(request.id)
        defer { workingIds.remove(request.id) }
        cancelledSentIds.insert(request.id)
        do {
            try await context.repository.deleteFollowRequest(id: request.id)
            outgoing[request.user.id] = FollowState.none
            context.events.send(.followsChanged)
        } catch {
            guard let failure = await context.failure(from: error) else { return }
            if failure == .notFound {
                // Already gone (accepted or declined meanwhile).
                return
            }
            cancelledSentIds.remove(request.id)
            context.toasts.show("Couldn't cancel the request. \(failure.message)")
        }
    }

    /// Re-requests after cancelling.
    func requestAgain(_ request: FollowRequestDTO) async {
        workingIds.insert(request.id)
        defer { workingIds.remove(request.id) }
        cancelledSentIds.remove(request.id)
        if let result = await FollowActions(context: context).follow(request.user) {
            outgoing[request.user.id] = result
        } else {
            cancelledSentIds.insert(request.id)
        }
    }
}
