import Foundation
import Observation

/// The keying-relevant slice of `AppSettings`, as a value.
///
/// A test is never handed a live `AppSettings`: every `didSet` writes
/// `UserDefaults.standard`, so flipping `cwCutNumbers` in a test would rewrite
/// the operator's real preferences.
struct KeyingSettings: Equatable, Sendable {
    var esmEnabled = false
    var cutNumbers = false
    var cutOne = false

    init(esmEnabled: Bool = false, cutNumbers: Bool = false, cutOne: Bool = false) {
        self.esmEnabled = esmEnabled
        self.cutNumbers = cutNumbers
        self.cutOne = cutOne
    }
}

extension AppSettings {
    /// One place for the view to build what the flow needs, so the two cannot
    /// drift apart over which preference drives which macro.
    var keying: KeyingSettings {
        KeyingSettings(
            esmEnabled: esmEnabled,
            cutNumbers: cwCutNumbers,
            cutOne: cwCutNumberOne
        )
    }
}

/// Everything that decides what the radio keys: the entry row, the document it
/// logs into, and the sequence the two move through on a Return.
///
/// Non-`View` on purpose. This code lived inside `MainView` until 2026-07-25,
/// where being private to a SwiftUI `View` put it out of reach of every test —
/// and two bugs that put both stations out of each other's logs shipped through
/// eight review rounds because deleting the QSO number from the air entirely
/// left the whole suite green. See
/// `docs/superpowers/specs/2026-07-25-keying-path-seam-design.md`.
///
/// The rule that makes it testable: **this type never transmits anything.** It
/// returns the `Transmission` it would put on the air — expanded CW text, or a
/// voice memory to play — and the caller hands that to the radio. A caller that
/// has to be handed the resolved transmission cannot send a different one,
/// which is what closes the ordering bug: resolving a message after logging
/// keys the *next* contact's number.
@MainActor
@Observable
final class EntryFlow {
    let entry: EntryState
    let document: LogDocument

    /// Previous contests, indexed by call. Empty until the load finishes, which
    /// costs nothing but a missed prefill in the first second of a contest.
    var archiveIndex = StationMemory.Index.empty

    /// The active party's N1MM call history file, when one is downloaded —
    /// tagged with the party it was parsed for, because the download lands
    /// asynchronously and the operator may have changed parties while it was
    /// in flight. A mismatched tag is simply not consulted.
    ///
    /// Its calls also feed the super check strip, so setting it re-sorts them
    /// once (`historyCalls`) and refreshes the strip for whatever fragment is
    /// already typed — the roster lands after the operator starts typing as
    /// often as before.
    var callHistoryIndex: (partyID: String, parsed: CallHistoryFile.Parsed)? {
        didSet {
            historyCalls = callHistoryIndex.map {
                ($0.partyID, $0.parsed.entriesByCall.keys.sorted())
            }
            scpFragment = nil
            refreshSCPMatches()
        }
    }

    /// The history file's calls, sorted once per download rather than per
    /// keystroke, under the party tag they belong to.
    @ObservationIgnored private var historyCalls: (partyID: String, calls: [String])?

    /// The active party's recordings on this Mac, memory number → rendered
    /// audio — set by the view from `VoiceStore`, like `callHistoryIndex`.
    /// Only read under `PhoneSource.recordings`.
    var voiceRecordings: [Int: VoiceAudio] = [:]

    /// The callbook's current answer, pushed by the window (the client is
    /// the window's; the flow only reads). Read at logging for the POTA
    /// stamp, and only when it matches the call being logged. Arrival is
    /// also a moment the State field may take an offer — the record lands
    /// asynchronously, well after the keystrokes that asked for it.
    var callbookRecord: CallbookRecord? {
        didSet { offerState() }
    }

    /// The single location a park reference sits in, as the park directory
    /// describes it ("US-ME") — the window wires this to the offline
    /// directory. Where they are sitting outranks where they live, so this
    /// is the State offer's first source (operator request, 2026-08-25).
    @ObservationIgnored var parkLocation: (String) -> String? = { _ in nil }

    /// The park field changed — typed, prefilled, or taken from the board.
    /// The park may now name the state.
    func theirParkEdited() {
        offerState()
    }

    /// Offer the State field its best guess, park first — where he is
    /// sitting right now — then what he sent me earlier this log, then the
    /// callbook's home state. Offers ride the same ownership rule as the
    /// name: grey until the operator's first keystroke, taken back when
    /// their call leaves the field, and never over typed text.
    private func offerState() {
        guard standaloneContest?.potaProgram == true else { return }
        let call = entry.callNormalized
        guard !call.isEmpty else {
            entry.clearAutoFilledState()
            return
        }
        guard entry.stateTyped.isEmpty || entry.stateIsAutoFilled else { return }
        if let hint = parkStateHint() ?? ownLogState(for: call) ?? callbookState(for: call) {
            entry.autoFillState(hint)
        } else {
            entry.clearAutoFilledState()
        }
    }

