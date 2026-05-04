import SwiftUI

struct ProgramDayDetailView: View {
    let dayId: String
    let dayNumber: Int
    private let repository: ProgramRepository

    @Environment(\.dismiss) private var dismiss
    @State private var day: ProgramDayDTO?
    @State private var isLoading = false
    @State private var loadError: Error?

    init(dayId: String, dayNumber: Int, repository: ProgramRepository) {
        self.dayId = dayId
        self.dayNumber = dayNumber
        self.repository = repository
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(navigationTitle)
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
        if let day {
            List {
                if let warmUp = day.warmUp, !warmUp.isEmpty {
                    Section("Warm-up") { Text(warmUp) }
                }
                ForEach(day.exerciseGroups, id: \.id) { group in
                    Section {
                        ForEach(group.exercises, id: \.id) { exercise in
                            ExerciseBlock(exercise: exercise)
                        }
                    } header: {
                        groupHeader(group)
                    }
                }
            }
        } else if isLoading {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            ContentUnavailableView(
                "Couldn't load day",
                systemImage: "exclamationmark.triangle",
                description: Text(loadError.localizedDescription)
            )
        }
    }

    private var navigationTitle: String {
        if let name = day?.name, !name.isEmpty {
            return name
        }
        return "Day \(dayNumber)"
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            day = try await repository.fetchProgramDay(id: dayId)
        } catch {
            loadError = error
        }
    }

    @ViewBuilder
    private func groupHeader(_ group: ExerciseGroupDTO) -> some View {
        HStack {
            Text(groupTypeLabel(group.type))
            if let rest = group.restSeconds, rest > 0 {
                Spacer()
                Text("Rest \(rest)s")
            }
        }
    }

    private func groupTypeLabel(_ type: ExerciseGroupType) -> String {
        switch type {
        case .standard: return "Standard"
        case .superset: return "Superset"
        }
    }
}

// MARK: - Exercise Block
private struct ExerciseBlock: View {
    let exercise: ProgramExerciseDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise.exercise.name)
                .font(.headline)
            ForEach(exercise.sets, id: \.id) { set in
                HStack {
                    Text("Set \(set.setNumber)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(setSummary(set))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.primary)
                }
            }
            if let notes = exercise.sets.first?.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func setSummary(_ set: ExerciseSetDTO) -> String {
        var parts: [String] = []
        if let reps = set.reps {
            parts.append("\(reps) reps")
        }
        if let weight = set.weight {
            parts.append(formatWeight(weight))
        }
        if let rpe = set.rpe {
            parts.append("RPE \(formatRPE(rpe))")
        }
        if parts.isEmpty, let target = set.effortTarget, !target.isEmpty {
            return target
        }
        return parts.joined(separator: " · ")
    }

    private func formatWeight(_ w: Double) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        let n = formatter.string(from: NSNumber(value: w)) ?? "\(w)"
        return "\(n) lb"
    }

    private func formatRPE(_ r: Double) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: r)) ?? "\(r)"
    }
}
