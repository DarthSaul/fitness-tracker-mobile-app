import Foundation
import Testing
import UIKit
@testable import FitnessTracker

/// Regression tests for the PR #53 review fixes.
@Suite("PR #53 review fixes")
@MainActor
struct ReviewFixRegressionTests {
    // MARK: - Activity dismiss

    @Test("a partly failed dismiss keeps only the failed notifications visible")
    func partialDismiss() async {
        let harness = SocialTestHarness()
        let repository = NotificationsRepository(apiClient: harness.client)
        let notifications = NotificationCenterModel(repository: repository, sessionManager: harness.sessionManager, badgeSetter: { _ in })
        harness.client.stub(.getUnreadNotificationCount, response: CountResponseDTO(count: 0))
        harness.client.stub(.getFollowRequests(direction: .incoming), response: FollowRequestsResponseDTO(requests: []))
        harness.client.stub(.markAllNotificationsRead(MarkAllReadBody(before: nil)), response: CountResponseDTO(count: 0))
        let target = NotificationTargetDTO(postId: "p1")
        harness.client.stub(.getNotifications(status: .all, page: .firstPage), response: NotificationsResponseDTO(notifications: [
            SocialFactory.notification("n1", type: .postReaction, actor: SocialFactory.user("u1"), target: target),
            SocialFactory.notification("n2", type: .postReaction, actor: SocialFactory.user("u2"), target: target),
        ]))
        let viewModel = ActivityViewModel(context: harness.context, notifications: notifications)
        await viewModel.open()
        let item = viewModel.items[0]
        #expect(item.notifications.count == 2)

        let dismissed = SocialFactory.notification("n1", type: .postReaction, status: .dismissed, target: target)
        harness.client.handlers["PATCH /api/notifications/n1"] = { _ in
            try JSONCoding.encoder.encode(NotificationResponseDTO(notification: dismissed))
        }
        harness.client.stubHTTPError(.updateNotification(id: "n2", body: UpdateNotificationBody(status: .dismissed)), status: 500)

        await viewModel.dismiss(item)

        #expect(viewModel.inbox.items.map(\.id) == ["n2"])
        #expect(viewModel.items.first?.notifications.map(\.id) == ["n2"])
    }

    // MARK: - Notification preferences