    /// The state the P2P park(s) pin down: every ref must agree on one
    /// side. A ref's own `@subdivision` answers directly; otherwise the
    /// directory's locationDesc does — and a park that straddles states
    /// claims nothing.
    private func parkStateHint() -> String? {
        guard case .success(let refs) =
                PotaRef.parseList(PotaRef.expandShorthand(entry.theirParkTyped)),
              !refs.isEmpty else { return nil }
        var states = Set<String>()
        for ref in refs {
            let halves = ref.split(separator: "@", maxSplits: 1)
            let state: String? = halves.count == 2
                ? PotaPark.singleState(fromLocationDesc: String(halves[1]))
                : PotaPark.singleState(fromLocationDesc: parkLocation(String(halves[0])))
            guard let state else { return nil }
            states.insert(state)
        }
        return states.count == 1 ? states.first : nil
    }

    private func ownLogState(for call: String) -> String? {
        document.log.qsos.last {
            $0.call.uppercased() == call && !($0.theirState ?? "").isEmpty
        }?.theirState
    }

    private func callbookState(for call: String) -> String? {
        guard let record = callbookRecord, record.call == call,
              let state = record.state, !state.isEmpty else { return nil }
        return state.uppercased()
    }

    /// The park the POTA board currently shows a call activating from, if
    /// any — the window wires this to the spot store. An activator hunting
    /// me brings his park along with his call (operator report 2,
    /// 2026-08-25). A closure, not a spot list: the flow stays blind to the
    /// band map and the tests state the board in one line.
    @ObservationIgnored var parkOnBoard: (String) -> String? = { _ in nil }

    /// The super check partial database, when the option is on and a
    /// MASTER.SCP is cached or downloaded. Nil (option off, nothing
    /// downloaded yet) empties its half of the strip immediately.
    private(set) var scpDatabase: SCPDatabase?

    /// What the strip under the entry bar shows for the fragment in the
    /// call field right now: the database's calls and the party's call
    /// history calls, merged and ranked by `SuperCheck`. Recomputed once per
    /// call-field change — the view only reads it.
    private(set) var superCheckMatches: SuperCheck.Matches = .none

    /// Whether the strip has a source to draw from — the database, or the
    /// active party's history file — so a cached roster shows before
    /// MASTER.SCP has landed.
    var superCheckLive: Bool {
        scpDatabase != nil || !historyCallsForParty.isEmpty
    }

    /// The most calls the strip offers; past this it says "+N more".
    static let scpDisplayCap = 24

    /// The fragment `superCheckMatches` was computed for — the memo that lets
    /// the refresh ride `revalidate` (which also runs on exchange keystrokes)
    /// without rescanning 50k calls for a fragment that has not moved.
    @ObservationIgnored private var scpFragment: String?

    func updateSCPDatabase(_ database: SCPDatabase?) {
        scpDatabase = database
        scpFragment = nil
        refreshSCPMatches()
    }

    /// The history calls the strip may use: the downloaded file's, and only
    /// while its tag is this party's.
    private var historyCallsForParty: [String] {
        guard let historyCalls, historyCalls.partyID == party?.id else { return [] }
        return historyCalls.calls
    }

    private func refreshSCPMatches() {
        let fragment = entry.callNormalized
        guard fragment != scpFragment else { return }
        scpFragment = fragment
        let fresh = SuperCheck.matches(
            for: fragment,
            scpCalls: scpDatabase?.calls ?? [],
            historyCalls: historyCallsForParty,
            limit: Self.scpDisplayCap
        )
        if fresh != superCheckMatches { superCheckMatches = fresh }
    }

    /// Everything that changes between one Return and the next and is owned by
    /// the view — the radio's band and mode, where the cursor is, whether the
    /// radio is connected at all.
    ///
    /// Passed per call rather than mirrored into stored properties, so a test
    /// states the conditions directly instead of reproducing the `onChange`
    /// wiring that keeps them current.
    struct Context: Equatable {
        var band: Band
        var modeClass: ModeClass
        var rawMode: String
        var freqKHz: Int?
        var radioConnected: Bool
        var cursor: ESM.Cursor
        var keying: KeyingSettings
        /// How many voice memories the connected radio actually has, 0 for none.
        /// A count rather than a Bool so `transmission(at:)` can tell an
        /// unassigned key from one pointing past the end of this radio's
        /// memories — the second is a mapping built for a different radio, and
        /// must not fire a neighbouring recording.
        var voiceMemoryCount: Int
        /// Where phone keys get their audio. `.radioMemories` reads
        /// `voiceMemoryCount`; `.recordings` reads `voiceRecordings` on the
        /// flow, and only when `ready`. Defaulted to the radio, so every
        /// context built before recordings existed means what it did.
        var phoneSource: PhoneSource
        /// Whether a spot's county is offered into the exchange when a
        /// station arrives from the call frame — the band map's "Offer the
        /// spotted county as the exchange" option. Defaulted on, so every
        /// context built before the frame existed means what it did.
        var offersSpotCounty: Bool

