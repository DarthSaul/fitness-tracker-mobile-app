import SwiftUI

/// Composes the home dashboard: calendar strip, date header, today/scheduled
/// card, Strength on the Go, and the FRIENDS section. Program progress and
/// management live in the Program tab. The tab provides the NavigationStack —
/// this view is content-only.
struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @State private var friends: HomeFriendsViewModel?
    @State private var scheduleSheetPresented = false
    @Environment(LiveWorkoutPresentation.self) private var liveWorkout
    @Environment(ProgramRunChanges.self) private var runChanges
    @Environment(SocialContext.self) private var socialContext
    private let workoutRepository: WorkoutRepository
    private let standaloneRepository: StandaloneWorkoutRepository

    init(
        viewModel: HomeViewModel,
        workoutRepository: WorkoutRepository,
        standaloneRepository: StandaloneWorkoutRepository
    ) {
        _viewModel = State(initialValue: viewModel)
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
                    } else if !viewModel.completedEntriesForSelectedDate.isEmpty {
                        // Past date with completed workout(s) → one card per
                        // session (a program and a standalone can share a day).
                        VStack(spacing: 12) {
                            ForEach(viewModel.completedEntriesForSelectedDate) { entry in
                                HomeCompletedCard(
                                    viewModel: viewModel,
                                    entry: entry,
                                    workoutRepository: workoutRepository,
                                    standaloneRepository: standaloneRepository
                                )
                            }
                        }
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

                StrengthOnTheGoCard(
                    standaloneRepository: standaloneRepository,
                    workoutRepository: workoutRepository
                )
                .padding(.horizontal)

                if let friends {
                    HomeFriendsSection(viewModel: friends)
                        .padding(.top, 6)
                }

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
        .task {
            if friends == nil { friends = HomeFriendsViewModel(context: socialContext) }
            async let home: Void = viewModel.load()
            async let friendsPosts: Void = friends?.load() ?? ()
            _ = await (home, friendsPosts)
        }
        .refreshable {
            async let home: Void = viewModel.load()
            async let friendsPosts: Void = friends?.load() ?? ()
            _ = await (home, friendsPosts)
        }
        // Refresh on transitions of the live-workout sheet so the today card
        // flips back from "Resume workout" to "Start next workout" after the
        // user completes or abandons a session.
        .onChange(of: liveWorkout.isPresented) { wasPresented, isPresented in
            if wasPresented && !isPresented {
                Task { await viewModel.load() }
            }
        }
        // The run changed (activated / paused / ended, possibly from the
        // Program tab). Activate can hand back a different run id, so refetch
        // rather than keep anything loaded under the previous one.
        .onChange(of: runChanges.revision) {
            Task { await viewModel.load() }
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
