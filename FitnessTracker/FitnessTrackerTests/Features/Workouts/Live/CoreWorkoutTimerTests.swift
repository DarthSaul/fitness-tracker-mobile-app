import Foundation
import Testing
@testable import FitnessTracker

@Suite("CoreWorkoutTimer")
@MainActor
struct CoreWorkoutTimerTests {
    @Test("builds work+rest phases per set, cycling exercises")
    func schedule() {
        let timer = CoreWorkoutTimer(sets: 3, workSeconds: 45, restSeconds: 15, exercises: ["A", "B"])

        #expect(timer.phases.count == 6)                       // 3 sets × (work + rest)
        #expect(timer.totalDuration == 3 * (45 + 15))          // 180 → matches "6:00"-style estimate
        #expect(timer.phases.map(\.kind) == [.work, .rest, .work, .rest, .work, .rest])
        // Exercises cycle A, B, A across the three work phases.
        #expect(timer.phases.filter { $0.kind == .work }.map(\.label) == ["A", "B", "A"])
        #expect(timer.phases.map(\.setNumber) == [1, 1, 2, 2, 3, 3])
    }

    @Test("omits zero-length rest phases")
    func noRest() {
        let timer = CoreWorkoutTimer(sets: 2, workSeconds: 30, restSeconds: 0, exercises: ["A"])

        #expect(timer.phases.count == 2)
        #expect(timer.phases.allSatisfy { $0.kind == .work })
        #expect(timer.totalDuration == 60)
    }

    @Test("labels work phases \"Work\" when no exercises are added")
    func genericWork() {
        let timer = CoreWorkoutTimer(sets: 1, workSeconds: 20, restSeconds: 10, exercises: [])
        #expect(timer.phases.first?.label == "Work")
    }

    @Test("phase index + remaining track elapsed across boundaries")
    func phaseAtElapsed() {
        // 0..45 work (set 1), 45..60 rest, 60..105 work (set 2), 105..120 rest.
        let timer = CoreWorkoutTimer(sets: 2, workSeconds: 45, restSeconds: 15, exercises: ["A"])

        #expect(timer.phaseIndex(atElapsed: 0) == 0)
        #expect(timer.remaining(atElapsed: 0) == 45)
        #expect(timer.remaining(atElapsed: 44) == 1)
        #expect(timer.phaseIndex(atElapsed: 45) == 1)                 // rest starts
        #expect(timer.phases[timer.phaseIndex(atElapsed: 45)!].kind == .rest)
        #expect(timer.remaining(atElapsed: 45) == 15)
        #expect(timer.phaseIndex(atElapsed: 60) == 2)                 // set 2 work
        #expect(timer.phaseIndex(atElapsed: 119) == 3)                // last rest
        #expect(timer.phaseIndex(atElapsed: 120) == nil)             // finished
    }

    @Test("empty schedule is finished immediately")
    func emptyFinished() {
        let timer = CoreWorkoutTimer(sets: 0, workSeconds: 45, restSeconds: 15, exercises: [])
        #expect(timer.phases.isEmpty)
        #expect(timer.isFinished)
    }
}