        init(
            band: Band = .m20,
            modeClass: ModeClass = .cw,
            rawMode: String = "CW",
            freqKHz: Int? = nil,
            radioConnected: Bool = false,
            cursor: ESM.Cursor = .call,
            keying: KeyingSettings = KeyingSettings(),
            voiceMemoryCount: Int = 0,
            phoneSource: PhoneSource = .radioMemories,
            offersSpotCounty: Bool = true
        ) {
            self.band = band
            self.modeClass = modeClass
            self.rawMode = rawMode
            self.freqKHz = freqKHz
            self.radioConnected = radioConnected
            self.cursor = cursor
            self.keying = keying
            self.voiceMemoryCount = voiceMemoryCount
            self.phoneSource = phoneSource
            self.offersSpotCounty = offersSpotCounty
        }
    }

    /// The two places a phone key's audio can come from — decided by the view
    /// from the setting, the connected radio and the audio path's readiness
    /// (Article 11 as amended 2026-08-15).
    enum PhoneSource: Equatable, Sendable {
        /// The radio's own recorder, memories 1...`voiceMemoryCount`.
        case radioMemories
        /// Recordings on this Mac. An unready path leaves every key silent,
        /// with the reason shown by the row — it never falls back to the
        /// radio's recorder, which would put a different recording on the
        /// air than the one the operator chose.
        case recordings(ready: Bool)
    }

    /// What a message slot puts on the air.
    ///
    /// CW carries expanded text; a voice message carries a memory number,
    /// because a recording has no text and no macro can reach inside one. The
    /// caption rides along so the TX badge and the messages row cannot word the
    /// same memory two different ways.
    enum Transmission: Equatable {
        case cw(String)
        /// One of the radio's own voice memories.
        case voice(memory: Int, caption: String)
        /// A recording on this Mac, resolved to its audio here so the caller
        /// hands exactly this to the radio path — it cannot pick a different
        /// clip than the one the flow decided on.
        case recording(memory: Int, audio: VoiceAudio, caption: String)
        /// An empty CW slot, an unassigned phone key, one pointing at a memory
        /// this radio does not have, or one with nothing recorded in it.
        case silent
    }

    /// What Return decided, for the caller to apply.
    ///
    /// The resolved `Transmission` rides in the value rather than going
    /// straight to the radio, because what would go on the air *is* the thing
    /// under test.
    enum Outcome: Equatable {
        /// "14025", "40M", "CW" in the call field: a QSY, not a contact.
        case qsy(EntryCommand)
        /// Nothing was logged; `transmission` goes on the air.
        case send(index: Int, transmission: Transmission)
        /// `rows` were appended and `transmission` goes out after them —
        /// resolved *before* the append, which is the whole point.
        case logged(rows: [QSO], transmission: Transmission)
        /// The exchange is valid but the station has no location: Contest Setup
        /// has never run.
        case needsSetup
        case nothing
    }

    init(document: LogDocument, entry: EntryState = EntryState()) {
        self.document = document
        self.entry = entry
        entry.nextSerial = { [weak self] in self?.nextSerialIfUsed }
    }

    // MARK: Party

    /// `PartyCatalog.party(id:)` re-reads the bundle *and* the user parties
    /// folder on every call, and both revalidation and the entry bar's QSO
    /// number read it on every keystroke. Keyed on `partyID`, so a party change
    /// invalidates it and nobody has to remember to.
    ///
    /// `@ObservationIgnored` because a getter that notified would fire during a
    /// view body pass. Correctness still holds: the getter reads
    /// `document.log.partyID`, which *is* observed.
    @ObservationIgnored private var partyCache: (id: String, party: PartyDefinition?)?

    var party: PartyDefinition? {
        let id = document.log.partyID
        if let cached = partyCache, cached.id == id { return cached.party }
        let looked = PartyCatalog.party(id: id)
        partyCache = (id, looked)
        return looked
    }

    /// The definitions of whatever the active party `combines` — empty for
    /// every ordinary party. Cached for the same reason `party` is: the score
    /// sidebar reads it on every render, and resolving four ids means four
    /// passes over the bundle and the user's parties folder.
    @ObservationIgnored private var membersCache: (id: String, members: [PartyDefinition])?

    var combinedMembers: [PartyDefinition] {
        let id = document.log.partyID
        if let cached = membersCache, cached.id == id { return cached.members }
        let looked = (party?.combines ?? []).compactMap { PartyCatalog.party(id: $0) }
        membersCache = (id, looked)
        return looked
    }

    /// The QSO number the next contact will send, or nil for the parties that
    /// exchange none.
    var nextSerialIfUsed: Int? {
        (party?.exchangeIncludesSerial ?? false) ? document.log.nextSerial : nil
    }

    /// Resolves a v2-only contest for tests without touching the bundle.
    @ObservationIgnored var contestResolver: (String) -> ContestDefinition? =
        { ContestCatalog.contest(id: $0) }
    @ObservationIgnored private var contestCache: (id: String, contest: ContestDefinition?)?

