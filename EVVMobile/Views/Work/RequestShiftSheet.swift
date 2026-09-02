import SwiftUI

// MARK: - Request a shift (staff-requested shift, server v0.4.348, build 51)
//
// "I worked a shift that isn't in the system" — the primary case Nick named is
// someone entirely forgot to clock in. Staff picks individual + service + date
// + in/out times, submits, and IMMEDIATELY documents the visit. The visit sits
// in a Pending-approval state until the department manager approves; a denial
// removes the visit and its documentation (soft-deleted server-side).
//
// Rules baked in:
// - Individuals come from the SAME scoped roster the unscheduled sheet uses
//   (GET /api/individuals, v0.4.320 visibleClientsFor) — never a second list.
// - No fixed-height ScrollView clipping inside the Form — proportional cap,
//   count in the section header (the v0.4.320 / build 43 lesson).
// - ONLINE-ONLY, never queued: the server's duplicate/overlap checks must run
//   at submit time, and the whole point is dropping straight into
//   documentation for a visit that exists.
// - The server is the control: future dates and >14-day lookback are blocked
//   by the pickers here AND refused server-side; overlaps come back as a 409
//   naming the conflicting visit.
struct RequestShiftSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Called with the created (pending) visit — the parent routes straight
    /// into DocumentationView for it.
    let onCreated: (Visit) -> Void

    @State private var selectedIndividualId: String?
    @State private var selectedServiceName: String = ""
    @State private var searchText = ""
    @State private var visitDate: Date = Date()
    @State private var startTime: Date = Calendar.current.date(byAdding: .hour, value: -4, to: Date()) ?? Date()
    @State private var endTime: Date = Date()
    @State private var reason = ""
    @State private var isSubmitting = false
    @State private var submitError: String?

    private var online: Bool { appState.effectivelyOnline }

    /// Same lookback the server enforces (resolveManualDate, 14 days).
    private var dateRange: ClosedRange<Date> {
        let today = Calendar.current.startOfDay(for: Date())
        let earliest = Calendar.current.date(byAdding: .day, value: -14, to: today) ?? today
        return earliest...Date()
    }

    private var selectedIndividual: ServerIndividualOption? {
        guard let id = selectedIndividualId else { return nil }
        return appState.serverIndividuals.first { $0.id == id }
    }

    /// Services authorized for the selected individual (descriptions — the
    /// server resolves either a code or a description).
    private var availableServices: [String] {
        (selectedIndividual?.services ?? []).sorted()
    }

    private var filteredIndividuals: [ServerIndividualOption] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return appState.serverIndividuals }
        return appState.serverIndividuals.filter { $0.name.lowercased().contains(trimmed) }
    }

    /// Count in the header — the affordance that turns a silent clip into a
    /// visible one (v0.4.320 / build 43).
    private var individualsSectionTitle: String {
        let n = filteredIndividuals.count
        return n > 0 ? "Individual — \(n)" : "Individual"
    }

    /// Proportional cap: never clip a short roster, still bounded for long ones.
    private var individualsListMaxHeight: CGFloat {
        min(CGFloat(max(filteredIndividuals.count, 1)) * 56 + 8, 400)
    }

    private var timesValid: Bool { endTime > startTime }

    /// Build 56 — reason is REQUIRED (Nick 2026-09-02: "Reason should be
    /// required on iOS and web"). The server (v0.4.393) refuses without one;
    /// this keeps the button honest instead of round-tripping a 400.
    private var trimmedReason: String { reason.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSubmit: Bool {
        online && !isSubmitting && selectedIndividualId != nil
            && !selectedServiceName.isEmpty && timesValid && !trimmedReason.isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                if !online {
                    Section {
                        Label("You're offline. Shift requests need a connection — they're checked against your existing visits when you submit.", systemImage: "wifi.slash")
                            .font(.subheadline)
                            .foregroundColor(Theme.danger)
                    }
                }

                Section(header: Text(individualsSectionTitle),
                        footer: Text("Who you worked with. Only individuals you have access to are listed.")) {
                    if appState.isLoadingIndividuals && appState.serverIndividuals.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading individuals…")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else if appState.serverIndividuals.isEmpty {
                        Text(online ? "No active individuals found" : "Connect to the internet once to load individuals")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        TextField("Search…", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredIndividuals) { individual in
                                    Button(action: { select(individual) }) {
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
                                            if selectedIndividualId == individual.id {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(Theme.success)
                                            }
                                        }
                                        .padding(.vertical, 10)
                                    }
                                    Divider()
                                }
                            }
                        }
                        .frame(maxHeight: individualsListMaxHeight)
                    }
                }

                Section(header: Text("Service")) {
                    if selectedIndividualId == nil {
                        Text("Select an individual first")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else if availableServices.isEmpty {
                        Text("No authorized services")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        Picker("Service", selection: $selectedServiceName) {
                            ForEach(availableServices, id: \.self) { svcName in
                                Text(svcName).tag(svcName)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }

                Section(header: Text("When"),
                        footer: Text("Up to 14 days back — this records a shift that already happened, it doesn't schedule one.")) {
                    DatePicker("Date", selection: $visitDate, in: dateRange, displayedComponents: .date)
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                    if !timesValid {
                        Label("End time must be after the start time.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(Theme.danger)
                    }
                }

                Section(header: Text("Reason (required)"),
                        footer: trimmedReason.isEmpty
                            ? Text("Tell your manager why this shift isn't in the system.").foregroundColor(Theme.danger)
                            : Text("")) {
                    TextField("e.g. Forgot to clock in", text: $reason)
                }

                if let err = submitError {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundColor(Theme.danger)
                    }
                }

                Section(footer: Text("Your manager must approve this shift. You'll document it now — if the request is denied, the visit and its documentation are removed.")) {
                    Button(action: submit) {
                        if isSubmitting {
                            HStack {
                                ProgressView()
                                Text("Submitting…")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Label("Submit & Document Now", systemImage: "square.and.pencil")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .navigationTitle("Request a Shift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                Task { await appState.refreshIndividuals() }
            }
        }
    }

    private func select(_ individual: ServerIndividualOption) {
        selectedIndividualId = individual.id
        let services = (individual.services ?? []).sorted()
        if !services.contains(selectedServiceName) {
            selectedServiceName = services.first ?? ""
        }
    }

    // MARK: - Submit

    /// Server's "h:mm a" time label (agency timezone) — same formatting the
    /// manual-time path uses.
    private func serverTimeLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    private func serverDateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Cosmetic ServiceType mapping — same heuristic the unscheduled sheet
    /// uses. The real service string travels to the server verbatim.
    private func mapServiceNameToType(_ name: String) -> ServiceType {
        let lower = name.lowercased()
        if lower.contains("home") || lower.contains("in-home") { return .inHomeSupport }
        if lower.contains("community") && lower.contains("participation") { return .communityParticipation }
        if lower.contains("companion") { return .companion }
        if lower.contains("respite") { return .respite }
        return .inHomeSupport
    }

    private func submit() {
        guard let individual = selectedIndividual, canSubmit else { return }
        isSubmitting = true
        submitError = nil

        // Combine the picked date with the picked times so the labels sent to
        // the server describe the visit day, not today.
        let cal = Calendar.current
        let startCombined = combine(day: visitDate, time: startTime, calendar: cal)
        let endCombined = combine(day: visitDate, time: endTime, calendar: cal)

        Task {
            do {
                let resp = try await APIClient.shared.requestShift(
                    clientId: individual.id,
                    service: selectedServiceName,
                    date: serverDateLabel(visitDate),
                    startTime: serverTimeLabel(startCombined),
                    endTime: serverTimeLabel(endCombined),
                    reason: reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? nil : reason.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                await MainActor.run {
                    isSubmitting = false
                    // Build the Visit the documentation screen needs. The
                    // server visit id is the only field DocumentationView
                    // actually submits against; the rest is display.
                    let client = Client(id: UUID(), name: individual.name,
                                        address: individual.id, city: "")
                    var visit = Visit(
                        id: UUID(),
                        clients: [client],
                        service: mapServiceNameToType(selectedServiceName),
                        scheduledStart: startCombined,
                        scheduledEnd: endCombined,
                        actualStart: startCombined,
                        actualEnd: endCombined,
                        status: .completed
                    )
                    visit.serverVisitId = resp.visit.id
                    visit.approvalStatus = resp.visit.approvalStatus ?? "pending"
                    visit.serverDocStatus = "incomplete"
                    onCreated(visit)
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    let apiErr = error as? APIError ?? .networkError(error)
                    submitError = apiErr.errorDescription ?? "Could not submit the shift request."
                }
            }
        }
    }

    private func combine(day: Date, time: Date, calendar: Calendar) -> Date {
        let d = calendar.dateComponents([.year, .month, .day], from: day)
        let t = calendar.dateComponents([.hour, .minute], from: time)
        var c = DateComponents()
        c.year = d.year; c.month = d.month; c.day = d.day
        c.hour = t.hour; c.minute = t.minute
        return calendar.date(from: c) ?? day
    }
}
