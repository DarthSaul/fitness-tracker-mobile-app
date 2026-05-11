import SwiftUI
import Observation

enum AppTab: Hashable, Sendable {
    case home, history, analytics, programs, settings
}

/// Lightweight selection store so non-tab views (e.g. Home's quick links) can
/// switch tabs programmatically without having to thread a binding through
/// every intermediate view. Provided by RootTabView via `.environment(...)`.
@Observable
@MainActor
final class TabSelection {
    var current: AppTab = .home

    func select(_ tab: AppTab) {
        current = tab
    }
}
