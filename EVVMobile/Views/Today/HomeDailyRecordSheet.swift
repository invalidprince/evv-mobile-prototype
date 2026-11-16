import SwiftUI

// MARK: - CLA daily record (build 124, server v0.4.821)
//
// The web dashboard documents a group-home (CLA) shift per resident per day:
// visit questions, ISP outcomes for each goal, community activities, absences
// and — when the resident needs a nurse — nurse notes. Until build 124 the app
// only offered a free-text shift note; this sheet is the same record the web
// shows at /homes/:id/residents/:cid/days/:date, written through the same
// server ops, so a phone-written day looks identical on the dashboard.

// MARK: Wire shapes (tolerant: the dashboard adds fields freely)

struct HomeDailyRecord: Decodable {
    struct Ref: Decodable { let id: String; let name: String }
    struct Absence: Decodable, Identifiable {
        let id: Int
        let start: String?
        let end: String?
        let kindLabel: String?
        let reason: String?
        let authorName: String?
    }
    struct OutcomeEntry: Decodable, Identifiable {
        let id: Int
        let goalId: Int
        let provided: Bool
        let note: String?
        let why: String?
        let authorName: String?
    }
    struct Goal: Decodable, Identifiable {
        let id: Int
        let title: String
        let description: String?
        let instructions: String?
        let entries: [OutcomeEntry]
    }
    struct Activity: Decodable, Identifiable {
        let id: Int
        let description: String
        let authorName: String?
    }
    struct NurseNote: Decodable, Identifiable {
        let id: Int
        let noteTime: String?
        let body: String
        let authorName: String?
    }
    struct Answers: Decodable {
        struct Entry: Decodable {
            let questionId: Int
            let answer: String?
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                if let i = try? c.decode(Int.self, forKey: .questionId) { questionId = i }
                else if let s = try? c.decode(String.self, forKey: .questionId), let i = Int(s) { questionId = i }
                else { questionId = 0 }
                if let s = try? c.decode(String.self, forKey: .answer) { answer = s }
                else if let b = try? c.decode(Bool.self, forKey: .answer) { answer = b ? "yes" : "no" }
                else if let n = try? c.decode(Double.self, forKey: .answer) { answer = String(n) }
                else { answer = nil }
            }
            enum CodingKeys: String, CodingKey { case questionId, answer }
        }
        let questionAnswers: [Entry]
        let authorName: String?
    }
    struct Kind: Decodable, Identifiable {
        let key: String
        let label: String
        let help: String?
        var id: String { key }
    }

    let home: Ref
    let client: Ref
    let date: String
    let today: String?
    let isFuture: Bool?
    let absences: [Absence]
    let goals: [Goal]
    let activities: [Activity]
    let questions: [ServerDocQuestion]
    let answers: Answers?
    let nurseRequired: Bool?
    let nurseNotes: [NurseNote]
    let canWriteNurseNotes: Bool?
    let kinds: [Kind]

    enum CodingKeys: String, CodingKey {
        case home, client, date, today, isFuture, absences, goals, activities, questions, answers, nurseRequired, nurseNotes, canWriteNurseNotes, kinds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        home = try c.decode(Ref.self, forKey: .home)
        client = try c.decode(Ref.self, forKey: .client)
        date = try c.decode(String.self, forKey: .date)
        today = try? c.decodeIfPresent(String.self, forKey: .today)
        isFuture = try? c.decodeIfPresent(Bool.self, forKey: .isFuture)
        absences = ((try? c.decode([FailableDecodable<Absence>].self, forKey: .absences)) ?? []).compactMap { $0.value }
        goals = ((try? c.decode([FailableDecodable<Goal>].self, forKey: .goals)) ?? []).compactMap { $0.value }
        activities = ((try? c.decode([FailableDecodable<Activity>].self, forKey: .activities)) ?? []).compactMap { $0.value }
        questions = ((try? c.decode([FailableDecodable<ServerDocQuestion>].self, forKey: .questions)) ?? []).compactMap { $0.value }
        answers = try? c.decodeIfPresent(Answers.self, forKey: .answers)
        nurseRequired = try? c.decodeIfPresent(Bool.self, forKey: .nurseRequired)
        nurseNotes = ((try? c.decode([FailableDecodable<NurseNote>].self, forKey: .nurseNotes)) ?? []).compactMap { $0.value }
        canWriteNurseNotes = try? c.decodeIfPresent(Bool.self, forKey: .canWriteNurseNotes)
        kinds = ((try? c.decode([FailableDecodable<Kind>].self, forKey: .kinds)) ?? []).compactMap { $0.value }
    }
}

