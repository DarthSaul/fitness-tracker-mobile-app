import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class WorkoutDetailViewModel {
    let workoutId: String

    var workout: ActiveWorkoutResponseDTO?
    var isLoading = false
    var loadError: Error?

    private let repository: WorkoutRepository

    init(workoutId: String, repository: WorkoutRepository) {
        self.workoutId = workoutId
        self.repository = repository
    }

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            workout = try await repository.getWorkout(id: workoutId)
        } catch {
            Logger.data.error("WorkoutDetailViewModel.load failed: \(error)")
            loadError = error
        }
    }
}
