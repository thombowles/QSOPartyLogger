import Foundation

/// A QSO party's complete rule set, loaded from JSON (bundled or user-installed).
/// Adding a party requires no code — drop a JSON file in
/// `~/Library/Application Support/QSOPartyLogger/Parties/`.
///
/// All fields beyond the core set are optional with defaults chosen so that
/// schema-v1 files written for earlier builds keep decoding identically.
struct PartyDefinition: Codable, Identifiable, Equatable, Sendable {
    let schemaVersion: Int
    let id: String
    let name: String
    let cabrilloContest: String
    /// Two-letter state whose counties define the party (e.g. "KS").
    let homeState: String
    let countyAbbrLength: Int
    let validBands: [Band]
    let points: PointsTable
    let dupeScope: DupeScope
    let multipliers: MultRules
    let bonuses: [BonusRule]
    let oneByOne: OneByOneConfig?
    /// Operating windows for the current year (UTC), from the official calendar.
    let schedule: [ScheduleWindow]?
    let counties: [County]
    let notes: String?
    /// Where this party's spots live on qsopartyhub.com, when the hub serves
    /// it. `nil` for the two it does not: California's page is an unfinished
    /// stub, and WA Salmon Run has no page at all.
    let hubSpots: HubSpotSource?

    /// This party's N1MM call history file in the community listing, when one
    /// exists. `nil` for the three with no file upstream (azqp, mdc, vtqp) —
    /// pinned by `CallHistorySourceTests`, so a party joining or leaving the
    /// set is a deliberate edit backed by a regenerated mapping.
    let callHistory: CallHistorySource?

    // MARK: Optional rule shapes (defaults preserve original behavior)

    /// How DX stations identify themselves in the exchange.
    /// `.token`: the literal word "DX". `.prefix`: their DXCC country prefix
    /// (each unique prefix is its own multiplier where the dx class counts).
    var dxStyle: DXStyle { dxStyleRaw ?? .token }
    private let dxStyleRaw: DXStyle?

    /// Mode classes that are legal contest modes (ALQP/OhQP/COQP/WA/MDC have
    /// no digital). Rows in other modes are invalid — no points, no mults.
    var allowedModeClasses: [ModeClass] { allowedModeClassesRaw ?? ModeClass.allCases }
    private let allowedModeClassesRaw: [ModeClass]?

    /// Max counties one station may claim simultaneously (county lines).
    /// ALQP forbids line sitting (1); TnQP/WA/COQP allow 2; IAQP junctions 4.
    var maxSimultaneousCounties: Int { maxSimultaneousCountiesRaw ?? 4 }
    private let maxSimultaneousCountiesRaw: Int?

    /// State tokens accepted but credited as another state (e.g. DC→MD).
    var stateAliases: [String: String] { stateAliasesRaw ?? [:] }
    private let stateAliasesRaw: [String: String]?

    /// Every state this party's counties lie in. Defaults to `[homeState]`,
    /// which is every single-state party — the list exists for the two
    /// multi-state regionals, where **one log covers all member states**: the
    /// 7th Call Area's seven and New England's six.
    ///
    /// `homeState` remains the party's *primary* state and still drives the
    /// Cabrillo `LOCATION:` header and the ADIF fallback; `homeStates` is what
    /// decides which state tokens an entrant may not send, because a station in
    /// any member state sends a county rather than a bare state.
    var homeStates: [String] { homeStatesRaw ?? [homeState] }
    private let homeStatesRaw: [String]?

    /// The state a given county lies in — its own `state` where the party set
    /// one, and `homeState` otherwise. **Every call site that used to read
    /// `party.homeState` for a county should read this**, which is what keeps
    /// single-state parties identical while letting a 7QP county carry Idaho.
    func state(forCounty abbr: String) -> String {
        county(for: abbr)?.state ?? homeState
    }

    /// The party ids this one combines, for the weekends where several
    /// sponsors accept a single shared log — empty for every ordinary party.
    ///
    /// This does **not** replace the members: they stay independently
    /// selectable, because an operator inside one of them needs that party's own
    /// exchange and multipliers. It only tells the picker to group them, so four
    /// parties on one weekend do not read as four unrelated choices.
    var combines: [String] { combinesRaw ?? [] }
    private let combinesRaw: [String]?

    /// How the setup sheet names the inside/outside choice: "Inside \(this)".
    /// Defaults to `homeState`, so every existing party reads as before; the
    /// multi-state regionals supply a phrase instead ("the 7th call area").
    var inStateLabel: String { inStateLabelRaw ?? homeState }
    private let inStateLabelRaw: String?

