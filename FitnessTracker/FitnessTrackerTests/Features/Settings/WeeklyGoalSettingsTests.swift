import Foundation
import Testing
@testable import FitnessTracker

@Suite("Weekly goal settings")
@MainActor
struct WeeklyGoalSettingsTests {
    private func harness(_ profile: UserProfile) async -> SocialTestHarness {
        let harness = SocialTestHarness()
        harness.client.stub(.getMe, response: profile)
        await harness.sessionManager.loadProfile()
        return harness
    }

    private func profile(enabled: Bool? = nil, goal: Int? = nil, weekStart: WeekStartDay? = nil) -> UserProfile {
        UserProfile(
            id: "user-me", email: "s@example.com", name: nil, avatarUrl: nil,
            weeklyWorkoutGoalEnabled: enabled, weeklyWorkoutGoal: goal, weekStartDay: weekStart
        )
    }

    private func sentBodies(_ harness: SocialTestHarness) -> [UpdateMeBody] {
        harness.sent { if case .updateMe(let body) = $0 { body } else { nil } }
    }

    @Test("a profile without the fields reads as off, 3, Sunday (the server defaults)")
    func defaults() async {
        let viewModel = SocialSettingsViewModel(context: await harness(profile()).context)
        #expect(!viewModel.weeklyGoalEnabled)
        #expect(viewModel.weeklyGoal == 3)
        #expect(viewModel.weekStartDay == .sunday)
    }

    @Test("turning the goal on sends only the toggle and keeps the saved number")
    func enable() async {
        let harness = await harness(profile(enabled: false, goal: 4))
        harness.client.stub(.updateMe(UpdateMeBody()), response: profile(enabled: true, goal: 4))
        let viewModel = SocialSettingsViewModel(context: harness.context)

        await viewModel.setWeeklyGoalEnabled(true)

        #expect(sentBodies(harness) == [UpdateMeBody(weeklyWorkoutGoalEnabled: true)])
        #expect(viewModel.weeklyGoalEnabled)
        #expect(viewModel.weeklyGoal == 4)
    }

    @Test("changing the number and the week start each send one field")
    func numberAndWeekStart() async {
        let harness = await harness(profile(enabled: true, goal: 3))
        harness.client.stub(.updateMe(UpdateMeBody()), response: profile(enabled: true, goal: 5, weekStart: .monday))
        let viewModel = SocialSettingsViewModel(context: harness.context)

        await viewModel.setWeeklyGoal(5)
        await viewModel.setWeekStartDay(.monday)

        #expect(sentBodies(harness) == [
            UpdateMeBody(weeklyWorkoutGoal: 5),
            UpdateMeBody(weekStartDay: .monday)
        ])
        #expect(harness.sessionManager.userProfile?.weeklyWorkoutGoal == 5)
        #expect(harness.sessionManager.userProfile?.weekStartDay == .monday)
    }

    @Test("a failed change rolls back and shows a toast")
    func rollback() async {
        let harness = await harness(profile(enabled: true, goal: 3))
        harness.client.stubHTTPError(.updateMe(UpdateMeBody()), status: 500)
        let viewModel = SocialSettingsViewModel(context: harness.context)

        await viewModel.setWeeklyGoal(6)

        #expect(viewModel.weeklyGoal == 3)
        #expect(harness.context.toasts.current != nil)
    }
}

@Suite("WeekStartDay")
struct WeekStartDayTests {
    @Test("decodes the server's names, and falls back to Sunday")
    func decoding() throws {
        let days = try JSONDecoder().decode([WeekStartDay].self, from: Data(#"["MONDAY","SATURDAY","FUNDAY"]"#.utf8))
        #expect(days == [.monday, .saturday, .sunday])
    }

    @Test("maps to Calendar.firstWeekday (1 is Sunday)")
    func calendarWeekday() {
        #expect(WeekStartDay.sunday.calendarWeekday == 1)
        #expect(WeekStartDay.monday.calendarWeekday == 2)
        #expect(WeekStartDay.saturday.calendarWeekday == 7)
        #expect(WeekStartDay.wednesday.calendar().firstWeekday == 4)
    }

    @Test("the weekly chart's weeks start on the chosen day")
    func chartWeeks() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let iso = ISO8601DateFormatter()
        // Tuesday, Oct 6 2026.
        let now = try #require(iso.date(from: "2026-10-06T12:00:00Z"))
        // Sunday Oct 4 is this week when weeks start Sunday, last week when
        // they start Monday.
        let sunday = try #require(iso.date(from: "2026-10-04T12:00:00Z"))

        let sundayWeeks = WeeklyVolumeCard.weeks(from: [sunday], now: now, calendar: WeekStartDay.sunday.calendar(utc))
        let mondayWeeks = WeeklyVolumeCard.weeks(from: [sunday], now: now, calendar: WeekStartDay.monday.calendar(utc))

        #expect(sundayWeeks.map(\.sessions).suffix(2) == [0, 1])
        #expect(mondayWeeks.map(\.sessions).suffix(2) == [1, 0])
        #expect(mondayWeeks.last?.start == iso.date(from: "2026-10-05T00:00:00Z"))
    }
}
