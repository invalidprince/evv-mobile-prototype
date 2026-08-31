import SwiftUI
import SafariServices

// MARK: - Work tab (build 29 / server v0.4.273)
// To-Dos + forms + acknowledgements + documents in one place, mirroring the
// web dashboard's To-Do card (same shared server assembly, todo-core.js).
// Nick's final tab shape 2026-08-26: Today · Schedule · History · Work · More.
//
// ⚠️ ONLINE-ONLY — deliberate, per Nick 2026-08-26 ("The app is solely for
// convenience"). Nothing on this tab ever enters the offline queue: when
// offline, the checkboxes and links are disabled with a clear message. Do NOT
// change that — it exists so a to-do can never be stamped with a sync time.
// The offline punch queue for clock-in/out is a separate, untouched system.
struct WorkView: View {
    @EnvironmentObject var appState: AppState

    @State private var items: [WorkItem] = []
    @State private var teamRollup: WorkTeamRollup?
    /// My Documents status roll-up (server v0.4.337) — badges the Documents row.
    @State private var docSummary: WorkDocSummary?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var togglingIds: Set<Int> = []
    @State private var safariItem: SafariItem?
    /// Visit being documented natively (native == "documentation", build 47).
    @State private var docVisit: Visit?
    /// Request-a-shift flow (server v0.4.348, build 51).
    @State private var showRequestShift = false
    /// Pending visit created by the request sheet — handed to the doc sheet
    /// once the request sheet has dismissed (sequential-sheet handoff).
    @State private var requestedDocVisit: Visit?

    private var online: Bool { appState.effectivelyOnline }
    private var openTodos: [WorkItem] { items.filter { $0.isTodo && !$0.done } }
    private var doneTodos: [WorkItem] { items.filter { $0.isTodo && $0.done } }
    private var autoItems: [WorkItem] { items.filter { !$0.isTodo } }

    var body: some View {
        NavigationView {
            Group {
                if appState.mode == .mock {
                    mockPlaceholder
                } else {
                    workList
                }
            }
            .navigationTitle("Work")
        }
        .navigationViewStyle(.stack)
        .sheet(item: $safariItem) { item in
            SafariView(url: item.url)
        }
        .sheet(item: $docVisit, onDismiss: {
            // The doc item clears itself once documentation is complete —
            // reload so a finished visit disappears without a manual refresh.
            // Also refresh history so a just-requested pending shift shows its
            // ⏳ badge without a manual pull.
            Task {
                await load()
                await appState.refreshHistory()
            }
        }) { visit in
            NavigationView {
                DocumentationView(visit: visit)
            }
        }
        .sheet(isPresented: $showRequestShift, onDismiss: {
            // Nick's flow: "Immediately upon requesting, staff should be able
            // to complete documentation." The request sheet hands back the
            // pending visit; once it's gone, open the SAME DocumentationView
            // every other surface uses.
            if let v = requestedDocVisit {
                requestedDocVisit = nil
                docVisit = v
            }
        }) {
            RequestShiftSheet { visit in
                requestedDocVisit = visit
                showRequestShift = false
            }
        }
    }

    // MARK: - Server-mode list

