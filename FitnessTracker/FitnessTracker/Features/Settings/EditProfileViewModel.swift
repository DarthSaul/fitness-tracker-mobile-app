import Foundation
import Observation
import OSLog

/// Username rules mirrored from the server (SPEC-usernames): 3–30 of
/// `a–z 0–9 _ .`, no leading, trailing or doubled period. Saved trimmed,
/// without a leading `@`, lowercased. Reserved names are the server's call.
nonisolated enum UsernameRules {
    static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed).lowercased()
    }

    /// Whether a normalized name has a valid format.
    static func isValidFormat(_ name: String) -> Bool {
        guard (3...30).contains(name.count) else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_.")
        guard name.allSatisfy({ allowed.contains($0) }) else { return false }
        return !name.hasPrefix(".") && !name.hasSuffix(".") && !name.contains("..")
    }
}

/// Edit Profile: username (checked live) and bio. Name and photo aren't
/// editable through the API yet.
@Observable
@MainActor
final class EditProfileViewModel {
    enum UsernameStatus: Equatable {
        case unchanged
        case checking
        case available
        case unavailable(UsernameUnavailableReason)
        /// The check itself failed (offline, rate limited); saving decides.
        case unknown
    }

    var username: String
    var bio: String
    private(set) var usernameStatus: UsernameStatus = .unchanged
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var didSave = false

    private let originalUsername: String
    private let originalBio: String
    private let context: SocialContext
    private let debounce: Duration
    private var checkTask: Task<Void, Never>?

    init(context: SocialContext, debounce: Duration = .milliseconds(400)) {
        self.context = context
        self.debounce = debounce
        let profile = context.sessionManager.userProfile
        originalUsername = profile?.username ?? ""
        // Trimmed like `trimmedBio`, so an untouched bio never reads as changed.
        originalBio = (profile?.bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        username = originalUsername
        bio = originalBio
    }

    // MARK: - Username

    var normalizedUsername: String { UsernameRules.normalize(username) }
    var usernameChanged: Bool { normalizedUsername != originalUsername }

    /// Call on every keystroke. Format problems show at once; availability
    /// is checked after a pause (limited to 60 checks a minute).
    func usernameEdited() {
        checkTask?.cancel()
        errorMessage = nil
        guard usernameChanged else {
            usernameStatus = .unchanged
            return
        }
        let name = normalizedUsername
        guard UsernameRules.isValidFormat(name) else {
            usernameStatus = .unavailable(.invalid)
            return
        }
        usernameStatus = .checking
        checkTask = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await check(name)
        }
    }

    func check(_ name: String) async {
        do {
            let result = try await context.repository.checkUsername(name)
            guard !Task.isCancelled, name == normalizedUsername else { return }
            usernameStatus = result.available ? .available : .unavailable(result.reason ?? .invalid)
        } catch {
            guard !Task.isCancelled else { return }
            _ = await context.failure(from: error)
            usernameStatus = .unknown
        }
    }

    var usernameMessage: String? {
        switch usernameStatus {
        case .unchanged, .checking, .unknown: return nil
        case .available: return "@\(normalizedUsername) is available."
        case .unavailable(.invalid): return "Use 3–30 letters, numbers, underscores or periods (no period at the start or end, or two in a row)."
        case .unavailable(.reserved): return "That username is reserved."
        case .unavailable(.taken): return "That username is taken."
        }
    }

    // MARK: - Bio

    /// Code points, as the server counts (👍🏽 is 2).
    var bioLength: Int { SocialRules.bioLength(bio) }
    var isBioTooLong: Bool { bioLength > SocialRules.bioMax }
    private var trimmedBio: String { bio.trimmingCharacters(in: .whitespacesAndNewlines) }
    var bioChanged: Bool { trimmedBio != originalBio }

    // MARK: - Save

    var canSave: Bool {
        guard !isSaving, usernameChanged || bioChanged, !isBioTooLong else { return false }
        switch usernameStatus {
        case .unavailable, .checking: return false
        case .unchanged, .available, .unknown: return true
        }
    }

    func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        var body = UpdateMeBody()
        if usernameChanged { body.username = normalizedUsername }
        // "" clears the bio (the server treats it like null).
        if bioChanged { body.bio = trimmedBio }
        do {
            let saved = try await context.repository.updateMe(body)
            context.sessionManager.applyProfile(saved)
            didSave = true
            return true
        } catch {
            guard let failure = await context.failure(from: error) else { return false }
            Logger.data.error("Edit profile failed: \(error)")
            if case .conflict = failure {
                usernameStatus = .unavailable(.taken)
            }
            errorMessage = failure.message
            return false
        }
    }
}
