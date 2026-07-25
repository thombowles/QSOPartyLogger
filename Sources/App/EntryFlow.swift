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
/// The rule that makes it testable: **this type never keys anything.** It
/// returns the string it would key, and the caller hands that to the radio. A
/// caller that has to be handed the text cannot key a different one, which is
/// what closes the ordering bug — expanding a message after logging keys the
/// *next* contact's number.
@MainActor
@Observable
final class EntryFlow {
    let entry: EntryState
    let document: LogDocument

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

        init(
            band: Band = .m20,
            modeClass: ModeClass = .cw,
            rawMode: String = "CW",
            freqKHz: Int? = nil,
            radioConnected: Bool = false,
            cursor: ESM.Cursor = .call,
            keying: KeyingSettings = KeyingSettings()
        ) {
            self.band = band
            self.modeClass = modeClass
            self.rawMode = rawMode
            self.freqKHz = freqKHz
            self.radioConnected = radioConnected
            self.cursor = cursor
            self.keying = keying
        }
    }

    /// What Return decided, for the caller to apply.
    ///
    /// The keyed text rides in the value rather than going straight to the
    /// radio, because the text *is* the thing under test.
    enum Outcome: Equatable {
        /// "14025", "40M", "CW" in the call field: a QSY, not a contact.
        case qsy(EntryCommand)
        /// Nothing was logged; `text` goes on the air.
        case send(index: Int, text: String)
        /// `rows` were appended and `text` goes out after them — expanded
        /// *before* the append, which is the whole point. `text` is "" when the
        /// slot is empty.
        case logged(rows: [QSO], text: String)
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

    /// The QSO number the next contact will send, or nil for the parties that
    /// exchange none.
    var nextSerialIfUsed: Int? {
        (party?.exchangeIncludesSerial ?? false) ? document.log.nextSerial : nil
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
            cutNumbers: context.keying.cutNumbers && context.modeClass == .cw,
            cutOne: context.keying.cutOne
        )
    }

    /// The text F<index+1> would key right now, or "" when that slot is empty.
    func expandedMessage(at index: Int, context: Context) -> String {
        let set = activeMessages
        guard set.indices.contains(index), !set[index].isEmpty else { return "" }
        return expandMacros(set[index], context: context)
    }

    // MARK: ESM

    /// ESM only drives Return on CW with the radio connected — otherwise Return
    /// is a plain log key.
    func esmDrivesReturn(_ context: Context) -> Bool {
        context.keying.esmEnabled && context.radioConnected && context.modeClass == .cw
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
            entry.call = ""
            revalidate(context)
            return .qsy(command)
        }

        entry.applyDefaults(modeClass: context.modeClass)
        revalidate(context)

        guard esmDrivesReturn(context) else {
            return logContact(context, undoManager: undoManager)
        }

        switch esmAction(context) {
        case .sendMessage(let index):
            // The cursor is never moved for you. Wherever it is, that is where
            // it stays, so a Return that called once calls again — Space is
            // what advances, when the operator decides the contact has.
            let text = expandedMessage(at: index, context: context)
            return text.isEmpty ? .nothing : .send(index: index, text: text)

        case .logAndSend(let index):
            // Expand before logging: logging advances the entry to the next QSO
            // number, so expanding afterwards would key a number one higher
            // than the one just written to the log — and the other station
            // would log that, putting both of us NIL.
            //
            // This ordering is the 2026-07-25 bug. It is why the expansion
            // happens here rather than in the caller.
            let pending = expandedMessage(at: index, context: context)
            switch logContact(context, undoManager: undoManager) {
            case .logged(let rows, _):
                return .logged(rows: rows, text: pending)
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
        guard let party else { return .nothing }
        entry.applyDefaults(modeClass: context.modeClass)
        revalidate(context)
        guard case .valid(let theirLocs) = entry.exchangeStatus,
              !entry.callNormalized.isEmpty else { return .nothing }

        let myLocs = document.log.myLocation.sentExchanges.filter { !$0.isEmpty }
        guard !myLocs.isEmpty else { return .needsSetup }

        // One contact, one QSO number — every row of a county-line contact
        // carries the same pair. A blank sent field falls back to the log's next
        // number so a submittable log never ends up with a hole in it.
        let serials = entry.serials(party: party)
        let sentSerial = party.exchangeIncludesSerial
            ? (serials.sent ?? document.log.nextSerial)
            : nil

        let rows = CountyLineExpander.expand(
            entry: .init(
                call: entry.callNormalized,
                rstSent: entry.rstSent.isEmpty ? context.modeClass.defaultRST : entry.rstSent,
                rstRcvd: entry.rstRcvd.isEmpty ? context.modeClass.defaultRST : entry.rstRcvd,
                serialSent: sentSerial,
                serialRcvd: serials.rcvd,
                band: context.band,
                modeClass: context.modeClass,
                rawMode: context.rawMode,
                freqKHz: context.freqKHz,
                timestampUTC: Date()
            ),
            myLocs: myLocs,
            theirLocs: theirLocs
        )
        document.append(qsos: rows, undoManager: undoManager)
        entry.clearForNextContact(modeClass: context.modeClass)
        return .logged(rows: rows, text: "")
    }

    // MARK: Entry housekeeping

    func revalidate(_ context: Context) {
        entry.revalidate(
            party: party,
            log: document.log,
            band: context.band,
            modeClass: context.modeClass
        )
    }

    /// Mode changes (radio or manual): swap pre-filled RST defaults (599 ↔ 59)
    /// and re-check validation/dupes for the new mode.
    func modeChanged(_ context: Context) {
        entry.syncRSTDefaults(modeClass: context.modeClass)
        revalidate(context)
    }

    /// F12 — wipe a half-typed contact.
    func clearEntry(_ context: Context) {
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
