import Foundation
import Observation

/// Drives the "Start" core workout: an interval timer that steps through a
/// schedule of work / rest phases built from the Core setup (Sets · Time · Rest).
///
/// For sets = 6, time = 45, rest = 15 the schedule is 6 × (45s work + 15s rest) =
/// 360s. Each set's work phase shows a core exercise (cycling through the added
/// list); each rest phase shows "Rest".
///
/// Like `RestStopwatch`, elapsed time is derived from a start `Date` plus paused
/// accumulation, so the current phase / countdown stay accurate even if the tick
/// is throttled. The phase and remaining-seconds derivations are pure functions
/// of an elapsed value so they can be unit-tested without waiting on the ticker.
@Observable
@MainActor
final class CoreWorkoutTimer: Identifiable {
    struct Phase: Equatable {
        enum Kind { case work, rest }
        let kind: Kind
        let label: String
        let duration: Int   // seconds
        let setNumber: Int  // 1-based
    }

    let id = UUID()
    let phases: [Phase]
    let totalSets: Int
    let totalDuration: Int

    /// Cumulative end offset (seconds) of each phase — `phases[i]` occupies
    /// `[ends[i] - duration, ends[i])`.
    private let ends: [Int]

    private(set) var elapsed: TimeInterval = 0
    private(set) var isRunning = false

    private var startDate: Date?
    private var accumulated: TimeInterval = 0
    private var ticker: Task<Void, Never>?

    init(phases: [Phase], totalSets: Int) {
        self.phases = phases
        self.totalSets = totalSets
        var running = 0
        var ends: [Int] = []
        for phase in phases {
            running += phase.duration
            ends.append(running)
        }
        self.ends = ends
        self.totalDuration = running
    }

    /// Builds the schedule from the Core setup: per set, a work phase (cycling
    /// through `exercises`, or "Work" if none) then a rest phase. Zero-length
    /// work / rest phases are omitted.
    convenience init(sets: Int, workSeconds: Int, restSeconds: Int, exercises: [String]) {
        var built: [Phase] = []
        for setIndex in 0..<max(0, sets) {
            let setNumber = setIndex + 1
            if workSeconds > 0 {
                let label = exercises.isEmpty ? "Work" : exercises[setIndex % exercises.count]
                built.append(Phase(kind: .work, label: label, duration: workSeconds, setNumber: setNumber))
            }
            if restSeconds > 0 {
                built.append(Phase(kind: .rest, label: "Rest", duration: restSeconds, setNumber: setNumber))
            }
        }
        self.init(phases: built, totalSets: max(0, sets))
    }

    // MARK: - Pure derivations (also exercised by tests)

    /// Index of the phase active at `seconds` elapsed, or nil once finished.
    func phaseIndex(atElapsed seconds: Int) -> Int? {
        guard !phases.isEmpty, seconds < totalDuration else { return nil }
        for (index, end) in ends.enumerated() where seconds < end {
            return index
        }
        return nil
    }

    /// Whole seconds left in the phase active at `seconds` elapsed.
    func remaining(atElapsed seconds: Int) -> Int {
        guard let index = phaseIndex(atElapsed: seconds) else { return 0 }
        return max(0, ends[index] - seconds)
    }

    // MARK: - Live state

    private var elapsedSeconds: Int { Int(elapsed) }

    var isFinished: Bool { phases.isEmpty || elapsedSeconds >= totalDuration }

    var currentPhase: Phase? {
        guard let index = phaseIndex(atElapsed: elapsedSeconds) else { return nil }
        return phases[index]
    }

    var remaining: Int { remaining(atElapsed: elapsedSeconds) }

    // MARK: - Controls

    func start() {
        guard !isRunning, !isFinished else { return }
        isRunning = true
        startDate = Date()
        // The class is @MainActor, so this Task inherits main-actor isolation.
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self else { return }
                self.tick()
                if !self.isRunning { return }
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

    func toggle() { isRunning ? pause() : start() }

    /// End early — freeze wherever we are and stop ticking. The presenter
    /// dismisses the timer on tap.
    func end() {
        if isRunning, let startDate {
            accumulated += Date().timeIntervalSince(startDate)
            elapsed = accumulated
        }
        startDate = nil
        isRunning = false
        ticker?.cancel()
        ticker = nil
    }

    private func tick() {
        guard let startDate else { return }
        elapsed = accumulated + Date().timeIntervalSince(startDate)
        if elapsedSeconds >= totalDuration {
            // Clamp to the end and stop.
            elapsed = Double(totalDuration)
            accumulated = Double(totalDuration)
            self.startDate = nil
            isRunning = false
            ticker?.cancel()
            ticker = nil
        }
    }
}
