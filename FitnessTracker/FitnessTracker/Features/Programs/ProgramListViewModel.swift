import Foundation
import Observation
import OSLog

enum ProgramFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case saved
    case active

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .saved: return "Saved"
        case .active: return "Active"
        }
    }
}

@Observable
@MainActor
final class ProgramListViewModel {
    // MARK: - State
    var programs: [ProgramModel] = []
    var userPrograms: [UserProgramWithProgramDTO] = []
    var filter: ProgramFilter = .all
    var isLoading = false
    var error: Error?
    /// Surfaced when an action (save / activate) fails or is rejected client-side
    /// (e.g. trying to activate a second program while one is already active).
    var actionError: String?

    private(set) var savingProgramIds: Set<String> = []
    private(set) var activatingUserProgramIds: Set<String> = []

    // MARK: - Dependencies
    private let programRepository: ProgramRepository
    private let userProgramRepository: UserProgramRepository
    private let sessionManager: SessionManager

    init(
        programRepository: ProgramRepository,
        userProgramRepository: UserProgramRepository,
        sessionManager: SessionManager
    ) {
        self.programRepository = programRepository
        self.userProgramRepository = userProgramRepository
        self.sessionManager = sessionManager
    }

    // MARK: - Derived State
    var filteredPrograms: [ProgramModel] {
        switch filter {
        case .all:
            return programs
        case .saved:
            return programs.filter { savedMap[$0.id] != nil }
        case .active:
            return programs.filter { savedMap[$0.id]?.isActive == true }
        }
    }

    var savedMap: [String: UserProgramWithProgramDTO] {
        Dictionary(userPrograms.map { ($0.programId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var hasActiveProgram: Bool {
        userPrograms.contains { $0.isActive }
    }

    func isSaved(programId: String) -> Bool {
        savedMap[programId] != nil
    }

    func isActive(programId: String) -> Bool {
        savedMap[programId]?.isActive == true
    }

    func isSaving(programId: String) -> Bool {
        savingProgramIds.contains(programId)
    }

    func isActivating(programId: String) -> Bool {
        guard let userProgramId = savedMap[programId]?.id else { return false }
        return activatingUserProgramIds.contains(userProgramId)
    }

    // MARK: - Load
    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            async let programsTask = programRepository.fetchPrograms()
            async let userProgramsTask = userProgramRepository.fetchUserPrograms()
            let (fetchedPrograms, fetchedUserPrograms) = try await (programsTask, userProgramsTask)
            programs = fetchedPrograms
            userPrograms = fetchedUserPrograms
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch {
            Logger.data.error("Failed to load programs: \(error)")
            programs = (try? programRepository.cachedPrograms()) ?? programs
            self.error = error
        }
    }

    // MARK: - Save / Unsave
    func toggleSave(programId: String) async {
        guard !isSaving(programId: programId) else { return }
        savingProgramIds.insert(programId)
        defer { savingProgramIds.remove(programId) }

        do {
            if let existing = savedMap[programId] {
                try await userProgramRepository.unsaveProgram(userProgramId: existing.id)
            } else {
                try await userProgramRepository.saveProgram(programId: programId)
            }
            await refreshUserPrograms()
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch {
            Logger.data.error("toggleSave failed for \(programId): \(error)")
            actionError = error.localizedDescription
        }
    }

    // MARK: - Activate / Deactivate
    func toggleActive(programId: String) async {
        guard let existing = savedMap[programId] else { return }
        guard !activatingUserProgramIds.contains(existing.id) else { return }

        // Server enforces single-active too, but we surface the message client-side
        // so the user gets immediate feedback rather than a 409 round-trip.
        if !existing.isActive && hasActiveProgram {
            actionError = "You already have an active program. Deactivate it before starting a new one."
            return
        }

        activatingUserProgramIds.insert(existing.id)
        defer { activatingUserProgramIds.remove(existing.id) }

        do {
            if existing.isActive {
                try await userProgramRepository.deactivateProgram(userProgramId: existing.id)
            } else {
                try await userProgramRepository.activateProgram(userProgramId: existing.id)
            }
            await refreshUserPrograms()
        } catch let apiError as APIError where apiError == .unauthorized {
            await sessionManager.signOut()
        } catch {
            Logger.data.error("toggleActive failed for \(programId): \(error)")
            actionError = error.localizedDescription
        }
    }

    private func refreshUserPrograms() async {
        do {
            userPrograms = try await userProgramRepository.fetchUserPrograms()
        } catch {
            Logger.data.error("Failed to refresh user programs after mutation: \(error)")
        }
    }
}
