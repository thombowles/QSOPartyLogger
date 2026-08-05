import Foundation

/// Cabrillo V3 export. County-line contacts arrive pre-expanded as separate
/// rows, so each emits its own QSO line with its own sent county — the format
/// QSO party sponsors (and N1MM) expect.
enum CabrilloExporter {

    static let creator = "QSO Party Logger 1.0"

    static func export(log: ContestLog, party: PartyDefinition, score: ScoreEngine.ScoreBreakdown) -> String {
        var lines: [String] = []
        let s = log.station

        lines.append("START-OF-LOG: 3.0")
        lines.append("CREATED-BY: \(creator)")
        lines.append("CONTEST: \(party.cabrilloContest)")
        lines.append("CALLSIGN: \(s.callsign.uppercased())")
        lines.append("LOCATION: \(cabrilloLocation(log: log, party: party))")
        lines.append("CATEGORY-OPERATOR: \(s.categoryOperator.rawValue)")
        lines.append("CATEGORY-ASSISTED: \(s.categoryAssisted.rawValue)")
        lines.append("CATEGORY-BAND: ALL")
        lines.append("CATEGORY-MODE: \(categoryMode(log.qsos))")
        lines.append("CATEGORY-POWER: \(s.categoryPower.rawValue)")
        lines.append("CATEGORY-STATION: \(s.categoryStation.rawValue)")
        lines.append("CATEGORY-TRANSMITTER: \(s.categoryTransmitter.rawValue)")
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

        let myCall = s.callsign.uppercased()
        for q in log.qsos.sortedChronologically() {
            lines.append(qsoLine(q, myCall: myCall))
        }
        lines.append("END-OF-LOG:")
        return lines.joined(separator: "\n") + "\n"
    }

    /// In-state logs use the party state; out-of-state use the operator's
    /// state/province — or, for a party with no home region, whatever token
    /// the entrant sends. "DX" for entrants outside US/Canada.
    static func cabrilloLocation(log: ContestLog, party: PartyDefinition) -> String {
        let token = log.myLocation.entrantToken(party: party)
        return token.isEmpty ? "DX" : token
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

    static func qsoLine(_ q: QSO, myCall: String) -> String {
        let freq = String(q.freqKHz ?? q.band.defaultFreqKHz)
        let mode = cabrilloMode(q.rawMode)
        let when = dateFormatter.string(from: q.timestampUTC)
        return "QSO: "
            + freq.leftPadded(to: 5) + " "
            + mode.padded(to: 2) + " "
            + when + " "
            + myCall.padded(to: 13) + " "
            + exchangeElement(name: q.nameSent, serial: q.serialSent, rst: q.rstSent).padded(to: 3) + " "
            + q.myLoc.uppercased().padded(to: 6)
            + memberColumn(q.memberSent) + " "
            + q.call.uppercased().padded(to: 13) + " "
            + exchangeElement(name: q.nameRcvd, serial: q.serialRcvd, rst: q.rstRcvd).padded(to: 3) + " "
            + q.theirLoc.uppercased().padded(to: 6)
            + memberColumn(q.memberRcvd)
    }

    /// The member-number-or-power column, trailing each side's location the
    /// way the sponsor's exchange does ("559 NJ NR 13" → `... 559 NJ  13`).
    /// Row-driven like `exchangeElement`, and empty rows append nothing at
    /// all, so every existing party's lines stay byte-identical.
    private static func memberColumn(_ member: String?) -> String {
        guard let member, !member.isEmpty else { return "" }
        return " " + member.uppercased().padded(to: 3)
    }

    /// The ex1 element: name → QSO number → signal report, driven by the
    /// row's own data rather than by the party, so the exporter cannot
    /// disagree with the log. A name owns the slot wherever it exists —
    /// NAQP's and MNQP's own log templates put it there (`AC0W BILL MOW`) —
    /// and no bundled party carries more than one of the three.
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
