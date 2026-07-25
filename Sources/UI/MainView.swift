import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @Bindable var document: LogDocument
    @Environment(\.undoManager) private var undoManager

    @State private var settings = AppSettings.shared
    @State private var radio = RadioController()
    /// Everything the radio keys goes through here. This view builds the
    /// context, calls the flow, and hands the returned text to the radio — it
    /// never decides what that text is.
    @State private var flow: EntryFlow
    @FocusState private var focusedField: EntryBar.Field?

    init(document: LogDocument) {
        self.document = document
        // Built once with the document, not per body pass: the flow caches the
        // party lookup and owns the entry row's link to the log's QSO number.
        _flow = State(initialValue: EntryFlow(document: document))
    }

    private var entry: EntryState { flow.entry }

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

    @State private var repeatCQ = false
    @State private var repeatTask: Task<Void, Never>?
    @State private var hostWindow: NSWindow?

    @State private var spotStore = SpotStore()
    @State private var spotClient = SpotClient()
    @State private var spotPurgeTask: Task<Void, Never>?
    @State private var showClusterPopover = false
    @State private var clusterCommand = ""
    /// Reference frequency for ⌘←/⌘→ when no live radio frequency exists.
    @State private var spotCursorKHz: Double?
    /// Run frequency captured when CQ is sent; ⌘J jumps back to it.
    @State private var cqFrequencyHz: Int?

    @State private var bandMapModel: BandMapModel?
    @State private var bandMapPanel: NSPanel?

    private var party: PartyDefinition? {
        flow.party
    }

    /// The one place the view describes "right now" to the flow. Built in a
    /// single property so there is a single place it can be got wrong, and so a
    /// test constructs the same value rather than reproducing the wiring.
    private var operatingContext: EntryFlow.Context {
        EntryFlow.Context(
            band: currentBand,
            modeClass: currentModeClass,
            rawMode: currentRawMode,
            freqKHz: radio.radioState?.frequencyKHz,
            radioConnected: radio.isConnected,
            cursor: esmCursor,
            keying: settings.keying
        )
    }

    /// The document owns the mode so it survives a reopen. Writes go straight
    /// to `log` without registering undo — ⌘Z belongs to log edits, and an
    /// operator who toggles Run/S&P four times should not have to press it
    /// four times to reach a deleted QSO. The change rides along with the next
    /// save, which the QSO-append autosave triggers on the next contact.
    private var operatingMode: Binding<OperatingMode> {
        Binding(
            get: { document.log.operatingMode },
            set: { document.log.operatingMode = $0 }
        )
    }

    private var score: ScoreEngine.ScoreBreakdown {
        guard let party else { return .init() }
        return ScoreEngine.score(log: document.log, party: party)
    }

    private var currentBand: Band {
        radio.radioState?.band ?? manualBand
    }

    private var currentRawMode: String {
        radio.radioState?.rawMode ?? manualRawMode
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
                EditQSOSheet(
                    original: qso,
                    party: party,
                    role: document.log.myLocation.isInState ? .inState : .outOfState
                ) { updated in
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
                .layoutPriority(1)
            ScoreSidebar(log: document.log, party: party, score: score)
        }
    }

    /// Spots on the current band after every filter — the band map and
    /// ⌘←/⌘→ work from this same list so they can't disagree.
    private var visibleSpotsOnBand: [Spot] {
        SpotFilter.filter(
            spotStore.spots(band: currentBand),
            options: settings.spotFilterOptions(workedCalls: workedCallsOnCurrentBandMode)
        )
    }

    /// Calls already in the log on the current band+mode — grays their spots.
    private var workedCallsOnCurrentBandMode: Set<String> {
        Set(
            document.log.qsos
                .filter { $0.band == currentBand && $0.modeClass == currentModeClass }
                .map { $0.call.uppercased() }
        )
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
            .onChange(of: radio.radioState?.rawMode) { modeChanged() }
            .onChange(of: radio.radioReportedWPM) { syncSpeedFromRadio() }
            .onChange(of: repeatCQ) { repeatCQChanged() }
            .onChange(of: radio.isConnected) { if !radio.isConnected { stopRepeat() } }
            Divider()

            stationStrip
                .onChange(of: document.log.partyID) { applyDefaultDocumentName() }
                .onChange(of: document.log.station.callsign) { applyDefaultDocumentName() }
                .onChange(of: document.log.setupCompleted) { autoSaveNewDocumentIfNeeded() }
                .onChange(of: document.log.qsos) { autoSaveAfterChange() }
            Divider()

            EntryBar(entry: entry, party: party, onLog: returnPressed, focus: $focusedField)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .onChange(of: entry.exchange) { revalidate() }
                .onChange(of: entry.call) { revalidate() }

            MessagesRow(
                operatingMode: operatingMode,
                messages: flow.activeMessages,
                expand: { flow.expandMacros($0, context: operatingContext) },
                onSend: sendMessageAt,
                enabled: radio.isConnected && currentModeClass == .cw,
                pendingIndex: pendingMessageIndex,
                repeatEnabled: $repeatCQ,
                repeatInterval: $settings.repeatIntervalSeconds,
                esmEnabled: $settings.esmEnabled,
                cqFrequencyLabel: cqFrequencyHz.map { String(format: "%.1f", Double($0) / 1000) },
                onJumpToCQ: jumpToCQFrequency
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
        .onChange(of: manualRawMode) { modeChanged() }
        .onChange(of: currentBand) { bandMapModel?.band = currentBand }
        .onChange(of: workedCallsOnCurrentBandMode) {
            bandMapModel?.workedCalls = workedCallsOnCurrentBandMode
        }
        .onChange(of: cqFrequencyHz) {
            bandMapModel?.cqKHz = cqFrequencyHz.map { Double($0) / 1000 }
        }
        .onChange(of: settings.spotMaxAgeMinutes) {
            spotStore.maxAgeMinutes = settings.spotMaxAgeMinutes
            spotStore.purge(now: Date())
        }
        // The QSO number needs no re-seeding here: `EntryState.serialSent`
        // follows the log until the operator types over it, so a document that
        // is still `ksqp` when the entry appears picks up the real party's
        // numbering the moment Contest Setup chooses it.
        .onChange(of: document.log.partyID) {
            bandMapModel?.partyBands = party?.validBands ?? Band.allCases
        }
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
        spotPurgeTask?.cancel()
        spotPurgeTask = nil
        spotClient.disconnect()
        bandMapPanel?.close()
        bandMapPanel = nil
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

            Button {
                toggleBandMap()
            } label: {
                Label("Band Map", systemImage: "ruler")
            }
            .help("Band map — spots by frequency with the VFO marker (⌘B)")

            Button {
                showClusterPopover.toggle()
            } label: {
                Label(
                    "Spots",
                    systemImage: spotClient.status == .connected
                        ? "antenna.radiowaves.left.and.right.circle.fill"
                        : "antenna.radiowaves.left.and.right"
                )
                .foregroundStyle(spotClient.status == .connected ? .green : .primary)
            }
            .help("DX cluster connection for spots — click a spot to tune, ⌘← / ⌘→ / ⌘↑ / ⌘↓ to step")
            .popover(isPresented: $showClusterPopover) {
                clusterPopover
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

    // MARK: DX cluster popover

    private var clusterPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DX Cluster")
                .font(.headline)
            HStack(spacing: 6) {
                TextField("dxc.example.com", text: $settings.clusterHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                TextField("Port", value: $settings.clusterPort, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
            }
            if !settings.clusterHistory.isEmpty {
                Menu("Recent Clusters") {
                    ForEach(settings.clusterHistory, id: \.self) { entry in
                        Button(entry) {
                            if let parsed = ClusterHistory.parse(entry) {
                                settings.clusterHost = parsed.host
                                settings.clusterPort = Int(parsed.port)
                                connectCluster()
                            }
                        }
                    }
                    Divider()
                    Button("Clear List") { settings.clusterHistory = [] }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("On connect")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("sh/dx 30", text: $settings.clusterCommands, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospaced())
                    .lineLimit(2...4)
                    .frame(width: 246)
                    .help("Commands sent after login, one per line. sh/dx backfills recent spots.")
            }

            Toggle("Connect automatically when a contest opens", isOn: $settings.clusterAutoConnect)
                .font(.callout)

            Text("Spot filters (continent, mode, band, age) live in the band map window — ⌘B.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 250, alignment: .leading)

            HStack(spacing: 8) {
                if spotClient.status == .disconnected {
                    Button("Connect") { connectCluster() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Disconnect") {
                        spotClient.disconnect()
                    }
                }
                switch spotClient.status {
                case .disconnected:
                    Text("Not connected").foregroundStyle(.secondary)
                case .connecting:
                    Text("Connecting…").foregroundStyle(.orange)
                case .loggingIn:
                    Text("Logging in…").foregroundStyle(.orange)
                case .connected:
                    Label(
                        "\(spotClient.spotsReceived) spots",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                }
            }
            .font(.callout)
            if let error = spotClient.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: 250, alignment: .leading)
            }

            if spotClient.status != .disconnected || !spotClient.console.isEmpty {
                nodeConsole
            }
            Text("Logs in with your callsign. Spots for the current band appear in the sidebar and band map — click to tune, ⌘← / ⌘→ / ⌘↑ / ⌘↓ to step through them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 250, alignment: .leading)
        }
        .padding(14)
    }

    /// Everything the node has said, plus a box to talk back to it. Without
    /// this a node that rejects a login or needs a SET/… command just looks
    /// like "connected, no spots".
    private var nodeConsole: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Node")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(spotClient.console.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(line.hasPrefix(">") ? Color.accentColor : .secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(4)
                }
                .frame(width: 250, height: 140)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 5))
                .onChange(of: spotClient.console.count) {
                    proxy.scrollTo(spotClient.console.count - 1, anchor: .bottom)
                }
            }
            HStack(spacing: 4) {
                TextField("command (e.g. sh/dx 30)", text: $clusterCommand)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .onSubmit(sendClusterCommand)
                Button("Send", action: sendClusterCommand)
                    .controlSize(.small)
                    .disabled(clusterCommand.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .frame(width: 250)
            .disabled(spotClient.status == .disconnected)
        }
    }

    private func sendClusterCommand() {
        spotClient.send(clusterCommand)
        clusterCommand = ""
    }

    private func connectCluster() {
        let port: UInt16 = (1...65535).contains(settings.clusterPort)
            ? UInt16(settings.clusterPort) : 7300
        spotClient.connect(
            host: settings.clusterHost,
            port: port,
            callsign: document.log.station.callsign,
            initialCommands: settings.clusterCommands
        )
        guard spotClient.status != .disconnected else { return }  // refused (no host/call)
        settings.clusterHistory = ClusterHistory.adding(
            ClusterHistory.entry(host: settings.clusterHost, port: Int(port)),
            to: settings.clusterHistory
        )
    }

    // MARK: Actions

    private func onAppear() {
        // New (or never-configured) contests go straight to Contest Setup.
        if !document.log.setupCompleted {
            showSetup = true
        }
        focusedField = .call
        flow.onAppear(operatingContext)
        installKeyMonitor()
        radio.connectAndValidate(settings: settings)

        spotClient.onSpot = { spot in
            spotStore.add(spot)
        }
        if settings.clusterAutoConnect,
           !settings.clusterHost.trimmingCharacters(in: .whitespaces).isEmpty,
           !document.log.station.callsign.isEmpty,
           spotClient.status == .disconnected {
            connectCluster()
        }
        spotPurgeTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                spotStore.purge(now: Date())
            }
        }

        spotStore.maxAgeMinutes = settings.spotMaxAgeMinutes

        if bandMapModel == nil {
            let model = BandMapModel(radio: radio, spotStore: spotStore, settings: settings)
            model.band = currentBand
            model.workedCalls = workedCallsOnCurrentBandMode
            model.partyBands = party?.validBands ?? Band.allCases
            model.onTuneSpot = { tune(to: $0) }
            model.onTuneKHz = { qsyTo(kHz: $0) }
            bandMapModel = model
        }
    }

    // MARK: Band map panel

    private func toggleBandMap() {
        if let panel = bandMapPanel {
            panel.isVisible ? panel.orderOut(nil) : panel.orderFront(nil)
            return
        }
        guard let model = bandMapModel else { return }
        let panel = BandMapPanel.make(model: model, near: hostWindow)
        bandMapPanel = panel
        panel.orderFront(nil)
    }

    /// Mode changes (radio or manual): swap pre-filled RST defaults
    /// (599 ↔ 59) and re-check validation/dupes for the new mode.
    private func modeChanged() {
        flow.modeChanged(operatingContext)
    }

    /// Return key. The flow decides what happens and what goes on the air; this
    /// only carries the decision out to the radio, the focus ring and the setup
    /// sheet. Nothing here may re-expand a message — expansion order is exactly
    /// what the flow exists to pin down.
    private func returnPressed() {
        apply(flow.returnPressed(operatingContext, undoManager: undoManager))
    }

    private func apply(_ outcome: EntryFlow.Outcome) {
        switch outcome {
        case .qsy(let command):
            execute(command)
        case .send(let index, let text):
            keyed(text, fromMessageAt: index)
        case .logged(_, let text):
            focusedField = .call
            if !text.isEmpty { radio.sendCW(text, settings: settings) }
        case .needsSetup:
            showSetup = true
        case .nothing:
            break
        }
    }

    private func keyed(_ text: String, fromMessageAt index: Int) {
        // F1 in Run mode is the CQ — remember where we're running from.
        if operatingMode.wrappedValue == .run, index == 0 {
            captureCQFrequency()
        }
        radio.sendCW(text, settings: settings)
    }

    /// Only the call and exchange fields change what Return does; the signal
    /// reports and QSO numbers behave like the exchange without being it.
    private var esmCursor: ESM.Cursor {
        switch focusedField {
        case .call: .call
        case .exchange: .exchange
        default: .other
        }
    }

    /// The F-key slot Return will send next, or nil when ESM isn't driving it.
    private var pendingMessageIndex: Int? {
        flow.pendingMessageIndex(operatingContext)
    }

    /// F12 — wipe a half-typed contact and get back to the call field.
    private func clearEntry() {
        flow.clearEntry(operatingContext)
        focusedField = .call
    }

    private func sendMessageAt(_ index: Int) {
        let context = operatingContext
        let message = flow.expandedMessage(at: index, context: context)
        guard !message.isEmpty else { return }
        keyed(message, fromMessageAt: index)
    }

    // MARK: Typed QSY commands + spot tuning

    private func execute(_ command: EntryCommand) {
        switch command {
        case .frequency(let kHz):
            qsyTo(kHz: kHz)
        case .band(let band):
            qsyTo(kHz: Double(band.defaultFreqKHz))
        case .mode(let mode):
            if radio.isConnected {
                radio.setMode(rawMode: mode)
            } else {
                manualRawMode = manualToken(for: mode)
            }
        }
    }

    /// Tune the radio (or the manual band picker when disconnected) and move
    /// the spot cursor — shared by typed commands and band-map clicks.
    private func qsyTo(kHz: Double) {
        if radio.isConnected {
            radio.setFrequency(kHz: kHz)
        } else if let band = Band.from(freqKHz: Int(kHz.rounded())) {
            manualBand = band
        }
        spotCursorKHz = kHz
        applyBandPlanMode(kHz: kHz)
    }

    /// Put the radio in the mode the band plan expects at a frequency.
    ///
    /// Called only from the paths where *the app* moved the frequency — a spot
    /// click, a typed QSY, ⌘←/⌘→, ⌘J, a click on empty map. Frequency changes
    /// the operator makes on the VFO knob arrive through `radio.radioState` and
    /// deliberately never reach here: an automatic mode change mid-QSO, because
    /// you drifted across a sub-band edge, is the radio fighting you.
    ///
    /// `BandPlan` decides whether there is a change to make at all — it holds
    /// back on the bands with no defensible CW/phone split, when the mode is
    /// already right, and when a digital operator is moving inside the
    /// CW/data portion of a band. A mode the party does not score is never
    /// selected either: a CW-only sponsor's band plan has no phone segment as
    /// far as this contest is concerned.
    private func applyBandPlanMode(kHz: Double) {
        guard settings.followBandPlan,
              let target = BandPlan.modeChange(toKHz: kHz, currentMode: currentModeClass),
              party?.allowedModeClasses.contains(target) ?? true,
              let rawMode = BandPlan.rawMode(for: target)
        else { return }
        if radio.isConnected {
            radio.setMode(rawMode: rawMode)
        } else {
            manualRawMode = manualToken(for: rawMode)
        }
    }

    /// Map any typed mode onto the manual picker's CW/SSB/RTTY tokens.
    private func manualToken(for mode: String) -> String {
        switch ModeClass.classify(rawMode: mode) {
        case .cw: "CW"
        case .phone: "SSB"
        case .digital: "RTTY"
        }
    }

    private func tune(to spot: Spot) {
        radio.setFrequency(kHz: spot.freqKHz)
        if !radio.isConnected, let band = spot.band {
            manualBand = band
        }
        spotCursorKHz = spot.freqKHz
        applyBandPlanMode(kHz: spot.freqKHz)
        entry.call = spot.call
        focusedField = .call
        revalidate()
    }

    /// ⌘← / ⌘→ / ⌘↑ / ⌘↓. Worked stations stay on the band map, greyed, but there is
    /// nothing left to work on them so the keys step over them.
    private func jumpToSpot(_ direction: SpotStore.Direction) {
        let bandSpots = visibleSpotsOnBand
        let reference = radio.radioState.map { Double($0.frequencyHz) / 1000 }
            ?? spotCursorKHz
            ?? Double(currentBand.defaultFreqKHz)
        guard let spot = SpotStore.next(
            in: bandSpots,
            afterKHz: reference,
            direction: direction,
            workedCalls: workedCallsOnCurrentBandMode
        ) else {
            return
        }
        tune(to: spot)
    }

    // MARK: CQ frequency memory

    private func captureCQFrequency() {
        if let hz = radio.radioState?.frequencyHz {
            cqFrequencyHz = hz
        }
    }

    private func jumpToCQFrequency() {
        guard let hz = cqFrequencyHz else { return }
        let kHz = Double(hz) / 1000
        radio.setFrequency(kHz: kHz)
        spotCursorKHz = kHz
        applyBandPlanMode(kHz: kHz)
        operatingMode.wrappedValue = .run
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
        captureCQFrequency()
        repeatTask = Task {
            while !Task.isCancelled && repeatCQ {
                let text = flow.expandMacros(cq, context: operatingContext)
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

    /// Write the document through to disk after every QSO change (log, edit,
    /// delete, undo) so a crash or power loss mid-contest never costs
    /// contacts. Drafts that don't have a file yet are skipped — the
    /// setup-completion auto-save gives them one.
    private func autoSaveAfterChange() {
        guard let window = hostWindow,
              let nsDocument = window.windowController?.document as? NSDocument,
              let url = nsDocument.fileURL else { return }
        nsDocument.save(to: url, ofType: nsDocument.fileType ?? "QSO Party Log", for: .saveOperation) { error in
            if let error {
                NSLog("Auto-save after QSO change failed: \(error)")
            }
        }
    }

    private func revalidate() {
        flow.revalidate(operatingContext)
    }

    /// The Log button and any Return that is not driven by ESM.
    private func logContact() {
        apply(flow.logContact(operatingContext, undoManager: undoManager))
    }

    // MARK: F-key handling (AppKit monitor — reliable across macOS versions)

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // The monitor is app-wide, so the first question is always whether
            // this keystroke is even ours — see `KeyMonitorGate`.
            let focus = KeyMonitorGate.focus(currentWindows())
            guard focus != .elsewhere else { return event }

            // Any keystroke cancels a running repeat-CQ loop (per Tom's spec:
            // "typing anything cancels repeat"). Typing in *another* log's
            // window no longer stops this one's CQ.
            if repeatTask != nil {
                stopRepeat()
            }

            guard
                let action = KeyMonitorGate.action(
                    keyCode: event.keyCode,
                    command: event.modifierFlags.contains(.command)
                )
            else { return event }

            // A sheet owns the keyboard. Article 11 still holds — Esc aborts
            // instantly wherever it is pressed — but the key is never consumed,
            // so Esc also closes the sheet and F1–F8 cannot transmit a macro the
            // operator is in the middle of editing.
            if focus == .sheet {
                if action == .abortCW {
                    radio.abortCW(settings: settings)
                }
                return event
            }

            perform(action)
            return nil
        }
    }

    /// The live window state the gate reasons about.
    private func currentWindows() -> KeyMonitorGate.Windows {
        let key = NSApp.keyWindow
        return KeyMonitorGate.Windows(
            host: hostWindow?.windowNumber,
            key: key?.windowNumber,
            keySheetParent: key?.sheetParent?.windowNumber,
            bandMap: bandMapPanel?.windowNumber,
            hostHasAttachedSheet: hostWindow?.attachedSheet != nil
        )
    }

    private func perform(_ action: KeyMonitorGate.Action) {
        switch action {
        // ⌘= / ⌘+ and ⌘- (plus keypad variants): CW speed ±2 WPM.
        case .adjustWPM(let delta): adjustWPM(by: delta)
        // ⌘←/⌘→ and ⌘↓/⌘↑: previous/next spot on the band. ⌘J: back to CQ.
        case .previousSpot: jumpToSpot(.down)
        case .nextSpot: jumpToSpot(.up)
        case .jumpToCQFrequency: jumpToCQFrequency()
        case .toggleBandMap: toggleBandMap()
        case .sendMessage(let index): sendMessageAt(index)
        case .clearEntry: clearEntry()
        case .abortCW: radio.abortCW(settings: settings)
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
