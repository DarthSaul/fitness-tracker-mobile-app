import SwiftUI
import Charts

/// Analytics dashboard. Mirrors the Vue page:
///   1. Three-up stat tiles (sessions, this-week, total volume).
///   2. Collapsible "What is e1RM?" explainer.
///   3. Searchable exercise selector → presents a sheet with a search list.
///   4. Selected-exercise detail: e1RM sparkline (Swift Charts, tap-to-label)
///      and a reverse-chronological session list.
///
/// The tab provides the NavigationStack — this view is content-only.
struct AnalyticsView: View {
    @State private var viewModel: AnalyticsViewModel
    @State private var isE1rmInfoOpen = false
    @State private var isSelectorPresented = false

    init(viewModel: AnalyticsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statsGrid
                e1rmExplainer
                exerciseSelector
                exerciseDetail
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .navigationTitle("Analytics")
        .task { await viewModel.load() }
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

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Strength progress")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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

    private var e1rmExplainer: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isE1rmInfoOpen.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.tint)
                    Text("What is e1RM?")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: isE1rmInfoOpen ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isE1rmInfoOpen {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Estimated 1-Rep Max (e1RM) is a way to estimate the maximum weight you could lift for a single rep, based on any set you actually performed.")
                    HStack(spacing: 4) {
                        Text("Formula:")
                        Text("e1RM = weight × (1 + reps ÷ 30)")
                            .font(.caption.monospaced())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .font(.footnote)
                    Text("This is the Epley formula — one of the most widely used estimates in strength training.")
                    Text("Why it matters: programs use different rep ranges across phases (e.g. 5×5 one month, 3×12 the next). Average weight would drop as reps go up, even if you're getting stronger. e1RM normalizes this so the trend reflects true progress.")
                    Text("Note: less accurate above ~15 reps; most meaningful for compound barbell movements.")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.tint)
                .frame(width: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Exercise selector

    @ViewBuilder
    private var exerciseSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exercise")
                .font(.caption)
                .foregroundStyle(.secondary)

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
                        HistoryDetail(history: history)
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

    static func formatE1rm(_ value: Double) -> String {
        "\(Int(value.rounded())) lbs"
    }

    static func formatSessionDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
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

private struct HistoryDetail: View {
    let history: AnalyticsExerciseHistoryDTO

    private var chartPoints: [AnalyticsExerciseHistoryDTO.SessionEntry] {
        history.history.filter { $0.bestE1rm != nil }
    }

    private var displayHistory: [AnalyticsExerciseHistoryDTO.SessionEntry] {
        history.history.reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(history.exercise.name)
                .font(.headline)

            if history.history.isEmpty {
                Text("No completed sessions found for this exercise")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            } else {
                if !chartPoints.isEmpty {
                    E1rmSparkline(points: chartPoints)
                }
                LazyVStack(spacing: 8) {
                    ForEach(displayHistory) { session in
                        SessionRow(session: session)
                    }
                }
            }
        }
    }
}

private struct SessionRow: View {
    let session: AnalyticsExerciseHistoryDTO.SessionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(AnalyticsView.formatSessionDate(session.completedAt))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(session.sets.count) \(session.sets.count == 1 ? "set" : "sets")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Label {
                    Text("e1RM: \(session.bestE1rm.map(AnalyticsView.formatE1rm) ?? "—")")
                } icon: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                }
                .labelStyle(.titleOnly)
                .foregroundStyle(.tint)

                Label {
                    Text("Vol: \(session.totalVolume.map { "\(AnalyticsView.formatVolume($0)) lbs" } ?? "—")")
                } icon: {
                    Image(systemName: "scalemass")
                }
                .labelStyle(.titleOnly)
                .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Sparkline

/// Swift Charts e1RM sparkline. Tapping a point pins a label that sits above
/// the marker showing weight + session date; tapping the same point clears it.
private struct E1rmSparkline: View {
    let points: [AnalyticsExerciseHistoryDTO.SessionEntry]
    @State private var selectedSessionId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("e1RM Trend")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    let value = point.bestE1rm ?? 0
                    LineMark(
                        x: .value("Session", index),
                        y: .value("e1RM", value)
                    )
                    .foregroundStyle(.tint)
                    .interpolationMethod(.linear)

                    PointMark(
                        x: .value("Session", index),
                        y: .value("e1RM", value)
                    )
                    .foregroundStyle(.tint)
                    .symbolSize(selectedSessionId == point.id ? 120 : 60)

                    if selectedSessionId == point.id {
                        PointMark(
                            x: .value("Session", index),
                            y: .value("e1RM", value)
                        )
                        .annotation(position: .top, alignment: .center, spacing: 4) {
                            VStack(spacing: 2) {
                                Text(AnalyticsView.formatE1rm(value))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tint)
                                Text(AnalyticsView.formatSessionDate(point.completedAt))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 96)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { value in
                                    handleTap(at: value.location, proxy: proxy, geometry: geo)
                                }
                        )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private func handleTap(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        let xInPlot = location.x - frame.origin.x
        guard xInPlot >= 0, xInPlot <= frame.width else {
            selectedSessionId = nil
            return
        }
        guard let xValue: Double = proxy.value(atX: xInPlot) else { return }

        let nearest = points.enumerated().min(by: { lhs, rhs in
            abs(Double(lhs.offset) - xValue) < abs(Double(rhs.offset) - xValue)
        })
        guard let chosen = nearest?.element else { return }

        if selectedSessionId == chosen.id {
            selectedSessionId = nil
        } else {
            selectedSessionId = chosen.id
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
