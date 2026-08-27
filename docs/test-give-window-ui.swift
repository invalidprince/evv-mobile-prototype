// docs/test-give-window-ui.swift — build 33 / server v0.4.295
//
// Offline proof of the DueMedication give-window decoding + derived UI state.
// Run standalone:  swift docs/test-give-window-ui.swift
//
// This deliberately re-declares a MINIMAL mirror of the shipped struct's
// decoding + computed properties rather than importing the app target (the
// app has no test target and pulls in SwiftUI/UIKit). The mirror is kept
// byte-identical to APIClient.swift's canGive/windowBlocked/windowChipLabel/
// windowExplanation bodies — if you change one, change both.
//
// What it proves:
//   • The five v0.4.295 fields decode from a REAL /api/me/medications payload.
//   • An OLD server payload (fields absent) still decodes and falls back to
//     the pre-window behaviour — Given stays available, no chip. This is the
//     regression that would silently hide Given on every dose.
//   • state 'none' (a dose with no due_at) is NOT treated as a closed window.
//   • early / closed produce the right chip text and the server's prose.
//   • A recorded dose never shows a window chip.

import Foundation

struct DueMedication: Decodable, Identifiable {
    let id: Int
    let clientId: String
    let clientName: String
    let medName: String
    let instructions: String?
    let route: String?
    let dueTime: String?
    let dueTimeLabel: String?
    let status: String
    let late: Bool
    let initials: String?
    let recordable: Bool
    let giveAllowed: Bool?
    let giveWindowState: String?
    let giveWindowOpensLabel: String?
    let giveWindowClosesLabel: String?
    let giveWindowReason: String?

    var canGive: Bool { giveAllowed ?? recordable }

    var windowBlocked: Bool {
        guard recordable, let s = giveWindowState else { return false }
        return (s == "early" || s == "closed") && !canGive
    }

    var windowChipLabel: String? {
        guard windowBlocked else { return nil }
        if giveWindowState == "early" {
            if let opens = giveWindowOpensLabel { return "opens \(opens)" }
            return "not open yet"
        }
        if let closes = giveWindowClosesLabel { return "window closed \(closes)" }
        return "window closed"
    }

    var windowExplanation: String? {
        guard windowBlocked else { return nil }
        if let reason = giveWindowReason, !reason.isEmpty { return reason }
        if giveWindowState == "early", let opens = giveWindowOpensLabel {
            return "Too early — this dose cannot be recorded as given until \(opens)."
        }
        if let closes = giveWindowClosesLabel {
            return "This dose is past its one-hour window (it closed at \(closes)) and can no longer be recorded as given."
        }
        return "This dose is outside its one-hour give window."
    }
}

// ---------------------------------------------------------------------------

var passed = 0
var failed = 0
func ok(_ name: String, _ cond: Bool, _ detail: String = "") {
    if cond { passed += 1; print("  ✓ \(name)") }
    else { failed += 1; print("  ✗ \(name)  \(detail)") }
}
func eq<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
    ok(name, actual == expected, "got \(actual), want \(expected)")
}
func decode(_ json: String) -> DueMedication {
    try! JSONDecoder().decode(DueMedication.self, from: json.data(using: .utf8)!)
}

func base(_ extra: String) -> String {
    """
    {"id":1,"clientId":"C001","clientName":"Ray Varner","medName":"Metformin",
     "instructions":null,"route":"PO","dueTime":"20:00","dueTimeLabel":"8:00 PM",
     "status":"pending","late":false,"initials":null,"recordable":true\(extra)}
    """
}

