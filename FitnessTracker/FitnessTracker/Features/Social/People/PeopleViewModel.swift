import Foundation
import Observation
import OSLog

/// People (design-spec 08): Find (user search), Followers and Following in
/// one screen. The last tab is remembered for the session.
@Observable
@MainActor
final class PeopleViewModel {
    enum Tab: Hashable { case find, followers, following }

    /// Remembered for the session (not across launches).
    private static var lastTab: Tab = .find

    var tab: Tab = PeopleViewModel.lastTab {
        didSet { Self.lastTab = tab }
    }
    var query = ""

    // Find
    private(set) var results: [UserWithRelationshipDTO] = []
    private(set) var isSearching = false
    private(set) var searchError: APIFailure?
    /// The query the current results are for.
    private(set) var searchedQuery: String?

    // Lists
    private(set) var followers: [FollowListUserDTO] = []
    private(set) var following: [FollowListUserDTO] = []
    private(set) var listsLoaded = false
    private(set) var listsError: APIFailure?
    /// Users I've unfollowed or re-followed from this screen, by id.
    private(set) var outgoingOverrides: [String: FollowState] = [:]
    private(set) var removingIds: Set<String> = []

    private let context: SocialContext
    private let debounce: Duration
    private var searchTask: Task<Void, Never>?

    init(context: SocialContext, debounce: Duration = .milliseconds(300)) {
        self.context = context
        self.debounce = debounce
        context.events.subscribe(self) { [weak self] event in
            if case .userBlocked(let userId) = event {
                self?.results.removeAll { $0.user.id == userId }
                self?.followers.removeAll { $0.user.id == userId }
                self?.following.removeAll { $0.user.id == userId }
            }
        }
    }

    // MARK: - Find

    /// Call on every keystroke. Searches after a pause (search is limited to
    /// 30 a minute); a query under 2 characters clears the results.
    func queryChanged() {
        guard tab == .find else { return }
        searchTask?.cancel()
        guard let normalized = SocialRules.normalizedSearchQuery(query) else {
            results = []
            searchedQuery = nil
            searchError = nil
            isSearching = false
            return
        }
        searchTask = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await search(normalized)
        }
    }

    func search(_ normalized: String) async {
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            let users = try await context.repository.searchUsers(query: normalized)
            guard !Task.isCancelled else { return }
            results = users
            searchedQuery = normalized
        } catch {
            guard !Task.isCancelled else { return }
            searchError = await context.failure(from: error)
        }
    }

    func setOutgoing(_ state: FollowState, forResult userId: String) {
        guard let index = results.firstIndex(where: { $0.user.id == userId }) else { return }
        results[index].relationship.outgoing = state
    }

    // MARK: - Lists

    func loadLists() async {
        listsError = nil
        do {
            async let followerList = context.repository.fetchFollowers()
            async let followingList = context.repository.fetchFollowing()
            (followers, following) = try await (followerList, followingList)
            outgoingOverrides = [:]
            listsLoaded = true
        } catch {
            listsError = await context.failure(from: error)
            Logger.data.error("People lists failed: \(error)")
        }
    }

    var followersTitle: String { listsLoaded ? "Followers · \(followers.count)" : "Followers" }
    var followingTitle: String { listsLoaded ? "Following · \(following.count)" : "Following" }

    var filteredFollowers: [FollowListUserDTO] { filter(followers) }
    var filteredFollowing: [FollowListUserDTO] { filter(following) }

    private func filter(_ users: [FollowListUserDTO]) -> [FollowListUserDTO] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
            .trimmingPrefix("@")
        guard !needle.isEmpty else { return users }
        return users.filter {
            $0.user.username.lowercased().contains(needle)
                || ($0.user.name?.lowercased().contains(needle) ?? false)
        }
    }

    private var followingIds: Set<String> { Set(following.map(\.user.id)) }
    private var followerIds: Set<String> { Set(followers.map(\.user.id)) }

    /// "@maya · Follows you" or "@maya · Mutual".
    func followerSubtitle(_ follower: FollowListUserDTO) -> String {
        "\(follower.user.handle) · \(followingIds.contains(follower.user.id) ? "Mutual" : "Follows you")"
    }

    /// "@dev · Mutual", "@coach · Private", or just the handle.
    func followingSubtitle(_ followee: FollowListUserDTO) -> String {
        if followerIds.contains(followee.user.id) { return "\(followee.user.handle) · Mutual" }
        if followee.user.profileVisibility == .private { return "\(followee.user.handle) · Private" }
        return followee.user.handle
    }

    func outgoing(for userId: String) -> FollowState {
        outgoingOverrides[userId] ?? .following
    }

    func setOutgoing(_ state: FollowState, forFollowing userId: String) {
        outgoingOverrides[userId] = state
    }

    /// Removes a follower (they aren't notified). `204` even if they weren't.
    func removeFollower(_ follower: FollowListUserDTO) async {
        removingIds.insert(follower.id)
        defer { removingIds.remove(follower.id) }
        do {
            try await context.repository.removeFollower(userId: follower.user.id)
            followers.removeAll { $0.id == follower.id }
            context.events.send(.followsChanged)
        } catch {
            guard let failure = await context.failure(from: error) else { return }
            context.toasts.show("Couldn't remove \(follower.user.displayName). \(failure.message)")
        }
    }
}
