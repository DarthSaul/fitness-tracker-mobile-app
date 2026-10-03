import SwiftUI

/// Progress tab: History and Analytics under one title, switched by a
/// segmented control. Provides the NavigationStack both sections push into.
struct ProgressTab: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        NavigationStack {
            ProgressScreen(
                historyViewModel: HistoryViewModel(
                    repository: HistoryRepository(apiClient: apiClient),
                    sessionManager: sessionManager
                ),
                analyticsViewModel: AnalyticsViewModel(
                    repository: AnalyticsRepository(apiClient: apiClient)
                ),
                workoutRepository: WorkoutRepository(apiClient: apiClient),
                standaloneRepository: StandaloneWorkoutRepository(apiClient: apiClient)
            )
        }
    }
}

private struct ProgressScreen: View {
    @Environment(TabSelection.self) private var tabSelection
    // Held here (not in the sections) so switching segments keeps each
    // section's loaded data instead of refetching from scratch.
    @State private var historyViewModel: HistoryViewModel
    @State private var analyticsViewModel: AnalyticsViewModel
    private let workoutRepository: WorkoutRepository
    private let standaloneRepository: StandaloneWorkoutRepository

    init(
        historyViewModel: HistoryViewModel,
        analyticsViewModel: AnalyticsViewModel,
        workoutRepository: WorkoutRepository,
        standaloneRepository: StandaloneWorkoutRepository
    ) {
        _historyViewModel = State(initialValue: historyViewModel)
        _analyticsViewModel = State(initialValue: analyticsViewModel)
        self.workoutRepository = workoutRepository
        self.standaloneRepository = standaloneRepository
    }

    var body: some View {
        @Bindable var tabSelection = tabSelection
        Group {
            switch tabSelection.progressSection {
            case .history:
                HistoryView(
                    viewModel: historyViewModel,
                    workoutRepository: workoutRepository,
                    standaloneRepository: standaloneRepository
                )
            case .analytics:
                AnalyticsView(viewModel: analyticsViewModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 8) {
                ScreenTitleHeader(title: "Progress", emoji: "📈")
                Picker("Section", selection: $tabSelection.progressSection) {
                    ForEach(ProgressSection.allCases) { section in
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