    /// The v2 contest for a log whose id names no party (POTA). Nil whenever
    /// a `PartyDefinition` exists, so every party path stays exactly as it
    /// was. Cached like `party`, for the same per-keystroke reason.
    var standaloneContest: ContestDefinition? {
        guard party == nil else { return nil }
        let id = document.log.partyID
        if let cached = contestCache, cached.id == id { return cached.contest }
        let looked = contestResolver(id)
        contestCache = (id, looked)
        return looked
    }

    // MARK: Messages

    var activeMessages: [String] {
        document.log.messages.messages(for: document.log.operatingMode)
    }

    func expandMacros(_ template: String, context: Context) -> String {
        AppSettings.expandMacros(
            template,
            myCall: document.log.station.callsign.uppercased(),
            call: entry.callNormalized,
            rst: entry.rstSent.isEmpty ? context.modeClass.defaultRST : entry.rstSent,
            exchange: document.log.myLocation.displayText,
            serial: entry.serialSent,
            name: document.log.exchangeName.uppercased(),
            member: sentMemberMacroText,
            myParks: document.log.myPotaRefs.joined(separator: " "),
            cutNumbers: context.keying.cutNumbers && context.modeClass == .cw,
            cutOne: context.keying.cutOne
        )
    }

    /// What `{MEMBER}` keys: the on-air form of the log's contest-long
    /// element. A member number goes out as "NR 13" — the sponsor's own
    /// sample QSO — and a power as "5W" verbatim, which is why the macro
    /// shapes itself rather than the message template carrying a literal
    /// "NR" that a non-member's power would inherit. Empty for every party
    /// without the element.
    private var sentMemberMacroText: String {
        guard party?.memberExchange != nil else { return "" }
        let raw = document.log.exchangeMember
            .trimmingCharacters(in: .whitespaces).uppercased()
        guard !raw.isEmpty else { return "" }
        if case .member = MemberExchange.parse(raw) { return "NR \(raw)" }
        return raw
    }

    /// The text F<index+1> would key right now, or "" when that slot is empty.
    func expandedMessage(at index: Int, context: Context) -> String {
        let set = activeMessages
        guard set.indices.contains(index), !set[index].isEmpty else { return "" }
        return expandMacros(set[index], context: context)
    }

    /// What F<index+1> would put on the air right now. `expandedMessage`
    /// survives for its own tests and as this method's CW arm — the CW
    /// preview itself now goes through `transmission`/`messageKeys` like
    /// everything else that keys.
    func transmission(at index: Int, context: Context) -> Transmission {
        if context.modeClass == .phone {
            let memories = document.log.messages.voiceMemories(for: document.log.operatingMode)
            guard memories.indices.contains(index), let memory = memories[index] else { return .silent }
            let caption = document.log.messages.voiceMemoryCaption(memory)
            switch context.phoneSource {
            case .radioMemories:
                // Not `(1...count).contains` on a zero count — `1...0` traps.
                guard context.voiceMemoryCount > 0,
                      (1...context.voiceMemoryCount).contains(memory) else { return .silent }
                return .voice(memory: memory, caption: caption)
            case .recordings(let ready):
                guard ready, let audio = voiceRecordings[memory] else { return .silent }
                return .recording(memory: memory, audio: audio, caption: caption)
            }
        }
        let text = expandedMessage(at: index, context: context)
        return text.isEmpty ? .silent : .cw(text)
    }

    // MARK: ESM

    /// ESM drives Return on CW, and on phone once there is something to play
    /// — the radio's memories, or a ready path with a recording in it.
    /// Otherwise Return is a plain log key.
    func esmDrivesReturn(_ context: Context) -> Bool {
        guard context.keying.esmEnabled, context.radioConnected else { return false }
        switch context.modeClass {
        case .cw: return true
        case .phone:
            switch context.phoneSource {
            case .radioMemories: return context.voiceMemoryCount > 0
            case .recordings(let ready): return ready && !voiceRecordings.isEmpty
            }
        case .digital: return false
        }
    }

    private var esmExchangeState: ESM.ExchangeState {
        switch entry.exchangeStatus {
        case .idle: .empty
        case .valid: .valid
        case .invalid: .unmatched
        }
    }

    /// What Return would do right now. Read both by the Return key and by the
    /// messages row's highlight, so the two can never disagree about which
    /// message is next.
    func esmAction(_ context: Context) -> ESM.Action {
        ESM.nextAction(
            mode: document.log.operatingMode,
            callEmpty: entry.callNormalized.isEmpty,
            exchange: esmExchangeState,
            cursor: context.cursor
        )
    }

    /// The F-key slot Return will send next, or nil when ESM isn't driving it.
    func pendingMessageIndex(_ context: Context) -> Int? {
        esmDrivesReturn(context) ? esmAction(context).messageIndex : nil
    }

    // MARK: The Return sequence

