import XCTest

/// Build 53 reproduction/verification harness for Todoist 6hPM7CM4hgFRfVXq
/// ("History includes today and in-progress visits").
///
/// ⚠️ NOT referenced by EVVMobile.xcodeproj on purpose (the pbxproj lists
/// test files explicitly; xcodegen from project.yml would pick it up). To run
/// it, temporarily copy this file's body over MyDocumentsShotTests.swift, or
/// add it to the UITests target.
///
/// Flow: log into the LIVE backend as the demo account (S001), open History,
/// screenshot + dump the accessibility tree, then — if the TEST_RUNNER_-prefixed
/// env vars are set — make a server-side change via the API (e.g. clock a
/// visit out) and pull-to-refresh, then screenshot/dump again.
///   TEST_RUNNER_EVV_TEST_TOKEN=<mv1 token for S001>
///   TEST_RUNNER_EVV_TEST_POST_PATH=/api/visits/V-xxxx/clock-out
///   TEST_RUNNER_EVV_TEST_POST_BODY='{"lat":40.27,"lng":-76.88,"accuracy":10,"signatureSkipReason":"test"}'
/// Outputs: /tmp/hist_0_today.png, /tmp/hist_1_history.{png,txt},
/// /tmp/hist_change.txt, /tmp/hist_2_after_refresh.{png,txt}.
///
/// This is how the build-52 bug was proven: the pre-fix run logged
/// `refreshHistory error networkError(... Code=-999 "cancelled" ... /api/me/visits)`
/// right after `refreshable fired`, and the post-refresh tree still showed the
/// stale row. Clean up any demo visits/shifts you create afterwards.
final class HistoryTodayShotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHistoryShowsToday() throws {
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
        sleep(5)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/hist_0_today.png"))

        let historyTab = app.tabBars.buttons["History"]
        var tries = 0
        while !historyTab.isSelected && tries < 5 { historyTab.tap(); sleep(2); tries += 1 }
        XCTAssertTrue(historyTab.isSelected)
        sleep(5)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/hist_1_history.png"))
        try? app.debugDescription.write(toFile: "/tmp/hist_1_history.txt", atomically: true, encoding: .utf8)

        // Optional: server-side change (any POST the caller specifies) then pull-to-refresh
        let env = ProcessInfo.processInfo.environment
        if let token = env["EVV_TEST_TOKEN"], let path = env["EVV_TEST_POST_PATH"], !path.isEmpty {
            var req = URLRequest(url: URL(string: "https://d2hmfpgqkgeyu.cloudfront.net\(path)")!)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = (env["EVV_TEST_POST_BODY"] ?? "{}").data(using: .utf8)
            let sem = DispatchSemaphore(value: 0)
            var out = ""
            URLSession.shared.dataTask(with: req) { d, r, _ in
                out = "\((r as? HTTPURLResponse)?.statusCode ?? 0) " + (d.flatMap { String(data: $0, encoding: .utf8) } ?? "")
                sem.signal()
            }.resume()
            sem.wait()
            try? out.write(toFile: "/tmp/hist_change.txt", atomically: true, encoding: .utf8)
            sleep(2)

            // pull to refresh on the History scroll view
            let scroll = app.scrollViews.firstMatch
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
            start.press(forDuration: 0.2, thenDragTo: end)
            sleep(6)
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/hist_2_after_refresh.png"))
            try? app.debugDescription.write(toFile: "/tmp/hist_2_after_refresh.txt", atomically: true, encoding: .utf8)
        }
    }
}
