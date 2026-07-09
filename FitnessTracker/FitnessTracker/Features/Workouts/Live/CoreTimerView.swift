import SwiftUI

/// Full-screen timer for a running core workout. Steps through the
/// `CoreWorkoutTimer` schedule — showing the current exercise during work phases
/// and "Rest" during rest — with Pause / Resume and End early controls.
struct CoreTimerView: View {
    let timer: CoreWorkoutTimer
    /// Called to dismiss. `finished` is true when the circuit ran to completion
    /// (Done), false when the user ended early — the presenter uses it to decide
    /// whether to mark the saved circuit complete.
    let onClose: (_ finished: Bool) -> Void

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 24) {
                header
                Spacer()
                phaseContent
                Spacer()
                controls
            }
            .padding()
        }
        .onAppear { timer.start() }
        // Safety net: stop ticking if the cover goes away for any reason.
        .onDisappear { timer.pause() }
    }

    /// Subtle phase-colored wash: green while working, blue while resting.
    private var background: Color {
        guard !timer.isFinished, let phase = timer.currentPhase else {
            return Color(uiColor: .systemBackground)
        }
        return (phase.kind == .rest ? Color.blue : Color.green).opacity(0.12)
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            if let phase = timer.currentPhase {
                Text("Set \(phase.setNumber) of \(timer.totalSets)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        if timer.isFinished {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.green)
                Text("Core complete")
                    .font(.title.bold())
            }
        } else if let phase = timer.currentPhase {
            VStack(spacing: 16) {
                Text(phase.kind == .rest ? "Rest" : phase.label)
                    .font(.system(size: 34, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(phase.kind == .rest ? Color.blue : Color.primary)
                Text(formatTime(timer.remaining))
                    .font(.system(size: 84, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        if timer.isFinished {
            Button { onClose(true) } label: {
                Text("Done")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.green)
        } else {
            VStack(spacing: 12) {
                Button { timer.toggle() } label: {
                    Label(timer.isRunning ? "Pause" : "Resume",
                          systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(role: .destructive) {
                    timer.end()
                    onClose(false)
                } label: {
                    Text("End early")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
