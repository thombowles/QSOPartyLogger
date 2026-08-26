import Foundation

/// One park from POTA's program list — the subset of api.pota.app's
/// per-program payload the app uses (verified 2026-08-05; entry shape banked
/// in docs/research/pota/SOURCES.md). Upstream's activation counters
/// (attempts, activations, qsos) are ignored by not being declared.
struct PotaPark: Codable, Equatable, Hashable, Sendable, Identifiable {
    let reference: String
    let name: String
    /// Every entry carried coordinates on the verification date; optional
    /// anyway, so an upstream null tomorrow costs one park its place in the
    /// nearest list rather than costing the whole file its parse.
    let latitude: Double?
    let longitude: Double?
    let grid: String?
    /// Upstream's location tag, e.g. "US-TX" — what keeps two same-named
    /// parks in different states tellable apart, and what makes a search for
    /// "lake tx" work.
    let locationDesc: String?

    /// The single state/province a locationDesc names — "US-ME" → "ME",
    /// "CA-AB" → "AB" — or nil where the park spans several ("US-TN,US-NC"):
    /// an ambiguous park cannot claim a side, and the State offer falls
    /// through to the next source (operator request, 2026-08-25).
    static func singleState(fromLocationDesc desc: String?) -> String? {
        guard let desc, !desc.contains(",") else { return nil }
        let halves = desc.uppercased().split(separator: "-", maxSplits: 1)
        guard halves.count == 2, !halves[1].isEmpty else { return nil }
        return String(halves[1])
    }

    var id: String { reference }
}
