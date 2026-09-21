import SwiftUI

// MARK: - Manual-entry back-date policy (build 62)
//
// Nick, #evv 2026-09-09 (screenshot of this sheet): "There's no way to put a
// date on this like you can on desktop. Just fix this." Staff need to record a
// visit they forgot on a PRIOR day (his example: yesterday's Lifesharing day).
//
// The window is the acting ROLE's, published by the server on GET
// /api/me/shifts (`manualBackdateMaxDays`, v0.4.436) from the SAME helper the
// POST enforces (`visit-core.backdateMaxDaysFor`) and the same value the
// desktop my-day view renders — recomputing it on the phone is exactly how a
// picker and its validator drift apart (the v0.4.364 lesson).
//
// Lives here as a tiny observable (the build-58 ShiftRequestPolicy pattern) so
// the sheet re-renders when the value arrives; APIClient.fetchShiftsResponse
// updates it on every Today refresh. The POST re-resolves and enforces the
// window regardless — this only shapes the picker.
@MainActor
final class ManualEntryPolicy: ObservableObject {
    static let shared = ManualEntryPolicy()
    /// Default matches the server's MANUAL_BACKDATE_MAX_DAYS. Only a fallback:
    /// a value the server DID send always wins, including 0.
    @Published var maxDays: Int = ManualSpan.defaultBackdateMaxDays

    func update(from response: ShiftsResponse) {
        // ⚠️ `0` is a real answer meaning "today only" — an `if let n = …, n > 0`
        // here would silently hand a today-only role a 30-day picker whose
        // every back-dated save 400s.
        if let n = response.manualBackdateMaxDays, n >= 0, n <= 366, n != maxDays {
            maxDays = n
        }
    }
}

struct UnscheduledVisitSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showSuccess = false

    var body: some View {
        if appState.mode == .server {
            ServerUnscheduledContent(showSuccess: $showSuccess, onDismiss: { dismiss() })
                .environmentObject(appState)
        } else {
            MockUnscheduledContent(showSuccess: $showSuccess, onDismiss: { dismiss() })
                .environmentObject(appState)
        }
    }
}

// MARK: - Server Mode (real individuals from API)

struct ServerUnscheduledContent: View {
    @EnvironmentObject var appState: AppState
    @Binding var showSuccess: Bool
    let onDismiss: () -> Void
    @State private var selectedIndividualIds: Set<String> = []
    @State private var selectedServiceName: String = ""
    @State private var searchText = ""
    // F2: Unlisted individual
    @State private var isUnlisted = false
    @State private var unlistedName = ""
    @State private var unlistedServiceName: String = ""
    // Manual time entry (non-EVV services). Build 55: both boxes open at
    // MIDNIGHT (12:00 AM → 12:00 AM), matching the desktop's
    // MANUAL_TIME_PLACEHOLDER — the app no longer guesses now-1h → now
    // (Nick 2026-09-02: "Make the mobile manual-time defaults match the
    // desktop behavior (12 AM – 12 AM)"). See ManualSpan.
    @State private var manualStart: Date = ManualSpan.midnightToday()
    @State private var manualEnd: Date = ManualSpan.midnightToday()
    // Build 62: the DAY the time was worked. Defaults to TODAY, so an entry
    // made the same day behaves exactly as it did before this picker existed.
    @State private var manualDate: Date = ManualSpan.midnightToday()
    @ObservedObject private var manualPolicy = ManualEntryPolicy.shared
    @State private var manualConfirmMessage: String?
    @State private var showManualConfirm = false
    @State private var pendingManualSubmit: (() -> Void)?
    // Build 54: manual entries await the server before showing success.
    // `manualSubmitError` is the server's refusal, shown INLINE (the
    // root-level alert cannot present behind a sheet + success cover — which
    // is exactly how Nick's 409 went unseen on 2026-09-02).
    @State private var isSubmittingManual = false
    @State private var manualSubmitError: String?
    @State private var successMessage: String?
    // Build 83 — LIVE clock-ins await the server too (the build-57 contract,
    // finally applied to this sheet). Nick, #evv 2026-09-21: his Alex Rivera
    // clock-in was refused 409 ("You already have a visit in progress" —
    // the Sep 3 Erik Hoover punch was still open) and the app "just said
    // 'clocked in' and didn't work": `showSuccess = true` fired before the
    // request left, and the refusal went to the root alert, which cannot
    // present behind a sheet + cover. Now: spinner while the server is asked,
    // green cover ONLY for `.synced` / `.queued`, and a refusal INLINE — with
    // the blocking visit named and a button to go to it.
    @State private var isSubmittingLive = false
    @State private var liveSubmitError: String?
    @State private var liveBlockingVisit: BlockingVisit?
    // Build 80 — HOW is this visit delivered? Nick, #evv 2026-09-21 (video:
    // Connor Couldridge → Behavioral Supports – Level 1 → Clock In Now, no
    // question asked): "it never asked consult or direct". The dashboard has
    // asked since v0.4.509/v0.4.579 (delivery-mode.js): a consult-capable
    // service works EITHER as an in-person punch OR as a consult with typed
    // times. The server publishes which services qualify (`consultServices`
    // on the roster) and VALIDATES the answer on the POST — a consult on a
    // service that has not opted in is refused (400 consult_not_allowed)
    // regardless of what this sheet showed.
    //
    // 🔑 REQUIRED, NO DEFAULT. nil until the staff member taps one; the
    //    Clock In / Record Time button stays disabled until they do. The
    //    web pre-ticks "In person"; on a phone a pre-ticked radio is exactly
    //    how a consult gets punched by accident. Reset whenever the service
    //    or individual selection changes so a stale answer can never ride
    //    onto a different service.
    enum DeliveryChoice: String { case inPerson = "in_person", consult = "consult" }
    @State private var deliveryChoice: DeliveryChoice?
    // Location state (GPS-unavailable address fallback)
    @ObservedObject private var locationManager = LocationManager.shared
    @State private var fallbackAddress = ""

