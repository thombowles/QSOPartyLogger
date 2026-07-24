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
    let esmEnabled: Bool

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: $operatingMode) {
                ForEach(OperatingMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 110)
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

            if esmEnabled {
                Text("ESM")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.purple.opacity(0.2), in: Capsule())
                    .help("Enter sends the next message (toggle in CW Messages)")
            }

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
