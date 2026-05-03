import Foundation
import SwiftData
import OSLog

@MainActor
final class ProgramRepository {
    private let apiClient: any APIClientProtocol
    private let modelContext: ModelContext

    init(apiClient: any APIClientProtocol, modelContext: ModelContext) {
        self.apiClient = apiClient
        self.modelContext = modelContext
    }

    // MARK: - Fetch and Sync
    @discardableResult
    func fetchPrograms() async throws -> [ProgramModel] {
        let dtos: [ProgramSummaryDTO] = try await apiClient.send(.getPrograms)
        Logger.data.info("Fetched \(dtos.count) programs from API — upserting into SwiftData.")
        return try upsert(dtos)
    }

    // MARK: - Local Query
    func cachedPrograms() throws -> [ProgramModel] {
        let descriptor = FetchDescriptor<ProgramModel>(sortBy: [SortDescriptor(\.name)])
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Upsert
    @discardableResult
    private func upsert(_ dtos: [ProgramSummaryDTO]) throws -> [ProgramModel] {
        var descriptor = FetchDescriptor<ProgramModel>()
        descriptor.predicate = #Predicate { _ in true }
        let existing = try modelContext.fetch(descriptor)
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        for dto in dtos {
            if let model = existingById[dto.id] {
                model.name = dto.name
                model.programDescription = dto.description
                model.createdAt = dto.createdAt
            } else {
                modelContext.insert(dto.toModel())
            }
        }
        try modelContext.save()

        return try modelContext.fetch(FetchDescriptor<ProgramModel>(sortBy: [SortDescriptor(\.name)]))
    }
}
