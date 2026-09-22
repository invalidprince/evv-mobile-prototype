import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var payPeriod = 0 // 0 = this, 1 = last
    @State private var timeFixVisit: Visit?
    @State private var deleteVisit: Visit?
    @State private var noteVisit: Visit?
    @State private var addNoteVisit: Visit?
    // Build 56 — "Request a shift" lives on History too (Nick 2026-09-02:
    // "make the 'request a shift' show up in the 'history'"): a forgotten
    // shift is noticed while looking at past visits. SAME sheet + SAME
    // straight-into-documentation handoff as the Work tab.
    @State private var showRequestShift = false
    @State private var requestedDocVisit: Visit?
    @State private var requestDocVisit: Visit?
    // Build 76 — MISSED DAYS (📅) in History (server v0.4.569, Todoist
    // 6hWwwJ8Jr64937GH). Nick, #evv 2026-09-17, with a History screenshot:
    // show missed visits in iOS history with the same action items as the
    // dashboard. The sheet carries both, driven by the server's flags.
    // Build 77 — the row has one button per action, so the request carries
    // which path to open on.
    @State private var dailyToResolve: MissedDailyResolveRequest?
    // Build 77 — missed SHIFTS (🚫) are in History too, like the web's All
    // Visits table: "It was missed" → reason sheet; "I worked this shift" →
    // the pre-filled request form + the same documentation handoff the
    // "Request a shift" card uses.
    @State private var shiftReasonToResolve: MissedShiftItem?
    @State private var missedRequestPrefill: MissedShiftPrefillRequest?
    // Build 83 — clock out of a STILL CLOCKED IN row straight from History
    // (server v0.4.604 returns an open visit however old). The flow acts on
    // `appState.activeVisit` (Today's copy of the same visit, carried over
    // by mergeStaleOpenVisitsIntoToday / the shifts payload).
    @State private var clockOutVisit: Visit?

    /// `.sheet(item:)` payloads for the two missed-row sheets.
    struct MissedDailyResolveRequest: Identifiable {
        let item: MissedDailyItem
        let start: MissedDailyStart
        var id: String { item.key }
    }
    struct MissedShiftPrefillRequest: Identifiable {
        let prefill: MissedShiftPrefill
        var id: Int { prefill.shiftId }
    }

    /// Build 90 (Todoist 6hXrQ7VjHH3C7q8q) — the build-56 "Shift requests"
    /// block at the top of the tab is GONE. Nick, 2026-09-21: "Shift requests
    /// shouldnt show like this. It should show in the history and just show
    /// the shift details and approved/denied. It should only show for 2 weeks
    /// after the approval/denial. Just like when you request a shift and it
    /// says pending."
    ///
    /// A shift request is now an ordinary row under the day of the SHIFT:
    ///   • pending  → the real (unapproved) visit is already in the list;
    ///                ServerHistoryRow shows a yellow PENDING APPROVAL chip.
    ///   • approved → the visit is a normal visit in the list; a green SHIFT
    ///                APPROVED chip for 14 days after the decision, then plain.
    ///   • denied   → the visit is soft-deleted, so a STAND-IN row is built
    ///                from the request record (server v0.4.625 `shiftRequest`)
    ///                and disappears 14 days after the denial.
    /// A stand-in is built ONLY when no matching visit is in the list (an
    /// approved request would otherwise appear twice), which also covers a
    /// request decided recently for a shift older than the history window.
    private var shiftRequestStandIns: [ServerException] {
        let visitIds = Set(mergedHistoryVisits.compactMap { $0.serverVisitId })
        return appState.serverExceptions.filter { req in
            guard (req.type ?? "").lowercased() == "shift request" else { return false }
            if let vid = req.visitId, visitIds.contains(vid) { return false }
            if let sr = req.shiftRequest?.visitId, visitIds.contains(sr) { return false }
            return ShiftRequestHistoryPolicy.isVisible(req)
        }
    }

    // MARK: - Mock mode data

    private var mockFilteredVisits: [Visit] {
        let cal = Calendar.current
        let now = Date()
        let cutoff = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now))!
        let visits = appState.pastVisits.filter { v in
            payPeriod == 0 ? v.scheduledStart >= cutoff : v.scheduledStart < cutoff
        }
        return visits.sorted { $0.scheduledStart > $1.scheduledStart }
    }

    // MARK: - Server mode data

    /// Merges server history with unsynced local events (offline clock in/out).
    /// Deduplicates by serverVisitId so synced records replace local ones.
    private var mergedHistoryVisits: [Visit] {
        var merged = appState.historyVisits
        let existingServerIds = Set(merged.compactMap { $0.serverVisitId })

        // Include completed or in-progress visits from todayVisits that
        // are pending sync and not already present in server history
        let unsyncedLocal = appState.todayVisits.filter { visit in
            (visit.status == .completed || visit.status == .inProgress)
            && visit.syncState == .pending
            && (visit.serverVisitId == nil || !existingServerIds.contains(visit.serverVisitId!))
        }
        merged.append(contentsOf: unsyncedLocal)
        return merged
    }

    // MARK: - One stream: visits + missed, grouped by day (build 77)

    /// One line of the History list — a real visit or a missed pseudo-row.
    /// Build 77 (Todoist 6hWwwJ8Jr64937GH, Nick #evv 2026-09-21: "I want the
    /// missing visits to literally show in the history on iOS like it does
    /// web. Same format, just shows missed."). The web's All Visits table
    /// co-sorts `missed_shift` / `missed_daily` pseudo-rows with real visits
    /// (v0.4.546) instead of a block above it; this is the same merge, under
    /// the same day headers. A missed row is NOT a visit: it never counts
    /// toward `mergedHistoryVisits`, the hours or the Visits number.
    enum HistoryEntry: Identifiable {
        case visit(Visit)
        case missed(MissedHistoryEntry)
        /// Build 90 — a shift request with no visit in the list (denied, or
        /// decided for a shift outside the history window).
        case request(ServerException)

        var id: String {
            switch self {
            case .visit(let v): return "visit-\(v.id.uuidString)"
            case .missed(let m): return m.id
            case .request(let r): return "request-\(r.id)"
            }
        }
    }

    /// A missed item's agency day ("yyyy-MM-dd"), placed on the DEVICE's
    /// calendar so it lands in the same bucket the visit rows use
    /// (`cal.startOfDay(for:)` on the device). Falls back to the agency zone.
    private static func localDay(_ ymd: String, calendar cal: Calendar) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: ymd) { return cal.startOfDay(for: d) }
        return MissedShiftPrefill.parse(date: ymd, time: nil).map { cal.startOfDay(for: $0) }
    }

    /// Sort key inside a day: a visit by its start; a missed item by its
    /// scheduled start, or the day's midnight when nothing was scheduled (so
    /// an unscheduled missed day sits at the bottom of its day).
    private static func sortKey(_ entry: HistoryEntry, day: Date, calendar cal: Calendar) -> Date {
        switch entry {
        case .visit(let v):
            return v.actualStart ?? v.scheduledStart
        case .missed(let m):
            if let st = m.start {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = cal.timeZone
                f.dateFormat = "yyyy-MM-dd h:mm a"
                if let d = f.date(from: "\(m.date) \(st)") { return d }
            }
            return day
        case .request(let r):
            if let ymd = ShiftRequestHistoryPolicy.shiftDay(r), let st = r.shiftRequest?.clockIn {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = cal.timeZone
                f.dateFormat = "yyyy-MM-dd h:mm a"
                if let d = f.date(from: "\(ymd) \(st)") { return d }
            }
            return day
        }
    }

    /// Missed rows the server currently reports for me — both kinds. Absent
    /// keys / an older server / a 403 leave these empty and the list is the
    /// plain visit history.
    ///
    /// Build 79 (server v0.4.594) — the REASONED rows ride along too. Nick,
    /// #evv 2026-09-21: "When I saved a reason, it disappeared from the iOS. I
    /// don't want that to happen. Similar to the dashboard I just want it to
    /// say missed and the reason and not just disappear." A row whose reason
    /// is on file stays under its day header in neutral styling with the
    /// reason; only the owing rows are red. De-duplicated by id in case the
    /// optimistic local move and a refresh briefly overlap.
    private var missedEntries: [MissedHistoryEntry] {
        let owing: [MissedHistoryEntry] = appState.missedShifts.map { .shift($0) } + appState.missedDaily.map { .daily($0) }
        let reasoned: [MissedHistoryEntry] = appState.missedShiftsReasoned.map { .shift($0) } + appState.missedDailyReasoned.map { .daily($0) }
        var seen = Set<String>()
        return (owing + reasoned).filter { seen.insert($0.id).inserted }
    }

    /// Day groups, newest first. A day that holds ONLY missed rows still gets
    /// its header — that is the point of putting them in the history.
    private var serverGroupedEntries: [(label: String, day: Date, entries: [HistoryEntry])] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        var groups: [Date: [HistoryEntry]] = [:]
        for visit in mergedHistoryVisits {
            let day = cal.startOfDay(for: visit.actualStart ?? visit.scheduledStart)
            groups[day, default: []].append(.visit(visit))
        }
        for m in missedEntries {
            guard let day = Self.localDay(m.date, calendar: cal) else { continue }
            groups[day, default: []].append(.missed(m))
        }
        // Build 90 — shift requests whose visit is not in the list, on the
        // day of the SHIFT (not the day of the decision).
        for r in shiftRequestStandIns {
            guard let ymd = ShiftRequestHistoryPolicy.shiftDay(r),
                  let day = Self.localDay(ymd, calendar: cal) else { continue }
            groups[day, default: []].append(.request(r))
        }

        func label(for day: Date) -> String {
            if cal.isDate(day, inSameDayAs: today) { return "Today" }
            if cal.isDate(day, inSameDayAs: yesterday) { return "Yesterday" }
            let f = DateFormatter()
            f.dateFormat = "EEEE, MMM d"
            return f.string(from: day)
        }

        return groups.keys.sorted(by: >).map { day in
            let entries = groups[day]!.sorted {
                Self.sortKey($0, day: day, calendar: cal) > Self.sortKey($1, day: day, calendar: cal)
            }
            return (label: label(for: day), day: day, entries: entries)
        }
    }

    private var totalHoursServer: Double {
        mergedHistoryVisits.reduce(0) { $0 + $1.hoursValue }
    }

    private var totalHoursMock: Double {
        mockFilteredVisits.reduce(0) { $0 + $1.hoursValue }
    }

    var body: some View {
        NavigationView {
            Group {
                if appState.mode == .server {
                    serverBody
                } else {
                    mockBody
                }
            }
            .background(Theme.screenBackground.ignoresSafeArea())
            .navigationTitle("History")
            .sheet(item: $timeFixVisit) { visit in
                TimeFixSheet(visit: visit)
            }
            .sheet(item: $deleteVisit) { visit in
                DeleteRequestSheet(visit: visit)
            }
            .sheet(item: $noteVisit) { visit in
                NavigationView {
                    DocumentationView(visit: visit)
                }
            }
            .sheet(item: $addNoteVisit) { visit in
                NavigationView {
                    DocumentationView(visit: visit)
                }
            }
            .sheet(item: $requestDocVisit, onDismiss: {
                Task { await appState.refreshHistory() }
            }) { visit in
                NavigationView {
                    DocumentationView(visit: visit)
                }
            }
            .fullScreenCover(item: $clockOutVisit, onDismiss: {
                // Either clocked out or backed out — re-read both feeds so the
                // STILL CLOCKED IN row and the Today banner follow the server.
                Task {
                    await appState.refreshServerShifts()
                    await appState.refreshHistory()
                }
            }) { visit in
                ClockOutFlow(visit: visit)
            }
            .sheet(item: $dailyToResolve, onDismiss: {
                // Either action changes History: a created visit appears, a
                // recorded reason moves the row to its reasoned state (build
                // 79: it stays visible). Refresh both lists.
                Task {
                    await appState.refreshHistory()
                    await appState.refreshMissedShifts()
                }
            }) { req in
                MissedDailyResolveSheet(item: req.item, start: req.start)
            }
            .sheet(item: $shiftReasonToResolve, onDismiss: {
                // Build 79: a recorded reason keeps the row under its day, now
                // neutral with the reason; refetch so it reflects the server.
                Task { await appState.refreshMissedShifts() }
            }) { item in
                MissedShiftResolveSheet(item: item, startOnReason: true)
            }
            .sheet(item: $missedRequestPrefill, onDismiss: {
                // Same handoff as "Request a shift" below: the request sheet
                // hands back the pending visit; once it's gone, open
                // DocumentationView. The linked request also clears the
                // missed row server-side, so refresh that list too.
                Task { await appState.refreshMissedShifts() }
                if let v = requestedDocVisit {
                    requestedDocVisit = nil
                    requestDocVisit = v
                }
            }) { req in
                RequestShiftSheet(prefill: req.prefill) { visit in
                    requestedDocVisit = visit
                    missedRequestPrefill = nil
                }
            }
            .sheet(isPresented: $showRequestShift, onDismiss: {
                // Same handoff WorkView uses: the request sheet hands back the
                // pending visit; once it's gone, open DocumentationView.
                if let v = requestedDocVisit {
                    requestedDocVisit = nil
                    requestDocVisit = v
                }
            }) {
                RequestShiftSheet { visit in
                    requestedDocVisit = visit
                    showRequestShift = false
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Server Mode Body

    private var serverBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                serverSummaryCard

                requestShiftCard

                // Build 77 — the build-76 "Missed" block that sat here is
                // GONE. Missed rows are interleaved under their day headers
                // in the list below, the way the web's All Visits table does
                // it (Nick, #evv 2026-09-21: "Same format, just shows missed").
                // Build 90 — the build-56 "Shift requests" block that sat
                // here is GONE too: a request is a row under its shift's day
                // (pending / approved chips on the visit row, a stand-in row
                // for a denied one). See shiftRequestStandIns.

                if appState.isLoadingHistory {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading history…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }

                if !appState.isLoadingHistory && mergedHistoryVisits.isEmpty && missedEntries.isEmpty && shiftRequestStandIns.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No visit history yet")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }

                ForEach(serverGroupedEntries, id: \.day) { group in
                    Text(group.label)
                        .font(.title3.bold())
                        .padding(.top, 4)
                    ForEach(group.entries) { entry in
                        switch entry {
                        case .visit(let visit):
                            ServerHistoryRow(visit: visit,
                                             onTimeFix: { timeFixVisit = visit },
                                             onRequestDelete: { deleteVisit = visit },
                                             onAddNote: { addNoteVisit = visit },
                                             onFinishNote: { noteVisit = visit },
                                             onClockOut: {
                                                 // Prefer Today's copy (clockOut() reads todayVisits);
                                                 // fall back to this row for display.
                                                 clockOutVisit = appState.todayVisits.first(where: { $0.serverVisitId == visit.serverVisitId && $0.status == .inProgress }) ?? visit
                                             })
                        case .missed(let m):
                            MissedHistoryRow(
                                entry: m,
                                isOffline: !appState.effectivelyOnline,
                                onRequestShift: {
                                    if case .shift(let s) = m, let p = MissedShiftPrefill(item: s) {
                                        missedRequestPrefill = MissedShiftPrefillRequest(prefill: p)
                                    }
                                },
                                onShiftReason: {
                                    if case .shift(let s) = m { shiftReasonToResolve = s }
                                },
                                onCreateVisit: {
                                    if case .daily(let d) = m {
                                        dailyToResolve = MissedDailyResolveRequest(item: d, start: .create)
                                    }
                                },
                                onDailyReason: {
                                    if case .daily(let d) = m {
                                        dailyToResolve = MissedDailyResolveRequest(item: d, start: .reason)
                                    }
                                }
                            )
                        case .request(let r):
                            ShiftRequestHistoryRow(request: r)
                        }
                    }
                }
            }
            .padding(16)
        }
        .refreshable {
            await appState.refreshHistory()
            // Build 76 — pull-to-refresh must also refresh the missed rows,
            // or a staff member who just created the visit elsewhere would
            // keep seeing the row they already cleared.
            await appState.refreshMissedShifts()
        }
        .onAppear {
            // Build 53: refresh EVERY time the tab is shown (debounced in
            // AppState), not only when empty. The old `isEmpty` guard meant a
            // list loaded before today's visit existed was never refetched —
            // the visit was on the server and absent from this screen.
            Task { await appState.refreshHistoryIfStale() }
            // Build 76 — the missed lists are memory-only and online-only,
            // so they must be fetched when the tab appears or the rows would
            // be absent on a cold open of History.
            Task { await appState.refreshMissedShifts() }
        }
    }

    // MARK: - Mock Mode Body (unchanged)

    private var mockBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Pay Period", selection: $payPeriod) {
                    Text("This Pay Period").tag(0)
                    Text("Last Pay Period").tag(1)
                }
                .pickerStyle(.segmented)

                mockSummaryCard

                ForEach(mockFilteredVisits) { visit in
                    HistoryRow(visit: visit,
                               onTimeFix: { timeFixVisit = visit },
                               onRequestDelete: { deleteVisit = visit },
                               onFinishNote: { noteVisit = visit })
                }
            }
            .padding(16)
        }
    }

    private var serverSummaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total Hours (14d)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(format: "%.1f h", totalHoursServer))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Theme.primary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Visits")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(mergedHistoryVisits.count)")
                    .font(.system(size: 32, weight: .bold))
            }
        }
        .cardStyle()
    }

    /// Build 56 — History entry point for a shift that isn't in the system.
    private var requestShiftCard: some View {
        Button {
            showRequestShift = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.title3)
                    .foregroundColor(appState.effectivelyOnline ? Theme.primary : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Request a shift")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text(appState.effectivelyOnline
                         ? "Forgot to clock in? Request the shift and document it now — your manager approves or denies it."
                         : "Shift requests need a connection.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Theme.cardBackground)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
        .disabled(!appState.effectivelyOnline)
    }

    private var mockSummaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total Hours")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(format: "%.1f h", totalHoursMock))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Theme.primary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Visits")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(mockFilteredVisits.count)")
                    .font(.system(size: 32, weight: .bold))
            }
        }
        .cardStyle()
    }
}

