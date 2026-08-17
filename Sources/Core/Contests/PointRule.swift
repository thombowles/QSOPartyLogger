import Foundation

/// QSO points, as an ordered list of rules; the first whose conditions all
/// hold pays. The last rule of a contest carries no conditions.
struct PointRule: Codable, Equatable, Sendable {
    let when: [PointCondition]
    let points: Int

    init(when: [PointCondition] = [], points: Int) {
        self.when = when
        self.points = points
    }

    private enum CodingKeys: String, CodingKey { case when, points }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(when: try c.decodeIfPresent([PointCondition].self, forKey: .when) ?? [],
                  points: try c.decode(Int.self, forKey: .points))
    }

    func matches(_ ctx: PointCondition.Context) -> Bool { when.allSatisfy { $0.matches(ctx) } }

    /// The points the first matching rule pays; 0 when none matches (a
    /// validated contest always ends with an unconditional rule).
    static func points(_ rules: [PointRule], _ ctx: PointCondition.Context) -> Int {
        rules.first { $0.matches(ctx) }?.points ?? 0
    }
}

/// A conjunction of constraints; every present field must hold.
struct PointCondition: Codable, Equatable, Sendable {
    enum Relation: String, Codable, Sendable { case sameEntity, sameContinent, differentContinent }
    struct TokenMatch: Codable, Equatable, Sendable {
        let element: String
        let set: String
    }

    let modeClass: [ModeClass]?
    let band: [Band]?
    let relation: Relation?
    /// Both stations are on this continent (CQ WW / WPX North America).
    let bothInContinent: String?
    let side: [String]?
    let workedSide: [String]?
    let receivedTokenIn: TokenMatch?
    /// `member` / `qrp` / `other` (the member-exchange sprints).
    let workedStationKind: [String]?
    let callsign: [String]?

    init(modeClass: [ModeClass]? = nil, band: [Band]? = nil, relation: Relation? = nil,
         bothInContinent: String? = nil, side: [String]? = nil, workedSide: [String]? = nil,
         receivedTokenIn: TokenMatch? = nil, workedStationKind: [String]? = nil, callsign: [String]? = nil) {
        self.modeClass = modeClass
        self.band = band
        self.relation = relation
        self.bothInContinent = bothInContinent
        self.side = side
        self.workedSide = workedSide
        self.receivedTokenIn = receivedTokenIn
        self.workedStationKind = workedStationKind
        self.callsign = callsign?.map { $0.uppercased() }
    }

    /// Everything a condition can read about one row.
    struct Context {
        let modeClass: ModeClass
        let band: Band
        let relation: Relation?
        /// The continent both stations share, or nil.
        let sharedContinent: String?
        let side: String
        let workedSide: String
        /// Received exchange, element id → value.
        let received: [String: String]
        let workedStationKind: String?
        let call: String
        let sets: (String) -> TokenSet?
    }

    func matches(_ ctx: Context) -> Bool {
        if let modeClass, !modeClass.contains(ctx.modeClass) { return false }
        if let band, !band.contains(ctx.band) { return false }
        if let relation, ctx.relation != relation { return false }
        if let bothInContinent, ctx.sharedContinent != bothInContinent { return false }
        if let side, !side.contains(ctx.side) { return false }
        if let workedSide, !workedSide.contains(ctx.workedSide) { return false }
        if let receivedTokenIn {
            guard let value = ctx.received[receivedTokenIn.element],
                  let set = ctx.sets(receivedTokenIn.set), set.accepts(value) else { return false }
        }
        if let workedStationKind {
            guard let kind = ctx.workedStationKind, workedStationKind.contains(kind) else { return false }
        }
        if let callsign, !callsign.contains(ctx.call.uppercased()) { return false }
        return true
    }
}