    @Test("a failed preference save reverts only its own field")
    func preferenceRevertsOwnField() async {
        let harness = SocialTestHarness()
        let viewModel = NotificationPreferencesViewModel(
            repository: NotificationsRepository(apiClient: harness.client),
            context: harness.context
        )
        harness.client.stubJSON(.getNotificationPreferences, """
        {"push":{"FOLLOW_REQUEST":true,"POST_REACTION":true},"timezone":null,"workoutReminderTime":"08:00","workoutReminderDay":"sameDay"}
        """)
        await viewModel.load()

        harness.client.handlers["PATCH /api/notifications/preferences"] = { endpoint in
            guard case .updateNotificationPreferences(let body) = endpoint else { return Data() }
            if body.push?["POST_REACTION"] != nil {
                throw APIError.httpError(statusCode: 500, message: nil, data: Data())
            }
            // Succeeds, echoing a full (stale-looking) copy the client must not adopt.
            return Data(#"{"push":{"FOLLOW_REQUEST":false,"POST_REACTION":true},"timezone":null,"workoutReminderTime":"08:00","workoutReminderDay":"sameDay"}"#.utf8)
        }

        await viewModel.set(.followRequest, false)
        await viewModel.set(.postReaction, false)

        #expect(!viewModel.isOn(.followRequest), "the successful change stays")
        #expect(viewModel.isOn(.postReaction), "only the failed field reverts")
    }

    // MARK: - Edit profile

    @Test("a bio with stray whitespace doesn't read as edited")
    func bioTrimmed() async {
        let harness = SocialTestHarness()
        harness.client.stub(.getMe, response: UserProfile(
            id: "user-me", email: "s@example.com", name: nil, avatarUrl: nil, username: "saulg", bio: "Lifting \n"
        ))
        await harness.sessionManager.loadProfile()
        let viewModel = EditProfileViewModel(context: harness.context, debounce: .zero)
        #expect(!viewModel.bioChanged)
        #expect(!viewModel.canSave)
    }

    // MARK: - Settings privacy

    @Test("a failed switch to public doesn't announce follow changes")
    func failedGoPublic() async {
        let harness = SocialTestHarness()
        let log = harness.recordEvents()
        harness.client.stub(.getMe, response: UserProfile(
            id: "user-me", email: "s@example.com", name: nil, avatarUrl: nil, profileVisibility: .private
        ))
        await harness.sessionManager.loadProfile()
        harness.client.stubHTTPError(.updateMe(UpdateMeBody()), status: 500)

        await SocialSettingsViewModel(context: harness.context).setPrivate(false)

        #expect(!log.events.contains { if case .followsChanged = $0 { true } else { false } })
    }

    @Test("overlapping settings saves don't undo each other")
    func overlappingSettingsSaves() async throws {
        let harness = SocialTestHarness()
        let original = UserProfile(
            id: "user-me", email: "s@example.com", name: nil, avatarUrl: nil,
            profileVisibility: .private, showActiveProgram: true, showWorkoutCount: true
        )
        harness.client.stub(.getMe, response: original)
        await harness.sessionManager.loadProfile()

        // The server echoes the whole profile with only that request's field
        // changed — so each response is stale about the other save.
        harness.client.handlers["PATCH /api/auth/me"] = { endpoint in
            guard case .updateMe(let body) = endpoint else { return Data() }
            var echoed = original
            if let value = body.showActiveProgram { echoed.showActiveProgram = value }
            if let value = body.showWorkoutCount { echoed.showWorkoutCount = value }
            return try JSONCoding.encoder.encode(echoed)
        }
        let viewModel = SocialSettingsViewModel(context: harness.context)
        let endpoint = APIEndpoint.updateMe(UpdateMeBody())

        // First save is held on the wire while the second completes.
        harness.client.holdNextResponse(for: endpoint)
        let first = Task { await viewModel.setShowActiveProgram(false) }
        for _ in 0..<200 where !harness.client.isHolding(endpoint) { await Task.yield() }
        #expect(harness.client.isHolding(endpoint))

        await viewModel.setShowWorkoutCount(false)
        #expect(!viewModel.showActiveProgram, "the second save didn't restore the first field")

        harness.client.release(endpoint)
        await first.value

        #expect(!viewModel.showActiveProgram)
        #expect(!viewModel.showWorkoutCount, "the first save's stale response didn't undo the second")
    }

    @Test("a failed settings save reverts only its own field")
    func settingsRevertOwnField() async {
        let harness = SocialTestHarness()
        harness.client.stub(.getMe, response: UserProfile(
            id: "user-me", email: "s@example.com", name: nil, avatarUrl: nil,
            showActiveProgram: true, showWorkoutCount: true
        ))
        await harness.sessionManager.loadProfile()
        harness.client.handlers["PATCH /api/auth/me"] = { endpoint in
            guard case .updateMe(let body) = endpoint, body.showWorkoutCount == nil else {
                throw APIError.httpError(statusCode: 500, message: nil, data: Data())
            }
            return try JSONCoding.encoder.encode(UserProfile(
                id: "user-me", email: "s@example.com", name: nil, avatarUrl: nil,
                showActiveProgram: false, showWorkoutCount: true
            ))
        }
        let viewModel = SocialSettingsViewModel(context: harness.context)

        await viewModel.setShowActiveProgram(false)
        await viewModel.setShowWorkoutCount(false)

        #expect(!viewModel.showActiveProgram, "the successful change stays")
        #expect(viewModel.showWorkoutCount, "only the failed field reverts")
    }

    // MARK: - Compose

    @Test("overlapping photo picks never exceed four photos")
    func overlappingPicks() async throws {
        let harness = SocialTestHarness()
        harness.client.stub(.uploadPostPhoto, response: UploadedPhotoDTO(id: "ph", width: 4, height: 4))
        let viewModel = ComposeViewModel(context: harness.context)
        let png = try #require(UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }.pngData())

        async let first: Void = viewModel.addPhotos([png, png, png])
        async let second: Void = viewModel.addPhotos([png, png, png])
        _ = await (first, second)

        #expect(viewModel.photos.count == ComposeViewModel.maxPhotos)
    }

    // MARK: - Post menu on the stage

    @Test("a menu choice waits until the stage has closed")
    func queuedMenuAction() {
        let harness = SocialTestHarness()
        let interactions = PostInteractions(context: harness.context)
        let post = SocialFactory.post()

        interactions.queueMenuAction(.report(post))
        #expect(interactions.report == nil, "nothing presents while the stage is still up")

        interactions.runQueuedMenuAction()
        #expect(interactions.report?.id == ReportTarget.post(post).id)

        interactions.runQueuedMenuAction()
        #expect(interactions.blockCandidate == nil, "the action runs once")
    }
}
