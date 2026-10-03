import Foundation

/// Feed and post-creation calls for the Friends tab.
@MainActor
final class FeedRepository {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    /// GET /api/feed — my posts plus those of everyone I follow (accepted),
    /// newest first. A page shorter than `limit` is the end.
    func fetchFeed(page: PageQuery) async throws -> [PostDTO] {
        let response: PostsResponseDTO = try await apiClient.send(.getFeed(page: page))
        return response.posts
    }

    /// POST /api/posts → `201 Post`.
    func createPost(_ body: CreatePostBody) async throws -> PostDTO {
        try await apiClient.send(.createPost(body))
    }
}
