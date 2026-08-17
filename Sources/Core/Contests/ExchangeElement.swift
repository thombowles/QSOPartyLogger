import Foundation

/// One piece of a contest exchange, in send order. `sentBy` names every side
/// that sends it and, for `token` kinds, what that side sends; the received
/// fields a side sees are the elements sent by the sides it may work, and a
/// token field accepts the union of those sides' sets.
struct ExchangeElement: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case rst, serial, name, token, cqZone, ituZone, precedence, check
        case classToken, power, memberOrPower, callEcho, grid, report

        var defaultLabel: String {
            switch self {
            case .rst: "RST"
            case .serial: "Nr"
            case .name: "Name"
            case .token: "Exchange"
            case .cqZone: "Zone"
            case .ituZone: "ITU zone"
            case .precedence: "Prec"
            case .check: "Check"
            case .classToken: "Class"
            case .power: "Power"
            case .memberOrPower: "Member #"
            case .callEcho: "Call"
            case .grid: "Grid"
            case .report: "Report"
            }
        }

        /// The generic Cabrillo template's widths: `rst nnn`, `exch ******`;
        /// Sweepstakes' `p` and `ck` are 1 and 2; a call echo has no column.
        var defaultCabrilloWidth: Int {
            switch self {
            case .rst: 3
            case .precedence: 1
            case .check: 2
            case .callEcho: 0
            default: 6
            }
        }
    }

    struct SentSpec: Codable, Equatable, Sendable {
        struct Multi: Codable, Equatable, Sendable { let max: Int }
        /// Token-set ids this side sends (token kinds only).
        let sets: [String]?
        /// Several values at once — a county-line entrant (token kinds only).
        let multi: Multi?
        init(sets: [String]? = nil, multi: Multi? = nil) {
            self.sets = sets
            self.multi = multi
        }
    }

    enum PrefillSource: String, Codable, Sendable { case cty, callHistory, stationMemory, spot }

    /// A sent value computed from the entrant's category (Sweepstakes'
    /// precedence). Rows are tried in order; every key in `when` must equal
    /// the category axis's value.
    struct Derivation: Codable, Equatable, Sendable {
        struct Row: Codable, Equatable, Sendable {
            let when: [String: String]
            let value: String
        }
        let kind: String
        let table: [Row]

        func value(for category: [String: String]) -> String? {
            table.first { row in row.when.allSatisfy { category[$0.key] == $0.value } }?.value
        }
    }

    let id: String
    let kind: Kind
    let label: String
    let shortLabel: String?
    let sentBy: [String: SentSpec]
    /// Set once in Setup and stamped per row; false for a per-QSO value (serial).
    let fixed: Bool
    /// Must be filled before a QSO can be logged.
    let required: Bool
    let cabrilloWidth: Int
    let prefill: [PrefillSource]
    let derived: Derivation?
    /// `precedence` / `classToken`: the accepted letters.
    let letters: [String]?
    /// `classToken`: the smallest transmitter count (Field Day: 1).
    let minNumber: Int?
    /// `memberOrPower`: labels and the QRP ceilings.
    let member: MemberSpec?

    init(id: String, kind: Kind, label: String? = nil, shortLabel: String? = nil,
         sentBy: [String: SentSpec], fixed: Bool = false, required: Bool = true,
         cabrilloWidth: Int? = nil, prefill: [PrefillSource] = [], derived: Derivation? = nil,
         letters: [String]? = nil, minNumber: Int? = nil, member: MemberSpec? = nil) {
        self.id = id
        self.kind = kind
        self.label = label ?? kind.defaultLabel
        self.shortLabel = shortLabel
        self.sentBy = sentBy
        self.fixed = fixed
        self.required = required
        self.cabrilloWidth = cabrilloWidth ?? kind.defaultCabrilloWidth
        self.prefill = prefill
        self.derived = derived
        self.letters = letters
        self.minNumber = minNumber
        self.member = member
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, label, shortLabel, sentBy, fixed, required, cabrilloWidth, prefill, derived, letters, minNumber, member
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            kind: try c.decode(Kind.self, forKey: .kind),
            label: try c.decodeIfPresent(String.self, forKey: .label),
            shortLabel: try c.decodeIfPresent(String.self, forKey: .shortLabel),
            sentBy: try c.decodeIfPresent([String: SentSpec].self, forKey: .sentBy) ?? [:],
            fixed: try c.decodeIfPresent(Bool.self, forKey: .fixed) ?? false,
            required: try c.decodeIfPresent(Bool.self, forKey: .required) ?? true,
            cabrilloWidth: try c.decodeIfPresent(Int.self, forKey: .cabrilloWidth),
            prefill: try c.decodeIfPresent([PrefillSource].self, forKey: .prefill) ?? [],
            derived: try c.decodeIfPresent(Derivation.self, forKey: .derived),
            letters: try c.decodeIfPresent([String].self, forKey: .letters),
            minNumber: try c.decodeIfPresent(Int.self, forKey: .minNumber),
            member: try c.decodeIfPresent(MemberSpec.self, forKey: .member)
        )
    }

    /// The token-set ids the given sides send, in declaration order, deduplicated.
    func setsSent(by sides: [String]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for side in sides {
            for set in sentBy[side]?.sets ?? [] where seen.insert(set).inserted { out.append(set) }
        }
        return out
    }

    /// The largest `multi.max` among the given sides — 1 when none allows several.
    func maxValues(for sides: [String]) -> Int {
        sides.compactMap { sentBy[$0]?.multi?.max }.max() ?? 1
    }
}

/// The member-number-or-power element's labels and QRP ceilings — the
/// display half of today's `MemberExchange`; its points live in `PointRule`s.
struct MemberSpec: Codable, Equatable, Sendable {
    let term: String
    let shortTerm: String
    let memberPlural: String
    let qrpMaxWatts: MemberExchange.QRPMaxWatts
}
