import Foundation
import Observation
import OSLog

/// Drives the live (in-progress) standalone workout screen. Mirrors
/// `LiveWorkoutViewModel`, minus the program-only machinery (swaps, extra-set
/// endpoint, core circuit, workout notes — none exist for standalone sessions).
///
/// Two flavors of completed set share `StandaloneCompletedSetDTO`:
///   1. **Prescribed** sets — `standaloneWorkoutSetId` non-nil → keyed by that id
///   2. **Ad-hoc** sets — `adhocExerciseName` non-nil → bucketed by name
///
/// "Add set" on an exercise card logs an ad-hoc set carrying that exercise's
/// name (the standalone API has no per-exercise extra-set endpoint), so ad-hoc
/// sets whose name matches a template exercise render as extra rows under it;
/// the rest render in the trailing Ad-hoc section.
@Observable
@MainActor
final class StandaloneLiveWorkoutViewModel {
    // MARK: - State
    let sessionId: String
    var session: StandaloneSessionDetailResponseDTO.SessionWithSets?
    var workout: StandaloneWorkoutDetailDTO?

    private(set) var completedByTemplateSetId: [String: StandaloneCompletedSetDTO] = [:]
    private(set) var adhocSets: [StandaloneCompletedSetDTO] = []
    /// Per-exercise "user pressed Complete" flag, persisted device-locally via
    /// `MarkedCompleteStore` (keyed by session id) — same as the program flow.
    private(set) var markedCompleteExerciseIds: Set<String> = []

    /// Starts true so the cover's first frame renders the spinner instead of
    /// flashing the "no active workout" empty state before `.task` runs load().
    var isLoading = true
    var isCompleting = false
    var isAbandoning = false
    /// In-flight guard for `addAdhocExercise` — rapid taps on a search-sheet
    /// row would otherwise fire concurrent POSTs and create duplicate ad-hoc
    /// sets (the server allows any number of same-named logs).
    private(set) var isAddingAdhocExercise = false
    var loadError: String?
    var actionError: String?

    // MARK: - Dependencies
    private let repository: StandaloneWorkoutRepository
    private let sessionManager: SessionManager
    private let markedCompleteStore: MarkedCompleteStore

    init(
        sessionId: String,
        repository: StandaloneWorkoutRepository,
        sessionManager: SessionManager,
        markedCompleteStore: MarkedCompleteStore = MarkedCompleteStore()
    ) {
        self.sessionId = sessionId
        self.repository = repository
        self.sessionManager = sessionManager
        self.markedCompleteStore = markedCompleteStore
    }

    // MARK: - Derived

    var workoutDisplayName: String {
        workout?.displayName ?? "Workout"
    }

