import SwiftUI
import SwiftData

struct ThoughtListView: View {
    @EnvironmentObject private var syncManager: SyncManager
    @Query(sort: \Thought.createdAt, order: .reverse) private var thoughts: [Thought]

    var body: some View {
        Group {
            if thoughts.isEmpty {
                ContentUnavailableView(
                    "No Thoughts Yet",
                    systemImage: "brain.head.profile",
                    description: Text("Capture your first thought using the + button or via Shortcuts")
                )
            } else {
                List {
                    ForEach(thoughts) { thought in
                        ThoughtRow(thought: thought)
                            .swipeActions(edge: .leading) {
                                if thought.status == .failed {
                                    Button {
                                        thought.status = .queued
                                        syncManager.requestFlush(trigger: .manualRetry)
                                    } label: {
                                        Label("Retry", systemImage: "arrow.clockwise")
                                    }
                                    .tint(.blue)
                                }
                            }
                    }
                }
            }
        }
    }
}

struct ThoughtRow: View {
    let thought: Thought

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium  // Includes seconds
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(thought.text)
                .font(.body)
                .lineLimit(3)

            HStack {
                StatusBadge(status: thought.status)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Created: \(timeFormatter.string(from: thought.createdAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let sentAt = thought.sentAt {
                        HStack(spacing: 4) {
                            Text("Sent: \(timeFormatter.string(from: sentAt))")
                            if let sentVia = thought.sentVia {
                                Text("(\(sentVia.rawValue))")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.green)
                    }
                }
            }

            if let error = thought.lastError, thought.status == .failed {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

struct StatusBadge: View {
    let status: ThoughtStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption2)
            Text(status.rawValue.capitalized)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor.opacity(0.15))
        .foregroundStyle(backgroundColor)
        .clipShape(Capsule())
    }

    private var iconName: String {
        switch status {
        case .queued: "clock"
        case .sending: "arrow.up.circle"
        case .sent: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .queued: .orange
        case .sending: .blue
        case .sent: .green
        case .failed: .red
        }
    }
}

#Preview {
    ThoughtListView()
        .modelContainer(for: Thought.self, inMemory: true)
}