    /// Return: typed QSY commands first, then plain logging or the ESM state
    /// machine.
    func returnPressed(_ context: Context, undoManager: UndoManager?) -> Outcome {
        // "14025", "40M", "CW"… in the call field tunes instead of logging —
        // hands stay on the keyboard.
        if let command = EntryCommand.parse(entry.call) {
            entry.callTyped = ""
            revalidate(context)
            return .qsy(command)
        }

        entry.applyDefaults(modeClass: context.modeClass)
        revalidate(context)

        guard esmDrivesReturn(context) else {
            return logContact(context, undoManager: undoManager)
        }

        // N1MM: "Hitting the space bar (or Enter, in ESM) will pull the
        // call-sign from the call-frame into the Call-sign textbox." Only from
        // the call field — it never logs, so filling it here is always safe;
        // from the exchange field ESM reads the cursor as "I have him", and a
        // row filled with a county could log on the same keystroke.
        if context.cursor == .call, entry.callNormalized.isEmpty {
            takeCallFrame(context)
        }

        switch esmAction(context) {
        case .sendMessage(let index):
            // The cursor is never moved for you. Wherever it is, that is where
            // it stays, so a Return that called once calls again — Space is
            // what advances, when the operator decides the contact has.
            let outgoing = transmission(at: index, context: context)
            return outgoing == .silent ? .nothing : .send(index: index, transmission: outgoing)

        case .logAndSend(let index):
            // Resolve before logging: logging advances the entry to the next
            // QSO number, so resolving afterwards would key a number one higher
            // than the one just written to the log — and the other station
            // would log that, putting both of us NIL.
            //
            // This ordering is the 2026-07-25 bug. It is why the resolution
            // happens here rather than in the caller.
            let pending = transmission(at: index, context: context)
            switch logContact(context, undoManager: undoManager) {
            case .logged(let rows, _):
                return .logged(rows: rows, transmission: pending)
            case let other:
                // Nothing was logged — a missing location or an invalid
                // exchange. Do not key a report for a contact that did not
                // happen.
                return other
            }

        case .none:
            return logContact(context, undoManager: undoManager)
        }
    }

    func logContact(_ context: Context, undoManager: UndoManager?) -> Outcome {
        guard let party else { return logStandaloneContact(context, undoManager: undoManager) }
        entry.applyDefaults(modeClass: context.modeClass)
        revalidate(context)
        guard case .valid(let theirLocs) = entry.exchangeStatus,
              !entry.callNormalized.isEmpty else { return .nothing }

        // A name party's exchange is not complete without the name — logging
        // a nameless row is the blank ex1 column that blocks submission, and
        // the ESM path must not key a report for a contact that did not
        // happen.
        guard !entry.missingName(party: party) else { return .nothing }

        // A member party's element may be blank — that is a QRO station —
        // but it may not be unreadable: the element decides the QSO's
        // points, so a mis-keyed number would score as QRO in silence.
        guard !entry.invalidMember(party: party) else { return .nothing }

        // One contact, one park set each way. An unparseable park-to-park
        // reference is refused like an unreadable member element — it is
        // what earns the credit at POTA.
        guard case .success(let theirParks) = PotaRef.parseList(PotaRef.expandShorthand(entry.theirParkTyped)) else {
            return .nothing
        }
        // Mine is the log's current Contest Setup value, stamped per row so
        // the record shows where the contact was actually made from — a
        // mid-contest park change affects later rows only.
        let myParks = document.log.myPotaRefs

        let myLocs = document.log.myLocation.sentExchanges.filter { !$0.isEmpty }
        guard !myLocs.isEmpty else { return .needsSetup }

        // One contact, one QSO number — every row of a county-line contact
        // carries the same pair. A blank sent field falls back to the log's next
        // number so a submittable log never ends up with a hole in it.
        let serials = entry.serials(party: party)
        let sentSerial = party.exchangeIncludesSerial
            ? (serials.sent ?? document.log.nextSerial)
            : nil

        // One contact, one name each way. The sent name is the log's
        // contest-long setting; the row records what actually went out.
        let sentName = party.exchangeIncludesName
            ? normalizedName(document.log.exchangeName)
            : nil
        let rcvdName = party.exchangeIncludesName
            ? normalizedName(entry.nameRcvd)
            : nil

        // One contact, one member element each way — the sent value is the
        // log's contest-long setting, the received one what was just copied.
        let hasMember = party.memberExchange != nil
        let sentMember = hasMember
            ? normalizedName(document.log.exchangeMember)
            : nil
        let rcvdMember = hasMember
            ? normalizedName(entry.memberRcvd)
            : nil

        let rows = CountyLineExpander.expand(
            entry: .init(
                call: entry.callNormalized,
                rstSent: entry.rstSent.isEmpty ? context.modeClass.defaultRST : entry.rstSent,
                rstRcvd: entry.rstRcvd.isEmpty ? context.modeClass.defaultRST : entry.rstRcvd,
                serialSent: sentSerial,
                serialRcvd: serials.rcvd,
                nameSent: sentName,
                nameRcvd: rcvdName,
                memberSent: sentMember,
                memberRcvd: rcvdMember,
                myPotaRefs: myParks.isEmpty ? nil : myParks,
                theirPotaRefs: theirParks.isEmpty ? nil : theirParks,
                band: context.band,
                modeClass: context.modeClass,
                rawMode: context.rawMode,
                freqKHz: context.freqKHz,
                timestampUTC: Date(),
                // The same flag that picks the message set and decides what
                // ⇧⌘S means. Nothing scores on it and no export carries it —
                // it is what lets the advisor say what running on this band
                // has actually paid tonight.
                posture: document.log.operatingMode
            ),
            myLocs: myLocs,
            theirLocs: theirLocs
        )
        document.append(qsos: rows, undoManager: undoManager)
        // He is in the log now; there is nothing pending about him.
        entry.pendingExchanges.removeValue(forKey: entry.callNormalized)
        entry.clearForNextContact(modeClass: context.modeClass)
        // The call just left the field; no strip may outlive it.
        refreshSCPMatches()
        return .logged(rows: rows, transmission: .silent)
    }

