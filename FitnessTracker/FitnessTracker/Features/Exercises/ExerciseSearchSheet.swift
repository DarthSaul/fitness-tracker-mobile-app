import SwiftUI

/// Inner search-and-pick component (no NavigationStack / toolbar of its own).
/// Extracted from `ExerciseSearchSheet` so other sheets can host the same
/// search experience inside their own stable `NavigationStack`, which avoids
/// the `_UIReparentingView` warning that comes from swapping one root
/// `NavigationStack` for another inside a single SwiftUI sheet.
struct ExerciseSearchList: View {
    /// Optional copy shown above the list when the query is empty.
    let subtitle: String?
    /// Sync callback — the host decides what to do with the picked exercise
    /// (e.g. dismiss its sheet, advance to a confirmation step).
    let onPick: (ExerciseDTO) -> Void

    @Environment(APIClient.self) private var apiClient

    @State private var query: String = ""
    @State private var results: [ExerciseDTO] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        content
            .searchable(text: $query, prompt: "Search exercises")
            .onChange(of: query) { _, newValue in
                scheduleSearch(query: newValue)
            }
            .task {
                await runSearch(query: "")
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
                        onPick(exercise)
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

/// Searchable exercise picker presented as a sheet on its own. Wraps
/// `ExerciseSearchList` in a NavigationStack with a Cancel toolbar item.
struct ExerciseSearchSheet: View {
    let title: String
    let subtitle: String?
    let onPick: (ExerciseDTO) async -> Void

    @Environment(\.dismiss) private var dismiss

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
            ExerciseSearchList(subtitle: subtitle) { exercise in
                Task {
                    await onPick(exercise)
                    dismiss()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
