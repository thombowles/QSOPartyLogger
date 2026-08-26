import Foundation

/// The logs folder read as the contest history: every set-up `.qplog` with
/// QSOs is one contest, one level deep. The logs *are* the history — nothing
/// is copied anywhere, an entry exists exactly while its log is in the
/// folder, and a log dragged into a subfolder is kept without counting.
struct LogFolder: Sendable {
    /// The logs folder itself (the iCloud folder in the app, a temp folder
    /// in tests).
    let url: URL

    static let fileExtension = "qplog"

    /// Two files for one contest — a copy, an iCloud "2" duplicate. The
    /// later-modified one is shown; the others are named so the operator
    /// can tidy up.
    struct Duplicate: Equatable, Sendable {
        let identity: ContestRecord.Identity
        let shown: String
        let others: [String]
    }

    struct History: Equatable, Sendable {
        var archive: ContestArchive
        var duplicates: [Duplicate]
        /// Files that didn't decode as logs, by name — skipped, never touched.
        var unreadable: [String]
        /// iCloud placeholders not yet downloaded on this Mac; a download was
        /// requested for each.
        var downloading: Int

        static let empty = History(archive: .empty, duplicates: [], unreadable: [], downloading: 0)
    }

    /// Read every log in the folder. A missing folder is empty, not an error.
    func history() throws -> History {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false)).sorted()
        } catch let error as NSError where error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError {
            return .empty
        }

        var candidates: [ContestRecord.Identity: [ContestRecord]] = [:]
        var unreadable: [String] = []
        var downloading = 0

        for name in names {
            let fileURL = url.appendingPathComponent(name)
            if Self.isPlaceholder(name) {
                downloading += 1
                try? FileManager.default.startDownloadingUbiquitousItem(at: Self.placeholderTarget(fileURL))
                continue
            }
            guard Self.isLogFile(name) else { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false), isDirectory: &isDirectory),
                  !isDirectory.boolValue else { continue }

            var coordinationError: NSError?
            var outcome: Result<ContestRecord?, Error> = .success(nil)
            NSFileCoordinator(filePresenter: nil).coordinate(
                readingItemAt: fileURL, options: [], error: &coordinationError
            ) { fileURL in
                outcome = Result { try Self.record(at: fileURL) }
            }
            if let coordinationError { throw coordinationError }
            switch outcome {
            case .success(let record?):
                candidates[record.identity, default: []].append(record)
            case .success(nil):
                continue
            case .failure:
                unreadable.append(name)
            }
        }

        var records: [ContestRecord] = []
        var duplicates: [Duplicate] = []
        for (identity, copies) in candidates {
            // Later-modified first; ties keep name order (already sorted).
            let ordered = copies.enumerated().sorted {
                if $0.element.updatedAt != $1.element.updatedAt {
                    return $0.element.updatedAt > $1.element.updatedAt
                }
                return $0.offset < $1.offset
            }.map(\.element)
            records.append(ordered[0])
            if ordered.count > 1 {
                duplicates.append(Duplicate(
                    identity: identity,
                    shown: ordered[0].sourceFileName ?? "",
                    others: ordered.dropFirst().map { $0.sourceFileName ?? "" }
                ))
            }
        }
        return History(
            archive: ContestArchive(records: ContestArchive.canonicalOrder(records)),
            duplicates: duplicates.sorted { $0.shown < $1.shown },
            unreadable: unreadable,
            downloading: downloading
        )
    }

    // MARK: One file

    /// nil for a draft (not set up, no QSOs, no callsign); throws for a file
    /// that doesn't decode as a log.
    static func record(at fileURL: URL) throws -> ContestRecord? {
        let log = try ContestLog.decode(from: try Data(contentsOf: fileURL))
        guard log.setupCompleted else { return nil }
        let modified = (try? fileURL.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate) ?? Date()
        let contest = ContestCatalog.contest(id: log.partyID)
        let (snapshot, origin) = score(for: log, contests: { _ in contest })
        return ContestRecord.make(
            from: log,
            snapshot: snapshot,
            scoreOrigin: origin,
            updatedAt: modified,
            sourceFileName: fileURL.lastPathComponent,
            program: contest?.family == .program
        )
    }

    /// The log's own snapshot when it carries figures — the frozen "what I
    /// claimed" — else one computed now with the rules installed here (a
    /// log from an older build, or one saved on a Mac without this contest).
    static func score(
        for log: ContestLog,
        contests: (String) -> ContestDefinition? = { ContestCatalog.contest(id: $0) }
    ) -> (ScoreSnapshot, ContestRecord.ScoreOrigin) {
        if let saved = log.scoreSnapshot, saved.figures != nil {
            return (saved, .savedWithLog)
        }
        return (ScoreSnapshot.best(for: log, contests: contests), .computedNow)
    }

    // MARK: Names

    static func isLogFile(_ name: String) -> Bool {
        !name.hasPrefix(".") && name.lowercased().hasSuffix(".\(fileExtension)")
    }

    /// `.<name>.qplog.icloud` — iCloud's stand-in for a log not downloaded here.
    static func isPlaceholder(_ name: String) -> Bool {
        name.hasPrefix(".") && name.lowercased().hasSuffix(".\(fileExtension).icloud")
    }

    /// The real file a placeholder stands for.
    static func placeholderTarget(_ placeholder: URL) -> URL {
        var name = placeholder.lastPathComponent
        name.removeFirst()
        name.removeLast(".icloud".count)
        return placeholder.deletingLastPathComponent().appendingPathComponent(name)
    }
}
