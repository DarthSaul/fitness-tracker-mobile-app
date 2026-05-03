import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.modelContext) private var modelContext
    @Environment(APIClient.self) private var apiClient

    var body: some View {
        switch sessionManager.authState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .unauthenticated:
            AuthView(viewModel: makeAuthViewModel())

        case .authenticated:
            ProgramListView(viewModel: makeProgramListViewModel())
        }
    }

    // MARK: - Factory Helpers
    private func makeAuthViewModel() -> AuthViewModel {
        let repo = AuthRepository(apiClient: apiClient, sessionManager: sessionManager)
        return AuthViewModel(repository: repo, sessionManager: sessionManager)
    }

    private func makeProgramListViewModel() -> ProgramListViewModel {
        let repo = ProgramRepository(apiClient: apiClient, modelContext: modelContext)
        return ProgramListViewModel(repository: repo, sessionManager: sessionManager)
    }
}
