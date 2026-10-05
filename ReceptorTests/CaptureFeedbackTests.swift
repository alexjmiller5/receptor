import Foundation
import SwiftData
import Testing
@testable import Receptor

@MainActor
@Suite(.serialized)
struct CaptureFeedbackTests {
    @Test func failedSaveDoesNotLeaveAThoughtToBeSavedOnRetry() async throws {
        let manager = SyncManager.shared
        let original = manager.modelContainer
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        do {
            let writable = try ModelContainer(for: Thought.self, SyncLogEntry.self,
                configurations: ModelConfiguration(url: url))
            try writable.mainContext.save()
        }
        let container = try ModelContainer(for: Thought.self, SyncLogEntry.self,
            configurations: ModelConfiguration(url: url, allowsSave: false))
        manager.configure(with: container)
        defer { if let original { manager.configure(with: original) } }
        #expect(await manager.queueThought("failed capture", source: "test") == false)
        #expect(try container.mainContext.fetch(FetchDescriptor<Thought>()).isEmpty)
    }

    @Test func savingAThoughtReturnsOnlyAfterItIsPersisted() async throws {
        let manager = SyncManager.shared
        let original = manager.modelContainer
        let container = try ModelContainer(for: Thought.self, SyncLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        manager.configure(with: container)
        defer { if let original { manager.configure(with: original) } }
        #expect(await manager.queueThought("", source: "test") == false)
        #expect(await manager.queueThought("capture feedback test", source: "test") == true)
        let thoughts = try ModelContext(container).fetch(FetchDescriptor<Thought>())
        #expect(thoughts.count == 1)
        #expect(thoughts.first?.text == "capture feedback test")
        var intent = CaptureThoughtIntent()
        intent.text = " "
        await #expect(throws: (any Error).self) { try await intent.perform() }
    }
}
