import SwiftUI

/// Editor for the document's F-key messages — separate Run and S&P sets, on
/// both CW (text the app keys) and phone (eight voice memories: recordings
/// made here on the Mac, or the radio's own) — stored in the log file so
/// every contest keeps its own macros. The recordings themselves live per
/// party on disk (`VoiceStore`), and save as they are made.
struct MessagesEditor: View {
    let document: LogDocument
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    @State private var editMode: OperatingMode = .run
    @State private var editClass: ModeClass
    /// The connected radio's voice-memory situation, for the status line and
    /// for greying memories this radio cannot play.
    let voiceStatus: VoiceKeyerStatus
    /// Which message bank the radio is currently in, or nil on a radio with no
    /// banks. Reported rather than corrected — see `voiceStatusText`.
    let voiceBank: Int?
    /// The active party's recordings and the recorder.
    let voiceStore: VoiceStore
    /// The connection, for the phone tab's path status and play-to-radio.
    let radio: RadioController
    /// Play memory N to the radio, exactly as an F-key would.
    let onPlayToRadio: (Int) -> Void
    /// The edits so far. A value, so Restore Defaults and the warning banner
    /// are testable — see `MessagesDraftTests`.
    @State private var draft = MessagesDraft()
    /// Resolved once on appear — `document.party` re-reads the bundle and the
    /// user parties folder on every call, which a view body must not do.
    @State private var party: PartyDefinition?

    init(document: LogDocument, settings: AppSettings, voiceStatus: VoiceKeyerStatus, voiceBank: Int?,
         voiceStore: VoiceStore, radio: RadioController, onPlayToRadio: @escaping (Int) -> Void,
         initialClass: ModeClass = .cw) {
        self.document = document
        self.settings = settings
        self.voiceStatus = voiceStatus
        self.voiceBank = voiceBank
        self.voiceStore = voiceStore
        self.radio = radio
        self.onPlayToRadio = onPlayToRadio
        _editClass = State(initialValue: initialClass)
    }

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

    /// Radio-neutral, per Article 10 — no manufacturer, no model.
    ///
    /// A `static func` rather than a literal in the view body so the wording is
    /// reachable from `VoiceStatusTextTests`, which asserts that no string an
    /// operator can see names a manufacturer. `nonisolated` because it touches
    /// no view state — without it, the `View` conformance infers `@MainActor`
    /// and every synchronous test call warns under Swift 6 strict concurrency,
    /// the same reason `LogDocument`'s pure static helpers are `nonisolated`.
    nonisolated static func voiceStatusText(_ status: VoiceKeyerStatus, bank: Int?) -> String {
        switch status {
        case .unsupported:
            return "This radio reports no voice memories of its own."
        case .notInstalled:
            return "This radio's voice recorder option isn't installed, so it has no "
                + "memories to play."
        case .available(let count):
            var text = "The radio has \(count) voice \(count == 1 ? "memory" : "memories") of its own. "
                + "Record those from its front panel; the app plays them when the source is set "
                + "to the radio's memories."
            if let bank {
                // The app leaves the bank where the last play put it, so the
                // radio's own M-buttons may not address what their labels say.
                //
                // Which memories that bank holds is the radio's business, not
                // ours: naming them here would hard-code one model's layout in
                // the app layer (Article 10).
                text += " The radio is currently in bank \(bank); its front-panel "
                    + "message buttons play that bank."
            }
            return text
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Messages — \(party?.name ?? document.log.partyID)")
                .font(.title3.weight(.semibold))
            if editClass == .cw {
                Text(Self.macroHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("", selection: $editClass) {
                Text("CW").tag(ModeClass.cw)
                Text("Phone").tag(ModeClass.phone)
            }
            .pickerStyle(.segmented)
            .help("CW messages are text the app keys. Phone messages are recordings made here, "
                  + "or the radio's own voice memories.")

            Picker("", selection: $editMode) {
                ForEach(OperatingMode.allCases, id: \.self) { mode in
                    Text(mode == .run ? "Run (CQ)" : "Search & Pounce").tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if editClass == .cw {
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
            } else {
                // The recorder rows, the source and device controls, and the
                // F-key mapping — one place for everything about phone keys.
                // `voiceMemoryPickerCaption`, not `draft.edited.…`: the latter
                // rebuilds the whole MessageSets once per row per memory, 64
                // times a render.
                VoiceMessagesPane(
                    store: voiceStore, settings: settings, radio: radio,
                    voiceStatus: voiceStatus, editMode: editMode,
                    name: nameBinding, mapping: memoryBinding,
                    pickerCaption: voiceMemoryPickerCaption, onPlayToRadio: onPlayToRadio
                )

                if voiceStatus != .unsupported {
                    Text(Self.voiceStatusText(voiceStatus, bank: voiceBank))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if editClass == .cw, let party, let mismatch = draft.mismatch(with: party) {
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

            if editClass == .cw {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Send cut numbers (599 → 5NN, 40 → 4T)", isOn: $settings.cwCutNumbers)
                        .help(Self.cutNumbersHelp)
                    Toggle("Also cut 1 → A (199 → ANN)", isOn: $settings.cwCutNumberOne)
                        .help("Less universal than 0→T and 9→N — leave off if stations ask for repeats.")
                        .disabled(!settings.cwCutNumbers)
                        .padding(.leading, 20)
                }
            }

            HStack {
                Button("Restore Defaults", action: applyPartyDefaults)
                    // ⇧⌘R, not ⇧⌘D: the Contest Dashboard window claims ⇧⌘D
                    // as a `Window` scene shortcut, which lives in the Window
                    // menu and stays active whichever window is key — it would
                    // shadow this button entirely.
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .help("Replace all messages with \(party?.name ?? "this party")'s defaults (⇧⌘R)")
                    .shortcutHint("⇧⌘R")
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .shortcutHint("Esc")
                Button("Save") {
                    document.updateMessages(draft.edited, undoManager: undoManager)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .shortcutHint("⏎")
            }
        }
        .padding(20)
        // Floored so the warning banner appears and disappears inside space the
        // sheet already occupies, instead of resizing the modal mid-keystroke.
        // `.topLeading` is load-bearing: the default `.center` would split the
        // banner's height evenly above and below, moving the eight F-key fields
        // 21.5 pt each time the verdict flips — under the operator's own caret.
        .frame(minWidth: 900, minHeight: 560, alignment: .topLeading)
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

    private func nameBinding(_ memoryIndex: Int) -> Binding<String> {
        Binding(
            get: { draft.voiceMemoryNames[memoryIndex] },
            set: { draft.setVoiceMemoryName($0, at: memoryIndex) }
        )
    }

    private func memoryBinding(_ index: Int) -> Binding<Int?> {
        Binding(
            get: { draft[voice: editMode, index] },
            set: { draft[voice: editMode, index] = $0 }
        )
    }

    /// The F-key picker's label for one memory option — the recorded name,
    /// marked when this radio does not go that high. Never hides the option:
    /// a mapping built for an 8-memory radio must stay visible and intact
    /// while a smaller one (or none) is plugged in, matching the memory-name
    /// fields above, which stay editable rather than disappearing. With no
    /// radio connected (`memoryCount == 0`) every option is offered unmarked,
    /// since there is nothing yet to say it doesn't fit.
    private func voiceMemoryPickerCaption(_ memory: Int) -> String {
        let caption = draft.voiceMemoryCaption(memory)
        guard voiceStatus.memoryCount > 0, memory > voiceStatus.memoryCount else { return caption }
        return "\(caption) — not on this radio"
    }
}
