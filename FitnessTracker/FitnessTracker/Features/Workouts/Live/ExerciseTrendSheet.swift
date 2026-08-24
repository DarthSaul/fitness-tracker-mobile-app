import SwiftUI

/// Quick reference sheet showing recent session history for an exercise.
/// Backed by GET /api/analytics/exercises/:id (the same endpoint M8's
/// Analytics tab uses for the e1RM chart). The server returns history in
/// chronological order for the chart; this sheet sorts most-recent-first.
struct ExerciseTrendSheet: View {
    let exerciseId: String
    let exerciseName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var apiClient

    @State private var history: AnalyticsExerciseHistoryDTO?
    @State private var isLoading = false
    @State private var loadError: String?

    private var sortedHistory: [AnalyticsExerciseHistoryDTO.SessionEntry] {
        history?.history.sorted { $0.completedAt > $1.completedAt } ?? []
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(exerciseName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
                .task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && history == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            ContentUnavailableView(
                "Couldn't load history",
                systemImage: "exclamationmark.triangle",
                description: Text(loadError)
            )
        } else if let history, !history.history.isEmpty {
            List {
                Section {
                    Text("Last \(history.history.count) session\(history.history.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(sortedHistory) { entry in
                    SessionRow(entry: entry)
                }
            }
        } else {
            ContentUnavailableView(
                "No history yet",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("Log this exercise in a workout to start tracking.")
            )
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let dto: AnalyticsExerciseHistoryDTO = try await apiClient.send(.getAnalyticsExercise(id: exerciseId))
            history = dto
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct SessionRow: View {
    let entry: AnalyticsExerciseHistoryDTO.SessionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(formattedDate)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let contextLabel = entry.contextLabel {
                    Text(contextLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(Array(entry.sets.enumerated()), id: \.offset) { _, sessionSet in
                HStack {
                    Text(setLine(sessionSet))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let e1rm = sessionSet.e1rm {
                        Text("e1RM \(formatDouble(e1rm))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            if let bestE1rm = entry.bestE1rm {
                Text("Best e1RM: \(formatDouble(bestE1rm))")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: entry.completedAt)
    }

    private func setLine(_ s: AnalyticsExerciseHistoryDTO.SessionSet) -> String {
        var parts: [String] = []
        if let reps = s.reps { parts.append("\(reps) reps") }
        if let weight = s.weight { parts.append("\(formatDouble(weight)) lb") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}
