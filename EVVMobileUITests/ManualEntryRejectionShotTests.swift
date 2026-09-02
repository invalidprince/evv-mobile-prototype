import XCTest

/// Build 54/55 reproduction/verification harness for the 2026-09-02 "unscheduled
/// manual-time visit silently lost" incident.
///
/// ⚠️ NOT referenced by EVVMobile.xcodeproj on purpose (the pbxproj lists
/// test files explicitly). To run it, temporarily copy this file's body over
/// MyDocumentsShotTests.swift (git checkout it afterwards), or add it to the
/// UITests target.
///
/// Flow (LIVE backend, demo account S001 / Alex Rivera C001, W8593 is a
/// non-EVV manual-time service for that pair):
///   0. The driver has ALREADY created a manual W8593 visit for S001 covering
///      the app's default manual span (now-1h → now) — so the first attempt
///      MUST be refused 409 staff_overlap by the server.
///   1. Log in → Today → Start Unscheduled Visit → Alex Rivera → Record Time.
///      Pre-fix: green "Time recorded" then the row vanished (Nick's bug).
///      Post-fix: inline "That time overlaps visit V-…" and NO "Time recorded".
///      Screenshot + tree → /tmp/uml_1_rejected.{png,txt}. Touch /tmp/uml_stage1_done.
///   2. Wait for /tmp/uml_go (driver deleted the blocking visit).
///   3. Record Time again → expect "Time recorded", then the row on Today.
///      Screenshot + tree → /tmp/uml_2_success.{png,txt}, /tmp/uml_3_today.{png,txt}.
final class ManualEntryRejectionShotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func dump(_ app: XCUIApplication, _ name: String) {
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
        try? app.debugDescription.write(toFile: "/tmp/\(name).txt", atomically: true, encoding: .utf8)
    }

    func testManualEntryRejectionThenSuccess() throws {
        let app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "Notifications") { alert in
            for name in ["Allow", "Allow While Using App", "Don't Allow"] {
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

        // Open the unscheduled sheet (may need to scroll the Today list down)
        let startBtn = app.buttons["Start Unscheduled Visit"].firstMatch
        var tries = 0
        while !startBtn.exists && tries < 6 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(startBtn.waitForExistence(timeout: 10), "Start Unscheduled Visit not found")
        startBtn.tap()
        sleep(3)

        // Select Alex Rivera (C001)
        let alex = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Alex Rivera'")).firstMatch
        XCTAssertTrue(alex.waitForExistence(timeout: 10), "Alex Rivera row not found")
        alex.tap()
        sleep(1)

        // Make sure the Life Sharing (non-EVV) service is selected
        // (inline Picker rows are Buttons; the auto-selected first option is
        // "Companion (1:1)" by sort order, so tap the Life Sharing row)
        let ls = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'IDD Life Sharing'")).firstMatch
        XCTAssertTrue(ls.waitForExistence(timeout: 5), "Life Sharing service row not found")
        if !ls.isHittable { app.swipeUp() }
        ls.tap()
        sleep(1)
        dump(app, "uml_0_form")

        // The manual-time section must be showing (this IS the manual path).
        // Form cells below the fold are not materialized until scrolled.
        app.swipeUp(); sleep(1); app.swipeUp(); sleep(1)
        let visitTimes = app.staticTexts["Visit Times"].firstMatch
        XCTAssertTrue(visitTimes.waitForExistence(timeout: 5), "manual-time section not shown — wrong service selected?")
        dump(app, "uml_0b_times")

        // Build 55: both boxes open at 12:00 AM and the hint reads a full day.
        let dayHint = app.staticTexts["24h 0m — spans midnight"].firstMatch
        XCTAssertTrue(dayHint.waitForExistence(timeout: 5), "12:00 AM → 12:00 AM default hint not shown")

        // ── Attempt 1: server refuses (overlap) ────────────────────────
        let record = app.buttons["Record Time"].firstMatch
        var rt = 0
        while !record.exists && rt < 4 { app.swipeUp(); sleep(1); rt += 1 }
        XCTAssertTrue(record.waitForExistence(timeout: 5), "Record Time button not found")
        record.tap()
        // Untouched midnight placeholder → the desktop-mirroring confirm.
        let save = app.alerts.buttons["Save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5), "12:00 AM placeholder confirm not shown")
        dump(app, "uml_0c_confirm")
        save.tap()

        let rejected = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'overlaps visit'")).firstMatch
        let recorded = app.staticTexts["Time recorded"].firstMatch
        let deadline = Date().addingTimeInterval(20)
        var sawRecorded = false
        while Date() < deadline && !rejected.exists {
            if recorded.exists { sawRecorded = true }
            usleep(200_000)
        }
        dump(app, "uml_1_rejected")
        XCTAssertFalse(sawRecorded, "BUG: 'Time recorded' rendered for a refused entry")
        XCTAssertTrue(rejected.exists, "inline overlap refusal not shown")
        XCTAssertFalse(recorded.exists, "'Time recorded' must not be showing after a refusal")
        // The sheet is still open with the form (staff can adjust and retry)
        var rt2 = 0
        while !app.buttons["Record Time"].firstMatch.exists && rt2 < 4 { app.swipeUp(); sleep(1); rt2 += 1 }
        XCTAssertTrue(app.buttons["Record Time"].firstMatch.exists, "sheet should remain open after refusal")
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.exists, "sheet chrome should remain")

        try? "done".write(toFile: "/tmp/uml_stage1_done", atomically: true, encoding: .utf8)

        // ── Wait for the driver to delete the blocking visit ───────────
        let goDeadline = Date().addingTimeInterval(90)
        while Date() < goDeadline && !FileManager.default.fileExists(atPath: "/tmp/uml_go") { sleep(1) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: "/tmp/uml_go"), "driver never signalled /tmp/uml_go")

        // ── Attempt 2: same entry, now accepted ────────────────────────
        app.buttons["Record Time"].firstMatch.tap()
        let save2 = app.alerts.buttons["Save"].firstMatch
        if save2.waitForExistence(timeout: 5) { save2.tap() }
        let ok = recorded.waitForExistence(timeout: 20)
        dump(app, "uml_2_success")
        XCTAssertTrue(ok, "'Time recorded' not shown after the server accepted")
        sleep(4) // success cover auto-dismisses after 1.4s, sheet closes
        dump(app, "uml_3_today")
        let row = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Alex Rivera'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "recorded visit not on Today")
        try? "done".write(toFile: "/tmp/uml_stage2_done", atomically: true, encoding: .utf8)
    }
}
