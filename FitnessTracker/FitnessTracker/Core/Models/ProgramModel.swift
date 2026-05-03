import Foundation
import SwiftData

@Model
final class ProgramModel {
    // MARK: - Stored Properties
    @Attribute(.unique) var id: String
    var name: String
    var programDescription: String
    var createdAt: Date

    // MARK: - Init
    init(id: String, name: String, programDescription: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.programDescription = programDescription
        self.createdAt = createdAt
    }
}