    private var workList: some View {
        List {
            if !online {
                Section {
                    Label("You're offline. Work items are view-only until you reconnect — nothing here is ever queued.", systemImage: "wifi.slash")
                        .font(.subheadline)
                        .foregroundColor(Theme.danger)
                }
            }

            if isLoading && items.isEmpty && teamRollup == nil {
                Section { HStack { ProgressView(); Text("Loading your work…").foregroundColor(.secondary) } }
            } else if let err = loadError, items.isEmpty {
                Section {
                    Text(err).foregroundColor(Theme.danger).font(.subheadline)
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                if let team = teamRollup {
                    Section(header: Text("Your Team")) {
                        teamRow(team)
                    }
                }

                Section(header: Text("To-Dos")) {
                    if openTodos.isEmpty && autoItems.isEmpty {
                        Text("Nothing on your list. 🎉")
                            .foregroundColor(.secondary)
                    }
                    ForEach(openTodos) { item in
                        todoRow(item)
                    }
                    ForEach(autoItems) { item in
                        autoRow(item)
                    }
                }

                if !doneTodos.isEmpty {
                    Section(header: Text("Completed")) {
                        ForEach(doneTodos) { item in
                            todoRow(item)
                        }
                    }
                }

                Section(header: Text("Shifts"),
                        footer: Text("Forgot to clock in? Request the shift and document it now — your manager approves or denies it.")) {
                    Button {
                        showRequestShift = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.body)
                                .foregroundColor(online ? .accentColor : .secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Request a shift")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Text("For a shift that isn't in the system — pending manager approval")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!online)
                }

                Section(header: Text("Documents"),
                        footer: Text("Items marked with an arrow open in the web portal. To-dos with a checkbox can be checked off right here.")) {
                    NavigationLink(destination: MyDocumentsView()) {
                        myDocumentsLabel
                    }
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    // MARK: - Rows

    /// A real, checkable to-do from the `todos` table. Toggling is ONLINE-ONLY
    /// — the button is disabled offline and the tap is never queued.
    private func todoRow(_ item: WorkItem) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await toggle(item) }
            } label: {
                if let todoId = item.todoId, togglingIds.contains(todoId) {
                    ProgressView().frame(width: 22, height: 22)
                } else {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(item.done ? Theme.success : (online ? .accentColor : .secondary))
                }
            }
            .buttonStyle(.plain)
            .disabled(!online || item.todoId == nil || togglingIds.contains(item.todoId ?? -1))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .strikethrough(item.done)
                    .foregroundColor(item.done ? .secondary : .primary)
                if let due = item.dueDate {
                    Text(item.overdue ? "Due \(due) — overdue" : "Due \(due)")
                        .font(.caption)
                        .foregroundColor(item.overdue ? Theme.danger : .secondary)
                }
            }
            Spacer()
        }
    }

    /// A derived line — clears automatically when the underlying work is done.
    /// Never checkable; deep-links into the web portal (or a native screen).
    ///
    /// build 47 (Nick 2026-08-28: "if it's available on the app, open on the
    /// app"): `native == "documentation"` opens the SAME DocumentationView
    /// that History's "Finish documentation" uses, for the item's visit — no
    /// Safari sheet, no re-auth. If the visit can't be resolved from the
    /// app's fetched set (older than the 14-day history window), fall through
    /// to the webPath branch rather than dead-ending the tap.
    private func autoRow(_ item: WorkItem) -> some View {
        Group {
            if item.native == "documents" {
                NavigationLink(destination: MyDocumentsView()) {
                    autoRowLabel(item)
                }
            } else if item.native == "documentation",
                      let visit = resolveVisit(item.visitId) {
                Button {
                    docVisit = visit
                } label: {
                    HStack {
                        autoRowLabel(item)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } else if let path = item.webPath, online {
                Button {
                    openWeb(path)
                } label: {
                    HStack {
                        autoRowLabel(item)
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                autoRowLabel(item)
            }
        }
    }

    private func autoRowLabel(_ item: WorkItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconFor(item.category))
                .font(.body)
                .foregroundColor(item.overdue ? Theme.danger : .accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                if let detail = item.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(item.overdue ? Theme.danger : .secondary)
                } else if item.overdue {
                    Text("Overdue")
                        .font(.caption)
                        .foregroundColor(Theme.danger)
                }
            }
        }
    }

    /// The Documents row carries the SAME signal the web dashboard shows
    /// (Nick 2026-08-29: "on the work section (like the desktop), it should
    /// show rejected documents"). The underlying `staffdoc` alert rows were
    /// always present in the To-Dos list, but on a real roster a rejected
    /// document sorts in behind six identical "Documentation — <name>" rows
    /// and reads as absent. This is the surfacing fix — the status text and
    /// its colour are BOTH decided server-side from the same builder that
    /// produced those rows, so this can never contradict the list below.
    private var myDocumentsLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.badge.ellipsis")
                .font(.body)
                .foregroundColor(docChipColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("My Documents")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                if let summary = docSummary {
                    Text(summary.label)
                        .font(.caption)
                        .foregroundColor(summary.chip == "ok" ? .secondary : docChipColor)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer()
            // A count badge only when something actually needs re-uploading —
            // "missing" and "expiring" are already spelled out in the caption
            // and do not warrant a red pill.
            if let summary = docSummary, summary.needsAction {
                Text("\(summary.rejected + summary.expired)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Theme.danger)
                    .clipShape(Capsule())
            }
        }
    }

    private var docChipColor: Color {
        switch docSummary?.chip {
        case "danger": return Theme.danger
        case "warn": return Theme.warning
        default: return .accentColor
        }
    }

    private func teamRow(_ team: WorkTeamRollup) -> some View {
        let late = team.overdue > 0
        let title = late
            ? "\(team.overdue) team form obligation\(team.overdue == 1 ? "" : "s") OVERDUE"
            : "\(team.total) team form obligation\(team.total == 1 ? "" : "s") due within 5 days"
        let detail = late && team.total > team.overdue
            ? "\(team.total) total due within 5 days — staff you supervise"
            : "Assignments + signatures for staff you supervise"
        return Group {
            if let path = team.webPath, online {
                Button {
                    openWeb(path)
                } label: {
                    teamRowLabel(title: title, detail: detail, late: late)
                }
                .buttonStyle(.plain)
            } else {
                teamRowLabel(title: title, detail: detail, late: late)
            }
        }
    }

    private func teamRowLabel(title: String, detail: String, late: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.body)
                .foregroundColor(late ? Theme.danger : .accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(late ? .semibold : .regular))
                    .foregroundColor(late ? Theme.danger : .primary)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if online {
                Image(systemName: "arrow.up.forward.app")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// Resolve a server visit id ("V-2027") to a Visit the app has already
    /// fetched — today's visits first, then the 14-day history set. Returns
    /// nil when the visit isn't loaded, which sends the row down the webPath
    /// fallback instead of a tap that does nothing.
    private func resolveVisit(_ serverVisitId: String?) -> Visit? {
        guard let vid = serverVisitId, !vid.isEmpty else { return nil }
        if let v = appState.todayVisits.first(where: { $0.serverVisitId == vid }) { return v }
        return appState.historyVisits.first(where: { $0.serverVisitId == vid })
    }

    private func iconFor(_ category: String?) -> String {
        switch category {
        case "ack": return "signature"
        case "doc": return "square.and.pencil"
        case "staffdoc": return "doc.badge.ellipsis"
        case "form": return "doc.text"
        case "signature": return "signature"
        case "review": return "exclamationmark.bubble"
        default: return "checklist"
        }
    }

    // MARK: - Mock mode

    private var mockPlaceholder: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Work is available in server mode", systemImage: "checklist")
                        .font(.subheadline.weight(.semibold))
                    Text("Sign in with your staff account to see your to-dos, forms, acknowledgements, and documents.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        guard appState.mode == .server else { return }
        guard online else { return } // online-only: never fetch/queue offline
        isLoading = true
        loadError = nil
        do {
            let response = try await APIClient.shared.fetchWorkTodos()
            items = response.items
            teamRollup = response.teamRollup
            docSummary = response.docSummary
            appState.workOpenCount = response.openCount + (response.teamRollup != nil ? 1 : 0)
            // build 47: native documentation rows resolve their visit from the
            // app's fetched set. If any of them can't resolve yet (user came
            // straight to Work without opening History), pull history once so
            // the rows open natively instead of falling back to the web.
            let needsHistory = response.items.contains {
                $0.native == "documentation" && resolveVisit($0.visitId) == nil
            }
            if needsHistory {
                await appState.refreshHistory()
            }
        } catch {
            let apiErr = error as? APIError ?? .networkError(error)
            loadError = apiErr.errorDescription ?? "Could not load your work items."
        }
        isLoading = false
    }

    private func toggle(_ item: WorkItem) async {
        // ONLINE-ONLY by design: no queueing, no optimistic offline state.
        guard online, let todoId = item.todoId else { return }
        togglingIds.insert(todoId)
        defer { togglingIds.remove(todoId) }
        do {
            let done = try await APIClient.shared.toggleTodo(id: todoId)
            if let idx = items.firstIndex(where: { $0.key == item.key }) {
                items[idx].done = done
            }
            appState.workOpenCount = items.filter { !$0.done }.count + (teamRollup != nil ? 1 : 0)
        } catch {
            let apiErr = error as? APIError ?? .networkError(error)
            loadError = apiErr.errorDescription ?? "Could not update the to-do."
        }
    }

    private func openWeb(_ path: String) {
        // The web portal shares the API host; strip the /api suffix.
        let base = APIClient.shared.baseURL.hasSuffix("/api")
            ? String(APIClient.shared.baseURL.dropLast(4))
            : APIClient.shared.baseURL
        guard let url = URL(string: base + path) else { return }
        safariItem = SafariItem(url: url)
    }
}

// MARK: - Safari sheet plumbing

private struct SafariItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Minimal SFSafariViewController wrapper — web-only destinations (form fill,
/// submissions, sign pages) open in-app against the CloudFront host.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
