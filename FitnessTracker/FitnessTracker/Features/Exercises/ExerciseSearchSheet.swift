import SwiftUI

/// Searchable exercise picker. Issues a debounced GET /api/exercises?search=
/// as the user types and surfaces results in a list. Tap a result → invoke
/// `onPick` (caller closes the sheet on its own — sheet only dismisses on
/// the explicit Cancel button).
///
/// Reused for two flows in M7:
///   1. Adding an ad-hoc exercise to a live workout
///   2. Picking the replacement in ExerciseSwapSheet (which wraps this view)
struct ExerciseSearchSheet: View {
    let title: String
    let subtitle: String?
    let onPick: (ExerciseDTO) async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var apiClient

    @State private var query: String = ""
    @State private var results: [ExerciseDTO] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var searchTask: Task<Void, Never>?

    init(
        title: String,
        subtitle: String? = nil,
        onPick: @escaping (ExerciseDTO) async -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .searchable(text: $query, prompt: "Search exercises")
                .onChange(of: query) { _, newValue in
                    scheduleSearch(query: newValue)
                }
                .task {
                    // Initial load with empty query so the user sees something
                    // before they start typing.
                    await runSearch(query: "")
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && results.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            ContentUnavailableView(
                "Couldn't load exercises",
                systemImage: "exclamationmark.triangle",
                description: Text(loadError)
            )
        } else {
            List {
                if let subtitle, query.isEmpty {
                    Section { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
                }
                ForEach(results) { exercise in
                    Button {
                        Task {
                            await onPick(exercise)
                            dismiss()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name).foregroundStyle(.primary)
                            if let description = exercise.description, !description.isEmpty {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if !isLoading && results.isEmpty && !query.isEmpty {
                    Text("No matches for \"\(query)\".")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Search

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)  // 0.3s debounce
            if Task.isCancelled { return }
            await runSearch(query: query)
        }
    }

    private func runSearch(query: String) async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let exercises: [ExerciseDTO] = try await apiClient.send(
                .getExercises(search: trimmed.isEmpty ? nil : trimmed)
            )
            self.results = exercises
        } catch {
            loadError = error.localizedDescription
        }
    }
}