    /// The nil-party path: a v2-only contest (POTA). No location element and
    /// no county line — one row per contact, parks each way, the RSTs from
    /// the row or the mode's default. Everything else — pending stash, SCP
    /// strip, clear-for-next — behaves exactly as the party path.
    private func logStandaloneContact(_ context: Context, undoManager: UndoManager?) -> Outcome {
        guard standaloneContest != nil else { return .nothing }
        entry.applyDefaults(modeClass: context.modeClass)
        revalidate(context)
        guard !entry.callNormalized.isEmpty else { return .nothing }
        // An unparseable park refuses to log, exactly as in a party — the
        // reference is what earns the P2P credit at POTA.
        guard case .success(let theirParks) = PotaRef.parseList(PotaRef.expandShorthand(entry.theirParkTyped)) else {
            return .nothing
        }
        // Mine is the log's current Contest Setup value, stamped per row so
        // the record shows where the contact was actually made from — a
        // mid-outing rove affects later rows only.
        let myParks = document.log.myPotaRefs
        // The callbook stamp (spec 2026-08-25 decisions 4–5): only where
        // the contest asks, and only the record for this very call — a
        // stale answer for the last station must never mark this one.
        var stamp: QSO.CallbookStamp?
        if standaloneContest?.enrichFromCallbook == true,
           let known = callbookRecord, known.call == entry.callNormalized {
            stamp = QSO.CallbookStamp(name: known.name, qth: known.qth,
                                      state: known.state, grid: known.grid,
                                      source: known.source.label)
        }
        // Their state as copied and the operator's note — advisory fields
        // (operator report 1, 2026-08-25): a token folds to caps, prose
        // keeps its case, and empty stores nothing.
        let state = entry.stateTyped.trimmingCharacters(in: .whitespaces).uppercased()
        let note = entry.notesTyped.trimmingCharacters(in: .whitespaces)
        let row = QSO(
            call: entry.callNormalized,
            band: context.band,
            modeClass: context.modeClass,
            rawMode: context.rawMode,
            freqKHz: context.freqKHz,
            sent: [ExchangeElementID.rst: entry.rstSent.isEmpty
                       ? context.modeClass.defaultRST : entry.rstSent],
            rcvd: [ExchangeElementID.rst: entry.rstRcvd.isEmpty
                       ? context.modeClass.defaultRST : entry.rstRcvd,
                   ExchangeElementID.state: state],
            myPotaRefs: myParks.isEmpty ? nil : myParks,
            theirPotaRefs: theirParks.isEmpty ? nil : theirParks,
            posture: document.log.operatingMode,
            callbook: stamp,
            notes: note.isEmpty ? nil : note
        )
        document.append(qsos: [row], undoManager: undoManager)
        entry.pendingExchanges.removeValue(forKey: entry.callNormalized)
        entry.clearForNextContact(modeClass: context.modeClass)
        refreshSCPMatches()
        return .logged(rows: [row], transmission: .silent)
    }

    // MARK: Entry housekeeping

    func revalidate(_ context: Context) {
        if let contest = standaloneContest {
            entry.revalidate(
                contest: contest,
                log: document.log,
                band: context.band,
                modeClass: context.modeClass
            )
        } else {
            entry.revalidate(
                party: party,
                log: document.log,
                band: context.band,
                modeClass: context.modeClass
            )
        }
        refreshSCPMatches()
    }

    /// The call field changed by typing. Refresh what the app is offering for
    /// this station, then revalidate. Safe on every keystroke: the only text it
    /// can overwrite is text it wrote itself.
    func callChanged(_ context: Context) {
        refreshPrefill(context)
        revalidate(context)
    }

