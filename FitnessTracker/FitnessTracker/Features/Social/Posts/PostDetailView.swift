import SwiftUI
import Observation

@Observable
@MainActor
final class PostDetailViewModel {
    let postId: String
    private(set) var post: PostDTO?
    private(set) var isGone = false
    private(set) var loadError: APIFailure?
    private let context: SocialContext

    init(postId: String, context: SocialContext) {
        self.postId = postId
        self.context = context
        context.events.subscribe(self) { [weak self] event in
            guard let self else { return }
            switch event {
            case .postUpdated(let post) where post.id == self.postId:
                self.post = post
            case .postDeleted(let id) where id == self.postId:
                self.post = nil
                self.isGone = true
            case .userBlocked(let userId) where userId == self.post?.author.id:
                self.post = nil
                self.isGone = true
            default:
                break
            }
        }
    }

    func load() async {
        loadError = nil
        do {
            post = try await context.repository.fetchPost(id: postId)
            isGone = false
        } catch {
            guard let failure = await context.failure(from: error) else { return }
            // 404: deleted, or no longer visible (privacy or a block).
            if failure == .notFound {
                isGone = true
                post = nil
            } else {
                loadError = failure
            }
        }
    }

    /// Refetch when the signed photo URLs have expired.
    func refreshIfPhotosExpired(now: Date = .now) async {
        if post?.photosExpired(at: now) == true { await load() }
    }
}

/// A single post, e.g. from a reaction notification.
struct PostDetailView: View {
    @State private var viewModel: PostDetailViewModel
    private let context: SocialContext

    init(postId: String, context: SocialContext) {
        self.context = context
        _viewModel = State(initialValue: PostDetailViewModel(postId: postId, context: context))
    }

    var body: some View {
        ScrollView {
            Group {
                if let post = viewModel.post {
                    PostCardView(post: post)
                } else if viewModel.isGone {
                    ContentUnavailableView(
                        "Post not available",
                        systemImage: "text.bubble",
                        description: Text("It may have been deleted, or it's no longer visible to you.")
                    )
                    .padding(.top, 60)
                } else if let error = viewModel.loadError {
                    RetryCard(message: error.message) { Task { await viewModel.load() } }
                } else {
                    ProgressView().padding(.top, 80)
                }
            }
            .padding(SocialStyle.screenInset)
        }
        .background(SocialStyle.background)
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .task { if viewModel.post == nil { await viewModel.load() } else { await viewModel.refreshIfPhotosExpired() } }
        .refreshable { await viewModel.load() }
        .postInteractionHost(context: context)
    }
}
