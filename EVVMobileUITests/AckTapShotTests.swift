import XCTest

/// Build 95 — sign-off card tap targets (Todoist 6hXqxmCPjjhjCGHH, Nick
/// 2026-09-23: "It shows up the ISP is due. HOWEVER, I click it and nothing
/// happens"). Overlay harness, NOT referenced in the pbxproj: copy this file
/// over EVVMobileUITests/MyDocumentsShotTests.swift, run
///     python3 docs/ack-tap-proxy.py 8765 &
///     xcodebuild test -project EVVMobile.xcodeproj -scheme EVVMobile \
///       -destination 'id=<booted sim>' -only-testing:EVVMobileUITests/AckTapShotTests \
///       CODE_SIGNING_ALLOWED=NO
/// then restore the original file. Logs into the live backend as the demo
/// account through the proxy (which injects ONE fake incomplete visit with the
/// demo account's real pending doc), opens Finish Note, and taps the card in
/// four places — row centre, header, document name, element — writing
/// center=/header=/text=/elem= to /tmp/ack_results.txt. Build 90 gave
/// center=false header=false text=true; build 95 gives all true.
final class AckTapShotTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    func testAckRowOpensSignPage() throws {
        let app = XCUIApplication()
        app.launchEnvironment["EVV_BASE_URL"] = "http://127.0.0.1:8765/api"
        addUIInterruptionMonitor(withDescription: "Notifications") { alert in
            for t in ["Allow", "Don't Allow", "OK"] { let b = alert.buttons[t]; if b.exists { b.tap(); return true } }
            return false
        }
        app.launch()
        app.tap()
        let tag = ProcessInfo.processInfo.environment["SHOT_TAG"] ?? "ack"
        func shot(_ name: String) {
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/\(tag)_\(name).png"))
            try? app.debugDescription.write(toFile: "/tmp/\(tag)_\(name).txt", atomically: true, encoding: .utf8)
        }
        let emailField = app.textFields["Email"].firstMatch
        if emailField.waitForExistence(timeout: 10) {
            emailField.tap(); emailField.typeText("demo@focus.com")
            let pw = app.secureTextFields["Password"].firstMatch
            XCTAssertTrue(pw.waitForExistence(timeout: 5)); pw.tap(); pw.typeText("DemoEVV2026!")
            app.buttons["Log In"].firstMatch.tap()
        }
        let todayTab = app.tabBars.buttons["Today"]
        XCTAssertTrue(todayTab.waitForExistence(timeout: 30), "Today tab")
        var tries = 0
        while !todayTab.isSelected && tries < 5 { todayTab.tap(); sleep(2); tries += 1 }
        sleep(4)
        let finish = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Finish Note'")).firstMatch
        var swipes = 0
        while !finish.exists && swipes < 4 { app.swipeUp(); swipes += 1 }
        shot("0_today")
        XCTAssertTrue(finish.waitForExistence(timeout: 20), "Finish Note button")
        finish.tap()
        let card = app.otherElements["pendingAcknowledgementsCard"].firstMatch
        let header = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Sign-off required'")).firstMatch
        _ = header.waitForExistence(timeout: 20)
        sleep(2)
        shot("1_doc")
        XCTAssertTrue(header.exists, "sign-off card header")
        _ = card
        var row = app.buttons["pendingAckRow-18"].firstMatch
        if !row.waitForExistence(timeout: 3) { row = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'RV ISP 26-27'")).firstMatch }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "ack row")
        func opened() -> Bool {
            app.buttons["Done"].firstMatch.exists || app.webViews.firstMatch.exists || app.otherElements["URL"].exists
        }
        func closeIfOpen() {
            let d = app.buttons["Done"].firstMatch
            if d.exists { d.tap(); sleep(2); return }
            if opened() {
                // drag the sheet down
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
                start.press(forDuration: 0.2, thenDragTo: end)
                sleep(2)
            }
        }
        var results: [String] = []
        // A: dead-centre of the row (the empty Spacer region between name and chevron)
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)).tap()
        sleep(5); shot("2_center"); results.append("center=\(opened())"); closeIfOpen()
        // B: the header line
        header.tap()
        sleep(4); shot("3_header"); results.append("header=\(opened())"); closeIfOpen()
        // C: the document name text itself
        app.staticTexts["RV ISP 26-27"].firstMatch.tap()
        sleep(5); shot("4_text"); results.append("text=\(opened())"); closeIfOpen()
        // D: XCUIElement.tap() on the button element
        if row.isHittable { row.tap() }
        sleep(5); shot("5_elem"); results.append("elem=\(opened())"); closeIfOpen()
        try? results.joined(separator: "\n").write(toFile: "/tmp/\(tag)_results.txt", atomically: true, encoding: .utf8)
        NSLog("ACKTAP RESULTS %@", results.joined(separator: " "))
    }
}
