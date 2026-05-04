import SwiftUI

/// Non-today view: either show the schedule for selectedDate (with an Unschedule
/// action) or invite the user to schedule a workout. Hidden entirely when no
/// active program — the parent view shows the "no active program" empty state.
struct HomeScheduledCard: View {
    let viewModel: HomeViewModel
    let onScheduleTapped: () -> Void

    var body: some View {
        if let scheduled = viewModel.scheduledForSelectedDate {
            ScheduledRow(viewModel: viewModel, scheduled: scheduled)
        } else if viewModel.hasActiveProgram {
            ScheduleCTA(onTap: onScheduleTapped)
        }
    }
}

private struct ScheduledRow: View {
    let viewModel: HomeViewModel
    let scheduled: ScheduledWorkoutDTO

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [.purple, .pink],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: 8)
            VStack(alignment: .leading, spacing: 6) {
                Text("Scheduled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text("Week \(scheduled.weekNumber), Day \(scheduled.dayNumber)")
                        .font(.headline)
                    if let name = viewModel.dayName(forWeek: scheduled.weekNumber, day: scheduled.dayNumber) {
                        Text("— \(name)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    Task { await viewModel.unscheduleSelected() }
                } label: {
                    HStack {
                        if viewModel.isUnscheduling {
                            ProgressView().controlSize(.small)
                            Text("Unscheduling…")
                        } else {
                            Text("Unschedule")
                            Spacer()
                            Image(systemName: "xmark")
                        }
                    }
                    .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isUnscheduling)
                .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct ScheduleCTA: View {
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [.purple, .pink],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: 8)
            VStack(alignment: .leading, spacing: 8) {
                Text("Scheduled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("No workout scheduled")
                    .font(.headline)
                Spacer(minLength: 0)
                Button(action: onTap) {
                    HStack {
                        Text("Schedule a workout")
                        Spacer()
                        Image(systemName: "plus")
                    }
                    .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
