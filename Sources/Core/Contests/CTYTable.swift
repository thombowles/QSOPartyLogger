import Foundation

/// AD1C's Big CTY `cty.csv`, the authority for callsign → DXCC entity, CQ and
/// ITU zone, continent and WAE-only status (spec §1.6; constitution Article 1
/// as amended). Bundled under `Resources/CTY/` with `VERSION.txt`; refreshed
/// by the CTY client and applied at launch only.
struct CTYTable: Sendable {
    struct Entity: Equatable, Sendable {
        let name: String
        let primaryPrefix: String
        /// The ADIF/DXCC entity code the file gives. A WAE-only record (`*`
        /// in the file) carries its *parent* entity's code — Sicily is 248
        /// like Italy — so use `waeOnly` to tell them apart; nil only where
        /// the file leaves the field empty, which no bundled record does.
        let entityCode: Int?
        let continent: String
        let cqZone: Int
        let ituZone: Int
        let waeOnly: Bool
    }

    struct Match: Equatable, Sendable {
        let entity: Entity
        let cqZone: Int
        let ituZone: Int
        let continent: String
        /// Matched an `=CALL` entry rather than a prefix.
        let exact: Bool
    }

    let entities: [Entity]
    /// The `=VERyyyymmdd` release marker the file carries.
    let release: String?

    private struct Rule: Sendable {
        let entity: Int
        let cq: Int?
        let itu: Int?
    }
    private let exact: [String: Rule]
    private let prefixes: [String: Rule]
    /// Every entity's primary prefix (field 0), independent of whether the
    /// file also lists it as a token in its own prefix list.
    private let primaryPrefixes: Set<String>
    private let longestPrefix: Int

    // MARK: Loading

    static func load(bundle: Bundle = .main) -> CTYTable? {
        guard let url = bundle.url(forResource: "cty", withExtension: "csv", subdirectory: "CTY"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return try? parse(csv: text)
    }

    /// The bundled table, loaded once; nil only if the resource is missing.
    static let shared: CTYTable? = CTYTable.load()

    enum ParseError: Error, Equatable { case malformedRecord(String), noRecords }

    static func parse(csv: String) throws -> CTYTable {
        var entities: [Entity] = [], exact: [String: Rule] = [:], prefixes: [String: Rule] = [:]
        var release: String?
        for raw in csv.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            var fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 10 else { throw ParseError.malformedRecord(line) }
            // A name may contain commas: everything between the primary prefix
            // and the last eight fields is the name.
            if fields.count > 10 {
                let name = fields[1...(fields.count - 9)].joined(separator: ",")
                fields = [fields[0], name] + Array(fields[(fields.count - 8)...])
            }
            let waeOnly = fields[0].hasPrefix("*")
            let primary = waeOnly ? String(fields[0].dropFirst()) : fields[0]
            guard let cq = Int(fields[4]), let itu = Int(fields[5]) else { throw ParseError.malformedRecord(line) }
            let entity = Entity(name: fields[1], primaryPrefix: primary.uppercased(),
                                entityCode: Int(fields[2]).flatMap { $0 > 0 ? $0 : nil },
                                continent: fields[3], cqZone: cq, ituZone: itu, waeOnly: waeOnly)
            let index = entities.count
            entities.append(entity)
            let list = fields[9].replacingOccurrences(of: ";", with: "")
            for token in list.split(separator: " ") {
                var t = Substring(token)
                let isExact = t.hasPrefix("=")
                if isExact { t = t.dropFirst() }
                var cqOverride: Int?, ituOverride: Int?
                if let open = t.firstIndex(of: "("), let close = t[open...].firstIndex(of: ")") {
                    cqOverride = Int(t[t.index(after: open)..<close]); t = t[..<open] + t[t.index(after: close)...]
                }
                if let open = t.firstIndex(of: "["), let close = t[open...].firstIndex(of: "]") {
                    ituOverride = Int(t[t.index(after: open)..<close]); t = t[..<open] + t[t.index(after: close)...]
                }
                let key = String(t).uppercased()
                if key.hasPrefix("VER"), key.count == 11, Int(key.dropFirst(3)) != nil { release = key; continue }
                let rule = Rule(entity: index, cq: cqOverride, itu: ituOverride)
                // A callsign listed under two entities keeps the first (4U1VIC).
                if isExact { if exact[key] == nil { exact[key] = rule } } else if prefixes[key] == nil { prefixes[key] = rule }
            }
        }
        guard !entities.isEmpty else { throw ParseError.noRecords }
        return CTYTable(entities: entities, release: release, exact: exact, prefixes: prefixes,
                        primaryPrefixes: Set(entities.map(\.primaryPrefix)),
                        longestPrefix: prefixes.keys.map(\.count).max() ?? 0)
    }

    // MARK: Lookup

    func entity(forPrimaryPrefix prefix: String) -> Entity? {
        entities.first { $0.primaryPrefix == prefix.uppercased() }
    }

    /// Whether `prefix`, uppercased, is one of the file's prefix keys (not
    /// one of its exact-call `=CALL` keys) or some entity's primary prefix
    /// (field 0) — a record's own primary prefix does not always reappear
    /// as a token in its own prefix list, so primary prefixes count too.
    func hasPrefix(_ prefix: String) -> Bool {
        let key = prefix.uppercased()
        return prefixes[key] != nil || primaryPrefixes.contains(key)
    }

    /// The entity and zones for a callsign: an exact `=CALL` entry (with or
    /// without its portable suffix), else the longest prefix of the call's
    /// location part (`DXCCTable.locationPart(of:)` strips /P, /MM, /QRP…).
    func match(callsign raw: String) -> Match? {
        let call = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard !call.isEmpty else { return nil }
        if let rule = exact[call] { return make(rule, exact: true) }
        let part = DXCCTable.locationPart(of: call)
        if let rule = exact[part] { return make(rule, exact: true) }
        var length = min(part.count, longestPrefix)
        while length > 0 {
            if let rule = prefixes[String(part.prefix(length))] { return make(rule, exact: false) }
            length -= 1
        }
        return nil
    }

    private func make(_ rule: Rule, exact: Bool) -> Match {
        let e = entities[rule.entity]
        return Match(entity: e, cqZone: rule.cq ?? e.cqZone, ituZone: rule.itu ?? e.ituZone, continent: e.continent, exact: exact)
    }
}