    /// What this party calls the class in its `counties` slot, **lowercase
    /// and singular**. Default "county", which is what the overwhelming
    /// majority of the catalogue actually enumerates.
    ///
    /// The slot holds whatever a sponsor's finest enumerated multiplier class
    /// is, and that is not always a county: NAQP's rule 11 counts "other
    /// North American entities as defined by the ARRL DXCC List", BCQP counts
    /// electoral districts, QCQP counts Quebec's administrative regions.
    /// Naming the class per party is what stops the score sidebar telling an
    /// operator their contest has counties when it does not.
    ///
    /// Lowercase because call sites capitalize the first letter for a heading
    /// (`sentenceCased`); storing "NA entity" capitalized would either shout
    /// mid-sentence or, run through `capitalized`, come back as "Na Entity".
    var countyTerm: String { countyTermRaw ?? "county" }
    private let countyTermRaw: String?

    /// The plural of `countyTerm`. Defaults to "counties" for the default
    /// term, and otherwise to the singular plus "s" — so a party whose plural
    /// is regular ("district") spends one line, and one whose plural is not
    /// ("parish") supplies it outright.
    var countyTermPlural: String {
        if let plural = countyTermPluralRaw { return plural }
        guard let singular = countyTermRaw else { return "counties" }
        return singular + "s"
    }
    private let countyTermPluralRaw: String?

    /// Is there a home region an entrant can be *inside* of? Default true —
    /// a state QSO party's whole geometry is host state versus everyone else.
    ///
    /// NAQP is the exception: rule 10 gives every North American entrant the
    /// same exchange (name + their own location), and the country tokens
    /// riding in the county slot are peers of the states and provinces, not
    /// sub-regions of a host state. Asking such an entrant whether they are
    /// "inside" is a question with no answer, and answering it wrong used to
    /// put the pseudo-`homeState` in the Cabrillo `LOCATION:` header. Where
    /// this is false the setup sheet asks one question — where are you — and
    /// the exports read the entrant's own token.
    var hasHomeRegion: Bool { hasHomeRegionRaw ?? true }
    private let hasHomeRegionRaw: Bool?

    /// State tokens that are not valid in this party beyond the home state
    /// (MDC: DC arrives as the WDC county entity, so both MD and DC are out).
    /// Defaults to **all** of `homeStates`, so a multi-state party excludes
    /// every member state without having to list them twice.
    var excludedStateTokens: [String] { excludedStateTokensRaw ?? homeStates }
    private let excludedStateTokensRaw: [String]?

    /// Province token list override (OhQP counts only 11). Default: the 13.
    var provinces: Set<String> {
        provincesRaw.map(Set.init) ?? MultClass.canadianProvinces
    }
    private let provincesRaw: [String]?

    /// ARRL/RAC section tokens, for a party whose exchange carries a section
    /// rather than a state or province (PAQP). **When present this list
    /// supplants the state and province token sets entirely** — `NTX` becomes
    /// valid and `TX` becomes invalid — because a party that counts sections
    /// counts nothing else alongside them. `nil` everywhere else, which leaves
    /// every existing party on states + provinces exactly as before.
    var sections: Set<String> { sectionsRaw.map(Set.init) ?? [] }
    private let sectionsRaw: [String]?

    /// Whether this party's non-county exchange is a section rather than a
    /// state/province.
    var usesSections: Bool { !(sectionsRaw ?? []).isEmpty }

    /// Whether the exchange carries RST (MDC exchanges call + location only).
    var exchangeIncludesRST: Bool { exchangeIncludesRSTRaw ?? true }
    private let exchangeIncludesRSTRaw: Bool?

    /// Whether the exchange carries a QSO number. CQP: "California stations send
    /// QSO number and 4-letter county abbreviation … QSO number = contact serial
    /// number starting with 1 for the first contact."
    ///
    /// Independent of `exchangeIncludesRST` — all four combinations are real:
    /// report only (most parties), number only (CQP), neither (MDC), or both.
    var exchangeIncludesSerial: Bool { exchangeIncludesSerialRaw ?? false }
    private let exchangeIncludesSerialRaw: Bool?

    /// Whether the exchange carries an operator name. NAQP rule 10: "Operator
    /// name and station location (state, province, or country) for North
    /// American stations"; MNQP is the same shape. The name is the Cabrillo
    /// ex1 element wherever it exists, ahead of a serial or a report — which
    /// is why a name party's log cannot be submitted without one.
    ///
    /// Independent of `exchangeIncludesRST` and `exchangeIncludesSerial`;
    /// both bundled name parties pair the name with a location and nothing
    /// else.
    var exchangeIncludesName: Bool { exchangeIncludesNameRaw ?? false }
    private let exchangeIncludesNameRaw: Bool?

