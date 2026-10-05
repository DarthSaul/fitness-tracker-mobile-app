import SwiftUI
import SwiftData

/// Program tab: Manage (the active run) and Explore (the program library)
/// under one title, switched by a segmented control — the same treatment as
/// the Progress tab. Provides the NavigationStack both sections push into.
struct ProgramTab: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.modelContext) private var modelContext
    @Environment(ProgramRunChanges.self) private var runChanges
    /// Built once, on first appearance (environment values aren't available
    /// in `init`), so body re-evaluations don't allocate throwaway instances.
    @State private var dependencies: ProgramScreen.Dependencies?

    var body: some View {
        NavigationStack {
            if let dependencies {
                ProgramScreen(dependencies: dependencies)
            }
        }
        .onAppear {
            if dependencies == nil { dependencies = makeDependencies() }
        }
    }

    private func makeDependencies() -> ProgramScreen.Dependencies {
        let programRepo = ProgramRepository(apiClient: apiClient, modelContext: modelContext)
        let userProgramRepo = UserProgramRepository(apiClient: apiClient)
        return ProgramScreen.Dependencies(
            listViewModel: ProgramListViewModel(
                programRepository: programRepo,
                userProgramRepository: userProgramRepo,
                sessionManager: sessionManager,
                onRunChanged: { [runChanges] in runChanges.notify() }
            ),
            flowViewModel: ProgramFlowViewModel(
                homeRepository: HomeRepository(apiClient: apiClient),
                userProgramRepository: userProgramRepo,
                sessionManager: sessionManager
            ),
            programRepository: programRepo,
            workoutRepository: WorkoutRepository(apiClient: apiClient)
        )
    }
}

private struct ProgramScreen: View {
    /// Everything the screen needs, created once by ProgramTab. The view
    /// models live here (not in the sections) so switching segments keeps
    /// each section's loaded data.
    struct Dependencies {
        let listViewModel: ProgramListViewModel
        let flowViewModel: ProgramFlowViewModel
        let programRepository: ProgramRepository
        let workoutRepository: WorkoutRepository
    }

    @Environment(TabSelection.self) private var tabSelection
    @Environment(ProgramRunChanges.self) private var runChanges
    private let listViewModel: ProgramListViewModel
    private let flowViewModel: ProgramFlowViewModel
    private let programRepository: ProgramRepository
    private let workoutRepository: WorkoutRepository

    init(dependencies: Dependencies) {
        listViewModel = dependencies.listViewModel
        flowViewModel = dependencies.flowViewModel
        programRepository = dependencies.programRepository
        workoutRepository = dependencies.workoutRepository
    }

    var body: some View {
        @Bindable var tabSelection = tabSelection
        Group {
            switch tabSelection.programSection {
            case .manage:
                ProgramFlowView(
                    viewModel: flowViewModel,
                    workoutRepository: workoutRepository,
                    // Ending the run deletes its scheduled workouts and any
                    // in-progress session server-side; signal the change so
                    // Home and the resume banner stop showing them.
                    onProgramEnded: { runChanges.notify() },
                    onExplore: { tabSelection.programSection = .explore },
                    programInfo: programInfo(programId:)
                )
            case .explore:
                ProgramListView(viewModel: listViewModel, programRepository: programRepository)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 8) {
                ScreenTitleHeader(title: "Program", emoji: "🏋️")
                Picker("Section", selection: $tabSelection.programSection) {
                    ForEach(ProgramSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
            .background(Color(.systemBackground))
        }
        .toolbar(.hidden, for: .navigationBar)
        // Manage's Info chip opens a program from the library, so load it
        // even if Explore hasn't been opened yet.
        .task {
            if listViewModel.programs.isEmpty { await listViewModel.load() }
        }
    }

    /// The program's info page, as Explore opens it. Nil until the library
    /// has loaded (the chip stays hidden until then).
    private func programInfo(programId: String) -> ProgramDetailView? {
        guard let program = listViewModel.programs.first(where: { $0.id == programId }) else { return nil }
        return ProgramDetailView(program: program, listViewModel: listViewModel, repository: programRepository)
    }
}
