import Foundation
import Observation
import OSLog

/// Drives the Friends tab: the post composer and the following feed.
///
/// The feed pages through `KeysetPaginator`. A new post is inserted at the
/// top from the `201` response rather than refetching. Photo URLs are signed
/// for 15 minutes, so a feed holding expired URLs is refetched when the
/// screen comes back (`refreshIfPhotosExpired`) instead of showing broken
/// images.
@Observable
@MainActor
final class FeedViewModel {
    // MARK: - Feed
    let feed: KeysetPaginator<PostDTO>

    // MARK: - Composer
    var draft = ""
    private(set) var isPosting = false
    private(set) var postError: String?

    // MARK: - Dependencies
    private let repository: FeedRepository
    private let sessionManager: SessionManager
    /// The seam for the App Store Guideline 1.2 terms-of-use gate before a
    /// first post. No API exists for it yet, so it always allows posting;
    /// when one ships, this decides whether to show the terms first.
    private let canPost: @MainActor () -> Bool

    init(
        repository: FeedRepository,
        sessionManager: SessionManager,
        pageSize: Int = 20,
        canPost: @escaping @MainActor () -> Bool = { true }
    ) {
        self.repository = repository
        self.sessionManager = sessionManager
        self.canPost = canPost
        self.feed = KeysetPaginator(
            pageSize: pageSize,
            endRule: .shortPage,
            cursor: \.cursor,
            onUnauthorized: { await sessionManager.signOut() },
            fetch: { try await repository.fetchFeed(page: $0) }
        )
    }

    // MARK: - Composer

    /// Trimmed length as the server counts it (UTF-16 code units).
    var draftLength: Int { SocialRules.postBodyLength(draft) }

    var isDraftTooLong: Bool { draftLength > SocialRules.postBodyMax }

    /// Text-only for now: a body is required (photos and workout shares,
    /// which allow an empty body, come later).
    var canSubmit: Bool {
        draftLength > 0 && !isDraftTooLong && !isPosting
    }

    func submit() async {
        guard canSubmit, canPost() else { return }
        isPosting = true
        postError = nil
        defer { isPosting = false }

        do {
            let post = try await repository.createPost(CreatePostBody(body: draft))
            feed.insertAtTop(post)
            draft = ""
        } catch {
            let failure = APIFailure(error)
            if failure == .unauthorized {
                await sessionManager.signOut()
                return
            }
            Logger.data.error("Create post failed: \(error)")
            postError = failure.message
        }
    }

    func clearPostError() {
        postError = nil
    }

    // MARK: - Photo URL expiry

    /// Refetches from the top when any loaded post's photo URLs have expired.
    func refreshIfPhotosExpired(now: Date = .now) async {
        guard feed.items.contains(where: { $0.photosExpired(at: now) }) else { return }
        await feed.refresh()
    }
}
