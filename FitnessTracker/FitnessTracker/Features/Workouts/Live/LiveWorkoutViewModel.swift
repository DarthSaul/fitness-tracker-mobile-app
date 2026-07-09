import Foundation
import Observation
import OSLog

/// Drives the live (in-progress) workout screen.
///
/// Consumes `getActiveWorkout` to load the current session, then exposes
/// derived "buckets" for the three flavors of CompletedSet that share the
/// `CompletedSetDTO` shape:
///   1. **Template** sets — `exerciseSetId` non-nil → keyed by `exerciseSetId`
///   2. **Extra**    sets — `programExerciseId` non-nil, `exerciseSetId` nil → list per programExercise
///   3. **Ad-hoc**   sets — both nil, `adhocExerciseName` non-nil → flat list
///
/// Server already pre-applies exercise swaps to `day.exerciseGroups[].exercises[].exercise`,
/// so the UI can render `day` directly; the swap map is kept locally for "swapped" indicators.
@Observable
@MainActor
final class LiveWorkoutViewModel {
    // MARK: - State
    var session: ActiveWorkoutResponseDTO.ActiveWorkoutSession?
    var day: ProgramDayDTO?

    private(set) var completedByExerciseSetId: [String: CompletedSetDTO] = [:]
    private(set) var extraSetsByProgramExerciseId: [String: [CompletedSetDTO]] = [:]
    private(set) var adhocSets: [CompletedSetDTO] = []
    private(set) var swapsByProgramExerciseId: [String: WorkoutExerciseSwapDTO] = [:]
    /// Per-exercise "user pressed Complete" flag. The server has no field for
    /// it, so it's persisted device-locally via `MarkedCompleteStore` (keyed by
    /// session id) and reloaded in `apply(_:)` — surviving view dismissal.
    private(set) var markedCompleteExerciseIds: Set<String> = []
    // MARK: Core workout (server-backed)
    /// The fetched core-exercise catalog (GET /api/exercises/core), for the picker.
    private(set) var coreCatalog: [ExerciseDTO] = []
    /// The exercises the user has added to the circuit, in order. Seeded from the
    /// saved `coreWorkout` on load; edited locally until "Save" persists it.
    private(set) var coreSelectedExercises: [ExerciseDTO] = []
    /// Last-known server state of the saved circuit (also mirrored onto `session`).
    private(set) var coreWorkout: CoreWorkoutDTO?
    /// Raw text inputs for the per-set work / rest seconds. Number of sets is the
    /// number of selected exercises.
    var coreSetupTimeText: String = ""
    var coreSetupRestText: String = ""
    /// Whether the circuit is "Saved" (locked) — freezes the setup fields and
    /// hides the per-exercise delete controls until the user taps "Edit".
    var isCoreWorkoutLocked = false
    /// In-flight PUT for the circuit.
    var isSavingCore = false

    var isLoading = false
    var isCompleting = false
    var isAbandoning = false
    var loadError: String?
    var actionError: String?

    // MARK: - Dependencies
    private let repository: WorkoutRepository
    private let sessionManager: SessionManager
    /// Persists the per-exercise "marked complete" flags locally (see store doc).
    private let markedCompleteStore: MarkedCompleteStore

    init(
        repository: WorkoutRepository,
        sessionManager: SessionManager,
        markedCompleteStore: MarkedCompleteStore = MarkedCompleteStore()
    ) {
        self.repository = repository
        self.sessionManager = sessionManager
        self.markedCompleteStore = markedCompleteStore
    }

    // MARK: - Derived

