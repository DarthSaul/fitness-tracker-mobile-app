import SwiftUI

/// Full-list workout history: the History section of the Progress tab, which
/// provides the NavigationStack and the screen title.
/// Program and standalone completions interleave chronologically (unified
/// GET /api/history); rows push the matching detail view for their type.
struct HistoryView: View {
    @State private var viewModel: HistoryViewModel
    private let workoutRepository: WorkoutRepository
    private let standaloneRepository: StandaloneWorkoutRepository

    init(
        viewModel: HistoryViewModel,
        workoutRepository: WorkoutRepository,
        standaloneRepository: StandaloneWorkoutRepository
    ) {
        _viewModel = State(initialValue: viewModel)
        self.workoutRepository = workoutRepository
        self.standaloneRepository = standaloneRepository
    }

    var body: some View {
        content
            .task { if viewModel.sessions.isEmpty { await viewModel.load() } }
            .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.sessions.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.sessions.isEmpty {
            // Surface the load error rather than falling through to a generic
            // "no workouts yet" empty state — otherwise a fetch failure looks
            // identical to a brand-new account with no history.
            if let loadError = viewModel.loadError {
                ContentUnavailableView(
                    "Couldn't load history",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError.localizedDescription)
                )
            } else {
                ContentUnavailableView(
                    "No workouts yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Completed workouts will show up here.")
                )
            }
        } else {
            ScrollViewReader { proxy in
                List {
                    Section {
                        WorkoutMonthCalendarCard(
                            workoutCalendar: viewModel.workoutCalendar,
                            displayedMonth: $viewModel.displayedMonth,
                            selectedDay: viewModel.selectedDay
                        ) { day in
                            Task {
                                if let id = await viewModel.reveal(day: day) {
                                    withAnimation { proxy.scrollTo(id, anchor: .top) }
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }

                    Section {
                        ForEach(viewModel.sessions) { entry in
                            NavigationLink {
                                HistoryEntryDestination(
                                    entry: entry,
                                    workoutRepository: workoutRepository,
                                    standaloneRepository: standaloneRepository,
                                    onChange: { Task { await viewModel.load() } }
                                )
                            } label: {
                                HistoryRow(entry: entry)
                            }
                            .id(entry.id)
                            .onAppear {
                                if entry.id == viewModel.sessions.last?.id, !viewModel.isLoadingMore {
                                    Task { await viewModel.loadMore() }
                                }
                            }
                        }

                        if viewModel.isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        }

                        if let loadError = viewModel.loadError {
                            Text(loadError.localizedDescription)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                // 16pt from the section control to the calendar, and between
                // the calendar and the list — the same rhythm as Program.
                .contentMargins(.top, 12, for: .scrollContent)
                .listSectionSpacing(16)
            }
        }
    }
}
