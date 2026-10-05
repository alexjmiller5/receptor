import AppIntents
import SwiftUI
import WidgetKit

@main
struct ReceptorWidgets: WidgetBundle {
    var body: some Widget {
        CaptureThoughtControl()
    }
}

struct CaptureThoughtControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.alexmiller.receptor.capture-thought") {
            ControlWidgetButton(action: captureIntent) {
                Label("Recept", systemImage: "brain.head.profile")
            }
        }
        .displayName("Capture Thought")
        .description("Capture a thought with Receptor.")
    }

    private var captureIntent: CaptureThoughtIntent {
        let intent = CaptureThoughtIntent()
        intent.source = "native-control"
        return intent
    }
}
