import Foundation

/// Wraps `/api/feedback` (list, create, update). The list and update calls
/// are JSON; create posts multipart/form-data so the optional screenshot can
/// ride along with the text content in a single round-trip.
@MainActor
final class FeedbackRepository {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func fetchFeedback() async throws -> [FeedbackDTO] {
        try await apiClient.send(.getFeedback)
    }

    /// Submits a new feedback entry. `screenshot` is the raw image bytes
    /// (JPEG/PNG); pass `nil` for text-only feedback. Server returns the
    /// stored Prisma row; the caller usually re-fetches the full list to pick
    /// up the public Supabase URL the GET endpoint adds.
    @discardableResult
    func submitFeedback(content: String, screenshot: ScreenshotPayload? = nil) async throws -> FeedbackDTO {
        var parts: [MultipartPart] = [.text(name: "content", value: content)]
        if let screenshot {
            parts.append(.file(
                name: "screenshot",
                filename: screenshot.filename,
                mimeType: screenshot.mimeType,
                data: screenshot.data
            ))
        }
        return try await apiClient.sendMultipart(.createFeedback, parts: parts)
    }

    /// PATCH returns the bare Prisma row (no `user`/`screenshotUrl`), so we
    /// don't try to decode it back into `FeedbackDTO`. The VM updates the
    /// flag locally and lets the next list refresh resync.
    func setAddressed(id: String, addressed: Bool) async throws {
        try await apiClient.send(.updateFeedback(id: id, body: UpdateFeedbackBody(addressed: addressed)))
    }

    /// Bundles the binary + filename + MIME type the multipart encoder needs.
    /// Built by the view layer (PhotosPicker → Data + UTType inference).
    struct ScreenshotPayload {
        let data: Data
        let filename: String
        let mimeType: String
    }
}
