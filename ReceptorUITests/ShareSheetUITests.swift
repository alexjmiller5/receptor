import XCTest

/// Drives the real share sheet in Safari and screenshots every step, so the
/// share actions are looked at on a simulator before they reach a phone.
/// Screenshots and hierarchy dumps land in SHOTS_DIR (host path).
final class ShareSheetUITests: XCTestCase {
    private let shots = ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? "/tmp/receptor-shots"
    private let action = ProcessInfo.processInfo.environment["SHARE_ACTION"] ?? "Receptor 📥"
    private let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
    }

    private func snap(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
    }

    private func dump(_ name: String, _ app: XCUIApplication) {
        try? app.debugDescription.write(toFile: "\(shots)/\(name).txt", atomically: true, encoding: .utf8)
    }

    /// Banners need the app's notification permission; grant it the way a
    /// person would, on the first launch.
    private func grantNotifications() {
        let app = XCUIApplication()
        app.launch()
        let allow = springboard.buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        app.open(URL(string: "receptor://enroll?url=http%3A%2F%2F127.0.0.1%3A8799%2F&token=sim-token")!)
        sleep(2)
        snap("00-app")
    }

    func testSettingsScreen() {
        let app = XCUIApplication()
        app.launch()
        let allow = springboard.buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        app.tabBars.buttons["Settings"].firstMatch.tap()
        sleep(1)
        snap("10-settings")
        XCTAssertTrue(app.staticTexts["Notifications are only used for failed captures"].exists)
    }

    func testShareAction() {
        grantNotifications()
        safari.activate()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 20))
        sleep(3)
        snap("01-safari")
        dump("01-safari", safari)

        let share = safari.buttons["ShareButton"].firstMatch
        if share.waitForExistence(timeout: 5) {
            share.tap()
        } else {
            // Newer Safari tucks Share into the page menu.
            let more = safari.buttons["MoreMenuButton"].firstMatch
            if more.waitForExistence(timeout: 3) { more.tap() }
            let item = safari.buttons["Share"].firstMatch
            if item.waitForExistence(timeout: 3) { item.tap() }
        }
        sleep(2)
        snap("02-share-sheet")
        dump("02-share-sheet-safari", safari)
        dump("02-share-sheet-springboard", springboard)

        // The actions list scrolls; look for our action while swiping up.
        var target = safari.descendants(matching: .any).matching(NSPredicate(format: "label == %@", action)).firstMatch
        var tries = 0
        while !target.exists && tries < 6 {
            safari.swipeUp()
            tries += 1
            target = safari.descendants(matching: .any).matching(NSPredicate(format: "label == %@", action)).firstMatch
        }
        snap("03-actions-list")
        dump("03-actions-list", safari)
        guard target.exists else {
            XCTFail("share action \(action) not found in the share sheet")
            return
        }
        target.tap()
        // An action with its own screen (the context prompt): fill it in.
        let field = safari.textFields["Context"].firstMatch
        if action == "Receptor 📤 💭" {
            dump("04-context-tree", safari)
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            snap("04-context-prompt")
            field.tap()
            field.typeText("from the ui test")
            snap("04-context-typed")
            safari.buttons["Done"].firstMatch.tap()
        }
        // Successful captures must not post a system banner.
        XCTAssertFalse(springboard.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "✓")).firstMatch.waitForExistence(timeout: 3))
        sleep(6)
        snap("05-settled")
    }
}
