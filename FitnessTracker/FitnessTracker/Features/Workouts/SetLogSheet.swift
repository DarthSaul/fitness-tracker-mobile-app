import SwiftUI

/// Sheet for logging or editing one set: reps, weight, RPE, notes.
/// Designed to be reused across the M6 retroactive flow and the M7 live workout
/// view — neither owns the persistence logic, that's left to the caller via
/// `onSave` and `onDelete` closures so each flow can route to the right endpoint.
struct SetLogSheet: View {
    let exerciseName: String
    let setNumber: Int
    /// Template values used as placeholders / defaults if no completed set exists.
    let templateSet: ExerciseSetDTO
    /// Existing log, if any. When non-nil, the sheet shows a Delete button.
    let existing: CompletedSetDTO?
    /// Returns `true` on successful persistence, `false` on failure. The sheet
    /// only dismisses on `true` so the user can see and recover from errors
    /// the caller already surfaces (e.g. via `viewModel.actionError`).
    let onSave: (_ reps: Int?, _ weight: Double?, _ rpe: Double?, _ notes: String?) async -> Bool
    let onDelete: (() async -> Bool)?

    @Environment(\.dismiss) private var dismiss
    @State private var repsText: String
    @State private var weightText: String
    @State private var rpeText: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var isDeleting = false

    init(
        exerciseName: String,
        setNumber: Int,
        templateSet: ExerciseSetDTO,
        existing: CompletedSetDTO?,
        onSave: @escaping (_ reps: Int?, _ weight: Double?, _ rpe: Double?, _ notes: String?) async -> Bool,
        onDelete: (() async -> Bool)? = nil
    ) {
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.templateSet = templateSet
        self.existing = existing
        self.onSave = onSave
        self.onDelete = onDelete

        let initialReps = existing?.reps ?? templateSet.reps
        let initialWeight = existing?.weight ?? templateSet.weight
        let initialRPE = existing?.rpe ?? templateSet.rpe
        _repsText = State(initialValue: initialReps.map(String.init) ?? "")
        _weightText = State(initialValue: initialWeight.map { Self.formatDouble($0) } ?? "")
        _rpeText = State(initialValue: initialRPE.map { Self.formatDouble($0) } ?? "")
        _notes = State(initialValue: existing?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(exerciseName)
                        .font(.headline)
                    Text("Set \(setNumber)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    LabeledTextField(label: "Reps", placeholder: placeholderInt(templateSet.reps), text: $repsText, keyboard: .numberPad)
                    LabeledTextField(label: "Weight (lb)", placeholder: placeholderDouble(templateSet.weight), text: $weightText, keyboard: .decimalPad)
                    LabeledTextField(label: "RPE", placeholder: placeholderDouble(templateSet.rpe), text: $rpeText, keyboard: .decimalPad)
                }

                Section("Notes") {
                    TextField("Add a note", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let onDelete, existing != nil {
                    Section {
                        Button(role: .destructive) {
                            Task {
                                isDeleting = true
                                let ok = await onDelete()
                                isDeleting = false
                                if ok { dismiss() }
                            }
                        } label: {
                            HStack {
                                if isDeleting { ProgressView().controlSize(.small) }
                                Text("Delete this set")
                            }
                        }
                        .disabled(isDeleting)
                    }
                }
            }
            .navigationTitle(existing == nil ? "Log set" : "Edit set")
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
            let ok = await onSave(parseInt(repsText), parseDouble(weightText), parseDouble(rpeText), notes.isEmpty ? nil : notes)
            isSaving = false
            if ok { dismiss() }
        }
    }

    // MARK: - Helpers

    private func parseInt(_ s: String) -> Int? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Int(trimmed)
    }

    private func parseDouble(_ s: String) -> Double? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Double(trimmed)
    }

    private func placeholderInt(_ value: Int?) -> String {
        value.map(String.init) ?? "—"
    }

    private func placeholderDouble(_ value: Double?) -> String {
        value.map { Self.formatDouble($0) } ?? "—"
    }

    private static func formatDouble(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Labeled text field
private struct LabeledTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let keyboard: UIKeyboardType

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboard)
                .frame(maxWidth: 120)
        }
    }
}
