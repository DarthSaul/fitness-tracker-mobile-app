import Foundation
import Testing
import UIKit
@testable import FitnessTracker

@Suite("Post-workout share prompt")
@MainActor
struct PostWorkoutShareViewModelTests {
    private func summary(_ share: CreatePostBody.SharedWorkout = .program(sessionId: "ws-1")) -> WorkoutCompletionSummary {
        WorkoutCompletionSummary(
            share: share, title: nil, position: "Week 2 · Day 4",
            sets: 32, volumeLbs: 19_140
        )
    }

    private func makeViewModel(
        _ summary: WorkoutCompletionSummary? = nil
    ) -> (PostWorkoutShareViewModel, SocialTestHarness) {
        let harness = SocialTestHarness()
        let viewModel = PostWorkoutShareViewModel(
            summary: summary ?? self.summary(),
            context: harness.context,
            historyRepository: HistoryRepository(apiClient: harness.client)
        )
        return (viewModel, harness)
    }

    private func createBodies(_ harness: SocialTestHarness) -> [CreatePostBody] {
        harness.sent { if case .createPost(let body) = $0 { body } else { nil } }
    }

    // MARK: - Summary

    @Test("highlights format volume")
    func highlights() {
        #expect(summary().formattedVolume == "19.1k")
        #expect(WorkoutCompletionSummary(share: .program(sessionId: "x"), sets: 1, volumeLbs: 950).formattedVolume == "950")
    }

    @Test("volume sums reps × weight, skipping sets without both")
    func volume() {
        #expect(WorkoutCompletionSummary.volume([(5, 100), (3, 200), (nil, 50), (8, nil)]) == 1100)
    }

    // MARK: - Loading

    @Test("load fills the program name from history and the follower count")
    func load() async {
        let (viewModel, harness) = makeViewModel()
        harness.client.stub(
            .getHistory(type: nil, limit: 5, before: nil, beforeId: nil),
            response: HistoryResponseDTO(sessions: [.program(HistorySessionDTO(
                id: "ws-1", userId: "user-me", userProgramId: "up1", programName: "Arm Farm 2",
                weekNumber: 2, dayNumber: 4, status: .completed, startedAt: .now, completedAt: .now,
                notes: nil, count: .init(completedSets: 32)
            ))])
        )
        harness.client.stubJSON(.getUser(id: "user-me"), """
        {"id":"user-me","name":"Me","avatarUrl":null,"profileVisibility":"PRIVATE","username":"me",
         "isSelf":true,"outgoing":"none","incoming":"none","incomingRequestId":null,
         "bio":null,"followerCount":48,"followingCount":3,"activeProgram":null,"completedWorkoutCount":12}
        """)

        await viewModel.load()

        #expect(viewModel.summary.subtitle == "Arm Farm 2 · Week 2 · Day 4")
        #expect(viewModel.audienceText == "48 followers will see it on their timeline.")
    }

    @Test("audience copy before load and with no followers")
    func audienceCopy() {
        let (viewModel, _) = makeViewModel()
        #expect(viewModel.audienceText == "Your followers will see it on their timeline.")
    }

    // MARK: - Sharing

    @Test("Share posts the caption with the program session id")
    func shareProgram() async {
        let (viewModel, harness) = makeViewModel()
        let log = harness.recordEvents()
        harness.client.stub(.createPost(CreatePostBody(body: nil)), response: SocialFactory.post("new", isMine: true))
        viewModel.caption = "  Legs done "

        let closed = await viewModel.share()

        #expect(closed)
        #expect(createBodies(harness) == [CreatePostBody(body: "Legs done", sharing: .program(sessionId: "ws-1"))])
        #expect(log.events.contains { if case .postCreated = $0 { true } else { false } })
        #expect(viewModel.didShare)
    }

    @Test("a standalone workout shares by standaloneSessionId, caption optional")
    func shareStandalone() async {
        let (viewModel, harness) = makeViewModel(summary(.standalone(sessionId: "ss-9")))
        harness.client.stub(.createPost(CreatePostBody(body: nil)), response: SocialFactory.post("new", isMine: true))

        _ = await viewModel.share()

        #expect(createBodies(harness) == [CreatePostBody(body: nil, sharing: .standalone(sessionId: "ss-9"))])
    }

    @Test("attached photos go on the post; a failed upload blocks sharing until removed")
    func sharePhotos() async throws {
        let (viewModel, harness) = makeViewModel()
        harness.client.stub(.uploadPostPhoto, response: UploadedPhotoDTO(id: "ph-1", width: 4, height: 4))
        harness.client.stub(.createPost(CreatePostBody(body: nil)), response: SocialFactory.post("new", isMine: true))
        let png = try #require(UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }.pngData())

        await viewModel.photoAttachments.addPhotos([png])
        #expect(viewModel.canShare)
        _ = await viewModel.share()
        #expect(createBodies(harness).first?.photoIds == ["ph-1"])

        let (failing, failingHarness) = makeViewModel()
        failingHarness.client.stubHTTPError(.uploadPostPhoto, status: 429)
        await failing.photoAttachments.addPhotos([png])
        #expect(!failing.canShare)
        failing.photoAttachments.removePhoto(try #require(failing.photoAttachments.photos.first?.id))
        #expect(failing.canShare)
    }

    @Test("already shared (409) closes the prompt; other failures keep it open")
    func conflicts() async {
        let (viewModel, harness) = makeViewModel()
        harness.client.stubHTTPError(.createPost(CreatePostBody(body: nil)), status: 409, message: "Workout already shared")
        #expect(await viewModel.share())

        let (other, otherHarness) = makeViewModel()
        otherHarness.client.stubHTTPError(.createPost(CreatePostBody(body: nil)), status: 429)
        #expect(await other.share() == false)
        #expect(other.errorMessage == APIFailure.rateLimited.message)
    }
}