// MARK: - Server History Row

struct ServerHistoryRow: View {
    let visit: Visit
    let onTimeFix: () -> Void
    let onRequestDelete: () -> Void
    let onAddNote: () -> Void
    let onFinishNote: () -> Void
    /// Build 83 — clock out from History (a STILL CLOCKED IN row from a
    /// prior day has no Today card of its own to find). Optional so the
    /// mock/other call sites need no change.
    var onClockOut: (() -> Void)? = nil

    /// Build 53: a visit that is clocked in but not out. It appears here
    /// under "Today" AND on the Today tab (Nick, 2026-09-02: "It should").
    /// Read-only in History until clock-out — Time Fix / Delete are
    /// meaningless before the visit has an end time.
    private var isInProgress: Bool {
        visit.status == .inProgress || (visit.actualStart != nil && visit.actualEnd == nil)
    }

    /// Build 83 — running, and the clock-in was on a PRIOR day. Nick, #evv
    /// 2026-09-21: "even if over 2 weeks (should NEVER happen), if you're
    /// clocked in still show that visit in history." The server now returns
    /// such rows regardless of its 14-day window; this row says so loudly.
    private var isStaleOpen: Bool { isInProgress && visit.isStaleOpen }

    private var timeText: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        let start = visit.actualStart ?? visit.scheduledStart
        let end = visit.actualEnd
        let startStr = f.string(from: start)
        // A stale open row reads "10:46 AM – no clock-out", never "– now":
        // "now" implies today.
        let endStr = end != nil ? f.string(from: end!) : (isStaleOpen ? "no clock-out" : "now")
        return "\(startStr) – \(endStr)"
    }

    /// Elapsed-so-far for a running visit (no clock-out yet), else the
    /// stored duration. Never "0h 0m" for a visit that is still going.
    /// A prior-day open visit shows days, not a 400-hour figure.
    private var durationLabel: String {
        guard isInProgress else { return visit.durationText }
        guard let start = visit.actualStart else { return "—" }
        let mins = max(0, Int(Date().timeIntervalSince(start) / 60))
        if isStaleOpen {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: start), to: Calendar.current.startOfDay(for: Date())).day ?? 0
            return days <= 1 ? "since yesterday" : "\(days) days open"
        }
        return "\(mins / 60)h \(mins % 60)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 12) {
                    AvatarView(name: visit.client.name, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(visit.client.name).font(.headline)
                        Text(visit.serviceLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(durationLabel)
                        .font(.headline)
                        .foregroundColor(isStaleOpen ? Theme.danger : (isInProgress ? Theme.primary : .primary))
                    Text(timeText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Status chips row
            HStack(spacing: 6) {
                // Build 53: running visit — one unambiguous badge. The server's
                // docStatus for a running visit is also "in progress", which
                // as a doc chip reads like a documentation state; suppressed
                // below while the visit itself is running.
                // Build 83: a prior-day running visit is a problem, not a
                // state — red, and it says what to do.
                if isStaleOpen {
                    StatusBadge(text: "STILL CLOCKED IN", color: Theme.danger)
                        .accessibilityIdentifier("history.stillClockedIn")
                } else if isInProgress {
                    StatusBadge(text: "IN PROGRESS", color: Theme.primary)
                }
                // Build 90 — a staff shift request reads like the time-fix /
                // delete chips beside it: yellow while the manager decides,
                // green for 14 days after approval (Nick: "It should show
                // yea"), then the row is just a visit. Denied requests never
                // reach this row — see ShiftRequestHistoryRow.
                if visit.isPendingApproval {
                    StatusBadge(text: "⏳ PENDING APPROVAL", color: Theme.warning)
                        .accessibilityIdentifier("history.shiftRequestPending")
                } else if visit.showsShiftApprovedChip {
                    StatusBadge(text: "SHIFT APPROVED", color: Theme.success)
                        .accessibilityIdentifier("history.shiftRequestApproved")
                }
                // Unsynced badge for offline events
                if visit.syncState == .pending {
                    StatusBadge(text: "⏳ Unsynced", color: Theme.warning)
                }
                // Note status
                if visit.hasNote {
                    StatusBadge(text: "📝 Note", color: Theme.success)
                }
                // Doc status
                if !isInProgress, let ds = visit.serverDocStatus, !ds.isEmpty {
                    StatusBadge(text: ds.capitalized, color: ds.lowercased() == "complete" ? Theme.success : Theme.warning)
                }
                // Pending request badges
                if visit.timeFixStatus == .pending {
                    StatusBadge(text: "⏳ time fix requested", color: Theme.warning)
                } else if visit.timeFixStatus == .approved {
                    StatusBadge(text: "FIX APPROVED", color: Theme.success)
                } else if visit.timeFixStatus == .denied {
                    StatusBadge(text: "FIX DENIED", color: Theme.danger)
                }
                if visit.deleteRequestStatus == .pending {
                    StatusBadge(text: "⏳ delete requested", color: Theme.warning)
                } else if visit.deleteRequestStatus == .approved {
                    StatusBadge(text: "DELETE APPROVED", color: Theme.success)
                } else if visit.deleteRequestStatus == .denied {
                    StatusBadge(text: "DELETE DENIED", color: Theme.danger)
                }
                Spacer()
            }

            if isStaleOpen {
                Label("You never clocked out of this visit. Clock out now so you can clock in again.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Action buttons
            HStack(spacing: 16) {
                if isInProgress, let onClockOut = onClockOut {
                    Button(action: onClockOut) {
                        Label("Clock Out", systemImage: "stop.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Theme.danger)
                    }
                    .accessibilityIdentifier("history.clockOut")
                }
                Button(action: onAddNote) {
                    Label(visit.hasNote ? "Update Note" : "Add Note", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(Theme.primary)
                }
                // Build 53: no Time Fix / Delete on a running visit (Nick,
                // 2026-09-02 answer 3: read-only until clock-out).
                if !isInProgress && visit.timeFixStatus == .none {
                    Button("Time Fix", action: onTimeFix)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(Theme.primary)
                }
                if !isInProgress && visit.deleteRequestStatus == .none {
                    Button("Delete", action: onRequestDelete)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(Theme.danger)
                }
                Spacer()
            }
        }
        .cardStyle()
    }
}

// MARK: - Server Add Note Sheet

struct ServerAddNoteSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let visit: Visit

    @State private var noteText = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Visit")) {
                    HStack {
                        AvatarView(name: visit.client.name, size: 36)
                        VStack(alignment: .leading) {
                            Text(visit.client.name).font(.headline)
                            Text(visit.serviceLabel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("Note")) {
                    TextEditor(text: $noteText)
                        .frame(minHeight: 120)
                }

                if let error = errorMessage {
                    Section {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Theme.danger)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(Theme.danger)
                        }
                    }
                }

                Section {
                    Button(action: submit) {
                        if isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Submit Note")
                                .frame(maxWidth: .infinity)
                                .font(.headline)
                        }
                    }
                    .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            }
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Note submitted", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your note has been saved.")
            }
        }
        // Build 75: 'Update Note' TextEditor.
        .keyboardDismissable()
    }

    private func submit() {
        guard let svid = visit.serverVisitId else { return }
        let text = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil

        Task {
            await appState.submitServerNote(visitId: visit.id, serverVisitId: svid, text: text)
            await MainActor.run {
                isSubmitting = false
                showSuccess = true
            }
        }
    }
}

