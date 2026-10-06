import SwiftUI
import Charts

/// Progress → Overview:
///   1. Three-up stat tiles (sessions, this week, total volume).
///   2. Weekly volume (completed workouts per local week).
///   3. Searchable exercise selector, with an ⓘ explaining e1RM.
///   4. The selected exercise's detail: e1RM card with chart and range
///      picker, best set, and recent sessions.
///
/// The Progress tab provides the NavigationStack and the screen title — this
/// view is content-only.
struct AnalyticsView: View {
    @State private var viewModel: AnalyticsViewModel
    @State private var isE1rmInfoOpen = false
    @State private var isSelectorPresented = false

    init(viewModel: AnalyticsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                statsGrid
                WeeklyVolumeCard(weeks: viewModel.weeklyVolume, errorMessage: weeklyVolumeError)
                exerciseSelector
                    .padding(.top, 10)
                exerciseDetail
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        // Switching back to the Analytics section re-runs `.task`; skip the
        // reload once every load has succeeded. Pull-to-refresh always reloads.
        .task {
            if !viewModel.hasLoaded {
                await viewModel.load()
            }
        }
        .refreshable { await viewModel.load() }
        .sheet(isPresented: $isSelectorPresented) {
            AnalyticsExercisePicker(
                exercises: viewModel.exercises,
                selectedId: viewModel.selectedExerciseId
            ) { picked in
                viewModel.selectExercise(picked.id)
            }
        }
    }

    private var weeklyVolumeError: String? {
        if case .error(let message) = viewModel.weeklyVolumeStatus { return message }
        return nil
    }

    // MARK: - Stats grid

    @ViewBuilder
    private var statsGrid: some View {
        switch viewModel.dashboardStatus {
        case .pending, .idle:
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    StatTile.placeholder
                }
            }
        case .error(let message):
            Text("Couldn't load stats: \(message)")
                .font(.footnote)
                .foregroundStyle(.red)
        case .success:
            if let dash = viewModel.dashboard {
                HStack(spacing: 12) {
                    StatTile(
                        systemImage: "calendar.badge.checkmark",
                        value: "\(dash.totalSessions)",
                        label: "Sessions"
                    )
                    StatTile(
                        systemImage: "calendar",
                        value: "\(dash.sessionsThisWeek)",
                        label: "this week"
                    )
                    StatTile(
                        systemImage: "scalemass",
                        value: AnalyticsView.formatVolume(dash.totalVolumeLbs),
                        label: "lbs total"
                    )
                }
            }
        }
    }

    // MARK: - e1RM explainer

    /// The ⓘ next to the Exercise heading: opens the explainer as a bottom
    /// sheet at half height (drag up for the rest).
    private var e1rmInfoButton: some View {
        Button {
            isE1rmInfoOpen = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 17))
                .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What is e1RM?")
        .sheet(isPresented: $isE1rmInfoOpen) {
            E1rmInfoSheet()
        }
    }

    // MARK: - Exercise selector

    @ViewBuilder
    private var exerciseSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Exercise · e1RM")
                    .font(.system(size: 17, weight: .semibold))
                e1rmInfoButton
            }

            switch viewModel.exercisesStatus {
            case .pending, .idle:
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: 44)
            case .error(let message):
                Text("Failed to load exercises: \(message)")
                    .font(.footnote)
                    .foregroundStyle(.red)
            case .success:
                if viewModel.exercises.isEmpty {
                    Text("No exercises tracked yet. Complete some workouts to see your exercises here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Button {
                        isSelectorPresented = true
                    } label: {
                        HStack {
                            Text(selectedExerciseName ?? "Choose an exercise…")
                                .foregroundStyle(selectedExerciseName == nil ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var selectedExerciseName: String? {
        guard let id = viewModel.selectedExerciseId else { return nil }
        return viewModel.exercises.first(where: { $0.id == id })?.name
    }

    // MARK: - Exercise detail

    @ViewBuilder
    private var exerciseDetail: some View {
        if viewModel.selectedExerciseId == nil {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                switch viewModel.historyStatus {
                case .idle, .pending:
                    HistoryPlaceholder()
                case .error(let message):
                    Text("Couldn't load history: \(message)")
                        .font(.footnote)
                        .foregroundStyle(.red)
                case .success:
                    if let history = viewModel.exerciseHistory {
                        ExerciseTrendDetail(history: history)
                    }
                }
            }
        }
    }

    // MARK: - Formatters

    static func formatVolume(_ lbs: Double) -> String {
        if lbs >= 1000 {
            return String(format: "%.1fk", lbs / 1000)
        }
        return String(format: "%.0f", lbs)
    }
}

// MARK: - Stat tile

private struct StatTile: View {
    let systemImage: String
    let value: String
    let label: String

    static let placeholder = StatTile(systemImage: "circle.dashed", value: "—", label: "")

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.tint)
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - e1RM explainer sheet

private struct E1rmInfoSheet: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("What is e1RM?")
                    .font(.title3.weight(.semibold))
                Text("Estimated 1-Rep Max (e1RM) is a way to estimate the maximum weight you could lift for a single rep, based on any set you actually performed.")
                HStack(spacing: 4) {
                    Text("Formula:")
                    Text("e1RM = weight × (1 + reps ÷ 30)")
                        .font(.caption.monospaced())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                }
                Text("This is the Epley formula — one of the most widely used estimates in strength training.")
                Text("Why it matters: programs use different rep ranges across phases (e.g. 5×5 one month, 3×12 the next). Average weight would drop as reps go up, even if you're getting stronger. e1RM normalizes this so the trend reflects true progress.")
                Text("Note: less accurate above ~15 reps; most meaningful for compound barbell movements.")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - History detail

private struct HistoryPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 96)
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.10))
                    .frame(height: 56)
            }
        }
    }
}

// MARK: - Exercise picker sheet

/// Searchable list of analytics exercises. Reuses the native `.searchable`
/// idiom rather than porting Vue's USelectMenu — this is the iOS equivalent.
private struct AnalyticsExercisePicker: View {
    let exercises: [AnalyticsExerciseDTO]
    let selectedId: String?
    let onPick: (AnalyticsExerciseDTO) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [AnalyticsExerciseDTO] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return exercises }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { exercise in
                    Button {
                        onPick(exercise)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name)
                                    .foregroundStyle(.primary)
                                Text("\(exercise.sessionCount) \(exercise.sessionCount == 1 ? "session" : "sessions")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if exercise.id == selectedId {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
            .navigationTitle("Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
