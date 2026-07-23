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
    private let standaloneRepository: StandaloneWorkoutRepository

    init(
        viewModel: HomeViewModel,
        homeRepository: HomeRepository,
        workoutRepository: WorkoutRepository,
        standaloneRepository: StandaloneWorkoutRepository
    ) {
        _viewModel = State(initialValue: viewModel)
        self.homeRepository = homeRepository
        self.workoutRepository = workoutRepository
        self.standaloneRepository = standaloneRepository
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenTitleHeader(title: "Home", emoji: "💪")

                CalendarStripView(
                    selectedDate: Binding(
                        get: { viewModel.selectedDate },
                        set: { viewModel.selectedDate = $0 }
                    ),
                    scheduledDateKeys: viewModel.scheduledDateKeys,
                    completedDateKeys: viewModel.completedDateKeys
                )

                Text(formattedSelectedDate)
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal)

                Group {
                    if viewModel.isViewingToday {
                        HomeTodayCard(viewModel: viewModel)
                    } else if let completed = viewModel.completedSessionForSelectedDate {
                        // Past date with a completed workout → show a preview.
                        HomeCompletedCard(
                            viewModel: viewModel,
                            session: completed,
                            workoutRepository: workoutRepository
                        )
                    } else if viewModel.isSelectedDateInFuture {
                        // Future date → scheduling lives here.
                        HomeScheduledCard(viewModel: viewModel) {
                            scheduleSheetPresented = true
                        }
                    } else {
                        // Past date with nothing completed → neutral placeholder.
                        HomeNoWorkoutCard()
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

                StrengthOnTheGoCard(
                    standaloneRepository: standaloneRepository,
                    workoutRepository: workoutRepository
                )
                .padding(.horizontal)

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
        .scrollingTitleChrome(title: "Home")
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
