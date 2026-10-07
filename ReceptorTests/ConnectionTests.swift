import Foundation
import SwiftData
import Testing
@testable import Receptor

struct EnrollLinkTests {
    private func link(_ query: String) -> DeepLink? {
        DeepLink.parse(URL(string: "receptor://enroll?\(query)")!)
    }

    @Test func carriesTheCaptureURLAndToken() {
        #expect(link("url=https%3A%2F%2Fws--synapse-capture.modal.run&token=abc_DEF-123")
                == .enroll(url: URL(string: "https://ws--synapse-capture.modal.run")!, token: "abc_DEF-123"))
    }

    @Test(arguments: [
        "url=https%3A%2F%2Fws.modal.run",                 // no token
        "url=https%3A%2F%2Fws.modal.run&token=",          // empty token
        "url=ftp%3A%2F%2Fws.modal.run&token=abc",         // not http(s)
        "url=&token=abc",                                 // no url
        "url=https%3A%2F%2Fws.modal.run&token=a%20b",     // whitespace in token
    ])
    func rejectsIncompleteLinks(query: String) {
        #expect(link(query) == nil)
    }

    @Test func rejectsAnOverlongToken() {
        #expect(link("url=https%3A%2F%2Fws.modal.run&token=\(String(repeating: "a", count: 513))") == nil)
    }
}

struct HTTPOutcomeTests {
    @Test(arguments: [(200, ThoughtStatus.sent), (202, .sent), (401, .failed), (403, .failed),
                      (422, .rejected), (404, .rejected), (500, .failed), (503, .failed)])
    func classifiesTheReply(code: Int, expected: ThoughtStatus) {
        #expect(ThoughtStatus.after(httpStatus: code) == expected)
    }
}

struct TokenStoreTests {
    @Test func savesReplacesAndDeletes() {
        let store = TokenStore(service: "com.alexmiller.receptor.tests.\(UUID().uuidString)")
        #expect(store.load() == nil)
        #expect(store.save("first"))
        #expect(store.load() == "first")
        #expect(store.save("second"))
        #expect(store.load() == "second")
        store.delete()
        #expect(store.load() == nil)
    }
}

struct LegacyCredentialTests {
    @Test func purgeRemovesTheOldModalProxyCredentials() throws {
        let defaults = try #require(Configuration.sharedDefaults)
        defaults.set("old-key", forKey: "receptor_api_key")
        defaults.set("old-secret", forKey: "receptor_proxy_secret")
        Configuration.purgeLegacyCredentials()
        #expect(defaults.string(forKey: "receptor_api_key") == nil)
        #expect(defaults.string(forKey: "receptor_proxy_secret") == nil)
    }
}

struct DisconnectTests {
    @Test func disconnectForgetsTheURLAndToken() {
        Configuration.enroll(url: URL(string: "https://ws--synapse-capture.modal.run")!, token: "test-token")
        #expect(Configuration.isConfigured)
        #expect(Configuration.connectedHost == "ws--synapse-capture.modal.run")
        Configuration.disconnect()
        #expect(!Configuration.isConfigured)
        #expect(Configuration.connectedHost == nil)
        #expect(Configuration.captureToken == nil)
    }
}

struct CaptureIdentityTests {
    @Test func retriesEncodeTheSavedIdentityWithoutRegeneratingIt() throws {
        let thought = Thought(text: "Synthetic capture", source: "test-client")
        let identity = thought.id.uuidString.lowercased()
        let first = try JSONSerialization.jsonObject(with: JSONEncoder().encode(thought.uploadPayload)) as? [String: String]
        thought.status = .failed
        thought.retryCount += 1
        let retry = try JSONSerialization.jsonObject(with: JSONEncoder().encode(thought.uploadPayload)) as? [String: String]
        #expect(first?["capture_id"] == identity)
        #expect(retry == first)
        #expect(first?["source"] == "test-client")
        #expect(first?["raw_text"] == "Synthetic capture")
    }

    @Test func identicalTextSubmissionsHaveDifferentCaptureIdentities() {
        let first = Thought(text: "Same text")
        let second = Thought(text: "Same text")
        #expect(first.uploadPayload["capture_id"] != nil)
        #expect(first.uploadPayload["capture_id"] != second.uploadPayload["capture_id"])
    }
}


struct PersistedCaptureIdentityTests {
    @Test func reopeningTheStorePreservesTheUploadIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("capture.store")
        let schema = Schema([Thought.self, SyncLogEntry.self])
        var saved: UUID?
        do {
            let container = try ModelContainer(for: schema,
                configurations: [ModelConfiguration(url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let thought = Thought(text: "Synthetic retry", source: "test-client")
            context.insert(thought)
            try context.save()
            saved = thought.id
        }
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(url: url, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let thought = try #require(context.fetch(FetchDescriptor<Thought>()).first)
        thought.status = .failed
        thought.retryCount += 1
        try context.save()
        #expect(thought.id == saved)
        #expect(thought.uploadPayload["capture_id"] == saved?.uuidString.lowercased())
    }
}
