import Foundation
import Testing
import UIKit
@testable import FitnessTracker

@Suite("ComposeViewModel")
@MainActor
struct ComposeViewModelTests {
    private func createBodies(_ harness: SocialTestHarness) -> [CreatePostBody] {
        harness.sent { if case .createPost(let body) = $0 { body } else { nil } }
    }

    @Test("Post is disabled with no caption and nothing attached")
    func emptyDisabled() {
        let viewModel = ComposeViewModel(context: SocialTestHarness().context)
        #expect(!viewModel.canSubmit)
        viewModel.caption = "   \n"
        #expect(!viewModel.canSubmit)
        viewModel.caption = "Leg day"
        #expect(viewModel.canSubmit)
    }

    @Test("an attached workout allows an empty caption")
    func workoutAllowsEmptyCaption() {
        let viewModel = ComposeViewModel(
            context: SocialTestHarness().context,
            workout: .init(share: .program(sessionId: "ws-1"), label: "Arm Farm 2 · Week 2 · Day 4")
        )
        #expect(viewModel.canSubmit)
    }

    @Test("the caption is capped at 500, counted like the server")
    func captionLimit() {
        let viewModel = ComposeViewModel(context: SocialTestHarness().context)
        viewModel.caption = String(repeating: "a", count: 500)
        #expect(viewModel.canSubmit)
        viewModel.caption = String(repeating: "a", count: 499) + "💪"
        #expect(viewModel.isCaptionTooLong)
        #expect(!viewModel.canSubmit)
    }

    @Test("posting sends the caption and shared workout, then broadcasts the post")
    func postsAndBroadcasts() async {
        let harness = SocialTestHarness()
        let log = harness.recordEvents()
        harness.client.stub(.createPost(CreatePostBody(body: nil)), response: SocialFactory.post("new", isMine: true))
        let viewModel = ComposeViewModel(
            context: harness.context,
            workout: .init(share: .standalone(sessionId: "ss-1"), label: "Strength on the Go")
        )
        viewModel.caption = " Done \n"

        let posted = await viewModel.submit()

        #expect(posted)
        #expect(createBodies(harness) == [CreatePostBody(body: "Done", sharing: .standalone(sessionId: "ss-1"))])
        #expect(log.events.contains { if case .postCreated(let post) = $0 { post.id == "new" } else { false } })
    }

    @Test("a conflict shows the specific message and keeps the draft")
    func conflictMessage() async {
        let harness = SocialTestHarness()
        harness.client.stubHTTPError(.createPost(CreatePostBody(body: nil)), status: 409, message: "Workout already shared")
        let viewModel = ComposeViewModel(
            context: harness.context,
            workout: .init(share: .program(sessionId: "ws-1"), label: "x")
        )
        viewModel.caption = "Again"
        let posted = await viewModel.submit()
        #expect(!posted)
        #expect(viewModel.errorMessage == "You've already shared this workout.")
        #expect(viewModel.caption == "Again")
    }

    @Test("a picked photo is uploaded as JPEG and its id goes on the post")
    func photoUpload() async throws {
        let harness = SocialTestHarness()
        harness.client.stub(.uploadPostPhoto, response: UploadedPhotoDTO(id: "ph-1", width: 10, height: 10))
        harness.client.stub(.createPost(CreatePostBody(body: nil)), response: SocialFactory.post("new", isMine: true))
        let viewModel = ComposeViewModel(context: harness.context)

        let png = try #require(UIGraphicsImageRenderer(size: CGSize(width: 20, height: 10)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        }.pngData())
        await viewModel.addPhotos([png])

        #expect(viewModel.photos.first?.state == .uploaded(id: "ph-1"))
        let part = try #require(harness.client.lastMultipartParts?.first)
        #expect(part.name == "photo")
        #expect(part.mimeType == "image/jpeg")
        #expect(UIImage(data: part.data) != nil)

        #expect(viewModel.canSubmit, "a photo alone is enough to post")
        await viewModel.submit()
        #expect(createBodies(harness).first?.photoIds == ["ph-1"])
    }

    @Test("a failed upload blocks posting until removed")
    func failedUploadBlocks() async throws {
        let harness = SocialTestHarness()
        harness.client.stubHTTPError(.uploadPostPhoto, status: 429)
        let viewModel = ComposeViewModel(context: harness.context)
        viewModel.caption = "Hi"
        let png = try #require(UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }.pngData())

        await viewModel.addPhotos([png])
        #expect(!viewModel.canSubmit)

        viewModel.removePhoto(try #require(viewModel.photos.first?.id))
        #expect(viewModel.canSubmit)
    }

    @Test("photos are downscaled to 2048 on the long edge")
    func targetSize() {
        #expect(PhotoProcessing.targetSize(for: CGSize(width: 4032, height: 3024)) == CGSize(width: 2048, height: 1536))
        #expect(PhotoProcessing.targetSize(for: CGSize(width: 1000, height: 3000)) == CGSize(width: 683, height: 2048))
        #expect(PhotoProcessing.targetSize(for: CGSize(width: 800, height: 600)) == CGSize(width: 800, height: 600))
    }
}
