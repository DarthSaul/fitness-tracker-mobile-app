import Foundation
import Testing
@testable import FitnessTracker

@Suite("Activity rows")
struct ActivityItemTests {
    private let dev = SocialFactory.user("u-dev", name: "Dev Patel", username: "devpulls")
    private let maya = SocialFactory.user("u-maya", name: "Maya Ortiz", username: "maya.lifts")
    private let ana = SocialFactory.user("u-ana", name: "Ana Lucero", username: "analu")

    private func reaction(_ id: String, by actor: PublicUserDTO, post: String, emoji: String = "💪") -> NotificationItemDTO {
        SocialFactory.notification(
            id, type: .postReaction, actor: actor,
            target: NotificationTargetDTO(postId: post),
            data: NotificationDataDTO(["emoji": .string(emoji)])
        )
    }

    @Test("reactions to the same post group into one row")
    func groupsReactions() {
        let items = ActivityItem.build(from: [
            reaction("n1", by: dev, post: "p1"),
            reaction("n2", by: maya, post: "p2", emoji: "🔥"),
            reaction("n3", by: ana, post: "p1"),
            reaction("n4", by: SocialFactory.user("u-x"), post: "p1"),
        ])
        #expect(items.count == 2)
        #expect(items[0].notifications.map(\.id) == ["n1", "n3", "n4"])
        #expect(items[0].text.name == "Dev Patel")
        #expect(items[0].text.rest == "and 2 others reacted to your post")
        #expect(items[1].text.rest == "reacted 🔥 to your post")
    }

    @Test("follow requests and unknown types aren't rows")
    func hidesRequestsAndUnknown() {
        let items = ActivityItem.build(from: [
            SocialFactory.notification("n1", type: .followRequest, target: NotificationTargetDTO(followId: "f1")),
            SocialFactory.notification("n2", type: .unknown("COMMENT_LIKE")),
            SocialFactory.notification("n3", type: .followAccepted, actor: maya),
        ])
        #expect(items.map(\.id) == ["n3"])
        #expect(items[0].text.rest == "accepted your follow request")
    }

    @Test("a workout reminder reads its program, position and day")
    func reminderText() {
        let item = ActivityItem.build(from: [
            SocialFactory.notification(
                "n1", type: .workoutReminder, actor: nil,
                target: NotificationTargetDTO(scheduledWorkoutId: "sw-1"),
                data: NotificationDataDTO([
                    "programName": .string("Arm Farm 2"), "weekNumber": .number(3), "dayNumber": .number(2), "day": .string("tomorrow"),
                ])
            ),
        ])[0]
        #expect(item.text.name == nil)
        #expect(item.text.rest == "Your Arm Farm 2 workout (Week 3 · Day 2) is scheduled for tomorrow.")
        #expect(item.destination == .home)
    }

    @Test("a group is unread if any notification in it is")
    func unreadGroup() {
        let items = ActivityItem.build(from: [
            reaction("n1", by: dev, post: "p1"),
            SocialFactory.notification("n2", type: .postReaction, status: .read, actor: ana, target: NotificationTargetDTO(postId: "p1")),
        ])
        #expect(items[0].isUnread)
    }

    @Test("rows split into Today, This week and Earlier")
    func sections() throws {
        let now = try #require(JSONCoding.parseISO8601("2026-10-02T18:00:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let items = ActivityItem.build(from: [
            SocialFactory.notification("today", type: .newFollower, createdAt: "2026-10-02T09:00:00.000Z"),
            SocialFactory.notification("week", type: .newFollower, createdAt: "2026-09-29T09:00:00.000Z"),
            SocialFactory.notification("old", type: .newFollower, createdAt: "2026-09-01T09:00:00.000Z"),
        ])
        let groups = ActivitySections.group(items, now: now, calendar: calendar)
        #expect(groups.map(\.section) == [.today, .thisWeek, .earlier])
        #expect(groups.map { $0.items.map(\.id) } == [["today"], ["week"], ["old"]])
    }
}

@Suite("Notification destinations and push payloads")
struct NotificationRoutingTests {
    @Test("each type opens the right place")
    func destinations() {
        #expect(NotificationDestination.for(type: .postReaction, target: NotificationTargetDTO(postId: "p1"), actorId: "u1") == .friends([.post(id: "p1")]))
        #expect(NotificationDestination.for(type: .followRequest, target: NotificationTargetDTO(followId: "f1"), actorId: "u1") == .friends([.requests]))
        #expect(NotificationDestination.for(type: .newFollower, target: .empty, actorId: "u1") == .friends([.profile(userId: "u1")]))
        #expect(NotificationDestination.for(type: .followAccepted, target: .empty, actorId: nil) == .friends([.activity]))
        #expect(NotificationDestination.for(type: .workoutUnfinished, target: NotificationTargetDTO(workoutSessionId: "w1"), actorId: nil) == .home)
        #expect(NotificationDestination.for(type: .unknown("X"), target: .empty, actorId: nil) == .friends([.activity]))
    }

    @Test("a push payload parses notificationId, type and target")
    func parsesPayload() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "New reaction"], "badge": 3],
            "notificationId": "n-9",
            "type": "POST_REACTION",
            "target": ["postId": "p-1"],
        ]
        let payload = PushPayload(userInfo: userInfo)
        #expect(payload == PushPayload(notificationId: "n-9", type: .postReaction, target: NotificationTargetDTO(postId: "p-1")))
    }

    @Test("a push without our fields isn't ours")
    func ignoresForeignPayload() {
        #expect(PushPayload(userInfo: ["aps": ["alert": "hi"]]) == nil)
    }
}

@Suite("NotificationCenterModel")
@MainActor
struct NotificationCenterModelTests {
    @Test("the unread count also sets the app badge")
    func unreadSetsBadge() async {
        let harness = SocialTestHarness()
        harness.client.stub(.getUnreadNotificationCount, response: CountResponseDTO(count: 4))
        var badge: Int?
        let model = NotificationCenterModel(
            repository: NotificationsRepository(apiClient: harness.client),
            sessionManager: harness.sessionManager,
            badgeSetter: { badge = $0 }
        )
        await model.refreshUnreadCount()
        #expect(model.unreadCount == 4)
        #expect(badge == 4)
    }

    @Test("the timezone is sent as an IANA name, once per change")
    func timezoneSync() async throws {
        let harness = SocialTestHarness()
        harness.client.stubJSON(
            .updateNotificationPreferences(UpdateNotificationPreferencesBody()),
            #"{"push":{},"timezone":"America/Chicago","workoutReminderTime":"08:00","workoutReminderDay":"sameDay"}"#
        )
        let model = NotificationCenterModel(
            repository: NotificationsRepository(apiClient: harness.client),
            sessionManager: harness.sessionManager,
            badgeSetter: { _ in }
        )
        let chicago = try #require(TimeZone(identifier: "America/Chicago"))

        await model.syncTimezone(chicago)
        await model.syncTimezone(chicago)

        let bodies: [UpdateNotificationPreferencesBody] = harness.sent {
            if case .updateNotificationPreferences(let body) = $0 { body } else { nil }
        }
        #expect(bodies == [UpdateNotificationPreferencesBody(timezone: "America/Chicago")])

        await model.syncTimezone(try #require(TimeZone(identifier: "Europe/London")))
        #expect(harness.client.callCount(for: .updateNotificationPreferences(UpdateNotificationPreferencesBody())) == 2)
    }
}
