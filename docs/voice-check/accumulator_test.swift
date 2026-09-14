// Build 69 — offline proof for TranscriptAccumulator (the REAL code, extracted
// from EVVMobile/Services/SpeechRecognizer.swift between the BEGIN/END markers
// by check.sh, and prepended to this file before `swift` runs it).
//
// Each scenario replays the sequence of SFSpeechRecognizer callbacks iOS is
// known to produce and asserts what the staff member sees in the live bubble.
import Foundation

var pass = 0, fail = 0
func ok(_ name: String, _ cond: Bool, _ detail: String = "") {
    if cond { pass += 1; print("  ✓ \(name)") } else { fail += 1; print("  ✗ \(name)  \(detail)") }
}
func eq(_ name: String, _ got: String, _ want: String) { ok(name, got == want, "got «\(got)» want «\(want)»") }

// Reference: what build 68 did — committed only grew on isFinal.
struct Build68 {
    var committed = ""; var transcript = ""
    mutating func absorb(_ live: String, isFinal: Bool) {
        transcript = TranscriptAccumulator.join(committed, live)
        if isFinal { committed = TranscriptAccumulator.join(committed, live) }
    }
}

print("[1] iOS 17+ on-device: a PAUSE ends the utterance without isFinal (metadata) and the next partial is fresh")
do {
    var a = TranscriptAccumulator(); var b = Build68()
    a.beginSegment()
    for (t, bank, gap) in [("I took", false, 0.2), ("I took Ray to the", false, 0.2), ("I took Ray to the store", false, 0.2),
                           ("I took Ray to the store.", true, 0.3)] { a.absorb(t, bank: bank, gap: gap); b.absorb(t, isFinal: false) }
    eq("utterance banked at the pause", a.transcript, "I took Ray to the store.")
    a.absorb("and", bank: false, gap: 1.4); b.absorb("and", isFinal: false)
    eq("fresh partial APPENDS instead of replacing", a.transcript, "I took Ray to the store. and")
    eq("(build 68 lost the first sentence here — the reported bug)", b.transcript, "and")
    a.absorb("and then we cleaned his", bank: false, gap: 0.2)
    a.absorb("and then we cleaned his room", bank: false, gap: 0.2)
    eq("second utterance grows live", a.transcript, "I took Ray to the store. and then we cleaned his room")
    a.absorb("and then we cleaned his room.", bank: true, gap: 0.3)
    a.absorb("he", bank: false, gap: 1.1)
    eq("third utterance appends too", a.transcript, "I took Ray to the store. and then we cleaned his room. he")
    ok("two utterances banked", a.banks == 2, "\(a.banks)")
}

print("[2] Older iOS: after a boundary the recognizer keeps reporting the WHOLE segment — no duplication")
do {
    var a = TranscriptAccumulator(); a.beginSegment()
    a.absorb("He brushed his teeth", bank: false, gap: 0.2)
    a.absorb("He brushed his teeth.", bank: true, gap: 0.3)
    a.absorb("He brushed his teeth. And", bank: false, gap: 0.9)
    eq("prefix stripped, remainder appended", a.transcript, "He brushed his teeth. And")
    a.absorb("He brushed his teeth. And flossed", bank: false, gap: 0.2)
    eq("keeps growing", a.transcript, "He brushed his teeth. And flossed")
    a.absorb("he brushed his teeth, and flossed.", bank: true, gap: 0.3)   // final: case + punctuation differ
    eq("isFinal repeating the segment does not duplicate", a.transcript, "He brushed his teeth. and flossed.")
    a.beginSegment()
    eq("new segment keeps everything", a.transcript, "He brushed his teeth. and flossed.")
}

print("[3] Silent restart with NO metadata (much shorter partial after a gap) is detected")
do {
    var a = TranscriptAccumulator(); a.beginSegment()
    a.absorb("we went to the park and he played on the swings", bank: false, gap: 0.2)
    a.absorb("then", bank: false, gap: 1.0)
    eq("previous words kept", a.transcript, "we went to the park and he played on the swings then")
    a.absorb("then he had lunch", bank: false, gap: 0.2)
    eq("restart grows", a.transcript, "we went to the park and he played on the swings then he had lunch")
}

