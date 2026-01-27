import SwiftUI
import SwiftData

@main
struct ReceptorApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    let container: ModelContainer

    init() {
        do {
            // Use shared App Group container for SwiftData
            let config = ModelConfiguration(
                url: Configuration.sharedContainerURL!.appendingPathComponent("Receptor.sqlite")
            )
            let modelContainer = try ModelContainer(for: Thought.self, configurations: config)
            self.container = modelContainer

            // Configure the shared SyncManager with the container
            SyncManager.shared.configure(with: modelContainer)

            // Request notification permission (iOS does this in AppDelegate)
            #if os(macOS)
            SyncManager.requestNotificationPermission()
            #endif

            // Reconnect background URLSession to pick up in-flight wake pings
            SyncManager.shared.reconnectBackgroundSession()
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        #if os(macOS)
        // Menu bar app on macOS
        MenuBarExtra {
            MenuBarMenu()
        } label: {
            Image(systemName: "brain.head.profile")
        }
        .menuBarExtraStyle(.menu)

        // Main window
        Window("Receptor", id: "main") {
            MacContentView()
                .environmentObject(SyncManager.shared)
                .modelContainer(container)
                .onAppear {
                    SyncManager.shared.requestFlush(trigger: .appBecameActive)
                }
        }
        .defaultSize(width: 500, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        // Settings window
        Settings {
            SettingsTab()
                .environmentObject(SyncManager.shared)
                .modelContainer(container)
                .frame(minWidth: 450, minHeight: 500)
        }
        #else
        // iOS app
        WindowGroup {
            ContentView()
                .environmentObject(SyncManager.shared)
                .onAppear {
                    SyncManager.shared.requestFlush(trigger: .appBecameActive)
                }
        }
        .modelContainer(container)
        #endif
    }
}

#if os(macOS)
struct MacContentView: View {
    @EnvironmentObject private var syncManager: SyncManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MacThoughtsTab()
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
        .frame(minWidth: 450, minHeight: 400)
    }
}

// macOS-specific ThoughtsTab without the toolbar issues
struct MacThoughtsTab: View {
    @EnvironmentObject private var syncManager: SyncManager
    @State private var showingCompose = false

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with status and add button
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(syncManager.isOnline ? .green : .orange)
                        .frame(width: 8, height: 8)
                    Text(syncManager.isOnline ? "Online" : "Offline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if syncManager.isSyncing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.trailing, 8)
                }

                Button {
                    showingCompose = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ThoughtListView()
        }
        .sheet(isPresented: $showingCompose) {
            ComposeView()
        }
    }
}
#endif
