import Foundation

/// Every social API call (API_CONTRACT_SOCIAL.md) behind one repository, so
/// screens and view models depend on this rather than on endpoint details.
@MainActor
final class SocialRepository {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    // MARK: - Feed & posts

    func fetchFeed(page: PageQuery) async throws -> [PostDTO] {
        let response: PostsResponseDTO = try await apiClient.send(.getFeed(page: page))
        return response.posts
    }

    func fetchUserPosts(userId: String, page: PageQuery) async throws -> [PostDTO] {
        let response: PostsResponseDTO = try await apiClient.send(.getUserPosts(userId: userId, page: page))
        return response.posts
    }

    func fetchPost(id: String) async throws -> PostDTO {
        try await apiClient.send(.getPost(id: id))
    }

    func createPost(_ body: CreatePostBody) async throws -> PostDTO {
        try await apiClient.send(.createPost(body))
    }

    func deletePost(id: String) async throws {
        try await apiClient.send(.deletePost(id: id))
    }

    /// Multipart field `photo`. The bytes must already be a JPEG under 4 MB.
    func uploadPhoto(jpeg: Data) async throws -> UploadedPhotoDTO {
        try await apiClient.sendMultipart(
            .uploadPostPhoto,
            parts: [.file(name: "photo", filename: "photo.jpg", mimeType: "image/jpeg", data: jpeg)]
        )
    }

    // MARK: - Reactions

    /// Returns the post's full reaction summary after adding.
    func addReaction(postId: String, emoji: String) async throws -> [ReactionSummaryDTO] {
        let response: ReactionsResponseDTO = try await apiClient.send(.addReaction(postId: postId, emoji: emoji))
        return response.reactions
    }

    func removeReaction(postId: String, emoji: String) async throws {
        try await apiClient.send(.removeReaction(postId: postId, emoji: emoji))
    }

    func fetchReactors(postId: String, emoji: String, page: PageQuery) async throws -> [ReactorDTO] {
        let response: ReactorsResponseDTO = try await apiClient.send(.getReactors(postId: postId, emoji: emoji, page: page))
        return response.users
    }

    // MARK: - Users

    func searchUsers(query: String) async throws -> [UserWithRelationshipDTO] {
        let response: UsersWithRelationshipResponseDTO = try await apiClient.send(.searchUsers(query: query))
        return response.users
    }

    func fetchProfile(userId: String) async throws -> UserProfileDTO {
        try await apiClient.send(.getUser(id: userId))
    }

    func checkUsername(_ username: String) async throws -> UsernameAvailabilityDTO {
        try await apiClient.send(.checkUsernameAvailability(username: username))
    }

    // MARK: - Follows

    func follow(userId: String) async throws -> FollowResponseDTO {
        try await apiClient.send(.follow(FollowBody(userId: userId)))
    }

    /// Unfollow, or cancel my pending request.
    func unfollow(userId: String) async throws {
        try await apiClient.send(.unfollow(userId: userId))
    }

    func fetchFollowing() async throws -> [FollowListUserDTO] {
        let response: FollowListResponseDTO = try await apiClient.send(.getFollowing)
        return response.users
    }

    func fetchFollowers() async throws -> [FollowListUserDTO] {
        let response: FollowListResponseDTO = try await apiClient.send(.getFollowers)
        return response.users
    }

    func removeFollower(userId: String) async throws {
        try await apiClient.send(.removeFollower(userId: userId))
    }

    func fetchFollowRequests(direction: FollowRequestDirection) async throws -> [FollowRequestDTO] {
        let response: FollowRequestsResponseDTO = try await apiClient.send(.getFollowRequests(direction: direction))
        return response.requests
    }

    func acceptFollowRequest(id: String) async throws {
        let _: AcceptFollowRequestResponseDTO = try await apiClient.send(.acceptFollowRequest(id: id))
    }

    /// Decline (as the followee) or cancel (as the requester).
    func deleteFollowRequest(id: String) async throws {
        try await apiClient.send(.deleteFollowRequest(id: id))
    }

    // MARK: - Safety

    func block(userId: String) async throws {
        let _: BlockResponseDTO = try await apiClient.send(.block(BlockBody(userId: userId)))
    }

    func unblock(userId: String) async throws {
        try await apiClient.send(.unblock(userId: userId))
    }

    func fetchBlocked() async throws -> [BlockedUserDTO] {
        let response: BlockedUsersResponseDTO = try await apiClient.send(.getBlocks)
        return response.users
    }

    func report(_ body: ReportBody) async throws {
        let _: ReportResponseDTO = try await apiClient.send(.report(body))
    }

    // MARK: - My settings

    func updateMe(_ body: UpdateMeBody) async throws -> UserProfile {
        try await apiClient.send(.updateMe(body))
    }
}