    /// Whether an out-of-state entrant earns credit *only* for contacts with
    /// home-state stations. MDC rule 10b: "Stations not located in the state of
    /// Maryland, or the District of Columbia may only receive credit for
    /// contacts with stations located in Maryland or the District of Columbia."
    /// Rows carrying any other location are not contest QSOs — no points, no
    /// multiplier, excluded from dupe accounting.
    ///
    /// Most state parties word the same restriction somewhere in their rules;
    /// the default is `false` so that definitions written before this field
    /// existed keep scoring identically (constitution Article 4). Turn it on
    /// per party only with the rule text to back it.
    var outStateWorksHomeStationsOnly: Bool { outStateWorksHomeStationsOnlyRaw ?? false }
    private let outStateWorksHomeStationsOnlyRaw: Bool?

    /// Final-score multipliers by entry category (NJQP power; MDC power ×
    /// station category). Keys are the Cabrillo raw values ("QRP", "ROVER"…).
    let scoreMultipliers: ScoreMultipliers?

    /// Points for a contact with a **home-state** station, where the party pays
    /// by *who was worked* rather than by mode. MEQP: "Contacts with stations in
    /// Maine are worth 2 points. Contacts with stations outside Maine are worth
    /// 1 point." — CW and phone pay alike, and the received location decides.
    ///
    /// `nil` (every other bundled party) means `points` applies to every row,
    /// which is how definitions written before this field existed keep scoring
    /// identically (constitution Article 4).
    let homeStationPoints: PointsTable?

    /// Counties the sponsor designates as paying a **multiple** of the ordinary
    /// QSO points, applied *before* the multiplier product. NCQP's "Rarest of
    /// NC": "A QSO with someone in one of these counties will be scored 10X QSO
    /// points… **These points are added to the rest of the regular QSO Points
    /// prior to MULT multiplication** so they have a significant positive effect
    /// on the final score."
    ///
    /// Deliberately not a `BonusRule`: bonuses are added *after* multiplication,
    /// and the sponsor's placement is the whole point. Keyed on the **received**
    /// county, with no in-state/out-of-state split — NCQP states the rule
    /// unconditionally, two paragraphs after splitting its multiplier rules by
    /// side, so both entrants earn it.
    ///
    /// `nil` (every other bundled party) leaves `pointsTable` returning exactly
    /// what it returned before (constitution Article 4).
    let countyPointFactor: CountyPointFactor?

    /// The points table governing a contact whose received location is
    /// `theirLoc`. Home-state stations are recognised the only way the exchange
    /// allows — they send a county — so `countyAbbrs` is the party's county set.
    ///
    /// A designated county scales whichever table applies rather than replacing
    /// it, because "10× QSO points" means ten times what the contact was
    /// otherwise worth.
    func pointsTable(forTheirLoc theirLoc: String, countyAbbrs: Set<String>) -> PointsTable {
        let loc = theirLoc.uppercased()
        var table = points
        if let homeStationPoints, countyAbbrs.contains(loc) {
            table = homeStationPoints
        }
        if let countyPointFactor, countyPointFactor.applies(to: loc) {
            table = table.scaled(by: countyPointFactor.factor)
        }
        return table
    }

    /// A designated subset of counties and what a QSO with one of them pays,
    /// as a multiple of the ordinary rate.
    struct CountyPointFactor: Codable, Equatable, Sendable {
        /// The sponsor's designated county abbreviations.
        let counties: [String]
        /// The multiple — NCQP's 10, giving phone 20, CW 30, digital 50.
        let factor: Int

        /// Uppercased once at decode rather than per logged row.
        private let abbrs: Set<String>

        func applies(to loc: String) -> Bool { abbrs.contains(loc.uppercased()) }

        init(counties: [String], factor: Int) {
            self.counties = counties
            self.factor = factor
            self.abbrs = Set(counties.map { $0.uppercased() })
        }

