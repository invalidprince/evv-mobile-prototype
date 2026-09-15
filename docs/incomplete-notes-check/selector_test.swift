import Foundation

// ---------------------------------------------------------------------------
// Build 70 — Today's incomplete-documentation card (Todoist 6hVvh2hr9qM9r2cH).
//
// Nick, 2026-09-15: "it's now not showing on the iOS. It showed initially but
// after sync, it removed an incomplete note from yesterday, 9/14".
//
// This harness executes the REAL `incompleteNoteVisits` selector: check.sh
// extracts the source between the BEGIN/END incomplete-notes-source markers in
// AppState.swift and compiles it against the minimal shims below. So a
// regression in the shipped property fails this test — it is not a rewrite of
// the logic.
//
// The shim models only what the selector touches: mode, todayVisits,
// pastVisits, historyVisits, and the Visit fields it reads.
// ---------------------------------------------------------------------------

enum AppMode { case mock, server }

enum VisitStatus { case scheduled, inProgress, completed, missed }

struct ShimClient { var name: String }

struct Visit: Identifiable {
    var id = UUID()
    var client: ShimClient = ShimClient(name: "Someone")
    var scheduledStart: Date = Date()
    var status: VisitStatus = .completed
    var docComplete: Bool = false
    var serverVisitId: String? = nil
    var serverShiftId: Int? = nil
    var serverDocStatus: String? = nil
    var approvalStatus: String? = nil
}

/// Host for the extracted property.
final class AppState {
    var mode: AppMode = .server
    var todayVisits: [Visit] = []
    var pastVisits: [Visit] = []
    var historyVisits: [Visit] = []

    // <<< REAL incompleteNoteVisits IS SPLICED IN HERE BY check.sh >>>
    INCOMPLETE_NOTES_SOURCE_PLACEHOLDER
}

// --------------------------------------------------------------------- harness
var pass = 0, fail = 0
func ok(_ label: String, _ cond: Bool) {
    if cond { pass += 1; print("  ✓ \(label)") }
    else { fail += 1; print("  ✗ \(label)") }
}
func eq<T: Equatable>(_ label: String, _ got: T, _ want: T) {
    if got == want { pass += 1; print("  ✓ \(label)") }
    else { fail += 1; print("  ✗ \(label) — got \(got), want \(want)") }
}

let cal = Calendar.current
let startOfToday = cal.startOfDay(for: Date())
func day(_ offset: Int, hour: Int = 9) -> Date {
    cal.date(byAdding: .hour, value: hour,
             to: cal.date(byAdding: .day, value: offset, to: startOfToday)!)!
}

func st(_ s: AppState) -> AppState { s }

print("[A] THE REPORTED BUG — a past-dated incomplete note from HISTORY is shown")
do {
    // Nick's real row: V-2069, 2026-09-14, note_status 'incomplete'.
    let s = AppState()
    s.mode = .server
    s.todayVisits = []
    s.pastVisits = []          // /api/me/shifts is today-forward: ALWAYS empty
    s.historyVisits = [
        Visit(client: ShimClient(name: "Ray Varner"), scheduledStart: day(-1),
              status: .completed, serverVisitId: "V-2069", serverShiftId: 900,
              serverDocStatus: "incomplete"),
    ]
    let got = s.incompleteNoteVisits
    eq("yesterday's incomplete note appears", got.count, 1)
    eq("it is V-2069", got.first?.serverVisitId ?? "none", "V-2069")
}

print("[B] THE OLD CODE PATH IS GONE — an empty pastVisits no longer hides the row")
do {
    // This is the exact state after refreshServerShifts() in server mode.
    // Pre-build-70 this returned [] and the card vanished.
    let s = AppState()
    s.mode = .server
    s.pastVisits = []
    s.historyVisits = [
        Visit(scheduledStart: day(-3), status: .completed,
              serverVisitId: "V-1", serverDocStatus: "incomplete"),
        Visit(scheduledStart: day(-5), status: .completed,
              serverVisitId: "V-2", serverDocStatus: "in progress"),
    ]
    eq("both past-dated rows survive an empty pastVisits", s.incompleteNoteVisits.count, 2)
}

print("[C] 'in progress' COUNTS AS INCOMPLETE — same definition as the web")
do {
    let s = AppState()
    s.mode = .server
    s.historyVisits = [
        Visit(scheduledStart: day(-1), status: .completed,
              serverVisitId: "V-ip", serverDocStatus: "in progress"),
    ]
    eq("'in progress' still needs finishing", s.incompleteNoteVisits.count, 1)
}

