import SwiftUI

/// F1–F8 CW message buttons for the active operating mode, plus the
/// Run/S&P toggle and repeat-CQ controls.
struct MessagesRow: View {
    @Binding var operatingMode: OperatingMode
    let messages: [String]
    let expand: (String) -> String
    let onSend: (String) -> Void
    let enabled: Bool

    @Binding var repeatEnabled: Bool
    @Binding var repeatInterval: Double
    @Binding var esmEnabled: Bool

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
                    onSend(template)
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
                .help(expand(template))
            }

            Spacer()

            Toggle(isOn: $esmEnabled) {
                Label("ESM", systemImage: "return")
                    .font(.caption)
            }
            .toggleStyle(.button)
            .tint(.purple)
            .help("Enter Sends Message: Return sends CQ / exchange / TU based on the entry fields, and logs automatically after the exchange.")

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
