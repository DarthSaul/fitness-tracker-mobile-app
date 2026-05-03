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
    /// Returns the configured Sentry DSN, or `nil` if the value is missing,
    /// empty, or still the placeholder shipped in the xcconfig templates.
    /// Callers should skip Sentry initialization when this is `nil` rather
    /// than crash, so dev builds without a real DSN still launch.
    nonisolated static let sentryDSN: String? = {
        guard
            let dsn = Bundle.main.infoDictionary?["SENTRY_DSN"] as? String,
            !dsn.isEmpty,
            dsn != "SENTRY_DSN_PLACEHOLDER"
        else {
            return nil
        }
        return dsn
    }()
}
