import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var syncManager: SyncManager
    @EnvironmentObject private var router: ComposeRouter
    @Environment(\.scenePhase) private var scenePhase
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
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            // Set by OpenComposeIntent (Control Center button) right before launch.
            if Configuration.pendingCompose {
                Configuration.pendingCompose = false
                selectedTab = 0
                router.showCompose = true
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Thought.self, inMemory: true)
}
