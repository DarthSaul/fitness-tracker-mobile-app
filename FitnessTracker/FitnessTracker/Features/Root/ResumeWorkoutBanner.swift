import SwiftUI

/// Persistent "you have a workout in progress" pill anchored to the bottom
/// safe-area inset of the TabView (Apple-Music-style). Tap surfaces the
/// active workout. PR #7 wires the tap target to navigate into the live
/// workout view; for now it's a no-op with an explicit log line.
struct ResumeWorkoutBanner: View {
    let session: ActiveWorkoutResponseDTO.ActiveWorkoutSession
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.tint, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Workout in progress")
                        .font(.subheadline.weight(.semibold))
                    Text("Week \(session.weekNumber) · Day \(session.dayNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text("Resume")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            // Capsule + matching horizontal inset so it reads as the same
            // floating pill as the tab bar directly below it.
            .background(.regularMaterial, in: Capsule())
            .padding(.horizontal, 22)
            .padding(.bottom, 6)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Resume workout, week \(session.weekNumber), day \(session.dayNumber)")
        .accessibilityHint("Opens the active workout")
    }
}
