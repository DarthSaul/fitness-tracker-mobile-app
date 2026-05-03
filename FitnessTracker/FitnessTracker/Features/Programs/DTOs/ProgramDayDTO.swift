import Foundation

nonisolated struct ProgramDayDTO: Codable, Sendable, Equatable {
    let id: String
    let programWeekId: String
    let dayNumber: Int
    let name: String?
    let warmUp: String?
    let exerciseGroups: [ExerciseGroupDTO]
}

nonisolated struct ExerciseGroupDTO: Codable, Sendable, Equatable {
    let id: String
    let programDayId: String
    let order: Int
    let type: ExerciseGroupType
    let restSeconds: Int?
    let exercises: [ProgramExerciseDTO]
}

nonisolated struct ProgramExerciseDTO: Codable, Sendable, Equatable {
    let id: String
    let exerciseGroupId: String
    let exerciseId: String
    let order: Int
    let exercise: ExerciseDTO
    let sets: [ExerciseSetDTO]
}

nonisolated struct ExerciseSetDTO: Codable, Sendable, Equatable {
    let id: String
    let programExerciseId: String
    let setNumber: Int
    let reps: Int?
    let weight: Double?
    let rpe: Double?
    let notes: String?
    let effortTarget: String?
}
