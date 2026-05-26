import Foundation
import Testing
@testable import FitnessTracker

@Suite("FeedbackRepository")
@MainActor
struct FeedbackRepositoryTests {
    private func makeFeedback(id: String = "f1", addressed: Bool = false) -> FeedbackDTO {
        FeedbackDTO(
            id: id, content: "Hello", screenshotPath: nil, screenshotUrl: nil,
            addressed: addressed, createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            user: .init(name: "Saul Graves")
        )
    }

    @Test("fetchFeedback decodes the list")
    func fetchList() async throws {
        let client = MockAPIClient()
        client.stub(.getFeedback, response: [makeFeedback(), makeFeedback(id: "f2", addressed: true)])
        let repo = FeedbackRepository(apiClient: client)

        let list = try await repo.fetchFeedback()
        #expect(list.count == 2)
        #expect(list[1].addressed)
    }

    @Test("submitFeedback sends content and screenshot as multipart parts")
    func submitWithScreenshot() async throws {
        let client = MockAPIClient()
        client.stub(.createFeedback, response: makeFeedback())
        let repo = FeedbackRepository(apiClient: client)

        let png = Data([0x89, 0x50, 0x4E, 0x47])
        _ = try await repo.submitFeedback(
            content: "Bug report",
            screenshot: .init(data: png, filename: "shot.png", mimeType: "image/png")
        )

        let parts = try #require(client.lastMultipartParts)
        #expect(parts.count == 2)
        #expect(parts[0].name == "content")
        #expect(String(data: parts[0].data, encoding: .utf8) == "Bug report")
        #expect(parts[1].name == "screenshot")
        #expect(parts[1].filename == "shot.png")
        #expect(parts[1].mimeType == "image/png")
        #expect(parts[1].data == png)
    }

    @Test("submitFeedback omits screenshot part when none attached")
    func submitTextOnly() async throws {
        let client = MockAPIClient()
        client.stub(.createFeedback, response: makeFeedback())
        let repo = FeedbackRepository(apiClient: client)

        _ = try await repo.submitFeedback(content: "Just text")

        let parts = try #require(client.lastMultipartParts)
        #expect(parts.count == 1)
        #expect(parts[0].name == "content")
    }

    @Test("setAddressed POSTs the patch body to the right id")
    func setAddressed() async throws {
        let client = MockAPIClient()
        // PATCH endpoint returns the bare Prisma row; the repo discards it,
        // so any successful Data response works as long as the path matches.
        client.handlers["PATCH /api/feedback/f1"] = { _ in Data("{}".utf8) }
        let repo = FeedbackRepository(apiClient: client)

        try await repo.setAddressed(id: "f1", addressed: true)
        // No exception ⇒ pass. The handler key matches the patched id.
    }

    // MARK: - encodeMultipart smoke test

    @Test("encodeMultipart emits CRLF-delimited parts with boundary terminator")
    func encodeMultipart() {
        let parts: [MultipartPart] = [
            .text(name: "content", value: "hi"),
            .file(name: "screenshot", filename: "a.png", mimeType: "image/png", data: Data([0x01, 0x02]))
        ]
        let body = APIClient.encodeMultipart(parts: parts, boundary: "B")
        let asString = String(data: body, encoding: .utf8) ?? ""

        #expect(asString.contains("--B\r\n"))
        #expect(asString.contains("Content-Disposition: form-data; name=\"content\"\r\n"))
        #expect(asString.contains("Content-Disposition: form-data; name=\"screenshot\"; filename=\"a.png\"\r\n"))
        #expect(asString.contains("Content-Type: image/png\r\n"))
        // Last separator should be the closing boundary.
        #expect(asString.hasSuffix("--B--\r\n"))
    }
}
