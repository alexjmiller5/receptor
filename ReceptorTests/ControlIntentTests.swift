import AppIntents
import Testing
@testable import Receptor

struct ControlIntentTests {
    @Test func captureRunsInContainingApp() {
        #expect(CaptureThoughtIntent() is any LiveActivityIntent)
    }
}
