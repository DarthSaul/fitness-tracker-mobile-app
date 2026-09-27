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

    var animationURL: URL? { animationUrl.flatMap(Self.mediaURL) }
    var posterURL: URL? { posterUrl.flatMap(Self.mediaURL) }

    /// `URL(string:)` percent-encodes invalid characters on iOS 17+ instead of
    /// returning nil, so parse strictly and require an absolute http(s) URL.
    private static func mediaURL(_ string: String) -> URL? {
        guard let url = URL(string: string, encodingInvalidCharacters: false),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host != nil
        else { return nil }
        return url
    }
}
