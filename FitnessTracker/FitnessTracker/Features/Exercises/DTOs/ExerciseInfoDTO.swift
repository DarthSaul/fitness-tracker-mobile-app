import Foundation

/// GET /api/exercises/:exerciseId/info — demonstration media for one exercise.
///
/// `animationUrl` / `posterUrl` are short-lived signed Supabase Storage URLs
/// (about 15 minutes, see `mediaExpiresAt`). Never persist them — the demo
/// sheet re-fetches on every open. URLs stay `String?` rather than `URL?` so a
/// malformed value degrades to "no demo" instead of failing the whole decode.
nonisolated struct ExerciseInfoDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    /// External (YouTube) demonstration link, if any. Not used by the demo sheet.
    let videoUrl: String?
    let animationUrl: String?
    let posterUrl: String?
    let mediaExpiresAt: Date?

    var animationURL: URL? { animationUrl.flatMap(URL.init(string:)) }
    var posterURL: URL? { posterUrl.flatMap(URL.init(string:)) }
}
