import SwiftUI

struct SignatureStepView: View {
    let onDone: () -> Void
    let onSkip: (String) -> Void  // skip reason passed back
    @State private var lines: [[CGPoint]] = []
    @State private var currentLine: [CGPoint] = []
    @State private var showSkipReason = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Client / Guardian Signature")
                .font(.title3.bold())
                .padding(.top, 24)
            Text("Optional — have the client or guardian sign below.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            SignaturePad(lines: $lines, currentLine: $currentLine)
                .frame(height: 240)
                .background(Theme.cardBackground)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6]))
                )
                .padding(.horizontal)

            Button("Clear") {
                lines = []
                currentLine = []
            }
            .font(.subheadline.weight(.medium))
            .disabled(lines.isEmpty && currentLine.isEmpty)

            Spacer()

            VStack(spacing: 12) {
                Button("Accept Signature") { onDone() }
                    .buttonStyle(PrimaryButtonStyle(enabled: !lines.isEmpty))
                    .disabled(lines.isEmpty)
                Button("Skip Signature") { showSkipReason = true }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .background(Theme.screenBackground.ignoresSafeArea())
        .sheet(isPresented: $showSkipReason) {
            SignatureSkipReasonSheet(onSubmit: { reason in
                showSkipReason = false
                onSkip(reason)
            })
        }
    }
}

// MARK: - Skip Reason Sheet

struct SignatureSkipReasonSheet: View {
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason = ""
    @State private var customReason = ""

    private let reasons = [
        "Client unable to sign",
        "Client refused to sign",
        "Guardian not present",
        "Client nonverbal / physical limitation",
        "Emergency situation",
        "Other"
    ]

    private var finalReason: String {
        if selectedReason == "Other" {
            return customReason.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return selectedReason
    }

    private var canSubmit: Bool {
        if selectedReason.isEmpty { return false }
        if selectedReason == "Other" {
            return !customReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Why is the signature being skipped?")) {
                    ForEach(reasons, id: \.self) { reason in
                        Button(action: { selectedReason = reason }) {
                            HStack {
                                Text(reason).foregroundColor(.primary)
                                Spacer()
                                if selectedReason == reason {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Theme.primary)
                                }
                            }
                        }
                    }
                }

                if selectedReason == "Other" {
                    Section(header: Text("Please describe")) {
                        TextField("Reason for skipping signature…", text: $customReason)
                    }
                }

                Section {
                    Button(action: { onSubmit(finalReason) }) {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                    .disabled(!canSubmit)
                }
            }
            .navigationTitle("Skip Reason")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct SignaturePad: View {
    @Binding var lines: [[CGPoint]]
    @Binding var currentLine: [CGPoint]

    var body: some View {
        ZStack {
            if lines.isEmpty && currentLine.isEmpty {
                Text("Sign here")
                    .font(.title3)
                    .foregroundColor(.secondary.opacity(0.4))
            }
            Canvas { context, _ in
                for line in lines + [currentLine] {
                    guard line.count > 1 else { continue }
                    var path = Path()
                    path.move(to: line[0])
                    for point in line.dropFirst() {
                        path.addLine(to: point)
                    }
                    context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    currentLine.append(value.location)
                }
                .onEnded { _ in
                    if currentLine.count > 1 {
                        lines.append(currentLine)
                    }
                    currentLine = []
                }
        )
    }
}