    var totalTemplateSets: Int {
        guard let day else { return 0 }
        return day.exerciseGroups.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.count } }
    }

    var loggedTemplateSetCount: Int {
        completedByExerciseSetId.count
    }

    func completedSet(forExerciseSetId id: String) -> CompletedSetDTO? {
        completedByExerciseSetId[id]
    }

    func extraSets(forProgramExerciseId id: String) -> [CompletedSetDTO] {
        extraSetsByProgramExerciseId[id] ?? []
    }

    /// Most recently logged set for one exercise — across its template sets and
    /// any extra sets — picked by `completedAt`. Drives the "Copy previous set"
    /// button. `excludingCompletedSetId` skips the set currently being edited so
    /// re-opening an existing log doesn't offer to copy itself.
    func mostRecentLoggedSet(
        programExerciseId: String,
        templateSetIds: [String],
        excludingCompletedSetId: String? = nil
    ) -> CompletedSetDTO? {
        let templateLogged = templateSetIds.compactMap { completedByExerciseSetId[$0] }
        let extras = extraSets(forProgramExerciseId: programExerciseId)
        return (templateLogged + extras)
            .filter { $0.id != excludingCompletedSetId }
            .max { $0.completedAt < $1.completedAt }
    }

    /// Server pre-applies swaps to `day`, so the displayed exercise is the new one;
    /// this map only tells the UI which slots have a swap badge.
    func isSwapped(programExerciseId: String) -> Bool {
        swapsByProgramExerciseId[programExerciseId] != nil
    }

    // MARK: - Mark complete (in-memory)

    func isMarkedComplete(programExerciseId: String) -> Bool {
        markedCompleteExerciseIds.contains(programExerciseId)
    }

    func toggleMarkedComplete(programExerciseId: String) {
        if markedCompleteExerciseIds.contains(programExerciseId) {
            markedCompleteExerciseIds.remove(programExerciseId)
        } else {
            markedCompleteExerciseIds.insert(programExerciseId)
        }
        // Persist locally so the checkmark survives leaving/returning the view.
        if let sessionId = session?.id {
            markedCompleteStore.save(markedCompleteExerciseIds, sessionId: sessionId)
        }
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            guard let response = try await repository.getActiveWorkout() else {
                self.session = nil
                self.day = nil
                return
            }
            apply(response)
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch {
            Logger.data.error("LiveWorkoutViewModel.load failed: \(error)")
            loadError = error.localizedDescription
        }
    }

    private func apply(_ response: ActiveWorkoutResponseDTO) {
        self.session = response.session
        self.day = response.day
        self.markedCompleteExerciseIds = markedCompleteStore.load(sessionId: response.session.id)
        rebuildCompletedSetBuckets(from: response.session.completedSets)
        // Restore a saved core circuit (Setup + ordered list). When none is
        // saved, leave any in-progress local edits untouched.
        if let cw = response.session.coreWorkout {
            adoptCoreWorkout(cw)
        } else {
            self.coreWorkout = nil
        }
        self.swapsByProgramExerciseId = Dictionary(
            response.session.workoutExerciseSwaps.map { ($0.programExerciseId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func rebuildCompletedSetBuckets(from sets: [CompletedSetDTO]) {
        var template: [String: CompletedSetDTO] = [:]
        var extra: [String: [CompletedSetDTO]] = [:]
        var adhoc: [CompletedSetDTO] = []

        for set in sets {
            if let id = set.exerciseSetId {
                template[id] = set
            } else if let peId = set.programExerciseId {
                extra[peId, default: []].append(set)
            } else if set.adhocExerciseName != nil {
                adhoc.append(set)
            }
        }

        self.completedByExerciseSetId = template
        self.extraSetsByProgramExerciseId = extra
        self.adhocSets = adhoc
    }

    // MARK: - Set logging (template)

    /// Routes between record (POST) and update (PATCH) based on whether a
    /// CompletedSet already exists for this template set id.
    @discardableResult
    func logSet(
        exerciseSetId: String,
        reps: Int?, weight: Double?, rpe: Double?, notes: String?
    ) async -> Bool {
        guard let session else { return false }
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
                    body: RecordSetBody(exerciseSetId: exerciseSetId, reps: reps, weight: weight, rpe: rpe, notes: notes)
                )
                completedByExerciseSetId[exerciseSetId] = created
            }
            return true
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
            return false
        } catch {
            Logger.data.error("logSet failed: \(error)")
            actionError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteLoggedSet(exerciseSetId: String) async -> Bool {
        guard let session, let existing = completedByExerciseSetId[exerciseSetId] else { return false }
        actionError = nil
        do {
            try await repository.deleteSet(workoutId: session.id, setId: existing.id)
            completedByExerciseSetId.removeValue(forKey: exerciseSetId)
            return true
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
            return false
        } catch {
            Logger.data.error("deleteLoggedSet failed: \(error)")
            actionError = error.localizedDescription
            return false
        }
    }

    // MARK: - Extra sets

    @discardableResult
    func addExtraSet(programExerciseId: String, reps: Int?, weight: Double?, rpe: Double?, notes: String?) async -> Bool {
        guard let session else { return false }
        actionError = nil
        do {
            let created = try await repository.addExtraSet(
                workoutId: session.id, programExerciseId: programExerciseId,
                body: AddExtraSetBody(reps: reps, weight: weight, rpe: rpe, notes: notes)
            )
            extraSetsByProgramExerciseId[programExerciseId, default: []].append(created)
            return true
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
            return false
        } catch {
            Logger.data.error("addExtraSet failed: \(error)")
            actionError = error.localizedDescription
            return false
        }
    }

    func deleteExtraSet(programExerciseId: String, completedSetId: String) async {
        guard let session else { return }
        actionError = nil
        do {
            try await repository.deleteExtraSet(workoutId: session.id, completedSetId: completedSetId)
            extraSetsByProgramExerciseId[programExerciseId]?.removeAll { $0.id == completedSetId }
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch {
            Logger.data.error("deleteExtraSet failed: \(error)")
            actionError = error.localizedDescription
        }
    }

    // MARK: - Ad-hoc sets

    func addAdHocExercise(name: String) async {
        guard let session else { return }
        actionError = nil
        do {
            let created = try await repository.addAdHocSet(workoutId: session.id, exerciseName: name)
            adhocSets.append(created)
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch {
            Logger.data.error("addAdHocExercise failed: \(error)")
            actionError = error.localizedDescription
        }
    }

    func deleteAdHocSet(id: String) async {
        guard let session else { return }
        actionError = nil
        do {
            // Server deletes ad-hoc sets via the same /sets/:setId endpoint
            // (they're CompletedSets without a template anchor).
            try await repository.deleteSet(workoutId: session.id, setId: id)
            adhocSets.removeAll { $0.id == id }
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch {
            Logger.data.error("deleteAdHocSet failed: \(error)")
            actionError = error.localizedDescription
        }
    }

    // MARK: - Core workout
    //
    // A per-session timed circuit persisted server-side (see CoreWorkoutDTO).
    // The exercise list is edited locally, then persisted with `saveCoreWorkout`.

    /// Estimated total duration in seconds: `sets × (time + rest)`, where sets is
    /// the number of selected exercises. Nil unless there's at least one exercise
    /// and a positive time/rest total; blank time/rest count as 0.
    var coreEstimatedSeconds: Int? {
        let sets = coreSelectedExercises.count
        guard sets > 0 else { return nil }
        let total = sets * (coreTimeSeconds + coreRestSeconds)
        return total > 0 ? total : nil
    }

    var coreTimeSeconds: Int { Int(coreSetupTimeText.trimmingCharacters(in: .whitespaces)) ?? 0 }
    var coreRestSeconds: Int { Int(coreSetupRestText.trimmingCharacters(in: .whitespaces)) ?? 0 }

    /// Fetches the core-exercise catalog once (idempotent).
    func loadCoreCatalog() async {
        guard coreCatalog.isEmpty else { return }
        do {
            coreCatalog = try await repository.getCoreExercises()
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch {
            Logger.data.error("loadCoreCatalog failed: \(error)")
            actionError = error.localizedDescription
        }
    }

    /// Appends a catalog exercise to the circuit (no-op if already present).
    /// Local only — persisted on the next `saveCoreWorkout`.
    func addCoreExercise(_ exercise: ExerciseDTO) {
        guard !coreSelectedExercises.contains(where: { $0.id == exercise.id }) else { return }
        coreSelectedExercises.append(exercise)
    }

    /// Removes an exercise from the circuit (local only).
    func removeCoreExercise(_ exercise: ExerciseDTO) {
        coreSelectedExercises.removeAll { $0.id == exercise.id }
    }

    /// Persists the circuit (PUT), then locks it. Requires a session, ≥1 exercise
    /// and a positive work time. Mirrors the saved circuit back onto `session`.
    @discardableResult
    func saveCoreWorkout() async -> Bool {
        guard let session, !isSavingCore else { return false }
        let exerciseIds = coreSelectedExercises.map(\.id)
        guard !exerciseIds.isEmpty, coreTimeSeconds > 0 else {
            actionError = "Add at least one exercise and a work time before saving."
            return false
        }
        isSavingCore = true
        actionError = nil
        defer { isSavingCore = false }
        do {
            let saved = try await repository.saveCoreWorkout(
                sessionId: session.id,
                timeSeconds: coreTimeSeconds,
                restSeconds: coreRestSeconds,
                exerciseIds: exerciseIds
            )
            adoptCoreWorkout(saved)
            return true
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
            return false
        } catch {
            Logger.data.error("saveCoreWorkout failed: \(error)")
            actionError = error.localizedDescription
            return false
        }
    }

    /// Marks the saved circuit complete (best-effort) — called when the timer
    /// finishes naturally. No-op if nothing is saved or it's already complete.
    func completeCoreWorkoutIfNeeded() async {
        guard let session, let cw = coreWorkout, cw.completedAt == nil else { return }
        do {
            let updated = try await repository.completeCoreWorkout(sessionId: session.id)
            self.coreWorkout = updated
            self.session?.coreWorkout = updated
        } catch {
            // Best-effort — the timer already ran; don't surface a UI error.
            Logger.data.error("completeCoreWorkout failed: \(error)")
        }
    }

    /// Adopts a saved circuit as the source of truth: restores Setup + the
    /// ordered exercise list, locks the view, and mirrors it onto `session`.
    private func adoptCoreWorkout(_ cw: CoreWorkoutDTO) {
        self.coreWorkout = cw
        self.session?.coreWorkout = cw
        self.coreSetupTimeText = String(cw.timeSeconds)
        self.coreSetupRestText = String(cw.restSeconds)
        self.coreSelectedExercises = cw.orderedExercises
        self.isCoreWorkoutLocked = true
    }

    // MARK: - Swap

    /// Swaps an exercise. Server returns `deletedSetCount` so callers can warn
    /// the user about lost progress; we re-fetch the workout to pick up the
    /// pre-applied swap on `day.exerciseGroups[].exercises[].exercise`.
    @discardableResult
    func swap(programExerciseId: String, replacementExerciseId: String) async -> Int? {
        guard let session else { return nil }
        actionError = nil
        do {
            let response = try await repository.swapExercise(
                workoutId: session.id,
                programExerciseId: programExerciseId,
                replacementExerciseId: replacementExerciseId
            )
            await load()
            return response.deletedSetCount
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
            return nil
        } catch {
            Logger.data.error("swap failed: \(error)")
            actionError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Workout notes

    var workoutNotes: String {
        session?.notes ?? ""
    }

    /// Persists workout-level notes via PATCH /api/workouts/:id. Returns true
    /// on success. Mirrors the server `notes` back onto the local session so
    /// the collapsed card's "has notes" state stays accurate without a reload.
    @discardableResult
    func updateNotes(_ notes: String) async -> Bool {
        guard let session else { return false }
        actionError = nil
        do {
            let response = try await repository.updateNotes(workoutId: session.id, notes: notes)
            self.session?.notes = response.notes
            return true
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
            return false
        } catch {
            Logger.data.error("updateNotes failed: \(error)")
            actionError = error.localizedDescription
            return false
        }
    }

    // MARK: - Finalize / discard

    func completeWorkout() async -> Bool {
        guard let session, !isCompleting else { return false }
        isCompleting = true
        actionError = nil
        defer { isCompleting = false }

        do {
            // completedAt: nil → server uses "now".
            _ = try await repository.completeWorkout(id: session.id, completedAt: nil)
            markedCompleteStore.clear(sessionId: session.id)
            return true
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
            return false
        } catch {
            Logger.data.error("completeWorkout failed: \(error)")
            actionError = error.localizedDescription
            return false
        }
    }

    func abandonWorkout() async -> Bool {
        guard let session, !isAbandoning else { return false }
        isAbandoning = true
        actionError = nil
        defer { isAbandoning = false }
        do {
            try await repository.abandonWorkout(id: session.id)
            markedCompleteStore.clear(sessionId: session.id)
            self.session = nil
            self.day = nil
            return true
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
            return false
        } catch {
            Logger.data.error("abandonWorkout failed: \(error)")
            actionError = error.localizedDescription
            return false
        }
    }
}

