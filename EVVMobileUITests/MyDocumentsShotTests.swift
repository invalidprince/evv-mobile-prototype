import XCTest

/// One-off visual verification for the build-42 My Documents button polish.
/// Logs into the live backend with the demo account, opens Work → My
/// Documents, and saves a screenshot to /tmp via simctl-visible attachment
/// AND a direct file write (attachments are buried in the xcresult).
final class MyDocumentsShotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMyDocumentsScreenshot() throws {
        let app = XCUIApplication()

        addUIInterruptionMonitor(withDescription: "Notifications") { alert in
            let allow = alert.buttons["Allow"]
            if allow.exists { allow.tap(); return true }
            let dont = alert.buttons["Don't Allow"]
            if dont.exists { dont.tap(); return true }
            return false
        }

        app.launch()
        app.tap()

        // ── Login (email + password since v0.4.277) ──────────────
        let emailField = app.textFields["Email"].firstMatch
        if emailField.waitForExistence(timeout: 10) {
            emailField.tap()
            emailField.typeText("demo@focus.com")
            let pw = app.secureTextFields["Password"].firstMatch
            XCTAssertTrue(pw.waitForExistence(timeout: 5), "Password field not found")
            pw.tap()
            pw.typeText("DemoEVV2026!")
            let login = app.buttons["Log In"].firstMatch
            XCTAssertTrue(login.waitForExistence(timeout: 5), "Log In button not found")
            login.tap()
        }
        // else: already logged in from a previous run

        // ── Work tab ─────────────────────────────────────────────
        let workTab = app.tabBars.buttons["Work"]
        XCTAssertTrue(workTab.waitForExistence(timeout: 20), "Work tab not visible after login")
        // The first tap can be consumed by the notification-permission alert's
        // interruption monitor — retry until the tab is actually selected.
        var tabTries = 0
        while !(workTab.isSelected) && tabTries < 5 {
            workTab.tap()
            sleep(2)
            tabTries += 1
        }
        XCTAssertTrue(workTab.isSelected, "Work tab never became selected")

        // ── My Documents ─────────────────────────────────────────
        // NavigationLink rows surface as buttons/cells; may need scrolling.
        sleep(3)
        var myDocs = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'My Documents'")).firstMatch
        if !myDocs.waitForExistence(timeout: 8) {
            myDocs = app.cells.containing(NSPredicate(format: "label CONTAINS[c] 'My Documents'")).firstMatch
        }
        var swipes = 0
        while !myDocs.exists && swipes < 5 {
            app.swipeUp()
            swipes += 1
        }
        if !myDocs.exists {
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/work_debug.png"))
            try? app.debugDescription.write(toFile: "/tmp/work_debug.txt", atomically: true, encoding: .utf8)
        }
        XCTAssertTrue(myDocs.waitForExistence(timeout: 5), "My Documents link not found")
        myDocs.tap()

        // Wait for the slots to load from the live server
        sleep(6)

        let shot = app.screenshot()
        try shot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/mydocs_build42.png"))

        let attachment = XCTAttachment(screenshot: shot)
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
