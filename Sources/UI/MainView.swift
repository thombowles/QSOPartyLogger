import SwiftUI
import UniformTypeIdentifiers
import os

struct MainView: View {
    @Bindable var document: LogDocument
    @Environment(\.undoManager) private var undoManager

    @State private var settings = AppSettings.shared
    /// The app's one radio, held the way `settings` is — every log window
    /// shares it, and this window counts itself in and out in `onAppear` /
    /// `onDisappear` so the link outlives any one of them.
    @State private var radio = RadioController.shared
    /// Everything the radio puts on the air goes through here. This view builds
    /// the context, calls the flow, and hands the returned transmission to the
    /// radio — it never decides what that transmission is.
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
    @State private var bulkEditing: BulkEditSheet.Request?
    @State private var exportDoc: TextExportDocument?
    @State private var exportType: UTType = .plainText
    @State private var exportName = ""
    @State private var isExporting = false
    /// Why the last export could not run — the save panel refused, or the
    /// write failed — shown inline under the messages row until dismissed or
    /// the next export succeeds. Never a modal, and never silence: on
    /// 2026-08-15 ⌘E "did nothing" twelve times in a row while AppKit was
    /// logging "Unable to display save panel" (`AppIntegrity`).
    @State private var exportNotice: String?
    @State private var keyMonitor: Any?
    /// The second monitor: media keys (`.systemDefined`), watched only so an
    /// F-key that arrives as brightness or backlight can say so. Never
    /// consumed.
    @State private var mediaKeyMonitor: Any?
    /// The line under the messages row when the F row arrives as media keys —
    /// `KeyDiagnostics.fRowNotice`. Cleared by the next real function key.
    @State private var fRowNotice: String?
    /// The last key the monitor ruled on, for the shortcut-hints legend.
    @State private var lastKeyReadout: String?

    @State private var repeatCQ = false
    @State private var repeatTask: Task<Void, Never>?
    @State private var hostWindow: NSWindow?
    /// ⌃⌘S, or the toolbar's Score button: the score sidebar hidden, so this
    /// window can be pushed into a corner while another keeps its sidebar.
    /// Per window, restored with it. The strip shows the total meanwhile.
    @SceneStorage("scoreSidebarHidden") private var scoreSidebarHidden = false

    /// The active party's recordings on this Mac and the recorder behind the
    /// Messages editor's Phone tab. Per window, like the flow.
    @State private var voiceStore = VoiceStore()
    /// Which tab the Messages editor opens on — ⇧⌘V lands on Phone.
    @State private var messagesEditorClass: ModeClass = .cw
    /// Which F-key slot the editor should open focused on, when it was opened
    /// from one. Nil when it was opened from the toolbar or ⇧⌘V, which are
    /// about the whole set rather than one key.
    @State private var messagesEditorSlot: Int?

    @State private var spotStore = SpotStore()
    @State private var spotClient = SpotClient()
    @State private var hubSpotClient = HubSpotClient()
    @State private var callHistoryClient = CallHistoryClient()
    @State private var dxccLabelClient = DXCCLabelClient()
    @State private var spaceWeatherClient = SpaceWeatherClient()
    @State private var scpClient = SCPClient()
    @State private var potaParkClient = PotaParkClient()
    /// The POTA activator board — the hunting feed (spec 2026-08-25
    /// decision 3). Polled while `SpottingPolicy.potaShouldPoll` says so.
    @State private var potaBoardClient = PotaBoardClient()
    /// Callsign lookup (QRZ/HamQTH). The configuration closure reads the
    /// live settings per lookup, so the pane's edits apply without a
    /// restart — and nothing here touches `AppSettings.shared` until a
    /// lookup actually runs.
    @State private var callbookClient = CallbookClient(configuration: {
        .init(qrzEnabled: AppSettings.shared.qrzEnabled,
              qrzUsername: AppSettings.shared.qrzUsername,
              hamqthEnabled: AppSettings.shared.hamqthEnabled,
              hamqthUsername: AppSettings.shared.hamqthUsername,
              primary: AppSettings.shared.callbookPrimary)
    })
    @State private var showLookupPopover = false
    @State private var potaSpotClient = PotaSpotClient()
    /// Fans one confirmed spot out to every ticked network and keeps the
    /// receipt. Its transports are wired in `onAppear`, once the clients
    /// exist to wire them to.
    @State private var spotDispatcher = SpotDispatcher(transports: .init(
        sendClusterCommand: { _ in false }, postToHub: { _, _ in }, postToPota: { _ in }
    ))
    @State private var locationProvider = MacLocationProvider()
    @State private var showSpotSheet = false
    @State private var spotDraft = SpotDraft.empty
    /// Who the open sheet is for — it decides POTA's row (your park, or theirs).
    @State private var spotTarget = SpotNetworkAvailability.Target.myself
    /// The county the last self-spot went out for, so a rover is prompted when
    /// it moves — the moment that matters, and the one most often forgotten.
    @State private var lastSelfSpotCounty: String?
    @State private var spotPurgeTask: Task<Void, Never>?
    @State private var showClusterPopover = false
    @State private var clusterCommand = ""
    /// Session-scoped on purpose: a claim that is still wrong earns one nag
    /// per sitting, and the Cabrillo export stands it back up regardless.
    @State private var spotWarningDismissed = false
    /// Reference frequency for ⌘↑/⌘↓ when no live radio frequency exists.
    @State private var spotCursorKHz: Double?
    /// Run frequency captured when CQ is sent; ⌘J jumps back to it.
    @State private var cqFrequencyHz: Int?
    /// Which side of the CQ frequency the VFO was on at the last report — on
    /// it, near it, or away — so only a *change* of zone switches the mode
    /// (`TuningPolicy`). Reset to `.onFrequency` when a CQ frequency is
    /// captured; nil when there is none.
    @State private var cqZone: TuningPolicy.Zone?

    @State private var bandMapModel: BandMapModel?
    @State private var bandMapPanel: NSPanel?
    /// The panel's relationship to this window — floating, or bolted to its
    /// side (`settings.bandMapBolted`). Made with the panel; closed with it.
    @State private var bandMapBolt: BandMapBolt.Attachment?

    private var party: PartyDefinition? {
        flow.party
    }

    /// The entry row's shape for this log — party flags, or the contest's
    /// exchange spec for a v2-only contest (POTA).
    private var entryLayout: EntryLayout {
        EntryLayout(party: party, contest: flow.standaloneContest,
                    isActivation: !document.log.myPotaRefs.isEmpty)
    }

