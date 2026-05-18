import SwiftUI

/// Composes the home dashboard: calendar strip, date header, today/scheduled
/// card, active program progress, and quick links. The tab provides the
/// NavigationStack — this view is content-only.
struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @State private var scheduleSheetPresented = false
    @Environment(LiveWorkoutPresentation.self) private var liveWorkout
    private let homeRepository: HomeRepository
    private let workoutRepository: WorkoutRepository

    init(viewModel: HomeViewModel, homeRepository: HomeRepository, workoutRepository: WorkoutRepository) {
        _viewModel = State(initialValue: viewModel)
        self.homeRepository = homeRepository
        self.workoutRepository = workoutRepository
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CalendarStripView(
                    selectedDate: Binding(
                        get: { viewModel.selectedDate },
                        set: { viewModel.selectedDate = $0 }
                    ),
                    scheduledDateKeys: viewModel.scheduledDateKeys
                )

                Text(formattedSelectedDate)
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal)

                Group {
                    if viewModel.isViewingToday {
                        HomeTodayCard(viewModel: viewModel)
                    } else {
                        HomeScheduledCard(viewModel: viewModel) {
                            scheduleSheetPresented = true
                        }
                    }
                }
                .padding(.horizontal)

                if viewModel.hasActiveProgram {
                    ActiveProgramProgressCard(
                        viewModel: viewModel,
                        homeRepository: homeRepository,
                        workoutRepository: workoutRepository
                    )
                    .padding(.horizontal)
                }

                HomeRecentHistorySection(
                    recentHistory: viewModel.recentHistory,
                    workoutRepository: workoutRepository,
                    hasLoadedOnce: viewModel.hasLoadedOnce
                )

                if let loadError = viewModel.loadError {
                    Text(loadError.localizedDescription)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical, 12)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenTitleHeader(title: "Home", emoji: "💪")
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        // Refresh on transitions of the live-workout sheet so the today card
        // flips back from "Resume workout" to "Start next workout" after the
        // user completes or abandons a session.
        .onChange(of: liveWorkout.isPresented) { wasPresented, isPresented in
            if wasPresented && !isPresented {
                Task { await viewModel.load() }
            }
        }
        .sheet(isPresented: $scheduleSheetPresented) {
            ScheduleWorkoutSheet(viewModel: viewModel)
        }
    }

    private var formattedSelectedDate: String {
        if viewModel.isViewingToday {
            let f = DateFormatter(); f.dateFormat = "MMM d"
            return "Today, \(f.string(from: viewModel.selectedDate))"
        }
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"
        return f.string(from: viewModel.selectedDate)
    }
}