// MARK: - Shift request in History (build 90, Todoist 6hXrQ7VjHH3C7q8q)

/// THE rule for how long a decided shift request stays visible in History:
/// 14 days from the DECISION (approve/deny), not from the shift date. A
/// pending request never expires. Shared by the visit-row chip
/// (`Visit.showsShiftApprovedChip`) and the stand-in row, so the two cannot
/// disagree. Nick, 2026-09-21: "It should only show for 2 weeks after the
/// approval/denial."
enum ShiftRequestHistoryPolicy {
    static let windowDays = 14

    /// Server timestamps are ISO-8601 (`resolutionTimestamp()` /
    /// `toISOString()`), with or without fractional seconds.
    static func parseISO(_ s: String?) -> Date? {
        guard let s = s, !s.isEmpty else { return nil }
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    static func isWithinWindow(decidedAt: Date, now: Date = Date()) -> Bool {
        let cutoff = Calendar.current.date(byAdding: .day, value: -windowDays, to: now) ?? now
        return decidedAt >= cutoff
    }

    /// "pending" | "approved" | "denied" for a 'Shift request' row. Prefers
    /// the server's joined visit state; falls back to the exception's own
    /// status/resolution on an older server.
    static func outcome(_ r: ServerException) -> String {
        if let o = r.shiftRequest?.outcome?.lowercased(), !o.isEmpty { return o }
        if (r.status ?? "").lowercased() != "resolved" { return "pending" }
        let res = (r.resolution ?? "").lowercased()
        return res == "approved" ? "approved" : (res == "denied" ? "denied" : "resolved")
    }

    static func decidedAt(_ r: ServerException) -> Date? {
        parseISO(r.shiftRequest?.decidedAt) ?? parseISO(r.decidedAt)
    }

    /// Should this request row be drawn at all (given no visit covers it)?
    /// Pending → always. Decided → only inside the 14-day window; a decided
    /// row whose timestamp is unknown (very old server) is hidden rather than
    /// shown forever.
    static func isVisible(_ r: ServerException, now: Date = Date()) -> Bool {
        let o = outcome(r)
        if o == "pending" { return true }
        guard let at = decidedAt(r) else { return false }
        return isWithinWindow(decidedAt: at, now: now)
    }

    /// The SHIFT's agency day ("yyyy-MM-dd") — the row sorts under that day.
    static func shiftDay(_ r: ServerException) -> String? {
        let raw = r.shiftRequest?.date ?? r.date
        guard let d = raw, d.count >= 10 else { return nil }
        return String(d.prefix(10))
    }
}

/// A shift request with NO visit in the list — a DENIED one (the visit was
/// soft-deleted), or one decided for a shift older than the history window.
/// Same layout as a visit row (avatar + name, service, time range) with the
/// status chip and the manager's reason; NO action buttons — there is no
/// visit to act on.
struct ShiftRequestHistoryRow: View {
    let request: ServerException

