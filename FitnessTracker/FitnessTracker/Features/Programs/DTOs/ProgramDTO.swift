import Foundation

nonisolated struct ProgramDTO: Codable, Sendable {
    let id: String
    let name: String
    let description: String
    let createdAt: Date
}

extension ProgramDTO {
    func toModel() -> ProgramModel {
        ProgramModel(
            id: id,
            name: name,
            programDescription: description,
            createdAt: createdAt
        )
    }
}
