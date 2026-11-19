import XCTest

/// Build 126 — Work tab grouped To-Dos (server v0.4.833). Overlay harness, NOT
/// referenced in the pbxproj (same pattern as AckTapShotTests): copy this file
/// over EVVMobileUITests/MyDocumentsShotTests.swift, start
///     EVV_MOBILE_TOKEN=<staging manager mv1 token> python3 docs/work-groups-check/proxy.py 8766 &
/// run
///     xcodebuild test -project EVVMobile.xcodeproj -scheme EVVMobile \
///       -destination 'id=<sim>' -only-testing:EVVMobileUITests/WorkGroupsShotTests CODE_SIGNING_ALLOWED=NO
/// then restore the original file. Read-only: the proxy refuses every write.
/// Screenshots + accessibility trees land in /tmp/wg_*.png|txt and the
/// assertions land in /tmp/wg_results.txt.
final class WorkGroupsShotTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    func testWorkTabGroupsExpandCollapse() throws {
        let app = XCUIApplication()
        app.launchEnvironment["EVV_BASE_URL"] = "http://127.0.0.1:8766/api"
        addUIInterruptionMonitor(withDescription: "Alerts") { alert in
            for t in ["Allow", "Don't Allow", "OK", "Allow While Using App"] { let b = alert.buttons[t]; if b.exists { b.tap(); return true } }
            return false
        }
        app.launch()
        app.tap()
        var results: [String] = []
        func shot(_ name: String) {
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/wg_\(name).png"))
            try? app.debugDescription.write(toFile: "/tmp/wg_\(name).txt", atomically: true, encoding: .utf8)
        }
        func record(_ k: String, _ v: Bool) { results.append("\(k)=\(v)"); XCTAssertTrue(v, k) }

        let emailField = app.textFields["Email"].firstMatch
        if emailField.waitForExistence(timeout: 10) {
            emailField.tap(); emailField.typeText("staging-manager@example.invalid")
            let pw = app.secureTextFields["Password"].firstMatch
            if pw.waitForExistence(timeout: 5) { pw.tap(); pw.typeText("x") }
            app.buttons["Log In"].firstMatch.tap()
        }
        let workTab = app.tabBars.buttons["Work"]
        XCTAssertTrue(workTab.waitForExistence(timeout: 30), "Work tab")
        workTab.tap()
        sleep(4)
        shot("0_top")
        let team = app.buttons["work-group-team-unfinished-notes"].firstMatch
        // List rows are lazy: scroll until the group row is on screen.
        var down = 0
        while !(team.exists && team.isHittable) && down < 12 { app.swipeUp(); down += 1; sleep(1) }
        record("group_row_exists", team.exists)
        sleep(1)
        shot("1_collapsed")
        record("collapsed_title", team.label.contains("Team Unfinished Documentation"))
        let firstChild = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Unfinished documentation'")).firstMatch
        record("children_hidden_when_collapsed", !firstChild.exists)

        team.tap()
        sleep(2)
        record("children_shown_when_expanded", firstChild.waitForExistence(timeout: 5))
        shot("2_expanded")
        let footer = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Incomplete documentation'")).firstMatch
        var swipes = 0
        while !footer.isHittable && swipes < 6 { app.swipeUp(); swipes += 1 }
        record("footer_row_present", footer.exists)
        shot("3_footer")
        while !(team.exists && team.isHittable) && swipes > -8 { app.swipeDown(); swipes -= 1; sleep(1) }
        team.tap()
        sleep(2)
        record("collapses_again", !firstChild.exists)
        shot("4_recollapsed")
        let badge = app.tabBars.buttons["Work"].value as? String ?? ""
        results.append("work_tab_badge=\(badge)")
        try? results.joined(separator: "\n").write(toFile: "/tmp/wg_results.txt", atomically: true, encoding: .utf8)
    }
}
