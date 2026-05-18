import SwiftUI

/// Workout-level notes editor, presented as a short pull-up drawer from the
/// "Notes" action. Distinct from per-exercise notes (the Notes chip) and the
/// removed per-set notes — this is the session's single `notes` field
/// (PATCH /api/workouts/:id). Starts shorter than the Log-set drawer; the
/// caller supplies the detents.
struct WorkoutNotesSheet: View {
    let viewModel: LiveWorkoutViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var notes: String
    @State private var isSaving = false

    init(viewModel: LiveWorkoutViewModel) {
        self.viewModel = viewModel
        _notes = State(initialValue: viewModel.workoutNotes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Add notes for this workout", text: $notes, axis: .vertical)
                        .lineLimit(4...12)
                } header: {
                    Text("Workout notes")
                }
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveAndDismiss() }
                        .disabled(isSaving)
                }
            }
        }
    }

    private func saveAndDismiss() {
        isSaving = true
        Task {
            let ok = await viewModel.updateNotes(notes)
            isSaving = false
            if ok { dismiss() }
        }
    }
}
