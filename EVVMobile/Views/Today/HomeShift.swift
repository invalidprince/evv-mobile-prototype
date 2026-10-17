import SwiftUI
import CoreLocation

// Group home shifts — card 4 of epic 6hhHw5PWcCV3pM9q (Todoist 6hj3W5cRmFgCGr2q).
//
// Staff whose department includes a group home can clock in to the HOME
// (not a resident), pick a role (Main for <resident> / Assisting <resident> /
// Floater), see who else is on the clock, switch role mid-shift, document the
// shift, and clock out. Everything goes through the card-2 endpoints in
// APIClient (/api/homes, /home-punches/…). Online-only by design: the server
// owns the "main already taken" and overlap checks.
//
// No silent blank states (🤖 addition on the card): the Today card always
// shows SOMETHING when the staff has a home — the open shift, or the home with
// a Clock in button, or the error that stopped us.

// MARK: - Store

@MainActor
final class HomeShiftStore: ObservableObject {
    static let shared = HomeShiftStore()

    @Published var homes: [HomeInfo] = []
    @Published var roles: [String] = []
    @Published var open: HomePunch?
    @Published var recent: [HomePunch] = []
    @Published var error: String?
    @Published var isLoading = false
    @Published var loadedOnce = false
    @Published var isBusy = false
    /// True once any load proved this staff has a home (homes / open / recent).
    /// Errors only earn a card for staff we KNOW have a home; everyone else
    /// keeps the normal Today screen (no red card for a 500 or being offline).
    @Published private(set) var knownHome = false

    private let api = APIClient.shared
    /// Refresh generation: a mutation bumps it so a slower, older GET /homes
    /// that lands afterwards can't resurrect a closed punch or an old role.
    private var generation = 0

    /// Does this staff have anything home-related to show at all?
    var hasHomeContent: Bool { !homes.isEmpty || open != nil || !recent.isEmpty || (error != nil && knownHome) }

    /// Closed shifts still worth showing: note still editable, or has a note.
    var recentForDocs: [HomePunch] {
        recent.filter { ($0.editable ?? false) || !(($0.notes ?? []).isEmpty) }
    }

    func refresh() async {
        generation += 1
        let gen = generation
        isLoading = true
        defer { isLoading = false; loadedOnce = true }
        do {
            let resp = try await api.fetchHomes()
            guard gen == generation else { return }   // superseded by a newer refresh/mutation
            homes = resp.homes
            roles = resp.roles ?? HomeShiftStore.defaultRoles
            open = resp.open
            recent = resp.recent ?? []
            if !homes.isEmpty || open != nil || !recent.isEmpty { knownHome = true }
            error = nil
        } catch {
            guard gen == generation else { return }
            // Keep the last good state visible; surface the error on the card.
            self.error = HomeShiftStore.describe(error, fallback: "Couldn't load your group home.")
        }
    }

    func clockIn(homeId: String, role: String, clientId: String?) async throws {
        isBusy = true
        defer { isBusy = false }
        let gps = LocationManager.shared.currentCoordinates   // captured, never required
        let punch = try await api.homeClockIn(homeId: homeId, role: role, clientId: clientId,
                                              lat: gps?.lat, lng: gps?.lng, accuracy: gps?.accuracy)
        generation += 1   // invalidate any GET /homes still in flight
        open = punch
        knownHome = true
        error = nil
        await refresh()   // pull roster + staffing for the new punch
    }

    func switchRole(role: String, clientId: String?, swap: Bool = false) async throws {
        guard let punchId = open?.id else { return }
        isBusy = true
        defer { isBusy = false }
        let punch = try await api.homeSwitchRole(punchId: punchId, role: role, clientId: clientId, swap: swap)
        generation += 1
        open = punch
        await refresh()
    }

    func clockOut() async throws {
        guard let punchId = open?.id else { return }
        isBusy = true
        defer { isBusy = false }
        let gps = LocationManager.shared.currentCoordinates
        _ = try await api.homeClockOut(punchId: punchId, lat: gps?.lat, lng: gps?.lng, accuracy: gps?.accuracy)
        generation += 1
        open = nil
        await refresh()
    }