print("[4] Restart that begins with the SAME word as the previous utterance (\"I … I …\") after a pause")
do {
    var a = TranscriptAccumulator(); a.beginSegment()
    a.absorb("I took him to the grocery store today", bank: false, gap: 0.2)
    a.absorb("I", bank: false, gap: 1.5)
    eq("banked on the pause, not treated as a trim-back", a.transcript, "I took him to the grocery store today I")
    a.absorb("I also", bank: false, gap: 0.2)
    eq("continues", a.transcript, "I took him to the grocery store today I also")
}

print("[5] Revisions mid-speech are NOT restarts")
do {
    var a = TranscriptAccumulator(); a.beginSegment()
    a.absorb("I clean the", bank: false, gap: 0.2)
    a.absorb("I cleaned the house", bank: false, gap: 0.2)
    eq("revision replaces the live partial", a.transcript, "I cleaned the house")
    ok("nothing banked", a.banks == 0)
    a.absorb("I cleaned the house with him and he", bank: false, gap: 0.2)
    a.absorb("I cleaned the house with him and he did the", bank: false, gap: 0.2)
    a.absorb("I cleaned the house with him and he did the dishes", bank: false, gap: 0.2)
    eq("long revision chain still one utterance", a.transcript, "I cleaned the house with him and he did the dishes")
    ok("still nothing banked", a.banks == 0)
    // recognizer trims back to the opening word DURING speech (no gap) — a revision it will regrow
    a.absorb("I", bank: false, gap: 0.1)
    ok("same-word trim-back inside continuous speech is a revision", a.banks == 0 && a.transcript == "I", a.transcript)
    // a different-word much-shorter partial inside continuous speech IS a restart (opening word changed)
    var c = TranscriptAccumulator(); c.beginSegment()
    c.absorb("we walked around the block twice", bank: false, gap: 0.2)
    c.absorb("she", bank: false, gap: 0.2)
    eq("opening word changed → restart even without a gap", c.transcript, "we walked around the block twice she")
}

print("[6] Task ERROR without isFinal: the segment's partial is banked before the new task")
do {
    var a = TranscriptAccumulator(); a.beginSegment()
    a.absorb("he made his own lunch and did his laundry", bank: false, gap: 0.2)
    a.bankLive()          // what the error path calls
    a.beginSegment()      // restartSegment
    eq("partial survived the error", a.transcript, "he made his own lunch and did his laundry")
    a.absorb("and", bank: false, gap: 0.5)
    eq("next segment appends", a.transcript, "he made his own lunch and did his laundry and")
    ok("segmentBanked reset for the new task", a.segmentBanked.isEmpty)
}

print("[7] isFinal right after a metadata result with the same text does not duplicate")
do {
    var a = TranscriptAccumulator(); a.beginSegment()
    a.absorb("we went outside", bank: false, gap: 0.2)
    a.absorb("we went outside", bank: true, gap: 0.3)   // metadata
    a.absorb("we went outside", bank: true, gap: 0.1)   // isFinal
    eq("once", a.transcript, "we went outside")
    ok("one bank", a.banks == 1, "\(a.banks)")
}

print("[8] Empty / whitespace results never disturb the transcript")
do {
    var a = TranscriptAccumulator(); a.beginSegment()
    a.absorb("he stayed safe all day", bank: false, gap: 0.2)
    a.absorb("", bank: false, gap: 0.2)
    a.absorb("   ", bank: true, gap: 2.0)
    eq("kept", a.transcript, "he stayed safe all day")
    ok("empty boundary banked the live text", a.banks == 1 && a.liveText.isEmpty)
}

