import Foundation
import Testing
@testable import FitnessTracker

@Suite("Notification DTO decoding")
struct NotificationDTOTests {
    @Test("a reaction notification decodes with its emoji and target")
    func reactionNotification() throws {
        let item = try SocialFixtures.decode(NotificationItemDTO.self, SocialFixtures.notificationJSON())
        #expect(item.type == .postReaction)
        #expect(item.status == .unread)
        #expect(item.actor?.username == "ann")
        #expect(item.target.postId == "post-1")
        #expect(item.data.emoji == "🔥")
        #expect(item.cursor == PageCursor(before: "2026-10-02T12:00:00.000Z", beforeId: "n-1"))
    }

    @Test("an unknown type decodes as .unknown instead of failing the page")
    func unknownTypeDoesNotFailPage() throws {
        let json = """
        {"notifications":[\(SocialFixtures.notificationJSON(id: "a", type: "COMMENT_LIKE")),\
        \(SocialFixtures.notificationJSON(id: "b"))]}
        """
        let page = try SocialFixtures.decode(NotificationsResponseDTO.self, json)
        #expect(page.notifications.count == 2)
        #expect(page.notifications[0].type == .unknown("COMMENT_LIKE"))
        #expect(!page.notifications[0].type.isKnown)
        #expect(page.notifications[1].type == .postReaction)
    }

    @Test("a workout reminder decodes numeric data and has no actor")
    func workoutReminderData() throws {
        let json = SocialFixtures.notificationJSON(
            type: "WORKOUT_REMINDER",
            actor: nil,
            target: #"{"scheduledWorkoutId":"sw-1"}"#,
            data: #"{"programName":"Arm Farm 2","weekNumber":3,"dayNumber":2,"day":"tomorrow"}"#
        )
        let item = try SocialFixtures.decode(NotificationItemDTO.self, json)
        #expect(item.actor == nil)
        #expect(item.target.scheduledWorkoutId == "sw-1")
        #expect(item.data.programName == "Arm Farm 2")
        #expect(item.data.weekNumber == 3)
        #expect(item.data.dayNumber == 2)
        #expect(item.data.day == "tomorrow")
    }

    @Test("non-scalar data values are skipped, not fatal")
    func nonScalarDataSkipped() throws {
        let json = SocialFixtures.notificationJSON(data: #"{"emoji":"🔥","nested":{"a":1}}"#)
        let item = try SocialFixtures.decode(NotificationItemDTO.self, json)
        #expect(item.data.emoji == "🔥")
        #expect(item.data.values["nested"] == nil)
    }

    @Test("preferences keep unknown push keys and default missing ones to on")
    func preferences() throws {
        let json = """
        {"push":{"FOLLOW_REQUEST":false,"POST_REACTION":true,"BRAND_NEW":true},
         "timezone":null,"workoutReminderTime":"08:00","workoutReminderDay":"dayBefore"}
        """
        let prefs = try SocialFixtures.decode(NotificationPreferencesDTO.self, json)
        #expect(!prefs.isPushEnabled(.followRequest))
        #expect(prefs.isPushEnabled(.postReaction))
        #expect(prefs.isPushEnabled(.workoutReminder))
        #expect(prefs.push["BRAND_NEW"] == true)
        #expect(prefs.workoutReminderDay == .dayBefore)
        #expect(prefs.timezone == nil)
    }

    @Test("only the workout types are turned off entirely by their toggle")
    func preferenceSemantics() {
        #expect(NotificationType.workoutReminder.preferenceDisablesEntirely)
        #expect(NotificationType.workoutUnfinished.preferenceDisablesEntirely)
        #expect(!NotificationType.followRequest.preferenceDisablesEntirely)
        #expect(!NotificationType.postReaction.preferenceDisablesEntirely)
    }
}