print("\n1. The v0.4.295 fields decode")
let open = decode(base(#","giveAllowed":true,"giveWindowState":"open","giveWindowOpensLabel":"7:00 PM","giveWindowClosesLabel":"9:00 PM","giveWindowReason":null"#))
eq("1.1 state decodes", open.giveWindowState, "open")
eq("1.2 giveAllowed decodes", open.giveAllowed, true)
eq("1.3 opens label decodes", open.giveWindowOpensLabel, "7:00 PM")
eq("1.4 closes label decodes", open.giveWindowClosesLabel, "9:00 PM")
ok("1.5 an OPEN window can give", open.canGive)
ok("1.6 ...and is not blocked", !open.windowBlocked)
ok("1.7 ...and shows NO chip", open.windowChipLabel == nil)

print("\n2. EARLY — Given withheld, 'opens' chip")
let early = decode(base(#","giveAllowed":false,"giveWindowState":"early","giveWindowOpensLabel":"7:00 PM","giveWindowClosesLabel":"9:00 PM","giveWindowReason":"Too early — this dose cannot be recorded as given until 7:00 PM (one hour before it is due).""#))
ok("2.1 cannot give", !early.canGive)
ok("2.2 blocked", early.windowBlocked)
eq("2.3 chip reads 'opens 7:00 PM'", early.windowChipLabel, "opens 7:00 PM")
ok("2.4 uses the SERVER's prose verbatim", early.windowExplanation?.hasPrefix("Too early") == true)
ok("2.5 documentation still offered (recordable)", early.recordable)

print("\n3. CLOSED — Given withheld, 'window closed' chip")
let closed = decode(base(#","giveAllowed":false,"giveWindowState":"closed","giveWindowOpensLabel":"7:00 PM","giveWindowClosesLabel":"9:00 PM","giveWindowReason":"This dose is past its one-hour window (it closed at 9:00 PM) and has been marked missed.""#))
ok("3.1 cannot give", !closed.canGive)
eq("3.2 chip names the close time", closed.windowChipLabel, "window closed 9:00 PM")
ok("3.3 server prose used", closed.windowExplanation?.contains("9:00 PM") == true)

print("\n4. state 'none' is UNCONSTRAINED, not closed")
let none = decode(base(#","giveAllowed":true,"giveWindowState":"none","giveWindowOpensLabel":null,"giveWindowClosesLabel":null,"giveWindowReason":null"#))
ok("4.1 can give", none.canGive)
ok("4.2 NOT blocked — 'none' means no due_at, not a shut window", !none.windowBlocked)
ok("4.3 no chip", none.windowChipLabel == nil)

print("\n5. 🚨 OLD SERVER / mock payload — fields ABSENT")
let legacy = decode(base(""))
ok("5.1 still decodes (no throw)", legacy.id == 1)
ok("5.2 canGive falls back to recordable=true — Given is NOT hidden", legacy.canGive)
ok("5.3 not blocked", !legacy.windowBlocked)
ok("5.4 no chip", legacy.windowChipLabel == nil)
ok("5.5 no explanation", legacy.windowExplanation == nil)

print("\n6. An ALREADY-RECORDED dose never shows a window chip")
let done = """
{"id":2,"clientId":"C001","clientName":"Ray Varner","medName":"Metformin",
 "instructions":null,"route":"PO","dueTime":"08:00","dueTimeLabel":"8:00 AM",
 "status":"given","late":false,"initials":"NM","recordable":false,
 "giveAllowed":false,"giveWindowState":"closed","giveWindowOpensLabel":"7:00 AM",
 "giveWindowClosesLabel":"9:00 AM","giveWindowReason":null}
"""
let recorded = decode(done)
ok("6.1 not recordable", !recorded.recordable)
ok("6.2 NOT blocked — the row shows initials, not a lock", !recorded.windowBlocked)
ok("6.3 no chip", recorded.windowChipLabel == nil)

print("\n7. A missed-but-undocumented dose stays actionable")
let missed = decode("""
{"id":3,"clientId":"C001","clientName":"Ray Varner","medName":"Metformin",
 "instructions":null,"route":"PO","dueTime":"08:00","dueTimeLabel":"8:00 AM",
 "status":"missed","late":true,"initials":null,"recordable":true,
 "giveAllowed":false,"giveWindowState":"closed","giveWindowOpensLabel":"7:00 AM",
 "giveWindowClosesLabel":"9:00 AM","giveWindowReason":"past its one-hour window"}
""")
ok("7.1 recordable — it still needs documenting", missed.recordable)
ok("7.2 but cannot be GIVEN", !missed.canGive)
ok("7.3 shows the closed chip", missed.windowChipLabel != nil)

print("\n\(passed) passed, \(failed) failed\n")
exit(failed == 0 ? 0 : 1)
