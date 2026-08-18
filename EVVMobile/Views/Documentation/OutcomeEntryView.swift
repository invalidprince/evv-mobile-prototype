import SwiftUI

/// One compact counter row: label · − · value · +.
/// The value itself is tappable for keyboard entry — steppers stay because
/// they're field-friendly (gloves / cold hands), but typing 12 shouldn't take
/// 12 taps.
private struct CountRow: View {
    let label: String
    @Binding var value: Int?
    var disabled: Bool

    @State private var editing = false
    @State private var typed = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Spacer()
            Button(action: {
                let v = value ?? 0
                if v > 0 { value = v - 1 }
            }) {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
                    .foregroundColor((value ?? 0) > 0 && !disabled ? Theme.primary : .secondary.opacity(0.4))
            }
            .disabled(disabled)
            .buttonStyle(.plain)

            if editing {
                TextField("", text: $typed)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title3.bold())
                    .frame(minWidth: 56)
                    .focused($focused)
                    .onSubmit { commit() }
                    // Single-argument onChange — the iOS 17 two-argument form
                    // does not compile against this target (deployment 15.0).
                    .onChange(of: focused) { isFocused in
                        if !isFocused { commit() }
                    }
            } else {
                // "—" means not measured; 0 is a real measurement.
                Text(value.map(String.init) ?? "—")
                    .font(.title3.bold())
                    .foregroundColor(disabled ? .secondary.opacity(0.5) : .primary)
                    .frame(minWidth: 56, minHeight: 44)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !disabled else { return }
                        typed = value.map(String.init) ?? ""
                        editing = true
                        focused = true
                    }
            }

            Button(action: { value = (value ?? 0) + 1 }) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(disabled ? .secondary.opacity(0.4) : Theme.primary)
            }
            .disabled(disabled)
            .buttonStyle(.plain)
        }
        .opacity(disabled ? 0.5 : 1)
    }

    private func commit() {
        let trimmed = typed.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            value = nil
        } else if let n = Int(trimmed) {
            value = max(0, n)
        }
        editing = false
    }
}

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

            // Data points — three counts + N/A (v0.4.152).
            VStack(alignment: .leading, spacing: 10) {
                Text("Data Points")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                CountRow(label: "Prompts", value: $entry.prompts, disabled: entry.na)
                CountRow(label: "Successes", value: $entry.successes, disabled: entry.na)
                CountRow(label: "Opportunities", value: $entry.opportunities, disabled: entry.na)

                Toggle("N/A", isOn: Binding(
                    get: { entry.na },
                    set: { on in
                        entry.na = on
                        if on {
                            // N/A wins — never leave numbers behind it.
                            entry.prompts = nil
                            entry.successes = nil
                            entry.opportunities = nil
                            if entry.narrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                entry.narrative = "We did not work on this outcome today."
                            }
                        }
                    }
                ))
                .font(.subheadline.weight(.semibold))
            }

            // Per-goal narrative (required unless N/A)
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.na ? "Narrative" : "Narrative *")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                DocTextEditor(text: $entry.narrative,
                              placeholder: entry.na
                                  ? "Optional — add details if needed"
                                  : "Describe how \(outcome.title.lowercased()) went during this visit…",
                              minHeight: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }

            // Per Nick 2026-08-17: a non-N/A outcome needs a data point AND a
            // narrative. Say WHICH half is still missing rather than leaving the
            // grey dashed circle as the only signal.
            if let missing = entry.missingPart {
                Label("Needs \(missing.label) — or check N/A if this wasn’t worked on.",
                      systemImage: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Theme.screenBackground)
        .cornerRadius(12)
    }
}