/// 400 bodies from the daily-record routes: { reason, error, missing?: [question text] }.
struct HomeDailyRecordError: Decodable {
    let reason: String?
    let error: String?
    let missing: [String]?
}

/// Which resident/day the sheet is for. `date` is "today" for the open shift.
struct HomeDailyRecordTarget: Identifiable, Hashable {
    let homeId: String
    let homeName: String
    let clientId: String
    let clientName: String
    let date: String
    var id: String { "\(homeId)|\(clientId)|\(date)" }
}

// MARK: - Sheet

struct HomeDailyRecordSheet: View {
    let target: HomeDailyRecordTarget
    private let api = APIClient.shared
    @Environment(\.dismiss) private var dismiss

    @State private var record: HomeDailyRecord?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var busy = false
    @State private var errorText: String?
    @State private var savedFlash: String?

    // Visit questions
    @State private var answers: [Int: String?] = [:]
    @State private var answersDirty = false
    // ISP outcome composer (one goal at a time)
    @State private var outcomeGoal: HomeDailyRecord.Goal?
    @State private var outcomeProvided = true
    @State private var outcomeText = ""
    // Community activity
    @State private var activityText = ""
    // Absence
    @State private var absenceKind = "outside_services"
    @State private var absenceStart = Date()
    @State private var absenceEnd = Date()
    @State private var absenceReason = ""
    // Nurse note
    @State private var nurseText = ""
    @State private var nurseTime = Date()

