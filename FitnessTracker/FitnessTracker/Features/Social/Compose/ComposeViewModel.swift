import Foundation
import Observation
import OSLog
import UIKit

/// The New Post sheet (design-spec 04): a caption, up to four photos
/// (uploaded as soon as they're picked; the upload returns ids, not URLs,
/// so the local copy is shown), and optionally a completed workout to share.
@Observable
@MainActor
final class ComposeViewModel {
    /// The app's caption limit. The API allows 2,000; the design caps posts
    /// at 500.
    static let captionMax = 500
    static let maxPhotos = 4

    struct AttachedPhoto: Identifiable {
        enum State: Equatable {
            case processing
            case uploading
            case uploaded(id: String)
            case failed(String)
        }

        let id = UUID()
        var preview: UIImage?
        var state: State
    }

    /// A completed workout attached ahead of time (from History's Share or
    /// the post-workout prompt).
    struct AttachedWorkout: Equatable {
        let share: CreatePostBody.SharedWorkout
        /// e.g. "Arm Farm 2 · Week 2 · Day 4" — my own workout, shown only
        /// to me in the composer. The post itself carries the program name.
        let label: String
    }

    var caption = ""
    private(set) var photos: [AttachedPhoto] = []
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
        self.workout = workout
        self.canPost = canPost
    }

    // MARK: - Caption

    /// Counted as the server counts (UTF-16 units, trimmed).
    var captionLength: Int { SocialRules.postBodyLength(caption) }

    var isCaptionTooLong: Bool { captionLength > Self.captionMax }

    // MARK: - Posting rules

    private var uploadedPhotoIds: [String] {
        photos.compactMap {
            if case .uploaded(let id) = $0.state { return id }
            return nil
        }
    }

    private var hasPendingUploads: Bool {
        photos.contains { $0.state == .processing || $0.state == .uploading }
    }

    private var hasFailedUploads: Bool {
        photos.contains { if case .failed = $0.state { return true } else { return false } }
    }

    /// Disabled when there's no caption **and** nothing attached, while
    /// photos upload, or with a failed photo still attached.
    var canSubmit: Bool {
        let hasContent = captionLength > 0 || !photos.isEmpty || workout != nil
        return hasContent && !isCaptionTooLong && !hasPendingUploads && !hasFailedUploads && !isPosting
    }

    var remainingPhotoSlots: Int { Self.maxPhotos - photos.count }

    // MARK: - Photos

    /// Processes and uploads picked images, in pick order. Placeholders for
    /// every accepted image are added up front, before any await, so an
    /// overlapping pick sees those slots as taken and can't exceed the limit.
    func addPhotos(_ items: [Data]) async {
        let accepted = items.prefix(remainingPhotoSlots).map { data in
            (photo: AttachedPhoto(preview: nil, state: .processing), data: data)
        }
        photos.append(contentsOf: accepted.map(\.photo))
        for (photo, data) in accepted {
            await process(photoId: photo.id, data: data)
        }
    }

    func removePhoto(_ id: UUID) {
        // An upload that's never attached expires server-side after 24 hours,
        // so there's nothing to clean up.
        photos.removeAll { $0.id == id }
    }

    private func process(photoId: UUID, data: Data) async {
        let processed: (jpeg: Data, preview: UIImage)
        do {
            processed = try await Task.detached(priority: .userInitiated) {
                try PhotoProcessing.jpegForUpload(from: data)
            }.value
        } catch {
            update(photoId) { $0.state = .failed("This image couldn't be read.") }
            return
        }
        update(photoId) {
            $0.preview = processed.preview
            $0.state = .uploading
        }
        do {
            let uploaded = try await context.repository.uploadPhoto(jpeg: processed.jpeg)
            update(photoId) { $0.state = .uploaded(id: uploaded.id) }
        } catch {
            guard let failure = await context.failure(from: error) else { return }
            Logger.data.error("Photo upload failed: \(error)")
            update(photoId) { $0.state = .failed(failure.message) }
        }
    }

    private func update(_ id: UUID, _ change: (inout AttachedPhoto) -> Void) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        change(&photos[index])
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

        let body = CreatePostBody(body: caption, photoIds: uploadedPhotoIds, sharing: workout?.share)
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
