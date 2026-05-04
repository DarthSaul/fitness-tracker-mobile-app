import Foundation
import Observation
import OSLog

/// Drives the feedback list + submit flow. Mirrors the Vue page's behavior
/// with three filter states ordered Unaddressed → Addressed → All.
///
/// Submit is a multipart POST that may include a screenshot; once the server
/// accepts it, the VM re-fetches the list so the new entry's public
/// screenshot URL (added server-side) is visible immediately. PATCH for
/// addressed/unaddressed updates locally first then re-fetches as a
/// belt-and-suspenders sync.
@Observable
@MainActor
final class FeedbackViewModel {
    enum Filter: String, CaseIterable, Identifiable {
        case unaddressed
        case addressed
        case all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .unaddressed: "Unaddressed"
            case .addressed:   "Addressed"
            case .all:         "All"
            }
        }
    }

    // MARK: - State
    var allFeedback: [FeedbackDTO] = []
    var filter: Filter = .unaddressed
    var isLoading = false
    var loadError: String?

    var draftContent: String = ""
    var draftScreenshot: FeedbackRepository.ScreenshotPayload?
    var isSubmitting = false
    var submitError: String?
    /// Briefly true after a successful submit; the view shows a confirmation
    /// note then clears it before the next interaction.
    var didSubmit = false

    // MARK: - Dependencies
    private let repository: FeedbackRepository

    init(repository: FeedbackRepository) {
        self.repository = repository
    }

    // MARK: - Derived
    var filteredFeedback: [FeedbackDTO] {
        switch filter {
        case .all:          return allFeedback
        case .unaddressed:  return allFeedback.filter { !$0.addressed }
        case .addressed:    return allFeedback.filter { $0.addressed }
        }
    }

    /// Trims the draft so submit/disabled state matches what the server sees.
    var canSubmit: Bool {
        !draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    // MARK: - Public API

    func load() async {
        isLoading = true
        loadError = nil
        do {
            self.allFeedback = try await repository.fetchFeedback()
        } catch {
            Logger.networking.error("Feedback list failed: \(error.localizedDescription, privacy: .public)")
            self.loadError = error.localizedDescription
        }
        isLoading = false
    }

    func submit() async {
        let trimmed = draftContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSubmitting else { return }

        isSubmitting = true
        submitError = nil
        didSubmit = false

        do {
            _ = try await repository.submitFeedback(content: trimmed, screenshot: draftScreenshot)
            self.draftContent = ""
            self.draftScreenshot = nil
            self.didSubmit = true
            await self.load()
        } catch {
            Logger.networking.error("Feedback submit failed: \(error.localizedDescription, privacy: .public)")
            self.submitError = "Something went wrong. Please try again."
        }

        isSubmitting = false
    }

    func toggleAddressed(_ feedback: FeedbackDTO) async {
        let newValue = !feedback.addressed
        // Optimistic update so the UI reflects the toggle without waiting for
        // the round-trip; on failure we roll back.
        if let index = allFeedback.firstIndex(where: { $0.id == feedback.id }) {
            allFeedback[index] = mutateAddressed(allFeedback[index], to: newValue)
        }
        do {
            try await repository.setAddressed(id: feedback.id, addressed: newValue)
        } catch {
            // Roll back on failure.
            if let index = allFeedback.firstIndex(where: { $0.id == feedback.id }) {
                allFeedback[index] = mutateAddressed(allFeedback[index], to: !newValue)
            }
            Logger.networking.error("Feedback toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clearScreenshot() {
        draftScreenshot = nil
    }

    // MARK: - Helpers

    /// FeedbackDTO is `let`-only by design (wire-format). Rebuild a copy with
    /// the addressed flag flipped instead of mutating in place.
    private func mutateAddressed(_ original: FeedbackDTO, to value: Bool) -> FeedbackDTO {
        FeedbackDTO(
            id: original.id,
            content: original.content,
            screenshotPath: original.screenshotPath,
            screenshotUrl: original.screenshotUrl,
            addressed: value,
            createdAt: original.createdAt,
            user: original.user
        )
    }
}
