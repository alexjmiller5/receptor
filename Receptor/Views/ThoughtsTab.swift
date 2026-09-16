import SwiftUI
import SwiftData

struct ThoughtsTab: View {
    @EnvironmentObject private var syncManager: SyncManager
    @EnvironmentObject private var router: ComposeRouter

    var body: some View {
        NavigationStack {
            ThoughtListView()
                .navigationTitle("Thoughts")
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .topBarLeading) {
                        statusIndicator
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        trailingToolbarContent
                    }
                    #else
                    ToolbarItem(placement: .automatic) {
                        statusIndicator
                    }
                    ToolbarItem(placement: .primaryAction) {
                        trailingToolbarContent
                    }
                    #endif
                }
                .sheet(isPresented: $router.showCompose) {
                    ComposeView()
                }
        }
    }

    private var statusIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: syncManager.isOnline ? "wifi" : "wifi.slash")
                .font(.caption)
                .foregroundStyle(syncManager.isOnline ? .green : .orange)
            Text(syncManager.isOnline ? "Online" : "Offline")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    private var trailingToolbarContent: some View {
        HStack(spacing: 12) {
            if syncManager.isSyncing {
                ProgressView()
                    .scaleEffect(0.8)
            }

            Button {
                router.showCompose = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
        }
    }
}

#Preview {
    ThoughtsTab()
        .modelContainer(for: Thought.self, inMemory: true)
}
