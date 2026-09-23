import Foundation

// Executed against the REAL DiagnosticLogger class, lifted verbatim from
// EVVMobile/Services/DiagnosticLogger.swift by check.sh (awk line-range, never
// a copy — so the test cannot drift from what ships).
//
// The real singleton writes to Application Support, which exists on macOS too,
// so these run for real: entries are appended, the process's view is dropped,
// and a SECOND process re-reads the file to prove the tail survived a kill.

var pass = 0, fail = 0
func ok(_ label: String, _ cond: @autoclosure () -> Bool) {
    if cond() { pass += 1; print("  ✓ \(label)") }
    else { fail += 1; print("  ✗ \(label)") }
}

let logURL = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    .appendingPathComponent("EVVCache", isDirectory: true)
    .appendingPathComponent("diagnostic-log.jsonl")

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "write"

// ---------------------------------------------------------------------------
// PHASE 2 — a SEPARATE process: prove the tail survived the "kill".
// ---------------------------------------------------------------------------
if mode == "reload" {
    print("[phase 2] fresh process — does the previous run's evidence come back?")
    let logger = DiagnosticLogger.shared
    let entries = logger.exportEntries()

    ok("previous process's entries were reloaded from disk (non-empty)", !entries.isEmpty)
    ok("the pre-crash marker entry survived", entries.contains { $0["message"] == "PRECRASH-MARKER-A" })
    ok("the last entry written before the kill survived", entries.contains { $0["message"] == "PRECRASH-MARKER-LAST" })
    ok("category is preserved across the restart", entries.first { $0["message"] == "PRECRASH-MARKER-A" }?["category"] == "api")
    ok("timestamps are preserved (ISO-8601, not regenerated at load)",
       (entries.first { $0["message"] == "PRECRASH-MARKER-A" }?["timestamp"] ?? "").hasPrefix("20"))

    // A truncated final line — what a real mid-write kill leaves behind —
    // must be skipped, not poison the load. check.sh appended one.
    ok("a truncated final line was skipped, earlier entries still loaded",
       entries.contains { $0["message"] == "PRECRASH-MARKER-LAST" })
    ok("the corrupt partial line did not decode into an entry",
       !entries.contains { ($0["message"] ?? "").contains("TRUNCATED-GARBAGE") })

    // Ordering: oldest first, so a submitted log reads chronologically.
    let stamps = entries.map { $0["timestamp"] ?? "" }
    ok("entries are ordered oldest-first", stamps == stamps.sorted())

    // markLaunch() is the relaunch boundary the submitted log needs.
    logger.markLaunch()
    let afterLaunch = logger.exportEntries()
    ok("markLaunch() appends a lifecycle boundary entry",
       afterLaunch.last?["category"] == "lifecycle")
    ok("the boundary entry says entries above are from a previous run",
       (afterLaunch.last?["message"] ?? "").contains("previous run"))
    ok("the boundary lands AFTER the restored pre-crash entries (so they read as pre-crash)",
       afterLaunch.firstIndex { $0["message"] == "PRECRASH-MARKER-A" }! <
       afterLaunch.firstIndex { $0["category"] == "lifecycle" }!)

    // clear() must wipe BOTH copies or every future submission re-sends.
    logger.clear()
    Thread.sleep(forTimeInterval: 0.3)
    ok("clear() empties the in-memory buffer", logger.entryCount == 0)
    let onDisk = (try? Data(contentsOf: logURL)) ?? Data()
    ok("clear() also empties the persisted file (no re-submission of old entries)", onDisk.isEmpty)

    print("")
    print("\(pass) passed, \(fail) failed")
    exit(fail == 0 ? 0 : 1)
}

// ---------------------------------------------------------------------------
// PHASE 1 — this process writes, then dies (check.sh re-invokes with "reload").
// ---------------------------------------------------------------------------
print("[phase 1] write entries, then die without a clean shutdown")
let logger = DiagnosticLogger.shared
logger.clear()
Thread.sleep(forTimeInterval: 0.3)

logger.logAPI("PRECRASH-MARKER-A")
logger.logSync("PRECRASH-MARKER-B")
logger.logOffline("PRECRASH-MARKER-C")
for i in 0..<40 { logger.logScreen("filler \(i)") }
logger.logAPI("PRECRASH-MARKER-LAST")
Thread.sleep(forTimeInterval: 0.5)

ok("entries are in the in-memory buffer", logger.entryCount == 44)
let written = (try? Data(contentsOf: logURL)) ?? Data()
ok("entries were flushed to disk IMMEDIATELY (no shutdown hook ran)", !written.isEmpty)
ok("the file is JSON-lines (one object per line)",
   String(data: written, encoding: .utf8)!
       .split(separator: "\n")
       .allSatisfy { $0.hasPrefix("{") && $0.hasSuffix("}") })
ok("the last entry written is already on disk before any exit",
   String(data: written, encoding: .utf8)!.contains("PRECRASH-MARKER-LAST"))

// Bounded ring: blow well past maxEntries and prove both caps hold.
for i in 0..<1200 { logger.logScreen("flood \(i) — padding to push the file past its byte cap \(String(repeating: "x", count: 200))") }
Thread.sleep(forTimeInterval: 2.0)
ok("in-memory buffer stays capped at maxEntries (500)", logger.entryCount == 500)
let flooded = (try? Data(contentsOf: logURL)) ?? Data()
ok("the file is trimmed, never unbounded (< 512 KB after 1,244 entries)", flooded.count < 512 * 1024)
ok("the newest entry survived the trim (a trim drops the OLDEST)",
   String(data: flooded, encoding: .utf8)!.contains("flood 1199"))
ok("the trim did not corrupt the file — every line still decodes",
   String(data: flooded, encoding: .utf8)!
       .split(separator: "\n")
       .allSatisfy { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) != nil })

// Re-seed the markers the reload phase looks for, then leave WITHOUT a
// clean shutdown — no close, no flush, nothing. Exactly like a watchdog kill.
logger.clear()
Thread.sleep(forTimeInterval: 0.3)
logger.logAPI("PRECRASH-MARKER-A")
logger.logSync("PRECRASH-MARKER-B")
logger.logAPI("PRECRASH-MARKER-LAST")
Thread.sleep(forTimeInterval: 0.5)

print("")
print("\(pass) passed, \(fail) failed")
exit(fail == 0 ? 0 : 1)
