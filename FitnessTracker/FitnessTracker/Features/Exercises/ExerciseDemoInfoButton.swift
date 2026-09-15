import SwiftUI

/// The "i" glyph rendered next to an exercise name in the live-workout cards.
/// Always enabled — the demo sheet it opens decides whether a clip exists and
/// shows a friendly fallback otherwise. Shared by the program and standalone
/// cards so the two can't drift.
///
/// `.borderless` matches the cards' chips and keeps a List row from firing
/// every Button on a row tap. Callers must not nest this inside another
/// Button (see the tap-routing note in `ExerciseCard`).
struct ExerciseDemoInfoButton: View {
    let exerciseName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "info.circle")
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
                // Widens the hit area without widening the glyph.
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        // The name Text stays the element that truncates on long names.
        .fixedSize()
        .accessibilityLabel("Show demo for \(exerciseName)")
    }
}
