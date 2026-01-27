import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var syncManager: SyncManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ThoughtsTab()
                .tabItem {
                    Label("Thoughts", systemImage: "brain.head.profile")
                }
                .tag(0)

            SettingsTab()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(1)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Thought.self, inMemory: true)
}
