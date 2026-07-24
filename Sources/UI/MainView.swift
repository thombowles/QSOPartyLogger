import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @Bindable var document: LogDocument
    @Environment(\.undoManager) private var undoManager

    @State private var settings = AppSettings.shared
    @State private var radio = RadioController()
    @State private var entry = EntryState()
    @FocusState private var focusedField: EntryBar.Field?

    @State private var manualBand: Band = .m20
    @State private var manualRawMode = "CW"

    @State private var showSetup = false
    @State private var showMessagesEditor = false
    @State private var editingQSO: QSO?
    @State private var exportDoc: TextExportDocument?
    @State private var exportType: UTType = .plainText
    @State private var exportName = ""
    @State private var isExporting = false
    @State private var keyMonitor: Any?

    @State private var operatingMode: OperatingMode = .run
    @State private var repeatCQ = false
    @State private var repeatTask: Task<Void, Never>?
    @State private var hostWindow: NSWindow?

    private var party: PartyDefinition? {
        document.party
    }

    private var score: ScoreEngine.ScoreBreakdown {
        guard let party else { return .init() }
        return ScoreEngine.score(log: document.log, party: party)
    }

    private var currentBand: Band {
        radio.radioState?.band ?? manualBand
    }

    private var currentRawMode: String {
        radio.radioState?.mode.rawMode ?? manualRawMode
    }

    private var currentModeClass: ModeClass {
        ModeClass.classify(rawMode: currentRawMode)
    }

    var body: some View {
        splitContent
            .frame(minWidth: 1040, minHeight: 640)
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
            .sheet(isPresented: $showSetup) {
                SetupSheet(document: document)
            }
            .sheet(isPresented: $showMessagesEditor) {
                MessagesEditor(document: document, settings: settings)
            }
            .sheet(item: $editingQSO) { qso in
                EditQSOSheet(original: qso, party: party) { updated in
                    document.update(qso: updated, undoManager: undoManager)
                }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDoc,
                contentType: exportType,
                defaultFilename: exportName
            ) { _ in }
            .toolbar { toolbarContent }
            .alert("Radio error", isPresented: radioErrorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(radio.lastError ?? "")
            }
    }

    private var radioErrorPresented: Binding<Bool> {
        Binding(
            get: { radio.lastError != nil },
            set: { presented in
                if !presented { radio.clearError() }
            }
        )
    }

    private var splitContent: some View {
        HSplitView {
            leftPane
            ScoreSidebar(log: document.log, party: party, score: score)
        }
    }

    private var leftPane: some View {
        VStack(spacing: 0) {
            RadioBar(
                settings: settings,
                radio: radio,
                party: party,
                manualBand: $manualBand,
                manualRawMode: $manualRawMode
            )
            .onChange(of: radio.radioState?.band) { revalidate() }
            .onChange(of: radio.radioState?.mode) { revalidate() }
            .onChange(of: radio.radioReportedWPM) { syncSpeedFromRadio() }
            .onChange(of: repeatCQ) { repeatCQChanged() }
            .onChange(of: radio.isConnected) { if !radio.isConnected { stopRepeat() } }
            Divider()

            stationStrip
                .onChange(of: document.log.partyID) { applyDefaultDocumentName() }
                .onChange(of: document.log.station.callsign) { applyDefaultDocumentName() }
                .onChange(of: document.log.setupCompleted) { autoSaveNewDocumentIfNeeded() }
            Divider()

            EntryBar(entry: entry, party: party, onLog: returnPressed, focus: $focusedField)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .onChange(of: entry.exchange) { revalidate() }
                .onChange(of: entry.call) { revalidate() }

            MessagesRow(
                operatingMode: $operatingMode,
                messages: activeMessages,
                expand: expandMacros,
                onSend: sendMessage,
                enabled: radio.isConnected && currentModeClass == .cw,
                repeatEnabled: $repeatCQ,
                repeatInterval: $settings.repeatIntervalSeconds,
                esmEnabled: settings.esmEnabled
            )
            Divider()

            logTable
        }
        .frame(minWidth: 760)
        .background(WindowAccessor { window in
            hostWindow = window
            applyDefaultDocumentName()
        })
        .onChange(of: manualBand) { revalidate() }
        .onChange(of: manualRawMode) { revalidate() }
    }

    private var logTable: some View {
        LogTable(
            qsos: document.log.qsos,
            score: score,
            party: party,
            onDeleteRow: { document.remove(ids: [$0.id], undoManager: undoManager) },
            onDeleteGroup: { document.removeGroup(groupID: $0.groupID, undoManager: undoManager) },
            onEdit: { editingQSO = $0 }
        )
        .frame(minHeight: 240)
    }

    private func onDisappear() {
        stopRepeat()
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        radio.disconnect()
    }

    // MARK: Station strip

    private var stationStrip: some View {
        HStack(spacing: 10) {
            Label(
                document.log.station.callsign.isEmpty ? "No callsign — set up" : document.log.station.callsign,
                systemImage: "person.crop.square"
            )
            .font(.callout.weight(.semibold))

            if let party {
                Text(party.name)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Label("Party '\(document.log.partyID)' not found", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Text("From: \(document.log.myLocation.displayText.isEmpty ? "—" : document.log.myLocation.displayText)")
                .font(.callout.monospaced())
                .foregroundStyle(document.log.myLocation.sentExchanges.count > 1 ? .blue : .secondary)

            if document.log.myLocation.sentExchanges.count > 1 {
                Text("COUNTY LINE — logs ×\(document.log.myLocation.sentExchanges.count)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.2), in: Capsule())
            }

            Spacer()

            Text("\(currentBand.rawValue) \(currentRawMode)")
                .font(.callout.monospaced().weight(.semibold))

            Button("Setup…") { showSetup = true }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                exportADIF()
            } label: {
                Label("Export ADIF", systemImage: "square.and.arrow.up")
            }
            .keyboardShortcut("e", modifiers: .command)
            .help("Export ADIF (⌘E)")

            Button {
                exportCabrillo()
            } label: {
                Label("Export Cabrillo", systemImage: "doc.plaintext")
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .help("Export Cabrillo (⇧⌘E)")

            Button {
                showMessagesEditor = true
            } label: {
                Label("CW Messages", systemImage: "keyboard")
            }

            Menu {
                if let path = CloudMirror.folderDisplayPath {
                    Text(path)
                }
                Button(CloudMirror.isConfigured ? "Change iCloud Folder…" : "Choose iCloud Folder…") {
                    _ = CloudMirror.chooseFolder()
                }
                if CloudMirror.isConfigured {
                    Toggle("Auto-Save Copies to iCloud", isOn: Binding(
                        get: { CloudMirror.isEnabled },
                        set: { CloudMirror.isEnabled = $0 }
                    ))
                    Button("Open iCloud Folder") {
                        CloudMirror.openFolderInFinder()
                    }
                }
            } label: {
                Label(
                    "iCloud",
                    systemImage: CloudMirror.isEnabled ? "icloud.fill" : "icloud"
                )
            }
            .help("Mirror every save into an iCloud Drive folder so contests sync to your other Macs")
        }
    }

    // MARK: Actions

    private var activeMessages: [String] {
        document.log.messages.messages(for: operatingMode)
    }

    private func onAppear() {
        // New (or never-configured) contests go straight to Contest Setup.
        if !document.log.setupCompleted {
            showSetup = true
        }
        focusedField = .call
        installKeyMonitor()
    }

    /// Return key: plain logging, or the ESM state machine when enabled.
    private func returnPressed() {
        entry.applyDefaults(modeClass: currentModeClass)
        revalidate()
        let exchangeValid: Bool = {
            if case .valid = entry.exchangeStatus { return true }
            return false
        }()

        guard settings.esmEnabled, radio.isConnected, currentModeClass == .cw else {
            logContact()
            return
        }

        switch ESM.nextAction(
            mode: operatingMode,
            callEmpty: entry.callNormalized.isEmpty,
            exchangeValid: exchangeValid
        ) {
        case .sendMessage(let index):
            sendMessageAt(index)
        case .logAndSend(let index):
            logContact()
            sendMessageAt(index)
        case .none:
            logContact()
        }
    }

    private func sendMessageAt(_ index: Int) {
        let set = activeMessages
        guard set.indices.contains(index), !set[index].isEmpty else { return }
        sendMessage(set[index])
    }

    // MARK: CW speed

    private func syncSpeedFromRadio() {
        guard let wpm = radio.radioReportedWPM, wpm != settings.wpm else { return }
        settings.wpm = wpm
    }

    private func adjustWPM(by delta: Int) {
        settings.wpm = min(50, max(8, settings.wpm + delta))
        radio.syncWPM(settings.wpm, settings: settings)
    }

    // MARK: Repeat CQ

    private func repeatCQChanged() {
        repeatCQ ? startRepeat() : stopRepeat()
    }

    private func startRepeat() {
        repeatTask?.cancel()
        guard radio.isConnected, currentModeClass == .cw else {
            repeatCQ = false
            return
        }
        let cq = document.log.messages.run.first ?? ""
        guard !cq.isEmpty else {
            repeatCQ = false
            return
        }
        repeatTask = Task {
            while !Task.isCancelled && repeatCQ {
                let text = expandMacros(cq)
                radio.sendCW(text, settings: settings)
                let onAir = radio.estimatedSendDuration(text, settings: settings)
                let wait = onAir + settings.repeatIntervalSeconds
                do {
                    try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                } catch {
                    break
                }
            }
        }
    }

    private func stopRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
        if repeatCQ { repeatCQ = false }
    }

    // MARK: Document naming + automatic first save

    /// Give unsaved logs a useful default name: "2026-07-25 ALQP KE5CW".
    private func applyDefaultDocumentName() {
        guard let window = hostWindow,
              let nsDocument = window.windowController?.document as? NSDocument else { return }
        document.knownFileURL = nsDocument.fileURL
        guard nsDocument.fileURL == nil else { return }
        let name = LogDocument.defaultDisplayName(
            partyID: document.log.partyID,
            callsign: document.log.station.callsign
        )
        nsDocument.displayName = name
        window.title = name
    }

    /// Once Contest Setup completes, write the log straight into the logs
    /// folder (no save panel) so it exists on disk — and in iCloud — from the
    /// first minute. Later edits ride normal autosave-in-place; relaunching
    /// restores the window, so the operator picks up where they left off.
    private func autoSaveNewDocumentIfNeeded() {
        guard document.log.setupCompleted,
              let window = hostWindow,
              let nsDocument = window.windowController?.document as? NSDocument,
              nsDocument.fileURL == nil else { return }

        // Need a logs folder first; offer the chooser once (recommends iCloud
        // Drive). Declining leaves the classic ⌘S flow.
        if !CloudMirror.isConfigured {
            guard CloudMirror.chooseFolder() else { return }
        }

        let baseName = LogDocument.defaultDisplayName(
            partyID: document.log.partyID,
            callsign: document.log.station.callsign
        )
        guard let url = CloudMirror.uniqueSaveURL(baseName: baseName) else { return }
        nsDocument.save(to: url, ofType: nsDocument.fileType ?? "QSO Party Log", for: .saveOperation) { error in
            if let error {
                NSLog("Auto-save failed: \(error)")
            } else {
                Task { @MainActor in
                    document.knownFileURL = url
                }
            }
        }
    }

    private func revalidate() {
        entry.revalidate(
            party: party,
            log: document.log,
            band: currentBand,
            modeClass: currentModeClass
        )
    }

    private func logContact() {
        guard let party else { return }
        entry.applyDefaults(modeClass: currentModeClass)
        revalidate()
        guard case .valid(let theirLocs) = entry.exchangeStatus,
              !entry.callNormalized.isEmpty else { return }

        let myLocs = document.log.myLocation.sentExchanges.filter { !$0.isEmpty }
        guard !myLocs.isEmpty else {
            showSetup = true
            return
        }

        let rows = CountyLineExpander.expand(
            entry: .init(
                call: entry.callNormalized,
                rstSent: entry.rstSent.isEmpty ? currentModeClass.defaultRST : entry.rstSent,
                rstRcvd: entry.rstRcvd.isEmpty ? currentModeClass.defaultRST : entry.rstRcvd,
                band: currentBand,
                modeClass: currentModeClass,
                rawMode: currentRawMode,
                freqKHz: radio.radioState?.frequencyKHz,
                timestampUTC: Date()
            ),
            myLocs: myLocs,
            theirLocs: theirLocs
        )
        document.append(qsos: rows, undoManager: undoManager)
        _ = party
        entry.clearForNextContact()
        focusedField = .call
    }

    private func expandMacros(_ template: String) -> String {
        AppSettings.expandMacros(
            template,
            myCall: document.log.station.callsign.uppercased(),
            call: entry.callNormalized,
            rst: entry.rstSent.isEmpty ? currentModeClass.defaultRST : entry.rstSent,
            exchange: document.log.myLocation.displayText
        )
    }

    private func sendMessage(_ template: String) {
        radio.sendCW(expandMacros(template), settings: settings)
    }

    // MARK: F-key handling (AppKit monitor — reliable across macOS versions)

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Any keystroke cancels a running repeat-CQ loop (per Tom's spec:
            // "typing anything cancels repeat").
            if repeatTask != nil {
                stopRepeat()
            }

            // ⌘= / ⌘+ and ⌘- (plus keypad variants): CW speed ±2 WPM.
            if event.modifierFlags.contains(.command) {
                switch event.keyCode {
                case 24, 69:  // '=' / keypad '+'
                    adjustWPM(by: 2)
                    return nil
                case 27, 78:  // '-' / keypad '-'
                    adjustWPM(by: -2)
                    return nil
                default:
                    break
                }
            }

            let fKeyCodes: [UInt16: Int] = [
                122: 0, 120: 1, 99: 2, 118: 3, 96: 4, 97: 5, 98: 6, 100: 7,
            ]
            if let index = fKeyCodes[event.keyCode] {
                sendMessageAt(index)
                return nil
            }
            if event.keyCode == 53 {  // Esc: abort CW + stop repeating
                radio.abortCW(settings: settings)
                return nil
            }
            return event
        }
    }

    // MARK: Export

    private func exportADIF() {
        guard let party else { return }
        exportDoc = TextExportDocument(text: AdifExporter.export(log: document.log, party: party))
        exportType = .plainText
        exportName = "\(document.log.station.callsign.isEmpty ? "log" : document.log.station.callsign).adi"
        isExporting = true
    }

    private func exportCabrillo() {
        guard let party else { return }
        exportDoc = TextExportDocument(
            text: CabrilloExporter.export(log: document.log, party: party, score: score)
        )
        exportType = .plainText
        exportName = "\(document.log.station.callsign.isEmpty ? "log" : document.log.station.callsign).log"
        isExporting = true
    }
}

/// Grabs the hosting NSWindow so the document's display name can be set.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
    }
}

/// Plain-text FileDocument for save panels.
struct TextExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
