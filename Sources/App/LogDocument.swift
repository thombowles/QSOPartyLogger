import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var qplog: UTType {
        UTType(exportedAs: "org.b5n.qsopartylogger.log")
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
    /// The last station profile is read directly from UserDefaults (thread-safe)
    /// rather than through the @MainActor `AppSettings.shared`.
    init() {
        var initial = ContestLog(partyID: "ksqp")
        initial.station = LogDocument.savedStationProfile() ?? StationProfile()
        self.log = initial
    }

    nonisolated static func savedStationProfile() -> StationProfile? {
        UserDefaults.standard.data(forKey: "lastStationProfile")
            .flatMap { try? JSONDecoder().decode(StationProfile.self, from: $0) }
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.log = try ContestLog.decode(from: data)
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
        return FileWrapper(regularFileWithContents: data)
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
    func updateStation(_ station: StationProfile, location: MyLocation, partyID: String, undoManager: UndoManager?) {
        let (oldStation, oldLoc, oldParty) = (log.station, log.myLocation, log.partyID)
        log.station = station
        log.myLocation = location
        log.partyID = partyID
        log.setupCompleted = true
        AppSettings.shared.lastStationProfile = station
        undoManager?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated {
                doc.updateStation(oldStation, location: oldLoc, partyID: oldParty, undoManager: undoManager)
            }
        }
        undoManager?.setActionName("Change Station Setup")
    }
}
