import SwiftUI
import UIKit

struct SignatureStepView: View {
    let onDone: (String) -> Void
    let onSkip: (String) -> Void  // skip reason passed back
    @State private var lines: [[CGPoint]] = []
    @State private var currentLine: [CGPoint] = []
    @State private var padSize = CGSize(width: 600, height: 240)
    @State private var showSkipReason = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Client / Guardian Signature")
                .font(.title3.bold())
                .padding(.top, 24)
            Text("Optional — have the client or guardian sign below.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            GeometryReader { geometry in
                SignaturePad(lines: $lines, currentLine: $currentLine)
                    .onAppear { padSize = geometry.size }
                    .onChange(of: geometry.size) { padSize = $0 }
            }
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
                Button("Accept Signature") {
                    if let signature = renderedSignatureBase64() {
                        onDone(signature)
                    }
                }
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

    /// Renders the captured SwiftUI canvas points into a compact, standard
    /// base64 PNG. A fixed 600x240, 1x opaque image keeps payloads small while
    /// preserving enough detail for a readable signature.
    private func renderedSignatureBase64() -> String? {
        guard padSize.width > 0, padSize.height > 0, !lines.isEmpty else { return nil }

        let outputSize = CGSize(width: 600, height: 240)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        let image = renderer.image { rendererContext in
            let bounds = CGRect(origin: .zero, size: outputSize)
            UIColor.white.setFill()
            rendererContext.fill(bounds)

            let context = rendererContext.cgContext
            context.setStrokeColor(UIColor.black.cgColor)
            context.setLineWidth(2.5)
            context.setLineCap(.round)
            context.setLineJoin(.round)

            let scaleX = outputSize.width / padSize.width
            let scaleY = outputSize.height / padSize.height
            for line in lines where line.count > 1 {
                context.beginPath()
                context.move(to: CGPoint(x: line[0].x * scaleX, y: line[0].y * scaleY))
                for point in line.dropFirst() {
                    context.addLine(to: CGPoint(x: point.x * scaleX, y: point.y * scaleY))
                }
                context.strokePath()
            }
        }

        return image.pngData()?.base64EncodedString()
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
