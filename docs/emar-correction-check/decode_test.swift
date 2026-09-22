import Foundation
// Decodes a REAL /api/me/medications payload shape (v0.4.533) with the REAL structs.
let path = CommandLine.arguments[1]
let data = try! Data(contentsOf: URL(fileURLWithPath: path))
let r = try! JSONDecoder().decode(MedicationsResponse.self, from: data)
var n = 0
func ok(_ c: Bool, _ l: String) { if c { n += 1 } else { print("FAIL", l); exit(1) } }
ok(r.due.count == 3, "three due rows")
ok(r.correctable?.count == 1, "one earlier dose")
ok(r.correctionWindowHours == 48, "48h window")
ok(r.canCorrectAny == true, "canCorrectAny")
let missed = r.due[1]
ok(missed.offersCorrection, "missed today → Correct button")
ok(!r.due[0].offersCorrection, "pending live row → no Correct (recordable)")
ok(missed.isCorrection == false, "marker false on a first record")
let e = r.correctable![0]
ok(e.dateLabel == "Tue 9/15" && e.date == "2026-09-15", "earlier row date fields")
ok(e.scheduledInstant != nil, "scheduled instant parses in agency tz")
let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]; iso.timeZone = TimeZone(identifier: "America/New_York")
ok(iso.string(from: e.scheduledInstant!) == "2026-09-15T20:00:00-04:00", "2026-09-15 20:00 ET → -04:00 ISO")
// old-server payload (no new keys) still decodes
let old = """
{"due":[{"id":1,"clientId":"C1","clientName":"A","medName":"M","status":"missed","late":false,"recordable":false}],"prnMeds":[],"enabledClientIds":["C1"]}
""".data(using: .utf8)!
let o = try! JSONDecoder().decode(MedicationsResponse.self, from: old)
ok(o.correctable == nil && !o.due[0].offersCorrection, "old server: no Correct button, no crash")
// body encodes given_at only when present
let body = try! JSONEncoder().encode(CorrectAdministrationBody(action: "held", notes: "x", given_at: nil, on_behalf_staff_id: nil))
ok(!String(data: body, encoding: .utf8)!.contains("2026"), "held body has no time")
// build 74 — on-behalf choices decode; absent on old servers
ok(r.canRecordForOthers == true && r.onBehalfStaff?.count == 2 && r.onBehalfStaff?[0].id == "S102", "canRecordForOthers + 2 staff choices")
ok(o.canRecordForOthers == nil && o.onBehalfStaff == nil, "old server: no picker keys, no crash")
let body2 = try! JSONEncoder().encode(CorrectAdministrationBody(action: "given", notes: "x", given_at: "2026-09-15T20:00:00-04:00", on_behalf_staff_id: "S102"))
ok(String(data: body2, encoding: .utf8)!.contains("\"on_behalf_staff_id\":\"S102\""), "on-behalf body carries the staff id")
// build 85 / server v0.4.613 — the ADMINISTERED time is displayed (Nick 2026-09-22: corrected
// a 10:35 dose to "given 10:30", row kept reading 10:35 because the payload never carried it)
let corrected = r.due[2]
ok(corrected.givenAtLabel == "10:30 AM" && corrected.givenAt == "2026-09-16T14:30:00.000Z", "given row decodes givenAt + givenAtLabel")
ok(corrected.administeredChip == "given 10:30 AM", "row chip = 'given 10:30 AM' (differs from the 10:35 slot)")
ok(corrected.givenAtInstant != nil && iso.string(from: corrected.givenAtInstant!) == "2026-09-16T10:30:00-04:00", "givenAtInstant parses the fractional-seconds ISO into 10:30 ET (picker default)")
ok(r.due[1].administeredChip == nil && r.due[1].givenAtInstant == nil, "missed row: no administered chip, no instant")
ok(e.administeredChip == "given Sep 15, 8:05 PM", "earlier given row carries the server label verbatim (next-day label incl. date)")
ok(o.due[0].givenAt == nil && o.due[0].givenAtLabel == nil && o.due[0].administeredChip == nil, "old server: no givenAt keys, no chip, no crash")
let sameSlot = try! JSONDecoder().decode(DueMedication.self, from: """
{"id":5,"clientId":"C1","clientName":"A","medName":"M","status":"given","late":false,"recordable":false,"dueTimeLabel":"8:00 AM","givenAtLabel":"8:00 AM"}
""".data(using: .utf8)!)
ok(sameSlot.administeredChip == nil, "given exactly on the slot → no redundant second clock")
print("\(n) decode checks passed")
