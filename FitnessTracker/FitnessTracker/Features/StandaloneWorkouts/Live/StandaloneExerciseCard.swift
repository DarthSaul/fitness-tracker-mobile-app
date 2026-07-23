import SwiftUI

/// Per-exercise card for the standalone live workout — same collapsed-header /
/// five-column set grid UX as the program flow's `ExerciseCard`, minus the
/// Swap chip (standalone sessions have no swap endpoint). Extra rows are the
/// ad-hoc sets logged under this exercise's name.
struct StandaloneExerciseCard: View {
    let viewModel: StandaloneLiveWorkoutViewModel
    let exercise: StandaloneWorkoutExerciseDTO
    let onTapTemplateSet: (StandaloneWorkoutSetDTO) -> Void
    let onAddExtraSet: () -> Void
    let onShowTrend: () -> Void
    let onShowNotes: () -> Void
    /// Group rest period, surfaced as the first chip. The parent passes nil
    /// when it shouldn't render here (e.g. a non-final exercise of a superset,
    /// where rest is only taken after the whole round).
    let restSeconds: Int?

    @State private var isExpanded: Bool = false

    private var isMarkedComplete: Bool {
        viewModel.isMarkedComplete(exerciseId: exercise.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                setsGrid
            }
        }
        .padding(.vertical, 4)
        // Force the Form's row separator to span the full card width — by
        // default the leading edge aligns with the exercise name (which leaves
        // a half-width gap between superset rows).
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    // MARK: - Header (always visible)

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                // Toggling without `withAnimation` keeps the header text
                // anchored in place — animating the resize caused the title
                // to bounce vertically as the row grew to fit the set grid.
                isExpanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    Text(exercise.exercise.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    if isMarkedComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            chipsRow
        }
    }

    private var chipsRow: some View {
        HStack(spacing: 6) {
            if let restSeconds, restSeconds > 0 {
                restChip(seconds: restSeconds)
            }
            chip(label: "Trend", systemImage: "chart.line.uptrend.xyaxis") { deferred(onShowTrend) }
            chip(label: "Notes", systemImage: "note.text") { deferred(onShowNotes) }
        }
    }

    private func chip(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(label)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.18), in: Capsule())
        }
        .buttonStyle(.borderless)
    }

    /// Read-only rest pill. Same capsule visual as `chip` but not a Button —
    /// rest is informational, not an action.
    private func restChip(seconds: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
            Text(formatRest(seconds))
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.18), in: Capsule())
    }

    /// 150 → "2.5 min", 120 → "2 min", 45 → "45 sec".
    private func formatRest(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) sec" }
        let f = NumberFormatter()
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        let minutes = f.string(from: NSNumber(value: Double(seconds) / 60)) ?? "\(seconds / 60)"
        return "\(minutes) min"
    }

    // MARK: - Sets grid (expanded)

    private var setsGrid: some View {
        VStack(spacing: 0) {
            gridHeader
            ForEach(exercise.sets, id: \.id) { templateSet in
                StandaloneSetRow(
                    setNumber: templateSet.setNumber,
                    template: templateSet,
                    completed: viewModel.completedSet(forTemplateSetId: templateSet.id),
                    onTap: { onTapTemplateSet(templateSet) }
                )
            }
            extraSetsList
            actionButtons
        }
        .padding(.vertical, 8)
    }

    private var gridHeader: some View {
        StandaloneSetGridRow(
            number: AnyView(Text("#").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)),
            weight: AnyView(Text("lb").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)),
            reps: AnyView(Text("Reps").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)),
            effort: AnyView(Text("Effort").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)),
            trailing: AnyView(Text("Done").font(.caption2.weight(.semibold)).foregroundStyle(.secondary))
        )
        .textCase(.uppercase)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var extraSetsList: some View {
        let extras = viewModel.extraSets(forExerciseName: exercise.exercise.name)
        ForEach(Array(extras.enumerated()), id: \.element.id) { pair in
            StandaloneExtraSetRow(
                setNumber: exercise.sets.count + pair.offset + 1,
                completed: pair.element,
                onDelete: {
                    let setId = pair.element.id
                    Task {
                        await viewModel.deleteAdhocSet(id: setId)
                    }
                }
            )
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button(action: onAddExtraSet) {
                Text("Add set")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Button {
                viewModel.toggleMarkedComplete(exerciseId: exercise.id)
                // Marking complete collapses the panel; un-completing leaves
                // it as-is so the user can keep editing sets.
                if viewModel.isMarkedComplete(exerciseId: exercise.id) {
                    isExpanded = false
                }
            } label: {
                Text(isMarkedComplete ? "Completed" : "Complete")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isMarkedComplete ? .green : .accentColor)
            .controlSize(.regular)
        }
        .padding(.top, 4)
    }

    // MARK: - Deferred actions

    /// Defer state changes that fire from inside Button taps so the
    /// presentation animation has time to settle before any sheet pops up
    /// (avoids the `_UIReparentingView` warning — same trick as ExerciseCard).
    private func deferred(_ action: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            action()
        }
    }
}

