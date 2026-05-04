import SwiftUI
import SwiftData

struct ProgramsTab: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let programRepo = ProgramRepository(apiClient: apiClient, modelContext: modelContext)
        let userProgramRepo = UserProgramRepository(apiClient: apiClient)
        let viewModel = ProgramListViewModel(
            programRepository: programRepo,
            userProgramRepository: userProgramRepo,
            sessionManager: sessionManager
        )
        NavigationStack {
            ProgramListView(viewModel: viewModel, programRepository: programRepo)
                .settingsToolbarItem()
        }
    }
}
