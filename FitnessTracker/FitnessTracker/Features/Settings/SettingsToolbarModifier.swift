import SwiftUI

/// Adds a person.crop.circle button to the trailing toolbar that opens the
/// SettingsView as a sheet. Apply to the inner content view of each tab so
/// the toolbar attaches to that tab's NavigationStack.
private struct SettingsToolbarModifier: ViewModifier {
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresented = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .accessibilityLabel("Settings")
                    }
                }
            }
            .sheet(isPresented: $isPresented) {
                SettingsView()
            }
    }
}

extension View {
    func settingsToolbarItem() -> some View {
        modifier(SettingsToolbarModifier())
    }
}
