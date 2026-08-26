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
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var togglingIds: Set<Int> = []
    @State private var safariItem: SafariItem?

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

                Section(header: Text("Documents"),
                        footer: Text("Items marked with an arrow open in the web portal. To-dos with a checkbox can be checked off right here.")) {
                    NavigationLink(destination: MyDocumentsView()) {
                        Label("My Documents", systemImage: "doc.badge.ellipsis")
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
    /// Never checkable; deep-links into the web portal (or native Documents).
    private func autoRow(_ item: WorkItem) -> some View {
        Group {
            if item.native == "documents" {
                NavigationLink(destination: MyDocumentsView()) {
                    autoRowLabel(item)
                }
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
            appState.workOpenCount = response.openCount + (response.teamRollup != nil ? 1 : 0)
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
