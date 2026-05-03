import SwiftData
@testable import FitnessTracker

func makeTestContainer() throws -> ModelContainer {
    try PersistenceContainer.makeInMemory()
}
