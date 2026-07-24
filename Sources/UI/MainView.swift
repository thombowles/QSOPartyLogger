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
                MessagesEditor(settings: settings)
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
            Divider()

            stationStrip
            Divider()

            EntryBar(entry: entry, party: party, onLog: logContact, focus: $focusedField)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            MessagesRow(
                messages: settings.messages,
                expand: expandMacros,
                onSend: sendMessage,
                enabled: radio.isConnected && currentModeClass == .cw
            )
            Divider()

            logTable
        }
        .frame(minWidth: 760)
        .onChange(of: entry.exchange) { revalidate() }
        .onChange(of: entry.call) { revalidate() }
        .onChange(of: radio.radioState?.band) { revalidate() }
        .onChange(of: radio.radioState?.mode) { revalidate() }
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
        }
    }

    // MARK: Actions

    private func onAppear() {
        if document.log.station.callsign.isEmpty {
            showSetup = true
        }
        focusedField = .call
        installKeyMonitor()
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
            let fKeyCodes: [UInt16: Int] = [
                122: 0, 120: 1, 99: 2, 118: 3, 96: 4, 97: 5, 98: 6, 100: 7,
            ]
            if let index = fKeyCodes[event.keyCode] {
                if settings.messages.indices.contains(index) {
                    sendMessage(settings.messages[index])
                }
                return nil
            }
            if event.keyCode == 53 {  // Esc: abort CW immediately
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
