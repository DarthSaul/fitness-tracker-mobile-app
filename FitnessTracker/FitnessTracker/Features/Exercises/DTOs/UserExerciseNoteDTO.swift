import Foundation

nonisolated struct UserExerciseNoteDTO: Codable, Sendable, Equatable {
    let id: String
    let userId: String
    let exerciseId: String
    let notes: String
    let createdAt: Date
    let updatedAt: Date
}

nonisolated struct ExerciseNotesResponseDTO: Codable, Sendable, Equatable {
    let notes: String?
}
