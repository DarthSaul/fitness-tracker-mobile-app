import Foundation
import Observation
import OSLog
import UIKit

/// Up to four photos attached to a post being written (the New Post sheet
/// and the post-workout share prompt). Each is uploaded as soon as it's
/// picked; the upload returns ids, not URLs, so the local copy is shown.
@Observable
@MainActor
final class PhotoAttachments {
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

    private(set) var photos: [AttachedPhoto] = []

    private let context: SocialContext

    init(context: SocialContext) {
        self.context = context
    }

    // MARK: - Status

    var uploadedPhotoIds: [String] {
        photos.compactMap {
            if case .uploaded(let id) = $0.state { return id }
            return nil
        }
    }

    var hasPendingUploads: Bool {
        photos.contains { $0.state == .processing || $0.state == .uploading }
    }

    var hasFailedUploads: Bool {
        photos.contains { if case .failed = $0.state { return true } else { return false } }
    }

    /// Nothing still uploading and no failed photo attached: the post can go.
    var isReadyToPost: Bool { !hasPendingUploads && !hasFailedUploads }

    var remainingPhotoSlots: Int { Self.maxPhotos - photos.count }

    // MARK: - Adding and removing

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
}
