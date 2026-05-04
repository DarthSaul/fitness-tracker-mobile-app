import Foundation
import Testing
@testable import FitnessTracker

@Suite("FeedbackViewModel")
@MainActor
struct FeedbackViewModelTests {
    private func makeFeedback(id: String, addressed: Bool, content: String = "x") -> FeedbackDTO {
        FeedbackDTO(
            id: id, content: content, screenshotPath: nil, screenshotUrl: nil,
            addressed: addressed, createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            user: .init(name: "Saul Graves")
        )
    }

    private func makeViewModel(initial: [FeedbackDTO] = []) -> (FeedbackViewModel, MockAPIClient) {
        let client = MockAPIClient()
        client.stub(.getFeedback, response: initial)
        client.stub(.createFeedback, response: makeFeedback(id: "new", addressed: false))
        let repo = FeedbackRepository(apiClient: client)
        return (FeedbackViewModel(repository: repo), client)
    }

    // MARK: - Filter

    @Test("Default filter is .unaddressed and matches Vue's first-tab convention reordered")
    func defaultFilter() {
        let (vm, _) = makeViewModel()
        #expect(vm.filter == .unaddressed)
    }

    @Test("filteredFeedback applies the unaddressed/addressed/all filter")
    func filtering() async {
        let items = [
            FeedbackDTO(id: "a", content: "A", screenshotPath: nil, screenshotUrl: nil,
                        addressed: false, createdAt: .now, user: .init(name: nil)),
            FeedbackDTO(id: "b", content: "B", screenshotPath: nil, screenshotUrl: nil,
                        addressed: true, createdAt: .now, user: .init(name: nil)),
            FeedbackDTO(id: "c", content: "C", screenshotPath: nil, screenshotUrl: nil,
                        addressed: false, createdAt: .now, user: .init(name: nil))
        ]
        let (vm, _) = makeViewModel(initial: items)
        await vm.load()

        vm.filter = .unaddressed
        #expect(vm.filteredFeedback.map(\.id) == ["a", "c"])
        vm.filter = .addressed
        #expect(vm.filteredFeedback.map(\.id) == ["b"])
        vm.filter = .all
        #expect(vm.filteredFeedback.count == 3)
    }

    // MARK: - load

    @Test("load() populates allFeedback and clears errors")
    func loadHappy() async {
        let (vm, _) = makeViewModel(initial: [makeFeedback(id: "x", addressed: false)])
        await vm.load()
        #expect(vm.allFeedback.count == 1)
        #expect(vm.loadError == nil)
        #expect(vm.isLoading == false)
    }

    @Test("load() records error on 401")
    func loadError() async {
        let client = MockAPIClient()
        client.stubUnauthorized(for: .getFeedback)
        let vm = FeedbackViewModel(repository: FeedbackRepository(apiClient: client))
        await vm.load()
        #expect(vm.loadError != nil)
    }

    // MARK: - submit

    @Test("submit() sends multipart parts and refreshes the list")
    func submitHappy() async {
        let (vm, client) = makeViewModel(initial: [])
        // After submit, the next fetchFeedback returns a single new item.
        let newItem = makeFeedback(id: "new", addressed: false, content: "Bug")
        client.stub(.getFeedback, response: [newItem])

        vm.draftContent = "  Bug  "
        await vm.submit()

        #expect(vm.didSubmit)
        #expect(vm.draftContent.isEmpty)
        #expect(vm.allFeedback.count == 1)
        #expect(vm.allFeedback[0].id == "new")
        let parts = client.lastMultipartParts
        #expect(parts?.first?.name == "content")
        #expect(String(data: parts?.first?.data ?? Data(), encoding: .utf8) == "Bug")
    }

    @Test("submit() with whitespace-only content is a no-op")
    func submitNoOp() async {
        let (vm, _) = makeViewModel(initial: [])
        vm.draftContent = "   \n  "
        await vm.submit()
        #expect(vm.didSubmit == false)
        #expect(vm.canSubmit == false)
    }

    @Test("submit() surfaces an error on failure and keeps the draft")
    func submitFailure() async {
        let client = MockAPIClient()
        client.stub(.getFeedback, response: [FeedbackDTO]())
        client.stubUnauthorized(for: .createFeedback)
        let vm = FeedbackViewModel(repository: FeedbackRepository(apiClient: client))

        vm.draftContent = "x"
        await vm.submit()

        #expect(vm.submitError != nil)
        #expect(vm.draftContent == "x") // Not cleared on failure
        #expect(vm.didSubmit == false)
    }

    // MARK: - toggleAddressed

    @Test("toggleAddressed flips locally and persists")
    func toggleHappy() async {
        let item = makeFeedback(id: "f1", addressed: false)
        let client = MockAPIClient()
        client.stub(.getFeedback, response: [item])
        client.handlers["/api/feedback/f1"] = { _ in Data("{}".utf8) }
        let vm = FeedbackViewModel(repository: FeedbackRepository(apiClient: client))
        await vm.load()

        await vm.toggleAddressed(item)
        #expect(vm.allFeedback.first(where: { $0.id == "f1" })?.addressed == true)
    }

    @Test("toggleAddressed rolls back on failure")
    func toggleRollback() async {
        let item = makeFeedback(id: "f1", addressed: false)
        let client = MockAPIClient()
        client.stub(.getFeedback, response: [item])
        client.stubUnauthorized(for: "/api/feedback/f1")
        let vm = FeedbackViewModel(repository: FeedbackRepository(apiClient: client))
        await vm.load()

        await vm.toggleAddressed(item)
        // After rollback, addressed is back to false.
        #expect(vm.allFeedback.first(where: { $0.id == "f1" })?.addressed == false)
    }
}
