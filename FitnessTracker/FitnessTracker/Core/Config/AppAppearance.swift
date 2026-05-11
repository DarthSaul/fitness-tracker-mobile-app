import SwiftUI

/// User-selectable color scheme persisted via @AppStorage and applied at the
/// scene root through `.preferredColorScheme(...)`. `system` defers to iOS.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// Nil means "use the system setting" — `.preferredColorScheme(nil)` lets
    /// iOS choose based on the current trait collection.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Default UserDefaults key for the appearance preference. Bound from both the
/// scene root (to apply the scheme) and the Settings picker (to mutate it).
let appAppearanceStorageKey = "appAppearance"
