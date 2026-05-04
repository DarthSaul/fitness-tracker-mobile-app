import SwiftData

enum PersistenceContainer {
    // MARK: - Schema
    static var schema: Schema {
        Schema([
            ProgramModel.self,
        ])
    }

    // MARK: - Shared (on-disk)
    static func makeShared() throws -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - In-Memory (for tests)
    static func makeInMemory() throws -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
