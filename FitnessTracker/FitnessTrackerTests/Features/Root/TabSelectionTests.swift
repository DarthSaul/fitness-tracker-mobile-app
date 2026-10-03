import Testing
@testable import FitnessTracker

@Suite("TabSelection")
@MainActor
struct TabSelectionTests {
    @Test("selecting a Progress section switches to the Progress tab on that section")
    func selectProgressSection() {
        let selection = TabSelection()
        selection.selectProgress(.analytics)
        #expect(selection.current == .progress)
        #expect(selection.progressSection == .analytics)

        selection.select(.home)
        selection.selectProgress(.history)
        #expect(selection.current == .progress)
        #expect(selection.progressSection == .history)
    }
}
