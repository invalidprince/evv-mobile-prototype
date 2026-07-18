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

    var body: some View {
        NavigationView {
            Group {
                switch step {
                case .docGate: docGateView
                case .signature: SignatureStepView(onDone: { step = .confirm }, onSkip: { step = .confirm })
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

    // MARK: - Confirm
    private var confirmView: some View {
        VStack(spacing: 20) {
            Spacer()
            AvatarView(name: visit.client.name, size: 64)
            Text(visit.clients.map { $0.name }.joined(separator: " & "))
                .font(.title3.bold())
            Text(visit.service.rawValue)
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                Circle().fill(Theme.success).frame(width: 8, height: 8)
                Text("GPS location acquired").font(.subheadline)
            }
            Spacer()
            Button(action: doClockOut) {
                Label("Confirm Clock Out", systemImage: "stop.circle.fill")
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.danger))
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .background(Theme.screenBackground.ignoresSafeArea())
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
        completedVisit = appState.clockOut()
        step = .complete
    }
}
