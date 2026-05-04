import SwiftUI

/// Per-exercise block inside the LiveWorkoutView. Renders template sets,
/// extra sets, and exposes swap / trend / add-extra controls via a menu.
/// Pulls observable state from the parent VM directly — passing the VM
/// rather than rendering data lets row state (logged/unlogged, swap badge)
/// stay reactive without bouncing through identifiers and bindings.
struct ExerciseCard: View {
    let viewModel: LiveWorkoutViewModel
    let exercise: ProgramExerciseDTO
    let onTapTemplateSet: (ExerciseSetDTO) -> Void
    let onAddExtraSet: () -> Void
    let onSwap: () -> Void
    let onShowTrend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            templateSetsList
            extraSetsList
            footer
        }
        .padding(.vertical, 4)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(exercise.exercise.name).font(.headline)
                    if viewModel.isSwapped(programExerciseId: exercise.id) {
                        Text("Swapped")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            Menu {
                Button { onShowTrend() } label: { Label("Recent history", systemImage: "chart.line.uptrend.xyaxis") }
                Button { onSwap() } label: { Label("Swap exercise", systemImage: "arrow.triangle.2.circlepath") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Template sets

    @ViewBuilder
    private var templateSetsList: some View {
        ForEach(exercise.sets, id: \.id) { templateSet in
            LiveSetRow(
                setNumber: templateSet.setNumber,
                template: templateSet,
                completed: viewModel.completedSet(forExerciseSetId: templateSet.id),
                onTap: { onTapTemplateSet(templateSet) }
            )
        }
    }

    // MARK: - Extra sets

    @ViewBuilder
    private var extraSetsList: some View {
        let extras = viewModel.extraSets(forProgramExerciseId: exercise.id)
        if !extras.isEmpty {
            ForEach(Array(extras.enumerated()), id: \.element.id) { index, extra in
                ExtraSetRow(
                    setNumber: exercise.sets.count + index + 1,
                    completed: extra,
                    onDelete: {
                        Task { await viewModel.deleteExtraSet(programExerciseId: exercise.id, completedSetId: extra.id) }
                    }
                )
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Button(action: onAddExtraSet) {
            Label("Add extra set", systemImage: "plus")
                .font(.caption.weight(.medium))
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Set rows

private struct LiveSetRow: View {
    let setNumber: Int
    let template: ExerciseSetDTO
    let completed: CompletedSetDTO?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text("Set \(setNumber)").foregroundStyle(.primary)
                Spacer()
                summaryText
                Image(systemName: completed == nil ? "plus.circle" : "checkmark.circle.fill")
                    .foregroundStyle(completed == nil ? Color.secondary : Color.green)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var summaryText: some View {
        if let completed {
            Text(formatSet(reps: completed.reps, weight: completed.weight, rpe: completed.rpe))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.green)
        } else {
            Text(formatSet(reps: template.reps, weight: template.weight, rpe: template.rpe))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }
}

private struct ExtraSetRow: View {
    let setNumber: Int
    let completed: CompletedSetDTO
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Text("Extra \(setNumber)")
                .foregroundStyle(.orange)
            Spacer()
            Text(formatSet(reps: completed.reps, weight: completed.weight, rpe: completed.rpe))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.green)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Formatting helpers

func formatSet(reps: Int?, weight: Double?, rpe: Double?) -> String {
    var parts: [String] = []
    if let reps { parts.append("\(reps) reps") }
    if let weight { parts.append("\(formatDouble(weight)) lb") }
    if let rpe { parts.append("RPE \(formatDouble(rpe))") }
    return parts.isEmpty ? "—" : parts.joined(separator: " · ")
}

func formatDouble(_ value: Double) -> String {
    let f = NumberFormatter()
    f.maximumFractionDigits = 2
    f.minimumFractionDigits = 0
    return f.string(from: NSNumber(value: value)) ?? "\(value)"
}
