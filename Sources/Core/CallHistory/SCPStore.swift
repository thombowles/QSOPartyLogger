import Foundation

/// The on-disk cache of the downloaded MASTER.SCP: the file exactly as the
/// server sent it plus a `MASTER.meta.json` sidecar (which release it is
/// and when it was fetched), in the app's own Application Support folder —
/// a temp dir in tests. `CallHistoryStore`'s shape, minus the party key:
/// there is one super check partial database for every contest.
///
/// Failure posture: the cache is a convenience. A missing or unreadable
/// sidecar never hides a readable file — matching keeps working and only
/// the staleness bookkeeping resets.
struct SCPStore: Sendable {
    let folder: URL

    /// `~/Library/Application Support/QSOPartyLogger/SCP`
    /// (container-relative when sandboxed), beside the call history cache.
    static var defaultFolder: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QSOPartyLogger/SCP", isDirectory: true)
    }

    /// What is known about the cached file beyond its contents.
    struct Meta: Codable, Equatable, Sendable {
        /// The server's `Last-Modified` for the installed file — the token
        /// the next HEAD is compared against. Empty when the server sent
        /// none, which reads as "always stale" rather than "current".
        let sourceLastModified: String
        let fetchedAt: Date
        /// When upstream was last consulted — the 24 h throttle's clock,
        /// advanced on every check including ones that download nothing.
        var lastCheckedAt: Date
    }

    /// The cached file, parsed, with whatever bookkeeping survives.
    struct Cached: Equatable, Sendable {
        let database: SCPDatabase
        let meta: Meta?
    }

    var fileURL: URL { folder.appendingPathComponent("MASTER.SCP") }
    var metaURL: URL { folder.appendingPathComponent("MASTER.meta.json") }

    func loadCached() -> Cached? {
        guard let data = try? Data(contentsOf: fileURL),
              let database = SCPDatabase.parse(data: data)
        else { return nil }
        return Cached(database: database, meta: loadMeta())
    }

    func loadMeta() -> Meta? {
        guard let data = try? Data(contentsOf: metaURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Meta.self, from: data)
    }

    /// Install a downloaded release: bytes exactly as served, sidecar
    /// alongside, both atomic. The caller has already parsed and verified
    /// the bytes — the store never installs what it was not handed.
    func save(data: Data, meta: Meta) throws {
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        try write(meta: meta)
    }

    /// Upstream was consulted and showed nothing newer — advance the
    /// throttle clock without touching the file. A missing sidecar is left
    /// missing: there is nothing truthful to write about an unknown
    /// release.
    func touchLastChecked(at date: Date) throws {
        guard var meta = loadMeta() else { return }
        meta.lastCheckedAt = date
        try write(meta: meta)
    }

    private func write(meta: Meta) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(meta).write(to: metaURL, options: .atomic)
    }
}
