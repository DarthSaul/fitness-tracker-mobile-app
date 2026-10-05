import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class HistoryViewModel {
    // MARK: - State
    /// Unified rows — program and standalone completions interleaved
    /// chronologically (GET /api/history with no type filter).
    var sessions: [HistoryEntryDTO] = []
    var isLoading = false
    var isLoadingMore = false
    var loadError: Error?
    /// Set to true once the server returns fewer rows than `pageSize` — the
    /// list view stops triggering further `loadMore()` calls.
    private(set) var reachedEnd = false

    // Calendar
    /// Every completed workout's day, from GET /api/history/dates.
    private(set) var workoutCalendar = WorkoutCalendar(completionDates: [])
    /// The month the calendar card shows.
    var displayedMonth: Date
    /// The day last tapped on the calendar.
    private(set) var selectedDay: Date?
    /// Cap on pages fetched to reach a tapped day, so an old date can't
    /// trigger an unbounded crawl.
    private let maxRevealPages = 20

    // MARK: - Dependencies
    private let repository: HistoryRepository
    private let sessionManager: SessionManager
    private let pageSize: Int

    private let calendar: Calendar

    init(
        repository: HistoryRepository,
        sessionManager: SessionManager,
        pageSize: Int = 20,
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.sessionManager = sessionManager
        self.pageSize = pageSize
        self.calendar = calendar
        self.displayedMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        self.workoutCalendar = WorkoutCalendar(completionDates: [], calendar: calendar)
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        loadError = nil
        reachedEnd = false
        defer { isLoading = false }
        do {
            // The calendar's dates load alongside; if they fail, the list
            // still shows (the calendar just has no marked days).
            async let firstPage = repository.fetchHistory(limit: pageSize, before: nil)
            async let dates: [Date]? = try? repository.fetchCompletionDates()
            let (page, completionDates) = try await (firstPage, dates)
            sessions = page
            reachedEnd = page.count < pageSize
            if let completionDates {
                workoutCalendar = WorkoutCalendar(completionDates: completionDates, calendar: calendar)
            }
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch {
            Logger.data.error("HistoryViewModel.load failed: \(error)")
            loadError = error
        }
    }

    /// Loads the next older page using the last session's `completedAt` + `id`
    /// as the cursor (the server requires both together). No-op when already
    /// loading, when there is nothing to page from, or when the previous page
    /// indicated we've reached the end.
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
            Logger.data.error("HistoryViewModel.loadMore failed: \(error)")
            loadError = error
        }
    }

    // MARK: - Calendar

    /// A calendar day was tapped: pages older history until that day's
    /// workouts are loaded, and returns the first one's id to scroll to
    /// (nil if it can't be reached).
    func reveal(day: Date) async -> String? {
        selectedDay = day
        for _ in 0..<maxRevealPages {
            if let match = firstSession(on: day) { return match.id }
            // Newest first: once the oldest loaded row predates the day, it
            // isn't coming.
            if reachedEnd { return nil }
            if let oldest = sessions.last?.completedAt, calendar.startOfDay(for: oldest) < calendar.startOfDay(for: day) {
                return nil
            }
            let countBefore = sessions.count
            await loadMore()
            if sessions.count == countBefore { return nil }
        }
        return firstSession(on: day)?.id
    }

    private func firstSession(on day: Date) -> HistoryEntryDTO? {
        sessions.first { entry in
            entry.completedAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        }
    }
}
