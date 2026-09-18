import SwiftUI
import Observation

/// Signals that the user's program run changed (activated, paused, ended
/// early, unsaved) so surfaces holding run-keyed state in other tabs — Home's
/// active program / scheduled workouts, the resume banner — can refetch.
/// Activate can return a different run id and ending a run deletes its
/// unfinished sessions and scheduled workouts, so nothing fetched under the
/// previous run may be kept. Provided by RootTabView via `.environment(...)`.
@Observable
@MainActor
final class ProgramRunChanges {
    private(set) var revision = 0

    func notify() {
        revision += 1
    }
}
