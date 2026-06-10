import Foundation
import Observation

/// Count-up stopwatch for timing rest between sets. Owned by `LiveWorkoutView`
/// (not the sheet) so it keeps running while the drawer is dismissed and
/// reopened. Elapsed time is computed from a start `Date` plus accumulated
/// paused time, so it stays accurate even if the periodic tick is throttled.
@Observable
@MainActor
final class RestStopwatch {
    private(set) var elapsed: TimeInterval = 0
    private(set) var isRunning = false

    /// When running, the moment the current run began. nil while paused.
    private var startDate: Date?
    /// Total elapsed from previous (paused) runs, excluding the current run.
    private var accumulated: TimeInterval = 0
    /// Drives the visible tick. Cancelled on pause/reset.
    private var ticker: Task<Void, Never>?

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startDate = Date()
        // The class is @MainActor, so this Task inherits main-actor isolation.
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.tick()
            }
        }
    }

    func pause() {
        guard isRunning else { return }
        if let startDate {
            accumulated += Date().timeIntervalSince(startDate)
        }
        elapsed = accumulated
        startDate = nil
        isRunning = false
        ticker?.cancel()
        ticker = nil
    }

    /// Stops and zeroes the stopwatch.
    func reset() {
        ticker?.cancel()
        ticker = nil
        startDate = nil
        accumulated = 0
        elapsed = 0
        isRunning = false
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    private func tick() {
        guard let startDate else { return }
        elapsed = accumulated + Date().timeIntervalSince(startDate)
    }

    /// "m:ss" rendering of the current elapsed time.
    var formatted: String {
        let total = Int(elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
