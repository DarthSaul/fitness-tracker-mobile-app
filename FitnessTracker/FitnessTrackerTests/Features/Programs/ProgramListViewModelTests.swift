import Foundation
import Testing
import SwiftData
@testable import FitnessTracker

@Suite("ProgramListViewModel")
@MainActor
struct ProgramListViewModelTests {
    // MARK: - Fixtures
    private func makeProgramDTO(id: String, name: String) -> ProgramSummaryDTO {
        ProgramSummaryDTO(
            id: id,
            name: name,
            description: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            count: ProgramSummaryDTO.Count(weeks: 4)
        )
    }

    private func makeUserProgramDTO(
        id: String,
        programId: String,
        isActive: Bool,
        completedAt: Date? = nil,
        runNumber: Int? = nil,
        completedRunCount: Int? = nil
    ) -> UserProgramWithProgramDTO {
        UserProgramWithProgramDTO(
            id: id,
            userId: "u1",
            programId: programId,
            isActive: isActive,
            currentWeek: 1,
            currentDay: 1,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            program: UserProgramWithProgramDTO.NestedProgram(
                id: programId,
                name: "p",
                description: nil
            ),
            completedAt: completedAt,
            runNumber: runNumber,
            completedRunCount: completedRunCount
        )
    }

    private func makeViewModel(
        programs: [ProgramSummaryDTO] = [],
        userPrograms: [UserProgramWithProgramDTO] = []
    ) throws -> (ProgramListViewModel, MockAPIClient) {
        let client = MockAPIClient()
        client.stub(.getPrograms, response: programs)
        client.stub(.getUserPrograms, response: userPrograms)

        let container = try makeTestContainer()
        let context = ModelContext(container)
        let programRepo = ProgramRepository(apiClient: client, modelContext: context)
        let userProgramRepo = UserProgramRepository(apiClient: client)
        let session = SessionManager(keychain: KeychainService(), tokenStore: TokenStore())
        let vm = ProgramListViewModel(
            programRepository: programRepo,
            userProgramRepository: userProgramRepo,
            sessionManager: session
        )
        return (vm, client)
    }

    // The void mutation overload needs *some* Data; the content is discarded.
    private let voidStub: [String: Bool] = ["ok": true]

    // MARK: - Load + Filter

    @Test("load fetches programs and user-programs in parallel")
    func loadFetchesBoth() async throws {
        let (vm, _) = try makeViewModel(
            programs: [makeProgramDTO(id: "p1", name: "A"), makeProgramDTO(id: "p2", name: "B")],
            userPrograms: [makeUserProgramDTO(id: "up1", programId: "p1", isActive: true)]
        )

        await vm.load()

        #expect(vm.programs.count == 2)
        #expect(vm.userPrograms.count == 1)
        #expect(vm.isSaved(programId: "p1") == true)
        #expect(vm.isSaved(programId: "p2") == false)
        #expect(vm.isActive(programId: "p1") == true)
        #expect(vm.hasActiveProgram == true)
    }

    @Test("filter .saved returns only saved programs")
    func filterSaved() async throws {
        let (vm, _) = try makeViewModel(
            programs: [
                makeProgramDTO(id: "p1", name: "A"),
                makeProgramDTO(id: "p2", name: "B"),
                makeProgramDTO(id: "p3", name: "C"),
            ],
            userPrograms: [
                makeUserProgramDTO(id: "up1", programId: "p1", isActive: false),
                makeUserProgramDTO(id: "up2", programId: "p3", isActive: false),
            ]
        )

        await vm.load()
        vm.filter = .saved

        let ids = vm.filteredPrograms.map(\.id).sorted()
        #expect(ids == ["p1", "p3"])
    }

    @Test("filter .active returns only the active program")
    func filterActive() async throws {
        let (vm, _) = try makeViewModel(
            programs: [
                makeProgramDTO(id: "p1", name: "A"),
                makeProgramDTO(id: "p2", name: "B"),
            ],
            userPrograms: [
                makeUserProgramDTO(id: "up1", programId: "p1", isActive: false),
                makeUserProgramDTO(id: "up2", programId: "p2", isActive: true),
            ]
        )

        await vm.load()
        vm.filter = .active

        #expect(vm.filteredPrograms.map(\.id) == ["p2"])
    }

    @Test("filter .all returns every program regardless of saved state")
    func filterAll() async throws {
        let (vm, _) = try makeViewModel(
            programs: [makeProgramDTO(id: "p1", name: "A"), makeProgramDTO(id: "p2", name: "B")],
            userPrograms: []
        )
        await vm.load()
        vm.filter = .all
        #expect(vm.filteredPrograms.count == 2)
    }

    // MARK: - toggleSave

    @Test("toggleSave on unsaved program POSTs save then refreshes")
    func toggleSavePosts() async throws {
        let (vm, client) = try makeViewModel(
            programs: [makeProgramDTO(id: "p1", name: "A")],
            userPrograms: []
        )
        await vm.load()
        #expect(vm.isSaved(programId: "p1") == false)

        client.stub(.saveProgram(programId: "p1"), response: voidStub)
        // After save, the refresh re-fetches user-programs — re-stub with the saved record.
        client.stub(.getUserPrograms, response: [makeUserProgramDTO(id: "up1", programId: "p1", isActive: false)])

        await vm.toggleSave(programId: "p1")

        #expect(vm.isSaved(programId: "p1") == true)
        #expect(vm.actionError == nil)
    }

