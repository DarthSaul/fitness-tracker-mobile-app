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

    var body: some View {
        let programRepo = ProgramRepository(apiClient: apiClient, modelContext: modelContext)
        let userProgramRepo = UserProgramRepository(apiClient: apiClient)
        NavigationStack {
            ProgramScreen(
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
}

private struct ProgramScreen: View {
    @Environment(TabSelection.self) private var tabSelection
    @Environment(ProgramRunChanges.self) private var runChanges
    // Held here (not in the sections) so switching segments keeps each
    // section's loaded data.
    @State private var listViewModel: ProgramListViewModel
    @State private var flowViewModel: ProgramFlowViewModel
    private let programRepository: ProgramRepository
    private let workoutRepository: WorkoutRepository

    init(
        listViewModel: ProgramListViewModel,
        flowViewModel: ProgramFlowViewModel,
        programRepository: ProgramRepository,
        workoutRepository: WorkoutRepository
    ) {
        _listViewModel = State(initialValue: listViewModel)
        _flowViewModel = State(initialValue: flowViewModel)
        self.programRepository = programRepository
        self.workoutRepository = workoutRepository
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
                    onExplore: { tabSelection.programSection = .explore }
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
    }
}
