import SwiftUI

/// Per-exercise card matching the web UX: collapsed by default, tap the header
/// to expand into a five-column set grid (`# · lb · reps · effort · done`),
/// auto-marks complete when every template set has a CompletedSet, and exposes
/// swap / trend / add-extra-set actions inline.
///
/// Pulls observable state from the parent VM so row-level state (logged,
/// swap badge) stays reactive without bouncing through identifiers and bindings.
struct ExerciseCard: View {
    let viewModel: LiveWorkoutViewModel
    let exercise: ProgramExerciseDTO
    let onTapTemplateSet: (ExerciseSetDTO) -> Void
    let onAddExtraSet: () -> Void
    let onSwap: () -> Void
    let onShowTrend: () -> Void
    let onShowNotes: () -> Void
    /// Group rest period, surfaced as the first chip. The parent passes nil
    /// when it shouldn't render here (e.g. a non-final exercise of a superset,
    /// where rest is only taken after the whole round).
    let restSeconds: Int?
    /// When true (paged/single-exercise view), the set grid is always visible
    /// and the header drops its expand/collapse toggle and chevron. Defaults to
    /// false so the stacked list view keeps its tap-to-expand behavior.
    var alwaysExpanded: Bool = false

    @State private var isExpanded: Bool = false

    private var isMarkedComplete: Bool {
        viewModel.isMarkedComplete(programExerciseId: exercise.id)
    }

    /// Sets show when the card is force-expanded (paged view) or the user has
    /// tapped to expand it (list view).
    private var showSets: Bool { alwaysExpanded || isExpanded }

    var body: some View {
        VStack(spacing: 0) {
            header
            if showSets {
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
        // Two stacked rows: a tappable toggle row (name + completion + chevron)
        // and a separate chips row outside the Button. Nesting the chips inside
        // the toggle Button caused tap-routing ambiguity — chip taps could
        // bubble up to the expand/collapse handler in some cases.
        VStack(alignment: .leading, spacing: 10) {
            if alwaysExpanded {
                // Paged view: the grid is always shown, so the header is a
                // static row with no toggle Button and no chevron.
                HStack(spacing: 10) {
                    nameRow
                    Spacer()
                    if isMarkedComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            } else {
                Button {
                    // Toggling without `withAnimation` keeps the header text
                    // anchored in place — animating the resize caused the title
                    // to bounce vertically as the row grew to fit the set grid.
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 10) {
                        nameRow
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
            }

            chipsRow
        }
    }

    private var nameRow: some View {
        HStack(spacing: 6) {
            Text(exercise.exercise.name)
                .font(.headline)
                .lineLimit(1)
            if viewModel.isSwapped(programExerciseId: exercise.id) {
                Text("Swapped")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
    }

    private var chipsRow: some View {
        HStack(spacing: 6) {
            // Rest chip — informational (not a button), first of the row.
            // Mirrors the web's un-expanded card showing the group's rest.
            if let restSeconds, restSeconds > 0 {
                restChip(seconds: restSeconds)
            }
            // Trend chip — same idiom as the web's "📈 Trend" tag.
            chip(label: "Trend", systemImage: "chart.line.uptrend.xyaxis", action: deferredTrend)
            // Swap chip
            chip(
                label: viewModel.isSwapped(programExerciseId: exercise.id) ? "Change swap" : "Swap",
                systemImage: "arrow.triangle.2.circlepath",
                action: deferredSwap
            )
            // Notes chip — opens a per-exercise notes editor (lifetime notes
            // for this exercise across all sessions, not per-set).
            chip(label: "Notes", systemImage: "note.text", action: deferredNotes)
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
            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { _, templateSet in
                SetRow(
                    setNumber: templateSet.setNumber,
                    template: templateSet,
                    completed: viewModel.completedSet(forExerciseSetId: templateSet.id),
                    onTap: { onTapTemplateSet(templateSet) }
                )
            }
            extraSetsList
            actionButtons
        }
        .padding(.vertical, 8)
    }

    private var gridHeader: some View {
        SetGridRow(
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
        let extras = viewModel.extraSets(forProgramExerciseId: exercise.id)
        ForEach(Array(extras.enumerated()), id: \.element.id) { pair in
            ExtraSetRow(
                setNumber: exercise.sets.count + pair.offset + 1,
                completed: pair.element,
                onDelete: {
                    let setId = pair.element.id
                    Task {
                        await viewModel.deleteExtraSet(programExerciseId: exercise.id, completedSetId: setId)
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
                viewModel.toggleMarkedComplete(programExerciseId: exercise.id)
                // Marking complete collapses the panel; un-completing leaves
                // it as-is so the user can keep editing sets.
                if viewModel.isMarkedComplete(programExerciseId: exercise.id) {
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

    /// Defer state changes that fire from inside Menu/Button taps so the
    /// presentation animation has time to settle before any sheet pops up.
    /// Without this we see a `_UIReparentingView` warning when SwiftUI tries
    /// to attach a sheet while the trigger view is still being torn down.
    private func deferredTrend() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            onShowTrend()
        }
    }

    private func deferredSwap() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            onSwap()
        }
    }

    private func deferredNotes() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            onShowNotes()
        }
    }
}

// MARK: - Five-column grid row

/// Shared layout for both the column header and per-set rows so the columns
/// stay aligned. Mirrors the web's `set-grid` CSS:
/// `0.5fr 1.5fr 1fr 1.5fr 0.75fr`.
private struct SetGridRow: View {
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

private struct SetRow: View {
    let setNumber: Int
    let template: ExerciseSetDTO
    let completed: CompletedSetDTO?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            SetGridRow(
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
    /// "75% / RPE 7" (matches the web's `formatEffort` helper). Uses the
    /// extended `#/.../#` regex literal so the leading `/^` isn't parsed as
    /// an operator in this expression context.
    private func formatEffort(_ target: String) -> String {
        let pattern = #/^([\d.]+%)/#
        if let match = target.firstMatch(of: pattern) {
            return String(match.output.1)
        }
        return target
    }
}

private struct ExtraSetRow: View {
    let setNumber: Int
    let completed: CompletedSetDTO
    let onDelete: () -> Void

    var body: some View {
        SetGridRow(
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

// MARK: - Shared formatters

func formatDouble(_ value: Double) -> String {
    let f = NumberFormatter()
    f.maximumFractionDigits = 2
    f.minimumFractionDigits = 0
    return f.string(from: NSNumber(value: value)) ?? "\(value)"
}

/// One-line summary used by read-only views (preview sheet, day-edit,
/// ad-hoc card) where a full grid would be overkill.
func formatSet(reps: Int?, weight: Double?, rpe: Double?) -> String {
    var parts: [String] = []
    if let reps { parts.append("\(reps) reps") }
    if let weight { parts.append("\(formatDouble(weight)) lb") }
    if let rpe { parts.append("RPE \(formatDouble(rpe))") }
    return parts.isEmpty ? "—" : parts.joined(separator: " · ")
}
