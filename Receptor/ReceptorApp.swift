import SwiftUI
import SwiftData
import os.log

private let appLog = OSLog(subsystem: "com.alexmiller.receptor", category: "App")

@main
struct ReceptorApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    let container: ModelContainer

    init() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let proc = ProcessInfo.processInfo.processName
        os_log("[APP] ReceptorApp.init() — ENTRY pid=%d proc=%{public}@", log: appLog, type: .default, pid, proc)
        DebugFileLog.write("[APP] ReceptorApp.init() ENTRY pid=\(pid) proc=\(proc)")

        do {
            // Use shared App Group container for SwiftData
            let dbURL = Configuration.sharedContainerURL!.appendingPathComponent("Receptor.sqlite")
            os_log("[APP] ReceptorApp.init() — DB path=%{public}@", log: appLog, type: .default, dbURL.path)

            let config = ModelConfiguration(url: dbURL)
            let modelContainer = try ModelContainer(for: Thought.self, SyncLogEntry.self, configurations: config)
            self.container = modelContainer

            // Configure the shared SyncManager with the container
            SyncManager.shared.configure(with: modelContainer)
            os_log("[APP] ReceptorApp.init() — SyncManager configured", log: appLog, type: .default)

            // Request notification permission (iOS does this in AppDelegate)
            #if os(macOS)
            SyncManager.requestNotificationPermission()
            #endif

            // Reconnect background URLSession to pick up in-flight wake pings
            SyncManager.shared.reconnectBackgroundSession()
            os_log("[APP] ReceptorApp.init() — EXIT success", log: appLog, type: .default)
        } catch {
            os_log("[APP] ReceptorApp.init() — FATAL: ModelContainer init failed: %{public}@", log: appLog, type: .fault, error.localizedDescription)
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        #if os(macOS)
        // Menu bar app on macOS — clicking the icon opens the app UI directly
        // (a .window popover), instead of dropping down a menu.
        MenuBarExtra {
            MacContentView()
                .environmentObject(SyncManager.shared)
                .modelContainer(container)
                .frame(width: 400, height: 500)
        } label: {
            Image(systemName: "brain.head.profile")
        }
        .menuBarExtraStyle(.window)

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
