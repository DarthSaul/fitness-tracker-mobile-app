import Foundation
import Observation
import OSLog

/// The Settings → Social group and Edit Profile: privacy, profile stats,
/// username and bio, all through `PATCH /api/auth/me`. Toggles update
/// optimistically and roll back on failure.
@Observable
@MainActor
final class SocialSettingsViewModel {
    private(set) var followerCount: Int?
    private(set) var blockedCount: Int?
    /// Profile fields with a save in flight.
    private var savingFields: Set<PartialKeyPath<UserProfile>> = []
    /// Pending follow requests, for the "going public" warning.
    private(set) var pendingRequestCount = 0

    private let context: SocialContext

    init(context: SocialContext) {
        self.context = context
    }

    private var sessionManager: SessionManager { context.sessionManager }
    var profile: UserProfile? { sessionManager.userProfile }

    // MARK: - Loading

    /// Follower count (for "@handle · 48 followers"), blocked count and
    /// pending requests. Best-effort: missing values hide their text.
    func loadCounts() async {
        guard let userId = context.currentUserId else { return }
        async let profile = try? context.repository.fetchProfile(userId: userId)
        async let blocked = try? context.repository.fetchBlocked()
        async let requests = try? context.repository.fetchFollowRequests(direction: .incoming)
        let (loadedProfile, loadedBlocked, loadedRequests) = await (profile, blocked, requests)
        followerCount = loadedProfile?.followerCount
        blockedCount = loadedBlocked?.count
        pendingRequestCount = loadedRequests?.count ?? 0
    }

    func setBlockedCount(_ count: Int) {
        blockedCount = count
    }

    // MARK: - Toggles

    /// Every profile starts `PRIVATE`.
    var isPrivate: Bool { (profile?.profileVisibility ?? .private) == .private }
    var showActiveProgram: Bool { profile?.showActiveProgram ?? true }
    var showWorkoutCount: Bool { profile?.showWorkoutCount ?? true }

    /// Going public approves every pending request (the view warns first);
    /// going private keeps existing followers.
    func setPrivate(_ isPrivate: Bool) async {
        let visibility: ProfileVisibility = isPrivate ? .private : .public
        let saved = await update(\.profileVisibility, to: visibility, body: UpdateMeBody(profileVisibility: visibility))
        // Only a successful switch to public approved the pending requests.
        if saved, !isPrivate {
            pendingRequestCount = 0
            context.events.send(.followsChanged)
        }
    }

    func setShowActiveProgram(_ value: Bool) async {
        await update(\.showActiveProgram, to: value, body: UpdateMeBody(showActiveProgram: value))
    }

    func setShowWorkoutCount(_ value: Bool) async {
        await update(\.showWorkoutCount, to: value, body: UpdateMeBody(showWorkoutCount: value))
    }

    func isSaving(_ field: PartialKeyPath<UserProfile>) -> Bool {
        savingFields.contains(field)
    }

    /// Sets one field optimistically, then PATCHes it. Each save touches
    /// only its own field — success takes that field from the server's
    /// response, failure restores just that field — so overlapping saves of
    /// different settings can't undo each other. A field already being saved
    /// is left alone (its toggle is disabled meanwhile). Returns whether the
    /// change was saved.
    @discardableResult
    private func update<Value>(
        _ field: WritableKeyPath<UserProfile, Value?>,
        to value: Value,
        body: UpdateMeBody
    ) async -> Bool {
        guard let current = profile, !savingFields.contains(field) else { return false }
        let previous = current[keyPath: field]
        setField(field, to: value)
        savingFields.insert(field)
        defer { savingFields.remove(field) }
        do {
            let saved = try await context.repository.updateMe(body)
            setField(field, to: saved[keyPath: field])
            return true
        } catch {
            setField(field, to: previous)
            guard let failure = await context.failure(from: error) else { return false }
            Logger.data.error("Settings update failed: \(error)")
            context.toasts.show("Couldn't save that setting. \(failure.message)")
            return false
        }
    }

    /// Writes one field into the *current* cached profile, leaving any other
    /// field another save changed meanwhile untouched.
    private func setField<Value>(_ field: WritableKeyPath<UserProfile, Value?>, to value: Value?) {
        guard var updated = profile else { return }
        updated[keyPath: field] = value
        sessionManager.applyProfile(updated)
    }
}
