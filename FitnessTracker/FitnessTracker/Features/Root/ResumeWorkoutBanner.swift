import SwiftUI

/// Persistent "you have a workout in progress" pill anchored to the bottom
/// safe-area inset of the TabView (Apple-Music-style). Tap surfaces the
/// active workout — program or standalone; the subtitle identifies which
/// ("Week 2 · Day 3" vs. the standalone workout's name).
struct ResumeWorkoutBanner: View {
    let subtitle: String
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
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
        .accessibilityLabel("Resume workout, \(subtitle)")
        .accessibilityHint("Opens the active workout")
    }
}
