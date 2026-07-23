import SwiftUI
import Observation

/// Tiny shared presentation flag so any view (resume banner, Home card,
/// standalone detail, etc.) can request that a live-workout cover appear
/// without prop-drilling a binding through its ancestors. RootTabView owns the
/// cover and observes this. The target says *which* live screen to show: the
/// program session (singular, fetched via /api/workouts/active) or a specific
/// standalone session by id.
@Observable
@MainActor
final class LiveWorkoutPresentation {
    enum Target: Identifiable, Equatable {
        case program
        case standalone(sessionId: String)

        var id: String {
            switch self {
            case .program: return "program"
            case .standalone(let sessionId): return "standalone-\(sessionId)"
            }
        }
    }

    var target: Target?

    /// Convenience read for views that only care about open/closed transitions
    /// (e.g. Home refreshing when the cover dismisses).
    var isPresented: Bool { target != nil }

    /// Presents the program live workout. Kept as the unqualified `present()`
    /// so the pre-standalone call sites read unchanged.
    func present() {
        target = .program
    }

    func presentStandalone(sessionId: String) {
        target = .standalone(sessionId: sessionId)
    }

    func dismiss() {
        target = nil
    }
}
