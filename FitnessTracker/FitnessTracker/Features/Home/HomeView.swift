import SwiftUI

/// Composes the home dashboard: calendar strip, date header, today/scheduled
/// card, active program progress, and quick links. The tab provides the
/// NavigationStack — this view is content-only.
struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @State private var scheduleSheetPresented = false

    init(viewModel: HomeViewModel) {
        _viewModel = State(initialValue: viewModel)
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
                    ActiveProgramProgressCard(viewModel: viewModel)
                        .padding(.horizontal)

                    sectionHeader("My Fitness")
                    HomeQuickLinksRow()
                        .padding(.horizontal)
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
        .navigationTitle("Home")
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.top, 8)
    }
}
