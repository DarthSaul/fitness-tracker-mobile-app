import SwiftUI
import Observation

enum AppTab: Hashable, Sendable {
    case home, friends, progress, programs, settings
}

/// The two sections of the Progress tab, in display order.
enum ProgressSection: String, Hashable, Sendable, CaseIterable, Identifiable {
    case overview, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .history: "History"
        }
    }
}

/// The two sections of the Program tab.
enum ProgramSection: String, Hashable, Sendable, CaseIterable, Identifiable {
    case manage, explore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manage: "Manage"
        case .explore: "Explore"
        }
    }
}

/// Lightweight selection store so non-tab views (e.g. Home's quick links) can
/// switch tabs programmatically without having to thread a binding through
/// every intermediate view. Provided by RootTabView via `.environment(...)`.
@Observable
@MainActor
final class TabSelection {
    static let progressSectionDefaultsKey = "progressSection"

    var current: AppTab = .home
    /// Which section the Progress tab shows. Remembered between launches.
    var progressSection: ProgressSection {
        didSet { defaults.set(progressSection.rawValue, forKey: Self.progressSectionDefaultsKey) }
    }
    /// Which section the Program tab shows.
    var programSection: ProgramSection = .manage

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        progressSection = defaults.string(forKey: Self.progressSectionDefaultsKey)
            .flatMap(ProgressSection.init(rawValue:)) ?? .overview
    }

    func select(_ tab: AppTab) {
        current = tab
    }

    /// Switches to the Program tab, opened on `section`.
    func selectProgram(_ section: ProgramSection) {
        programSection = section
        current = .programs
    }

    /// Switches to the Progress tab, opened on `section`.
    func selectProgress(_ section: ProgressSection) {
        progressSection = section
        current = .progress
    }
}
