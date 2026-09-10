import XCTest

/// Build 62 verification harness for the unscheduled-visit DATE picker.
///
/// Nick, #evv 2026-09-09 (screenshot of this sheet): "There's no way to put a
/// date on this like you can on desktop. Just fix this."
///
/// ⚠️ NOT referenced by EVVMobile.xcodeproj on purpose (the pbxproj lists test
/// files explicitly). To run it, temporarily copy this file's body over
/// MyDocumentsShotTests.swift (git checkout it afterwards) — the overlay
/// pattern the build-61 punch-reminder harness used.
///
/// 🚧 STATUS (build 62): this UITest gets as far as opening the sheet but the
/// taps inside the Today ScrollView are UNRELIABLE in the iOS 26.3 simulator —
/// XCUITest computes a hit point of {-1,-1} for controls that are plainly
/// visible in the accessibility dump with no alert or cover present, so
/// `.tap()` fails "Not hittable" and even a coordinate tap does not always
/// register. It is committed as a starting point, NOT as the evidence for this
/// card. The shipped verification is:
///   • docs/manual-date-check  — 43/43 offline, the REAL ManualSpan /
///     ManualEntryPolicy / QueuedAction / ShiftsResponse; and
///   • docs/manual-date-live   — 16/16 against the LIVE CloudFront backend using
///     the REAL UnscheduledVisitRequest and the date-derivation line lifted
///     verbatim out of AppState, proving a back-dated entry is created on the
///     asked-for day and read back as that day by the app's own history feed.
/// Anyone reviving this: the blocker is simulator hit-testing, not the feature.
///
/// Flow (LIVE CloudFront backend, demo account S001 / Alex Rivera C001, W8593
/// is a non-EVV manual-time service for that pair):
///   1. Log in → Today → Start Unscheduled Visit → Alex Rivera → Life Sharing.
///   2. Assert the manual-time section now shows a **Date** row (the bug: it
///      only had Start/End times) defaulting to TODAY, and that the footer
///      names the role's back-date window.
///   3. Move the picker back one day, assert the sheet says so in words
///      ("Recording time for <day>") — the thing a caregiver must not get
///      wrong — and that the duration hint still reads a full day.
///   4. Record Time → confirm → "Time recorded".
///   5. The driver then asserts in RDS that the visit's DATE is YESTERDAY.
final class UnscheduledDateShotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func dump(_ app: XCUIApplication, _ name: String) {
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
        try? app.debugDescription.write(toFile: "/tmp/\(name).txt", atomically: true, encoding: .utf8)
    }

    /// Clear any SpringBoard permission alert sitting over the app. Without
    /// this the element underneath reports `exists == true`, `isHittable ==
    /// false` and a hit point of {-1,-1} — a failure that looks like a broken
    /// layout and is not.
    /// Tap through the element's own coordinate space. Inside the Today
    /// ScrollView and the unscheduled Form, XCUITest routinely computes a hit
    /// point of {-1,-1} for a perfectly visible control (sibling `Other` views
    /// span the same frame), so `.tap()` fails with "Not hittable" on something
    /// a human can obviously press.
    private func forceTap(_ el: XCUIElement) {
        if el.isHittable { el.tap(); return }
        el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func dismissSystemAlerts(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<4 {
            var tapped = false
            for target in [springboard.alerts.firstMatch, app.alerts.firstMatch] {
                guard target.exists else { continue }
                for name in ["Allow", "Allow While Using App", "Allow Once", "OK", "Continue", "Don’t Allow", "Don't Allow"] {
                    let b = target.buttons[name]
                    if b.exists && b.isHittable { b.tap(); tapped = true; break }
                }
                if tapped { break }
            }
            if !tapped { return }
            sleep(1)
        }
    }

    func testBackDatedUnscheduledEntry() throws {
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
        XCTAssertTrue(todayTab.waitForExistence(timeout: 25), "tab bar not visible after login")
        sleep(5)   // let the shifts refresh land so ManualEntryPolicy has the window
        if !todayTab.isSelected { todayTab.tap(); sleep(2) }

        // ⚠️ The notification-permission prompt (build 60's PunchReminderCenter)
        // is a SPRINGBOARD alert, not one of ours — XCUIApplication reports the
        // button underneath as existing but NOT HITTABLE, with a computed hit
        // point of {-1,-1}, which reads exactly like a layout bug. Dismiss it
        // explicitly rather than relying on the interruption monitor (which only
        // fires on an interaction that is itself being blocked).
        dismissSystemAlerts(app)

        // ⚠️ build-61 lesson: a bare app.tap() here lands on "Start Unscheduled
        // Visit" and opens the sheet unintentionally. Go straight for the button.
        let startBtn = app.buttons["Start Unscheduled Visit"].firstMatch
        var tries = 0
        while !startBtn.exists && tries < 6 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(startBtn.waitForExistence(timeout: 10), "Start Unscheduled Visit not found")
        // ⚠️ `isHittable` is FALSE here even with nothing covering the button:
        // the Today ScrollView has sibling `Other` overlays spanning the same
        // frame, so XCUITest computes a hit point of {-1,-1} and `.tap()`
        // retries three times and fails with "Not hittable". The accessibility
        // tree shows the button at its expected rect with no alert present — a
        // harness artifact, not a layout bug. Tap the element's own coordinate
        // space, which bypasses the hit-point computation.
        dump(app, "uvd_0_today")
        startBtn.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(3)

        dump(app, "uvd_0b_sheet")
        let alex = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Alex Rivera'")).firstMatch
        XCTAssertTrue(alex.waitForExistence(timeout: 10), "Alex Rivera row not found")
        forceTap(alex)
        sleep(1)

        let ls = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'IDD Life Sharing'")).firstMatch
        XCTAssertTrue(ls.waitForExistence(timeout: 5), "Life Sharing service row not found")
        forceTap(ls)
        sleep(1)

        app.swipeUp(); sleep(1)
        let visitTimes = app.staticTexts["Visit Times"].firstMatch
        XCTAssertTrue(visitTimes.waitForExistence(timeout: 5), "manual-time section not shown")
        dump(app, "uvd_0_times")

        // ── THE BUG: there was no Date row here at all ─────────────────
        let dateCell = app.datePickers.firstMatch
        XCTAssertTrue(dateCell.waitForExistence(timeout: 5), "no date picker in the manual-time section")
        let dateLabel = app.staticTexts["Date"].firstMatch
        XCTAssertTrue(dateLabel.waitForExistence(timeout: 5),
                      "the sheet still has no Date row — the reported bug")

        // The footer must name the role's window rather than a made-up number.
        let footer = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS 'back-date' OR label CONTAINS 'only enter time for today'")
        ).firstMatch
        XCTAssertTrue(footer.waitForExistence(timeout: 5), "no back-date window hint in the footer")
        dump(app, "uvd_1_datepicker")

        // Default is TODAY → no back-dated banner yet.
        let banner = app.staticTexts.containing(
            NSPredicate(format: "label BEGINSWITH 'Recording time for'")).firstMatch
        XCTAssertFalse(banner.exists, "a fresh sheet must default to today, with no back-dated banner")

        // ── Move the picker back one day ───────────────────────────────
        // The compact DatePicker opens a calendar popover; tapping the day
        // before today selects it.
        forceTap(dateCell)
        sleep(2)
        dump(app, "uvd_2_calendar")
        // Yesterday's day-of-month, resolved the same way the app would.
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
        let dayNumber = String(cal.component(.day, from: yesterday))
        // Calendar cells are buttons whose label starts with the weekday+date.
        let dayCell = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", dayNumber)).firstMatch
        if dayCell.waitForExistence(timeout: 5) {
            forceTap(dayCell)
        }
        sleep(1)
        // Dismiss the popover.
        app.tap()
        sleep(1)
        dump(app, "uvd_3_backdated")

        XCTAssertTrue(banner.waitForExistence(timeout: 5),
                      "back-dated entry must SAY which day it is recording")

        // The cross-midnight rules are untouched by the date.
        let dayHint = app.staticTexts.containing(
            NSPredicate(format: "label BEGINSWITH '24h 0m'")).firstMatch
        XCTAssertTrue(dayHint.exists, "12:00 AM → 12:00 AM must still read as a full day")

        // ── Record ─────────────────────────────────────────────────────
        let record = app.buttons["Record Time"].firstMatch
        var rt = 0
        while !record.exists && rt < 4 { app.swipeUp(); sleep(1); rt += 1 }
        XCTAssertTrue(record.waitForExistence(timeout: 5), "Record Time button not found")
        forceTap(record)

        // Untouched midnight placeholder → the desktop-mirroring confirm, which
        // on a back-dated entry NAMES the day.
        let save = app.alerts.buttons["Save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5), "placeholder confirm not shown")
        dump(app, "uvd_4_confirm")
        save.tap()

        let recorded = app.staticTexts["Time recorded"].firstMatch
        let ok = recorded.waitForExistence(timeout: 25)
        dump(app, "uvd_5_recorded")
        XCTAssertTrue(ok, "'Time recorded' not shown after the server accepted the back-dated entry")

        try? "done".write(toFile: "/tmp/uvd_stage1_done", atomically: true, encoding: .utf8)
        sleep(5)
        dump(app, "uvd_6_today")
    }
}
