import SwiftUI

/// A microphone button that records speech and appends transcribed text
/// to the bound string. Shows a pulsing animation while recording.
struct DictationButton: View {
    @Binding var text: String
    @StateObject private var speech = SpeechRecognizer()
    @State private var showPermissionAlert = false
    @State private var previousText = ""
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        Button(action: toggle) {
            Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                .font(.title2)
                .foregroundColor(speech.isRecording ? Theme.danger : Theme.primary)
                .scaleEffect(pulseScale)
                .animation(
                    speech.isRecording
                        ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                        : .default,
                    value: pulseScale
                )
        }
        .accessibilityLabel(speech.isRecording ? "Stop dictation" : "Start dictation")
        .onChange(of: speech.isRecording) { recording in
            pulseScale = recording ? 1.2 : 1.0
        }
        .onChange(of: speech.transcript) { newValue in
            guard !newValue.isEmpty else { return }
            let separator = previousText.isEmpty || previousText.hasSuffix(" ") || previousText.hasSuffix("\n") ? "" : " "
            text = previousText + separator + newValue
        }
        .onChange(of: speech.permissionDenied) { denied in
            if denied { showPermissionAlert = true }
        }
        .alert(isPresented: $showPermissionAlert) {
            Alert(
                title: Text("Microphone & Speech Access Required"),
                message: Text("Enable Microphone and Speech Recognition in Settings to use voice dictation."),
                primaryButton: .default(Text("Open Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func toggle() {
        if speech.isRecording {
            speech.stopRecording()
        } else {
            previousText = text
            Task { await speech.startRecording() }
        }
    }
}
