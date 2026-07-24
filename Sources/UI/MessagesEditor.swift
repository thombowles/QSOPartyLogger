import SwiftUI

/// Editor for the document's CW messages — separate Run and S&P sets, stored
/// in the log file so every contest keeps its own macros.
struct MessagesEditor: View {
    let document: LogDocument
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    @State private var editMode: OperatingMode = .run
    @State private var run: [String] = MessageSets.defaultRun
    @State private var searchPounce: [String] = MessageSets.defaultSearchPounce

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CW Messages — \(document.party?.name ?? document.log.partyID)")
                .font(.title3.weight(.semibold))
            Text("Stored in this log file, so each contest keeps its own macros. Macros: {MYCALL} {CALL} {RST} {EXCH} — prosigns: ( KN + AR = BT * SK")
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

            Toggle("Send cut numbers for RST (599 → 5NN)", isOn: $settings.cwCutNumbers)
                .help("Replaces 9→N and 0→T in the {RST} macro when keying CW. Callsigns and county codes are never altered.")

            HStack {
                Button("Restore Defaults") {
                    run = MessageSets.defaultRun
                    searchPounce = MessageSets.defaultSearchPounce
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    document.updateMessages(
                        MessageSets(run: normalized(run), searchPounce: normalized(searchPounce)),
                        undoManager: undoManager
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .onAppear {
            run = pad(document.log.messages.run)
            searchPounce = pad(document.log.messages.searchPounce)
        }
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
