import Foundation

/// Cabrillo V3 export on `ContestDefinition`. The header comes from the
/// station profile and `CabrilloSpec`; the QSO line is derived from the
/// exchange spec — `QSO: freq mo date time mycall <sent elements> call
/// <received elements> [t]`, each element padded to its `cabrilloWidth`.
/// County-line contacts arrive pre-expanded as separate rows, so each emits
/// its own QSO line with its own sent county — the format QSO party sponsors
/// (and N1MM) expect. Sponsors state that spaces delimit and columns need not
/// align, so the widths matter only for our own byte-identity
/// (`ExportByteIdentityTests`).
enum CabrilloExporter {

    static let creator = "QSO Party Logger 1.0"

    static func export(log: ContestLog, contest: ContestDefinition, score: ScoreEngine.ScoreBreakdown) -> String {
        var lines: [String] = []
        let s = log.station
        let side = contest.resolvedSideID(log.sideID)

        lines.append("START-OF-LOG: 3.0")
        lines.append("CREATED-BY: \(creator)")
        lines.append("CONTEST: \(contest.cabrillo.contest)")
        lines.append("CALLSIGN: \(s.callsign.uppercased())")
        lines.append("LOCATION: \(location(log: log, contest: contest))")
        lines.append("CATEGORY-OPERATOR: \(s.categoryOperator.rawValue)")
        lines.append("CATEGORY-ASSISTED: \(s.categoryAssisted.rawValue)")
        lines.append("CATEGORY-BAND: \(s.categoryBand ?? "ALL")")
        lines.append("CATEGORY-MODE: \(contest.cabrillo.categoryMode ?? categoryMode(log.qsos))")
        lines.append("CATEGORY-POWER: \(s.categoryPower.rawValue)")
        lines.append("CATEGORY-STATION: \(s.categoryStation.rawValue)")
        lines.append("CATEGORY-TRANSMITTER: \(s.categoryTransmitter.rawValue)")
        if let overlay = s.categoryOverlay, !overlay.isEmpty { lines.append("CATEGORY-OVERLAY: \(overlay)") }
        if let time = s.categoryTime, !time.isEmpty { lines.append("CATEGORY-TIME: \(time)") }
        lines.append("CLAIMED-SCORE: \(score.total)")
        lines.append("OPERATORS: \(s.operators.isEmpty ? s.callsign.uppercased() : s.operators.uppercased())")
        if !s.club.isEmpty { lines.append("CLUB: \(s.club)") }
        lines.append("NAME: \(s.name)")
        if !s.address.isEmpty { lines.append("ADDRESS: \(s.address)") }
        if !s.city.isEmpty { lines.append("ADDRESS-CITY: \(s.city)") }
        if !s.stateProvince.isEmpty { lines.append("ADDRESS-STATE-PROVINCE: \(s.stateProvince)") }
        if !s.postalCode.isEmpty { lines.append("ADDRESS-POSTALCODE: \(s.postalCode)") }
        if !s.country.isEmpty { lines.append("ADDRESS-COUNTRY: \(s.country)") }
        if !s.gridLocator.isEmpty { lines.append("GRID-LOCATOR: \(s.gridLocator.uppercased())") }
        if !s.email.isEmpty { lines.append("EMAIL: \(s.email)") }
        lines.append("SOAPBOX: ")
        // The credited off periods, where the contest has an operating-time
        // rule that applies to this entry (SS, WPX single-op, CQ WW Classic).
        if let rule = contest.operatingTime, rule.applies(to: log.categoryValues) {
            for period in ScoreEngine.classify(log: log, contest: contest).operatingTime.offPeriods {
                lines.append("OFFTIME: \(dateFormatter.string(from: period.start)) \(dateFormatter.string(from: period.end))")
            }
        }

        let myCall = s.callsign.uppercased()
        for q in log.qsos.sortedChronologically() {
            lines.append(qsoLine(q, myCall: myCall, contest: contest, side: side))
        }
        lines.append("END-OF-LOG:")
        return lines.joined(separator: "\n") + "\n"
    }

    /// The `PartyDefinition` overload: lower, then export on the model.
    static func export(log: ContestLog, party: PartyDefinition, score: ScoreEngine.ScoreBreakdown) -> String {
        export(log: log, contest: PartyLowering.lowered(party), score: score)
    }

    /// `LOCATION:` per `CabrilloSpec.location`. `.state`: `homeLocation` for
    /// an entrant on the first-listed side (a party's primary state, however
    /// many counties they sit on), else the entrant's sent location token —
    /// resolved to its group where the token has one (a county to its state)
    /// — else `exchangeDefaults["state"]`, else `DX`. `.entrantToken`: the
    /// sent token verbatim, else `DX`. `.section`: the sent section, else
    /// `exchangeDefaults["section"]`, else `DX`. Byte-identical to
    /// `MyLocation.entrantToken` for every party.
    static func location(log: ContestLog, contest: ContestDefinition) -> String {
        let side = contest.resolvedSideID(log.sideID)
        let sentLocation = log.sentExchange[ExchangeElementID.location]?.first?.uppercased()
        switch contest.cabrillo.location {
        case .entrantToken:
            return sentLocation ?? "DX"
        case .state:
            if let home = contest.cabrillo.homeLocation, side == contest.sides.first?.id { return home }
            if let token = sentLocation { return group(of: token, contest: contest, side: side) ?? token }
            if let state = log.station.exchangeDefaults["state"], !state.isEmpty { return state.uppercased() }
            return "DX"
        case .section:
            if let section = log.sentExchange["section"]?.first, !section.isEmpty { return section.uppercased() }
            if let section = log.station.exchangeDefaults["section"], !section.isEmpty { return section.uppercased() }
            return "DX"
        }
    }

