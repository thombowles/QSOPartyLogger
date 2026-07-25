import SwiftUI

/// Editor for the document's CW messages — separate Run and S&P sets, stored
/// in the log file so every contest keeps its own macros.
struct MessagesEditor: View {
    let document: LogDocument
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    @State private var editMode: OperatingMode = .run
    @State private var run: [String] = []
    @State private var searchPounce: [String] = []
    /// Resolved once on appear — `document.party` re-reads the bundle and the
    /// user parties folder on every call, which a view body must not do.
    @State private var party: PartyDefinition?

    /// The caption under the title — the one place an operator can discover
    /// what they may type into an F-key. A named constant, and derived from
    /// `MacroToken.allCases` rather than written out, because the hand-written
    /// version omitted `{SERIAL}` for as long as that macro existed and
    /// nothing could see it: a `Text` literal inside a view body is not
    /// reachable from a test.
    static let macroHelp =
        "Stored in this log file, so each contest keeps its own macros. "
        + "Macros: \(MacroToken.helpList) — prosigns: ( KN + AR = BT * SK"

    /// The cut-number toggle's tooltip. A `String` constant rather than an
    /// interpolated literal at the call site so it resolves to `help`'s
    /// `StringProtocol` overload: interpolating a `MacroToken` straight into a
    /// `LocalizedStringKey` compiles, renders the same, and is deprecated.
    static let cutNumbersHelp =
        "Replaces 0→T and 9→N in the \(MacroToken.rst) and \(MacroToken.serial) "
        + "macros when keying CW. Callsigns and county codes are never altered."

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CW Messages — \(party?.name ?? document.log.partyID)")
                .font(.title3.weight(.semibold))
            Text(Self.macroHelp)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: $editMode) {
                ForEach(OperatingMode.allCases, id: \.self) { mode in
                    Text(mode == .run ? "Run (CQ)" : "Search & Pounce").tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                ForEach(0..<8, id: \.self) { index in
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

            if let party, let mismatch = edited.exchangeMismatch(with: party) {
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
                    .help(Self.cutNumbersHelp)
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
                    document.updateMessages(edited, undoManager: undoManager)
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
            run = pad(document.log.messages.run)
            searchPounce = pad(document.log.messages.searchPounce)
        }
    }

    /// What this party's macros should be — for Restore Defaults and the fix
    /// button.
    private var partyDefaults: MessageSets {
        MessageSets.defaults(for: party)
    }

    /// What is currently in the fields, not what is saved, so the warning
    /// clears the moment the operator types a fix.
    private var edited: MessageSets {
        MessageSets(run: normalized(run), searchPounce: normalized(searchPounce))
    }

    private func applyPartyDefaults() {
        run = pad(partyDefaults.run)
        searchPounce = pad(partyDefaults.searchPounce)
    }

    private func binding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                let set = editMode == .run ? run : searchPounce
                return set.indices.contains(index) ? set[index] : ""
            },
            set: { newValue in
                if editMode == .run {
                    run = pad(run)
                    run[index] = newValue
                } else {
                    searchPounce = pad(searchPounce)
                    searchPounce[index] = newValue
                }
            }
        )
    }

    private func pad(_ set: [String]) -> [String] {
        var out = set
        while out.count < 8 { out.append("") }
        return out
    }

    private func normalized(_ set: [String]) -> [String] {
        pad(set).map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
