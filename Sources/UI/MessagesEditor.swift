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
                    Text("\(mismatch.warning(partyName: party.name)) Restore Defaults (⇧⌘D) fixes it.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }

            Toggle("Send cut numbers for RST (599 → 5NN)", isOn: $settings.cwCutNumbers)
                .help("Replaces 9→N and 0→T in the {RST} macro when keying CW. Callsigns and county codes are never altered.")

            HStack {
                Button("Restore Defaults", action: applyPartyDefaults)
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                    .help("Replace all 16 messages with \(party?.name ?? "this party")'s defaults (⇧⌘D)")
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
