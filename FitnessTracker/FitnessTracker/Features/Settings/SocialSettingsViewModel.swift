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
    private(set) var savingFields: Set<String> = []
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
        let saved = await update("profileVisibility", UpdateMeBody(profileVisibility: isPrivate ? .private : .public)) {
            $0.profileVisibility = isPrivate ? .private : .public
        }
        // Only a successful switch to public approved the pending requests.
        if saved, !isPrivate {
            pendingRequestCount = 0
            context.events.send(.followsChanged)
        }
    }

    func setShowActiveProgram(_ value: Bool) async {
        await update("showActiveProgram", UpdateMeBody(showActiveProgram: value)) { $0.showActiveProgram = value }
    }

    func setShowWorkoutCount(_ value: Bool) async {
        await update("showWorkoutCount", UpdateMeBody(showWorkoutCount: value)) { $0.showWorkoutCount = value }
    }

    /// Applies `change` to the cached profile at once, PATCHes, then adopts
    /// the server's copy — or restores the old one and shows a toast.
    /// Returns whether the change was saved.
    @discardableResult
    private func update(_ field: String, _ body: UpdateMeBody, change: (inout UserProfile) -> Void) async -> Bool {
        guard let original = profile else { return false }
        var optimistic = original
        change(&optimistic)
        sessionManager.applyProfile(optimistic)
        savingFields.insert(field)
        defer { savingFields.remove(field) }
        do {
            let saved = try await context.repository.updateMe(body)
            sessionManager.applyProfile(saved)
            return true
        } catch {
            sessionManager.applyProfile(original)
            guard let failure = await context.failure(from: error) else { return false }
            Logger.data.error("Settings update failed: \(error)")
            context.toasts.show("Couldn't save that setting. \(failure.message)")
            return false
        }
    }
}