    /// The quiet line under the park field: the refs as parsed, each with its
    /// name when the offline directory knows it. Silent while empty or
    /// unparseable — the red refuse-to-log label owns that case. A park with
    /// an `@subdivision` looks up by its base reference.
    private var parkCaption: String? {
        let typed = entry.theirParkTyped.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return nil }
        guard case .success(let parks) = PotaRef.parseList(PotaRef.expandShorthand(typed)), !parks.isEmpty else { return nil }
        let directory = potaParkClient.directory
        let parts = parks.map { ref -> String in
            let base = ref.split(separator: "@", maxSplits: 1).first.map(String.init) ?? ref
            if let name = directory?.park(reference: base)?.name { return "\(ref) · \(name)" }
            return ref
        }
        return parts.joined(separator: "  ·  ")
    }

    /// Cabrillo exists for every party, and for a v2 contest only where its
    /// spec says so — POTA's says not (`cabrillo.submittable`).
    private var cabrilloOffered: Bool {
        party != nil || (flow.standaloneContest?.cabrillo.submittable ?? false)
    }

    /// The callbook's quiet line for the call in the field — only while the
    /// published record is for exactly that call, so a half-edited call
    /// never wears the last station's name.
    private var callbookCaption: String? {
        guard let known = callbookClient.record,
              !entry.call.isEmpty,
              known.call == entry.callNormalized else { return nil }
        guard let line = CallbookCaption.line(
            for: known, stationGrid: document.log.station.gridLocator) else { return nil }
        return "\(line) — \(known.source.label)"
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
            keying: settings.keying,
            voiceMemoryCount: radio.voiceStatus.memoryCount,
            phoneSource: phoneSource,
            offersSpotCounty: settings.prefillExchangeFromSpots
        )
    }

    /// Where phone keys get their audio right now — the one place the setting,
    /// the connected radio and the audio path's readiness are combined
    /// (Article 11 as amended 2026-08-15). A radio that takes no audio from
    /// the Mac falls to its own memories, and the editor says so; a path that
    /// is merely not set up leaves the keys silent, never a different source.
    private var phoneSource: EntryFlow.PhoneSource {
        switch settings.phoneMessageSource {
        case .radioMemories:
            return .radioMemories
        case .recordings:
            switch radio.voicePathStatus {
            case .unsupported: return .radioMemories
            case .notReady: return .recordings(ready: false)
            case .readyOverNetwork, .readyOverDevice: return .recordings(ready: true)
            }
        }
    }

    /// Whether the phone F-keys can do anything at all: the radio's recorder
    /// is ready, or the recordings path is.
    private var phoneKeysEnabled: Bool {
        switch phoneSource {
        case .radioMemories: radio.voiceStatus.isReady
        case .recordings(let ready): ready
        }
    }

    /// What the messages row draws for F1–F8 right now. Built here rather than
    /// in the row so the row never has to know which mode class is live.
    private var messageKeys: [MessagesRow.MessageKey] {
        let context = operatingContext
        return (0..<8).map { index in
            switch flow.transmission(at: index, context: context) {
            case .cw(let text):
                MessagesRow.MessageKey(caption: text, isActive: true)
            case .voice(_, let caption), .recording(_, _, let caption):
                MessagesRow.MessageKey(caption: caption, isActive: true)
            case .silent:
                MessagesRow.MessageKey(caption: context.modeClass == .phone ? "—" : "",
                                       isActive: false)
            }
        }
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
        if let party { return ScoreEngine.score(log: document.log, party: party) }
        if let contest = flow.standaloneContest {
            // A v2-only contest (POTA): the general engine, zero points by
            // design — the QSO and dupe counts are what the sidebar reads.
            return ScoreEngine.score(log: document.log, contest: contest)
        }
        return .init()
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
            // 360 holds the radio bar, the strip, the entry and message rows
            // and five log rows; the width is the pane's floor plus the
            // sidebar when it is shown. Two of these fit beside a panadapter
            // (2026-08-22). Narrower than its rows need, the rows fold.
            .frame(minHeight: 360)
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
            .sheet(isPresented: $showSetup) {
                SetupSheet(document: document, callHistory: callHistoryClient,
                           scp: scpClient, parks: potaParkClient,
                           locationProvider: locationProvider)
            }
            .sheet(isPresented: $showMessagesEditor) {
                MessagesEditor(document: document, settings: settings,
                               voiceStatus: radio.voiceStatus, voiceBank: radio.voiceBank,
                               voiceStore: voiceStore, radio: radio,
                               onPlayToRadio: playRecordingToRadio,
                               initialClass: messagesEditorClass,
                               initialSlot: messagesEditorSlot)
            }
            .sheet(isPresented: $showSpotSheet) {
                if let party {
                    SpotSheet(
                        target: spotTarget,
                        party: party,
                        baseContext: spotContext(target: spotTarget, draftPark: spotDraft.park),
                        draft: $spotDraft,
                        onSend: { draft in
                            showSpotSheet = false
                            // Remember the ticks — for the networks that were
                            // on offer; an unavailable one keeps its old bit.
                            settings.spotNetworks = SpotNetwork.updatedPreference(
                                preferred: settings.spotNetworks,
                                available: SpotNetworkAvailability.available(
                                    in: spotContext(target: spotTarget, draftPark: draft.park)
                                ),
                                selected: draft.networks
                            )
                            spotDispatcher.send(draft, party: party)
                        },
                        onCancel: { showSpotSheet = false }
                    )
                }
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
            .sheet(item: $bulkEditing) { request in
                BulkEditSheet(
                    rows: request.rows,
                    allRows: document.log.qsos,
                    party: party,
                    isInState: document.log.myLocation.isInState
                ) { updated in
                    document.update(
                        qsos: updated,
                        actionName: updated.count == 1
                            ? "Change 1 Contact" : "Change \(updated.count) Contacts",
                        undoManager: undoManager
                    )
                }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDoc,
                contentType: exportType,
                defaultFilename: exportName
            ) { result in
                // A failure to write is news; a cancel is not.
                if case .failure(let error) = result {
                    exportNotice = "Export failed — \(error.localizedDescription)"
                }
            }
            .toolbar { toolbarContent }
    }

    private var splitContent: some View {
        HSplitView {
            leftPane
                .layoutPriority(1)
            if !scoreSidebarHidden {
                ScoreSidebar(
                    log: document.log, party: party, score: score, members: flow.combinedMembers,
                    advisorInput: advisorInput, onTune: tune
                )
            }
        }
    }

    /// Everything the Advisor reads, in one expression.
    ///
    /// A closure rather than a value because a rate reading and a trailing
    /// window are both functions of the instant they are taken at, and because
    /// building one on every body pass would cost a fold of the log for
    /// nothing — the section asks for it on its own thirty-second tick.
    private var advisorInput: (Date) -> Advisor.Input {
        { now in
            Advisor.Input.make(
                goal: settings.advisorGoal,
                log: document.log,
                party: party,
                score: score,
                reading: RateMeter.reading(timestamps: scoredTimestamps, now: now),
                currentBand: currentBand,
                currentModeClass: currentModeClass,
                spotsOnBand: visibleSpots(on:),
                spaceWeather: spaceWeatherClient.reading,
                followsBandPlan: settings.followBandPlan,
                mutedKinds: settings.advisorMutedKinds,
                now: now
            )
        }
    }

    /// Timestamps of the rows the score counts — the same exclusion
    /// `ScoreSidebar` makes before handing them to `RateMeter`, so the
    /// advisor's "12/hr last 10" is the figure in the rate column beside it.
    private var scoredTimestamps: [Date] {
        let excluded = score.dupeRowIDs
            .union(score.invalidRowIDs)
            .union(score.outOfScopeRowIDs)
        return document.log.qsos.filter { !excluded.contains($0.id) }.map(\.timestampUTC)
    }

    /// Spots on the current band after every filter — the band map and
    /// ⌘↑/⌘↓ work from this same list so they can't disagree.
    private var visibleSpotsOnBand: [Spot] {
        visibleSpots(on: currentBand)
    }

    /// The same list for any band, which is what the advisor needs to compare
    /// one against another. Each band is filtered against **its own** worked
    /// stations, because a call worked on 20 m is still workable on 40.
    private func visibleSpots(on band: Band) -> [Spot] {
        SpotFilter.filter(
            spotStore.spots(band: band),
            options: settings.spotFilterOptions(
                workedCalls: workedCalls(on: band),
                allowedModes: party?.allowedModeClasses ?? [],
                workedCallCounties: workedCallCounties(on: band)
            )
        )
    }

    /// Every prior contact with the call in the entry field — the history
    /// table's contents, and the reason it is on screen at all.
    private var workedBefore: [DupeChecker.WorkedContact] {
        DupeChecker.workedContacts(call: entry.callNormalized, log: document.log.qsos)
    }

    /// "KSQP 2025 — JOH" when previous contests know the station and this one
    /// does not — or, failing that, what the party's call history file says
    /// he sends. It is where a pre-filled exchange came from, which is why it
    /// belongs on screen rather than only in the field.
    private var workedBeforeArchiveLine: String? {
        guard workedBefore.isEmpty, !entry.callNormalized.isEmpty else { return nil }
        if let seen = flow.archiveIndex.entries(for: entry.callNormalized).first {
            return "\(seen.partyID.uppercased()) \(seen.year) — \(seen.theirLoc)"
        }
        guard let (partyID, parsed) = flow.callHistoryIndex,
              partyID == party?.id,
              let known = parsed.entry(for: entry.callNormalized),
              !known.isEmpty
        else { return nil }
        let bits = [known.name, known.locations.first, known.userText]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return "Call history — \(bits.joined(separator: " · "))"
    }

    private var workedBeforeHeight: CGFloat {
        WorkedBeforeTable.height(
            contacts: workedBefore.count,
            hasArchiveLine: workedBeforeArchiveLine != nil
        )
    }

    /// Calls already in the log on the current band+mode — grays their spots.
    private var workedCallsOnCurrentBandMode: Set<String> {
        workedCalls(on: currentBand)
    }

    private func workedCalls(on band: Band) -> Set<String> {
        Set(
            document.log.qsos
                .filter { $0.band == band && $0.modeClass == currentModeClass }
                .map { $0.call.uppercased() }
        )
    }

    /// The same, but paired with the county each contact was made in, so a
    /// mobile that has moved is not mistaken for a station already worked.
    /// `DupeChecker.DupeKey` counts a new county as a new contact; without
    /// this the band map would keep hiding a rover through every county it
    /// drives into, which is exactly where the multipliers are.
    private var workedCallCountiesOnCurrentBandMode: Set<String> {
        workedCallCounties(on: currentBand)
    }

    private func workedCallCounties(on band: Band) -> Set<String> {
        Set(
            document.log.qsos
                .filter { $0.band == band && $0.modeClass == currentModeClass }
                .map { "\($0.call.uppercased())|\($0.theirLoc.uppercased())" }
        )
    }

    /// The radio bar with the radio-driven wiring — frequency, band, mode,
    /// speed, connection, and the voice path — pulled out of `leftPaneContent`
    /// so that VStack stays under the type-checker's budget (2026-08-04).
    private var radioBar: some View {
        RadioBar(
            settings: settings,
            radio: radio,
            party: party,
            manualBand: $manualBand,
            manualRawMode: $manualRawMode
        )
        .onChange(of: radio.radioState?.band) { revalidate() }
        .onChange(of: radio.radioState?.rawMode) { modeChanged() }
        // The knob: Run ⇄ S&P round the CQ frequency, and the call frame.
        .onChange(of: radio.radioState?.frequencyHz) { vfoMoved() }
        .onChange(of: radio.radioReportedWPM) { syncSpeedFromRadio() }
        .onChange(of: repeatCQ) { repeatCQChanged() }
        .onChange(of: radio.isConnected) { if !radio.isConnected { interruptRepeat(.disconnected) } }
        // The recordings path re-derives from the voice settings while
        // connected; `connect` derives it itself.
        .onChange(of: settings.voiceOutputDeviceUID) { radio.refreshVoicePath(settings: settings) }
        .onChange(of: settings.voicePTT) { radio.refreshVoicePath(settings: settings) }
        .onChange(of: settings.phoneMessageSource) { radio.refreshVoicePath(settings: settings) }
        // The flow reads recordings by value, like the call history file.
        .onChange(of: voiceStore.rendered) { flow.voiceRecordings = voiceStore.rendered }
    }

    /// The pane's content, separate from its `onChange` wiring: one
    /// expression holding both put the type-checker over its budget the day
    /// the super check strip joined the stack (2026-08-04). Splitting at an
    /// opaque seam bounds each half.
    private var leftPaneContent: some View {
        VStack(spacing: 0) {
            radioBar
            Divider()

            stationStrip
                .onChange(of: document.log.partyID) { applyDefaultDocumentName() }
                .onChange(of: document.log.partyID) { voiceStore.partyID = document.log.partyID }
                .onChange(of: document.log.station.callsign) { applyDefaultDocumentName() }
                .onChange(of: document.log.setupCompleted) { autoSaveNewDocumentIfNeeded() }
                .onChange(of: document.log.qsos) {
                    autoSaveAfterChange()
                    // Every change to the log changes which multipliers are
                    // still needed — including a row deleted on another band.
                    bandMapModel?.log = document.log
                }
            Divider()

            EntryBar(entry: entry, party: party, layout: entryLayout,
                     parkCaption: parkCaption,
                     callbookCaption: callbookCaption,
                     callFrameColor: callFrameColor, onTakeCallFrame: takeCallFrame,
                     onLog: returnPressed, focus: $focusedField)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .onChange(of: entry.exchange) { revalidate() }
                .onChange(of: entry.call) {
                    flow.callChanged(operatingContext)
                    callbookClient.noteCallChanged(entry.call)
                }
                .onChange(of: callbookClient.record) {
                    flow.callbookRecord = callbookClient.record
                }
                // The member element can decide the NEW MULT badge (a party
                // may count the worked station itself), so it revalidates
                // like the exchange rather than only gating the log.
                .onChange(of: entry.memberRcvd) { revalidate() }

            superCheckStrip

            MessagesRow(
                operatingMode: operatingMode,
                keys: messageKeys,
                onSend: sendMessageAt,
                onEdit: editMessageAt,
                enabled: radio.isConnected
                    && (currentModeClass == .cw
                        || (currentModeClass == .phone && phoneKeysEnabled)),
                pendingIndex: pendingMessageIndex,
                repeatEnabled: $repeatCQ,
                repeatPaused: repeatPaused,
                repeatInterval: $settings.repeatIntervalSeconds,
                esmEnabled: $settings.esmEnabled,
                cqFrequencyLabel: cqFrequencyHz.map { String(format: "%.1f", Double($0) / 1000) },
                onJumpToCQ: jumpToCQFrequency
            )

            keyNoticeStrip

            if workedBeforeHeight > 0 {
                WorkedBeforeTable(
                    call: entry.callNormalized,
                    contacts: workedBefore,
                    archiveLine: workedBeforeArchiveLine,
                    currentBand: currentBand,
                    currentModeClass: currentModeClass
                )
            }
            Divider()

            logTable
        }
    }

    /// Under the messages row: the shortcut legend while hints are on (⌘/),
    /// and the F-row notice when the keyboard sent a media key where an F-key
    /// was expected. Inline, dismissable, and gone by itself the moment a real
    /// F-key arrives — never a modal.
    @ViewBuilder
    private var keyNoticeStrip: some View {
        if settings.showShortcutHints {
            VStack(alignment: .leading, spacing: 2) {
                Text(ShortcutLegend.line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ShortcutLegend.lastKeyLine(lastKeyReadout))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("What the logger last received from the keyboard, and what it did with it — "
                          + "press an F-key here to check the F row reaches the app")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
        }
        if let notice = fRowNotice {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    fRowNotice = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dismiss keyboard notice")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
        }
        // An export that could not run says so here — the same inline place,
        // never a modal (Tom's rule), and never silence.
        if let notice = exportNotice {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label(notice, systemImage: "square.and.arrow.up.trianglebadge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    exportNotice = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dismiss export notice")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
        }
    }

    /// Reserved height while the feature is live (option on, and a database
    /// or the party's call history loaded), so the strip filling and emptying
    /// under a 35 WPM exchange never reflows the window. Absent entirely
    /// otherwise.
    @ViewBuilder
    private var superCheckStrip: some View {
        if settings.superCheckEnabled, flow.superCheckLive {
            SuperCheckRow(matches: flow.superCheckMatches, typedCall: entry.callNormalized)
                .padding(.horizontal, 14)
        }
    }

    /// The pane with its band-map and spot wiring — the first half of an
    /// `onChange` chain the type-checker cannot swallow whole (the same
    /// budget split as `leftPaneContent`). Document and settings wiring is
    /// the second half, in `leftPane`.
    private var leftPaneSpotWired: some View {
        leftPaneContent
        // The everyday entry row — call, two reports, the exchange, Log — on
        // one line with its padding (535 + 24; `ViewThatFits` picks the line
        // by its ideal width, Log button and all). The widest party's row
        // folds below ~770 (`WindowSizeTests`).
        .frame(minWidth: 560)
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
        .onChange(of: workedCallCountiesOnCurrentBandMode) {
            bandMapModel?.workedCallCounties = workedCallCountiesOnCurrentBandMode
            // The log changed, so which counties are still multipliers has too.
            bandMapModel?.log = document.log
        }
        .onChange(of: cqFrequencyHz) {
            bandMapModel?.cqKHz = cqFrequencyHz.map { Double($0) / 1000 }
            cqZone = cqFrequencyHz == nil ? nil : .onFrequency
        }
        .onChange(of: settings.spotMaxAgeMinutes) {
            spotStore.maxAgeMinutes = settings.spotMaxAgeMinutes
            spotStore.purge(now: Date())
        }
        .onChange(of: settings.hubSpotMaxAgeMinutes) {
            spotStore.hubMaxAgeMinutes = settings.hubSpotMaxAgeMinutes
            spotStore.purge(now: Date())
        }
        .onChange(of: settings.hubSpotsEnabled) { syncHubSpotClient() }
        .onChange(of: settings.potaSpotsInParties) { syncPotaBoardClient() }
        // The board lands in the same store as every other feed, wholesale
        // per poll — a row gone from the feed is QRT or expired. Receiving
        // spots is assistance, recorded exactly as the hub records it.
        .onChange(of: potaBoardClient.spots) {
            spotStore.replace(source: .pota, with: potaBoardClient.spots)
            if !potaBoardClient.spots.isEmpty { document.noteSpotsUsed() }
        }
    }

    /// The bolt's wiring: the two settings that fasten the band map to this
    /// window. Its own seam, between the spot and tuning halves, for the same
    /// type-checker reason.
    private var leftPaneBoltWired: some View {
        leftPaneSpotWired
        .onChange(of: settings.bandMapBolted) { applyBandMapBolt() }
        .onChange(of: settings.bandMapBoltSide) { applyBandMapBolt() }
    }

    /// The mode and tuning wiring — its own seam for the same type-checker
    /// reason as the other two.
    private var leftPaneTuningWired: some View {
        leftPaneBoltWired
        // Leaving Run — by ⌘R or by tuning off the CQ frequency — takes Repeat
        // CQ down (N1MM: turned off "when … the mode changed to S&P"), and
        // the call frame follows the mode: empty in Run.
        .onChange(of: document.log.operatingMode) { operatingModeChanged() }
        .onChange(of: settings.callFrameEnabled) { refreshCallFrame() }
    }

    private var leftPane: some View {
        leftPaneTuningWired
        // Declaring NON-ASSISTED takes effect at once — an open connection is
        // dropped and the network spots come off the map, because a claim
        // that only applies to future spots is not a claim.
        .onChange(of: document.log.station.categoryAssisted) { enforceSpottingPolicy() }
        // A conflict that returns — spots on the record from an assisted
        // stretch, the claim now back to NON-ASSISTED — stands the badge back
        // up; going quiet leaves the dismissal alone.
        .onChange(of: document.log.spotsContradictNonAssistedClaim) { _, conflict in
            spotWarningDismissed = SpottingPolicy.rearm(
                dismissed: spotWarningDismissed, conflict: conflict
            )
        }
        .onChange(of: document.log.myLocation.sentExchanges) { offerReSpotOnCountyChange() }
        // Setup is where a rover changes county, so the offer waits for it to
        // close rather than stacking a sheet on top of it.
        .onChange(of: showSetup) { _, isOpen in
            guard !isOpen else { return }
            // Setup is also where the callsign and the park arrive, and
            // there is no spotting without the one and no POTA without the
            // other.
            bandMapModel?.canSpot = canSpotStation
            offerReSpotOnCountyChange()
        }
        // The QSO number needs no re-seeding here: `EntryState.serialSent`
        // follows the log until the operator types over it, so a document that
        // is still `ksqp` when the entry appears picks up the real party's
        // numbering the moment Contest Setup chooses it.
        .onChange(of: document.log.partyID) {
            bandMapModel?.partyBands = party?.validBands ?? Band.allCases
            bandMapModel?.allowedModes = party?.allowedModeClasses ?? []
            bandMapModel?.party = party
            bandMapModel?.canSpot = canSpotStation
            syncHubSpotClient()
            syncPotaBoardClient()
            activateCallHistory()
            activateSuperCheck()
            checkDXCCLabels()
        }
        .onChange(of: settings.callHistoryEnabled) { activateCallHistory() }
        .onChange(of: settings.superCheckEnabled) { activateSuperCheck() }
    }

    private var logTable: some View {
        LogTable(
            qsos: document.log.qsos,
            score: score,
            party: party,
            onDeleteRows: { document.remove(ids: $0, undoManager: undoManager) },
            onDeleteGroup: { document.removeGroup(groupID: $0.groupID, undoManager: undoManager) },
            onEdit: { editingQSO = $0 },
            showsPotaColumns: flow.standaloneContest?.potaProgram == true,
            onBulkEdit: { bulkEditing = BulkEditSheet.Request(rows: $0) },
            canSpot: canSpotStation,
            onSpotStation: { qso in
                beginSpot(
                    station: qso.call,
                    frequencyKHz: qso.freqKHz.map(Double.init),
                    location: qso.theirLoc,
                    target: .station,
                    park: qso.theirPotaRefs?.first ?? ""
                )
            }
        )
        // Whatever the history table takes, the log table gives back, so the
        // pane's minimum content height — and the window — never moves.
        .frame(minHeight: WorkedBeforeTable.logTableMin(tableHeight: workedBeforeHeight))
    }

    private func onDisappear() {
        pauseRepeat()
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = mediaKeyMonitor {
            NSEvent.removeMonitor(monitor)
            mediaKeyMonitor = nil
        }
        spotPurgeTask?.cancel()
        spotPurgeTask = nil
        spotClient.disconnect()
        bandMapBolt?.close()
        bandMapBolt = nil
        bandMapPanel?.close()
        bandMapPanel = nil
        // Not `disconnect()`: the radio is the app's, and another window may
        // still be logging on it. The last window out releases the port.
        radio.windowDidClose()
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
            } else if let contest = flow.standaloneContest {
                // A v2-only contest (POTA) has no PartyDefinition on
                // purpose; its name belongs here, not a warning.
                Text(contest.name)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Label("Contest '\(document.log.partyID)' not found", systemImage: "exclamationmark.triangle.fill")
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

            if SpottingPolicy.isVisible(
                conflict: document.log.spotsContradictNonAssistedClaim,
                dismissed: spotWarningDismissed
            ) {
                HStack(spacing: 5) {
                    Label(SpottingPolicy.badge, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.bold))
                    Button {
                        spotWarningDismissed = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(".", modifiers: .command)
                    .accessibilityLabel("Dismiss assisted-category warning")
                    .help("Dismiss for this sitting (⌘.) — it returns at Cabrillo export")
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.2), in: Capsule())
                .foregroundStyle(.orange)
                .help(SpottingPolicy.detail)
            }

            spotReceiptCapsule

            Spacer()

            // The total, while the sidebar that normally carries it is hidden.
            if scoreSidebarHidden {
                Text("\(score.total.formatted()) pts")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .help("Claimed score — the sidebar is hidden; ⌃⌘S shows it")
            }

            Text("\(currentBand.rawValue) \(currentRawMode)")
                .font(.callout.monospaced().weight(.semibold))

            Button("Setup…") { showSetup = true }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// What became of the last spot — a state per network, live — beside the
    /// other notices. Its own view, so the strip's expression grows by one
    /// name; every string and rule is `SpotReceipt`'s.
    @ViewBuilder
    private var spotReceiptCapsule: some View {
        if let receipt = spotDispatcher.receipt {
            SpotReceiptView(
                receipt: receipt,
                onRetry: retryFailedSpotNetworks,
                onDismiss: { spotDispatcher.dismiss() }
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            // One export affordance, two formats. The shortcuts on the items
            // are the menu's badge text — the keystrokes themselves are
            // handled by the key monitor (KeyMonitorGate), which consumes
            // them first wherever document focus rules allow an export.
            Menu {
                Button("ADIF (.adi)…") { exportADIF() }
                    .keyboardShortcut("e", modifiers: .command)
                if cabrilloOffered {
                    Button("Cabrillo (.log)…") { exportCabrillo() }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                }
                if !AdifExporter.ownParks(log: document.log).isEmpty {
                    Button("For POTA — one file per park…") { exportPota() }
                        .keyboardShortcut("e", modifiers: [.command, .option])
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export the log — ADIF (⌘E), Cabrillo (⇧⌘E), or POTA files (⌥⌘E)")
            .shortcutHint("⌘E · ⇧⌘E · ⌥⌘E")

            Button {
                beginSpotForMode()
            } label: {
                Label(spotCommandLabel, systemImage: spotCommandIcon)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!canSpotNow)
            .help(spotCommandHelp)
            .shortcutHint("⇧⌘S")

            Button {
                messagesEditorClass = .cw
                messagesEditorSlot = nil
                showMessagesEditor = true
            } label: {
                Label("Messages", systemImage: "keyboard")
            }
            .help("F-key messages — CW text, and phone recordings made here (⇧⌘V opens the Phone tab)")
            .shortcutHint("⇧⌘V phone")
            // Article 7 — the Phone tab's keyboard path. An invisible button
            // carries the shortcut, the pattern the Run/S&P toggle uses.
            .background {
                Button("Voice Messages") {
                    messagesEditorClass = .phone
                    messagesEditorSlot = nil
                    showMessagesEditor = true
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .opacity(0)
                .accessibilityHidden(true)
            }

            Button {
                toggleBandMap()
            } label: {
                Label("Band Map", systemImage: "ruler")
            }
            .help("Band map — spots by frequency with the VFO marker (⌘B)")
            .shortcutHint("⌘B")

            Button {
                scoreSidebarHidden.toggle()
            } label: {
                Label("Score", systemImage: "sidebar.trailing")
                    .foregroundStyle(scoreSidebarHidden ? .secondary : .primary)
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
            .help(scoreSidebarHidden
                  ? "Show the score sidebar (⌃⌘S)"
                  : "Hide the score sidebar (⌃⌘S) — the window can then shrink to half a display, and the strip shows the total")
            .shortcutHint("⌃⌘S")

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
            .help("DX cluster connection for spots — click a spot to tune, ⌘↑ / ⌘↓ to step")
            .popover(isPresented: $showClusterPopover) {
                clusterPopover
            }

            Button {
                showLookupPopover.toggle()
            } label: {
                Label("Lookup", systemImage: "person.text.rectangle")
            }
            .help("Callsign lookup — QRZ and HamQTH credentials. Advisory only; a lookup never fills an exchange field")
            .popover(isPresented: $showLookupPopover) {
                CallbookSettingsPane(client: callbookClient)
            }

            Menu {
                if let path = CloudMirror.folderDisplayPath {
                    Text(path)
                }
                Button(CloudMirror.isConfigured ? "Change iCloud Folder…" : "Choose iCloud Folder…") {
                    // The recordings and the message sets follow the folder:
                    // reload moves this Mac's recordings into it and reads
                    // from there, and the messages go the same way.
                    if CloudMirror.chooseFolder() {
                        voiceStore.reload()
                        adoptMessageSetsIntoCloudFolder()
                    }
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

            // The block is stated where the connect controls are, so a
            // switched-off Connect button is never a mystery.
            if !spottingAllowed {
                Label(SpottingPolicy.blockedReason, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 250, alignment: .leading)
            }

            Text("Spot filters (continent, mode, band, age) live in the band map window — ⌘B.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 250, alignment: .leading)

            HStack(spacing: 8) {
                if spotClient.status == .disconnected {
                    Button("Connect") { connectCluster() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!spottingAllowed)
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
            Text("Logs in with your callsign. Spots for the current band appear in the sidebar and band map — click to tune, ⌘↑ / ⌘↓ to step through them.")
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

    /// Whether this entry's declared category permits incoming spots at all.
    private var spottingAllowed: Bool {
        SpottingPolicy.allowsIncomingSpots(document.log.station.categoryAssisted)
    }

    /// Make the world match the declared category: no feeds, and no spots
    /// left on the map from before the declaration. Runs whenever the claim
    /// changes, so a mid-contest switch to NON-ASSISTED takes effect at once
    /// rather than at the next launch.
    private func enforceSpottingPolicy() {
        guard !spottingAllowed else {
            syncHubSpotClient()  // back to ASSISTED: the hub may resume
            syncPotaBoardClient()  // and the board with it
            return
        }
        spotClient.disconnect()
        hubSpotClient.stop()
        spotStore.removeNetworkSpots()
        // The claim governs contest assistance; POTA itself has no assisted
        // category, so a POTA log's board feed survives the sweep (the sync
        // stops it in party logs, where the claim does apply) and its rows
        // come straight back rather than flapping until the next poll.
        syncPotaBoardClient()
        if potaBoardClient.isPolling {
            spotStore.replace(source: .pota, with: potaBoardClient.spots)
        }
    }

    private func connectCluster() {
        // The one gate every path funnels through — the button, the Recent
        // Clusters menu, and auto-connect all land here.
        guard spottingAllowed else { return }
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
        // The per-party message memory, before Contest Setup can read it: a
        // new Skeeter Hunt log starts from last year's Skeeter Hunt messages
        // — from the iCloud logs folder when one is chosen, so the other Macs
        // start from the same set.
        document.messageMemory = .standard
        adoptMessageSetsIntoCloudFolder()
        // New (or never-configured) contests go straight to Contest Setup.
        if !document.log.setupCompleted {
            showSetup = true
        }
        focusedField = .call
        flow.onAppear(operatingContext)
        installKeyMonitor()
        // The party's recordings load and render off the main actor; the
        // `onChange` on `rendered` hands them to the flow when they land.
        voiceStore.partyID = document.log.partyID
        // Counted in first: a window that finds the radio already up is
        // counted like the one that brought it up, and `autoConnect` is a
        // no-op on a live link.
        radio.windowDidOpen()
        radio.autoConnect(settings: settings)

        // A spot can only get this far under an ASSISTED declaration, so the
        // record is of assistance legitimately taken — and it is what makes a
        // later switch to NON-ASSISTED visible, since prevention cannot reach
        // backwards into contacts already made.
        spotClient.onSpot = { spot in
            spotStore.add(spot)
            document.noteSpotsUsed()
            // Our own spot coming back is the node's proof of receipt.
            spotDispatcher.noteIncomingSpot(spot)
        }
        // Hub spots land in the same store, so the band map, filters, stacking
        // and ⌘↑/⌘↓ treat them exactly like any other spot — including the
        // assisted-category record.
        hubSpotClient.onSpots = { spots in
            for spot in spots { spotStore.add(spot) }
            if !spots.isEmpty { document.noteSpotsUsed() }
        }
        // An activator hunting me is on the board; typing his call brings
        // his park along (operator report 2, 2026-08-25). The store keeps
        // only the current board — a row gone from the feed answers nil.
        flow.parkOnBoard = { [weak spotStore] call in
            spotStore?.all.last {
                $0.source == .pota && $0.call == call.uppercased()
            }?.park
        }
        wireSpotDispatcher()
        syncHubSpotClient()
        syncPotaBoardClient()
        // The download may land after the operator has moved to another
        // party; the tag check keeps a late file from leaking into it.
        callHistoryClient.onIndex = { [weak flow] partyID, parsed in
            guard let flow, flow.party?.id == partyID else { return }
            flow.callHistoryIndex = (partyID, parsed)
            bandMapModel?.callHistory = parsed
        }
        scpClient.onDatabase = { [weak flow] database in
            flow?.updateSCPDatabase(database)
        }
        activateCallHistory()
        activateSuperCheck()
        checkDXCCLabels()
        checkSpaceWeather()
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
        loadArchiveIndex()

        if bandMapModel == nil {
            let model = BandMapModel(radio: radio, spotStore: spotStore, settings: settings)
            model.band = currentBand
            model.workedCalls = workedCallsOnCurrentBandMode
            model.partyBands = party?.validBands ?? Band.allCases
            model.allowedModes = party?.allowedModeClasses ?? []
            model.workedCallCounties = workedCallCountiesOnCurrentBandMode
            model.party = party
            model.log = document.log
            model.archiveIndex = flow.archiveIndex
            model.callHistory = flow.callHistoryIndex?.parsed
            model.onTuneSpot = { tune(to: $0) }
            model.onTuneKHz = { qsyTo(kHz: $0) }
            model.canSpot = canSpotStation
            model.onSpotStation = { spot in
                // A spot names no park, but the log may: a station worked
                // park-to-park earlier is offered to POTA with that park.
                let park = document.log.qsos.last { $0.call == spot.call }?.theirPotaRefs?.first
                beginSpot(
                    station: spot.call,
                    frequencyKHz: spot.freqKHz,
                    location: spot.county,
                    target: .station,
                    park: park ?? ""
                )
            }
            bandMapModel = model
        }
    }

    /// Serve the active party's cached call history at once, then let the
    /// client consult the listing in the background. Runs at appear, at party
    /// change, and when the toggle flips — and clears the index first, so a
    /// disabled toggle or a party with no file stops the offers immediately.
    private func activateCallHistory() {
        flow.callHistoryIndex = nil
        bandMapModel?.callHistory = nil
        guard settings.callHistoryEnabled,
              let party, party.callHistory != nil else { return }
        callHistoryClient.publishCached(party: party)
        Task { await callHistoryClient.refreshIfStale(party: party) }
    }

    /// Serve the cached MASTER.SCP at once, then let the client consult
    /// the server in the background — at appear, at contest load, and when
    /// the toggle flips. Clearing first is what stops the strip
    /// immediately when the option goes off. The client's daily throttle
    /// is what makes the triggers free (see `checkDXCCLabels`).
    private func activateSuperCheck() {
        flow.updateSCPDatabase(nil)
        guard settings.superCheckEnabled else { return }
        scpClient.publishCached()
        Task { await scpClient.refreshIfStale() }
    }

    /// Ask AD1C whether the DX multiplier labels have moved. Runs at launch
    /// and at every contest load; the client's own daily throttle is what
    /// makes calling it that often free, so opening six logs in an afternoon
    /// still makes at most one request.
    ///
    /// Detached and silent: this is a HEAD request comparing one date, it
    /// cannot change a score, and nothing about it may reach the entry path.
    /// A newer file takes effect at the next launch rather than mid-contest.
    private func checkDXCCLabels() {
        Task { await dxccLabelClient.refreshIfStale() }
    }

    /// Ask SWPC what the sun is doing. Hourly at most, cached to disk, and
    /// quiet in every failure mode: with no reading the advisor's propagation
    /// weights are identity and it runs on geometry alone, exactly as it would
    /// with no network at all.
    private func checkSpaceWeather() {
        guard settings.advisorEnabled else { return }
        Task { await spaceWeatherClient.refreshIfStale() }
    }

    /// Previous contests — the `.qplog` files in the logs folder — read once
    /// and indexed by call: what a prefill falls back on when this log has
    /// never worked the station. Off the main actor because that is every
    /// QSO of every contest ever logged, and a failure is silent: this is a
    /// convenience, not a correctness path. No logs folder chosen, no memory.
    private func loadArchiveIndex() {
        Task {
            let index = await Task.detached(priority: .userInitiated) {
                () -> StationMemory.Index in
                guard let folder = CloudMirror.activeFolder(),
                      let archive = try? LogFolder(url: folder).history().archive else {
                    return .empty
                }
                var counties: [String: Set<String>] = [:]
                for id in Set(archive.records.map(\.partyID)) {
                    counties[id] = Set(
                        PartyCatalog.party(id: id)?.counties.map(\.abbr) ?? []
                    )
                }
                return StationMemory.Index.build(archive, countiesByParty: counties)
            }.value
            flow.archiveIndex = index
            bandMapModel?.archiveIndex = index
        }
    }

    // MARK: Band map panel

    /// ⌘B: show the map, or hide it.
    private func toggleBandMap() {
        if let panel = bandMapPanel, panel.isVisible {
            bandMapBolt?.hide()
        } else {
            showBandMap()
        }
    }

    /// The map on screen — opened beside this window the first time, and
    /// bolted to it if the setting says so.
    private func showBandMap() {
        if let bolt = bandMapBolt {
            bolt.show()
            return
        }
        guard let model = bandMapModel, let host = hostWindow else { return }
        let panel = BandMapPanel.make(model: model, near: host)
        let bolt = BandMapBolt.Attachment(panel: panel, host: host)
        bandMapPanel = panel
        bandMapBolt = bolt
        bolt.apply(bolted: settings.bandMapBolted, side: settings.bandMapBoltSide)
        bolt.show()
    }

    /// The bolt settings, applied to the open map — on every change of
    /// either, and from ⇧⌘B.
    private func applyBandMapBolt() {
        bandMapBolt?.apply(bolted: settings.bandMapBolted, side: settings.bandMapBoltSide)
    }

    /// ⇧⌘B: bolt the map to the side of this window — opening it if it is
    /// closed or hidden, since a bolt with nothing on it is not a result —
    /// or set it free.
    private func toggleBandMapBolt() {
        settings.bandMapBolted.toggle()
        applyBandMapBolt()
        if settings.bandMapBolted, !(bandMapPanel?.isVisible ?? false) {
            showBandMap()
        }
    }

    /// Mode changes (radio or manual): swap pre-filled RST defaults
    /// (599 ↔ 59) and re-check validation/dupes for the new mode.
    private func modeChanged() {
        // A repeat started on CW must not keep running after a switch to phone,
        // where F1 means a different recording or text. The mode stays armed.
        interruptRepeat(.modeClassChanged)
        flow.modeChanged(operatingContext)
    }

    /// Return key. The flow decides what happens and what goes on the air; this
    /// only carries the decision out to the radio, the focus ring and the setup
    /// sheet. Nothing here may re-resolve a message — resolution order is
    /// exactly what the flow exists to pin down.
    private func returnPressed() {
        apply(flow.returnPressed(operatingContext, undoManager: undoManager))
    }

    private func apply(_ outcome: EntryFlow.Outcome) {
        switch outcome {
        case .qsy(let command):
            execute(command)
        case .send(let index, let transmission):
            sent(transmission, fromMessageAt: index)
        case .logged(let rows, let transmission):
            addWorkedStationsToBandMap(rows)
            focusedField = .call
            transmit(transmission)
        case .needsSetup:
            showSetup = true
        case .nothing:
            break
        }
    }

    /// An F-key, its button, or ESM's Return, resolved. F1 in Run is the CQ:
    /// it remembers the run frequency, and while Repeat CQ is armed it starts
    /// the loop (again) rather than sending once — the keystroke that paused
    /// the loop to work a caller left the mode on, and this is what N1MM's
    /// "press F1, Repeat CQ will resume" means (`RepeatCQPolicy`).
    private func sent(_ transmission: EntryFlow.Transmission, fromMessageAt index: Int) {
        if operatingMode.wrappedValue == .run, index == 0 {
            captureCQFrequency()
        }
        switch RepeatCQPolicy.onSend(index: index, operatingMode: operatingMode.wrappedValue, armed: repeatCQ) {
        case .restartLoop:
            restartRepeat(sending: transmission)
        case .sendOnce:
            transmit(transmission)
        }
    }

    /// The one place a resolved transmission reaches the radio. Nothing here
    /// may re-resolve a message — resolution order is exactly what the flow
    /// exists to pin down.
    private func transmit(_ transmission: EntryFlow.Transmission) {
        switch transmission {
        case .cw(let text):
            radio.sendCW(text, settings: settings)
        case .voice(let memory, let caption):
            radio.playVoiceMessage(memory: memory, caption: caption)
        case .recording(_, let audio, let caption):
            radio.playRecording(audio, caption: caption, settings: settings)
        case .silent:
            break
        }
    }

    /// The editor's ⇢ Radio button: memory N to the radio, exactly as an
    /// F-key mapped to it would — the same rendered clip, the same path.
    private func playRecordingToRadio(memory: Int) {
        guard let audio = voiceStore.rendered[memory] else { return }
        radio.playRecording(audio, caption: document.log.messages.voiceMemoryCaption(memory), settings: settings)
    }

    /// A station nobody spotted leaves nothing on the band map: work him, and
    /// ten minutes later his frequency reads as empty. So the log feeds the
    /// map too — one spot per contact, only where nobody has spotted him
    /// already, and only when the radio gave us a frequency to put him on.
    /// It arrives worked, so it draws struck-through and ⌘↑/⌘↓ steps over it.
    ///
    /// Searching only. Running, the mode is passed in and `WorkedSpot` returns
    /// nothing — see there for why a run frequency is the one that needs no
    /// marking.
    private func addWorkedStationsToBandMap(_ rows: [QSO]) {
        for spot in WorkedSpot.spots(for: rows, myCall: document.log.station.callsign,
                                     mode: operatingMode.wrappedValue) {
            spotStore.addIfAbsent(spot)
        }
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
        let transmission = flow.transmission(at: index, context: operatingContext)
        guard transmission != .silent else { return }
        sent(transmission, fromMessageAt: index)
    }

    /// Open the Messages editor on one F-key — from ⌥F1–⌥F8, or from that
    /// button's own right-click menu. The tab follows the mode being operated,
    /// because that is the message the key would actually send: CW text on CW,
    /// the recording or memory it fires on phone.
    private func editMessageAt(_ index: Int) {
        messagesEditorClass = currentModeClass == .phone ? .phone : .cw
        messagesEditorSlot = index
        showMessagesEditor = true
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
    /// click, a typed QSY, ⌘↑/⌘↓, ⌘J, a click on empty map. Frequency changes
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
        // Not a plain assignment: arriving at a station takes whatever was
        // copied for the last one off the row and keeps it under his call.
        //
        // Only a hub spot names a county, and only as a third party's claim,
        // so it goes in as the weakest candidate — behind anything copied for
        // this station and anything worked before.
        flow.stationChanged(
            to: spot.call,
            operatingContext,
            spotCounty: settings.prefillExchangeFromSpots ? spot.county : nil,
            atKHz: spot.freqKHz
        )
        // A POTA spot names the activator's park; it lands in an empty
        // their-park field the way a previously-given park does — typed
        // text is never overwritten (spec 2026-08-25 decision 3).
        if let park = spot.park, entry.theirParkTyped.isEmpty {
            entry.theirParkTyped = park
        }
        focusedField = .call
    }

    // MARK: Spotting — one sheet, every network

    /// What the availability rules need to know right now. `draftPark` is the
    /// one half that changes while the sheet is open, so the sheet supplies
    /// it live; everything else is read from the clients and the log.
    private func spotContext(
        target: SpotNetworkAvailability.Target, draftPark: String
    ) -> SpotNetworkAvailability.Context {
        SpotNetworkAvailability.Context(
            clusterConnected: spotClient.status == .connected,
            clusterHost: settings.clusterHost,
            clusterBlockedReason: spottingAllowed ? nil : SpottingPolicy.blockedReason,
            hubHost: party?.hubSpots.flatMap { URL(string: $0.postURL)?.host },
            target: target,
            myParks: document.log.myPotaRefs,
            draftPark: draftPark
        )
    }

    /// Whether spotting is possible at all: a party to spot in, a callsign to
    /// post under, and — for whichever target ⇧⌘S means right now — somewhere
    /// to send. For another station the sheet opens even with nothing on
    /// offer yet, because typing their park is the way onto POTA.
    private func canSpot(target: SpotNetworkAvailability.Target) -> Bool {
        party != nil && !document.log.station.callsign.isEmpty
            && SpotNetworkAvailability.canOpenSheet(in: spotContext(target: target, draftPark: ""))
    }

    /// The gate for the band map's and the log's right-click — always another
    /// station.
    private var canSpotStation: Bool { canSpot(target: .station) }

    /// The gate for ⇧⌘S and its toolbar button — whoever the mode says.
    private var canSpotNow: Bool {
        canSpot(target: spotCommand == .myself ? .myself : .station)
    }

    /// The transports the dispatcher fans a spot out through: the open node
    /// session, the hub client, the POTA client — and their reports back.
    /// Wired once the clients exist, in `onAppear`.
    private func wireSpotDispatcher() {
        spotDispatcher.transports = SpotDispatcher.Transports(
            sendClusterCommand: { command in
                guard spotClient.status == .connected else { return false }
                spotClient.send(command)
                return true
            },
            postToHub: { fields, party in
                guard let source = party.hubSpots else { return }
                Task { await hubSpotClient.post(fields, source: source, party: party) }
            },
            postToPota: { fields in
                Task { await potaSpotClient.post(fields) }
            }
        )
        hubSpotClient.onSendStateChange = { spotDispatcher.update(.hub, state: $0) }
        potaSpotClient.onSendStateChange = { spotDispatcher.update(.pota, state: $0) }
    }

    /// The receipt's Retry: the same draft again, only the failed network(s)
    /// ticked — and the sheet again, because every send is confirmed.
    private func retryFailedSpotNetworks() {
        guard let receipt = spotDispatcher.receipt, party != nil else { return }
        spotDraft.networks = Set(receipt.failedNetworks)
        showSpotSheet = true
    }

    /// What ⇧⌘S means right now — running advertises you, searching puts the
    /// station you found on the board.
    private var spotCommand: SpotCommand {
        SpotCommand.target(mode: document.log.operatingMode, entryCall: entry.callNormalized)
    }

    /// The button says which one it is before it is pressed. A command that
    /// changes meaning has to show it, or it is the same trap as two shortcuts
    /// a modifier apart.
    private var spotCommandLabel: String {
        spotCommand == .myself ? "Spot Myself" : "Spot Station"
    }

    private var spotCommandIcon: String {
        spotCommand == .myself ? "dot.radiowaves.left.and.right" : "dot.radiowaves.right"
    }

    private var spotCommandHelp: String {
        guard canSpotNow else {
            return "Nothing to spot to yet — connect a cluster node, pick a party with a "
                + "QSO Party Hub page, or set your park in Contest Setup; and set your callsign"
        }
        let what = switch spotCommand {
        case .myself: "Spot yourself (⇧⌘S)"
        case .station(let call): "Spot \(call) (⇧⌘S)"
        case .blankStation: "Spot a station (⇧⌘S) — type the call in the sheet"
        }
        return what + " — to the DX cluster, the QSO Party Hub and POTA, whichever apply, "
            + "confirmed before it sends. Or right-click any spot on the band map, or any "
            + "row in the log."
    }

    /// Where the radio is, to 10 Hz — finer than that is noise on a spot, and
    /// the hub's frequency field only accepts ten characters. `nil` with no
    /// radio: the sheet would rather show an empty field than a guess.
    private var vfoKHzForSpotting: Double? {
        radio.radioState.map { (Double($0.frequencyHz) / 10).rounded() / 100 }
    }

    /// ⇧⌘S — the only spot shortcut, and the operating mode decides who it
    /// means. Searching takes the county out of the exchange as copied so far,
    /// and only if it really is one of this party's counties — and the park
    /// out of the P2P field, for a station that gave one.
    private func beginSpotForMode() {
        switch spotCommand {
        case .myself:
            beginSelfSpot()
        case .station(let call):
            beginSpot(
                station: call,
                frequencyKHz: vfoKHzForSpotting,
                location: entry.exchange,
                target: .station,
                park: entry.theirParkTyped
            )
        case .blankStation:
            // Heard a call and reached for the command before typing it. The
            // sheet opens on the empty station field, the way it already opens
            // on an empty frequency, and validation holds the send.
            beginSpot(station: "", frequencyKHz: vfoKHzForSpotting, location: nil,
                      target: .station, park: "")
        }
    }

    /// Open the spot sheet — for you, or for a station from the band map, the
    /// log, or the entry field. It still only opens the sheet: every send is
    /// confirmed, because every network takes what it is given, publicly and
    /// at once.
    ///
    /// The county prefill is `HubSpotPrefill`'s, so its rules hold once for
    /// every network: an out-of-state location is not offered as a county, a
    /// county line is offered whole, and no radio means a blank frequency the
    /// sheet holds rather than a band default posted publicly as fact. The
    /// networks open ticked are the ones on offer that were ticked last time.
    private func beginSpot(
        station: String, frequencyKHz: Double?, location: String?,
        target: SpotNetworkAvailability.Target, park: String
    ) {
        guard canSpot(target: target), let party else { return }
        let hub = HubSpotPrefill.fields(
            station: station,
            frequencyKHz: frequencyKHz,
            location: location,
            poster: document.log.station.callsign,
            party: party
        )
        let context = spotContext(target: target, draftPark: park)
        spotTarget = target
        spotDraft = SpotDraft(
            station: hub.station,
            frequencyKHz: hub.frequencyKHz,
            county: hub.county,
            comment: "",
            poster: hub.poster,
            park: park,
            mode: AdifExporter.adifMode(currentRawMode),
            networks: SpotNetwork.initialSelection(
                available: SpotNetworkAvailability.available(in: context),
                preferred: settings.spotNetworks
            )
        )
        showSpotSheet = true
    }

    /// Open the sheet for yourself, pre-filled from live state.
    ///
    /// Everything here is already known — the call from the station profile,
    /// the frequency from the radio, the counties from the log, the park from
    /// Contest Setup — and retyping it mid-run is exactly why operators stop
    /// self-spotting.
    private func beginSelfSpot() {
        beginSpot(
            station: document.log.station.callsign,
            frequencyKHz: vfoKHzForSpotting,
            location: HubSpotPrefill.ownCounty(document.log.myLocation),
            target: .myself,
            park: document.log.myPotaRefs.first ?? ""
        )
    }

    /// Prompt a rover to re-spot when it changes county. A mobile has to
    /// re-spot on every county change, and the app knows the exact moment it
    /// happens — but it still only opens the sheet, never posts by itself.
    private func offerReSpotOnCountyChange() {
        // Only an in-state operator has a county to re-spot from — an
        // out-of-state entrant's "location" is a state, which is not a token
        // the hub's form would accept.
        //
        // Never while Contest Setup is open. That sheet is where the county
        // gets edited, so this fires mid-edit, and a second sheet over the
        // first is either dropped or lands on a half-finished change. The
        // county is deliberately *not* recorded in that case, so the change is
        // still pending when Setup closes and the offer follows then.
        //
        // Compared whole, not by first county: a line moving MDSN/LIME to
        // MDSN/LAWR changes in the second position only, and that is just as
        // much a county change to re-spot for.
        guard !showSetup else { return }
        guard canSpot(target: .myself), settings.hubSpotsEnabled,
              let county = HubSpotPrefill.ownCounty(document.log.myLocation),
              let previous = lastSelfSpotCounty, previous != county
        else {
            lastSelfSpotCounty = HubSpotPrefill.ownCounty(document.log.myLocation)
            return
        }
        lastSelfSpotCounty = county
        beginSelfSpot()
    }

    /// Start, restart or stop hub polling to match the setting and the party.
    /// Two of the nineteen bundled parties have no hub page at all, so this
    /// quietly does nothing for them rather than polling a dead URL.
    private func syncHubSpotClient() {
        guard SpottingPolicy.hubShouldPoll(
            enabled: settings.hubSpotsEnabled,
            hasSource: party?.hubSpots != nil,
            claim: document.log.station.categoryAssisted
        ), let party, let source = party.hubSpots else {
            hubSpotClient.stop()
            return
        }
        hubSpotClient.start(source: source, party: party)
    }

    private func syncPotaBoardClient() {
        if SpottingPolicy.potaShouldPoll(
            isPotaProgramLog: flow.standaloneContest?.potaProgram == true,
            partyOptIn: settings.potaSpotsInParties,
            claim: document.log.station.categoryAssisted
        ) {
            potaBoardClient.start()
        } else {
            potaBoardClient.stop()
        }
    }

    /// ⌘↑ / ⌘↓. Worked stations stay on the band map, greyed, but
    /// there is nothing left to work on them so the keys step over them.
    ///
    /// A spot reporting a county is judged on call+county, so a rover that has
    /// moved comes back into the rotation.
    private func jumpToSpot(_ direction: SpotStore.Direction) {
        let bandSpots = visibleSpotsOnBand
        let reference = radio.radioState.map { Double($0.frequencyHz) / 1000 }
            ?? spotCursorKHz
            ?? Double(currentBand.defaultFreqKHz)
        guard let spot = SpotStore.next(
            in: bandSpots,
            afterKHz: reference,
            direction: direction,
            workedCalls: workedCallsOnCurrentBandMode,
            workedCallCounties: workedCallCountiesOnCurrentBandMode
        ) else {
            return
        }
        tune(to: spot)
    }

    // MARK: CQ frequency memory

    private func captureCQFrequency() {
        if let hz = radio.radioState?.frequencyHz {
            cqFrequencyHz = hz
            // Captured at the VFO, so by definition on it — even when the
            // frequency is the same one as before and no `onChange` fires.
            cqZone = .onFrequency
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

    // MARK: Following the knob — Run ⇄ S&P, and the call frame

    /// Every frequency the radio reports. The zone check runs first so a turn
    /// that leaves Run can seed the call frame in the same pass.
    private func vfoMoved() {
        guard let hz = radio.radioState?.frequencyHz else {
            cqZone = nil
            flow.updateCallFrame(nil)
            return
        }
        followCQFrequency(vfoHz: hz)
        followSpots(vfoHz: hz)
    }

    /// N1MM: on the CQ frequency you are in Run and QSYing switches to S&P;
    /// tuning back within tolerance switches to Run. `TuningPolicy` decides,
    /// edge-triggered, so ⌘R is never fought.
    private func followCQFrequency(vfoHz: Int) {
        guard let cq = cqFrequencyHz else {
            cqZone = nil
            return
        }
        let zone = TuningPolicy.zone(
            vfoHz: vfoHz, cqHz: cq,
            toleranceHz: settings.tuningToleranceHz.hz(for: currentModeClass),
            leaveHz: settings.leaveRunDistanceHz.hz(for: currentModeClass)
        )
        if let mode = TuningPolicy.modeChange(
            from: cqZone, to: zone, mode: operatingMode.wrappedValue,
            leaveEnabled: settings.autoLeaveRun, returnEnabled: settings.autoReturnToRun
        ) {
            operatingMode.wrappedValue = mode
        }
        cqZone = zone
    }

    /// The call frame: searching, the nearest visible spot within the tuning
    /// tolerance — the list ⌘↑/⌘↓ step through, so a hidden worked station
    /// never ghosts. First the erase rule for a call the app filled earlier,
    /// then the frame for wherever the VFO is now.
    private func followSpots(vfoHz: Int) {
        guard settings.callFrameEnabled, operatingMode.wrappedValue == .searchPounce else {
            flow.updateCallFrame(nil)
            return
        }
        let vfoKHz = Double(vfoHz) / 1000
        let toleranceHz = settings.tuningToleranceHz.hz(for: currentModeClass)
        flow.tunedAway(toKHz: vfoKHz, toleranceKHz: Double(toleranceHz) / 1000, operatingContext)
        flow.updateCallFrame(SpotStore.nearest(
            in: visibleSpotsOnBand,
            toKHz: vfoKHz,
            withinHz: toleranceHz,
            workedCalls: workedCallsOnCurrentBandMode,
            workedCallCounties: workedCallCountiesOnCurrentBandMode
        ))
    }

    /// Recompute the frame from where the radio is now — after the option or
    /// the mode changes rather than the VFO.
    private func refreshCallFrame() {
        guard let hz = radio.radioState?.frequencyHz else {
            flow.updateCallFrame(nil)
            return
        }
        followSpots(vfoHz: hz)
    }

    private func operatingModeChanged() {
        if !RepeatCQPolicy.continues(in: operatingMode.wrappedValue) {
            interruptRepeat(.leftRun)
        }
        refreshCallFrame()
    }

    /// Space in the empty call field, with a ghost showing.
    private func takeCallFrame() {
        guard flow.takeCallFrame(operatingContext) else { return }
        focusedField = .call
    }

    /// The ghost call's colour — the band map's colour for that spot.
    private var callFrameColor: Color {
        entry.callFrame.flatMap { bandMapModel?.status(for: $0) }?.color ?? .secondary
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

    /// Repeat CQ is a mode (the toggle) with a loop running inside it (the
    /// task). Three things happen to it, and they are kept apart on purpose:
    ///
    /// - **arm** (the toggle on): the mode is on and nothing goes on the air.
    ///   F1, the CQ button, or ESM's Return start the loop.
    /// - **pause** (`pauseRepeat`, `interruptRepeat`): the loop stops, the
    ///   mode stays armed. Any keystroke but a shortcut does this — the
    ///   operator has started answering someone — and so do leaving Run, a
    ///   CW ⇄ phone change and a disconnect. F1 starts it again.
    /// - **restart** (`restartRepeat`): the CQ comes off the air and the loop
    ///   starts over from the top, at once.
    ///
    /// Only the toggle itself turns the mode off. N1MM's Alt+R behaves this
    /// way (`RepeatCQPolicy`); until 2026-08-15 a keystroke here disengaged,
    /// so every QSO cost a click on the toggle, and until 2026-08-16 the
    /// toggle keyed a CQ on the click and every interruption disarmed it.
    private func repeatCQChanged() {
        switch RepeatCQPolicy.onToggle(armed: repeatCQ) {
        case .armOnly:
            break
        case .cancelLoop:
            pauseRepeat()
        }
    }

    /// The loop is running when the task is; the mode is armed when the
    /// toggle is. Paused is armed and not running — which is also the state
    /// right after arming, before F1.
    private var repeatPaused: Bool { repeatCQ && repeatTask == nil }

    private func pauseRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
    }

    /// Something other than the toggle took the loop down. The mode follows
    /// `RepeatCQPolicy` — it stays armed through all of them.
    private func interruptRepeat(_ interruption: RepeatCQPolicy.Interruption) {
        pauseRepeat()
        if !RepeatCQPolicy.staysArmed(through: interruption) { repeatCQ = false }
    }

    /// Whether the loop has a radio and a message path to run on: CW, or
    /// phone with the voice path ready.
    private var canRunRepeatLoop: Bool {
        radio.isConnected && (currentModeClass == .cw || (currentModeClass == .phone && phoneKeysEnabled))
    }

    /// F1 in Run while the mode is armed: the CQ comes off the air and the
    /// loop starts from the top, sending `transmission` first. When the loop
    /// cannot run — no radio, a phone path that is not ready — the CQ goes
    /// out once, as with the mode off, and the mode stays armed: never a
    /// silent disarm.
    private func restartRepeat(sending transmission: EntryFlow.Transmission) {
        pauseRepeat()
        radio.abortTransmission(settings: settings)
        guard canRunRepeatLoop, transmission != .silent else {
            transmit(transmission)
            return
        }
        repeatTask = Task {
            while !Task.isCancelled && repeatCQ {
                // Re-resolve each pass: the CW macros expand against live entry
                // state, and the mapping may have been edited between repeats.
                let outgoing = flow.transmission(at: 0, context: operatingContext)
                transmit(outgoing)
                await waitForEndOfTransmission(outgoing)
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(settings.repeatIntervalSeconds * 1_000_000_000))
                } catch {
                    break
                }
            }
        }
    }

    /// How long to hold before the next repeat. CW is estimated from the text
    /// and the speed; voice is not estimated at all — the radio reports when a
    /// message stops, which is exactly what other loggers cannot do for a
    /// radio's own recorder, and why their repeat interval has to be hand-tuned.
    private func waitForEndOfTransmission(_ transmission: EntryFlow.Transmission) async {
        switch transmission {
        case .cw(let text):
            let onAir = radio.estimatedSendDuration(text, settings: settings)
            try? await Task.sleep(nanoseconds: UInt64(onAir * 1_000_000_000))
        case .voice, .recording:
            await waitForVoicePlaybackToFinish()
        case .silent:
            break
        }
    }

    /// Wait for the radio to start, then finish, playing. Only the *start* half
    /// is bounded — 2 s, since `IC` is polled every 0.5 s and a short message
    /// can begin and end between polls, in which case this falls through to
    /// the repeat interval rather than wait for a start it already missed.
    ///
    /// The *finish* half has no deadline: it holds for as long as
    /// `radio.isVoicePlaying` keeps reading true, so a link that dies without
    /// the transport noticing would stall it. Accepted rather than closed
    /// because Esc, a disconnect, or a mode change all cancel the repeat task
    /// this runs under regardless of what the radio is reporting, and every
    /// iteration awaits 100 ms, so the wait sits at a light 10 Hz poll rather
    /// than busy-looping while it lasts.
    private func waitForVoicePlaybackToFinish() async {
        let startDeadline = Date().addingTimeInterval(2)
        while !radio.isVoicePlaying, Date() < startDeadline, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard radio.isVoicePlaying else { return }
        while radio.isVoicePlaying, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    // MARK: Message sets in the iCloud folder

    /// The iCloud logs folder is chosen (now, or before this launch): the
    /// message sets this Mac saved on its own follow it, once, the way the
    /// recordings do on `voiceStore.reload()`. Best effort — a failure leaves
    /// the local files for the next look and says so in the log; nothing on
    /// screen depends on it, since the sets are also in every log file.
    private func adoptMessageSetsIntoCloudFolder() {
        do {
            let moved = try MessageMemory.standard.adoptThisMacsSetsIfNeeded()
            if !moved.isEmpty {
                NSLog("MessageMemory: moved message sets to the iCloud folder: \(moved.joined(separator: ", "))")
            }
        } catch {
            NSLog("MessageMemory: could not move this Mac's message sets to the iCloud folder: \(error)")
        }
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
            adoptMessageSetsIntoCloudFolder()
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

    /// Every key the monitor rules on, and every media key it notices, goes to
    /// the unified log — `log show --predicate 'subsystem ==
    /// "org.b5n.QSOPartyLogger"' --last 10m` — so "the F-keys do nothing" can
    /// be read off the Mac that said it, key code and all.
    private static let keyLog = Logger(subsystem: "org.b5n.QSOPartyLogger", category: "keys")

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // The monitor is app-wide, and every rule — which window owns the
            // keystroke, what it does, whether it is swallowed — lives in
            // `KeyMonitorGate` where it can be tested. This closure reads the
            // window state, asks, and dispatches, in that order: the loop stops
            // and the transmitter comes down *before* the key's own action, so
            // F2 during a repeating CQ replaces the CQ instead of stacking
            // behind it.
            let command = event.modifierFlags.contains(.command)
            let shift = event.modifierFlags.contains(.shift)
            let option = event.modifierFlags.contains(.option)
            let focus = KeyMonitorGate.focus(currentWindows())
            let response = KeyMonitorGate.response(
                keyCode: event.keyCode,
                command: command,
                shift: shift,
                option: option,
                focus: focus,
                repeatRunning: repeatTask != nil
            )
            Self.keyLog.log("\(KeyDiagnostics.traceLine(keyCode: event.keyCode, command: command, shift: shift, option: option, focus: focus, response: response), privacy: .public)")
            if focus == .document {
                noteKeyDown(keyCode: event.keyCode, command: command, shift: shift,
                            option: option, action: response.action)
            }

            // A keystroke pauses the loop and leaves the mode armed — the
            // operator is answering someone; F1 will start it again.
            if response.stopsRepeat { pauseRepeat() }
            if response.abortsTransmission { radio.abortTransmission(settings: settings) }
            if let action = response.action { perform(action) }
            return response.consumesEvent ? nil : event
        }
        // Media keys are the system's; this only looks. An F row in
        // multimedia mode sends brightness where F1 should be, and the
        // operator deserves to be told rather than left pressing.
        mediaKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { event in
            guard let key = KeyDiagnostics.mediaKey(subtype: Int(event.subtype.rawValue), data1: event.data1),
                  KeyMonitorGate.focus(currentWindows()) == .document
            else { return event }
            Self.keyLog.log("media key \(key.name, privacy: .public) \(key.isDown ? "down" : "up", privacy: .public)")
            if let notice = KeyDiagnostics.fRowNotice(for: key) {
                fRowNotice = notice
                lastKeyReadout = "\(key.name) — a media key, not a function key"
            }
            return event
        }
    }

    /// The legend's last-key line, and the F-row notice's lifecycle: a system
    /// key on an F position raises it, any real function key clears it.
    private func noteKeyDown(keyCode: UInt16, command: Bool, shift: Bool, option: Bool,
                             action: KeyMonitorGate.Action?) {
        lastKeyReadout = KeyDiagnostics.lastKeyReadout(keyCode: keyCode, command: command,
                                                       shift: shift, option: option, action: action)
        if let notice = KeyDiagnostics.fRowNotice(forKeyCode: keyCode) {
            fRowNotice = notice
        } else if case .sendMessage = action {
            fRowNotice = nil
        } else if case .editMessage = action {
            // A real function key arrived, so the media-key notice is stale
            // whether it transmitted or opened the editor.
            fRowNotice = nil
        } else if action == .clearEntry {
            fRowNotice = nil
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
        // ⌘= / ⌘- (plus keypad variants): CW speed ±1 WPM; with ⇧, ±2.
        case .adjustWPM(let delta): adjustWPM(by: delta)
        // ⌘↓/⌘↑: previous/next spot on the band. ⌘J: back to CQ.
        case .previousSpot: jumpToSpot(.down)
        case .nextSpot: jumpToSpot(.up)
        case .jumpToCQFrequency: jumpToCQFrequency()
        case .toggleBandMap: toggleBandMap()
        case .toggleBandMapBolt: toggleBandMapBolt()
        case .sendMessage(let index): sendMessageAt(index)
        case .editMessage(let index): editMessageAt(index)
        case .clearEntry: clearEntry()
        // The gate hoists Esc into `Response.abortsTransmission` — which every
        // key does during a repeat — so this never arrives here. It keeps the
        // table exhaustive.
        case .abortTransmission: radio.abortTransmission(settings: settings)
        case .exportADIF: exportADIF()
        case .exportCabrillo: if cabrilloOffered { exportCabrillo() }
        case .exportPota: exportPota()
        // ⇧⌘← / ⇧⌘→: the VFO by 100 Hz.
        case .nudgeVFO(let hz): nudgeVFO(byHz: hz)
        // ⌘/: hints on every button, and the legend under the messages row.
        case .toggleShortcutHints: settings.showShortcutHints.toggle()
        }
    }

    /// The radio when there is one; otherwise the band-map cursor, which is
    /// the only VFO the app has while disconnected. Either way the spot
    /// cursor follows, so ⌘↑/⌘↓ step from where the radio now is. The band
    /// plan is left alone: 100 Hz never crosses a mode boundary on purpose.
    private func nudgeVFO(byHz hz: Int) {
        if let target = radio.nudgeFrequency(byHz: hz) {
            spotCursorKHz = Double(target) / 1000
        } else if !radio.isConnected {
            let base = spotCursorKHz ?? Double(currentBand.defaultFreqKHz)
            spotCursorKHz = base + Double(hz) / 1000
        }
    }

    // MARK: Export

    /// The log's file as the window knows it right now — `knownFileURL` alone
    /// can lag a Save As.
    private var exportFileURL: URL? {
        (hostWindow?.windowController?.document as? NSDocument)?.fileURL
            ?? document.knownFileURL
    }

    private func exportADIF() {
        let text: String
        if let party {
            text = AdifExporter.export(log: document.log, party: party)
        } else if let contest = flow.standaloneContest {
            text = AdifExporter.export(log: document.log, contest: contest)
        } else { return }
        // Through .plainText the save panel would append ".txt" — .adi is not
        // an extension of any plain-text type. .adi (LogDocument.swift) is.
        presentExport(
            TextExportDocument(text: text),
            type: .adi,
            name: LogDocument.exportBaseName(fileURL: exportFileURL, log: document.log) + ".adi"
        )
    }

    private func exportCabrillo() {
        // The claim ships here, so a standing conflict re-surfaces even if
        // dismissed earlier. The export itself proceeds untouched — the
        // warning is advice, and the file is never rewritten. ADIF (⌘E)
        // carries no CATEGORY-ASSISTED claim and does not re-arm.
        spotWarningDismissed = SpottingPolicy.rearm(
            dismissed: spotWarningDismissed,
            conflict: document.log.spotsContradictNonAssistedClaim
        )
        guard let party else { return }
        presentExport(
            TextExportDocument(
                text: CabrilloExporter.export(log: document.log, party: party, score: score)
            ),
            type: .plainText,
            name: LogDocument.exportBaseName(fileURL: exportFileURL, log: document.log) + ".log"
        )
    }

    /// One ADIF per own park, named CALL@PARK-YYYYMMDD.adi — "A separate log
    /// must be submitted for each park of the multi-park simultaneous
    /// activation" (docs/research/pota/SOURCES.md). The panel picks a folder
    /// once; Finder then shows what landed, which is the receipt.
    private func exportPota() {
        if let notice = AppIntegrity.check() {
            exportNotice = notice
            return
        }
        exportNotice = nil
        let parks = AdifExporter.ownParks(log: document.log)
        guard !parks.isEmpty else { return }
        let contest: ContestDefinition
        if let party { contest = PartyLowering.lowered(party) }
        else if let standalone = flow.standaloneContest { contest = standalone }
        else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export \(parks.count) File\(parks.count == 1 ? "" : "s")"
        panel.message = "One POTA submission file per park will be written here."
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        var written: [URL] = []
        for park in parks {
            let text = AdifExporter.exportForPota(log: document.log, contest: contest, park: park)
            let date = AdifExporter.firstQSODate(log: document.log, park: park) ?? Date()
            let url = folder.appendingPathComponent(
                AdifExporter.potaFileName(callsign: document.log.station.callsign,
                                          park: park, date: date))
            do {
                try Data(text.utf8).write(to: url)
                written.append(url)
            } catch {
                exportNotice = "Could not write \(url.lastPathComponent): \(error.localizedDescription)"
                return
            }
        }
        NSWorkspace.shared.activateFileViewerSelecting(written)
    }

    /// Open the save panel for an export — or say why it cannot open.
    ///
    /// The panel is a sandbox service that validates its caller, so a copy of
    /// the app that was rebuilt while running is refused: AppKit logs "Unable
    /// to display save panel", SwiftUI leaves `isPresented` up, and every
    /// later ⌘E is a no-op (2026-08-15). So: ask `AppIntegrity` first and put
    /// the answer on screen instead of trying; and when the flag is still up
    /// from a presentation that never completed, drop it and raise it again
    /// next turn, so a retry actually presents.
    private func presentExport(_ export: TextExportDocument, type: UTType, name: String) {
        if let notice = AppIntegrity.check() {
            exportNotice = notice
            return
        }
        exportNotice = nil
        exportDoc = export
        exportType = type
        exportName = name
        guard isExporting else {
            isExporting = true
            return
        }
        isExporting = false
        Task { @MainActor in isExporting = true }
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
    static var writableContentTypes: [UTType] { [.plainText, .adi] }
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