print("[D] A COMPLETE NOTE IS NEVER NAGGED — serverDocStatus is authoritative")
do {
    // mapHistoryVisit does NOT set docComplete, so a purely docComplete-based
    // filter would show every completed visit of the last 14 days as debt.
    // That would have been a far worse bug than the one being fixed.
    let s = AppState()
    s.mode = .server
    s.historyVisits = [
        Visit(scheduledStart: day(-1), status: .completed, docComplete: false,
              serverVisitId: "V-done", serverDocStatus: "complete"),
        Visit(scheduledStart: day(-2), status: .completed, docComplete: false,
              serverVisitId: "V-DONE-CAPS", serverDocStatus: "COMPLETE"),
    ]
    eq("a server-complete note is not listed (and case is ignored)", s.incompleteNoteVisits.count, 0)
}

print("[E] GHOST ROWS NEVER NAG")
do {
    let s = AppState()
    s.mode = .server
    s.historyVisits = [
        Visit(scheduledStart: day(-1), status: .completed, serverVisitId: "V-den",
              serverDocStatus: "incomplete", approvalStatus: "denied"),
        Visit(scheduledStart: day(-2), status: .completed, serverVisitId: "V-del",
              serverDocStatus: "incomplete", approvalStatus: "deleted"),
        Visit(scheduledStart: day(-3), status: .completed, serverVisitId: "V-ok",
              serverDocStatus: "incomplete", approvalStatus: "approved"),
    ]
    let got = s.incompleteNoteVisits
    eq("denied + deleted are excluded, approved kept", got.count, 1)
    eq("the surviving row is the approved one", got.first?.serverVisitId ?? "none", "V-ok")
}

print("[F] NO DOUBLE RENDER — today's visit is in BOTH payloads (the v0.4.485 trap)")
do {
    let s = AppState()
    s.mode = .server
    let todayRow = Visit(scheduledStart: day(0), status: .completed,
                         docComplete: false, serverVisitId: "V-today",
                         serverShiftId: 77, serverDocStatus: "incomplete")
    s.todayVisits = [todayRow]
    // /api/me/visits covers 14 days INCLUDING today, so the same visit is here.
    s.historyVisits = [todayRow]
    eq("rendered exactly once", s.incompleteNoteVisits.count, 1)
}
do {
    // Same visit, different local UUIDs (mapServerShift and mapHistoryVisit
    // each mint their own) — dedupe must key on the SERVER identity.
    let s = AppState()
    s.mode = .server
    s.todayVisits = [Visit(scheduledStart: day(0), status: .completed,
                           serverVisitId: "V-x", serverShiftId: 5,
                           serverDocStatus: "incomplete")]
    s.historyVisits = [Visit(scheduledStart: day(0), status: .completed,
                             serverVisitId: "V-x", serverShiftId: 5,
                             serverDocStatus: "incomplete")]
    eq("dedupe survives differing local UUIDs", s.incompleteNoteVisits.count, 1)
}
do {
    // Shift-id dedupe when the visit id is absent on one side.
    let s = AppState()
    s.mode = .server
    s.todayVisits = [Visit(scheduledStart: day(0), status: .completed,
                           serverVisitId: nil, serverShiftId: 42)]
    s.historyVisits = [Visit(scheduledStart: day(0), status: .completed,
                             serverVisitId: "V-42", serverShiftId: 42,
                             serverDocStatus: "incomplete")]
    eq("shift id dedupes when a visit id is missing", s.incompleteNoteVisits.count, 1)
}

print("[G] HISTORY CONTRIBUTES ONLY PREVIOUS DATES")
do {
    let s = AppState()
    s.mode = .server
    s.todayVisits = []
    // A visit dated TODAY that only exists in history must not be pulled in by
    // the past branch — Today's own rows are todayVisits' job, and letting both
    // branches claim today is how a double render creeps back in.
    s.historyVisits = [Visit(scheduledStart: day(0), status: .completed,
                             serverVisitId: "V-today-only",
                             serverDocStatus: "incomplete")]
    eq("today-dated history row is not added by the past branch", s.incompleteNoteVisits.count, 0)
}

print("[H] MOCK MODE STILL USES pastVisits (the demo must keep working)")
do {
    let s = AppState()
    s.mode = .mock
    s.pastVisits = [Visit(scheduledStart: day(-1), status: .completed, docComplete: false)]
    s.historyVisits = []   // never populated in mock mode
    eq("mock mode reads pastVisits", s.incompleteNoteVisits.count, 1)
}
do {
    // And mock mode must NOT read history.
    let s = AppState()
    s.mode = .mock
    s.pastVisits = []
    s.historyVisits = [Visit(scheduledStart: day(-1), status: .completed,
                             serverDocStatus: "incomplete")]
    eq("mock mode ignores historyVisits", s.incompleteNoteVisits.count, 0)
}