    private var summary: ShiftRequestSummary? { request.shiftRequest }
    private var outcome: String { ShiftRequestHistoryPolicy.outcome(request) }

    private var badge: (text: String, color: Color) {
        switch outcome {
        case "pending": return ("⏳ PENDING APPROVAL", Theme.warning)
        case "approved": return ("SHIFT APPROVED", Theme.success)
        case "denied": return ("SHIFT DENIED", Theme.danger)
        default: return ("RESOLVED", Theme.success)
        }
    }

    private var name: String {
        summary?.clientName ?? "Shift request"
    }

    private var serviceLabel: String {
        summary?.serviceName ?? summary?.service ?? ""
    }

    private var timeText: String? {
        guard let s = summary, let a = s.clockIn, let b = s.clockOut else { return nil }
        return "\(a) – \(b)"
    }

    /// Manager's reason (denial) — from the joined visit when the server sends
    /// it, else the outcome trailer the server writes into `detail`.
    private var reasonText: String? {
        if outcome == "denied" {
            if let r = summary?.denialReason, !r.isEmpty { return "Denied: \(r)" }
            if let d = request.detail, let range = d.range(of: "DENIED by ") {
                return String(d[range.lowerBound...]).replacingOccurrences(of: " The visit and its documentation were removed.", with: "")
            }
        }
        return nil
    }

    /// Older server (no `shiftRequest`): fall back to the request prose so the
    /// row still says what it was for.
    private var fallbackDetail: String? {
        guard summary == nil else { return nil }
        var s = request.detail ?? "Shift request"
        s = s.replacingOccurrences(of: " Approving makes this a normal billable visit; denying removes the visit AND its documentation.", with: "")
        s = s.replacingOccurrences(of: "Staff-requested shift ", with: "")
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 12) {
                    AvatarView(name: name, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.headline)
                        if !serviceLabel.isEmpty {
                            Text(serviceLabel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
                if let t = timeText {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Requested").font(.headline).foregroundColor(.secondary)
                        Text(t)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            HStack(spacing: 6) {
                StatusBadge(text: badge.text, color: badge.color)
                    .accessibilityIdentifier("history.shiftRequest.\(outcome)")
                Spacer()
            }

            if let r = reasonText {
                Text(r)
                    .font(.caption)
                    .foregroundColor(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let d = fallbackDetail {
                Text(d)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if outcome == "pending" {
                Text("Your manager decides this in Exceptions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .cardStyle()
    }
}
