import SwiftUI

/// Home tab — calendar strip, today's workout card, schedule modal arrive in PR #5.
struct HomeTab: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Home",
                systemImage: "house",
                description: Text("Calendar strip and today's workout will live here.")
            )
            .navigationTitle("Home")
            .settingsToolbarItem()
        }
    }
}
