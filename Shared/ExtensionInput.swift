import Foundation
import UniformTypeIdentifiers

/// What the share sheet handed an extension: the first URL (Safari shares a
/// URL plus its title), else the plain text.
enum ExtensionInput {
    static func text(from context: NSExtensionContext?) async -> String {
        let providers = (context?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []
        for type in [UTType.url, UTType.plainText] {
            for provider in providers where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                if let item = try? await provider.loadItem(forTypeIdentifier: type.identifier) {
                    if let url = item as? URL { return url.absoluteString }
                    if let text = item as? String { return text }
                    if let data = item as? Data, let text = String(data: data, encoding: .utf8) { return text }
                }
            }
        }
        return ""
    }
}
