import SwiftUI
import OSLog

/// Two-cell row: circular progress (completed / total days) + program name with
/// a "Manage" affordance. Tapping Manage logs for now — PR #6 wires it to the
/// /program detail view.
struct ActiveProgramProgressCard: View {
    let viewModel: HomeViewModel

    var body: some View {
        guard let program = viewModel.activeProgram else {
            return AnyView(EmptyView())
        }

        return AnyView(
            HStack(spacing: 12) {
                progressBadge
                programInfo(program: program)
            }
        )
    }

    private var progressBadge: some View {
        VStack {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(viewModel.progressPercent) / 100)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: viewModel.progressPercent)
                Text("\(viewModel.completedDays)/\(viewModel.totalDays)")
                    .font(.caption.weight(.semibold).monospacedDigit())
            }
            .frame(width: 64, height: 64)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func programInfo(program: ActiveUserProgramDTO) -> some View {
        Button {
            // PR #6 wires this to the /program detail view.
            Logger.app.info("Manage program tapped — navigation arrives in PR #6.")
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("My Program")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(program.program.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("Manage")
                    Image(systemName: "chevron.right")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
