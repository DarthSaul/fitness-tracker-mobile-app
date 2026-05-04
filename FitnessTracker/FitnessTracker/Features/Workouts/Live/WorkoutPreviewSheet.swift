import SwiftUI

/// Read-only preview of all template exercises and sets for the day.
/// Reused by the live-workout view (Preview menu) and could be wired into
/// HomeTodayCard's preview button. Server pre-applies swaps to `day`, so
/// this view just renders what's there.
struct WorkoutPreviewSheet: View {
    let day: ProgramDayDTO?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Workout preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
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
                            ExerciseRows(exercise: exercise)
                        }
                    } header: {
                        Text(group.type == .superset ? "Superset" : "Standard")
                    }
                }
            }
        } else {
            ContentUnavailableView("Nothing to preview", systemImage: "eye.slash")
        }
    }
}

private struct ExerciseRows: View {
    let exercise: ProgramExerciseDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise.exercise.name).font(.headline)
            ForEach(exercise.sets, id: \.id) { templateSet in
                HStack {
                    Text("Set \(templateSet.setNumber)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatSet(reps: templateSet.reps, weight: templateSet.weight, rpe: templateSet.rpe))
                        .font(.subheadline.monospacedDigit())
                }
            }
        }
        .padding(.vertical, 4)
    }
}
