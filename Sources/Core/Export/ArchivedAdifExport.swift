import Foundation

/// ADIF export of an archived contest, for the dashboard's per-row action.
/// The record's saved .qplog is the source of truth — the archive's embedded
/// QSO copy can lag a save synced from another Mac — so the export reads the
/// same file the row's Return/double-click would reopen, and is unavailable
/// when that file is gone.
extension AdifExporter {

    enum ArchiveFailure: Error, Equatable {
        /// No source file recorded, no logs folder configured, or the file
        /// is no longer in the folder.
        case logFileMissing
        /// `PartyCatalog` has no rules for the record's party id.
        case partyNotInstalled
        /// The file is there but does not decode as a contest log.
        case logUnreadable
    }

    /// What the save panel needs: text plus a default filename that keeps
    /// the saved log's own name ("2026-08-29 KSQP KE5CW.adi").
    struct ArchivedExport: Equatable {
        let fileName: String
        let text: String
    }

    static func exportArchived(record: ContestRecord, folder: URL?) throws -> ArchivedExport {
        guard let name = record.sourceFileName, let folder,
              let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else {
            throw ArchiveFailure.logFileMissing
        }
        guard let party = PartyCatalog.party(id: record.partyID) else {
            throw ArchiveFailure.partyNotInstalled
        }
        guard let log = try? ContestLog.decode(from: data) else {
            throw ArchiveFailure.logUnreadable
        }
        return ArchivedExport(
            fileName: (name as NSString).deletingPathExtension + ".adi",
            text: export(log: log, party: party)
        )
    }
}