print("[I] STATUS + docComplete GATES STILL HOLD")
do {
    let s = AppState()
    s.mode = .server
    s.historyVisits = [
        Visit(scheduledStart: day(-1), status: .inProgress,
              serverVisitId: "V-ip", serverDocStatus: "incomplete"),
        Visit(scheduledStart: day(-2), status: .missed,
              serverVisitId: "V-miss", serverDocStatus: "incomplete"),
        Visit(scheduledStart: day(-3), status: .scheduled,
              serverVisitId: "V-sched", serverDocStatus: "incomplete"),
    ]
    eq("only COMPLETED visits owe documentation", s.incompleteNoteVisits.count, 0)
}
do {
    let s = AppState()
    s.mode = .server
    s.historyVisits = [Visit(scheduledStart: day(-1), status: .completed,
                             docComplete: true, serverVisitId: "V-local-done",
                             serverDocStatus: "incomplete")]
    // An optimistic local completion (markServerDocComplete) clears the card
    // immediately, even before the server refresh lands.
    eq("a locally-completed note clears at once", s.incompleteNoteVisits.count, 0)
}

print("[J] NEWEST FIRST")
do {
    let s = AppState()
    s.mode = .server
    s.todayVisits = [Visit(scheduledStart: day(0), status: .completed,
                           serverVisitId: "V-0", serverDocStatus: "incomplete")]
    s.historyVisits = [
        Visit(scheduledStart: day(-7), status: .completed,
              serverVisitId: "V-7", serverDocStatus: "incomplete"),
        Visit(scheduledStart: day(-1), status: .completed,
              serverVisitId: "V-1", serverDocStatus: "incomplete"),
        Visit(scheduledStart: day(-3), status: .completed,
              serverVisitId: "V-3", serverDocStatus: "incomplete"),
    ]
    eq("sorted newest first", s.incompleteNoteVisits.map { $0.serverVisitId ?? "?" },
       ["V-0", "V-1", "V-3", "V-7"])
}

print("[K] A NIL docStatus IS TREATED AS INCOMPLETE (never silently dropped)")
do {
    // A row the server has no note_status for still needs a human to look at
    // it; swallowing it is how documentation debt goes invisible.
    let s = AppState()
    s.mode = .server
    s.historyVisits = [Visit(scheduledStart: day(-1), status: .completed,
                             serverVisitId: "V-nil", serverDocStatus: nil)]
    eq("nil docStatus is still listed", s.incompleteNoteVisits.count, 1)
}

print("[L] EMPTY EVERYTHING → NO CARDS (no empty-state clutter)")
do {
    let s = AppState()
    s.mode = .server
    eq("nothing incomplete → no rows", s.incompleteNoteVisits.count, 0)
}

print("[M] REAL PROD SHAPE — S203's last 8 days, exactly as RDS holds them")
do {
    // V-2070 complete (today), V-2069 incomplete (9/14), the rest complete.
    // Only ONE card must render, and it must be V-2069.
    let s = AppState()
    s.mode = .server
    s.todayVisits = [Visit(client: ShimClient(name: "Ray Varner"),
                           scheduledStart: day(0), status: .completed,
                           docComplete: true, serverVisitId: "V-2070",
                           serverShiftId: 1070, serverDocStatus: "complete")]
    s.pastVisits = []
    s.historyVisits = [
        Visit(scheduledStart: day(0),  status: .completed, serverVisitId: "V-2070", serverShiftId: 1070, serverDocStatus: "complete"),
        Visit(scheduledStart: day(-1), status: .completed, serverVisitId: "V-2069", serverShiftId: 1069, serverDocStatus: "incomplete"),
        Visit(scheduledStart: day(-2), status: .completed, serverVisitId: "V-2068", serverShiftId: 1068, serverDocStatus: "complete"),
        Visit(scheduledStart: day(-3), status: .completed, serverVisitId: "V-2067", serverShiftId: 1067, serverDocStatus: "complete"),
        Visit(scheduledStart: day(-4), status: .completed, serverVisitId: "V-2065", serverShiftId: 1065, serverDocStatus: "complete"),
        Visit(scheduledStart: day(-5), status: .completed, serverVisitId: "V-2062", serverShiftId: 1062, serverDocStatus: "complete"),
        Visit(scheduledStart: day(-6), status: .completed, serverVisitId: "V-2058", serverShiftId: 1058, serverDocStatus: "complete"),
        Visit(scheduledStart: day(-7), status: .completed, serverVisitId: "V-2059", serverShiftId: 1059, serverDocStatus: "complete"),
    ]
    let got = s.incompleteNoteVisits
    eq("exactly one card from the real 8-day window", got.count, 1)
    eq("and it is the 9/14 row Nick reported missing", got.first?.serverVisitId ?? "none", "V-2069")
}

print("[N] 14-DAY HORIZON IS THE SERVER'S — anything it returns is rendered")
do {
    let s = AppState()
    s.mode = .server
    s.historyVisits = (1...14).map {
        Visit(scheduledStart: day(-$0), status: .completed,
              serverVisitId: "V-\($0)", serverDocStatus: "incomplete")
    }
    eq("all 14 days of debt are shown (no client-side cutoff)",
       s.incompleteNoteVisits.count, 14)
}

print("")
print("incomplete-notes selector: \(pass) passed, \(fail) failed")
exit(fail == 0 ? 0 : 1)
