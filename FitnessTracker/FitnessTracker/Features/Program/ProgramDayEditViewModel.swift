import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class ProgramDayEditViewModel {
    // MARK: - Inputs (immutable)
    let weekNumber: Int
    let day: ProgramDayDTO

    // MARK: - State
    var session: ActiveWorkoutResponseDTO.ActiveWorkoutSession?
    /// exerciseSetId → CompletedSetDTO. Built from session.completedSets on every refresh.
    private(set) var completedByExerciseSetId: [String: CompletedSetDTO] = [:]
    var workoutDate: Date = .now
    var isLoading = false
    var isStartingSession = false
    var isCompleting = false
    var isAbandoning = false
    var loadError: String?
    var actionError: String?

    // MARK: - Dependencies
    private let repository: WorkoutRepository
    private let onChange: () -> Void
    /// Existing session ID hint from the parent list (avoids an extra round trip
    /// when the day already has a session). nil means "no session yet".
    private let initialSessionId: String?

    init(
        weekNumber: Int,
        day: ProgramDayDTO,
        existingSessionId: String?,
        repository: WorkoutRepository,
        onChange: @escaping () -> Void
    ) {
        self.weekNumber = weekNumber
        self.day = day
        self.initialSessionId = existingSessionId
        self.repository = repository
        self.onChange = onChange
    }

    // MARK: - Derived

    var hasSession: Bool { session != nil }

    func completedSet(forExerciseSetId id: String) -> CompletedSetDTO? {
        completedByExerciseSetId[id]
    }

    var totalTemplateSets: Int {
        day.exerciseGroups.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.count } }
    }

    var loggedSetsCount: Int {
        completedByExerciseSetId.count
    }

    // MARK: - Load

    /// On first appear: if we have an existing session, fetch its details and pre-fill the date.
    func loadIfNeeded() async {
        guard session == nil, let sessionId = initialSessionId else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let response = try await repository.getWorkout(id: sessionId)
            applyResponse(response)
        } catch {
            Logger.data.error("loadIfNeeded failed: \(error)")
            loadError = error.localizedDescription
        }
    }

    /// User taps "Start logging" — POST a new EDITING session for this week/day.
    func startRetroactive() async {
        guard !isStartingSession else { return }
        isStartingSession = true
        actionError = nil
        defer { isStartingSession = false }
        do {
            let response = try await repository.createRetroactiveWorkout(
                weekNumber: weekNumber, dayNumber: day.dayNumber
            )
            // The fresh session has no completed sets yet; build a minimal in-memory
            // shape so the UI can render immediately without a follow-up GET.
            self.session = ActiveWorkoutResponseDTO.ActiveWorkoutSession(
                id: response.session.id,
                userId: response.session.userId,
                userProgramId: response.session.userProgramId,
                weekNumber: response.session.weekNumber,
                dayNumber: response.session.dayNumber,
                status: response.session.status,
                startedAt: response.session.startedAt,
                completedAt: response.session.completedAt,
                notes: response.session.notes,
                completedSets: [],
                userProgram: UserProgramDTO(
                    id: response.session.userProgramId,
                    userId: response.session.userId,
                    programId: "",  // Unknown without a follow-up fetch — UI doesn't need it here.
                    isActive: true,
                    currentWeek: 1, currentDay: 1,
                    startedAt: response.session.startedAt
                ),
                workoutExerciseSwaps: []
            )
            self.completedByExerciseSetId = [:]
            self.workoutDate = .now
            onChange()
        } catch {
            Logger.data.error("startRetroactive failed: \(error)")
            actionError = error.localizedDescription
        }
    }

    // MARK: - Set logging

    /// Logs a value for a template set. Routes to recordSet (POST) for new sets
    /// and updateSet (PATCH) for already-completed ones — single call site for the UI.
    func logSet(
        exerciseSetId: String,
        reps: Int?,
        weight: Double?,
        rpe: Double?,
        notes: String?
    ) async {
        guard let session else { return }
        actionError = nil
        do {
            if let existing = completedByExerciseSetId[exerciseSetId] {
                let updated = try await repository.updateSet(
                    workoutId: session.id, setId: existing.id,
                    body: UpdateSetBody(reps: reps, weight: weight, rpe: rpe, notes: notes)
                )
                completedByExerciseSetId[exerciseSetId] = updated
            } else {
                let created = try await repository.recordSet(
                    workoutId: session.id,
                    body: RecordSetBody(
                        exerciseSetId: exerciseSetId,
                        reps: reps, weight: weight, rpe: rpe, notes: notes
                    )
                )
                completedByExerciseSetId[exerciseSetId] = created
            }
            onChange()
        } catch {
            Logger.data.error("logSet failed: \(error)")
            actionError = error.localizedDescription
        }
    }

    /// Deletes a previously-logged completed set.
    func deleteLoggedSet(exerciseSetId: String) async {
        guard let session, let existing = completedByExerciseSetId[exerciseSetId] else { return }
        actionError = nil
        do {
            try await repository.deleteSet(workoutId: session.id, setId: existing.id)
            completedByExerciseSetId.removeValue(forKey: exerciseSetId)
            onChange()
        } catch {
            Logger.data.error("deleteLoggedSet failed: \(error)")
            actionError = error.localizedDescription
        }
    }

    // MARK: - Finalize / discard

    /// Sends completedAt as a noon-local date so the server stores a date that
    /// reads correctly across reasonable time-zone shifts.
    func completeWithBackdate() async -> Bool {
        guard let session, !isCompleting else { return false }
        isCompleting = true
        actionError = nil
        defer { isCompleting = false }
        let backdated = noonLocal(workoutDate)
        do {
            _ = try await repository.completeWorkout(id: session.id, completedAt: backdated)
            onChange()
            return true
        } catch {
            Logger.data.error("completeWithBackdate failed: \(error)")
            actionError = error.localizedDescription
            return false
        }
    }

    func discard() async -> Bool {
        guard let session, !isAbandoning else { return false }
        isAbandoning = true
        actionError = nil
        defer { isAbandoning = false }
        do {
            try await repository.abandonWorkout(id: session.id)
            self.session = nil
            self.completedByExerciseSetId = [:]
            onChange()
            return true
        } catch {
            Logger.data.error("discard failed: \(error)")
            actionError = error.localizedDescription
            return false
        }
    }

    // MARK: - Helpers

    private func applyResponse(_ response: ActiveWorkoutResponseDTO) {
        self.session = response.session
        self.completedByExerciseSetId = Dictionary(
            response.session.completedSets.compactMap { set -> (String, CompletedSetDTO)? in
                guard let id = set.exerciseSetId else { return nil }
                return (id, set)
            },
            uniquingKeysWith: { first, _ in first }
        )
        if let completedAt = response.session.completedAt {
            self.workoutDate = completedAt
        } else {
            self.workoutDate = response.session.startedAt
        }
    }

    private func noonLocal(_ date: Date) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = .current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = 12
        components.minute = 0
        return calendar.date(from: components) ?? date
    }
}
