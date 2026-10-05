import SwiftUI

/// Top of Program → Manage: the run's progress ring (completed / total days)
/// beside a static card naming the active program. Moved here from Home.
struct ActiveProgramSummaryRow: View {
    let programName: String
    let progress: ProgramProgress

    var body: some View {
        HStack(spacing: 12) {
            progressBadge
            programCard
        }
        // Both cells fill the row's height (maxHeight: .infinity below);
        // fixedSize caps that at the taller cell's ideal height so the cards
        // match whether the program name takes one line or two.
        .fixedSize(horizontal: false, vertical: true)
    }

    private var progressBadge: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(progress.percent) / 100)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: progress.percent)
            Text("\(progress.completedDays)/\(progress.totalDays)")
                .font(.caption.weight(.semibold).monospacedDigit())
        }
        .frame(width: 64, height: 64)
        .padding(12)
        .frame(maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(progress.completedDays) of \(progress.totalDays) workouts done")
    }

    private var programCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Active Program")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(programName)
                .font(.headline)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
