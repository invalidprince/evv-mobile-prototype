import XCTest

/// REPRO/VERIFY harness for the build-88..93 open-shift pickup crash
/// (Nick, 2026-09-23): pick up an open shift → confirmation alert → tap OK →
/// frozen UI → watchdog kill. See docs/main-actor-check/README.md.
///
/// ⚠️ NOT referenced by EVVMobile.xcodeproj on purpose (the pbxproj lists
/// test files explicitly). To run it, temporarily copy this file's body over
/// EVVMobileUITests/MyDocumentsShotTests.swift (same convention as the other
/// Shot tests) and start the local stub first:
///   node docs/main-actor-check/repro_stub_server.js   # listens on :8099
/// The stub serves S013's captured payloads and answers the claim POST with
/// the exact prod shape — ZERO prod writes. APIClient honours the EVV_BASE_URL
/// launch environment since build 94 (unset in production).
///
/// On build 93 this run FROZE: XCUITest reported "Unable to perform work on
/// main run loop, process main thread busy for 30.0s", and `sample` of the
/// app process captured the Combine ObservableObjectPublisher deadlock
/// (main thread in dueMedications.setter waiting on _os_unfair_lock, a
/// background thread holding it in missedShifts.setter). On build 94 the
/// same run completes with the app foregrounded and responsive.
final class MyDocumentsShotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOpenShiftPickupOK() throws {
        let app = XCUIApplication()
        app.launchEnvironment["EVV_BASE_URL"] = ProcessInfo.processInfo.environment["EVV_BASE_URL"] ?? "http://127.0.0.1:8099/api"
        addUIInterruptionMonitor(withDescription: "Permissions") { alert in
            for name in ["Allow", "Allow While Using App", "Don't Allow", "Allow Once"] {
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
            emailField.typeText("nmudgett@fbhi.net")
            let pw = app.secureTextFields["Password"].firstMatch
            XCTAssertTrue(pw.waitForExistence(timeout: 5))
            pw.tap()
            pw.typeText("stub-password")
            let login = app.buttons["Log In"].firstMatch
            XCTAssertTrue(login.waitForExistence(timeout: 5))
            login.tap()
        }

        // Dismiss the springboard "Save Password?" prompt if it appears
        sleep(4)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Not Now", "Don\u{2019}t Allow", "Allow While Using App", "Allow"] {
            let b = springboard.buttons[label].firstMatch
            if b.exists && b.isHittable { b.tap(); sleep(1) }
        }

        // Wait for the tab bar, then go to Schedule
        let scheduleTab = app.tabBars.buttons["Schedule"].firstMatch
        XCTAssertTrue(scheduleTab.waitForExistence(timeout: 30), "Schedule tab never appeared")
        sleep(2)
        var onSchedule = false
        for _ in 0..<4 {
            scheduleTab.tap()
            sleep(2)
            if app.staticTexts["Open Shifts"].exists || app.navigationBars["Schedule"].exists {
                onSchedule = true
                break
            }
        }
        XCTAssertTrue(onSchedule, "never landed on the Schedule screen")

        // Scroll until the Request Shift button is hittable
        let requestBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Request Shift'")).firstMatch
        var scrolls = 0
        while (!requestBtn.exists || !requestBtn.isHittable) && scrolls < 8 {
            app.swipeUp()
            scrolls += 1
        }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/evv-stub/r2_openshifts.png"))
        XCTAssertTrue(requestBtn.exists, "No 'Request Shift' button found")
        requestBtn.tap()

        // The claim alert ("You're on the schedule" — reused for pickups)
        let ok = app.alerts.buttons["OK"].firstMatch
        XCTAssertTrue(ok.waitForExistence(timeout: 15), "claim confirmation alert with OK never appeared")
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/evv-stub/r3_alert.png"))
        ok.tap()

        // Give the app time to deadlock/crash if it is going to
        sleep(5)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/evv-stub/r4_after_ok.png"))
        XCTAssertEqual(app.state, .runningForeground, "app is no longer in the foreground after tapping OK")

        // Prove the main thread is alive (not a silent deadlock): the shift
        // must now show Requested, and tab switching must respond.
        let requested = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Requested'")).firstMatch
        XCTAssertTrue(requested.waitForExistence(timeout: 10), "claimed shift never flipped to Requested — UI not updating")
        let todayTab = app.tabBars.buttons["Today"].firstMatch
        XCTAssertTrue(todayTab.waitForExistence(timeout: 5))
        todayTab.tap()
        sleep(1)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/evv-stub/r5_today.png"))
        XCTAssertEqual(app.state, .runningForeground)
    }
}