    var totalTemplateSets: Int {
        guard let workout else { return 0 }
        return workout.groups.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.count } }
    }

    var loggedTemplateSetCount: Int {
        completedByTemplateSetId.count
    }

    func completedSet(forTemplateSetId id: String) -> StandaloneCompletedSetDTO? {
        completedByTemplateSetId[id]
    }

    /// Ad-hoc sets logged under a template exercise's name — the standalone
    /// analog of the program flow's "extra sets", ordered by log time.
    func extraSets(forExerciseName name: String) -> [StandaloneCompletedSetDTO] {
        adhocSets
            .filter { $0.adhocExerciseName == name }
            .sorted { $0.completedAt < $1.completedAt }
    }

    /// Ad-hoc sets whose name doesn't match any template exercise — rendered
    /// in the standalone "Ad-hoc" section like the program screen's.
    var unmatchedAdhocSets: [StandaloneCompletedSetDTO] {
        adhocSets.filter { set in
            guard let name = set.adhocExerciseName else { return false }
            return !templateExerciseNames.contains(name)
        }
    }

    private var templateExerciseNames: Set<String> {
        guard let workout else { return [] }
        return Set(workout.groups.flatMap { $0.exercises.map(\.exercise.name) })
    }

    /// Most recently logged set for one exercise — across its prescribed sets
    /// and any same-named ad-hoc sets — picked by `completedAt`. Drives the
    /// "Copy previous set" button in the shared SetLogSheet.
    func mostRecentLoggedSet(
        exerciseName: String,
        templateSetIds: [String],
        excludingCompletedSetId: String? = nil
    ) -> StandaloneCompletedSetDTO? {
        let templateLogged = templateSetIds.compactMap { completedByTemplateSetId[$0] }
        let extras = extraSets(forExerciseName: exerciseName)
        return (templateLogged + extras)
            .filter { $0.id != excludingCompletedSetId }
            .max { $0.completedAt < $1.completedAt }
    }

    // MARK: - Mark complete (device-local)

    func isMarkedComplete(exerciseId: String) -> Bool {
        markedCompleteExerciseIds.contains(exerciseId)
    }

    func toggleMarkedComplete(exerciseId: String) {
        if markedCompleteExerciseIds.contains(exerciseId) {
            markedCompleteExerciseIds.remove(exerciseId)
        } else {
            markedCompleteExerciseIds.insert(exerciseId)
        }
        markedCompleteStore.save(markedCompleteExerciseIds, sessionId: sessionId)
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            apply(try await repository.fetchSession(id: sessionId))
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch {
            Logger.data.error("StandaloneLiveWorkoutViewModel.load failed: \(error)")
            loadError = error.localizedDescription
        }
    }

    private func apply(_ response: StandaloneSessionDetailResponseDTO) {
        self.session = response.session
        self.workout = response.workout
        self.markedCompleteExerciseIds = markedCompleteStore.load(sessionId: sessionId)
        rebuildCompletedSetBuckets(from: response.session.completedSets)
    }

    private func rebuildCompletedSetBuckets(from sets: [StandaloneCompletedSetDTO]) {
        var template: [String: StandaloneCompletedSetDTO] = [:]
        var adhoc: [StandaloneCompletedSetDTO] = []

        for set in sets {
            if let id = set.standaloneWorkoutSetId {
                template[id] = set
            } else if set.adhocExerciseName != nil {
                adhoc.append(set)
            }
        }

        self.completedByTemplateSetId = template
        self.adhocSets = adhoc
    }

    // MARK: - Set logging (prescribed)

    /// Routes between record (POST) and update (PATCH) based on whether a
    /// completed set already exists for this template set id. A 409 on record
    /// means the set was already logged (e.g. from another device) — reload so
    /// the local buckets pick it up, and treat it as success.
    @discardableResult
    func logSet(
        templateSetId: String,
        reps: Int?, weight: Double?, rpe: Double?, notes: String?
    ) async -> Bool {
        actionError = nil
        do {
            if let existing = completedByTemplateSetId[templateSetId] {
                let updated = try await repository.updateSet(
                    sessionId: sessionId, setId: existing.id,
                    body: UpdateSetBody(reps: reps, weight: weight, rpe: rpe, notes: notes)
                )
                completedByTemplateSetId[templateSetId] = updated
            } else {
                let created = try await repository.recordSet(
                    sessionId: sessionId,
                    standaloneWorkoutSetId: templateSetId,
                    reps: reps, weight: weight, rpe: rpe, notes: notes
                )
                completedByTemplateSetId[templateSetId] = created
            }
            return true
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
            return false
        } catch APIError.httpError(let statusCode, _, _) where statusCode == 409 {
            await load()
            return true
        } catch {
            Logger.data.error("logSet failed: \(error)")
            actionError = error.localizedDescription
            return false
        }
    }

    /// Un-logs a prescribed set. 404 = already gone — treat as success so the
    /// row can be logged again either way.
    @discardableResult
    func deleteLoggedSet(templateSetId: String) async -> Bool {
        guard let existing = completedByTemplateSetId[templateSetId] else { return false }
        actionError = nil
        do {
            try await repository.deleteSet(sessionId: sessionId, setId: existing.id)
            completedByTemplateSetId.removeValue(forKey: templateSetId)
            return true
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
            return false
        } catch APIError.httpError(let statusCode, _, _) where statusCode == 404 {
            completedByTemplateSetId.removeValue(forKey: templateSetId)
            return true
        } catch {
            Logger.data.error("deleteLoggedSet failed: \(error)")
            actionError = error.localizedDescription
            return false
        }
    }

    // MARK: - Ad-hoc sets

    /// "Add set" under a template exercise — an ad-hoc set carrying the
    /// exercise's name so it buckets back under that card.
    @discardableResult
    func addExtraSet(exerciseName: String, reps: Int?, weight: Double?, rpe: Double?, notes: String?) async -> Bool {
        actionError = nil
        do {
            let created = try await repository.recordAdhocSet(
                sessionId: sessionId, exerciseName: exerciseName,
                reps: reps, weight: weight, rpe: rpe, notes: notes
            )
            adhocSets.append(created)
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

    /// "Add exercise" — a bare ad-hoc set for an off-plan exercise name.
    func addAdhocExercise(name: String) async {
        guard !isAddingAdhocExercise else { return }
        isAddingAdhocExercise = true
        defer { isAddingAdhocExercise = false }
        actionError = nil
        do {
            let created = try await repository.recordAdhocSet(sessionId: sessionId, exerciseName: name)
            adhocSets.append(created)
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch {
            Logger.data.error("addAdhocExercise failed: \(error)")
            actionError = error.localizedDescription
        }
    }

    func deleteAdhocSet(id: String) async {
        actionError = nil
        do {
            try await repository.deleteSet(sessionId: sessionId, setId: id)
            adhocSets.removeAll { $0.id == id }
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch APIError.httpError(let statusCode, _, _) where statusCode == 404 {
            adhocSets.removeAll { $0.id == id }
        } catch {
            Logger.data.error("deleteAdhocSet failed: \(error)")
            actionError = error.localizedDescription
        }
    }

    // MARK: - Finalize / discard

    /// Completes the session (partial is fine — unlogged sets aren't required).
    /// 409 = already completed — treat as success.
    func completeWorkout() async -> Bool {
        guard !isCompleting else { return false }
        isCompleting = true
        actionError = nil
        defer { isCompleting = false }
        do {
            _ = try await repository.completeSession(id: sessionId)
            markedCompleteStore.clear(sessionId: sessionId)
            return true
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
            return false
        } catch APIError.httpError(let statusCode, _, _) where statusCode == 409 {
            markedCompleteStore.clear(sessionId: sessionId)
            return true
        } catch {
            Logger.data.error("completeWorkout failed: \(error)")
            actionError = error.localizedDescription
            return false
        }
    }

    /// Abandons the session — the server deletes it and all logged sets.
    /// 404 = already gone — treat as success.
    func abandonWorkout() async -> Bool {
        guard !isAbandoning else { return false }
        isAbandoning = true
        actionError = nil
        defer { isAbandoning = false }
        do {
            try await repository.abandonSession(id: sessionId)
            markedCompleteStore.clear(sessionId: sessionId)
            return true
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
            return false
        } catch APIError.httpError(let statusCode, _, _) where statusCode == 404 {
            markedCompleteStore.clear(sessionId: sessionId)
            return true
        } catch {
            Logger.data.error("abandonWorkout failed: \(error)")
            actionError = error.localizedDescription
            return false
        }
    }
}
