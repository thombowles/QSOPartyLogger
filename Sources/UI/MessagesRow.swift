import SwiftUI

/// F1–F8 CW message buttons for the active operating mode, plus the
/// Run/S&P toggle, ESM, repeat-CQ, and the CQ-frequency jump chip.
struct MessagesRow: View {
    @Binding var operatingMode: OperatingMode
    let messages: [String]
    let expand: (String) -> String
    /// Send the message in F-key slot `index` (0-based).
    let onSend: (Int) -> Void
    let enabled: Bool
    /// The slot Return will send next under ESM, outlined so the sequence the
    /// program is stepping through is visible rather than guessed at.
    let pendingIndex: Int?

    @Binding var repeatEnabled: Bool
    @Binding var repeatInterval: Double
    @Binding var esmEnabled: Bool

    /// "14025.4" when a CQ frequency is remembered; nil hides the chip.
    let cqFrequencyLabel: String?
    let onJumpToCQ: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: $operatingMode) {
                ForEach(OperatingMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("Run = calling CQ; S&P = search and pounce. Each has its own F1–F8 set.")

            ForEach(Array(messages.prefix(8).enumerated()), id: \.offset) { index, template in
                Button {
                    onSend(index)
                } label: {
                    VStack(spacing: 1) {
                        Text("F\(index + 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(shortLabel(template))
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 62)
                }
                .disabled(!enabled || template.isEmpty)
                .overlay {
                    if index == pendingIndex {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(.purple, lineWidth: 2)
                    }
                }
                .help(index == pendingIndex ? "Return sends this: \(expand(template))" : expand(template))
            }

            Spacer()

            if let cqFrequencyLabel {
                Button {
                    onJumpToCQ()
                } label: {
                    Label(cqFrequencyLabel, systemImage: "arrow.uturn.backward")
                        .font(.caption.monospacedDigit())
                }
                .help("Jump back to your CQ run frequency and Run mode (⌘J)")
            }

            Toggle(isOn: $esmEnabled) {
                Label("ESM", systemImage: "return")
                    .font(.caption)
            }
            .toggleStyle(.button)
            .tint(.purple)
            .help("Enter Sends Message: Return steps through the contact — CQ, his report, log and TU when running; your call, then your report and the log when pouncing. The outlined key is what Return sends next.")

            Toggle(isOn: $repeatEnabled) {
                Label("Repeat CQ", systemImage: "repeat")
                    .font(.caption)
            }
            .toggleStyle(.button)
            .disabled(!enabled || operatingMode != .run)
            .help("Re-send F1 after each interval. Any keystroke cancels.")

            Stepper(value: $repeatInterval, in: 0.5...15, step: 0.5) {
                Text(String(format: "%.1fs", repeatInterval))
                    .font(.caption.monospacedDigit())
            }
            .disabled(!repeatEnabled)
            .help("Silence between repeats")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func shortLabel(_ template: String) -> String {
        let expanded = expand(template)
        return expanded.count > 13 ? String(expanded.prefix(12)) + "…" : expanded
    }
}
