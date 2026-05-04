import SwiftUI

/// Wraps ExerciseSearchSheet for the swap-mid-workout flow. Includes a
/// destructive-action warning if the user already has logged sets — the
/// server deletes them on swap.
struct ExerciseSwapSheet: View {
    let programExerciseId: String
    let currentExerciseName: String
    let hasLoggedSets: Bool
    /// Returns the deletedSetCount (server reports it) so the caller can
    /// surface a "lost N sets" message; nil on failure.
    let onConfirm: (_ replacementExerciseId: String) async -> Int?

    @Environment(\.dismiss) private var dismiss
    @State private var pendingReplacement: ExerciseDTO?
    @State private var isConfirming = false
    @State private var resultMessage: String?

    var body: some View {
        if pendingReplacement == nil {
            ExerciseSearchSheet(
                title: "Swap exercise",
                subtitle: "Currently: \(currentExerciseName)" + (hasLoggedSets ? "\n\u{26A0}\u{FE0F} Swapping will delete logged sets for this exercise." : "")
            ) { picked in
                pendingReplacement = picked
            }
        } else if let pending = pendingReplacement {
            confirmation(replacement: pending)
        }
    }

    private func confirmation(replacement: ExerciseDTO) -> some View {
        NavigationStack {
            Form {
                Section("Replacement") {
                    Text(replacement.name).font(.headline)
                    if let description = replacement.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if hasLoggedSets {
                    Section {
                        Label("Logged sets for the original exercise will be removed.", systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }

                if let resultMessage {
                    Section { Text(resultMessage).font(.footnote).foregroundStyle(.secondary) }
                }

                Section {
                    Button(role: .destructive) {
                        Task { await performSwap(replacement: replacement) }
                    } label: {
                        HStack {
                            if isConfirming { ProgressView().controlSize(.small) }
                            Text(isConfirming ? "Swapping…" : "Confirm swap")
                        }
                    }
                    .disabled(isConfirming)
                    Button("Pick a different exercise") {
                        pendingReplacement = nil
                    }
                    .disabled(isConfirming)
                }
            }
            .navigationTitle("Confirm swap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func performSwap(replacement: ExerciseDTO) async {
        isConfirming = true
        defer { isConfirming = false }
        let deleted = await onConfirm(replacement.id)
        if let deleted, deleted > 0 {
            resultMessage = "\(deleted) logged set\(deleted == 1 ? "" : "s") removed."
            // Hold briefly so the user sees the result, then dismiss.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        dismiss()
    }
}