// MARK: - Five-column grid row

/// Shared layout for both the column header and per-set rows so the columns
/// stay aligned. Same proportions as the program flow's `SetGridRow`.
private struct StandaloneSetGridRow: View {
    let number: AnyView
    let weight: AnyView
    let reps: AnyView
    let effort: AnyView
    let trailing: AnyView

    var body: some View {
        HStack(spacing: 0) {
            number.frame(maxWidth: .infinity)
            weight.frame(maxWidth: .infinity)
            reps.frame(maxWidth: .infinity)
            effort.frame(maxWidth: .infinity)
            trailing.frame(maxWidth: .infinity)
        }
        .multilineTextAlignment(.center)
    }
}

private struct StandaloneSetRow: View {
    let setNumber: Int
    let template: StandaloneWorkoutSetDTO
    let completed: StandaloneCompletedSetDTO?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            StandaloneSetGridRow(
                number: AnyView(
                    Text("\(setNumber)")
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(completed == nil ? Color.secondary : Color.green)
                ),
                weight: AnyView(weightCell),
                reps: AnyView(repsCell),
                effort: AnyView(effortCell),
                trailing: AnyView(trailingCell)
            )
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var weightCell: some View {
        if let value = completed?.weight ?? template.weight {
            Text(formatDouble(value))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(completed == nil ? Color.primary : Color.green)
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var repsCell: some View {
        if let value = completed?.reps ?? template.reps {
            Text("\(value)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(completed == nil ? Color.primary : Color.green)
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var effortCell: some View {
        if let target = template.effortTarget, !target.isEmpty {
            Text(formatEffort(target))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        } else if let rpe = completed?.rpe {
            // `completed` is non-nil in this branch — show in the
            // "logged-set green" color used by the other green cells.
            Text("RPE \(formatDouble(rpe))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.green)
                .lineLimit(1)
        } else if let rpe = template.rpe {
            Text("RPE \(formatDouble(rpe))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var trailingCell: some View {
        if completed != nil {
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.green)
        } else {
            Image(systemName: "circle.dotted")
                .foregroundStyle(.tertiary)
        }
    }

    /// Displays the leading percent or RPE token of an effort target like
    /// "75% / RPE 7" (matches the program flow's `formatEffort` helper).
    private func formatEffort(_ target: String) -> String {
        let pattern = #/^([\d.]+%)/#
        if let match = target.firstMatch(of: pattern) {
            return String(match.output.1)
        }
        return target
    }
}

private struct StandaloneExtraSetRow: View {
    let setNumber: Int
    let completed: StandaloneCompletedSetDTO
    let onDelete: () -> Void

    var body: some View {
        StandaloneSetGridRow(
            number: AnyView(
                Text("\(setNumber)")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.orange)
            ),
            weight: AnyView(
                Text(completed.weight.map { formatDouble($0) } ?? "—")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.green)
            ),
            reps: AnyView(
                Text(completed.reps.map(String.init) ?? "—")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.green)
            ),
            effort: AnyView(
                Text(completed.rpe.map { "RPE \(formatDouble($0))" } ?? "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            ),
            trailing: AnyView(
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.borderless)
            )
        )
        .padding(.vertical, 6)
    }
}
