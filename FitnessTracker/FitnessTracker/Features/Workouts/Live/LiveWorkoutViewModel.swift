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

    /// Bound to a TextEditor in the view; user edits schedule a debounced save.
    /// Server-driven assignments (apply / swap-then-load) toggle
    /// `isApplyingServerState` so they don't loop back through the debounced
    /// save (which would re-POST the value the server just sent us, and could
    /// even clobber a newer in-flight local edit).
    var notes: String = "" {
        didSet {
            guard !isApplyingServerState else { return }
            isNotesDirty = true
            scheduleNotesSave()
        }
    }
    private(set) var notesSaveState: NotesSaveState = .idle
    /// True after a user edit until the next successful `persistNotes` for
    /// the same value. Prevents `apply()` from overwriting unsaved local edits
    /// with the older server value mid-debounce.
    private var isNotesDirty = false
    /// Set to true while assigning server-loaded state so `notes.didSet`
    /// can distinguish user-driven edits from internal hydration.
    private var isApplyingServerState = false

    var isLoading = false
    var isCompleting = false
    var isAbandoning = false
    var loadError: String?
    var actionError: String?

    // MARK: - Dependencies
    private let repository: WorkoutRepository
    private let sessionManager: SessionManager
    private var notesSaveTask: Task<Void, Never>?

    init(repository: WorkoutRepository, sessionManager: SessionManager) {
        self.repository = repository
        self.sessionManager = sessionManager
    }
    // No deinit cleanup needed: scheduleNotesSave's Task uses [weak self] so
    // it doesn't keep this VM alive after the view goes away. If the VM is
    // released mid-debounce, the closure resolves to a nil self and is a no-op.

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

    /// Server pre-applies swaps to `day`, so the displayed exercise is the new one;
    /// this map only tells the UI which slots have a swap badge.
    func isSwapped(programExerciseId: String) -> Bool {
        swapsByProgramExerciseId[programExerciseId] != nil
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
        isApplyingServerState = true
        defer { isApplyingServerState = false }

        self.session = response.session
        self.day = response.day
        // Don't clobber an in-progress local edit. If the user has typed
        // something the server hasn't seen yet, leave `notes` alone — the
        // pending debounce (or an explicit flush) will get it across.
        if !isNotesDirty {
            self.notes = response.session.notes ?? ""
            self.notesSaveState = .idle
        }
        rebuildCompletedSetBuckets(from: response.session.completedSets)
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

    // MARK: - Notes auto-save

    private func scheduleNotesSave() {
        notesSaveTask?.cancel()
        notesSaveState = .pending
        let snapshot = notes
        notesSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)  // 0.6s quiet window
            if Task.isCancelled { return }
            await self?.persistNotes(snapshot)
        }
    }

    private func persistNotes(_ value: String) async {
        guard let session else { return }
        notesSaveState = .saving
        do {
            _ = try await repository.updateNotes(workoutId: session.id, notes: value)
            notesSaveState = .saved
            // Only clear the dirty flag if no newer edit slipped in while we
            // were saving — otherwise the next debounce will pick it up.
            if value == notes {
                isNotesDirty = false
            }
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch {
            Logger.data.error("notes save failed: \(error)")
            notesSaveState = .failed
        }
    }

    /// Synchronously persist any pending debounced notes save before tearing
    /// down the session. Used by `completeWorkout()` so a user who taps
    /// Complete inside the 0.6s debounce window doesn't lose their last edit.
    private func flushPendingNotes() async {
        // Cancel the in-flight debounce so it can't race us, then save now if
        // there are unsaved local edits.
        notesSaveTask?.cancel()
        notesSaveTask = nil
        guard isNotesDirty, session != nil else { return }
        await persistNotes(notes)
    }

    // MARK: - Finalize / discard

    func completeWorkout() async -> Bool {
        guard let session, !isCompleting else { return false }
        isCompleting = true
        actionError = nil
        defer { isCompleting = false }

        // Flush any pending debounced notes save first — otherwise a user who
        // tapped Complete inside the 0.6s debounce window would lose the last
        // edit when the sheet dismisses and the debounce task is cancelled.
        await flushPendingNotes()

        do {
            // completedAt: nil → server uses "now".
            _ = try await repository.completeWorkout(id: session.id, completedAt: nil)
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

enum NotesSaveState: Sendable, Equatable {
    case idle
    case pending
    case saving
    case saved
    case failed
}
