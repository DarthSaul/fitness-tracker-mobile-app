import SwiftUI

/// Programs tab — wraps the program library list. PR #4 will replace
/// ProgramListView with the full library (filters, detail, week/day expansion).
struct ProgramsTab: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            ProgramListView(viewModel: makeViewModel())
        }
    }

    private func makeViewModel() -> ProgramListViewModel {
        let repo = ProgramRepository(apiClient: apiClient, modelContext: modelContext)
        return ProgramListViewModel(repository: repo, sessionManager: sessionManager)
    }
}
