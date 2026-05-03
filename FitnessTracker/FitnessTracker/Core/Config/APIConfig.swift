import Foundation

enum APIConfig {
    // MARK: - Base URL
    // Reads API_BASE_URL from Info.plist, which is populated by Debug.xcconfig / Release.xcconfig.
    nonisolated static let baseURL: URL = {
        guard
            let raw = Bundle.main.infoDictionary?["API_BASE_URL"] as? String,
            !raw.isEmpty,
            let url = URL(string: raw)
        else {
            fatalError("API_BASE_URL is missing or invalid in Info.plist — check your xcconfig.")
        }
        return url
    }()

    // MARK: - Sentry DSN
    nonisolated static let sentryDSN: String = {
        guard
            let dsn = Bundle.main.infoDictionary?["SENTRY_DSN"] as? String,
            !dsn.isEmpty
        else {
            fatalError("SENTRY_DSN is missing in Info.plist — check your xcconfig.")
        }
        return dsn
    }()
}
