import SwiftUI

struct OutcomeEntryView: View {
    let outcome: Outcome
    @Binding var entry: OutcomeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(outcome.title)
                        .font(.subheadline.weight(.bold))
                    Text(outcome.goal)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: entry.isComplete ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundColor(entry.isComplete ? Theme.success : .secondary)
                    .font(.title3)
            }

            // Prompt level — 5 big buttons (data point, required)
            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt Level *")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                ForEach(PromptLevel.allCases) { level in
                    Button(action: { entry.promptLevel = level }) {
                        HStack {
                            Text(level.rawValue)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            if entry.promptLevel == level {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                        .background(entry.promptLevel == level ? Theme.primary : Theme.screenBackground)
                        .foregroundColor(entry.promptLevel == level ? .white : .primary)
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
                Button(action: { if entry.frequency > 0 { entry.frequency -= 1 } }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundColor(entry.frequency > 0 ? Theme.primary : .secondary.opacity(0.4))
                }
                Text("\(entry.frequency)")
                    .font(.title3.bold())
                    .frame(minWidth: 44)
                Button(action: { entry.frequency += 1 }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(Theme.primary)
                }
            }

            // Yes/No toggles
            Toggle("Goal opportunity provided", isOn: $entry.goalOpportunity)
                .font(.subheadline)
            Toggle("Target behavior observed", isOn: $entry.behaviorObserved)
                .font(.subheadline)

            // Per-goal narrative (required)
            VStack(alignment: .leading, spacing: 6) {
                Text("Narrative *")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                DocTextEditor(text: $entry.narrative,
                              placeholder: "Describe how \(outcome.title.lowercased()) went during this visit…",
                              minHeight: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
        }
        .padding(12)
        .background(Theme.screenBackground)
        .cornerRadius(12)
    }
}
