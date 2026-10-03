import SwiftUI
import Observation

enum AppTab: Hashable, Sendable {
    case home, friends, progress, programs, settings
}

/// The two sections of the Progress tab.
enum ProgressSection: String, Hashable, Sendable, CaseIterable, Identifiable {
    case history, analytics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: "History"
        case .analytics: "Analytics"
        }
    }
}

/// Lightweight selection store so non-tab views (e.g. Home's quick links) can
/// switch tabs programmatically without having to thread a binding through
/// every intermediate view. Provided by RootTabView via `.environment(...)`.
@Observable
@MainActor
final class TabSelection {
    var current: AppTab = .home
    /// Which section the Progress tab shows.
    var progressSection: ProgressSection = .history

    func select(_ tab: AppTab) {
        current = tab
    }

    /// Switches to the Progress tab, opened on `section`.
    func selectProgress(_ section: ProgressSection) {
        progressSection = section
        current = .progress
    }
}