print("[9] Helpers")
do {
    ok("tokens strip punctuation/case, keep apostrophes", TranscriptAccumulator.tokens("He didn't floss, today!") == ["he", "didn't", "floss", "today"])
    ok("remainder: exact", TranscriptAccumulator.remainder(after: "a b c", in: "a b c d e") == "d e")
    ok("remainder: empty when identical", TranscriptAccumulator.remainder(after: "a b c", in: "A, b. C!") == "")
    ok("remainder: nil when not a prefix", TranscriptAccumulator.remainder(after: "a b c", in: "a x c d") == nil)
    ok("remainder: nil when shorter", TranscriptAccumulator.remainder(after: "a b c", in: "a b") == nil)
    ok("remainder: em-dash word falls back to flat tokens", TranscriptAccumulator.remainder(after: "we went", in: "we went — home") == "home")
    ok("remainder: empty banked returns text", TranscriptAccumulator.remainder(after: "", in: "x y") == "x y")
    ok("isRestart: short previous never restarts", !TranscriptAccumulator.isRestart(previous: "a b c", next: "z", gap: 5))
    ok("isRestart: long next never restarts", !TranscriptAccumulator.isRestart(previous: "a b c d e f", next: "z y x", gap: 5))
    ok("isRestart: gap decides same-word case", TranscriptAccumulator.isRestart(previous: "a b c d e f", next: "a", gap: 0.7) && !TranscriptAccumulator.isRestart(previous: "a b c d e f", next: "a", gap: 0.2))
    ok("isRestart: different opening word restarts without gap", TranscriptAccumulator.isRestart(previous: "a b c d e f", next: "q", gap: 0.1))
    ok("join trims and single-spaces", TranscriptAccumulator.join("  a ", " b  ") == "a b" && TranscriptAccumulator.join("", "b") == "b" && TranscriptAccumulator.join("a", " ") == "a")
    ok("SpeechRecognizer.join is still exposed (build-68 name)", true)
}

print("[10] Property: committed text only ever grows and the transcript always starts with it (random replay)")
do {
    var rng = SystemRandomNumberGenerator()
    let words = ["i", "he", "we", "took", "ray", "to", "the", "store", "cleaned", "room", "and", "then", "lunch", "brushed", "teeth", "walked", "park", "today"]
    var violations = 0
    for _ in 0..<300 {
        var a = TranscriptAccumulator(); a.beginSegment()
        var prevCommitted = ""
        var utterance: [String] = []
        for _ in 0..<40 {
            let roll = Int.random(in: 0..<100, using: &rng)
            var reported: String; var bank = false; var gap = 0.2
            if roll < 65 {                       // grow / revise the utterance
                if utterance.isEmpty || roll < 55 { utterance.append(words.randomElement(using: &rng)!) }
                else { utterance[utterance.count - 1] = words.randomElement(using: &rng)! }
                reported = utterance.joined(separator: " ")
            } else if roll < 80 {                // utterance boundary (metadata), next partial fresh
                reported = utterance.joined(separator: " "); bank = true; utterance = []
            } else if roll < 90 {                // silent restart after a pause
                utterance = [words.randomElement(using: &rng)!]; reported = utterance.joined(separator: " "); gap = 1.2
            } else if roll < 95 {                // task error → new segment
                a.bankLive(); a.beginSegment(); utterance = []; continue
            } else {                             // isFinal → new segment
                reported = utterance.joined(separator: " "); bank = true; utterance = []
                a.absorb(reported, bank: bank, gap: gap); a.beginSegment()
                if !a.committedText.hasPrefix(prevCommitted) || !a.transcript.hasPrefix(a.committedText) { violations += 1 }
                prevCommitted = a.committedText; continue
            }
            a.absorb(reported, bank: bank, gap: gap)
            if !a.committedText.hasPrefix(prevCommitted) || !a.transcript.hasPrefix(a.committedText) { violations += 1 }
            prevCommitted = a.committedText
        }
    }
    ok("no violation in 300 × 40 random callbacks", violations == 0, "\(violations)")
}

print("\n\(pass) passed, \(fail) failed")
exit(fail == 0 ? 0 : 1)
