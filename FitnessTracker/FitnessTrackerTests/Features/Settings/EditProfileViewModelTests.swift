import Foundation
import Testing
@testable import FitnessTracker

@Suite("Usernames and Edit Profile")
@MainActor
struct EditProfileViewModelTests {
    @Test("usernames normalize like the server: trim, drop @, lowercase")
    func normalize() {
        #expect(UsernameRules.normalize("  @SaulG ") == "saulg")
        #expect(UsernameRules.normalize("dev.pulls") == "dev.pulls")
    }

    @Test("format: 3–30 of a–z 0–9 _ . with no edge or doubled periods")
    func format() {
        #expect(UsernameRules.isValidFormat("saul_g.2"))
        #expect(!UsernameRules.isValidFormat("ab"))
        #expect(!UsernameRules.isValidFormat(String(repeating: "a", count: 31)))
        #expect(!UsernameRules.isValidFormat(".saul"))
        #expect(!UsernameRules.isValidFormat("saul."))
        #expect(!UsernameRules.isValidFormat("sa..ul"))
        #expect(!UsernameRules.isValidFormat("saul-g"))
        #expect(!UsernameRules.isValidFormat("SAUL"), "checked after normalizing, so uppercase never reaches here")
    }

    /// Signed in with a cached profile, as Edit Profile always is.
    private func makeViewModel(username: String = "saulg", bio: String? = nil) async -> (EditProfileViewModel, SocialTestHarness) {
        let harness = SocialTestHarness()
        harness.client.stub(.getMe, response: UserProfile(
            id: "user-me", email: "s@example.com", name: "Saul", avatarUrl: nil,
            profileVisibility: .private, username: username, bio: bio
        ))
        await harness.sessionManager.loadProfile()
        return (EditProfileViewModel(context: harness.context, debounce: .zero), harness)
    }

    @Test("an invalid format is flagged without calling the API")
    func invalidLocally() async {
        let (viewModel, harness) = await makeViewModel()
        viewModel.username = "a"
        viewModel.usernameEdited()
        #expect(viewModel.usernameStatus == .unavailable(.invalid))
        #expect(harness.client.callCount(for: .checkUsernameAvailability(username: "")) == 0)
    }

    @Test("my current username reads as unchanged")
    func unchanged() async {
        let (viewModel, _) = await makeViewModel()
        viewModel.username = "@SaulG"
        viewModel.usernameEdited()
        #expect(viewModel.usernameStatus == .unchanged)
        #expect(!viewModel.canSave)
    }

    @Test("availability comes from the server; taken blocks saving")
    func availability() async {
        let (viewModel, harness) = await makeViewModel()
        harness.client.stubJSON(.checkUsernameAvailability(username: ""), #"{"available":false,"reason":"taken"}"#)

        viewModel.username = "@Maya"
        await viewModel.check(viewModel.normalizedUsername)
        #expect(viewModel.usernameStatus == .unavailable(.taken))
        #expect(viewModel.usernameMessage == "That username is taken.")
        #expect(!viewModel.canSave)
    }

    @Test("bio counts code points and blocks saving over 100")
    func bioLimit() async {
        let (viewModel, _) = await makeViewModel()
        viewModel.bio = String(repeating: "👍🏽", count: 50)
        #expect(viewModel.bioLength == 100)
        #expect(viewModel.canSave)
        viewModel.bio += "x"
        #expect(viewModel.isBioTooLong)
        #expect(!viewModel.canSave)
    }

    @Test("saving sends only what changed, and clears a bio with an empty string")
    func saveSendsChanges() async {
        let (viewModel, harness) = await makeViewModel(bio: "Old bio")
        harness.client.stub(.updateMe(UpdateMeBody()), response: UserProfile(
            id: "user-me", email: "s@example.com", name: "Saul", avatarUrl: nil, username: "saulg", bio: nil
        ))
        viewModel.bio = "   "

        let saved = await viewModel.save()

        #expect(saved)
        let bodies: [UpdateMeBody] = harness.sent { if case .updateMe(let body) = $0 { body } else { nil } }
        #expect(bodies == [UpdateMeBody(bio: "")])
        #expect(harness.sessionManager.userProfile?.bio == nil)
    }
}

@Suite("Relative time")
struct RelativeTimeTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test("compact relative times")
    func compact() throws {
        let now = try #require(JSONCoding.parseISO8601("2026-10-02T18:00:00Z"))
        func ago(_ seconds: TimeInterval) -> String {
            RelativeTime.short(now.addingTimeInterval(-seconds), now: now, calendar: calendar)
        }
        #expect(ago(20) == "now")
        #expect(ago(5 * 60) == "5m")
        #expect(ago(2 * 3600) == "2h")
        #expect(ago(30 * 3600) == "Yesterday")
        #expect(ago(3 * 86_400) == "3d")
    }
}
