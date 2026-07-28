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
    typealias Snapshot = ContestLog

    static var readableContentTypes: [UTType] { [.qplog] }

    var log: ContestLog

    /// Where this document currently lives on disk (tracked by the UI from
    /// the NSDocument bridge; nil while still an unsaved draft). Used to skip
    /// redundant iCloud mirroring for documents stored in the logs folder.
    @ObservationIgnored var knownFileURL: URL?

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
    /// not touch the filesystem, and `PartyCatalog.party(id:)` re-reads the
    /// bundle and the user parties folder on every call.
    nonisolated static func upgradingUntouchedMessages(_ log: ContestLog) -> ContestLog {
        guard log.messages == MessageSets.standard else { return log }
        var upgraded = log
        upgraded.messages = MessageSets.defaults(for: PartyCatalog.party(id: log.partyID))
        return upgraded
    }

    func snapshot(contentType: UTType) throws -> ContestLog {
        log
    }

    func fileWrapper(snapshot: ContestLog, configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try snapshot.encoded()
        // Best-effort iCloud mirror on every save; never blocks or fails the
        // primary write. Documents that already live in the logs folder ARE
        // the synced copy — mirroring them would trigger "file changed by
        // another application" churn.
        if CloudMirror.isEnabled, snapshot.setupCompleted, !CloudMirror.folderContains(knownFileURL) {
            let name = LogDocument.mirrorFileName(for: snapshot)
            DispatchQueue.global(qos: .utility).async {
                CloudMirror.mirror(data: data, fileName: name)
            }
        }
        // Keep the contest history archive current on every save (debounced
        // per contest inside the historian; value snapshot, so safe here).
        ContestHistorian.shared.noteSaved(
            log: snapshot,
            sourceFileName: knownFileURL?.lastPathComponent
                ?? LogDocument.mirrorFileName(for: snapshot) + ".qplog"
        )
        return FileWrapper(regularFileWithContents: data)
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
            date: log.qsos.map(\.timestampUTC).min() ?? Date()
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

    /// "2026-07-25 ALQP KE5CW" — default display name for unsaved logs.
    nonisolated static func defaultDisplayName(partyID: String, callsign: String, date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        var parts = [f.string(from: date), partyID.uppercased()]
        if !callsign.isEmpty { parts.append(callsign.uppercased()) }
        return parts.joined(separator: " ")
    }

    @MainActor
    func updateMessages(_ sets: MessageSets, undoManager: UndoManager?) {
        let old = log.messages
        log.messages = sets
        undoManager?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated {
                doc.updateMessages(old, undoManager: undoManager)
            }
        }
        undoManager?.setActionName("Edit CW Messages")
    }

    @MainActor
    func updateStation(
        _ station: StationProfile,
        location: MyLocation,
        partyID: String,
        exchangeName: String? = nil,
        undoManager: UndoManager?
    ) {
        let (oldStation, oldLoc, oldParty) = (log.station, log.myLocation, log.partyID)
        let oldMessages = log.messages
        let oldMode = log.operatingMode
        let oldExchangeName = log.exchangeName
        log.station = station
        log.myLocation = location
        log.partyID = partyID
        if let exchangeName {
            log.exchangeName = exchangeName.trimmingCharacters(in: .whitespaces).uppercased()
        }
        log.setupCompleted = true
        // Macros the operator never edited follow the new party's exchange
        // shape — this is what gives a CQP log {SERIAL} instead of Kansas's
        // {RST}. Anything customised is theirs and is left alone.
        if oldMessages == MessageSets.defaults(for: PartyCatalog.party(id: oldParty)) {
            log.messages = MessageSets.defaults(for: PartyCatalog.party(id: partyID))
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
                    exchangeName: oldExchangeName, undoManager: undoManager
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
