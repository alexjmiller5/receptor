import Foundation
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