        private enum CodingKeys: String, CodingKey { case counties, factor }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                counties: try c.decode([String].self, forKey: .counties),
                factor: try c.decode(Int.self, forKey: .factor)
            )
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(counties, forKey: .counties)
            try c.encode(factor, forKey: .factor)
        }
    }

    enum DXStyle: String, Codable, Sendable {
        case token
        case prefix
    }

    struct ScoreMultipliers: Codable, Equatable, Sendable {
        let power: [String: Int]?
        let stationCategory: [String: Int]?

        func factor(power p: StationProfile.CategoryPower, station s: StationProfile.CategoryStation) -> Int {
            (power?[p.rawValue] ?? 1) * (stationCategory?[s.rawValue] ?? 1)
        }
    }

    struct ScheduleWindow: Codable, Equatable, Sendable {
        let start: Date
        let end: Date
    }

    struct PointsTable: Codable, Equatable, Sendable {
        let phone: Int
        let cw: Int
        let digital: Int

        func points(for modeClass: ModeClass) -> Int {
            switch modeClass {
            case .phone: phone
            case .cw: cw
            case .digital: digital
            }
        }

        /// Every rate multiplied — a party paying "10X QSO points" for certain
        /// counties (`countyPointFactor`) scales the table rather than
        /// replacing it, so the multiple applies to whatever the contact was
        /// otherwise worth.
        func scaled(by factor: Int) -> PointsTable {
            PointsTable(phone: phone * factor, cw: cw * factor, digital: digital * factor)
        }
    }

    enum DupeScope: String, Codable, Sendable {
        /// Workable once per band × mode-class (all bundled parties).
        case bandMode
    }

    struct MultRules: Codable, Equatable, Sendable {
        let inState: MultRule
        let outState: MultRule
    }

    struct MultRule: Codable, Equatable, Sendable {
        let classes: [MultClass]
        /// KSQP/ALQP/COQP/IAQP: the first home-state county logged also
        /// satisfies the home state's own state multiplier.
        let homeStateCountsViaCounty: Bool
        let countScope: CountScope
        /// Cap on distinct dx multipliers (WA/NHQP in-state: 10). nil = no cap.
        var dxMultCap: Int? { dxMultCapRaw }
        private let dxMultCapRaw: Int?

        /// Cap on the multiplier total that reaches the **score**, where a party
        /// recognises more multipliers than it will pay for. CQP: "Although
        /// there are 63 possible multipliers that can accrue toward the CA
        /// station's multiplier tally, the maximum number of counted multipliers
        /// toward the CA station's final score is 58." The distinction is the
        /// sponsor's — every multiplier is still tallied and shown, only the
        /// count that multiplies QSO points is limited. nil = no cap.
        var maxScoredMultipliers: Int? { maxScoredMultipliersRaw }
        private let maxScoredMultipliersRaw: Int?

        /// Multipliers credited outright, because the party's own exchange makes
        /// them unreachable by working anyone. PAQP 12.d: "EPA and WPA
        /// multipliers are automatically added during the rescore process —
        /// there is no need to enter them", Pennsylvania stations sending a
        /// county so the two PA section tokens are never transmitted.
        ///
        /// Credited once, with no band or mode scope: the sponsor adds them to
        /// the tally rather than to any particular QSO. Only counted if the
        /// class is one this side actually counts.
        var granted: [GrantedMultiplier] { grantedRaw ?? [] }
        private let grantedRaw: [GrantedMultiplier]?

        init(
            classes: [MultClass],
            homeStateCountsViaCounty: Bool,
            countScope: CountScope,
            dxMultCap: Int? = nil,
            maxScoredMultipliers: Int? = nil,
            granted: [GrantedMultiplier]? = nil
        ) {
            self.classes = classes
            self.homeStateCountsViaCounty = homeStateCountsViaCounty
            self.countScope = countScope
            self.dxMultCapRaw = dxMultCap
            self.maxScoredMultipliersRaw = maxScoredMultipliers
            self.grantedRaw = granted
        }

        private enum CodingKeys: String, CodingKey {
            case classes, homeStateCountsViaCounty, countScope
            case dxMultCapRaw = "dxMultCap"
            case maxScoredMultipliersRaw = "maxScoredMultipliers"
            case grantedRaw = "grantedMultipliers"
        }
    }

    /// One multiplier a party hands over without it being worked.
    struct GrantedMultiplier: Codable, Equatable, Sendable {
        let multClass: MultClass
        let value: String
    }

    enum CountScope: String, Codable, Sendable {
        /// Each multiplier counts once for the whole log (KSQP, TQP, WA…).
        case once
        /// …once per mode class (ALQP, OhQP, COQP).
        case perMode
        /// …once per band (TnQP; NHQP/HQP out-of-state).
        case perBand
        /// …once per band *and* per mode (MEQP: "Each multiplier may be counted
        /// once on each mode on each of the six contest bands").
        case perBandMode

        /// The `scope` component of a `ScoreEngine.MultKey` under this scope.
        /// Both the scorer and the sidebar's roster call this, so a drawn
        /// block and a counted multiplier can never disagree about what
        /// "worked on 20m" means.
        func component(band: Band, modeClass: ModeClass) -> String {
            switch self {
            case .once: ""
            case .perMode: modeClass.rawValue
            case .perBand: band.rawValue
            case .perBandMode: "\(band.rawValue)/\(modeClass.rawValue)"
            }
        }
    }

    struct OneByOneConfig: Codable, Equatable, Sendable {
        let words: [String]
        let wildcard: String?
    }

    // MARK: Verification status (constitution Article 3)

    /// One thing about this party that an operator or a maintainer should know,
    /// classified by **what it costs the operator** rather than by how confident
    /// the maintainer was.
    ///
    /// This exists because `isPartiallyVerified` fired on 84% of the catalogue.
    /// A marker that is the default state cannot tell "your Cabrillo will be
    /// rejected" apart from "re-check the sponsor's page next spring", and the
    /// picker read as a list of broken things. Only `Kind.badges` raises a
    /// visible warning; the rest stay available in the sheet and under Rules
    /// provenance.
    ///
    /// **Never read by `ScoreEngine`.** Caveats describe the gap between this
    /// app and the sponsor's rules; they never change a score themselves, which
    /// is what makes them safe to add to every party in a single pass.
    struct Caveat: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable, CaseIterable {
            /// The log this app writes cannot be submitted as it stands — a
            /// required field is not captured (MNQP's exchange name half).
            case exportBlocking
            /// The app's total will differ from the sponsor's, because a rule
            /// that is fully verified cannot be expressed here (WIQP's
            /// fractional power multiplier; NCQP's two scoring rules).
            case scoreAffecting
            /// The sponsor's text is genuinely ambiguous and this app resolved
            /// it by inference. Defensible either way, and named so the reading
            /// is auditable.
            case ruleInference
            /// The source is stale, archived or undated — re-check before the
            /// next running. Costs the operator nothing today.
            case provenance
            /// Recorded for completeness; no scoring or export consequence.
            case cosmetic

            /// Loud enough to interrupt someone who is trying to start a
            /// contest. `ruleInference` deliberately does **not** qualify: it
            /// can move a score by one multiplier, but ~15 parties carry one and
            /// badging them rebuilds the problem this type exists to remove.
            var badges: Bool { self == .exportBlocking || self == .scoreAffecting }

            /// Most severe first, for display ordering.
            var severity: Int {
                switch self {
                case .exportBlocking: return 0
                case .scoreAffecting: return 1
                case .ruleInference: return 2
                case .provenance: return 3
                case .cosmetic: return 4
                }
            }
        }

        let kind: Kind
        /// One line, phrased as what the *app* does — "Score is a floor: the
        /// power multiplier isn't applied" — rather than as doubt about the
        /// rules. This is the only authored text; `detail` is copied verbatim.
        let summary: String
        /// The corresponding `KNOWN LIMITATION` / `OPEN QUESTION` prose from
        /// `notes`, copied rather than retyped (Article 2). `nil` where the
        /// summary is already the whole of it.
        let detail: String?
    }

    /// This party's caveats, most severe first. Empty for a party that has not
    /// been classified yet — including any user-installed file — in which case
    /// the sheet falls back to `operatorAlerts`.
    var caveats: [Caveat] {
        (caveatsRaw ?? []).sorted { $0.kind.severity < $1.kind.severity }
    }
    private let caveatsRaw: [Caveat]?

    /// The caveats that earn a visible warning: the app will mis-score or
    /// mis-export this party.
    var blockingCaveats: [Caveat] { caveats.filter(\.kind.badges) }

    /// Everything else — worth reading, not worth interrupting for.
    var advisoryCaveats: [Caveat] { caveats.filter { !$0.kind.badges } }

    /// Whether this party shipped with rules that could not be fully confirmed
    /// from an official source. Matched on the literal `verified: partial`
    /// marker rather than a loose word search, so provenance prose that merely
    /// mentions "partial" cannot raise a false warning.
    ///
    /// **No longer drives the UI** — see `Caveat`. It remains the Article 3
    /// marker, remains mandatory in `notes`, and remains covered by
    /// `PartyCatalogTests`, so a status change is still deliberate.
    var isPartiallyVerified: Bool {
        notes?.range(of: "verified: partial", options: .caseInsensitive) != nil
    }

    /// The `OPEN QUESTION…` tail of `notes` — the part an operator actually
    /// needs to act on before submitting a log, separated from the provenance
    /// paragraph that precedes it. `nil` when the notes carry no such section.
    /// The raw provenance tail, from the first marker to the end of `notes` —
    /// the maintainer's record, used for auditing. **The setup sheet does not
    /// show this**; it shows `operatorAlerts`, which is the same information cut
    /// down to what someone mid-contest has to act on.
    var openQuestions: String? {
        guard let notes,
              let marker = notes.range(of: "OPEN QUESTION", options: .caseInsensitive)
        else { return nil }
        let tail = notes[marker.lowerBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.isEmpty ? nil : tail
    }

    /// The things an operator has to *act on*, one short line each.
    ///
    /// `notes` is a maintainer's provenance record — long, shouty, and written
    /// to be audited rather than read mid-contest. This pulls out only the
    /// numbered `OPEN QUESTION n:` and `KNOWN LIMITATION n:` items and stops at
    /// the end of each, because the previous version ran from the first marker
    /// to the end of the notes and put the whole provenance paragraph on screen
    /// in caption text.
    ///
    /// Each item is trimmed to its own headline sentence, so what reaches the
    /// sheet is "Is the start 1400Z or 1300Z?" rather than four sentences about
    /// which aggregator believed which.
    var operatorAlerts: [String] {
        guard let notes else { return [] }
        let pattern = #"(OPEN QUESTION|KNOWN LIMITATION)\s*(\d+)?\s*[:\-]?\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let ns = notes as NSString
        let matches = regex.matches(in: notes, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [] }

        return matches.enumerated().compactMap { index, match -> String? in
            // Body runs from the end of this marker to the start of the next.
            let start = match.range.upperBound
            let end = index + 1 < matches.count
                ? matches[index + 1].range.lowerBound
                : ns.length
            guard start < end else { return nil }

            let body = ns.substring(with: NSRange(location: start, length: end - start))
            guard let headline = Self.firstSentence(of: body) else { return nil }
            let kind = ns.substring(with: match.range(at: 1)).capitalized
            return "\(kind): \(Self.softened(headline))"
        }
    }

    /// The first sentence, keeping its own terminator — so a question stays a
    /// question. Splitting on "." alone ran straight past "1400Z or 1300Z?" and
    /// swept in the paragraph that followed it.
    private static func firstSentence(of text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let end = trimmed.firstIndex(where: { ".?!".contains($0) }) {
            let sentence = String(trimmed[...end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { return sentence }
        }
        return trimmed
    }

    /// Technical abbreviations that are genuinely written in capitals and must
    /// survive the softening below. Everything else in caps is a maintainer
    /// shouting for attention in a wall of prose, which reads badly on screen.
    private static let keepUppercase: Set<String> = [
        "QSO", "QSOS", "CW", "SSB", "DX", "DXCC", "RST", "RS", "FM", "AM",
        "HF", "VHF", "UHF", "WARC", "ITU", "UTC", "GMT", "ADIF", "LOTW",
        "EDT", "CDT", "MDT", "PDT", "ADT", "EST", "CST", "MST", "PST",
        "US", "USA", "VE", "VA", "DC", "MD", "NL", "NF", "LB", "NU", "NT",
        "FT8", "FT4", "RTTY", "PSK", "WSJT", "APRS", "EOC", "SM", "ASM",
        "N1MM", "COG", "COGS", "FED", "FEDS", "QRP", "SO2R", "RBN",
    ]

    /// Lowers a maintainer's shouting. A word is left alone if it is a known
    /// abbreviation, contains a digit (`1400Z`, `DN91CE`, `7QP`), or is not
    /// entirely capitals; everything else that is all-caps is lowered.
    private static func softened(_ text: String) -> String {
        // Quoted spans are the SPONSOR'S OWN WORDS. Lowering their capitals
        // would misquote them - "'1A DE'" is an exchange, not shouting - so
        // each quoted run is passed through untouched.
        var out = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "'") {
            out += softenWords(String(rest[..<open]))
            let afterOpen = rest.index(after: open)
            if let close = rest[afterOpen...].firstIndex(of: "'") {
                out += String(rest[open...close])
                rest = rest[rest.index(after: close)...]
            } else {
                out += String(rest[open...])
                return out
            }
        }
        return out + softenWords(String(rest))
    }

    private static func softenWords(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: false)
            .map { word -> String in
                // Hyphenated compounds are judged part by part, so the word
                // half of "10-POINT" lowers while the number half is left.
                return word.split(separator: "-", omittingEmptySubsequences: false)
                    .map { part -> String in
                        let bare = part.filter(\.isLetter)
                        guard !bare.isEmpty,
                              bare.allSatisfy(\.isUppercase),
                              !part.contains(where: \.isNumber),
                              !keepUppercase.contains(bare.uppercased())
                        else { return String(part) }
                        return part.lowercased()
                    }
                    .joined(separator: "-")
            }
            .joined(separator: " ")
    }

    // MARK: County abbreviation shape

    /// Distinct abbreviation lengths actually present in the county data,
    /// ascending. Most parties use one length; the Salmon Run mixes 3 and 4
    /// (`CLAL`/`COL`, `KITS`/`KLI`), so a single `countyAbbrLength` cannot
    /// describe it. Derived from the data rather than hand-maintained.
    var countyAbbrLengths: [Int] {
        Set(counties.map(\.abbr.count)).sorted()
    }

    /// Entry-field hint: `"3"` for a uniform party, `"3/4"` where lengths mix.
    var countyAbbrLengthHint: String {
        let lengths = countyAbbrLengths
        return lengths.isEmpty
            ? String(countyAbbrLength)
            : lengths.map(String.init).joined(separator: "/")
    }

    // MARK: Lookup

    var countiesByAbbr: [String: County] {
        Dictionary(uniqueKeysWithValues: counties.map { ($0.abbr, $0) })
    }

    func county(for abbr: String) -> County? {
        countiesByAbbr[abbr.uppercased()]
    }

    /// Valid non-county location tokens: states (less exclusions, plus alias
    /// keys like DC), provinces, and the DX token when the party uses it — or,
    /// for a section party, its sections instead of all of that.
    var validOutStateTokens: Set<String> {
        var tokens: Set<String>
        if usesSections {
            tokens = sections
        } else {
            tokens = MultClass.acceptedStateTokens
                .subtracting(excludedStateTokens)
                .union(provinces)
            tokens.formUnion(stateAliases.keys)
        }
        if dxStyle == .token {
            tokens.insert(MultClass.dxToken)
        }
        return tokens
    }

    /// What an entrant may claim as their *own* location in setup. Normally
    /// the out-of-state set. A party with no home region has no "outside", so
    /// its own token list joins it as a peer class — an NAQP entrant in
    /// Bermuda types VP9 exactly as a Texan types TX.
    ///
    /// Deliberately separate from `validOutStateTokens`, which the exchange
    /// parser reads for *received* locations: what an entrant may be and what
    /// they may work are different questions, and merging them would put
    /// county-class tokens in the out-of-state branch for every party.
    var validEntrantTokens: Set<String> {
        hasHomeRegion
            ? validOutStateTokens
            : validOutStateTokens.union(counties.map(\.abbr))
    }

    /// Could this token be a DX prefix under `.prefix` style? 1–5 chars,
    /// letters/digits with at least one letter, and not a county or any
    /// state/province/DX token — including excluded ones like the home state,
    /// which must never sneak back in as a "DX prefix".
    /// Known limitation: DXCC prefixes that collide with US state or Canadian
    /// province codes (OH Finland, ON Belgium, PA Netherlands…) are read as
    /// the state/province — same resolution sponsors' log checkers apply.
    func isPlausibleDXPrefix(_ token: String) -> Bool {
        guard dxStyle == .prefix else { return false }
        guard (1...5).contains(token.count) else { return false }
        guard token.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
        guard token.contains(where: \.isLetter) else { return false }
        guard countiesByAbbr[token] == nil else { return false }
        guard !MultClass.acceptedStateTokens.contains(token) else { return false }
        guard !MultClass.canadianProvinces.contains(token) else { return false }
        guard !provinces.contains(token) else { return false }
        guard !sections.contains(token) else { return false }
        guard token != MultClass.dxToken else { return false }
        return true
    }

    /// Basic structural validation for user-supplied files.
    func validate() throws {
        var seen = Set<String>()
        for c in counties {
            guard c.abbr == c.abbr.uppercased(), !c.abbr.isEmpty else {
                throw PartyValidationError.badAbbreviation(c.abbr)
            }
            guard seen.insert(c.abbr).inserted else {
                throw PartyValidationError.duplicateAbbreviation(c.abbr)
            }
        }
        guard !counties.isEmpty else { throw PartyValidationError.noCounties }
        guard homeState.count == 2 else { throw PartyValidationError.badHomeState(homeState) }
        for s in homeStates where s.count != 2 {
            throw PartyValidationError.badHomeState(s)
        }
        guard homeStates.contains(homeState) else {
            throw PartyValidationError.badHomeState(homeState)
        }
        // A county's own state must be one the party actually covers, or the
        // ADIF export and the state credit would name a state nobody can work.
        for c in counties {
            if let s = c.state, !homeStates.contains(s) {
                throw PartyValidationError.badHomeState(s)
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, cabrilloContest, homeState, countyAbbrLength
        case validBands, points, dupeScope, multipliers, bonuses, oneByOne
        case schedule, counties, notes, scoreMultipliers, homeStationPoints
        case countyPointFactor
        case hubSpots, callHistory
        case caveatsRaw = "caveats"
        case combinesRaw = "combines"
        case homeStatesRaw = "homeStates"
        case inStateLabelRaw = "inStateLabel"
        case hasHomeRegionRaw = "hasHomeRegion"
        case countyTermRaw = "countyTerm"
        case countyTermPluralRaw = "countyTermPlural"
        case dxStyleRaw = "dxStyle"
        case allowedModeClassesRaw = "allowedModes"
        case maxSimultaneousCountiesRaw = "maxSimultaneousCounties"
        case stateAliasesRaw = "stateAliases"
        case excludedStateTokensRaw = "excludedStateTokens"
        case provincesRaw = "provinces"
        case sectionsRaw = "sections"
        case exchangeIncludesRSTRaw = "exchangeIncludesRST"
        case exchangeIncludesSerialRaw = "exchangeIncludesSerial"
        case exchangeIncludesNameRaw = "exchangeIncludesName"
        case outStateWorksHomeStationsOnlyRaw = "outStateWorksHomeStationsOnly"
    }
}

enum PartyValidationError: Error, Equatable, LocalizedError {
    case badAbbreviation(String)
    case duplicateAbbreviation(String)
    case noCounties
    case badHomeState(String)

    var errorDescription: String? {
        switch self {
        case .badAbbreviation(let a): "County abbreviation '\(a)' must be non-empty uppercase."
        case .duplicateAbbreviation(let a): "County abbreviation '\(a)' appears more than once."
        case .noCounties: "Party has no counties."
        case .badHomeState(let s): "homeState '\(s)' must be a 2-letter state code."
        }
    }
}

/// Bonus scoring strategies. JSON uses a `type` discriminator so new strategies
/// can be added as cases without breaking existing files.
enum BonusRule: Codable, Equatable, Sendable {
    /// Flat bonus for working a specific station. Scope: how often it pays.
    case workStation(call: String, points: Int, scope: WorkStationScope)
    /// TQP-style: +points for each `per` distinct counties a mobile is worked in.
    case mobileCountyCount(per: Int, points: Int)
    /// TnQP/COQP-style: +points per county I activate (as an in-state
    /// mobile/rover/portable) with at least `minQSOs` valid QSOs made from it.
    case activatedCountyCount(minQSOs: Int, points: Int)
    /// MDC-style tiered sweep of county-class entities: highest reached tier
    /// pays (non-stacking). Tiers must be sorted ascending by count.
    case sweepTiers([SweepTier])
    /// NCQP-style sweep of a **named subset**: "If at least one QSO is made with
    /// a station in five of the 'Rarest of NC' counties, 500 additional bonus
    /// points are added to the score after multiplication."
    ///
    /// Pays once at `need` or more — the sponsor's threshold is "at least", and
    /// working all ten still pays the one 500. Distinct from `sweepTiers`, which
    /// counts *any* county and reads the multiplier tally; this counts valid
    /// QSOs with the listed counties, which is the sponsor's own wording and
    /// stays right for an entrant whose side does not count counties as
    /// multipliers.
    case designatedCountySweep(counties: [String], need: Int, points: Int)

    enum WorkStationScope: String, Codable, Sendable {
        case once       // KSQP KS0KS, MDC W3VPR
        case perMode    // WA W7DX: 500 per mode
        case perQSO     // TnQP K4TCG: 100 per valid QSO
        /// …once per band **and** mode class. SCQP: "Bonus Stations may be
        /// worked ONCE per BAND per MODE for bonus points. You may work a bonus
        /// station more than once per band per mode for additional QSO points
        /// and multipliers" — a mobile bonus station worked from four counties
        /// on 40 m CW pays its bonus once, and four QSOs' worth of points.
        ///
        /// Distinct from `.perQSO`, which would pay all four, and from
        /// `.perMode`, which would collapse every band into one.
        case perBandMode
    }

    struct SweepTier: Codable, Equatable, Sendable {
        let count: Int
        let points: Int
    }

    private enum CodingKeys: String, CodingKey {
        case type, call, points, per, scope, minQSOs, tiers, counties, need
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "workStation":
            self = .workStation(
                call: try c.decode(String.self, forKey: .call),
                points: try c.decode(Int.self, forKey: .points),
                scope: try c.decodeIfPresent(WorkStationScope.self, forKey: .scope) ?? .once
            )
        case "mobileCountyCount":
            self = .mobileCountyCount(
                per: try c.decode(Int.self, forKey: .per),
                points: try c.decode(Int.self, forKey: .points)
            )
        case "activatedCountyCount":
            self = .activatedCountyCount(
                minQSOs: try c.decode(Int.self, forKey: .minQSOs),
                points: try c.decode(Int.self, forKey: .points)
            )
        case "sweepTiers":
            self = .sweepTiers(try c.decode([SweepTier].self, forKey: .tiers))
        case "designatedCountySweep":
            self = .designatedCountySweep(
                counties: try c.decode([String].self, forKey: .counties),
                need: try c.decode(Int.self, forKey: .need),
                points: try c.decode(Int.self, forKey: .points)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c,
                debugDescription: "Unknown bonus rule type '\(type)'"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .workStation(let call, let points, let scope):
            try c.encode("workStation", forKey: .type)
            try c.encode(call, forKey: .call)
            try c.encode(points, forKey: .points)
            try c.encode(scope, forKey: .scope)
        case .mobileCountyCount(let per, let points):
            try c.encode("mobileCountyCount", forKey: .type)
            try c.encode(per, forKey: .per)
            try c.encode(points, forKey: .points)
        case .activatedCountyCount(let minQSOs, let points):
            try c.encode("activatedCountyCount", forKey: .type)
            try c.encode(minQSOs, forKey: .minQSOs)
            try c.encode(points, forKey: .points)
        case .sweepTiers(let tiers):
            try c.encode("sweepTiers", forKey: .type)
            try c.encode(tiers, forKey: .tiers)
        case .designatedCountySweep(let counties, let need, let points):
            try c.encode("designatedCountySweep", forKey: .type)
            try c.encode(counties, forKey: .counties)
            try c.encode(need, forKey: .need)
            try c.encode(points, forKey: .points)
        }
    }
}

extension String {
    /// The first character uppercased, everything after it untouched.
    ///
    /// `capitalized` would lowercase the rest of every word, turning the
    /// multiplier term "NA entities" into "Na Entities". Headings need the
    /// first letter and nothing else touched.
    var sentenceCased: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
