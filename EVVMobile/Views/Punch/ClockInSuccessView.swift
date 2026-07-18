import SwiftUI

struct ClockInSuccessView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 0.4

    private var timeText: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: Date())
    }

    var body: some View {
        ZStack {
            Theme.success.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 110))
                    .foregroundColor(.white)
                    .scaleEffect(scale)
                Text("Clocked in \(timeText)")
                    .font(.title.bold())
                    .foregroundColor(.white)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                scale = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                dismiss()
            }
        }
        .onTapGesture { dismiss() }
    }
}
