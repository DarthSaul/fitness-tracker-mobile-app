import Foundation

/// Device-local persistence for the live-workout "mark exercise complete"
/// toggle. The server's data model has no field for a per-exercise complete
/// flag (it only persists individual logged sets), so this UI-only state would
/// otherwise reset every time the live workout reloads. We keep it in
/// `UserDefaults`, keyed by session id, so the green checkmark survives leaving
/// and returning to the active workout.
///
/// Keys are cleared when a session is completed or abandoned so finished
/// sessions don't accumulate stale entries.
struct MarkedCompleteStore {
    private let defaults: UserDefaults
    private let keyPrefix = "markedComplete."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(forSessionId sessionId: String) -> String {
        keyPrefix + sessionId
    }

    /// The set of `programExerciseId`s the user has marked complete for a session.
    func load(sessionId: String) -> Set<String> {
        let ids = defaults.stringArray(forKey: key(forSessionId: sessionId)) ?? []
        return Set(ids)
    }

    func save(_ ids: Set<String>, sessionId: String) {
        defaults.set(Array(ids), forKey: key(forSessionId: sessionId))
    }

    func clear(sessionId: String) {
        defaults.removeObject(forKey: key(forSessionId: sessionId))
    }
}
