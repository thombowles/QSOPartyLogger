import SwiftUI

/// Editor for the document's CW messages — separate Run and S&P sets, stored
/// in the log file so every contest keeps its own macros.
struct MessagesEditor: View {
    let document: LogDocument
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    @State private var editMode: OperatingMode = .run
    /// The edits so far. A value, so Restore Defaults and the warning banner
    /// are testable — see `MessagesDraftTests`.
    @State private var draft = MessagesDraft()
    /// Resolved once on appear — `document.party` re-reads the bundle and the
    /// user parties folder on every call, which a view body must not do.
    @State private var party: PartyDefinition?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CW Messages — \(party?.name ?? document.log.partyID)")
                .font(.title3.weight(.semibold))
            Text("Stored in this log file, so each contest keeps its own macros. Macros: {MYCALL} {CALL} {RST} {SERIAL} {EXCH} — prosigns: ( KN + AR = BT * SK")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: $editMode) {
                ForEach(OperatingMode.allCases, id: \.self) { mode in
                    Text(mode == .run ? "Run (CQ)" : "Search & Pounce").tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                ForEach(0..<MessagesDraft.slotCount, id: \.self) { index in
                    GridRow {
                        Text("F\(index + 1)")
                            .font(.callout.weight(.bold))
                            .frame(width: 30, alignment: .trailing)
                        TextField("", text: binding(index))
                            .font(.body.monospaced())
                            .frame(width: 360)
                    }
                }
            }

            if let party, let mismatch = draft.mismatch(with: party) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("\(mismatch.warning(partyName: party.name)) Restore Defaults (⇧⌘R) fixes it.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Send cut numbers (599 → 5NN, 40 → 4T)", isOn: $settings.cwCutNumbers)
                    .help("Replaces 0→T and 9→N in the {RST} and {SERIAL} macros when keying CW. Callsigns and county codes are never altered.")
                Toggle("Also cut 1 → A (199 → ANN)", isOn: $settings.cwCutNumberOne)
                    .help("Less universal than 0→T and 9→N — leave off if stations ask for repeats.")
                    .disabled(!settings.cwCutNumbers)
                    .padding(.leading, 20)
            }

            HStack {
                Button("Restore Defaults", action: applyPartyDefaults)
                    // ⇧⌘R, not ⇧⌘D: the Contest Dashboard window claims ⇧⌘D
                    // as a `Window` scene shortcut, which lives in the Window
                    // menu and stays active whichever window is key — it would
                    // shadow this button entirely.
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .help("Replace all 16 messages with \(party?.name ?? "this party")'s defaults (⇧⌘R)")
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    document.updateMessages(draft.edited, undoManager: undoManager)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        // Floored so the warning banner appears and disappears inside space the
        // sheet already occupies, instead of resizing the modal mid-keystroke.
        // `.topLeading` is load-bearing: the default `.center` would split the
        // banner's height evenly above and below, moving the eight F-key fields
        // 21.5 pt each time the verdict flips — under the operator's own caret.
        .frame(minWidth: 740, minHeight: 500, alignment: .topLeading)
        .onAppear {
            party = document.party
            draft = MessagesDraft(document.log.messages)
        }
    }

    private func applyPartyDefaults() {
        draft.restoreDefaults(for: party)
    }

    private func binding(_ index: Int) -> Binding<String> {
        Binding(
            get: { draft[editMode, index] },
            set: { draft[editMode, index] = $0 }
        )
    }
}
