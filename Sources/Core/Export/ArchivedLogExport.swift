import Foundation

/// Exports of an archived contest, for the dashboard's per-row actions.
/// The record's saved .qplog is the source of truth — the archive's embedded
/// QSO copy can lag a save synced from another Mac — so every format reads
/// the same file the row's Return/double-click would reopen, and none is
/// available when that file is gone.
enum ArchivedLogExport {

    enum Failure: Error, Equatable {
        /// No source file recorded, no logs folder configured, or the file
        /// is no longer in the folder.
        case logFileMissing
        /// `ContestCatalog` has no rules for the record's contest id. (The
        /// case keeps its name: the dashboard and its tests read it.)
        case partyNotInstalled
        /// The file is there but does not decode as a contest log.
        case logUnreadable
    }

    /// What the save panel needs: text plus a default filename that keeps
    /// the saved log's own name ("2026-08-29 KSQP KE5CW.adi").
    struct Export: Equatable {
        let fileName: String
        let text: String
    }

    static func adif(record: ContestRecord, folder: URL?) throws -> Export {
        let loaded = try load(record: record, folder: folder)
        return Export(
            fileName: loaded.baseName + ".adi",
            text: AdifExporter.export(log: loaded.log, contest: loaded.contest)
        )
    }

    /// Cabrillo carries a CLAIMED-SCORE, recomputed here from the saved log
    /// under the rules installed today — the same figure reopening the log
    /// and exporting from the document window would claim. The archived
    /// snapshot is deliberately not used: it freezes history for the
    /// dashboard, but a submission should be scored by the current rules.
    static func cabrillo(record: ContestRecord, folder: URL?) throws -> Export {
        let loaded = try load(record: record, folder: folder)
        return Export(
            fileName: loaded.baseName + ".log",
            text: CabrilloExporter.export(
                log: loaded.log,
                contest: loaded.contest,
                score: ScoreEngine.score(log: loaded.log, contest: loaded.contest)
            )
        )
    }

    private static func load(
        record: ContestRecord, folder: URL?
    ) throws -> (log: ContestLog, contest: ContestDefinition, baseName: String) {
        guard let name = record.sourceFileName, let folder,
              let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else {
            throw Failure.logFileMissing
        }
        guard let contest = ContestCatalog.contest(id: record.partyID) else {
            throw Failure.partyNotInstalled
        }
        guard let log = try? ContestLog.decode(from: data) else {
            throw Failure.logUnreadable
        }
        return (log, contest, (name as NSString).deletingPathExtension)
    }
}
