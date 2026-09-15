import Foundation
import Testing
@testable import FitnessTracker

@Suite("ExerciseInfoDTO")
struct ExerciseInfoDTOTests {
    private let decoder = JSONCoding.decoder

    @Test("decodes a full payload with signed media URLs and a fractional-second expiry")
    func decodesFullPayload() throws {
        let json = #"""
        {
          "id": "cmo6joils001crqwkyrq2crik",
          "name": "DB Zottman Curls",
          "videoUrl": null,
          "animationUrl": "https://proj.supabase.co/storage/v1/object/sign/exercise-media/exercises/db-zottman-curls/tok/demo.mp4?token=sig",
          "posterUrl": "https://proj.supabase.co/storage/v1/object/sign/exercise-media/exercises/db-zottman-curls/tok/poster.webp?token=sig",
          "mediaExpiresAt": "2026-09-10T15:15:00.000Z"
        }
        """#.data(using: .utf8)!

        let dto = try decoder.decode(ExerciseInfoDTO.self, from: json)
        #expect(dto.id == "cmo6joils001crqwkyrq2crik")
        #expect(dto.name == "DB Zottman Curls")
        #expect(dto.videoUrl == nil)
        #expect(dto.animationURL?.host == "proj.supabase.co")
        #expect(dto.animationURL?.lastPathComponent == "demo.mp4")
        #expect(dto.posterURL?.lastPathComponent == "poster.webp")
        // 2026-09-10T15:15:00Z
        #expect(dto.mediaExpiresAt == Date(timeIntervalSince1970: 1_789_053_300))
    }

    @Test("decodes the no-media shape with every media field null")
    func decodesNoMedia() throws {
        let json = #"""
        { "id": "ex1", "name": "Farmer Carry", "videoUrl": null,
          "animationUrl": null, "posterUrl": null, "mediaExpiresAt": null }
        """#.data(using: .utf8)!

        let dto = try decoder.decode(ExerciseInfoDTO.self, from: json)
        #expect(dto.animationURL == nil)
        #expect(dto.posterURL == nil)
        #expect(dto.mediaExpiresAt == nil)
    }

    @Test("tolerates the legacy shape without posterUrl / mediaExpiresAt keys")
    func decodesLegacyShape() throws {
        let json = #"""
        { "id": "ex1", "name": "Bench Press", "videoUrl": null, "animationUrl": null }
        """#.data(using: .utf8)!

        let dto = try decoder.decode(ExerciseInfoDTO.self, from: json)
        #expect(dto.posterUrl == nil)
        #expect(dto.mediaExpiresAt == nil)
        #expect(dto.animationURL == nil)
    }

    @Test("a malformed animationUrl decodes but yields no URL")
    func malformedURL() throws {
        let json = #"""
        { "id": "ex1", "name": "Bench Press", "videoUrl": null,
          "animationUrl": "not a url", "posterUrl": null, "mediaExpiresAt": null }
        """#.data(using: .utf8)!

        let dto = try decoder.decode(ExerciseInfoDTO.self, from: json)
        #expect(dto.animationUrl == "not a url")
        #expect(dto.animationURL == nil)
    }

    @Test("getExerciseInfo endpoint targets /api/exercises/:id/info with GET")
    func endpoint() {
        let endpoint = APIEndpoint.getExerciseInfo(exerciseId: "ex1")
        #expect(endpoint.path == "/api/exercises/ex1/info")
        #expect(endpoint.method == .get)
        #expect(endpoint.body == nil)
        #expect(endpoint.queryItems == nil)
    }
}
