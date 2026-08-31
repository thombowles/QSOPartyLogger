import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var qplog: UTType {
        UTType(exportedAs: "org.b5n.qsopartylogger.log")
    }

    /// The type behind the ⌘E save panel. The panel only keeps a `.adi`
    /// filename if an allowed content type claims that extension —
    /// `.plainText` does not, and third parties that do claim it (SmartSDR)
    /// don't conform to plain text, so exports came back `.adi.txt`.
    ///
    /// Built by shape, not by identifier: this Mac carries dozens of
    /// registered dev builds of this app, and `UTType(importedAs:)` was
    /// observed resolving to a stale conformance-less shape while the
    /// Info.plist declaration (project.yml) was correct. Shape lookup returns
    /// that declaration when LaunchServices is coherent and synthesizes an
    /// equivalent dynamic type when it is not; the panel keeps `.adi` either
    /// way. The declaration still supplies Finder's "ADIF Amateur Radio Log"
    /// description and the `.adif` alternate-extension claim.
    static var adi: UTType {
        UTType(filenameExtension: "adi", conformingTo: .plainText) ?? .plainText
    }
}

/// Document wrapper around `ContestLog`. Mutations are main-actor and register
/// undo so the document machinery tracks dirty state (and the user gets undo
/// for free). Snapshots hand an immutable `ContestLog` value to the writer,
/// which is what makes the `@unchecked Sendable` sound.
@Observable
final class LogDocument: ReferenceFileDocument, @unchecked Sendable {
    /// What one save writes: the log, and — when the window supplied one —
    /// its score as already folded, so the write queue never re-scores.
    struct SaveSnapshot: Sendable {
        var log: ContestLog
        var score: ScoreSnapshot?
    }

    typealias Snapshot = SaveSnapshot

    static var readableContentTypes: [UTType] { [.qplog] }

    var log: ContestLog {
        didSet { generation &+= 1 }
    }

    /// Bumped by every `log` mutation — the O(1) "did anything change" stamp
    /// `LiveScore` keys its cache on. Observed, so a view that reads the
    /// cached score re-renders exactly when the log changes. Reads never
    /// bump it; the initialisers don't either (a property's own `didSet`
    /// does not fire during `init`), so a freshly opened document starts
    /// at 0 with nothing folded yet.
    private(set) var generation = 0

    /// Where this document currently lives on disk (tracked by the UI from
    /// the NSDocument bridge; nil while still an unsaved draft). Used to skip
    /// redundant iCloud mirroring for documents stored in the logs folder.
    @ObservationIgnored var knownFileURL: URL?

    /// Where the operator's per-party message sets live between logs. Nil
    /// until the window wires the real store, so a document built in a test
    /// remembers nothing and no test can reach another through the memory.
    @ObservationIgnored var messageMemory: MessageMemory?

    /// The window's already-computed score for the save's stamp, wired like
    /// the flow's closures. Nil — no window yet, a test, an id with no rules
    /// installed, or a call off the main thread — falls back to computing
    /// the snapshot at save time, exactly as before.
    @ObservationIgnored var scoreSnapshotProvider: (() -> ScoreSnapshot?)?

    /// Nonisolated on purpose: `DocumentGroup`'s new-document factory runs on a
    /// background dispatch queue, so this must not touch main-actor state.
    /// The last station profile is read straight out of `Preferences.store`
    /// (thread-safe) rather than through the @MainActor `AppSettings.shared`.
    init() {
        var initial = ContestLog(partyID: "ksqp")
        initial.station = LogDocument.savedStationProfile() ?? StationProfile()
        self.log = initial
    }

    nonisolated static func savedStationProfile() -> StationProfile? {
        Preferences.store.data(forKey: "lastStationProfile")
            .flatMap { try? JSONDecoder().decode(StationProfile.self, from: $0) }
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.log = try LogDocument.decodeUpgrading(data)
    }