    /// The group of a sent location token — a county's state — if the set that
    /// owns it carries groups; nil for a state, province, DX or unknown token.
    private static func group(of token: String, contest: ContestDefinition, side: String) -> String? {
        guard let element = contest.exchange.first(where: { $0.id == ExchangeElementID.location }) else { return nil }
        for setID in element.setsSent(by: [side]) {
            if let set = contest.tokenSet(id: setID), let t = set.token(for: token) { return t.group }
        }
        return nil
    }

    static func categoryMode(_ qsos: [QSO]) -> String {
        let classes = Set(qsos.map(\.modeClass))
        if classes.count > 1 { return "MIXED" }
        switch classes.first {
        case .cw: return "CW"
        case .phone: return "SSB"
        case .digital: return "RTTY"
        case nil: return "MIXED"
        }
    }

    static func cabrilloMode(_ rawMode: String) -> String {
        switch rawMode.uppercased() {
        case "CW": "CW"
        case "SSB", "USB", "LSB", "AM": "PH"
        case "FM": "FM"
        case "RTTY": "RY"
        default: "DG"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HHmm"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// One QSO line: the fixed columns, my sent elements, the worked call, the
    /// received elements (the call echo among them, padded to the call
    /// column's 13), and the transmitter column where the contest has one
    /// (always `0` — one transmitter).
    static func qsoLine(_ q: QSO, myCall: String, contest: ContestDefinition, side: String) -> String {
        let freq = String(q.freqKHz ?? q.band.defaultFreqKHz)
        let mode = cabrilloMode(q.rawMode)
        let when = dateFormatter.string(from: q.timestampUTC)
        let mine = myCall.uppercased(), theirs = q.call.uppercased()
        var line = "QSO: " + freq.leftPadded(to: 5) + " " + mode.padded(to: 2) + " " + when + " " + mine.padded(to: 13)
        line += columns(for: contest.sentElements(for: side), values: q.sent, call: mine, modeClass: q.modeClass, contest: contest)
        line += " " + theirs.padded(to: 13)
        line += columns(for: contest.receivedElements(for: side, includingCallEcho: true), values: q.rcvd, call: theirs,
                        modeClass: q.modeClass, contest: contest)
        if contest.cabrillo.transmitterColumn { line += " 0" }
        return line
    }

    /// The columns for one side of the line: `" " + value.padded(to: width)`
    /// per element in spec order. A `callEcho` writes the side's call, padded
    /// to 13. An element that is not `required` writes nothing at all when its
    /// value is empty (the member-or-power element, absent for a QRO
    /// station). Where the spec has no `rst`/`serial`/`name` element and
    /// `reportColumn` is set, the row's report — or the mode's default report
    /// — leads, in the generic template's ex1 slot.
    private static func columns(for elements: [ExchangeElement], values: [String: String], call: String,
                                modeClass: ModeClass, contest: ContestDefinition) -> String {
        var out = ""
        if contest.cabrillo.reportColumn,
           !elements.contains(where: { $0.kind == .rst || $0.kind == .serial || $0.kind == .name }) {
            out += " " + (values[ExchangeElementID.rst] ?? modeClass.defaultRST).uppercased().padded(to: 3)
        }
        for element in elements {
            if element.kind == .callEcho {
                out += " " + call.padded(to: 13)
                continue
            }
            let value = (values[element.id] ?? "").uppercased()
            if value.isEmpty && !element.required { continue }
            out += " " + value.padded(to: element.cabrilloWidth)
        }
        return out
    }

    // MARK: The row-driven ex1 element (kept for `ExchangeSummary`)

    /// The ex1 element: name → QSO number → signal report, driven by the
    /// row's own data. The exporter no longer builds its line this way — the
    /// exchange spec does — but `ExchangeSummary` still summarises a row's
    /// exchange with it, and generalising that view is phase 2.
    ///
    /// A name owns the slot wherever it exists — NAQP's and MNQP's own log
    /// templates put it there (`AC0W BILL MOW`) — and no bundled party carries
    /// more than one of the three.
    static func exchangeElement(name: String?, serial: Int?, rst: String) -> String {
        if let name, !name.isEmpty { return name.uppercased() }
        return exchangeNumber(serial: serial, rst: rst)
    }

    /// The numeric exchange element: a QSO number where the party sends one
    /// (CQP), otherwise the signal report.
    ///
    /// No leading zeros — CQP: "It is unnecessary to send leading zeros in the
    /// QSO number."
    static func exchangeNumber(serial: Int?, rst: String) -> String {
        serial.map(String.init) ?? rst
    }
}

extension String {
    func padded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }

    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
