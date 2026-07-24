import Foundation

/// Recently-used DX cluster nodes, stored as "host:port" strings.
enum ClusterHistory {
    static let maxEntries = 8

    static func entry(host: String, port: Int) -> String {
        "\(host.trimmingCharacters(in: .whitespaces)):\(port)"
    }

    static func parse(_ entry: String) -> (host: String, port: UInt16)? {
        let parts = entry.split(separator: ":")
        guard parts.count == 2,
              let port = UInt16(parts[1]),
              !parts[0].isEmpty else { return nil }
        return (String(parts[0]), port)
    }

    /// Most recent first, case-insensitively de-duplicated, capped.
    static func adding(_ entry: String, to list: [String]) -> [String] {
        let trimmed = entry.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return list }
        var out = list.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        out.insert(trimmed, at: 0)
        return Array(out.prefix(maxEntries))
    }
}
