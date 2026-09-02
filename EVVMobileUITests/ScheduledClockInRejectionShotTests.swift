import XCTest

/// Build 57 verification harness for the 2026-09-02 "Clock In on a scheduled
/// card showed 'Clocked in 5:17 PM' for a punch the server REFUSED" incident
/// (Nick, shift 609 / Erik Hoover — server 409 "Already have a visit for this
/// shift" because a soft-deleted visit still counted; a wrong-client C001
/// visit followed).
///
/// ⚠️ NOT referenced by EVVMobile.xcodeproj on purpose (the pbxproj lists
/// test files explicitly). To run it, temporarily copy this file's body over
/// MyDocumentsShotTests.swift (git checkout it afterwards), or add it to the
/// UITests target. Drive it with docs/scheduled-clock-in-driver.js.
///
/// Flow (LIVE backend, demo account S001 / Alex Rivera C001):
///   0. The driver has created ONE scheduled W7061 shift for S001 today (the
///      only Up Next card) AND a completed visit on another shift whose span
///      covers "now" — so the first Clock In MUST be refused 409 staff_overlap
///      by the server. Nothing else on Today for S001.
///   1. Log in → Today → Up Next card "Clock In" → Confirm Clock In.
///      Pre-fix: green "Clocked in h:mm" (Nick's bug) while nothing was saved.
///      Post-fix: inline red refusal, NO "Clocked in", sheet still open.
///      Screenshot + tree → /tmp/sci_1_rejected.{png,txt}. Touch /tmp/sci_stage1_done.
///   2. Wait for /tmp/sci_go (driver deleted the blocking visit).
///   3. Confirm Clock In again → expect "Clocked in", then the Active visit
///      card on Today for Alex Rivera. → /tmp/sci_2_success, /tmp/sci_3_today.
final class ScheduledClockInRejectionShotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func dump(_ app: XCUIApplication, _ name: String) {
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
        try? app.debugDescription.write(toFile: "/tmp/\(name).txt", atomically: true, encoding: .utf8)
    }

    func testScheduledClockInRejectionThenSuccess() throws {
        let app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "System") { alert in
            for name in ["Allow", "Allow While Using App", "Allow Once", "Don't Allow", "OK"] {
                let b = alert.buttons[name]
                if b.exists { b.tap(); return true }
            }
            return false
        }
        app.launch()
        app.tap()

        let emailField = app.textFields["Email"].firstMatch
        if emailField.waitForExistence(timeout: 10) {
            emailField.tap()
            emailField.typeText("demo@focus.com")
            let pw = app.secureTextFields["Password"].firstMatch
            XCTAssertTrue(pw.waitForExistence(timeout: 5))
            pw.tap()
            pw.typeText("DemoEVV2026!")
            app.buttons["Log In"].firstMatch.tap()
        }

        let todayTab = app.tabBars.buttons["Today"]
        XCTAssertTrue(todayTab.waitForExistence(timeout: 20), "tab bar not visible after login")
        sleep(4)
        if !todayTab.isSelected { todayTab.tap(); sleep(2) }
        app.tap() // dismiss any system prompt the monitor handles

        // ── The Up Next card ───────────────────────────────────────────
        let clockIn = app.buttons["Clock In"].firstMatch
        var tries = 0
        while !clockIn.exists && tries < 6 { app.swipeUp(); sleep(1); tries += 1 }
        XCTAssertTrue(clockIn.waitForExistence(timeout: 15), "Up Next 'Clock In' button not found")
        dump(app, "sci_0_today")
        XCTAssertEqual(app.buttons.matching(identifier: "Clock In").count, 1, "expected exactly ONE Up Next card for S001")
        clockIn.tap()
        sleep(2)

        // Confirm sheet: wait for the GPS fix (Confirm is disabled while acquiring)
        let confirm = app.buttons["Confirm Clock In"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "confirm sheet not shown")
        let enabledDeadline = Date().addingTimeInterval(20)
        while Date() < enabledDeadline && !confirm.isEnabled { usleep(250_000) }
        dump(app, "sci_0b_sheet")
        XCTAssertTrue(confirm.isEnabled, "Confirm Clock In never became enabled (GPS?)")

        // ── Attempt 1: server refuses (staff overlap) ──────────────────
        confirm.tap()
        // SwiftUI puts the container's accessibilityIdentifier on the child
        // StaticTexts, and the server's overlap copy reads "…can't overlap…".
        let rejected = app.staticTexts.matching(identifier: "clockInRejected").firstMatch
        let rejectedText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'overlap' OR label CONTAINS 'Already have a visit'")).firstMatch
        let clockedIn = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Clocked in'")).firstMatch
        let deadline = Date().addingTimeInterval(25)
        var sawClockedIn = false
        while Date() < deadline && !rejected.exists && !rejectedText.exists {
            if clockedIn.exists { sawClockedIn = true }
            usleep(200_000)
        }
        dump(app, "sci_1_rejected")
        XCTAssertFalse(sawClockedIn, "BUG: 'Clocked in' rendered for a REFUSED punch (the 2026-09-02 incident)")
        XCTAssertTrue(rejected.exists || rejectedText.exists, "inline refusal not shown")
        XCTAssertFalse(clockedIn.exists, "'Clocked in' must not be showing after a refusal")
        XCTAssertTrue(app.staticTexts["You were NOT clocked in. Nothing was saved."].firstMatch.exists, "explanatory line missing")
        // Sheet stays open: Confirm + Cancel still there
        XCTAssertTrue(app.buttons["Confirm Clock In"].firstMatch.exists, "sheet should remain open after refusal")
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.exists, "sheet chrome should remain")

        try? "done".write(toFile: "/tmp/sci_stage1_done", atomically: true, encoding: .utf8)

        // ── Wait for the driver to delete the blocking visit ───────────
        let goDeadline = Date().addingTimeInterval(120)
        while Date() < goDeadline && !FileManager.default.fileExists(atPath: "/tmp/sci_go") { sleep(1) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: "/tmp/sci_go"), "driver never signalled /tmp/sci_go")

        // ── Attempt 2: same punch, now accepted ────────────────────────
        app.buttons["Confirm Clock In"].firstMatch.tap()
        let ok = clockedIn.waitForExistence(timeout: 25)
        dump(app, "sci_2_success")
        XCTAssertTrue(ok, "'Clocked in' not shown after the server accepted")

        // Back on Today: the Active visit card for Alex Rivera, no Up Next card
        sleep(4)
        dump(app, "sci_3_today")
        let active = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Alex Rivera'")).firstMatch
        XCTAssertTrue(active.waitForExistence(timeout: 10), "Alex Rivera not on Today after clock-in")
        XCTAssertTrue(app.buttons["Clock Out"].firstMatch.waitForExistence(timeout: 10) || app.staticTexts["In Progress"].firstMatch.exists
                      || app.buttons.containing(NSPredicate(format: "label CONTAINS 'Clock Out'")).firstMatch.exists,
                      "no active-visit state on Today")
        XCTAssertFalse(app.buttons["Clock In"].firstMatch.exists, "the Up Next 'Clock In' card must be gone once the visit is running")
        try? "done".write(toFile: "/tmp/sci_stage2_done", atomically: true, encoding: .utf8)
    }
}