    static let defaultRoles: [String] = ["main", "assist", "floater"]

    static func describe(_ error: Error, fallback: String) -> String {
        if case HomePunchConflict.mainTaken(let message, _) = error { return message }
        if let api = error as? APIError {
            switch api {
            case .conflict(let msg): return msg
            case .serverError(_, let msg): return msg
            default: return api.localizedDescription
            }
        }
        if (error as? URLError) != nil { return "You're offline — group home clock-in needs a connection." }
        return error.localizedDescription.isEmpty ? fallback : error.localizedDescription
    }
}

// MARK: - Today card

/// Shown on Today when the staff has a group home. Three states, none blank:
///  • open punch → shift details, roster, Switch role, Document, Clock out
///  • no open punch → each home with a Clock in button
///  • error → the error with a Retry button
struct HomeShiftCard: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var store = HomeShiftStore.shared
    @State private var showClockIn: HomeInfo?
    @State private var showSwitchRole = false
    @State private var noteTarget: HomeNoteTarget?
    @State private var confirmClockOut = false
    @State private var actionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Group home", systemImage: "house.fill")
                    .font(.caption.weight(.bold))
                    .foregroundColor(Theme.primary)
                Spacer()
                if store.isLoading { ProgressView().scaleEffect(0.8) }
            }

            if let open = store.open {
                openShift(open)
            } else if !store.homes.isEmpty {
                ForEach(store.homes) { home in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(home.name).font(.headline)
                            Text(residentsLine(home)).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            actionError = nil
                            showClockIn = home
                        } label: {
                            Label("Clock in", systemImage: "clock.badge.checkmark")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.hasActiveVisit || store.isBusy)
                    }
                    if appState.hasActiveVisit {
                        Text("Finish your current visit before clocking in to the home.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            } else if let err = store.error {
                errorRow(err)
            } else if !store.loadedOnce {
                Text("Loading your group home…").font(.subheadline).foregroundColor(.secondary)
            }

            if let err = store.error, store.open != nil || !store.homes.isEmpty {
                errorRow(err)
            }

            // Recent closed shifts (last 14 days) with a documentation entry
            // point while the late-note window is open.
            let recents = store.recentForDocs.filter { $0.id != store.open?.id }.prefix(3)
            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RECENT HOME SHIFTS").font(.caption2.weight(.bold)).foregroundColor(.secondary)
                    ForEach(Array(recents)) { p in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(p.homeName ?? p.homeId) · \(p.roleLabel ?? p.role)").font(.subheadline.weight(.medium))
                                Text("\(p.clockInLabel ?? "—") → \(p.clockOutLabel ?? "—")").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if p.editable ?? false {
                                Menu {
                                    ForEach(noteTargets(p)) { t in
                                        Button(t.title) { noteTarget = t }
                                    }
                                } label: {
                                    Text(((p.notes ?? []).isEmpty) ? "Add note" : "Edit note")
                                        .font(.caption.weight(.semibold)).foregroundColor(Theme.primary)
                                }
                            } else {
                                Label("Locked", systemImage: "lock.fill").font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            if let actionError {
                Text(actionError)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
        .sheet(item: $showClockIn) { home in
            NavigationView {
                HomeRoleSheet(home: home, mode: .clockIn)
            }
        }
        .sheet(isPresented: $showSwitchRole) {
            if let open = store.open, let home = homeFor(open) {
                NavigationView {
                    HomeRoleSheet(home: home, mode: .switchRole(current: open))
                }
            }
        }
        .sheet(item: $noteTarget) { target in
            NavigationView {
                HomeNoteSheet(target: target)
            }
        }
        .confirmationDialog("Clock out of \(store.open?.homeName ?? "the home")?", isPresented: $confirmClockOut, titleVisibility: .visible) {
            Button("Clock out", role: .destructive) {
                Task {
                    actionError = nil
                    do { try await store.clockOut() }
                    catch { actionError = HomeShiftStore.describe(error, fallback: "Couldn't clock out.") }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // No client-side staffing math: card 3 decides shortfalls server-side
            // and alerts the manager. We just remind that clock-out is never blocked.
            Text("If the home drops below its minimum staffing, your manager is notified — you are never blocked from clocking out. Your shift documentation stays editable until the late-note deadline.")
        }
        .onChange(of: store.open?.id) { _ in actionError = nil }
    }

    // MARK: open shift

    @ViewBuilder
    private func openShift(_ open: HomePunch) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(open.homeName ?? open.homeId).font(.headline)
                Text("\(open.roleLabel ?? open.role) · since \(open.clockInLabel ?? "—")")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
            if let s = open.staffing {
                StaffingBadge(staffing: s)
            }
        }

        // Roster — who else is on the clock (always the full list incl. me).
        VStack(alignment: .leading, spacing: 6) {
            Text("ON THE CLOCK").font(.caption2.weight(.bold)).foregroundColor(.secondary)
            let roster = open.roster ?? []
            if roster.isEmpty {
                Text("Just you so far.").font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(roster) { r in
                    HStack(spacing: 8) {
                        Image(systemName: r.id == open.id ? "person.fill.checkmark" : "person.fill")
                            .foregroundColor(r.id == open.id ? Theme.success : .secondary)
                            .font(.caption)
                        Text(r.id == open.id ? "You" : r.staffName).font(.subheadline.weight(.medium))
                        Text("· \(r.roleLabel ?? r.role)").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(r.clockInLabel ?? "").font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.screenBackground)
        .cornerRadius(10)

        // Documentation entry point — per resident for Main/Assisting, one
        // home/shift note for floaters.
        VStack(alignment: .leading, spacing: 6) {
            Text("DOCUMENTATION").font(.caption2.weight(.bold)).foregroundColor(.secondary)
            ForEach(noteTargets(open)) { target in
                Button {
                    noteTarget = target
                } label: {
                    HStack {
                        Image(systemName: target.existingBody.isEmpty ? "square.and.pencil" : "checkmark.circle.fill")
                            .foregroundColor(target.existingBody.isEmpty ? Theme.primary : Theme.success)
                        Text(target.title).font(.subheadline)
                        Spacer()
                        Text(target.existingBody.isEmpty ? "Add note" : "Edit")
                            .font(.caption.weight(.semibold)).foregroundColor(Theme.primary)
                        Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }

        HStack(spacing: 10) {
            Button {
                actionError = nil
                showSwitchRole = true
            } label: {
                Label("Switch role", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(store.isBusy)

            Button {
                confirmClockOut = true
            } label: {
                Label("Clock out", systemImage: "clock.badge.xmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.danger)
            .disabled(store.isBusy)
        }
    }

    private func errorRow(_ err: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Theme.danger)
            Text(err).font(.caption.weight(.semibold)).foregroundColor(Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Retry") { Task { await store.refresh() } }
                .font(.caption.weight(.semibold))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.danger.opacity(0.1))
        .cornerRadius(10)
    }

    private func residentsLine(_ home: HomeInfo) -> String {
        let here = home.residents.filter { $0.away != true }
        if here.isEmpty { return "No residents home right now" }
        return here.map { $0.name }.joined(separator: ", ")
    }

    private func homeFor(_ open: HomePunch) -> HomeInfo? {
        if let h = store.homes.first(where: { $0.id == open.homeId }) { return h }
        // Server always sends residents on the open punch; synthesize a HomeInfo
        // so Switch role still works when /homes raced an error.
        return HomeInfo(id: open.homeId, name: open.homeName ?? open.homeId, label: nil, residents: open.residents ?? [])
    }

    /// Documentation targets for a punch = every role leg worked on it
    /// (Main/Assisting legs → that resident's note, Floater leg → home note)
    /// ∪ the current role ∪ any note already written. So a note started as
    /// Main for A stays reachable after switching to B or Floater — the
    /// server enforces the same leg rule on save.
    private func noteTargets(_ p: HomePunch) -> [HomeNoteTarget] {
        let notes = p.notes ?? []
        func body(for clientId: String?) -> String {
            notes.first(where: { ($0.clientId ?? "") == (clientId ?? "") })?.body ?? ""
        }
        func residentName(_ cid: String) -> String {
            (p.legs ?? []).first(where: { $0.clientId == cid })?.clientName
                ?? (p.residents ?? []).first(where: { $0.id == cid })?.name
                ?? notes.first(where: { $0.clientId == cid })?.clientName
                ?? (p.clientId == cid ? p.clientName : nil) ?? cid
        }
        var residentIds: [String] = []
        var wantsHome = false
        for leg in (p.legs ?? []) {
            if leg.role == "floater" { wantsHome = true }
            else if let cid = leg.clientId, !residentIds.contains(cid) { residentIds.append(cid) }
        }
        if p.role == "floater" { wantsHome = true }
        else if let cid = p.clientId, !residentIds.contains(cid) { residentIds.append(cid) }
        for n in notes {
            if let cid = n.clientId { if !residentIds.contains(cid) { residentIds.append(cid) } }
            else { wantsHome = true }
        }
        var out = residentIds.map { cid in
            HomeNoteTarget(punchId: p.id, clientId: cid, title: "\(residentName(cid)) — resident note", existingBody: body(for: cid))
        }
        if wantsHome || out.isEmpty {
            out.append(HomeNoteTarget(punchId: p.id, clientId: nil, title: "Home / shift note", existingBody: body(for: nil)))
        }
        return out
    }
}

struct StaffingBadge: View {
    let staffing: HomeStaffing
    var body: some View {
        if let required = staffing.required, let onClock = staffing.onClock, let ok = staffing.ok, staffing.error == nil {
            Label("\(onClock)/\(required) staff", systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(ok ? Theme.success : Theme.danger)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background((ok ? Theme.success : Theme.danger).opacity(0.12))
                .cornerRadius(8)
        } else {
            // Card 3 not live / staffing rule errored: say so instead of guessing.
            Label("Staffing n/a", systemImage: "questionmark.circle")
                .font(.caption.weight(.semibold)).foregroundColor(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(8)
        }
    }
}

// MARK: - Role picker (clock in + switch role)

struct HomeRoleSheet: View {
    enum Mode {
        case clockIn
        case switchRole(current: HomePunch)
    }

    let home: HomeInfo
    let mode: Mode
    /// Called after a successful submit (the Unscheduled picker uses it to
    /// close itself as well, so the staff lands back on Today).
    var onDone: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store = HomeShiftStore.shared
    @State private var role: String = "main"
    @State private var clientId: String?
    @State private var errorText: String?
    @State private var offerSwap = false
    @State private var isSubmitting = false

    private var isSwitch: Bool { if case .switchRole = mode { return true } else { return false } }
    private var residentsHere: [HomeResident] { home.residents.filter { $0.away != true } }
    private var needsResident: Bool { role == "main" || role == "assist" }
    private var canSubmit: Bool { !isSubmitting && (!needsResident || clientId != nil) }

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "house.fill").foregroundColor(Theme.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(home.name).font(.headline)
                        if let l = home.label, l != home.name { Text(l).font(.caption).foregroundColor(.secondary) }
                    }
                }
                if case .switchRole(let cur) = mode {
                    Text("Currently: \(cur.roleLabel ?? cur.role)").font(.subheadline).foregroundColor(.secondary)
                }
            }

            Section(header: Text("Role")) {
                Picker("Role", selection: $role) {
                    ForEach(store.roles.isEmpty ? HomeShiftStore.defaultRoles : store.roles, id: \.self) { r in
                        Text(HomeRoleSheet.label(for: r)).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                Text(roleHelp).font(.caption).foregroundColor(.secondary)
            }

            if needsResident {
                Section(header: Text(role == "main" ? "Main for" : "Assisting")) {
                    if residentsHere.isEmpty {
                        Text("No residents are home right now — choose Floater.").foregroundColor(.secondary)
                    }
                    ForEach(residentsHere) { r in
                        Button {
                            clientId = r.id
                            errorText = nil
                            offerSwap = false
                        } label: {
                            HStack {
                                Text(r.name).foregroundColor(.primary)
                                Spacer()
                                if clientId == r.id { Image(systemName: "checkmark").foregroundColor(Theme.primary) }
                            }
                        }
                    }
                }
            }

            if let errorText {
                Section {
                    Text(errorText).foregroundColor(Theme.danger).font(.subheadline)
                    if offerSwap, isSwitch {
                        Button("Swap with them (they become Assisting)") { submit(swap: true) }
                            .disabled(isSubmitting)
                    }
                }
            }

            Section {
                Button {
                    submit(swap: false)
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting { ProgressView().padding(.trailing, 6) }
                        Text(isSwitch ? "Switch role" : "Clock in").font(.headline)
                        Spacer()
                    }
                }
                .disabled(!canSubmit)
                if !isSwitch {
                    Text("Location is recorded if available, but you can clock in without it.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(isSwitch ? "Switch role" : "Clock in to home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        .onAppear {
            if case .switchRole(let cur) = mode {
                role = cur.role
                clientId = cur.clientId
            } else if residentsHere.count == 1 {
                clientId = residentsHere[0].id
            }
            LocationManager.shared.warmUp()
        }
    }

    static func label(for role: String) -> String {
        switch role {
        case "main": return "Main"
        case "assist": return "Assisting"
        case "floater": return "Floater"
        default: return role.capitalized
        }
    }

    private var roleHelp: String {
        switch role {
        case "main": return "You are the primary staff for one resident. Only one Main per resident at a time."
        case "assist": return "You are helping with a resident alongside their Main."
        default: return "You cover the home as a whole; your note is a home / shift note."
        }
    }

    private func submit(swap: Bool) {
        guard canSubmit else { return }
        isSubmitting = true
        errorText = nil
        Task {
            defer { isSubmitting = false }
            do {
                let cid = needsResident ? clientId : nil
                switch mode {
                case .clockIn:
                    try await store.clockIn(homeId: home.id, role: role, clientId: cid)
                case .switchRole:
                    try await store.switchRole(role: role, clientId: cid, swap: swap)
                }
                dismiss()
                onDone?()
            } catch {
                if case HomePunchConflict.mainTaken(let message, _) = error {
                    errorText = message
                    // Server code main_taken: on a role switch card-2 supports swap:true
                    // (the other staff becomes Assisting). On clock-in, the server's
                    // own advice applies: clock in as Assisting, then swap.
                    offerSwap = isSwitch
                } else {
                    errorText = HomeShiftStore.describe(error, fallback: isSwitch ? "Couldn't switch role." : "Couldn't clock in.")
                    offerSwap = false
                }
            }
        }
    }
}

// MARK: - Shift documentation

struct HomeNoteTarget: Identifiable, Hashable {
    let punchId: Int
    let clientId: String?
    let title: String
    let existingBody: String
    var id: String { "\(punchId)-\(clientId ?? "home")" }
}

/// Simple note composer for a home shift (resident note or home note). Shares
/// the Documentation look (title, body, Save) without the visit-only outcome
/// fields — nothing here is billable or goes to a visit note.
struct HomeNoteSheet: View {
    let target: HomeNoteTarget
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store = HomeShiftStore.shared
    @State private var text: String = ""
    @State private var editable = true
    @State private var lockedReason: String?
    @State private var lastDay: String?
    @State private var errorText: String?
    @State private var isSaving = false
    @State private var isLoading = true
    /// Build 121 — visit questions that apply to this resident's note (server
    /// v0.4.736+; empty for the home/shift note and on older servers).
    @State private var questions: [ServerDocQuestion] = []
    @State private var answers: [Int: String] = [:]
    /// Resident note whose question list could not be loaded: Save stays off
    /// so required questions can't be skipped by going offline.
    @State private var questionsUnavailable = false

    var body: some View {
        Form {
            Section(header: Text(target.title)) {
                if isLoading {
                    HStack { ProgressView(); Text("Loading note…").foregroundColor(.secondary) }
                }
                TextEditor(text: $text)
                    .frame(minHeight: 180)
                    .disabled(!editable || isSaving)
                if let lastDay, editable {
                    Text("Editable until \(lastDay) (late-note deadline follows your clock-out).")
                        .font(.caption).foregroundColor(.secondary)
                }
                if !editable {
                    Label(lockedReason ?? "This note is locked — the late-note deadline has passed.", systemImage: "lock.fill")
                        .font(.caption.weight(.semibold)).foregroundColor(Theme.warning)
                }
            }
            if questionsUnavailable {
                Section {
                    Label("Couldn't load this resident's visit questions. Check your connection and try again.", systemImage: "wifi.exclamationmark")
                        .font(.caption.weight(.semibold)).foregroundColor(Theme.warning)
                    Button("Retry") { Task { await load() } }
                }
            }
            if !questions.isEmpty {
                Section(header: Text("Visit questions"),
                        footer: unansweredRequired.isEmpty ? nil : Text("Answer the required questions to save.").foregroundColor(Theme.danger)) {
                    ForEach(questions) { q in
                        VisitQuestionCard(question: q, answer: answerBinding(for: q.id))
                            .disabled(!editable || isSaving)
                    }
                }
            }
            if let errorText {
                Section { Text(errorText).foregroundColor(Theme.danger).font(.subheadline) }
            }
        }
        .navigationTitle("Shift documentation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save") { save() }
                    .disabled(!editable || isSaving || isLoading || questionsUnavailable || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !unansweredRequired.isEmpty)
            }
        }
        .task { await load() }
    }

    private func answerBinding(for id: Int) -> Binding<String?> {
        Binding(get: { answers[id] }, set: { answers[id] = $0 })
    }

    /// Same rule as DocumentationView: text needs non-empty trimmed, checkbox
    /// needs at least one selection, radio needs an option.
    private func isAnswered(_ q: ServerDocQuestion) -> Bool {
        guard let raw = answers[q.id] else { return false }
        if q.type == "checkbox" {
            return !VisitQuestionCard.decodeCheckboxSelections(raw).isEmpty
        }
        return !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var unansweredRequired: [ServerDocQuestion] {
        questions.filter { $0.required && !isAnswered($0) }
    }

    /// Only resident notes carry questions; the home note sends nil so the
    /// server leaves stored answers untouched.
    private var answerPayload: [HomeNoteAnswerPayload]? {
        guard !questions.isEmpty else { return nil }
        return questions.map { HomeNoteAnswerPayload(questionId: $0.id, answer: answers[$0.id] ?? "") }
    }

    private func load() async {
        isLoading = true
        questionsUnavailable = false
        text = target.existingBody
        do {
            let resp = try await APIClient.shared.fetchHomePunchNotes(punchId: target.punchId)
            let existing = resp.notes.first(where: { ($0.clientId ?? "") == (target.clientId ?? "") })
            if let n = existing { text = n.body }
            if let cid = target.clientId, let qs = resp.questions[cid] {
                questions = qs
                var a: [Int: String] = [:]
                for qa in existing?.questionAnswers ?? [] { a[qa.questionId] = qa.answer }
                // A brand-new note starts on the configured defaults (like visits).
                // An existing note never gets defaults stamped on by a body edit.
                if existing == nil {
                    for q in qs where a[q.id] == nil {
                        if let dv = q.defaultValue, !dv.isEmpty { a[q.id] = dv }
                    }
                }
                answers = a
            }
            editable = resp.editable ?? true
            lockedReason = resp.lockedReason
            lastDay = resp.lastDay
        } catch {
            // Keep what the card already had; show why the refresh failed.
            errorText = HomeShiftStore.describe(error, fallback: "Couldn't load the note.")
            // Resident notes may carry required visit questions we never saw —
            // don't let an offline save skip them.
            if target.clientId != nil { questionsUnavailable = true }
        }
        isLoading = false
    }

    private func save() {
        isSaving = true
        errorText = nil
        Task {
            defer { isSaving = false }
            do {
                _ = try await APIClient.shared.saveHomePunchNote(punchId: target.punchId, clientId: target.clientId, body: text, questionAnswers: answerPayload)
                await store.refresh()
                dismiss()
            } catch {
                errorText = HomeShiftStore.describe(error, fallback: "Couldn't save the note.")
            }
        }
    }
}
