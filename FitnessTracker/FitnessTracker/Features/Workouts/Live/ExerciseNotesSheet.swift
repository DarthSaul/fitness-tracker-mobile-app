import SwiftUI

/// Editor sheet for an exercise's lifetime notes (cross-session, persistent).
/// Backed by GET/PUT /api/exercises/:id/notes via the standard APIClient.
/// Presented from the per-exercise "Notes" chip on the live-workout view.
struct ExerciseNotesSheet: View {
    let exerciseId: String
    let exerciseName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var apiClient

    @State private var notes: String = ""
    @State private var initialNotes: String = ""
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var loadError: String?
    @State private var saveError: String?

    private var isDirty: Bool { notes != initialNotes }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(exerciseName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await save() }
                        } label: {
                            if isSaving {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Save").fontWeight(.semibold)
                            }
                        }
                        .disabled(!isDirty || isSaving)
                    }
                }
                .task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && notes.isEmpty && loadError == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Form {
                Section {
                    TextField("Form cues, weight progression, anything you want to remember…", text: $notes, axis: .vertical)
                        .lineLimit(5...12)
                } footer: {
                    Text("These notes persist across all sessions for this exercise.")
                }

                if let loadError {
                    Section { Text(loadError).foregroundStyle(.red).font(.footnote) }
                }
                if let saveError {
                    Section { Text(saveError).foregroundStyle(.red).font(.footnote) }
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let dto: ExerciseNotesResponseDTO = try await apiClient.send(.getExerciseNotes(exerciseId: exerciseId))
            let value = dto.notes ?? ""
            self.notes = value
            self.initialNotes = value
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            let _: UserExerciseNoteDTO = try await apiClient.send(
                .updateExerciseNotes(exerciseId: exerciseId, body: UpdateExerciseNotesBody(notes: notes))
            )
            initialNotes = notes
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
