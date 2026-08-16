import SwiftUI

/// F1–F8 message buttons for the active operating mode — CW text, or the
/// radio's voice memories on phone — plus the Run/S&P toggle, ESM, repeat-CQ,
/// and the CQ-frequency jump chip.
struct MessagesRow: View {
    /// One F-key as the row draws it. Built by the caller so the row never has
    /// to know whether it is showing expanded CW text or a voice memory.
    struct MessageKey: Equatable {
        /// The full caption — "CQ TEST KE5CW", or "M4 AGN?". Truncated here for
        /// the button and shown whole in the tooltip.
        var caption: String
        /// Whether this key does anything: a non-empty CW slot, or a memory
        /// mapping this radio can actually play.
        var isActive: Bool
    }

    @Binding var operatingMode: OperatingMode
    let keys: [MessageKey]
    /// Send the message in F-key slot `index` (0-based).
    let onSend: (Int) -> Void
    let enabled: Bool
    /// The slot Return will send next under ESM, outlined so the sequence the
    /// program is stepping through is visible rather than guessed at.
    let pendingIndex: Int?

    @Binding var repeatEnabled: Bool
    /// Armed but not running: a keystroke paused the loop, and F1 or the CQ
    /// button starts it again. Drawn in orange so the state is visible.
    var repeatPaused: Bool = false
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
            .help("Run = calling CQ; S&P = search and pounce. Each has its own F1–F8 set. "
                  + "Toggle Run / Search & Pounce (⌘R). Tuning off your CQ frequency switches to "
                  + "S&P and tuning back onto it switches to Run — the band map's Tuning options.")
            // Article 7 — keyboard-first. An out-of-state log opens in S&P, and
            // ⌘J only reaches Run once a CQ frequency has been captured, which
            // needs Run already. A picker carries no shortcut of its own, so an
            // invisible button behind it carries one. It toggles rather than
            // jumping to Run so the single key serves both directions.
            .background {
                Button("Toggle Run / Search & Pounce") {
                    operatingMode = operatingMode == .run ? .searchPounce : .run
                }
                .keyboardShortcut("r", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
            }
            .shortcutHint("⌘R")

            ForEach(Array(keys.prefix(8).enumerated()), id: \.offset) { index, key in
                Button {
                    onSend(index)
                } label: {
                    VStack(spacing: 1) {
                        Text("F\(index + 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(shortLabel(key.caption))
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 62)
                }
                .disabled(!enabled || !key.isActive)
                .overlay {
                    if index == pendingIndex {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(.purple, lineWidth: 2)
                    }
                }
                .help(index == pendingIndex ? "Return sends this: \(key.caption)" : key.caption)
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
                .shortcutHint("⌘J")
            }

            Toggle(isOn: $esmEnabled) {
                Label("ESM", systemImage: "return")
                    .font(.caption)
            }
            .toggleStyle(.button)
            .tint(.purple)
            .help("Enter Sends Message: with the cursor in the call field Return only calls — it never logs. Move to the exchange and Return logs and sends your report. An exchange that matches nothing sends AGN?. The outlined key is what Return sends next.")

            Toggle(isOn: $repeatEnabled) {
                Label(repeatPaused ? "Repeat CQ ⏸" : "Repeat CQ", systemImage: "repeat")
                    .font(.caption)
            }
            .toggleStyle(.button)
            .tint(repeatPaused ? .orange : .accentColor)
            .disabled(!enabled || operatingMode != .run)
            .help("Re-send F1 after each interval. Typing or Esc pauses the loop and leaves the mode on "
                  + "— F1, the CQ button or ESM's Return start it again from the top. "
                  + "Click to turn the mode off.")

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

    private func shortLabel(_ caption: String) -> String {
        caption.count > 13 ? String(caption.prefix(12)) + "…" : caption
    }
}
