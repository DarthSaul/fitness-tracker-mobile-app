import Foundation

/// Surfaces the bundle's marketing version + build number for the Settings
/// "About" section. Reads `CFBundleShortVersionString` and `CFBundleVersion`
/// (driven by MARKETING_VERSION / CURRENT_PROJECT_VERSION in build settings).
enum AppVersion {
    static var displayString: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (marketing, build) {
        case (let m?, let b?): return "\(m) (\(b))"
        case (let m?, nil): return m
        default: return "—"
        }
    }
}
