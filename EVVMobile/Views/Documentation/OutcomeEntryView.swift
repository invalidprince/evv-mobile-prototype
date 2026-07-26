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

            // Data point — 4 big buttons (required)
            VStack(alignment: .leading, spacing: 8) {
                Text("Data Point *")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                ForEach(DataPoint.allCases) { dp in
                    Button(action: {
                        entry.dataPoint = dp
                        // When N/A is selected, auto-fill narrative if empty
                        if dp == .notApplicable && entry.narrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            entry.narrative = "We did not work on this outcome today."
                        }
                    }) {
                        HStack {
                            Text(dp.rawValue)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            if entry.dataPoint == dp {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                        .background(entry.dataPoint == dp ? (dp == .notApplicable ? Color.secondary : Theme.primary) : Theme.screenBackground)
                        .foregroundColor(entry.dataPoint == dp ? .white : .primary)
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

            // Per-goal narrative (required unless N/A)
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.dataPoint == .notApplicable ? "Narrative" : "Narrative *")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                DocTextEditor(text: $entry.narrative,
                              placeholder: entry.dataPoint == .notApplicable
                                  ? "Optional — add details if needed"
                                  : "Describe how \(outcome.title.lowercased()) went during this visit…",
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
