import Foundation

/// The on-disk cache of the downloaded park list: the bytes exactly as the
/// server sent them plus a meta sidecar, in the app's own Application
/// Support folder — a temp dir in tests. `SCPStore`'s shape and failure
/// posture: the cache is a convenience, and a missing or unreadable sidecar
/// never hides a readable file.
struct PotaParkStore: Sendable {
    let folder: URL

    /// `~/Library/Application Support/QSOPartyLogger/POTA`
    /// (container-relative when sandboxed), beside the SCP cache.
    static var defaultFolder: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QSOPartyLogger/POTA", isDirectory: true)
    }

    /// `SCPStore.Meta` minus the release token: api.pota.app answers HEAD
    /// with 403 (docs/research/pota/SOURCES.md), so there is no freshness
    /// header to hold and the dates are the whole bookkeeping.
    struct Meta: Codable, Equatable, Sendable {
        let fetchedAt: Date
        var lastCheckedAt: Date
    }

    struct Cached: Equatable, Sendable {
        let directory: PotaParkDirectory
        let meta: Meta?
    }

    var fileURL: URL { folder.appendingPathComponent("parks-US.json") }
    var metaURL: URL { folder.appendingPathComponent("parks-US.meta.json") }

    func loadCached() -> Cached? {
        guard let data = try? Data(contentsOf: fileURL),
              let directory = PotaParkDirectory.parse(data: data)
        else { return nil }
        return Cached(directory: directory, meta: loadMeta())
    }

    func loadMeta() -> Meta? {
        guard let data = try? Data(contentsOf: metaURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Meta.self, from: data)
    }

    /// Install a download: bytes exactly as served, sidecar alongside, both
    /// atomic. The caller has already parsed and verified the bytes — the
    /// store never installs what it was not handed.
    func save(data: Data, meta: Meta) throws {
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(meta).write(to: metaURL, options: .atomic)
    }
}
