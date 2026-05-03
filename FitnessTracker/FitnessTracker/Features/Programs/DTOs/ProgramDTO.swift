import Foundation

nonisolated struct ProgramSummaryDTO: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let description: String?
    let createdAt: Date
    let count: Count

    nonisolated struct Count: Codable, Sendable, Equatable {
        let weeks: Int
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, createdAt
        case count = "_count"
    }
}

extension ProgramSummaryDTO {
    func toModel() -> ProgramModel {
        ProgramModel(
            id: id,
            name: name,
            programDescription: description,
            createdAt: createdAt
        )
    }
}
