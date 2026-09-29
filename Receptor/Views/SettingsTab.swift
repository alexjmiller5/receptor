import SwiftUI
import SwiftData
#if os(iOS)
import UniformTypeIdentifiers
import UserNotifications
#endif

/// Wrapper to make URL work with .sheet(item:)
struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct SettingsTab: View {
    @EnvironmentObject private var syncManager: SyncManager
    @State private var intakerURL: String = Configuration.intakerURL?.absoluteString ?? ""
    @State private var apiKey: String = Configuration.apiKey ?? ""
    @State private var proxySecret: String = Configuration.proxySecret ?? ""
    @Query private var thoughts: [Thought]
    @State private var exportItem: ExportItem?

    private var queuedCount: Int {
        thoughts.filter { $0.status == .queued || $0.status == .sending }.count
    }

    private var failedCount: Int {
        thoughts.filter { $0.status == .failed }.count
    }

    private var sentCount: Int {
        thoughts.filter { $0.status == .sent }.count
    }

    var body: some View {
        #if os(macOS)
        macOSSettings
        #else
        iOSSettings
        #endif
    }

    #if os(iOS)
    private var iOSSettings: some View {
        NavigationStack {
            Form {
                confirmationsSection
                shareDefaultsSection
                connectionSection
                requestFormatSection
                queueStatisticsSection
                syncLogSection
            }
            .navigationTitle("Settings")
            .scrollDismissesKeyboard(.interactively)
            .sheet(item: $exportItem) { item in
                ShareSheet(activityItems: [item.url])
            }
        }
    }
    #endif

    #if os(macOS)
    private var macOSSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Startup
                VStack(alignment: .leading, spacing: 8) {
                    Text("Startup")
                        .font(.headline)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start at Login")
                            Text("Keep Synapse running in the menu bar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { LoginItemManager.shared.isEnabled },
                            set: { LoginItemManager.shared.setEnabled($0) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                    }
                }

                Divider()

                // Connection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connection")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Intaker URL")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("https://your-workspace--synapse-webhook.modal.run", text: $intakerURL)
                            .textFieldStyle(.plain)
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                            .onChange(of: intakerURL) { _, newValue in
                                if let url = Configuration.validIntakerURL(newValue) {
                                    Configuration.intakerURL = url
                                }
                            }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Modal-Key (proxy token ID)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        SecureField("Enter your Modal proxy token ID", text: $apiKey)
                            .textFieldStyle(.plain)
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                            .onChange(of: apiKey) { _, newValue in
                                Configuration.apiKey = newValue.isEmpty ? nil : newValue
                            }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Modal-Secret (proxy token secret)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        SecureField("Enter your Modal proxy token secret", text: $proxySecret)
                            .textFieldStyle(.plain)
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                            .onChange(of: proxySecret) { _, newValue in
                                Configuration.proxySecret = newValue.isEmpty ? nil : newValue
                            }
                    }

                    if Configuration.isConfigured {
                        Label("Configured", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        Label("Enter URL and API key to enable syncing", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }

                Divider()

                // Queue Statistics
                VStack(alignment: .leading, spacing: 12) {
                    Text("Queue Statistics")
                        .font(.headline)

                    HStack(spacing: 32) {
                        VStack(spacing: 4) {
                            Text("\(queuedCount)")
                                .font(.title2.monospacedDigit())
                                .fontWeight(.medium)
                                .foregroundStyle(queuedCount > 0 ? .orange : .secondary)
                            Text("Queued")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        VStack(spacing: 4) {
                            Text("\(failedCount)")
                                .font(.title2.monospacedDigit())
                                .fontWeight(.medium)
                                .foregroundStyle(failedCount > 0 ? .red : .secondary)
                            Text("Failed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        VStack(spacing: 4) {
                            Text("\(sentCount)")
                                .font(.title2.monospacedDigit())
                                .fontWeight(.medium)
                                .foregroundStyle(.green)
                            Text("Sent")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                // Sync Log
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Sync Log")
                            .font(.headline)
                        Spacer()
                        if !syncManager.syncLog.isEmpty {
                            Button("Export") {
                                exportLogsForMacOS()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                            .font(.caption)
                        }
                    }

                    if syncManager.syncLog.isEmpty {
                        Text("No sync events yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(syncManager.syncLog.prefix(20)) { entry in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.message)
                                        .font(.caption)
                                        .lineLimit(1)
                                    HStack {
                                        Text(entry.trigger.rawValue)
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                        Spacer()
                                        Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private func exportLogsForMacOS() {
        Task.detached {
            guard let url = await syncManager.exportLogs() else { return }

            await MainActor.run {
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.plainText]
                savePanel.nameFieldStringValue = "receptor.log"
                savePanel.canCreateDirectories = true

                savePanel.begin { response in
                    if response == .OK, let targetURL = savePanel.url {
                        try? FileManager.default.copyItem(at: url, to: targetURL)
                    }
                }
            }
        }
    }
    #endif

    // iOS sections
    #if os(iOS)
    @State private var domainContexts = Configuration.domainContexts
    @State private var newDomain = ""
    @State private var newContext = ""

    @State private var catchAllContext = Configuration.domainContexts[Configuration.catchAllDomain] ?? ""
    @State private var bannersEnabled = true

    /// Every capture outside the app confirms with a notification banner;
    /// say so plainly when iOS will not show one.
    @ViewBuilder
    private var confirmationsSection: some View {
        Section {
            if bannersEnabled {
                Label("Banners confirm each capture", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Notifications are off, so captures cannot confirm", systemImage: "bell.slash.fill")
                    .foregroundStyle(.orange)
                Button("Open Notification Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        } header: {
            Text("Confirmations")
        }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            bannersEnabled = settings.authorizationStatus == .authorized && settings.alertSetting == .enabled
        }
    }

    private var shareDefaultsSection: some View {
        Section {
            TextField("All other links", text: $catchAllContext)
                .autocorrectionDisabled()
                .onChange(of: catchAllContext) { _, value in
                    let v = value.trimmingCharacters(in: .whitespaces)
                    if v.isEmpty { domainContexts.removeValue(forKey: Configuration.catchAllDomain) } else { domainContexts[Configuration.catchAllDomain] = v }
                    Configuration.domainContexts = domainContexts
                }
            ForEach(domainContexts.keys.filter { $0 != Configuration.catchAllDomain }.sorted(), id: \.self) { domain in
                LabeledContent(domain) { Text(domainContexts[domain] ?? "").foregroundStyle(.secondary) }
            }
            .onDelete { offsets in
                let keys = domainContexts.keys.filter { $0 != Configuration.catchAllDomain }.sorted()
                for i in offsets { domainContexts.removeValue(forKey: keys[i]) }
                Configuration.domainContexts = domainContexts
            }
            HStack {
                TextField("maps.app.goo.gl", text: $newDomain)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("context", text: $newContext)
                    .autocorrectionDisabled()
                Button {
                    let d = newDomain.trimmingCharacters(in: .whitespaces).lowercased()
                    let c = newContext.trimmingCharacters(in: .whitespaces)
                    guard !d.isEmpty, !c.isEmpty else { return }
                    domainContexts[d] = c
                    Configuration.domainContexts = domainContexts
                    newDomain = ""; newContext = ""
                } label: { Image(systemName: "plus.circle.fill") }
                .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty || newContext.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Pre-filled Receptor")
        } footer: {
            Text("\"Pre-filled Receptor\" in the share sheet appends the context for the matching site, else the one for all other links (sent as \"link $ context\"). Leave both empty and it sends as-is.")
        }
    }
    #endif

    private var connectionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Intaker URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://your-workspace--synapse-webhook.modal.run", text: $intakerURL)
                    #if os(iOS)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: intakerURL) { _, newValue in
                        if let url = Configuration.validIntakerURL(newValue) {
                            Configuration.intakerURL = url
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Modal-Key (proxy token ID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("Enter your Modal proxy token ID", text: $apiKey)
                    #if os(iOS)
                    .textContentType(.password)
                    #endif
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: apiKey) { _, newValue in
                        Configuration.apiKey = newValue.isEmpty ? nil : newValue
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Modal-Secret (proxy token secret)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("Enter your Modal proxy token secret", text: $proxySecret)
                    #if os(iOS)
                    .textContentType(.password)
                    #endif
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: proxySecret) { _, newValue in
                        Configuration.proxySecret = newValue.isEmpty ? nil : newValue
                    }
            }
        } header: {
            Text("Connection")
        } footer: {
            if Configuration.isConfigured {
                Label("Configured", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Label("Enter URL and both Modal proxy token values to enable syncing", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
    }

    private var requestFormatSection: some View {
        Section("Request Format") {
            VStack(alignment: .leading, spacing: 4) {
                Text("POST {url}")
                    .font(.system(.caption, design: .monospaced))
                Text("Modal-Key: {token id} · Modal-Secret: {token secret}")
                    .font(.system(.caption, design: .monospaced))
                Text("Content-Type: application/json")
                    .font(.system(.caption, design: .monospaced))
                Text("{\"raw_text\": \"your thought\"}")
                    .font(.system(.caption, design: .monospaced))
            }
            .foregroundStyle(.secondary)
        }
    }

    private var queueStatisticsSection: some View {
        Section("Queue Statistics") {
            LabeledContent("Queued") {
                Text("\(queuedCount)")
                    .foregroundStyle(queuedCount > 0 ? .orange : .secondary)
            }
            LabeledContent("Failed") {
                Text("\(failedCount)")
                    .foregroundStyle(failedCount > 0 ? .red : .secondary)
            }
            LabeledContent("Sent") {
                Text("\(sentCount)")
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private var syncLogSection: some View {
        Section("Sync Log") {
            if syncManager.syncLog.isEmpty {
                Text("No sync events yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(syncManager.syncLog.prefix(20)) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.message)
                            .font(.caption)
                        HStack {
                            Text(entry.trigger.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.blue)
                            Spacer()
                            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }

        if !syncManager.syncLog.isEmpty {
            Section {
                HStack {
                    Spacer()
                    exportLogButton
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 32, trailing: 0))
            }
        }
    }

    private var exportLogButton: some View {
        Button {
            Task {
                if let url = await syncManager.exportLogs() {
                    exportItem = ExportItem(url: url)
                }
            }
        } label: {
            Label("Export Log", systemImage: "square.and.arrow.up")
                .foregroundStyle(.primary)
                .font(.body.weight(.medium))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .modifier(GlassButtonModifier())
    }
}

struct GlassButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .background(.thinMaterial, in: Capsule())
        }
        #else
        content
            .background(.quaternary, in: Capsule())
        #endif
    }
}

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

#Preview {
    SettingsTab()
        .modelContainer(for: Thought.self, inMemory: true)
}
