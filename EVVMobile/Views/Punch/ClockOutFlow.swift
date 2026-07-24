import SwiftUI

struct ClockOutFlow: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let visit: Visit
    var thenClockIntoNext: Visit?

    enum Step {
        case docGate, signature, confirm, complete
    }

    @State private var step: Step = .docGate
    @State private var showDocumentation = false
    @State private var completedVisit: Visit?
    @State private var signatureSkipReason: String?
    @State private var showTimeFix = false
    @State private var timeFixWasSubmitted = false
    @State private var timeFixQueuedOffline = false

    private var docAlreadyComplete: Bool {
        appState.isDocComplete(visitId: visit.id)
    }

    var body: some View {
        NavigationView {
            Group {
                switch step {
                case .docGate: docGateView
                case .signature:
                    SignatureStepView(
                        onDone: { signatureSkipReason = nil; step = .confirm },
                        onSkip: { reason in signatureSkipReason = reason; step = .confirm }
                    )
                case .confirm: confirmView
                case .complete: completeView
                }
            }
            .navigationTitle("Clock Out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step != .complete {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showDocumentation, onDismiss: { step = .signature }) {
                NavigationView {
                    DocumentationView(visit: visit)
                }
            }
            .sheet(isPresented: $showTimeFix, onDismiss: {
                // B4: If a change request was submitted, auto-confirm clock out
                if timeFixWasSubmitted {
                    if !appState.effectivelyOnline {
                        timeFixQueuedOffline = true
                    }
                    doClockOut()
                }
            }) {
                TimeFixSheet(visit: visit, onSubmitted: {
                    timeFixWasSubmitted = true
                })
            }
            .onAppear {
                if step == .docGate && docAlreadyComplete { step = .signature }
            }
        }
    }

    // MARK: - Documentation gate
    private var docGateView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "doc.text.fill")
                .font(.system(size: 56))
                .foregroundColor(Theme.warning)
            Text("Visit documentation isn't finished")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text("Complete your visit note now, or continue and finish it later today.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 12) {
                Button("Complete Documentation Now") { showDocumentation = true }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Continue — Finish Later") { step = .signature }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .background(Theme.screenBackground.ignoresSafeArea())
    }

    // MARK: - Confirm (full summary)
    private var confirmView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                AvatarView(name: visit.client.name, size: 64)
                    .padding(.top, 24)
                Text(visit.clients.map { $0.name }.joined(separator: " & "))
                    .font(.title3.bold())

                // Summary card
                VStack(spacing: 0) {
                    summaryRow(icon: "calendar", label: "Date", value: formattedDate)
                    Divider().padding(.horizontal)
                    summaryRow(icon: "clock.fill", label: "Clock In", value: formattedClockIn)
                    Divider().padding(.horizontal)
                    summaryRow(icon: "clock.badge.checkmark.fill", label: "Clock Out", value: formattedNow)
                    Divider().padding(.horizontal)
                    summaryRow(icon: "person.fill", label: "Client(s)", value: visit.clients.map { $0.name }.joined(separator: ", "))
                    Divider().padding(.horizontal)
                    summaryRow(icon: "briefcase.fill", label: "Service", value: visit.service.rawValue)
                    if let loc = locationText {
                        Divider().padding(.horizontal)
                        summaryRow(icon: "mappin.and.ellipse", label: "Location", value: loc)
                    }
                    if let skipReason = signatureSkipReason {
                        Divider().padding(.horizontal)
                        summaryRow(icon: "signature", label: "Signature", value: "Skipped: \(skipReason)")
                    }
                }
                .background(Theme.cardBackground)
                .cornerRadius(12)
                .padding(.horizontal)

                // GPS status
                if appState.simulateGPSUnavailable {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Circle().fill(Theme.danger).frame(width: 8, height: 8)
                            Text("GPS unavailable").font(.subheadline).foregroundColor(Theme.danger)
                        }
                        Text("Manual location on file — flagged for manager review")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.success).frame(width: 8, height: 8)
                        Text("GPS location acquired").font(.subheadline)
                    }
                }

                // Duration
                if let start = visit.actualStart {
                    let mins = Int(Date().timeIntervalSince(start) / 60)
                    Text("Duration: \(mins / 60)h \(mins % 60)m")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 12)

                VStack(spacing: 12) {
                    Button(action: doClockOut) {
                        Label("Confirm Clock Out", systemImage: "stop.circle.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.danger))

                    Button(action: {
                        showTimeFix = true
                    }) {
                        Label("Request a Change", systemImage: "pencil.circle")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
        .background(Theme.screenBackground.ignoresSafeArea())
    }

    // MARK: - Summary row helper
    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Formatting helpers
    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d, yyyy"
        return f.string(from: visit.actualStart ?? Date())
    }

    private var formattedClockIn: String {
        guard let start = visit.actualStart else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: start)
    }

    private var formattedNow: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: Date())
    }

    private var locationText: String? {
        if let loc = visit.serverLocation, !loc.isEmpty { return loc }
        if let addr = visit.manualLocation { return addr.display }
        let addr = visit.client.address
        if !addr.isEmpty { return addr }
        return nil
    }

    // MARK: - Complete
    private var completeView: some View {
        ZStack {
            Theme.success.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 110))
                    .foregroundColor(.white)
                Text("Visit complete")
                    .font(.title.bold())
                    .foregroundColor(.white)
                Text(completedVisit?.durationText ?? "")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.9))
                if timeFixQueuedOffline {
                    Text("Change request will sync when you\u{2019}re back online.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                }
                if thenClockIntoNext != nil {
                    Text("Clocking into next visit…")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                if let next = thenClockIntoNext {
                    appState.clockIn(visitId: next.id)
                }
                dismiss()
            }
        }
    }

    private func doClockOut() {
        completedVisit = appState.clockOut(signatureSkipReason: signatureSkipReason)
        step = .complete
    }
}
