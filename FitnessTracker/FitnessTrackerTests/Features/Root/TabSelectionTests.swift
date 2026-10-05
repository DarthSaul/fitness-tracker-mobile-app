import Foundation
import Testing
@testable import FitnessTracker

@Suite("TabSelection")
@MainActor
struct TabSelectionTests {
    private func makeDefaults(_ name: String = #function) throws -> UserDefaults {
        let suite = "TabSelectionTests.\(name)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Progress opens on Overview the first time")
    func defaultsToOverview() throws {
        #expect(TabSelection(defaults: try makeDefaults()).progressSection == .overview)
        #expect(ProgressSection.allCases.map(\.title) == ["Overview", "History"])
    }

    @Test("selecting a Progress section switches tab and is remembered between launches")
    func remembersSection() throws {
        let defaults = try makeDefaults()
        let selection = TabSelection(defaults: defaults)
        selection.selectProgress(.history)
        #expect(selection.current == .progress)
        #expect(selection.progressSection == .history)

        #expect(TabSelection(defaults: defaults).progressSection == .history)
    }
}
