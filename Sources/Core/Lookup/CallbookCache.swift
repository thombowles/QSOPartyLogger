import Foundation

/// On-disk lookup cache — one JSON file of records keyed by call, 30-day
/// TTL, LRU-by-fetch-date cap (spec 2026-08-25 decision 8). Best-effort on
/// purpose: a cache that cannot read or write behaves as empty and costs
/// one fresh lookup, never an error in the entry path.
final class CallbookCache {
    static let defaultDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("QSOPartyLogger/Callbook", isDirectory: true)

    static let ttl: TimeInterval = 30 * 86_400

    private let fileURL: URL
    private let cap: Int
    private var records: [String: CallbookRecord]

    init(directory: URL = CallbookCache.defaultDirectory, cap: Int = 5000) {
        self.fileURL = directory.appendingPathComponent("cache.json")
        self.cap = cap
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.records = (try? decoder.decode(
            [String: CallbookRecord].self,
            from: Data(contentsOf: fileURL))) ?? [:]
    }

    func record(for call: String, now: Date = Date()) -> CallbookRecord? {
        guard let hit = records[call.uppercased()],
              now.timeIntervalSince(hit.fetchedAt) < Self.ttl else { return nil }
        return hit
    }

    func store(_ record: CallbookRecord) {
        records[record.call.uppercased()] = record
        while records.count > cap,
              let oldest = records.min(by: { $0.value.fetchedAt < $1.value.fetchedAt }) {
            records.removeValue(forKey: oldest.key)
        }
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
