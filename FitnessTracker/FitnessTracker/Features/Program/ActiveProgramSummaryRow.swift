import SwiftUI

/// Top of Program → Manage: the run's progress ring (completed / total days)
/// beside a card naming the active program, with an "Info" chip that opens
/// the program's detail page. Moved here from Home.
struct ActiveProgramSummaryRow: View {
    let programName: String
    let progress: ProgramProgress
    /// Opens the program's info page; nil hides the chip (e.g. while the
    /// program library is still loading).
    var onInfo: (() -> Void)?

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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Active Program")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(programName)
                    .font(.headline)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if let onInfo {
                // Plain style so only the chip reacts — this sits inside a
                // List row, which would otherwise highlight as a whole.
                Button(action: onInfo) {
                    Text("Info")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Program info")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
