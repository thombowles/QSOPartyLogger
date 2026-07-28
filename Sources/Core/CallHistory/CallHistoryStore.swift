import Foundation

/// The on-disk cache of downloaded call history files: one `<partyID>.txt`
/// (the file exactly as the site served it) plus one `<partyID>.meta.json`
/// (which revision it is and when it was fetched), in the app's own
/// Application Support folder — a temp dir in tests.
///
/// The combined May file is cached once per party it serves; five ~60 KB
/// copies beat a shared-cache coupling.
///
/// Failure posture: the cache is a convenience. A missing or unreadable meta
/// never hides a readable file — prefill keeps working and only the
/// staleness bookkeeping resets.
struct CallHistoryStore: Sendable {
    let folder: URL

    /// `~/Library/Application Support/QSOPartyLogger/CallHistory`
    /// (container-relative when sandboxed), beside the user parties folder.
    static var defaultFolder: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QSOPartyLogger/CallHistory", isDirectory: true)
    }

    /// What is known about a cached file beyond its contents.
    struct Meta: Codable, Equatable, Sendable {
        /// "QSOP_AL-2026-002.txt" — compared against the listing to decide
        /// whether a newer revision exists.
        let sourceFileName: String
        /// The listing's date column for that revision, as printed.
        let listedDate: String
        let fetchedAt: Date
        /// When the listing was last consulted — the 24 h throttle's clock,
        /// advanced on every check including ones that download nothing.
        var lastCheckedAt: Date
    }

    /// A cached file, parsed, with whatever bookkeeping survives. `meta` is
    /// `nil` when the sidecar is missing or unreadable — the text still
    /// serves prefill; only staleness resets.
    struct Cached: Equatable, Sendable {
        let parsed: CallHistoryFile.Parsed
        let meta: Meta?
    }

    func fileURL(partyID: String) -> URL {
        folder.appendingPathComponent("\(partyID).txt")
    }

    func metaURL(partyID: String) -> URL {
        folder.appendingPathComponent("\(partyID).meta.json")
    }

    func loadCached(partyID: String) -> Cached? {
        guard let data = try? Data(contentsOf: fileURL(partyID: partyID)),
              let parsed = CallHistoryFile.parse(data: data)
        else { return nil }
        return Cached(parsed: parsed, meta: loadMeta(partyID: partyID))
    }

    func loadMeta(partyID: String) -> Meta? {
        guard let data = try? Data(contentsOf: metaURL(partyID: partyID)) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Meta.self, from: data)
    }

    /// Install a downloaded revision: bytes exactly as served, sidecar
    /// alongside, both atomic. The caller has already parsed and verified
    /// the bytes — the store never installs what it was not handed.
    func save(partyID: String, data: Data, meta: Meta) throws {
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true)
        try data.write(to: fileURL(partyID: partyID), options: .atomic)
        try write(meta: meta, partyID: partyID)
    }

    /// The listing was consulted and showed nothing newer — advance the
    /// throttle clock without touching the file. A missing sidecar is left
    /// missing: there is nothing truthful to write about an unknown revision.
    func touchLastChecked(partyID: String, at date: Date) throws {
        guard var meta = loadMeta(partyID: partyID) else { return }
        meta.lastCheckedAt = date
        try write(meta: meta, partyID: partyID)
    }

    private func write(meta: Meta, partyID: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(meta).write(
            to: metaURL(partyID: partyID), options: .atomic)
    }
}
