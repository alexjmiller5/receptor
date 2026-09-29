import SwiftUI
import UIKit

/// The confirmation every share-sheet action ends with: a pill at the top of
/// the screen (where the Shortcuts checkmark used to appear) that says what
/// happened, shows the text, and goes away on its own.
struct CaptureHUD: View {
    let outcome: ShareCapture.Outcome
    let text: String
    @State private var shown = false

    private var symbol: String {
        switch outcome {
        case .sent: "checkmark.circle.fill"
        case .queued: "clock.fill"
        case .rejected: "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch outcome {
        case .sent: .green
        case .queued: .orange
        case .rejected: .red
        }
    }

    private var title: String {
        switch outcome {
        case .sent: "Sent to Receptor"
        case .queued: "Queued - sends on the next sync"
        case .rejected(let code): "Rejected (HTTP \(code))"
        }
    }

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .scaleEffect(shown ? 1 : 0.85)
            .opacity(shown ? 1 : 0)
            Spacer()
        }
        .onAppear { withAnimation(.spring(duration: 0.3)) { shown = true } }
    }
}

/// Base for the share-sheet actions: a transparent screen that runs one
/// capture, shows the HUD, and finishes the request. Subclasses only say what
/// text to send and under which source.
class CaptureViewController: UIViewController {
    /// How long the confirmation stays before the extension closes.
    static let hudDuration: Duration = .milliseconds(1300)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    @MainActor
    func capture(_ text: String, source: String) async {
        do {
            let outcome = try await ShareCapture.capture(text: text, source: source, container: try ShareCapture.makeContainer())
            showHUD(outcome, text: text)
            try? await Task.sleep(for: Self.hudDuration)
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            extensionContext?.cancelRequest(withError: error)
        }
    }

    private func showHUD(_ outcome: ShareCapture.Outcome, text: String) {
        children.forEach { $0.view.isHidden = true }
        let host = UIHostingController(rootView: CaptureHUD(outcome: outcome, text: text))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}
