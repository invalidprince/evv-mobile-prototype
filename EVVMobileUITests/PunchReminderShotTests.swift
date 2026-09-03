import XCTest

/// Build 60/61 verification harness for the LOCAL missed-punch reminders
/// (PunchReminderCenter; Todoist 6hQfcR8RVvmvqFcq).
///
/// ⚠️ NOT referenced by EVVMobile.xcodeproj on purpose (the pbxproj lists test
/// files explicitly). To run it, temporarily copy this file's body over
/// MyDocumentsShotTests.swift (git checkout it afterwards). Drive it with
/// docs/punch-reminder-driver.js, and watch the phone's decisions with
///   xcrun simctl spawn <sim> log stream --predicate 'eventMessage CONTAINS "[punch-reminders]"'
///
/// Flow (LIVE backend, demo account S001 / Alex Rivera C001):
///   0. The driver has created ONE scheduled W7061 shift for S001 today starting
///      ~2 h from now (the only Up Next card).
///   1. Log in → Today. The shifts refresh reconciles the reminders → the log
///      must show `reconciled: 1 pending (1 clock-in, 0 clock-out)` with
///      `punch-in-shift-<id>@<start+15>`. Touch /tmp/prc_stage1_done.
///   2. Clock In → Confirm → "Clocked in". The log must show
///      `punchedIn: cancelled punch-in-shift-<id>` and then a reconcile with
///      `(0 clock-in, 1 clock-out)` keyed `punch-out-visit-V-…@<end+60>`.
///      Touch /tmp/prc_stage2_done.
///   3. More → Sign Out → `signOut: cancelled 1`. Touch /tmp/prc_stage3_done.
final class PunchReminderShotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func dump(_ app: XCUIApplication, _ name: String) {
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
        try? app.debugDescription.write(toFile: "/tmp/\(name).txt", atomically: true, encoding: .utf8)
    }

    func testPunchRemindersScheduleCancelAndSignOut() throws {
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
        // ⚠️ Do NOT `app.tap()` here: on this layout a centre tap lands on
        //    "Start Unscheduled Visit" and opens its sheet over the Clock In
        //    card ("not hittable" on the first run). Dismiss one if it is up.
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists { cancel.tap(); sleep(1) }

        // Stage 1 — the refresh has reconciled; give the notification center a moment.
        sleep(8)
        dump(app, "prc_1_today")
        try? "done".write(toFile: "/tmp/prc_stage1_done", atomically: true, encoding: .utf8)

        // Stage 2 — clock in on the one scheduled card.
        let clockIn = app.buttons["Clock In"].firstMatch
        var tries = 0
        while !clockIn.exists && tries < 6 { app.swipeUp(); sleep(1); tries += 1 }
        XCTAssertTrue(clockIn.waitForExistence(timeout: 15), "Up Next 'Clock In' button not found")
        clockIn.tap()
        sleep(2)
        let confirm = app.buttons["Confirm Clock In"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "confirm sheet not shown")
        let enabledDeadline = Date().addingTimeInterval(20)
        while Date() < enabledDeadline && !confirm.isEnabled { usleep(250_000) }
        XCTAssertTrue(confirm.isEnabled, "Confirm Clock In never became enabled (GPS?)")
        confirm.tap()
        let clockedIn = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Clocked in'")).firstMatch
        XCTAssertTrue(clockedIn.waitForExistence(timeout: 25), "'Clocked in' never rendered")
        sleep(10) // post-punch refresh → reconcile (clock-out reminder)
        dump(app, "prc_2_clocked_in")
        try? "done".write(toFile: "/tmp/prc_stage2_done", atomically: true, encoding: .utf8)

        // Dismiss the success cover if it is still up, then sign out.
        for name in ["Done", "OK", "Close"] {
            let b = app.buttons[name].firstMatch
            if b.exists { b.tap(); sleep(1); break }
        }
        let moreTab = app.tabBars.buttons["More"]
        if moreTab.waitForExistence(timeout: 5) {
            moreTab.tap(); sleep(2)
            let signOut = app.buttons["Sign Out"].firstMatch
            var t2 = 0
            while !signOut.exists && t2 < 6 { app.swipeUp(); sleep(1); t2 += 1 }
            if signOut.exists { signOut.tap(); sleep(3) }
            dump(app, "prc_3_signed_out")
        }
        try? "done".write(toFile: "/tmp/prc_stage3_done", atomically: true, encoding: .utf8)
        sleep(2)
    }
}
