import Foundation

/// Keeps the one-file contest history up to date: debounces the document
/// save-path into at most one read-merge-write per pause, imports existing
/// `.qplog` files, migrates a local archive into the iCloud folder when one
/// is chosen, and resolves iCloud conflict versions by merge.
actor ContestHistorian {

    static let shared = ContestHistorian()

    private let folderOverride: URL?
    private let debounceNanos: UInt64
    private var pending: [ContestRecord.Identity: Task<Void, Never>] = [:]
    private(set) var writeCount = 0

    init(folderOverride: URL? = nil, debounceNanos: UInt64 = 2_000_000_000) {
        self.folderOverride = folderOverride
        self.debounceNanos = debounceNanos
    }

    // MARK: Folder resolution

    /// The synced logs folder when one is chosen, else Application Support —
    /// history works before iCloud is configured and merges over when it is.
    nonisolated static func resolveFolder() -> URL {
        CloudMirror.activeFolder() ?? applicationSupportFolder
    }

    nonisolated static var applicationSupportFolder: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QSOPartyLogger", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private var store: ArchiveStore {
        ArchiveStore(folder: folderOverride ?? Self.resolveFolder())
    }

    // MARK: Save-path entry

    /// Fire-and-forget entry point for the document save path. Inert under
    /// XCTest so unit tests never write into the real history.
    nonisolated func noteSaved(log: ContestLog, sourceFileName: String?) {
        guard NSClassFromString("XCTestCase") == nil else { return }
        Task { await self.archive(log: log, sourceFileName: sourceFileName) }
    }

    /// Schedule an archive update for this log, debounced per contest so
    /// autosave-per-QSO becomes one write per pause.
    func archive(log: ContestLog, sourceFileName: String?) {
        guard log.setupCompleted else { return }
        guard let record = ContestRecord.make(
            from: log,
            snapshot: Self.snapshot(for: log),
            updatedAt: Date(),
            sourceFileName: sourceFileName
        ) else { return }

        pending[record.identity]?.cancel()
        pending[record.identity] = Task { [debounceNanos] in
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            await self.write(record)
        }
    }

    /// Await every pending debounced write (tests, app termination).
    func drain() async {
        while !pending.isEmpty {
            let tasks = Array(pending.values)
            pending.removeAll()
            for task in tasks {
                await task.value
            }
        }
    }

    private func write(_ record: ContestRecord) {
        do {
            try store.upsert(record, rebuildSnapshot: Self.rebuildSnapshot)
            writeCount += 1
        } catch {
            NSLog("ContestHistorian: archive write failed: \(error.localizedDescription)")
        }
    }

    // MARK: Import

    /// Decode every `.qplog` in `folder` and fold it into the archive.
    /// Empty drafts are skipped; undecodable files are reported by name.
    func importLogs(from folder: URL) -> (imported: Int, failed: [String]) {
        let urls = ((try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? [])
            .filter { $0.pathExtension.lowercased() == "qplog" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var records: [ContestRecord] = []
        var failed: [String] = []
        for url in urls {
            do {
                let log = try ContestLog.decode(from: try Data(contentsOf: url))
                // The file's own modification date orders two Macs' copies.
                let modified = (try? url.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate) ?? Date()
                if let record = ContestRecord.make(
                    from: log,
                    snapshot: Self.snapshot(for: log),
                    updatedAt: modified,
                    sourceFileName: url.lastPathComponent
                ) {
                    records.append(record)
                }
            } catch {
                failed.append(url.lastPathComponent)
            }
        }

        guard !records.isEmpty else { return (0, failed) }
        var incoming = ContestArchive.empty
        for record in records {
            incoming = incoming.upserting(record, rebuildSnapshot: Self.rebuildSnapshot)
        }
        do {
            try store.mergeIn(incoming, rebuildSnapshot: Self.rebuildSnapshot)
            writeCount += 1
        } catch {
            NSLog("ContestHistorian: import failed: \(error.localizedDescription)")
            return (0, failed)
        }
        return (records.count, failed)
    }

    // MARK: Migration + conflicts

    /// Fold a local (Application Support) archive into the chosen folder's
    /// archive, then mark the local file migrated so it never re-merges.
    static func migrate(localFolder: URL, into folder: URL) throws -> Bool {
        guard localFolder.standardizedFileURL != folder.standardizedFileURL else { return false }
        let localStore = ArchiveStore(folder: localFolder)
        let localFile = localStore.fileURL
        guard FileManager.default.fileExists(atPath: localFile.path(percentEncoded: false)) else {
            return false
        }
        let local = try localStore.load()
        try ArchiveStore(folder: folder).mergeIn(local, rebuildSnapshot: rebuildSnapshot)
        let parked = localFile.appendingPathExtension("migrated")
        try? FileManager.default.removeItem(at: parked)
        try FileManager.default.moveItem(at: localFile, to: parked)
        return true
    }

    /// Fold iCloud conflict versions into the file by merge — possible
    /// because record merge is commutative — then mark them resolved.
    func resolveCloudConflicts() -> Bool {
        let store = self.store
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: store.fileURL),
              !versions.isEmpty else { return false }
        var merged = false
        for version in versions {
            if let data = try? Data(contentsOf: version.url),
               let archive = try? ContestArchive.decode(from: data),
               (try? store.mergeIn(archive, rebuildSnapshot: Self.rebuildSnapshot)) != nil {
                merged = true
            }
            version.isResolved = true
        }
        if merged { writeCount += 1 }
        try? NSFileVersion.removeOtherVersionsOfItem(at: store.fileURL)
        return merged
    }

    // MARK: Snapshots

    /// Engine snapshot when the party is installed, counts-only otherwise.
    nonisolated static func snapshot(for log: ContestLog) -> ScoreSnapshot {
        if let party = PartyCatalog.party(id: log.partyID) {
            ScoreSnapshot.make(log: log, party: party)
        } else {
            ScoreSnapshot.countsOnly(log: log)
        }
    }

    /// Recompute after a merge grew a record's QSO set; nil (keep the newer
    /// side's snapshot) when the party isn't installed here.
    nonisolated static func rebuildSnapshot(_ record: ContestRecord) -> ScoreSnapshot? {
        guard let party = PartyCatalog.party(id: record.partyID) else { return nil }
        var log = ContestLog(partyID: record.partyID)
        log.station = record.station
        log.myLocation = record.myLocation
        log.qsos = record.qsos
        return ScoreSnapshot.make(log: log, party: party)
    }
}