    /// A different station, chosen whole — a spot click or ⌘↑ / ⌘↓.
    ///
    /// Distinct from `callChanged` on purpose. Typing is incremental and must
    /// never cost the operator text they typed; arriving at a new station is a
    /// deliberate move away, so what was copied for the last one comes off the
    /// row — kept under his call, not thrown away.
    func stationChanged(
        to call: String, _ context: Context, spotCounty: String? = nil, atKHz: Double? = nil
    ) {
        stashPending()
        entry.exchangeTyped = ""
        entry.serialRcvd = ""
        entry.nameTyped = ""
        entry.memberTyped = ""
        entry.autoFillCall(call)
        // Where the app filled it, for the erase rule; nil when nobody arrived.
        autoFilledCallKHz = entry.callIsAutoFilled ? atKHz : nil
        // Tied to the call it arrived with, so typing over a busted spot does
        // not carry the old station's county to the new one.
        spotCountyHint = spotCounty
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .flatMap { $0.isEmpty ? nil : (call: entry.callNormalized, county: $0) }
        refreshPrefill(context)
        revalidate(context)
    }

    /// The station left the row without a contact — the VFO moved on. The
    /// same bookkeeping as arriving at a new one, with nobody arriving.
    func stationLeft(_ context: Context) {
        stationChanged(to: "", context)
    }

    /// The frequency the app filled the call at — a spot's, from the frame, a
    /// click or ⌘↑/⌘↓. Compared with the VFO by `tunedAway`.
    private var autoFilledCallKHz: Double?

    // MARK: The call frame

    /// The spot under the VFO, or nil. Written by the view on every VFO
    /// change while searching; never touches the call field.
    func updateCallFrame(_ spot: Spot?) {
        if entry.callFrame != spot { entry.callFrame = spot }
    }

    /// Space, or Return under ESM, in an empty call field: the frame's call
    /// goes into the field and its county — when the option is on — into the
    /// exchange, exactly as a spot click arrives. False when there is nothing
    /// to take or the field already holds text, typed or filled.
    @discardableResult
    func takeCallFrame(_ context: Context) -> Bool {
        guard entry.callNormalized.isEmpty, let spot = entry.callFrame else { return false }
        stationChanged(
            to: spot.call, context,
            spotCounty: context.offersSpotCounty ? spot.county : nil,
            atKHz: spot.freqKHz
        )
        return true
    }

    /// N1MM: "If you tune the VFO outside that range, any call-sign captured
    /// into the Entry window's call-frame or brought into the Entry window's
    /// call-sign textbox will be erased." Here: a call the app filled, once the
    /// VFO is more than the tolerance from where it was filled, and only while
    /// the row holds nothing the operator typed. Typed text is never touched
    /// by tuning.
    func tunedAway(toKHz vfoKHz: Double, toleranceKHz: Double, _ context: Context) {
        guard entry.callIsAutoFilled, !entry.hasOperatorText,
              let filledAt = autoFilledCallKHz,
              abs(vfoKHz - filledAt) > toleranceKHz + 0.0001
        else { return }
        stationLeft(context)
    }

    /// The county a spot claimed for a station, and which station it claimed it
    /// for. Only a hub spot carries one; a cluster spot never does.
    private var spotCountyHint: (call: String, county: String)?

    private func stashPending() {
        let outgoing = entry.callNormalized
        guard !outgoing.isEmpty else { return }
        // Only the operator's own text is worth keeping — an auto-filled
        // field is re-derivable, and stashing it would launder a hint into
        // "something he copied".
        let pending = EntryState.Pending(
            exchange: entry.exchangeIsAutoFilled ? "" : entry.exchange,
            serialRcvd: entry.serialRcvd,
            nameRcvd: entry.nameIsAutoFilled ? "" : entry.nameRcvd,
            memberRcvd: entry.memberIsAutoFilled ? "" : entry.memberRcvd
        )
        guard !pending.isEmpty else { return }
        entry.pendingExchanges[outgoing] = pending
    }