    private var questions: [ServerDocQuestion] { record?.questions ?? [] }
    private var editable: Bool { !(record?.isFuture ?? false) }
    private var canNurse: Bool { (record?.nurseRequired ?? false) && (record?.canWriteNurseNotes ?? false) }

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading daily record…")
                } else if let loadError {
                    VStack(spacing: 12) {
                        Text(loadError).foregroundColor(Theme.danger).multilineTextAlignment(.center)
                        Button("Try again") { Task { await load() } }
                    }.padding()
                } else {
                    form
                }
            }
            .navigationTitle(target.clientName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task { await load() }
            .sheet(item: $outcomeGoal) { goal in outcomeComposer(goal) }
        }
    }

    // MARK: Form

    private var form: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(target.homeName).font(.headline)
                    Text(dateLabel).font(.subheadline).foregroundColor(.secondary)
                    if !editable { Text("This day hasn't happened yet.").font(.footnote).foregroundColor(Theme.danger) }
                }
                if let savedFlash {
                    Label(savedFlash, systemImage: "checkmark.circle.fill").foregroundColor(Theme.primary).font(.subheadline)
                }
                if let errorText {
                    Text(errorText).foregroundColor(Theme.danger).font(.subheadline)
                }
            }

            questionsSection
            outcomesSection
            activitiesSection
            absencesSection
            if record?.nurseRequired == true { nurseSection }
        }
        .disabled(busy)
    }

    private var dateLabel: String {
        guard let d = record?.date else { return target.date }
        let inF = DateFormatter(); inF.dateFormat = "yyyy-MM-dd"
        let outF = DateFormatter(); outF.dateStyle = .full
        if let date = inF.date(from: d) { return outF.string(from: date) }
        return d
    }

    // Visit questions — same cards as the visit documentation screen.
    private var questionsSection: some View {
        Section(header: Text("Visit questions"),
                footer: questions.isEmpty ? Text("No visit questions are set up for this resident.") : (unansweredRequired.isEmpty ? nil : Text("Required questions are marked; answer them to save.").foregroundColor(Theme.danger))) {
            ForEach(questions) { q in
                VisitQuestionCard(question: q, answer: answerBinding(for: q.id))
                    .disabled(!editable)
            }
            if !questions.isEmpty {
                Button(busy ? "Saving…" : (answersDirty ? "Save answers" : "Answers saved")) { Task { await saveAnswers() } }
                    .disabled(!editable || busy || !answersDirty || !unansweredRequired.isEmpty)
                if let who = record?.answers?.authorName, !answersDirty {
                    Text("Last saved by \(who)").font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    // ISP outcomes — one entry per goal per shift, provided + note or why not.
    private var outcomesSection: some View {
        Section(header: Text("ISP outcomes"), footer: (record?.goals.isEmpty ?? true) ? Text("No active goals on this resident's plan.") : Text("Record each outcome you worked on this shift — what you did, or why it wasn't provided.")) {
            ForEach(record?.goals ?? []) { goal in
                VStack(alignment: .leading, spacing: 6) {
                    Text(goal.title).font(.subheadline.weight(.semibold))
                    if let d = goal.description, !d.isEmpty { Text(d).font(.caption).foregroundColor(.secondary) }
                    ForEach(goal.entries) { e in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: e.provided ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundColor(e.provided ? Theme.primary : Theme.danger)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.provided ? (e.note ?? "") : "Not provided: \(e.why ?? "")").font(.caption)
                                if let a = e.authorName { Text(a).font(.caption2).foregroundColor(.secondary) }
                            }
                        }
                    }
                    if editable {
                        Button("Add outcome") {
                            outcomeProvided = true; outcomeText = ""; outcomeGoal = goal
                        }.font(.subheadline)
                    }
                }.padding(.vertical, 2)
            }
        }
    }

    private func outcomeComposer(_ goal: HomeDailyRecord.Goal) -> some View {
        NavigationView {
            Form {
                Section(header: Text(goal.title)) {
                    if let i = goal.instructions, !i.isEmpty { Text(i).font(.caption).foregroundColor(.secondary) }
                    Picker("Outcome", selection: $outcomeProvided) {
                        Text("Provided").tag(true)
                        Text("Not provided").tag(false)
                    }.pickerStyle(.segmented)
                }
                Section(header: Text(outcomeProvided ? "What happened" : "Why not")) {
                    TextEditor(text: $outcomeText).frame(minHeight: 120)
                }
                if let errorText { Section { Text(errorText).foregroundColor(Theme.danger).font(.subheadline) } }
            }
            .navigationTitle("ISP outcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { outcomeGoal = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Saving…" : "Save") { Task { await saveOutcome(goal) } }
                        .disabled(busy || outcomeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var activitiesSection: some View {
        Section(header: Text("Community activities")) {
            ForEach(record?.activities ?? []) { a in
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.description).font(.subheadline)
                    if let who = a.authorName { Text(who).font(.caption2).foregroundColor(.secondary) }
                }
            }
            if editable {
                TextField("Where did they go / what did they do?", text: $activityText)
                Button(busy ? "Saving…" : "Add activity") { Task { await saveActivity() } }
                    .disabled(busy || activityText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var absencesSection: some View {
        Section(header: Text("Time away from the home"), footer: Text("Outside services (day program, work, school, appointments) or any other time the resident wasn't at the home.")) {
            ForEach(record?.absences ?? []) { ab in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ab.start ?? "?") – \(ab.end ?? "?")  \(ab.kindLabel ?? "")").font(.subheadline)
                    if let r = ab.reason, !r.isEmpty { Text(r).font(.caption).foregroundColor(.secondary) }
                }
            }
            if editable {
                Picker("Type", selection: $absenceKind) {
                    ForEach(record?.kinds ?? [HomeDailyRecord.Kind(key: "outside_services", label: "Outside services", help: nil), HomeDailyRecord.Kind(key: "other", label: "Other", help: nil)]) { k in
                        Text(k.label).tag(k.key)
                    }
                }
                DatePicker("Left", selection: $absenceStart, displayedComponents: .hourAndMinute)
                DatePicker("Returned", selection: $absenceEnd, displayedComponents: .hourAndMinute)
                TextField(absenceKind == "other" ? "Reason (required)" : "Reason (optional)", text: $absenceReason)
                Button(busy ? "Saving…" : "Add time away") { Task { await saveAbsence() } }
                    .disabled(busy || (absenceKind == "other" && absenceReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
    }

    private var nurseSection: some View {
        Section(header: Text("Nurse notes"), footer: canNurse ? nil : Text("This resident needs a nurse. Only nursing staff can write here.")) {
            ForEach(record?.nurseNotes ?? []) { n in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        if let t = n.noteTime, !t.isEmpty { Text(t).font(.caption.weight(.semibold)) }
                        if let who = n.authorName { Text(who).font(.caption2).foregroundColor(.secondary) }
                    }
                    Text(n.body).font(.subheadline)
                }
            }
            if editable && canNurse {
                DatePicker("Time", selection: $nurseTime, displayedComponents: .hourAndMinute)
                TextEditor(text: $nurseText).frame(minHeight: 90)
                Button(busy ? "Saving…" : "Add nurse note") { Task { await saveNurseNote() } }
                    .disabled(busy || nurseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: Questions helpers (same rule as the visit documentation screen)

    private func answerBinding(for id: Int) -> Binding<String?> {
        Binding(get: { answers[id] ?? nil }, set: { answers[id] = $0; answersDirty = true; savedFlash = nil })
    }

    private func isAnswered(_ q: ServerDocQuestion) -> Bool {
        guard let raw = answers[q.id] ?? nil else { return false }
        if q.type == "checkbox" { return !VisitQuestionCard.decodeCheckboxSelections(raw).isEmpty }
        return !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var unansweredRequired: [ServerDocQuestion] { questions.filter { $0.required && !isAnswered($0) } }

    // MARK: Loading / saving

    private func load() async {
        isLoading = record == nil
        loadError = nil
        do {
            let r = try await api.homeDailyRecord(homeId: target.homeId, clientId: target.clientId, date: target.date)
            record = r
            var map: [Int: String?] = [:]
            for e in r.answers?.questionAnswers ?? [] where e.questionId > 0 { map[e.questionId] = e.answer }
            // Server defaults for untouched questions, like the visit screen.
            for q in r.questions where map[q.id] == nil { if let d = q.defaultValue, !d.isEmpty { map[q.id] = d } }
            answers = map
            answersDirty = false
        } catch {
            loadError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    private func run(_ what: String, _ op: () async throws -> Void) async {
        busy = true; errorText = nil; savedFlash = nil
        do {
            try await op()
            savedFlash = what
            await load()
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        busy = false
    }

    private static let hhmm: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()

    private func saveAnswers() async {
        let payload = questions.map { HomeNoteAnswerPayload(questionId: $0.id, answer: (answers[$0.id] ?? nil) ?? "") }
        await run("Answers saved") {
            try await api.saveHomeDailyAnswers(homeId: target.homeId, clientId: target.clientId, date: target.date, answers: payload)
        }
    }

    private func saveOutcome(_ goal: HomeDailyRecord.Goal) async {
        let text = outcomeText.trimmingCharacters(in: .whitespacesAndNewlines)
        await run("Outcome saved") {
            try await api.addHomeDailyOutcome(homeId: target.homeId, clientId: target.clientId, date: target.date, goalId: goal.id, provided: outcomeProvided, note: outcomeProvided ? text : "", why: outcomeProvided ? "" : text)
        }
        if errorText == nil { outcomeGoal = nil; outcomeText = "" }
    }

    private func saveActivity() async {
        let text = activityText.trimmingCharacters(in: .whitespacesAndNewlines)
        await run("Activity saved") {
            try await api.addHomeDailyActivity(homeId: target.homeId, clientId: target.clientId, date: target.date, description: text)
        }
        if errorText == nil { activityText = "" }
    }

    private func saveAbsence() async {
        await run("Time away saved") {
            try await api.addHomeDailyAbsence(homeId: target.homeId, clientId: target.clientId, date: target.date, kind: absenceKind, startTime: Self.hhmm.string(from: absenceStart), endTime: Self.hhmm.string(from: absenceEnd), reason: absenceReason.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if errorText == nil { absenceReason = "" }
    }

    private func saveNurseNote() async {
        let text = nurseText.trimmingCharacters(in: .whitespacesAndNewlines)
        await run("Nurse note saved") {
            try await api.addHomeDailyNurseNote(homeId: target.homeId, clientId: target.clientId, date: target.date, body: text, noteTime: Self.hhmm.string(from: nurseTime))
        }
        if errorText == nil { nurseText = "" }
    }
}
