import Foundation
import Observation
import OSLog

/// Completed standalone sessions, newest first, with the same cursor-paging
/// shape as the program HistoryViewModel (`completedAt` + `id` passed together).
@Observable
@MainActor
final class StandaloneHistoryViewModel {
    // MARK: - State
    var sessions: [StandaloneSessionListItemDTO] = []
    var isLoading = false
    var isLoadingMore = false
    var loadError: Error?
    /// Set to true once the server returns fewer rows than `pageSize` — the
    /// list view stops triggering further `loadMore()` calls.
    private(set) var reachedEnd = false

    // MARK: - Dependencies
    private let repository: StandaloneWorkoutRepository
    private let sessionManager: SessionManager
    private let pageSize: Int

    init(repository: StandaloneWorkoutRepository, sessionManager: SessionManager, pageSize: Int = 20) {
        self.repository = repository
        self.sessionManager = sessionManager
        self.pageSize = pageSize
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        loadError = nil
        reachedEnd = false
        defer { isLoading = false }
        do {
            let page = try await repository.fetchHistory(limit: pageSize)
            sessions = page
            reachedEnd = page.count < pageSize
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch {
            Logger.data.error("StandaloneHistoryViewModel.load failed: \(error)")
            loadError = error
        }
    }

    /// Loads the next older page using the last session's `completedAt` + `id`
    /// as the cursor (the server requires both together).
    func loadMore() async {
        guard !isLoading, !isLoadingMore, !reachedEnd else { return }
        guard let last = sessions.last, let cursor = last.completedAt else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await repository.fetchHistory(limit: pageSize, before: cursor, beforeId: last.id)
            sessions.append(contentsOf: page)
            reachedEnd = page.count < pageSize
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch {
            Logger.data.error("StandaloneHistoryViewModel.loadMore failed: \(error)")
            loadError = error
        }
    }
}