    @Test("toggleSave on already-saved program DELETEs then refreshes")
    func toggleSaveDeletes() async throws {
        let (vm, client) = try makeViewModel(
            programs: [makeProgramDTO(id: "p1", name: "A")],
            userPrograms: [makeUserProgramDTO(id: "up1", programId: "p1", isActive: false)]
        )
        await vm.load()
        #expect(vm.isSaved(programId: "p1") == true)

        client.stub(.unsaveProgram(userProgramId: "up1"), response: voidStub)
        client.stub(.getUserPrograms, response: [] as [UserProgramWithProgramDTO])

        await vm.toggleSave(programId: "p1")

        #expect(vm.isSaved(programId: "p1") == false)
    }

    // MARK: - toggleActive

    @Test("toggleActive activates a saved program when none is active")
    func toggleActiveActivates() async throws {
        let (vm, client) = try makeViewModel(
            programs: [makeProgramDTO(id: "p1", name: "A")],
            userPrograms: [makeUserProgramDTO(id: "up1", programId: "p1", isActive: false)]
        )
        await vm.load()

        client.stub(.activateProgram(userProgramId: "up1"), response: voidStub)
        client.stub(.getUserPrograms, response: [makeUserProgramDTO(id: "up1", programId: "p1", isActive: true)])

        await vm.toggleActive(programId: "p1")

        #expect(vm.isActive(programId: "p1") == true)
    }

    @Test("toggleActive deactivates an already-active program")
    func toggleActiveDeactivates() async throws {
        let (vm, client) = try makeViewModel(
            programs: [makeProgramDTO(id: "p1", name: "A")],
            userPrograms: [makeUserProgramDTO(id: "up1", programId: "p1", isActive: true)]
        )
        await vm.load()

        client.stub(.deactivateProgram(userProgramId: "up1"), response: voidStub)
        client.stub(.getUserPrograms, response: [makeUserProgramDTO(id: "up1", programId: "p1", isActive: false)])

        await vm.toggleActive(programId: "p1")

        #expect(vm.isActive(programId: "p1") == false)
    }

    @Test("toggleActive on second program while one is active surfaces error and skips request")
    func toggleActiveBlockedByExistingActive() async throws {
        let (vm, _) = try makeViewModel(
            programs: [
                makeProgramDTO(id: "p1", name: "A"),
                makeProgramDTO(id: "p2", name: "B"),
            ],
            userPrograms: [
                makeUserProgramDTO(id: "up1", programId: "p1", isActive: true),
                makeUserProgramDTO(id: "up2", programId: "p2", isActive: false),
            ]
        )
        await vm.load()

        // Intentionally NOT stubbing activateProgram(up2) — if the VM dispatches
        // anyway, MockAPIClient throws .missingHandler and the test fails.
        await vm.toggleActive(programId: "p2")

        #expect(vm.actionError != nil)
        #expect(vm.isActive(programId: "p2") == false)
        #expect(vm.isActive(programId: "p1") == true)
    }

    // MARK: - Program runs

    @Test("a completed run never counts as active, even if the row is still isActive")
    func completedRunIsNotActive() async throws {
        let done = Date(timeIntervalSince1970: 1_700_500_000)
        let (vm, _) = try makeViewModel(
            programs: [makeProgramDTO(id: "p1", name: "A")],
            userPrograms: [makeUserProgramDTO(
                id: "up1", programId: "p1", isActive: true,
                completedAt: done, runNumber: 1, completedRunCount: 1
            )]
        )
        await vm.load()

        #expect(vm.isCompleted(programId: "p1") == true)
        #expect(vm.completedRunCount(programId: "p1") == 1)
        #expect(vm.isActive(programId: "p1") == false)
        #expect(vm.hasActiveProgram == false)
        vm.filter = .active
        #expect(vm.filteredPrograms.isEmpty)
    }

    @Test("toggleActive on a completed run activates it and adopts the fresh run's id")
    func toggleActiveRestartsCompletedRun() async throws {
        let done = Date(timeIntervalSince1970: 1_700_500_000)
        let (vm, client) = try makeViewModel(
            programs: [makeProgramDTO(id: "p1", name: "A")],
            userPrograms: [makeUserProgramDTO(
                id: "up1", programId: "p1", isActive: false,
                completedAt: done, runNumber: 1, completedRunCount: 1
            )]
        )
        await vm.load()

        client.stub(.activateProgram(userProgramId: "up1"), response: voidStub)
        // The server opens a new run — the refreshed list carries a different id.
        client.stub(.getUserPrograms, response: [makeUserProgramDTO(
            id: "up2", programId: "p1", isActive: true,
            runNumber: 2, completedRunCount: 1
        )])

        await vm.toggleActive(programId: "p1")

        #expect(vm.actionError == nil)
        #expect(vm.savedMap["p1"]?.id == "up2")
        #expect(vm.isActive(programId: "p1") == true)
        #expect(vm.isCompleted(programId: "p1") == false)
        #expect(vm.completedRunCount(programId: "p1") == 1)
    }

    @Test("a completed program does not block activating another one")
    func completedRunDoesNotBlockActivation() async throws {
        let done = Date(timeIntervalSince1970: 1_700_500_000)
        let (vm, client) = try makeViewModel(
            programs: [
                makeProgramDTO(id: "p1", name: "A"),
                makeProgramDTO(id: "p2", name: "B"),
            ],
            userPrograms: [
                makeUserProgramDTO(id: "up1", programId: "p1", isActive: true, completedAt: done),
                makeUserProgramDTO(id: "up2", programId: "p2", isActive: false),
            ]
        )
        await vm.load()

        client.stub(.activateProgram(userProgramId: "up2"), response: voidStub)
        client.stub(.getUserPrograms, response: [
            makeUserProgramDTO(id: "up1", programId: "p1", isActive: false, completedAt: done),
            makeUserProgramDTO(id: "up2", programId: "p2", isActive: true),
        ])

        await vm.toggleActive(programId: "p2")

        #expect(vm.actionError == nil)
        #expect(vm.isActive(programId: "p2") == true)
    }
}