    /// Decode-then-upgrade, split out from `init(configuration:)` because
    /// `ReadConfiguration` has no public initialiser and the open path's
    /// upgrade would otherwise be untestable.
    nonisolated static func decodeUpgrading(_ data: Data) throws -> ContestLog {
        upgradingUntouchedMessages(try ContestLog.decode(from: data))
    }

    /// A log saved before default macros followed the party's exchange shape
    /// carries the old fixed `{RST}` set. An untouched set — byte-identical to
    /// what shipped — carries no operator intent, so it is upgraded to the
    /// party's shape. An edited set is left alone for `MessagesEditor` to warn
    /// about; rewriting a customised message set behind the operator's back is
    /// worse than the bug.
    ///
    /// Separate from `ContestLog.init(from:)` on purpose: a `Codable` init must
    /// not touch the filesystem, and `ContestCatalog.contest(id:)` re-reads
    /// the user folders on every call.
    nonisolated static func upgradingUntouchedMessages(_ log: ContestLog) -> ContestLog {
        guard log.messages == MessageSets.standard else { return log }
        var upgraded = log
        upgraded.messages = MessageSets.defaults(for: ContestCatalog.contest(id: log.partyID))
        return upgraded
    }

    func snapshot(contentType: UTType) throws -> SaveSnapshot {
        SaveSnapshot(log: log, score: scoreSnapshotProvider.flatMap { $0() })
    }

    func fileWrapper(snapshot: SaveSnapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try LogDocument.dataForSaving(snapshot.log, score: snapshot.score)
        // Best-effort iCloud mirror on every save; never blocks or fails the
        // primary write. Documents that already live in the logs folder ARE
        // the synced copy — mirroring them would trigger "file changed by
        // another application" churn.
        if CloudMirror.isEnabled, snapshot.log.setupCompleted, !CloudMirror.folderContains(knownFileURL) {
            let name = LogDocument.mirrorFileName(for: snapshot.log)
            DispatchQueue.global(qos: .utility).async {
                CloudMirror.mirror(data: data, fileName: name)
            }
        }
        return FileWrapper(regularFileWithContents: data)
    }

    /// The bytes every save writes — to the document's own file and to the
    /// iCloud mirror alike: the log with its score as of this save stamped
    /// in (`ContestLog.stampingScoreSnapshot`), so the file itself is the
    /// contest history the dashboard reads. The document's model is not
    /// touched; the stamp lives in the file. A `score` the window already
    /// folded is stamped directly; nil computes it here, exactly as before.
    nonisolated static func dataForSaving(_ log: ContestLog, score: ScoreSnapshot? = nil) throws -> Data {
        if let score { return try log.stampingScoreSnapshot(using: score).encoded() }
        return try log.stampingScoreSnapshot().encoded()
    }

    /// The stem the export save panel offers: the log's own name — the file's
    /// for a saved document, the dated name the first auto-save is about to
    /// use for a draft. "2026-08-29 KSQP KE5CW.adi" sorts and reads; the bare
    /// callsign the exports used to offer did neither.
    nonisolated static func exportBaseName(fileURL: URL?, log: ContestLog) -> String {
        fileURL.map { $0.deletingPathExtension().lastPathComponent }
            ?? mirrorFileName(for: log)
    }

    /// Stable per-contest mirror name: dated by the first QSO (or today for
    /// an empty log) so a contest keeps one file across saves.
    nonisolated static func mirrorFileName(for log: ContestLog) -> String {
        defaultDisplayName(
            partyID: log.partyID,
            callsign: log.station.callsign,
            date: log.qsos.map(\.timestampUTC).min() ?? Date(),
            activatedParks: log.myPotaRefs,
            potaProgram: ContestCatalog.contest(id: log.partyID)?.potaProgram ?? false
        )
    }

    // MARK: Mutations (undoable, main-actor)

    var party: PartyDefinition? {
        PartyCatalog.party(id: log.partyID)
    }