    /// Trimmed and uppercased, nil when nothing is left — the form a name
    /// takes on a QSO row.
    private func normalizedName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespaces).uppercased()
        return name.isEmpty ? nil : name
    }

    /// Offer what we know about the call now in the field, or take back what we
    /// offered for the last one.
    private func refreshPrefill(_ context: Context) {
        let call = entry.callNormalized

        // The park an activator gave earlier comes back offered on the next
        // band. **This log only** — never the call history file or the
        // archive the exchange chain below draws on: a park is where someone
        // is sitting today, and last season's is worse than nothing. Typed
        // text is never overwritten, and nothing is taken back either: the
        // field may hold a half-typed park for the contact being entered
        // right now, and `clearForNextContact` is what resets it between
        // contacts. Above the party gate on purpose — a POTA log has no
        // party and hunts parks all day.
        if !call.isEmpty, entry.theirParkTyped.isEmpty {
            // The board first: it is the activator's own current claim,
            // minute-fresh, and outranks the park he gave me hours ago —
            // a rover's old row is exactly what must not come back. The
            // own-log offer stands where the board says nothing. Typed
            // text is never overwritten either way.
            if let onBoard = parkOnBoard(call) {
                entry.theirParkTyped = onBoard
            } else if let previous = document.log.qsos.last(where: {
                $0.call.uppercased() == call && $0.theirPotaRefs != nil
            }) {
                entry.theirParkTyped = (previous.theirPotaRefs ?? []).joined(separator: ",")
            }
        }

        // The State field's offer — the park's side, an earlier row's, or
        // the callbook's — recomputed now that the call (and possibly the
        // park, just above) has changed. Gated inside on the POTA row's own
        // field existing: a party log must not squirrel invisible text into
        // the state and trip the erase rule.
        offerState()

        guard let party else { return }

        guard !call.isEmpty else {
            entry.clearAutoFilledExchange()
            entry.clearAutoFilledName()
            entry.clearAutoFilledMember()
            return
        }

        let role: ExchangeParser.Role =
            document.log.myLocation.isInState ? .inState : .outOfState
        let history = callHistoryCandidate(call: call, party: party, role: role)

        if entry.exchange.isEmpty || entry.exchangeIsAutoFilled {
            // What the operator copied outranks anything the app can derive
            // — including what he copied for this station and never logged.
            if let pending = entry.pendingExchanges[call] {
                entry.restorePending(pending)
            }
            // The pending stash can hold a serial or name with no exchange;
            // an exchange the operator owns ends the matter, an empty one
            // still deserves a hint.
            if entry.exchange.isEmpty || entry.exchangeIsAutoFilled {
                // This log, the archive, then the call history file — the
                // community's roster ranks below anything we copied ourselves.
                // The band map colours spots by the same call, so a red spot
                // is one whose county lands here.
                if let known = StationMemory.knownLocation(
                    call: call,
                    log: document.log.qsos,
                    index: archiveIndex,
                    callHistory: callHistoryParsed(for: party),
                    party: party,
                    role: role
                ) {
                    entry.autoFillExchange(
                        known.text,
                        origin: known.source == .callHistory ? .callHistory : .ownLog
                    )
                } else if let hint = spotCountyHint, hint.call == call {
                    // A spot's county is the last resort and the weakest
                    // evidence there is — a stranger's claim about a station
                    // we have never worked — so it fills the field marked
                    // unconfirmed rather than leaving it blank.
                    entry.autoFillExchange(hint.county, origin: .spot)
                } else {
                    entry.clearAutoFilledExchange()
                }
            }
        }

        // The name has its own chain: this log first (a name party's rows
        // carry what was copied), then the call history file. Independent of
        // the exchange chain, because either half can be known without the
        // other.
        if party.exchangeIncludesName,
           entry.nameRcvd.isEmpty || entry.nameIsAutoFilled {
            let logged = document.log.qsos.last {
                $0.call.uppercased() == call
            }?.nameRcvd
            if let name = logged ?? history?.name {
                entry.autoFillName(name)
            } else {
                entry.clearAutoFilledName()
            }
        }

        // And the member element likewise: this log's own copy first (a
        // station's number does not change mid-contest), then the roster.
        if party.memberExchange != nil,
           entry.memberRcvd.isEmpty || entry.memberIsAutoFilled {
            let logged = document.log.qsos.last {
                $0.call.uppercased() == call
            }?.memberRcvd
            if let member = logged ?? history?.member {
                entry.autoFillMember(member)
            } else {
                entry.clearAutoFilledMember()
            }
        }

    }

    private func callHistoryCandidate(
        call: String, party: PartyDefinition, role: ExchangeParser.Role
    ) -> CallHistoryFile.Candidate? {
        guard let callHistoryIndex, callHistoryIndex.partyID == party.id else {
            return nil
        }
        return CallHistoryFile.candidate(
            for: call, in: callHistoryIndex.parsed, party: party, role: role)
    }

    /// The party's parsed call history file, or nil when the one loaded is
    /// another party's (the download may land after a party change).
    private func callHistoryParsed(for party: PartyDefinition) -> CallHistoryFile.Parsed? {
        guard let callHistoryIndex, callHistoryIndex.partyID == party.id else { return nil }
        return callHistoryIndex.parsed
    }

    /// Mode changes (radio or manual): swap pre-filled RST defaults (599 ↔ 59)
    /// and re-check validation/dupes for the new mode.
    func modeChanged(_ context: Context) {
        entry.syncRSTDefaults(modeClass: context.modeClass)
        revalidate(context)
    }

    /// F12 — wipe a half-typed contact.
    func clearEntry(_ context: Context) {
        autoFilledCallKHz = nil
        entry.clearForNextContact(modeClass: context.modeClass)
        revalidate(context)
    }

    /// Deliberately does *not* seed the QSO number. It follows the log, so
    /// there is no seeding moment here to get wrong — which is the whole
    /// reason the 2026-07-25 blank-number bug cannot recur.
    func onAppear(_ context: Context) {
        entry.applyDefaults(modeClass: context.modeClass)
    }
}
