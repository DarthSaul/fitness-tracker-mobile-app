import SwiftUI
import Observation

/// Tiny shared presentation flag so any view (resume banner, Home card, etc.)
/// can request that the live-workout sheet appear without prop-drilling a
/// binding through its ancestors. RootTabView owns the sheet and observes this.
@Observable
@MainActor
final class LiveWorkoutPresentation {
    var isPresented: Bool = false

    func present() {
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }
}
