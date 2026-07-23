import Foundation

/// Wraps the standalone-workout catalog and session endpoints. Standalone
/// sessions are fully isolated from the active program — starting or
/// completing one never touches program position or program sessions.
@MainActor
final class StandaloneWorkoutRepository {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    // MARK: - Catalog

    /// GET /api/standalone-workouts — raw array, ordered by category then order.
    func fetchCatalog(category: String? = nil) async throws -> [StandaloneWorkoutSummaryDTO] {
        try await apiClient.send(.getStandaloneWorkouts(category: category))
    }

    /// GET /api/standalone-workouts/:id — the full nested template.
    func fetchWorkout(id: String) async throws -> StandaloneWorkoutDetailDTO {
        try await apiClient.send(.getStandaloneWorkout(id: id))
    }

    // MARK: - Sessions

    /// POST /api/standalone-workout-sessions. Throws `.httpError(409, ...)`
    /// when a session for this workout is already in progress — callers fetch
    /// the active session and offer resume instead of surfacing an error.
    @discardableResult
    func startSession(standaloneWorkoutId: String) async throws -> StandaloneWorkoutSessionDTO {
        let response: StandaloneSessionResponseDTO = try await apiClient.send(
            .createStandaloneSession(CreateStandaloneSessionBody(standaloneWorkoutId: standaloneWorkoutId))
        )
        return response.session
    }

    /// GET /api/standalone-workout-sessions/active — in-progress sessions, newest first.
    func fetchActiveSessions() async throws -> [StandaloneSessionListItemDTO] {
        let response: StandaloneSessionListResponseDTO = try await apiClient.send(.getActiveStandaloneSessions)
        return response.sessions
    }

    /// GET /api/standalone-workout-sessions/:id — session (with completed sets)
    /// plus the full workout template. Works for in-progress and completed sessions.
    func fetchSession(id: String) async throws -> StandaloneSessionDetailResponseDTO {
        try await apiClient.send(.getStandaloneSession(id: id))
    }

    /// GET /api/standalone-workout-sessions/history — completed sessions,
    /// `completedAt DESC, id DESC`, cursor pair passed together or not at all.
    func fetchHistory(limit: Int? = nil, before: Date? = nil, beforeId: String? = nil) async throws -> [StandaloneSessionListItemDTO] {
        let response: StandaloneSessionListResponseDTO = try await apiClient.send(
            .getStandaloneSessionHistory(limit: limit, before: before, beforeId: beforeId)
        )
        return response.sessions
    }

    // MARK: - Set logging

    /// Logs a prescribed template set. 409 means "already recorded" (or session
    /// completed) — the live VM treats already-recorded as idempotent success.
    @discardableResult
    func recordSet(
        sessionId: String,
        standaloneWorkoutSetId: String,
        reps: Int?, weight: Double?, rpe: Double?, notes: String?
    ) async throws -> StandaloneCompletedSetDTO {
        try await apiClient.send(.recordStandaloneSet(
            sessionId: sessionId,
            body: .prescribed(standaloneWorkoutSetId: standaloneWorkoutSetId, reps: reps, weight: weight, rpe: rpe, notes: notes)
        ))
    }

    /// Logs an ad-hoc (off-plan) set by exercise name. Can be logged any number of times.
    @discardableResult
    func recordAdhocSet(
        sessionId: String,
        exerciseName: String,
        reps: Int? = nil, weight: Double? = nil, rpe: Double? = nil, notes: String? = nil
    ) async throws -> StandaloneCompletedSetDTO {
        try await apiClient.send(.recordStandaloneSet(
            sessionId: sessionId,
            body: .adhoc(exerciseName: exerciseName, reps: reps, weight: weight, rpe: rpe, notes: notes)
        ))
    }

    /// PATCH a logged set (`setId` is the completed-set id, not the template id).
    /// Works while in-progress and after completion.
    @discardableResult
    func updateSet(sessionId: String, setId: String, body: UpdateSetBody) async throws -> StandaloneCompletedSetDTO {
        try await apiClient.send(.updateStandaloneSet(sessionId: sessionId, setId: setId, body: body))
    }

    /// DELETE a logged set. 404 = already gone — callers treat that as success.
    func deleteSet(sessionId: String, setId: String) async throws {
        try await apiClient.send(.deleteStandaloneSet(sessionId: sessionId, setId: setId))
    }

    // MARK: - Finalize / discard

    /// PATCH /complete. `completedAt: nil` sends an empty body → server "now".
    /// 409 = already completed — callers treat that as success.
    @discardableResult
    func completeSession(id: String, completedAt: Date? = nil) async throws -> StandaloneWorkoutSessionDTO {
        let body = completedAt.map { CompleteWorkoutBody(completedAt: $0) }
        let response: StandaloneSessionResponseDTO = try await apiClient.send(
            .completeStandaloneSession(id: id, body: body)
        )
        return response.session
    }

    /// DELETE the session and all its logged sets. 404 = already gone — success.
    func abandonSession(id: String) async throws {
        try await apiClient.send(.abandonStandaloneSession(id: id))
    }
}
