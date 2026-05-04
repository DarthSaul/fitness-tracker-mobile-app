import Foundation

nonisolated struct ExerciseDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let description: String?
}
