import SwiftUI

/// Slide-in drawer showing the rest stopwatch. Presented from the clock button
/// in the live-workout toolbar. The stopwatch itself is owned by the parent so
/// it keeps counting if this drawer is dismissed mid-rest.
struct RestTimerSheet: View {
    @Bindable var stopwatch: RestStopwatch
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Text(stopwatch.formatted)
                .font(.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
                .padding(.top, 16)

            HStack(spacing: 16) {
                Button {
                    stopwatch.toggle()
                } label: {
                    Label(
                        stopwatch.isRunning ? "Pause" : "Start",
                        systemImage: stopwatch.isRunning ? "pause.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    stopwatch.reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(stopwatch.elapsed == 0 && !stopwatch.isRunning)
            }
            .padding(.horizontal)

            Spacer(minLength: 0)
        }
        .padding()
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.visible)
    }
}
