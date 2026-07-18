import SwiftUI

struct OutcomeEntryView: View {
    let outcome: Outcome

    @State private var promptLevel: PromptLevel?
    @State private var frequency = 0
    @State private var goalMet = false
    @State private var behaviorObserved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(outcome.title)
                    .font(.subheadline.weight(.bold))
                Text(outcome.goal)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Prompt level — 5 big buttons
            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt Level")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                ForEach(PromptLevel.allCases) { level in
                    Button(action: { promptLevel = level }) {
                        HStack {
                            Text(level.rawValue)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            if promptLevel == level {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                        .background(promptLevel == level ? Theme.primary : Theme.screenBackground)
                        .foregroundColor(promptLevel == level ? .white : .primary)
                        .cornerRadius(10)
                    }
                }
            }

            // Frequency counter
            HStack {
                Text("Frequency")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { if frequency > 0 { frequency -= 1 } }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundColor(frequency > 0 ? Theme.primary : .secondary.opacity(0.4))
                }
                Text("\(frequency)")
                    .font(.title3.bold())
                    .frame(minWidth: 44)
                Button(action: { frequency += 1 }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(Theme.primary)
                }
            }

            // Yes/No toggles
            Toggle("Goal opportunity provided", isOn: $goalMet)
                .font(.subheadline)
            Toggle("Target behavior observed", isOn: $behaviorObserved)
                .font(.subheadline)
        }
        .padding(12)
        .background(Theme.screenBackground)
        .cornerRadius(12)
    }
}
