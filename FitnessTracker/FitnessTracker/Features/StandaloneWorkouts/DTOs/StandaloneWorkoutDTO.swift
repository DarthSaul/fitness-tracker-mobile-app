import Foundation

/// GET /api/standalone-workouts returns a **raw array** of these (not wrapped),
/// ordered by category then order. `_count.groups` backs the "N groups" label
/// on the browse list.
nonisolated struct StandaloneWorkoutSummaryDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let category: String
    let order: Int
    let name: String?
    let description: String?
    let createdAt: Date
    let count: Count

    nonisolated struct Count: Codable, Sendable, Equatable {
        let groups: Int
    }

    enum CodingKeys: String, CodingKey {
        case id, category, order, name, description, createdAt
        case count = "_count"
    }
}

/// GET /api/standalone-workouts/:id returns the workout object directly (not
/// wrapped), with the full template nesting. Also embedded as `workout` in the
/// session detail response — note that there the nested `exercise` only carries
/// `{ id, name, description }` (no media fields), which `ExerciseDTO` matches.
nonisolated struct StandaloneWorkoutDetailDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let category: String
    let order: Int
    let name: String?
    let description: String?
    let createdAt: Date
    let groups: [StandaloneWorkoutGroupDTO]
}

nonisolated struct StandaloneWorkoutGroupDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let standaloneWorkoutId: String
    let order: Int
    let type: ExerciseGroupType
    let label: String?
    let restSeconds: Int?
    let exercises: [StandaloneWorkoutExerciseDTO]
}

nonisolated struct StandaloneWorkoutExerciseDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let groupId: String
    let exerciseId: String
    let order: Int
    let exercise: ExerciseDTO
    let sets: [StandaloneWorkoutSetDTO]
}

nonisolated struct StandaloneWorkoutSetDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let standaloneWorkoutExerciseId: String
    let setNumber: Int
    let reps: Int?
    let weight: Double?
    let rpe: Double?
    let notes: String?
    let effortTarget: String?
}

// MARK: - Display name fallback

/// `name` is nullable on the catalog — fall back to "{category} #{order}".
/// Shared by every surface that titles a standalone workout (browse rows,
/// detail header, live session toolbar, history rows, resume banner).
/// Nonisolated so the nonisolated DTO extensions below can call it.
nonisolated func standaloneWorkoutDisplayName(name: String?, category: String, order: Int) -> String {
    if let name, !name.isEmpty { return name }
    return "\(category) #\(order)"
}

extension StandaloneWorkoutSummaryDTO {
    var displayName: String { standaloneWorkoutDisplayName(name: name, category: category, order: order) }
}

extension StandaloneWorkoutDetailDTO {
    var displayName: String { standaloneWorkoutDisplayName(name: name, category: category, order: order) }
}
