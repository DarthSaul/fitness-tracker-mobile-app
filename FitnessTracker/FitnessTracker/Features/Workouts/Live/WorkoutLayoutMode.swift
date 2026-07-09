import SwiftUI

// MARK: - Layout mode

/// The two presentations of the live workout. `String`-backed so it round-trips
/// through `@AppStorage`. Persisted under the `liveWorkoutLayoutMode` key.
///
/// NOTE: This is feature scaffolding kept for a future re-wiring of the
/// one-exercise-per-page workout view. It is intentionally not yet referenced by
/// `LiveWorkoutView` (whose UI matches the list-only layout on `main`); the
/// paired support — `ExerciseCard(alwaysExpanded:)` and
/// `ActiveWorkoutSettingsSheet` below — is likewise retained for that future use.
enum WorkoutLayoutMode: String {
    /// Stacked list: every exercise as a collapsible card in one Form.
    case list
    /// Swipeable view: one exercise group per page, sets always shown.
    case paged
}

// MARK: - Settings sheet

/// Panel intended to host in-session presentation preferences — currently the
/// exercise layout toggle. Reads/writes the same `@AppStorage` key as the live
/// workout view so the choice persists across workouts.
///
/// Currently unwired (no presenter) — retained alongside `WorkoutLayoutMode` for
/// the future paged-layout feature.
struct ActiveWorkoutSettingsSheet: View {
    @AppStorage("liveWorkoutLayoutMode") private var layoutMode: WorkoutLayoutMode = .list
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Exercise layout", selection: $layoutMode) {
                        Label("List", systemImage: "list.bullet")
                            .tag(WorkoutLayoutMode.list)
                        Label("One at a time - Coming soon!", systemImage: "square.stack")
                            .tag(WorkoutLayoutMode.paged)
                            .selectionDisabled()
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Exercise layout")
                } footer: {
                    Text("List shows every exercise stacked. One at a time shows a single exercise per screen — swipe left or right to move between them.")
                }
            }
            .navigationTitle("Workout Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
