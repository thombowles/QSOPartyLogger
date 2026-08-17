import Foundation

/// Where a downloaded `cty.dat`'s label changes are kept between launches.
///
/// Deliberately tiny and deliberately *only labels*: entity code → prefix, for
/// the handful of entities whose displayed prefix has moved since the bundled
/// table was generated. Nothing here can add an entity or change a score — see
/// [`DXCCLabelRefresh`](DXCCLabelRefresh.swift) for why that boundary exists.
enum DXCCLabelStore {

    struct Overlay: Codable, Equatable, Sendable {
        /// The `Last-Modified` of the cty.dat these came from — the only
        /// version stamp that file has.
        let release: String
        let checkedAt: Date
        /// Entity code → label. Empty means "checked, nothing moved".
        let labels: [String: String]
    }

    /// `~/Library/Application Support/QSOPartyLogger/dxcc_labels.json`,
    /// alongside the user's own party overrides.
    static var overlayURL: URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        return base
            .appendingPathComponent("QSOPartyLogger", isDirectory: true)
            .appendingPathComponent("dxcc_labels.json")
    }

    static func load(at url: URL?) -> Overlay? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Overlay.self, from: data)
    }

    static func loadLabels(at url: URL?) -> [String: String]? {
        load(at: url)?.labels
    }

    @discardableResult
    static func save(_ overlay: Overlay, to url: URL?) -> Bool {
        guard let url else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(overlay) else { return false }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
