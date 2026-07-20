import XCTest

/// End-to-end server-mode test: logs into the live EVV PoC backend as the
/// staff member given by the EVV_TEST_EMAIL env var, verifies the 2:1 shift
/// renders with the partner's name, clocks in, verifies active state, and
/// (if EVV_TEST_CLOCKOUT=1) clocks back out.
final class ServerModeE2ETests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testServerLoginAndTwoToOneShift() throws {
        let email = ProcessInfo.processInfo.environment["EVV_TEST_EMAIL"] ?? "mgonzalez@fbhi.net"
        let partnerName = ProcessInfo.processInfo.environment["EVV_TEST_PARTNER"] ?? ""
        let doClockOut = ProcessInfo.processInfo.environment["EVV_TEST_CLOCKOUT"] == "1"

        let app = XCUIApplication()
        app.launchEnvironment["EVV_UITEST"] = "1"

        // Auto-dismiss the notification permission alert
        addUIInterruptionMonitor(withDescription: "Notifications") { alert in
            let allow = alert.buttons["Allow"]
            if allow.exists { allow.tap(); return true }
            return false
        }

        app.launch()
        app.tap() // trigger interruption monitor if alert is up

        // ── Login ────────────────────────────────────────────────
        let signInEmail = app.buttons["Sign in with Email"].firstMatch
        if !signInEmail.waitForExistence(timeout: 10) {
            app.tap() // one more nudge for the alert
        }
        XCTAssertTrue(signInEmail.waitForExistence(timeout: 10), "Sign in with Email button not found")
        signInEmail.tap()

        let emailField = app.textFields.matching(
            NSPredicate(format: "placeholderValue CONTAINS[c] 'Email'")
        ).firstMatch
        XCTAssertTrue(emailField.waitForExistence(timeout: 5), "Email field not found")
        emailField.tap()
        emailField.typeText(email)

        let signIn = app.buttons["Sign In"].firstMatch
        XCTAssertTrue(signIn.waitForExistence(timeout: 5), "Sign In button not found")
        signIn.tap()

        // ── Today view: 2:1 shift with partner ───────────────────
        let ratioBadge = app.staticTexts["2:1"].firstMatch
        XCTAssertTrue(ratioBadge.waitForExistence(timeout: 20), "2:1 badge not visible after login")

        if !partnerName.isEmpty {
            let partnerText = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", partnerName)
            ).firstMatch
            XCTAssertTrue(partnerText.waitForExistence(timeout: 5),
                          "Partner name \(partnerName) not shown on shift")
        }

        // ── Clock in ─────────────────────────────────────────────
        // The 2:1 shift may not be first; scroll to a Clock In button.
        let clockIn = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Clock In'")
        ).firstMatch
        if clockIn.waitForExistence(timeout: 5) {
            clockIn.tap()

            let confirm = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'Confirm Clock In'")
            ).firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 8), "Confirm Clock In not found")
            confirm.tap()

            // Success view or active card: look for CLOCKED IN badge
            let active = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'CLOCKED IN'")
            ).firstMatch
            // Success screen may need dismissal first
            let done = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'Done' OR label CONTAINS[c] 'Start'")
            ).firstMatch
            if done.waitForExistence(timeout: 6) { done.tap() }
            XCTAssertTrue(active.waitForExistence(timeout: 15), "CLOCKED IN state not visible")
        } else {
            // Already clocked in from a previous run — assert active card instead
            let active = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'CLOCKED IN'")
            ).firstMatch
            XCTAssertTrue(active.waitForExistence(timeout: 10),
                          "Neither Clock In button nor CLOCKED IN state found")
        }

        // ── Optional clock out ───────────────────────────────────
        if doClockOut {
            let clockOut = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'Clock Out'")
            ).firstMatch
            XCTAssertTrue(clockOut.waitForExistence(timeout: 8), "Clock Out button not found")
            clockOut.tap()
            // Walk any clock-out flow: tap prominent continue/confirm buttons
            for label in ["Continue", "Confirm", "Submit", "Finish", "Done", "Skip"] {
                let btn = app.buttons.matching(
                    NSPredicate(format: "label CONTAINS[c] %@", label)
                ).firstMatch
                if btn.waitForExistence(timeout: 3) { btn.tap() }
            }
        }

        // Screenshot for evidence
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
