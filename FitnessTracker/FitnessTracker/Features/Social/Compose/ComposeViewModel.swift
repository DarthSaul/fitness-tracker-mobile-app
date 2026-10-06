import Foundation
import Observation
import OSLog

/// The New Post sheet (design-spec 04): a caption, up to four photos
/// (uploaded as soon as they're picked; the upload returns ids, not URLs,
/// so the local copy is shown), and optionally a completed workout to share.
@Observable
@MainActor
final class ComposeViewModel {
    /// The app's caption limit. The API allows 2,000; the design caps posts
    /// at 500.
    static let captionMax = 500
    static let maxPhotos = PhotoAttachments.maxPhotos

    /// A completed workout attached ahead of time (from History's Share or
    /// the post-workout prompt).
    struct AttachedWorkout: Equatable {
        let share: CreatePostBody.SharedWorkout
        /// e.g. "Arm Farm 2 · Week 2 · Day 4" — my own workout, shown only
        /// to me in the composer. The post itself carries the program name.
        let label: String
    }

    var caption = ""
    let photoAttachments: PhotoAttachments
    var workout: AttachedWorkout?
    private(set) var isPosting = false
    private(set) var errorMessage: String?
    /// Flips on a successful post, for the success haptic.
    private(set) var didPost = false

    private let context: SocialContext
    /// The App Store Guideline 1.2 terms-of-use seam. No API exists yet, so
    /// it always allows posting; when one ships this gates the first post.
    private let canPost: @MainActor () -> Bool

    init(context: SocialContext, workout: AttachedWorkout? = nil, canPost: @escaping @MainActor () -> Bool = { true }) {
        self.context = context
        self.photoAttachments = PhotoAttachments(context: context)
        self.workout = workout
        self.canPost = canPost
    }

    // MARK: - Caption

    /// Counted as the server counts (UTF-16 units, trimmed).
    var captionLength: Int { SocialRules.postBodyLength(caption) }

    var isCaptionTooLong: Bool { captionLength > Self.captionMax }

    // MARK: - Posting rules

    var photos: [PhotoAttachments.AttachedPhoto] { photoAttachments.photos }

    /// Disabled when there's no caption **and** nothing attached, while
    /// photos upload, or with a failed photo still attached.
    var canSubmit: Bool {
        let hasContent = captionLength > 0 || !photos.isEmpty || workout != nil
        return hasContent && !isCaptionTooLong && photoAttachments.isReadyToPost && !isPosting
    }

    var remainingPhotoSlots: Int { photoAttachments.remainingPhotoSlots }

    // MARK: - Photos

    func addPhotos(_ items: [Data]) async {
        await photoAttachments.addPhotos(items)
    }

    func removePhoto(_ id: UUID) {
        photoAttachments.removePhoto(id)
    }

    // MARK: - Post

    /// Creates the post and broadcasts it (the feed inserts it at the top).
    /// Returns whether it posted.
    @discardableResult
    func submit() async -> Bool {
        guard canSubmit, canPost() else { return false }
        isPosting = true
        errorMessage = nil
        defer { isPosting = false }

        let body = CreatePostBody(body: caption, photoIds: photoAttachments.uploadedPhotoIds, sharing: workout?.share)
        do {
            let post = try await context.repository.createPost(body)
            context.events.send(.postCreated(post))
            didPost = true
            return true
        } catch {
            guard let failure = await context.failure(from: error) else { return false }
            Logger.data.error("Create post failed: \(error)")
            errorMessage = failure.message
            return false
        }
    }
}
