import Foundation

enum ArchiveStoreError: Error, LocalizedError {
    /// The file exists but doesn't decode. The store never overwrites it —
    /// the last good bytes are the user's to recover.
    case corruptArchive(url: URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .corruptArchive(let url, let underlying):
            "Contest history file '\(url.lastPathComponent)' can't be read " +
            "(\(underlying.localizedDescription)). It was left untouched."
        }
    }
}

/// Coordinated read/merge/write access to the one-file contest history in a
/// given folder (the CloudMirror logs folder in production, a temp dir in
/// tests). Every write re-reads the disk under coordination first, so a
/// record another Mac synced in while we weren't looking is merged, never
/// clobbered.
struct ArchiveStore: Sendable {
    let folder: URL

    static let fileName = "Contest History.qphistory"

    var fileURL: URL {
        folder.appendingPathComponent(Self.fileName)
    }

    func load() throws -> ContestArchive {
        var coordinationError: NSError?
        var outcome: Result<ContestArchive, Error> = .success(.empty)
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: fileURL, options: [], error: &coordinationError
        ) { url in
            outcome = Result { try Self.read(url) }
        }
        if let coordinationError { throw coordinationError }
        return try outcome.get()
    }

    /// Merge one record into the on-disk archive. `rebuildSnapshot` runs when
    /// the disk merge grows the QSO set beyond what the winning side's
    /// snapshot described (see `ContestArchive.upserting`).
    @discardableResult
    func upsert(
        _ record: ContestRecord,
        rebuildSnapshot: (ContestRecord) -> ScoreSnapshot? = { _ in nil }
    ) throws -> ContestArchive {
        try mutate { $0.upserting(record, rebuildSnapshot: rebuildSnapshot) }
    }

    /// Fold a whole archive into the on-disk one — the import and
    /// conflict-version paths.
    @discardableResult
    func mergeIn(
        _ other: ContestArchive,
        rebuildSnapshot: (ContestRecord) -> ScoreSnapshot? = { _ in nil }
    ) throws -> ContestArchive {
        try mutate { $0.merging(other, rebuildSnapshot: rebuildSnapshot) }
    }

    private func mutate(_ transform: (ContestArchive) -> ContestArchive) throws -> ContestArchive {
        var coordinationError: NSError?
        var outcome: Result<ContestArchive, Error> = .success(.empty)
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: fileURL, options: .forMerging, error: &coordinationError
        ) { url in
            outcome = Result {
                let current = try Self.read(url)
                let next = transform(current)
                try next.encoded().write(to: url, options: .atomic)
                return next
            }
        }
        if let coordinationError { throw coordinationError }
        return try outcome.get()
    }

    private static func read(_ url: URL) throws -> ContestArchive {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return .empty
        }
        let data = try Data(contentsOf: url)
        do {
            return try ContestArchive.decode(from: data)
        } catch {
            throw ArchiveStoreError.corruptArchive(url: url, underlying: error)
        }
    }
}