    private let maxIndividuals = 2  // 1:2 group visits are the max

    /// One active visit at a time — no new clock-in while a visit is running.
    private var punchBlocked: Bool { appState.hasActiveVisit }

    /// GPS could not be obtained (denied, restricted, or timed out) and no
    /// usable coordinates are available for the punch.
    private var gpsFailed: Bool {
        !locationManager.isAcquiring
            && locationManager.currentCoordinates == nil
            && (locationManager.locationError != nil
                || locationManager.authorizationStatus == .denied
                || locationManager.authorizationStatus == .restricted)
    }

    private var trimmedFallbackAddress: String? {
        let t = fallbackAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// A live EVV punch needs GPS or, failing that, a manually entered address.
    private var locationRequirementMet: Bool {
        !gpsFailed || trimmedFallbackAddress != nil
    }

    /// Combined enable check for the live clock-in buttons.
    private var clockInAllowed: Bool {
        !punchBlocked && !locationManager.isAcquiring && locationRequirementMet && !isSubmittingLive
    }

    /// True when the currently selected service does not require live EVV
    /// punches — staff enter the visit start/end times manually instead.
    private var selectedServiceIsNonEvv: Bool {
        guard !selectedServiceName.isEmpty else { return false }
        return appState.serverIndividuals
            .filter { selectedIndividualIds.contains($0.id) }
            .contains { ($0.nonEvvServices ?? []).contains(selectedServiceName) }
    }

    private var unlistedServiceIsNonEvv: Bool {
        guard !unlistedServiceName.isEmpty else { return false }
        return appState.serverIndividuals.contains { ($0.nonEvvServices ?? []).contains(unlistedServiceName) }
    }

    /// Build 80 — the selected service MAY be delivered as a consult (server-
    /// decided per service). Never true for a never-punch service: that one
    /// is already typed times every time, so there is nothing to ask.
    private var selectedServiceIsConsultCapable: Bool {
        guard !selectedServiceName.isEmpty, !selectedServiceIsNonEvv else { return false }
        return appState.serverIndividuals
            .filter { selectedIndividualIds.contains($0.id) }
            .contains { ($0.consultServices ?? []).contains(selectedServiceName) }
    }

    private var unlistedServiceIsConsultCapable: Bool {
        guard !unlistedServiceName.isEmpty, !unlistedServiceIsNonEvv else { return false }
        return appState.serverIndividuals.contains { ($0.consultServices ?? []).contains(unlistedServiceName) }
    }

    /// The In person / Consult question is on screen and must be answered.
    private var consultPromptActive: Bool {
        isUnlisted ? unlistedServiceIsConsultCapable : selectedServiceIsConsultCapable
    }

    /// The question is showing and nothing has been chosen yet — every
    /// start button is disabled while this is true.
    private var deliveryChoicePending: Bool { consultPromptActive && deliveryChoice == nil }

    /// The staff member chose Consult on a consult-capable service: the visit
    /// is a manual time entry (typed times, no punch), exactly as the web.
    private var consultChosen: Bool { consultPromptActive && deliveryChoice == .consult }

    /// What the POST carries. nil for every service that never asked (older
    /// servers and punch-only services see the byte-identical old payload).
    private var deliveryModeParam: String? { consultPromptActive ? deliveryChoice?.rawValue : nil }

    private var manualEntryActive: Bool {
        (isUnlisted ? unlistedServiceIsNonEvv : selectedServiceIsNonEvv) || consultChosen
    }

    /// Build 55: mirrors the desktop — there is NO "end must be after start"
    /// or "no future end" hard rule. end <= start crosses midnight (12→12 is
    /// a full 24h Lifesharing day).
    /// Build 65: the untouched-midnight / full-day confirm is GONE (Nick
    /// 2026-09-10) — only a FUTURE end still asks. Nothing here ever blocks.
    private var manualTimesValid: Bool { true }

    /// Footer under Visit Times: what the section is for, plus the role's
    /// actual back-date window (the desktop's per-role hint, v0.4.364).
    private var manualTimesFooter: String {
        (consultChosen
            ? "Consult delivery — enter the start and end times you worked. No clock in/out. "
            : "This service doesn't use live clock in/out — pick the date and enter the visit start and end times. ")
            + ManualSpan.backdateHint(maxDays: manualPolicy.maxDays)
    }

    /// Footer for the Individual(s) section — shows cache date hint when offline.
    private var cachedFooter: some View {
        Group {
            if isUnlisted {
                Text("Enter the individual's name manually.")
            } else if let cacheDate = appState.individualsFromCacheDate {
                let f = RelativeDateTimeFormatter()
                Text("Cached \(f.localizedString(for: cacheDate, relativeTo: Date())) \u{2022} Select up to \(maxIndividuals) for a group (1:2) visit.")
                    .foregroundColor(.secondary)
            } else {
                Text("Select up to \(maxIndividuals) for a group (1:2) visit.")
            }
        }
    }

    /// Authorized services = intersection of all selected individuals' service descriptions.
    /// If none selected, show empty (must select an individual first).
    private var authorizedServices: [String] {
        guard !selectedIndividualIds.isEmpty else { return [] }

        let selectedIndividuals = appState.serverIndividuals.filter { selectedIndividualIds.contains($0.id) }
        guard !selectedIndividuals.isEmpty else { return [] }

        // Start with first individual's services, intersect with each subsequent
        var intersection: Set<String>? = nil
        for individual in selectedIndividuals {
            let services = individual.services ?? []
            if services.isEmpty { continue }
            let svcSet = Set(services)
            if intersection == nil {
                intersection = svcSet
            } else {
                intersection = intersection!.intersection(svcSet)
            }
        }

        guard let final = intersection else { return [] }
        return final.sorted()
    }

    /// All available services (for unlisted individual — show every service from all individuals)
    private var allAvailableServices: [String] {
        var allSvcs = Set<String>()
        for individual in appState.serverIndividuals {
            for svc in (individual.services ?? []) {
                allSvcs.insert(svc)
            }
        }
        return allSvcs.sorted()
    }

    private var filteredIndividuals: [ServerIndividualOption] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return appState.serverIndividuals }
        return appState.serverIndividuals.filter { $0.name.lowercased().contains(trimmed) }
    }

    /// Section title carrying the visible count — the affordance that turns a
    /// silent clip into a visible one (build 43 / v0.4.320).
    private var individualsSectionTitle: String {
        let n = filteredIndividuals.count
        guard !isUnlisted, n > 0 else { return "Individual(s)" }
        return "Individual(s) — \(n)"
    }

    /// Proportional cap: never clip a short roster, still bounded for long ones.
    private var individualsListMaxHeight: CGFloat {
        min(CGFloat(max(filteredIndividuals.count, 1)) * 56 + 8, 400)
    }

    /// Message when selected individuals have no common services
    private var noCommonServicesMessage: String? {
        guard selectedIndividualIds.count > 1, authorizedServices.isEmpty else { return nil }
        let names = appState.serverIndividuals
            .filter { selectedIndividualIds.contains($0.id) }
            .map { $0.name }
            .joined(separator: " and ")
        return "\(names) have no services in common. Remove one to continue."
    }

    var body: some View {
        NavigationView {
            Form {
                // build 43 / v0.4.320 — the header carries the COUNT. Nick
                // reported "Erik Hoover is not showing" when the server was in
                // fact returning him: he was row 6 of 6 inside a scroll view
                // hard-clipped to 224pt, with no scroll indicator and no count,
                // so the list read as complete at row 4. A caregiver who can
                // see "6" will look for the 6th.
                Section(header: Text(individualsSectionTitle), footer: cachedFooter) {

                    // F2: Unlisted Individual toggle
                    Button(action: {
                        withAnimation {
                            isUnlisted.toggle()
                            if isUnlisted {
                                selectedIndividualIds.removeAll()
                                selectedServiceName = ""
                            } else {
                                unlistedName = ""
                                unlistedServiceName = ""
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: isUnlisted ? "person.fill.questionmark" : "person.fill.questionmark")
                                .foregroundColor(isUnlisted ? .white : Theme.primary)
                                .font(.title3)
                            Text("Unlisted Individual")
                                .foregroundColor(isUnlisted ? .white : .primary)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            if isUnlisted {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, isUnlisted ? 10 : 0)
                        .background(isUnlisted ? Theme.primary : Color.clear)
                        .cornerRadius(8)
                    }

                    if isUnlisted {
                        TextField("Enter individual name", text: $unlistedName)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        if appState.isLoadingIndividuals && appState.serverIndividuals.isEmpty {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Loading individuals…")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        } else if appState.serverIndividuals.isEmpty && !appState.effectivelyOnline {
                            // Offline with no cached data
                            VStack(spacing: 6) {
                                Image(systemName: "wifi.slash")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                Text("Connect to the internet once to load individuals")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 8)
                        } else if appState.serverIndividuals.isEmpty {
                            Text("No active individuals found")
                                .foregroundColor(.secondary)
                        } else {
                            TextField("Search…", text: $searchText)
                                .textFieldStyle(.roundedBorder)

                            // build 43 / v0.4.320 — the height cap is now
                            // PROPORTIONAL to the row count, so a short roster
                            // is never clipped. It used to be a flat
                            // `.frame(maxHeight: 224)` (~4 rows), which silently
                            // hid rows 5+ inside a Form that scrolls itself —
                            // indistinguishable from the individual not
                            // existing. The search field above handles genuinely
                            // long lists.
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(filteredIndividuals) { individual in
                                        Button(action: { toggleIndividual(individual) }) {
                                            HStack {
                                                AvatarView(name: individual.name, size: 36)
                                                VStack(alignment: .leading) {
                                                    Text(individual.name).foregroundColor(.primary)
                                                    if let services = individual.services, !services.isEmpty {
                                                        Text(services.joined(separator: ", "))
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                            .lineLimit(1)
                                                    }
                                                }
                                                Spacer()
                                                if selectedIndividualIds.contains(individual.id) {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(Theme.success)
                                                } else if selectedIndividualIds.count >= maxIndividuals {
                                                    Image(systemName: "circle")
                                                        .foregroundColor(.secondary.opacity(0.3))
                                                }
                                            }
                                            .padding(.vertical, 10)
                                        }
                                        .disabled(!selectedIndividualIds.contains(individual.id) && selectedIndividualIds.count >= maxIndividuals)

                                        Divider()
                                    }
                                }
                            }
                            .frame(maxHeight: individualsListMaxHeight)
                        }
                    }
                }

                Section(header: Text("Service"), footer: noCommonServicesMessage.map { Text($0).foregroundColor(Theme.danger) }) {
                    if isUnlisted {
                        // F2: Show all available services for unlisted individual
                        if allAvailableServices.isEmpty && !appState.effectivelyOnline {
                            VStack(spacing: 6) {
                                Image(systemName: "wifi.slash")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                Text("Connect to the internet once to load services")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 4)
                        } else if allAvailableServices.isEmpty {
                            Text("No services available")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        } else {
                            Picker("Service", selection: $unlistedServiceName) {
                                ForEach(allAvailableServices, id: \.self) { svcName in
                                    Text(svcName).tag(svcName)
                                }
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        }
                    } else if noCommonServicesMessage != nil {
                        Text("No common authorized services")
                            .foregroundColor(.secondary)
                    } else if !selectedIndividualIds.isEmpty && authorizedServices.isEmpty && !appState.effectivelyOnline {
                        VStack(spacing: 6) {
                            Image(systemName: "wifi.slash")
                                .font(.title3)
                                .foregroundColor(.secondary)
                            Text("Connect to the internet once to load services")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 4)
                    } else if !selectedIndividualIds.isEmpty && authorizedServices.isEmpty {
                        Text("No authorized services")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else if selectedIndividualIds.isEmpty {
                        Text("Select an individual first")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        Picker("Service", selection: $selectedServiceName) {
                            ForEach(authorizedServices, id: \.self) { svcName in
                                Text(svcName).tag(svcName)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }

                // Build 80 — the In person / Consult question, only for a
                // service the server says works both ways. Two tappable rows
                // (the app's own selection language — a checkmark on the
                // chosen row, like the individual picker above), REQUIRED.
                if consultPromptActive {
                    Section(header: Text("How is this visit delivered?"),
                            footer: Text(deliveryChoicePending
                                ? "Choose one to continue. In person clocks you in and out. Consult lets you enter the times you worked by hand — same authorization, same service, same units."
                                : (consultChosen
                                    ? "Consult — enter your start and end times below."
                                    : "In person — you will clock in and out."))) {
                        deliveryChoiceRow(.inPerson, title: "In person",
                                          detail: "Clock in and out with location",
                                          icon: "figure.walk")
                        deliveryChoiceRow(.consult, title: "Consult",
                                          detail: "Enter the times you worked",
                                          icon: "bubble.left.and.bubble.right")
                    }
                }

                if manualEntryActive {
                    Section(header: Text("Visit Times"), footer: Text(manualTimesFooter)) {
                        // Build 62 — the DATE, the desktop's `<input type="date"
                        // id="uv-date">`. `in:` bounds the wheel to the role's
                        // window; the server re-checks BOTH bounds, so this is a
                        // courtesy, not the control.
                        DatePicker("Date", selection: $manualDate,
                                   in: ManualSpan.dateRange(maxDays: manualPolicy.maxDays),
                                   displayedComponents: .date)
                        DatePicker("Start", selection: $manualStart, displayedComponents: .hourAndMinute)
                        DatePicker("End", selection: $manualEnd, displayedComponents: .hourAndMinute)
                        // Desktop's live "8h 15m" / "24h 0m — spans midnight" hint,
                        // so a midnight-to-midnight entry visibly reads as a full
                        // day BEFORE saving. Build 62 names the day a crossing
                        // span ends on, now that the start day is selectable.
                        HStack {
                            Label("Duration", systemImage: "hourglass")
                            Spacer()
                            Text(ManualSpan.hint(start: manualStart, end: manualEnd, on: manualDate))
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        // A back-dated entry says so in plain words — the one
                        // thing a staff member must not get wrong is WHICH day
                        // they just recorded.
                        if !ManualSpan.isToday(manualDate) {
                            Label("Recording time for \(ManualSpan.dayLabel(manualDate))",
                                  systemImage: "calendar.badge.clock")
                                .font(.subheadline)
                                .foregroundColor(Theme.primary)
                        }
                    }
                    if let err = manualSubmitError {
                        Section(footer: Text("Nothing was saved. Adjust the times and try again.")) {
                            Label(err, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .foregroundColor(Theme.danger)
                        }
                    }
                }

                // Active-visit block + GPS status for live EVV punches
                if !manualEntryActive {
                    if punchBlocked {
                        Section {
                            // Build 83 — names the running visit (and says
                            // "from another day" when it is a stale one).
                            Label(appState.punchBlockedMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .foregroundColor(Theme.danger)
                            Button {
                                onDismiss()
                            } label: {
                                Label("Go to that visit to clock out", systemImage: "arrow.uturn.backward.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .accessibilityIdentifier("unscheduledGoToBlockingVisit")
                        }
                    } else if locationManager.isAcquiring {
                        Section(header: Text("Location")) {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Getting your location\u{2026}")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else if gpsFailed {
                        Section(header: Text("Location"),
                                footer: Text("GPS couldn't be captured. Enter the address where this service is being provided \u{2014} the visit will be flagged for manager review.")) {
                            Label("Location unavailable", systemImage: "location.slash.fill")
                                .font(.subheadline)
                                .foregroundColor(Theme.danger)
                            TextField("Service address (street, city, state)", text: $fallbackAddress)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    if let err = liveSubmitError {
                        Section(footer: Text("You were NOT clocked in. Nothing was saved.")) {
                            Label(err, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(Theme.danger)
                                .accessibilityIdentifier("unscheduledRejected")
                            if liveBlockingVisit != nil {
                                // The refusal already triggered a Today +
                                // History refresh, so the blocking visit is
                                // on Today (CLOCKED IN card + banner) by the
                                // time this sheet closes.
                                Button {
                                    onDismiss()
                                } label: {
                                    Label("Go to that visit to clock out", systemImage: "arrow.uturn.backward.circle.fill")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .accessibilityIdentifier("unscheduledGoToBlockingVisit")
                            }
                        }
                    }
                }

                Section {
                    if isUnlisted {
                        if unlistedServiceIsNonEvv || consultChosen {
                            // Non-EVV service: manual time entry
                            Button(action: startUnlistedManualVisit) {
                                manualRecordLabel
                            }
                            .disabled(unlistedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !manualTimesValid || isSubmittingManual)
                        } else {
                            // F2: Unlisted clock-in
                            Button(action: startUnlistedVisit) {
                                liveClockInLabel
                            }
                            .disabled(unlistedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || unlistedServiceName.isEmpty || !clockInAllowed || deliveryChoicePending)
                        }
                    } else if selectedServiceIsNonEvv || consultChosen {
                        // Non-EVV service: manual time entry
                        Button(action: startManualVisit) {
                            manualRecordLabel
                        }
                        .disabled(selectedIndividualIds.isEmpty || !manualTimesValid || isSubmittingManual)
                    } else {
                        Button(action: startVisit) {
                            liveClockInLabel
                        }
                        .disabled(selectedIndividualIds.isEmpty || selectedServiceName.isEmpty || !clockInAllowed || deliveryChoicePending)

                        // "Clock In Without Service" fallback
                        if !selectedIndividualIds.isEmpty && authorizedServices.isEmpty {
                            Button(action: startVisitWithoutService) {
                                Label(punchBlocked ? "Clock out first" : (isSubmittingLive ? "Clocking in…" : "Clock In Without Service"), systemImage: "exclamationmark.triangle.fill")
                                    .frame(maxWidth: .infinity)
                                    .foregroundColor(.orange)
                            }
                            .disabled(!clockInAllowed)
                        }
                    }
                }
            }
            .navigationTitle("Unscheduled Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
            .fullScreenCover(isPresented: $showSuccess, onDismiss: { onDismiss() }) {
                ClockInSuccessView(message: successMessage ?? (manualEntryActive ? "Time recorded" : nil))
            }
            // A picker bounded to today…today-N can still hold a stale value if
            // the window SHRINKS after the sheet opened (the policy arrives on
            // a later refresh). Clamp rather than submit a date the server will
            // refuse.
            .onChange(of: manualPolicy.maxDays) { _ in
                let range = ManualSpan.dateRange(maxDays: manualPolicy.maxDays)
                if manualDate < range.lowerBound { manualDate = range.lowerBound }
                if manualDate > range.upperBound { manualDate = range.upperBound }
            }
            .interactiveDismissDisabled(isSubmittingManual || isSubmittingLive)
            // Build 80 — a stale answer must never ride onto another service:
            // any change to what is being started clears the choice.
            .onChange(of: selectedServiceName) { _ in deliveryChoice = nil }
            .onChange(of: unlistedServiceName) { _ in deliveryChoice = nil }
            .onChange(of: selectedIndividualIds) { _ in deliveryChoice = nil }
            .onChange(of: isUnlisted) { _ in deliveryChoice = nil }
            // A refusal is about what was just tried; changing the attempt
            // clears it.
            .onChange(of: selectedIndividualIds) { _ in liveSubmitError = nil; liveBlockingVisit = nil }
            .onChange(of: isUnlisted) { _ in liveSubmitError = nil; liveBlockingVisit = nil }
            // Build 55: the desktop's two confirm() prompts (untouched 12:00 AM
            // placeholder / end time not yet reached) — a question, not a block.
            .alert("Confirm times", isPresented: $showManualConfirm, presenting: manualConfirmMessage) { _ in
                Button("Save") { pendingManualSubmit?(); pendingManualSubmit = nil }
                Button("Cancel", role: .cancel) { pendingManualSubmit = nil }
            } message: { msg in
                Text(msg)
            }
            .onAppear {
                // Always attempt a refresh; refreshIndividuals handles offline fallback
                Task { await appState.refreshIndividuals() }
                // Warm up a GPS fix so the punch (and any offline queue
                // snapshot) carries coordinates captured at punch time.
                Task { _ = await LocationManager.shared.acquireLocation() }
            }
        }
        // Build 75: unlisted-name / individual search / fallback-address fields.
        .keyboardDismissable()
    }

    /// One selectable row of the delivery-mode question (build 80).
    private func deliveryChoiceRow(_ choice: DeliveryChoice, title: String, detail: String, icon: String) -> some View {
        Button(action: {
            withAnimation { deliveryChoice = choice }
            manualSubmitError = nil
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(Theme.primary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundColor(.primary).font(.subheadline.weight(.medium))
                    Text(detail).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if deliveryChoice == choice {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.success)
                } else {
                    Image(systemName: "circle").foregroundColor(.secondary.opacity(0.3))
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier(choice == .consult ? "deliveryChoiceConsult" : "deliveryChoiceInPerson")
    }

    private func toggleIndividual(_ individual: ServerIndividualOption) {
        if selectedIndividualIds.contains(individual.id) {
            selectedIndividualIds.remove(individual.id)
        } else if selectedIndividualIds.count < maxIndividuals {
            selectedIndividualIds.insert(individual.id)
        }
        // Auto-select first authorized service if current selection isn't in the list
        if !authorizedServices.isEmpty && !authorizedServices.contains(selectedServiceName) {
            selectedServiceName = authorizedServices[0]
        }
    }

    /// "Clock In Now" / "Clocking in…" / "Clock out first" — one label for
    /// both live clock-in buttons.
    private var liveClockInLabel: some View {
        Group {
            if isSubmittingLive {
                HStack {
                    ProgressView()
                    Text("Clocking in…")
                }
                .frame(maxWidth: .infinity)
            } else {
                Label(punchBlocked ? "Clock out first" : (deliveryChoicePending ? "Choose In person or Consult" : "Clock In Now"), systemImage: "play.circle.fill")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Build 83 — success ONLY for a confirmed or durably-queued punch. A
    /// refusal keeps the sheet open with the server's message; a "still
    /// clocked in" refusal also names the blocking visit and offers to go to
    /// it. Mirrors `finishManual` (build 54) for the live path.
    private func finishLive(_ outcome: AppState.PunchOutcome) {
        isSubmittingLive = false
        switch outcome {
        case .synced:
            successMessage = nil          // "Clocked in h:mm a"
            showSuccess = true
        case .queued:
            successMessage = "Clock-in saved — will sync when online"
            showSuccess = true
        case .rejected(let message):
            liveSubmitError = message
            liveBlockingVisit = nil
        case .stillClockedIn(let message, let blocker):
            liveSubmitError = message
            liveBlockingVisit = blocker
        }
    }

    private func startVisit() {
        guard !isSubmittingLive else { return }
        // Guard against stale UI: never start while another visit is running.
        guard !appState.hasActiveVisit else {
            appState.haptic(.error)
            liveSubmitError = appState.punchBlockedMessage
            return
        }
        let selectedIndividuals = appState.serverIndividuals.filter { selectedIndividualIds.contains($0.id) }
        guard !selectedIndividuals.isEmpty, !selectedServiceName.isEmpty else { return }
        // Build 80 — never punch a consult-capable service without an answer.
        guard !deliveryChoicePending else { return }

        // Build Clients from the server individuals; store server ID in address field
        let clients = selectedIndividuals.map { individual in
            Client(
                id: UUID(),
                name: individual.name,
                address: individual.id,  // server individual ID for API call
                city: ""
            )
        }
        // Map selected service description to a ServiceType for backward compat
        let serviceType = mapServiceNameToType(selectedServiceName)
        let serviceName = selectedServiceName
        let address = trimmedFallbackAddress
        let mode = deliveryModeParam
        isSubmittingLive = true
        liveSubmitError = nil
        liveBlockingVisit = nil
        Task { @MainActor in
            let outcome = await appState.startUnscheduledVisit(clients: clients, service: serviceType, serviceName: serviceName,
                                                               manualAddress: address, deliveryMode: mode)
            finishLive(outcome)
        }
    }

    private func startVisitWithoutService() {
        guard !isSubmittingLive else { return }
        // Guard against stale UI: never start while another visit is running.
        guard !appState.hasActiveVisit else {
            appState.haptic(.error)
            liveSubmitError = appState.punchBlockedMessage
            return
        }
        let selectedIndividuals = appState.serverIndividuals.filter { selectedIndividualIds.contains($0.id) }
        guard !selectedIndividuals.isEmpty else { return }

        let clients = selectedIndividuals.map { individual in
            Client(
                id: UUID(),
                name: individual.name,
                address: individual.id,
                city: ""
            )
        }
        let address = trimmedFallbackAddress
        isSubmittingLive = true
        liveSubmitError = nil
        liveBlockingVisit = nil
        Task { @MainActor in
            let outcome = await appState.startUnscheduledVisitWithoutService(clients: clients, manualAddress: address)
            finishLive(outcome)
        }
    }

    /// "Record Time" button content — spinner while the server is being asked.
    private var manualRecordLabel: some View {
        Group {
            if isSubmittingManual {
                HStack {
                    ProgressView()
                    Text("Recording…")
                }
                .frame(maxWidth: .infinity)
            } else {
                Label("Record Time", systemImage: "pencil.circle.fill")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Build 54: success is rendered ONLY for a confirmed or durably-queued
    /// entry. A rejection keeps the sheet open with the server's message —
    /// never a green screen over a record that does not exist.
    private func finishManual(_ outcome: AppState.ManualEntryOutcome) {
        isSubmittingManual = false
        switch outcome {
        case .synced:
            successMessage = "Time recorded"
            showSuccess = true
        case .queued:
            successMessage = "Time saved — will sync when online"
            showSuccess = true
        case .rejected(let message), .stillClockedIn(let message, _):
            manualSubmitError = message
        }
    }

    /// Runs `submit` immediately, or after the desktop-mirroring confirmation
    /// when the times need one (ManualSpan.confirmationMessage). Build 65: the
    /// only surviving prompt is the future-end one, so a full-day 12→12 entry
    /// now saves on the first tap.
    private func confirmThenSubmitManual(_ submit: @escaping () -> Void) {
        if let msg = ManualSpan.confirmationMessage(start: manualStart, end: manualEnd, date: manualDate) {
            manualConfirmMessage = msg
            pendingManualSubmit = submit
            showManualConfirm = true
        } else {
            submit()
        }
    }

    // Manual time entry for a non-EVV service (listed individuals)
    private func startManualVisit() {
        guard !isSubmittingManual else { return }
        let selectedIndividuals = appState.serverIndividuals.filter { selectedIndividualIds.contains($0.id) }
        guard !selectedIndividuals.isEmpty, !selectedServiceName.isEmpty, manualTimesValid else { return }

        let clients = selectedIndividuals.map { individual in
            Client(
                id: UUID(),
                name: individual.name,
                address: individual.id,  // server individual ID for API call
                city: ""
            )
        }
        let serviceType = mapServiceNameToType(selectedServiceName)
        let serviceName = selectedServiceName
        let start = manualStart, end = manualEnd, date = manualDate
        let mode = deliveryModeParam
        confirmThenSubmitManual {
            isSubmittingManual = true
            manualSubmitError = nil
            Task { @MainActor in
                let outcome = await appState.startUnscheduledManualVisit(
                    clients: clients, service: serviceType, serviceName: serviceName,
                    start: start, end: end, date: date, deliveryMode: mode)
                finishManual(outcome)
            }
        }
    }

    // Manual time entry for a non-EVV service (unlisted individual)
    private func startUnlistedManualVisit() {
        guard !isSubmittingManual else { return }
        let name = unlistedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !unlistedServiceName.isEmpty, manualTimesValid else { return }

        let client = Client(id: UUID(), name: name, address: "", city: "")
        let serviceType = mapServiceNameToType(unlistedServiceName)
        let serviceName = unlistedServiceName
        let start = manualStart, end = manualEnd, date = manualDate
        let mode = deliveryModeParam
        confirmThenSubmitManual {
            isSubmittingManual = true
            manualSubmitError = nil
            Task { @MainActor in
                let outcome = await appState.startUnscheduledManualVisit(
                    clients: [client], service: serviceType, serviceName: serviceName,
                    unlistedName: name, start: start, end: end, date: date, deliveryMode: mode)
                finishManual(outcome)
            }
        }
    }

    // F2: Start visit for unlisted individual
    private func startUnlistedVisit() {
        guard !isSubmittingLive else { return }
        // Guard against stale UI: never start while another visit is running.
        guard !appState.hasActiveVisit else {
            appState.haptic(.error)
            liveSubmitError = appState.punchBlockedMessage
            return
        }
        let name = unlistedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !unlistedServiceName.isEmpty else { return }
        guard !deliveryChoicePending else { return }

        // Create a dummy Client with empty address (no server ID)
        let client = Client(id: UUID(), name: name, address: "", city: "")
        let serviceType = mapServiceNameToType(unlistedServiceName)
        let serviceName = unlistedServiceName
        let address = trimmedFallbackAddress
        let mode = deliveryModeParam
        isSubmittingLive = true
        liveSubmitError = nil
        liveBlockingVisit = nil
        Task { @MainActor in
            let outcome = await appState.startUnscheduledVisit(clients: [client], service: serviceType,
                                                               serviceName: serviceName, unlistedName: name,
                                                               manualAddress: address, deliveryMode: mode)
            finishLive(outcome)
        }
    }

    private func mapServiceNameToType(_ name: String) -> ServiceType {
        let lower = name.lowercased()
        if lower.contains("home") || lower.contains("in-home") { return .inHomeSupport }
        if lower.contains("community") && lower.contains("participation") { return .communityParticipation }
        if lower.contains("companion") { return .companion }
        if lower.contains("respite") { return .respite }
        return .inHomeSupport
    }
}

// MARK: - Mock Mode (existing demo data)

struct MockUnscheduledContent: View {
    @EnvironmentObject var appState: AppState
    @Binding var showSuccess: Bool
    let onDismiss: () -> Void
    @State private var selectedClients: Set<UUID> = []
    @State private var service: ServiceType = .inHomeSupport
    @State private var searchText = ""

    private let maxIndividuals = 2  // 2:1 shifts are the max

    private var chosenClients: [Client] {
        MockData.clients.filter { selectedClients.contains($0.id) }
    }

    private var filteredClients: [Client] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return MockData.clients }
        return MockData.clients.filter { $0.name.lowercased().contains(trimmed) }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Client(s)"), footer: Text("Select up to \(maxIndividuals) for a group (1:2) visit.")) {
                    TextField("Search…", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    ForEach(filteredClients) { client in
                        Button(action: { toggle(client) }) {
                            HStack {
                                AvatarView(name: client.name, size: 36)
                                VStack(alignment: .leading) {
                                    Text(client.name).foregroundColor(.primary)
                                    Text(client.city).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedClients.contains(client.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Theme.success)
                                } else if selectedClients.count >= maxIndividuals {
                                    // Show disabled state when at cap
                                    Image(systemName: "circle")
                                        .foregroundColor(.secondary.opacity(0.3))
                                }
                            }
                        }
                        .disabled(!selectedClients.contains(client.id) && selectedClients.count >= maxIndividuals)
                    }
                }

                Section(header: Text("Service")) {
                    Picker("Service", selection: $service) {
                        ForEach(ServiceType.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section(footer: appState.hasActiveVisit ? Text("Clock out of your current visit first.").foregroundColor(Theme.danger) : nil) {
                    Button(action: startVisit) {
                        Label(appState.hasActiveVisit ? "Clock out first" : "Clock In Now", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(selectedClients.isEmpty || appState.hasActiveVisit)

                    Button(action: quickPunch) {
                        Label("Quick Punch (details later)", systemImage: "bolt.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(appState.hasActiveVisit)
                }
            }
            .navigationTitle("Unscheduled Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
            .fullScreenCover(isPresented: $showSuccess, onDismiss: { onDismiss() }) {
                ClockInSuccessView()
            }
        }
        // Build 75: service search field.
        .keyboardDismissable()
    }

    private func toggle(_ client: Client) {
        if selectedClients.contains(client.id) {
            selectedClients.remove(client.id)
        } else if selectedClients.count < maxIndividuals {
            selectedClients.insert(client.id)
        }
        // If at max, tapping an unselected client does nothing (button is disabled)
    }

    private func startVisit() {
        guard !appState.hasActiveVisit else {
            appState.surfacePunchBlocked()
            return
        }
        let clients = chosenClients
        Task { @MainActor in
            // Mock mode never refuses — synchronous local append.
            _ = await appState.startUnscheduledVisit(clients: clients, service: service)
            showSuccess = true
        }
    }

    private func quickPunch() {
        guard !appState.hasActiveVisit else {
            appState.surfacePunchBlocked()
            return
        }
        let client = chosenClients.isEmpty ? [MockData.clients[0]] : chosenClients
        Task { @MainActor in
            _ = await appState.startUnscheduledVisit(clients: client, service: service)
            showSuccess = true
        }
    }
}
