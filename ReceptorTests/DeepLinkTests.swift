import Foundation
import Testing
@testable import Receptor

struct DeepLinkTests {
    @Test func composeWithoutSource() {
        #expect(DeepLink.parse(URL(string: "receptor://compose")!) == .compose(source: nil))
    }

    @Test func composeCarriesItsSource() {
        #expect(DeepLink.parse(URL(string: "receptor://compose?source=hammerspoon-compose")!) == .compose(source: "hammerspoon-compose"))
    }

    @Test func emptySourceIsNoSource() {
        #expect(DeepLink.parse(URL(string: "receptor://compose?source=")!) == .compose(source: nil))
    }

    @Test func receptKeepsTextAndSource() {
        #expect(DeepLink.parse(DeepLink.receptURL(text: "a & b $ c", source: "agent")) == .recept(text: "a & b $ c", source: "agent"))
    }

    @Test func receptWithoutTextIsRejected() {
        #expect(DeepLink.parse(URL(string: "receptor://recept?source=agent")!) == nil)
    }

}
