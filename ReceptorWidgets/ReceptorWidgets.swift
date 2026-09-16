import WidgetKit
import SwiftUI
import AppIntents

@main
struct ReceptorWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ReceptorLockWidget()
        ReceptorControl()
    }
}

// MARK: - Lock Screen widget (tap = new thought)

struct ReceptorEntry: TimelineEntry {
    let date: Date
}

struct ReceptorProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReceptorEntry { ReceptorEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (ReceptorEntry) -> Void) {
        completion(ReceptorEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ReceptorEntry>) -> Void) {
        completion(Timeline(entries: [ReceptorEntry(date: .now)], policy: .never))
    }
}

struct ReceptorLockWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label("Recept", systemImage: "brain.head.profile")
            case .accessoryRectangular:
                HStack {
                    Image(systemName: "brain.head.profile").font(.title2)
                    VStack(alignment: .leading) {
                        Text("Recept").font(.headline)
                        Text("New thought").font(.caption).foregroundStyle(.secondary)
                    }
                }
            default:
                Image(systemName: "brain.head.profile")
                    .font(.title)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(DeepLink.composeURL)
    }
}

struct ReceptorLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ReceptorLockWidget", provider: ReceptorProvider()) { _ in
            ReceptorLockWidgetView()
        }
        .configurationDisplayName("Recept")
        .description("Capture a thought.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Control Center button

struct ReceptorControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ReceptorControl") {
            ControlWidgetButton(action: OpenComposeIntent()) {
                Label("Recept", systemImage: "brain.head.profile")
            }
        }
        .displayName("Recept")
        .description("Capture a thought in Receptor")
    }
}
