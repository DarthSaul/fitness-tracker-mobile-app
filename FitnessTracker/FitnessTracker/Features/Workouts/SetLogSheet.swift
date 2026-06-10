import SwiftUI

/// Sheet for logging or editing one set: reps and weight.
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
    /// Values of the most recent set logged for this exercise, if any. When
    /// non-nil, a "Copy previous set" button is shown that fills the form.
    let previousSet: PreviousSetValues?
    /// Returns `true` on successful persistence, `false` on failure. The sheet
    /// only dismisses on `true` so the user can see and recover from errors
    /// the caller already surfaces (e.g. via `viewModel.actionError`).
    let onSave: (_ reps: Int?, _ weight: Double?, _ rpe: Double?, _ notes: String?) async -> Bool
    let onDelete: (() async -> Bool)?

    @Environment(\.dismiss) private var dismiss
    @State private var repsText: String
    @State private var weightText: String
    @State private var isSaving = false
    @State private var isDeleting = false

    /// Enabled only when there's an earlier logged set whose weight we can copy.
    /// False for the first set logged in the group → button shows disabled.
    private var canCopyPreviousWeight: Bool {
        previousSet?.weight != nil
    }

    /// Accent fill when the copy action is available, otherwise a neutral grey
    /// that reads as "disabled" in both light (light grey) and dark (dark grey).
    private var copyButtonBackground: Color {
        canCopyPreviousWeight ? Color.accentColor : Color(uiColor: .systemGray5)
    }

    /// White label on the accent fill; a single subtle grey (icon == text) on
    /// the disabled fill, distinct from the grey background in both modes.
    private var copyButtonForeground: Color {
        canCopyPreviousWeight ? Color.white : Color(uiColor: .systemGray)
    }

    init(
        exerciseName: String,
        setNumber: Int,
        templateSet: ExerciseSetDTO,
        existing: CompletedSetDTO?,
        previousSet: PreviousSetValues? = nil,
        onSave: @escaping (_ reps: Int?, _ weight: Double?, _ rpe: Double?, _ notes: String?) async -> Bool,
        onDelete: (() async -> Bool)? = nil
    ) {
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.templateSet = templateSet
        self.existing = existing
        self.previousSet = previousSet
        self.onSave = onSave
        self.onDelete = onDelete

        let initialReps = existing?.reps ?? templateSet.reps
        let initialWeight = existing?.weight ?? templateSet.weight
        _repsText = State(initialValue: initialReps.map(String.init) ?? "")
        _weightText = State(initialValue: initialWeight.map { Self.formatDouble($0) } ?? "")
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
                    // Fields laid out side-by-side, each label left-aligned above
                    // its input, so the drawer stays short.
                    HStack(alignment: .top, spacing: 12) {
                        LabeledField(label: "Reps") {
                            // Number on the left, −/+ steppers on the right, all
                            // inside one boxed container (no per-button chrome).
                            HStack(spacing: 14) {
                                TextField(placeholderInt(templateSet.reps), text: $repsText)
                                    .keyboardType(.numberPad)
                                Button { adjustReps(by: -1) } label: {
                                    Image(systemName: "minus")
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.tint)
                                Button { adjustReps(by: 1) } label: {
                                    Image(systemName: "plus")
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.tint)
                            }
                            .boxedField()
                        }
                        LabeledField(label: "Weight (lb)") {
                            TextField(placeholderDouble(templateSet.weight), text: $weightText)
                                .keyboardType(.decimalPad)
                                .boxedField()
                        }
                    }

                    // Always shown; unavailable on the first set logged in the
                    // group. Copies weight only — reps are usually prefilled
                    // from the template. Colors are set explicitly (rather than
                    // via the prominent style's automatic states) so the
                    // disabled look reads clearly in both light and dark mode:
                    //   enabled  → accent background, white label
                    //   disabled → grey background, matching subtle-grey label
                    Button {
                        if let previousSet { applyPrevious(previousSet) }
                    } label: {
                        Label("Copy Previous Weight", systemImage: "doc.on.doc")
                            .font(.body.weight(.medium))
                            .foregroundStyle(copyButtonForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(copyButtonBackground, in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    // Non-tappable when there's nothing to copy, without the
                    // opacity dimming `.disabled` would apply over our colors.
                    .allowsHitTesting(canCopyPreviousWeight)
                    .padding(.top, 4)
                }

                if let onDelete, existing != nil {
                    Section {
                        Button(role: .destructive) {
                            // Guard against tapping Delete while a Save is mid-flight.
                            // Without this, Save and Delete on the same record can
                            // race — server-side ordering is undefined and local state
                            // can end up out of sync with the server.
                            guard !isSaving else { return }
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
                        .disabled(isDeleting || isSaving)
                    }
                }
            }
            // Pull the header card up closer to the inline "Log set" title by
            // trimming the Form's default top inset.
            .contentMargins(.top, 8, for: .scrollContent)
            .navigationTitle(existing == nil ? "Log Set" : "Edit Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveAndDismiss() }
                        .disabled(isSaving || isDeleting)
                }
            }
        }
    }

    private func saveAndDismiss() {
        // Match the Delete-button guard: don't queue a Save while a Delete is
        // already in flight on the same record.
        guard !isDeleting else { return }
        isSaving = true
        Task {
            // Per-set notes were removed from this sheet — set notes now live
            // at the exercise level (Notes chip) and workout level (Workout
            // Notes card). RPE was dropped from this form too. Pass nil for both
            // so those fields are left untouched server-side.
            let ok = await onSave(parseInt(repsText), parseDouble(weightText), nil, nil)
            isSaving = false
            if ok { dismiss() }
        }
    }

    /// Steps the reps field up or down via the inline −/+ buttons. Bases off the
    /// current text (falling back to the template default) and clamps at 0.
    private func adjustReps(by delta: Int) {
        let base = parseInt(repsText) ?? templateSet.reps ?? 0
        repsText = String(max(0, base + delta))
    }

    /// Copies the previous set's weight into the form, leaving reps untouched
    /// (the template prefill is usually the right rep count). Weight round-trips
    /// through the locale-aware formatter.
    private func applyPrevious(_ prev: PreviousSetValues) {
        weightText = prev.weight.map { Self.formatDouble($0) } ?? ""
    }

    // MARK: - Helpers

    private func parseInt(_ s: String) -> Int? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Int(trimmed)
    }

    private func parseDouble(_ s: String) -> Double? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // The decimalPad keyboard emits the user's locale separator (e.g. ","
        // in DE/FR), and `formatDouble` already produces locale-aware strings
        // for placeholders and prefills. Parse with the matching locale so the
        // round-trip works — `Double(_:)` only accepts "." and would silently
        // discard otherwise-valid input.
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        return formatter.number(from: trimmed)?.doubleValue
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

// MARK: - Previous-set values

/// Snapshot of a previously logged set, used to prefill the form via the
/// "Copy Previous Weight" button. Decoupled from `CompletedSetDTO` so the sheet
/// stays agnostic about where the value came from. Only weight is carried —
/// reps are intentionally left to the template prefill.
struct PreviousSetValues: Equatable {
    let weight: Double?
}

// MARK: - Boxed text field

private extension View {
    /// Rounded, filled text-field box that's a little taller than the default
    /// `.roundedBorder` style — gives the reps / weight inputs more height.
    func boxedField() -> some View {
        self
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(uiColor: .tertiarySystemFill))
            )
    }
}

// MARK: - Labeled field

/// One column of the side-by-side input row: a caption label stacked above an
/// arbitrary field, expanding to share width equally with its siblings. The
/// label sits at the leading edge above its input.
private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