    @MainActor
    func append(qsos: [QSO], undoManager: UndoManager?) {
        log.qsos.append(contentsOf: qsos)
        let ids = Set(qsos.map(\.id))
        undoManager?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated {
                doc.remove(ids: ids, undoManager: undoManager)
            }
        }
        undoManager?.setActionName("Log Contact")
    }

    @MainActor
    func remove(ids: Set<UUID>, undoManager: UndoManager?) {
        let removed = log.qsos.filter { ids.contains($0.id) }
        log.qsos.removeAll { ids.contains($0.id) }
        undoManager?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated {
                doc.append(qsos: removed, undoManager: undoManager)
            }
        }
        undoManager?.setActionName("Delete Contact")
    }

    @MainActor
    func removeGroup(groupID: UUID, undoManager: UndoManager?) {
        remove(ids: Set(log.qsos.filter { $0.groupID == groupID }.map(\.id)), undoManager: undoManager)
    }

    @MainActor
    func update(qso: QSO, undoManager: UndoManager?) {
        guard let idx = log.qsos.firstIndex(where: { $0.id == qso.id }) else { return }
        let old = log.qsos[idx]
        log.qsos[idx] = qso
        undoManager?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated {
                doc.update(qso: old, undoManager: undoManager)
            }
        }
        undoManager?.setActionName("Edit Contact")
    }

    /// One field changed across many rows — the bulk editor's single mutation.
    ///
    /// Not `update(qso:)` in a loop. That registers one undo step per row, so
    /// reverting a change whose whole purpose was to touch fifteen rows would
    /// cost fifteen ⌘Z presses. One registration, one action name, one press
    /// back. Rows no longer in the log are skipped rather than re-appended —
    /// undo of a *deletion* is `append`'s job.
    @MainActor
    func update(qsos: [QSO], actionName: String, undoManager: UndoManager?) {
        let byID = Dictionary(qsos.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var previous: [QSO] = []
        for idx in log.qsos.indices {
            guard let updated = byID[log.qsos[idx].id] else { continue }
            previous.append(log.qsos[idx])
            log.qsos[idx] = updated
        }
        guard !previous.isEmpty else { return }
        undoManager?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated {
                doc.update(qsos: previous, actionName: actionName, undoManager: undoManager)
            }
        }
        undoManager?.setActionName(actionName)
    }

    /// A spot from either feed — cluster or hub — reached this session.
    /// An observation, not an operator edit, so it registers no undo: ⌘Z
    /// must never clear an integrity record. Direct mutation is the same
    /// dirty-tracking class as the Run/S&P binding, and the flag rides
    /// along with every subsequent save.
    @MainActor
    func noteSpotsUsed() {
        guard !log.usedSpots else { return }
        log.usedSpots = true
    }

    /// "2026-07-25 ALQP KE5CW" — default display name for unsaved logs. A
    /// POTA *activation* is named the way its submission file is —
    /// "2026-07-25-KE5CW@US-1234", the first park naming the outing
    /// (operator report 2, 2026-08-26); a hunter log, a missing callsign,
    /// and every party keep the standard scheme, so no existing log's name
    /// moves.
    nonisolated static func defaultDisplayName(
        partyID: String, callsign: String, date: Date = Date(),
        activatedParks: [String] = [], potaProgram: Bool = false
    ) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        if potaProgram, let park = activatedParks.first, !callsign.isEmpty {
            return "\(f.string(from: date))-\(callsign.uppercased())@\(park.uppercased())"
        }
        var parts = [f.string(from: date), partyID.uppercased()]
        if !callsign.isEmpty { parts.append(callsign.uppercased()) }
        return parts.joined(separator: " ")
    }

    /// The editor's Save. The set is also banked under the log's party, so
    /// the next new log for that party starts from it (`MessageMemory`) —
    /// and undo, which comes back through here, banks the old set again.
    @MainActor
    func updateMessages(_ sets: MessageSets, undoManager: UndoManager?) {
        let old = log.messages
        log.messages = sets
        // Best effort, like the iCloud mirror: the set is safe in the log
        // file whatever happens to the memory, and a failure here must never
        // block the Save that already succeeded.
        do {
            try messageMemory?.remember(sets, for: log.partyID)
        } catch {
            NSLog("MessageMemory: could not remember \(log.partyID)'s messages: \(error)")
        }
        undoManager?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated {
                doc.updateMessages(old, undoManager: undoManager)
            }
        }
        undoManager?.setActionName("Edit Messages")
    }

    @MainActor
    func updateStation(
        _ station: StationProfile,
        location: MyLocation,
        partyID: String,
        exchangeName: String? = nil,
        exchangeMember: String? = nil,
        entryClassID: String? = nil,
        myPotaRefs: [String]? = nil,
        undoManager: UndoManager?
    ) {
        let (oldStation, oldLoc, oldParty) = (log.station, log.myLocation, log.partyID)
        let oldMessages = log.messages
        let oldMode = log.operatingMode
        let oldExchangeName = log.exchangeName
        let oldExchangeMember = log.exchangeMember
        let oldEntryClassID = log.entryClassID
        let oldMyPotaRefs = log.myPotaRefs
        log.station = station
        log.myLocation = location
        log.partyID = partyID
        if let exchangeName {
            log.exchangeName = exchangeName.trimmingCharacters(in: .whitespaces).uppercased()
        }
        if let exchangeMember {
            log.exchangeMember = exchangeMember.trimmingCharacters(in: .whitespaces).uppercased()
        }
        if let entryClassID {
            log.entryClassID = entryClassID.trimmingCharacters(in: .whitespaces)
        }
        // Already grammar-checked by whatever offered them: the picker only
        // ever adds references `PotaRef` accepted.
        if let myPotaRefs {
            log.myPotaRefs = myPotaRefs
        }
        log.setupCompleted = true
        // Macros the operator never edited follow the new party: the set they
        // saved last for it (`MessageMemory`), or its defaults — this is what
        // gives a CQP log {SERIAL} instead of Kansas's {RST}, and a Skeeter
        // Hunt log last year's Skeeter Hunt messages. "Never edited" means
        // equal to the old party's defaults, or to the old party's remembered
        // set: this log's own edits are banked under the old party the moment
        // they are saved, so taking the new party's set loses nothing — the
        // old habit is one setup away. A set matching neither is theirs and
        // is left alone. Undo restores it exactly, below.
        let untouched = oldMessages == MessageSets.defaults(for: ContestCatalog.contest(id: oldParty))
            || oldMessages == messageMemory?.messages(for: oldParty)
        if untouched {
            log.messages = messageMemory?.messages(for: partyID)
                ?? MessageSets.defaults(for: ContestCatalog.contest(id: partyID))
        }
        // Crossing the state line is the one location change that implies a
        // different operating style — the in-state station is the multiplier
        // being chased and runs, the out-of-state station chases. Any other
        // edit (a callsign typo, a different county, a different state) must
        // not overwrite a deliberate mid-contest switch.
        if oldLoc.isInState != location.isInState {
            log.operatingMode = log.derivedOperatingMode
        }
        AppSettings.shared.lastStationProfile = station
        undoManager?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated {
                doc.updateStation(
                    oldStation, location: oldLoc, partyID: oldParty,
                    exchangeName: oldExchangeName, exchangeMember: oldExchangeMember,
                    entryClassID: oldEntryClassID, myPotaRefs: oldMyPotaRefs,
                    undoManager: undoManager
                )
                // Restore the macros and the mode exactly afterwards, whatever
                // the nested call's own re-derivation decided: both are
                // conditionally re-derived above, so without this, undo would
                // be a second guess rather than an exact inverse — and for the
                // mode, that guess is silent, because the value it lands on
                // is often the same one the operator chose by hand.
                // `setupCompleted` is deliberately not restored — a draft that
                // has been through Contest Setup stays through it.
                doc.log.messages = oldMessages
                doc.log.operatingMode = oldMode
            }
        }
        undoManager?.setActionName("Change Station Setup")
    }
}
