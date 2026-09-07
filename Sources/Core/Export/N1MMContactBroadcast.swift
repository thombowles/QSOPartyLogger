import Foundation

/// N1MM Logger+'s UDP contact packets — `contactinfo`, `contactreplace`,
/// `contactdelete` — built from a row of a `ContestLog` under its
/// `ContestDefinition`, the way `AdifExporter` builds a record. This is what
/// RUMlogNG's "QSOs received from N1MM" listener saves, and what every other
/// N1MM-compatible listener on the LAN reads.
///
/// Every element, its order and its units come from N1MM's own "External
/// UDP Messages" page, banked in `docs/research/n1mm-udp-contactinfo.md`;
/// the two trailing elements (`dxcc`, `my_gridsquare`) are RUMlogNG's own,
/// from the packet it broadcasts itself. Pure: no socket, no clock, no host
/// name of its own — every packet carries the row's own time, and the
/// sending Mac's name arrives in `Station`.
enum N1MMContactBroadcast {

    /// What the sending Mac contributes to a packet.
    struct Station: Equatable, Sendable {
        /// `StationName` — "the netbios name of the station that sent this
        /// packet" (N1MM); this Mac's name.
        var stationName: String

        init(stationName: String) {
            self.stationName = stationName
        }
    }

    /// What the engine credited a row with, for `points` / `ismultiplier1`
    /// — `ScoreBreakdown.pointsByRowID` and `newMultRowIDs`, handed in by
    /// the window's fold. `none` for a row the engine did not pay.
    struct RowScoring: Equatable, Sendable {
        var points: Int
        var isNewMultiplier: Bool

        init(points: Int, isNewMultiplier: Bool) {
            self.points = points
            self.isNewMultiplier = isNewMultiplier
        }

        static let none = RowScoring(points: 0, isNewMultiplier: false)
    }

    /// One datagram: the XML text, and which packet it is and for whom, for
    /// the status line.
    struct Packet: Equatable, Sendable {
        /// The raw value is the packet's root element.
        enum Kind: String, Equatable, Sendable {
            case info = "contactinfo"
            case replace = "contactreplace"
            case delete = "contactdelete"
        }

        let kind: Kind
        let call: String
        let xml: String

        var data: Data { Data(xml.utf8) }
    }

    /// `app` — provenance, the way the POTA spot's `source` names the app.
    /// RUMlogNG's own packet carries no `app` element at all.
    static let app = "QSOPartyLogger"
    /// `contestnr` — "a unique number assigned to this contest instance in
    /// this database" (N1MM), opaque to every listener; one contest per log.
    static let contestNumber = "1"

    // MARK: Packets

    static func contactInfo(row: QSO, log: ContestLog, contest: ContestDefinition,
                            station: Station, scoring: RowScoring = .none) -> Packet {
        Packet(kind: .info, call: row.call.uppercased(),
               xml: render(.info, contact(row: row, old: row, log: log, contest: contest, station: station, scoring: scoring)))
    }

    /// The same body under `<contactreplace>`, with `oldtimestamp` /
    /// `oldcall` naming what was logged before the edit (N1MM's rule).
    static func contactReplace(row: QSO, replacing old: QSO, log: ContestLog, contest: ContestDefinition,
                               station: Station, scoring: RowScoring = .none) -> Packet {
        Packet(kind: .replace, call: row.call.uppercased(),
               xml: render(.replace, contact(row: row, old: old, log: log, contest: contest, station: station, scoring: scoring)))
    }

    /// N1MM's eight elements, exactly. Built from the row being removed —
    /// the *old* row of an edit — so the receiver matches what it holds.
    static func contactDelete(row: QSO, log: ContestLog, station: Station) -> Packet {
        Packet(kind: .delete, call: row.call.uppercased(), xml: render(.delete, [
            ("app", app),
            ("timestamp", timestamp(row.timestampUTC)),
            ("mycall", myCall(log)),
            ("band", bandToken(row.band)),
            ("call", row.call.uppercased()),
            ("contestnr", contestNumber),
            ("StationName", station.stationName),
            ("ID", id(row.id)),
        ]))
    }

    /// A document change as datagrams, in the order they must leave: one
    /// `contactinfo` per row added, one `contactdelete` per row removed,
    /// and for every edit a `contactdelete` of the old row followed by a
    /// `contactreplace` — "A <contactdelete> packet, followed by a
    /// <contactreplace> packet" (N1MM).
    static func packets(for change: QSOChange, log: ContestLog, contest: ContestDefinition,
                        station: Station, scoring: (QSO) -> RowScoring) -> [Packet] {
        switch change {
        case .added(let rows):
            return rows.map { contactInfo(row: $0, log: log, contest: contest, station: station, scoring: scoring($0)) }
        case .removed(let rows):
            return rows.map { contactDelete(row: $0, log: log, station: station) }
        case .replaced(let pairs):
            return pairs.flatMap { pair in [
                contactDelete(row: pair.old, log: log, station: station),
                contactReplace(row: pair.new, replacing: pair.old, log: log, contest: contest,
                               station: station, scoring: scoring(pair.new)),
            ] }
        }
    }

    /// Every row of the log as a fresh `contactinfo`, oldest first — the
    /// catch-up for a log made before sending was on.
    static func wholeLog(log: ContestLog, contest: ContestDefinition, station: Station,
                         scoring: (QSO) -> RowScoring) -> [Packet] {
        log.qsos.sortedChronologically().map {
            contactInfo(row: $0, log: log, contest: contest, station: station, scoring: scoring($0))
        }
    }

    // MARK: The contactinfo body, in N1MM's order

    private static func contact(row: QSO, old: QSO, log: ContestLog, contest: ContestDefinition,
                                station: Station, scoring: RowScoring) -> [(String, String)] {
        let call = row.call.uppercased()
        let my = myCall(log)
        let cty = CTYTable.shared?.match(callsign: call)
        let frequency = String(frequencyTens(row))
        let serialSent = value(.serial, in: row.sent, contest: contest)
        let serialRcvd = value(.serial, in: row.rcvd, contest: contest)
        let zone = firstNonEmpty(value(.cqZone, in: row.rcvd, contest: contest),
                                 value(.ituZone, in: row.rcvd, contest: contest))
        return [
            ("app", app),
            ("contestname", contest.cabrillo.contest),
            ("contestnr", contestNumber),
            ("timestamp", timestamp(row.timestampUTC)),
            ("mycall", my),
            ("band", bandToken(row.band)),
            ("rxfreq", frequency),
            ("txfreq", frequency),
            ("operator", my),
            ("mode", mode(row)),
            ("call", call),
            ("countryprefix", cty?.entity.primaryPrefix ?? ""),
            ("wpxprefix", WPXPrefix.of(call) ?? ""),
            ("stationprefix", my),
            ("continent", cty?.continent ?? ""),
            ("snt", report(in: row.sent, contest: contest)),
            ("sntnr", serialSent.isEmpty ? "0" : serialSent),
            ("rcv", report(in: row.rcvd, contest: contest)),
            ("rcvnr", serialRcvd.isEmpty ? "0" : serialRcvd),
            ("gridsquare", firstNonEmpty(value(.grid, in: row.rcvd, contest: contest), row.callbook?.grid ?? "")),
            ("exchange1", exchange1(row: row, contest: contest)),
            ("section", section(row: row, contest: contest)),
            ("comment", row.notes ?? ""),
            ("qth", row.callbook?.qth ?? ""),
            ("name", firstNonEmpty(value(.name, in: row.rcvd, contest: contest), row.callbook?.name ?? "")),
            ("power", power(row: row, contest: contest)),
            ("misctext", ""),
            ("zone", zone.isEmpty ? "0" : zone),
            ("prec", value(.precedence, in: row.rcvd, contest: contest)),
            ("ck", firstNonEmpty(value(.check, in: row.rcvd, contest: contest), "0")),
            ("ismultiplier1", scoring.isNewMultiplier ? "1" : "0"),
            ("ismultiplier2", "0"),
            ("ismultiplier3", "0"),
            ("points", String(scoring.points)),
            ("radionr", "1"),
            ("run1run2", "1"),
            ("RoverLocation", ""),
            ("RadioInterfaced", row.freqKHz == nil ? "0" : "1"),
            ("NetworkedCompNr", "0"),
            ("IsOriginal", "True"),
            ("NetBiosName", ""),
            ("IsRunQSO", row.posture == .run ? "1" : "0"),
            ("StationName", station.stationName),
            ("ID", id(row.id)),
            ("IsClaimedQso", "1"),
            ("oldtimestamp", timestamp(old.timestampUTC)),
            ("oldcall", old.call.uppercased()),
            ("SentExchange", sentExchange(row: row, contest: contest)),
            // RUMlogNG's own trailing elements — its packet carries `dxcc`
            // after N1MM's list, and 6.5.1 added `my_gridsquare`.
            ("dxcc", cty?.entity.entityCode.map(String.init) ?? ""),
            ("my_gridsquare", log.station.gridLocator.uppercased()),
        ]
    }

    // MARK: Field rules

    /// N1MM's band token: the band's lower edge in MHz — "3.5" for 80 m,
    /// "1.8" for 160 m (N1MM's page), "24" for 12 m (RUMlogNG's own packet)
    /// — one decimal below 7 MHz, whole megahertz above. Always a period:
    /// the comma on N1MM's page is a Windows locale, not a rule.
    static func bandToken(_ band: Band) -> String {
        let mhz = Double(band.rangeKHz.lowerBound) / 1000
        if mhz >= 7 { return String(Int(mhz)) }
        return String(format: "%.1f", (mhz * 10).rounded(.down) / 10)
    }

    /// "the frequency is exported in units of 10 Hz" — kHz × 100. A row
    /// logged without CAT sends the band's default frequency, the rule the
    /// Cabrillo line already follows.
    static func frequencyTens(_ row: QSO) -> Int {
        (row.freqKHz ?? row.band.defaultFreqKHz) * 100
    }

    /// N1MM's mode vocabulary has USB and LSB but no SSB: a row logged as
    /// "SSB" resolves to the band's conventional sideband at its frequency
    /// (`BandPlan.sidebandRawMode`, the rule the radio path uses). Every
    /// other raw mode goes out upper-cased as it is.
    static func mode(_ row: QSO) -> String {
        let raw = row.rawMode.uppercased()
        guard raw == "SSB" else { return raw }
        return BandPlan.sidebandRawMode(atKHz: Double(row.freqKHz ?? row.band.defaultFreqKHz))
    }

    /// "2020-01-17 16:43:38", UTC.
    static func timestamp(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// "a 32 byte unique GUID identifier … sent as 2 hex characters per
    /// byte": the row's UUID, dashes dropped, lower case as N1MM's example.
    /// Stable across delete and replace, so the receiver can match.
    static func id(_ uuid: UUID) -> String {
        uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(character)
            }
        }
        return out
    }

    // MARK: Exchange elements, by kind

    private static func myCall(_ log: ContestLog) -> String {
        log.station.callsign.uppercased()
    }

    /// The received or sent value of the first element of `kind` — the
    /// party elements carry the well-known ids, a general contest its own,
    /// and the kind is what both agree on.
    private static func value(_ kind: ExchangeElement.Kind, in map: [String: String],
                              contest: ContestDefinition) -> String {
        contest.exchange.first { $0.kind == kind }.flatMap { map[$0.id] } ?? ""
    }

    private static func firstNonEmpty(_ values: String...) -> String {
        values.first { !$0.isEmpty } ?? ""
    }

    /// The report: the `rst` element, or a digital `report` standing in
    /// where the contest has no RST (the ADIF exporter's rule).
    private static func report(in map: [String: String], contest: ContestDefinition) -> String {
        firstNonEmpty(value(.rst, in: map, contest: contest), value(.report, in: map, contest: contest))
    }

    /// N1MM's Exchange1 — the exchange beyond report, serial, name and
    /// section: a party's received location token (county, state, DX), or a
    /// general contest's token and class values in exchange order.
    private static func exchange1(row: QSO, contest: ContestDefinition) -> String {
        contest.exchange
            .filter { ($0.kind == .token && $0.id != "section") || $0.kind == .classToken }
            .compactMap { row.rcvd[$0.id] }
            .joined(separator: " ")
    }

    /// The `section` token element (Sweepstakes, Field Day) — "whatever the
    /// rules for the particular contest define it to mean".
    private static func section(row: QSO, contest: ContestDefinition) -> String {
        contest.exchange.first { $0.kind == .token && $0.id == "section" }.flatMap { row.rcvd[$0.id] } ?? ""
    }

    /// "the received power exchange from the other station": a `power`
    /// element, or the member-or-power element when what came was a power
    /// ("5W") — a member number is not one.
    private static func power(row: QSO, contest: ContestDefinition) -> String {
        let typed = value(.power, in: row.rcvd, contest: contest)
        if !typed.isEmpty { return typed }
        let member = value(.memberOrPower, in: row.rcvd, contest: contest)
        if !member.isEmpty, case .power = MemberExchange.parse(member) { return member }
        return ""
    }

    /// "the contents of the Sent Exchange box" — my sent exchange as this
    /// row carries it, every element but the report and the serial, in
    /// exchange order: "TX", "TOM TX", a county-line row's own county.
    private static func sentExchange(row: QSO, contest: ContestDefinition) -> String {
        contest.exchange
            .filter { ![.rst, .serial, .callEcho, .report].contains($0.kind) }
            .compactMap { row.sent[$0.id] }
            .joined(separator: " ")
    }

    // MARK: XML

    /// One element per line, tab-indented under N1MM's header — N1MM's own
    /// layout; a parser reads the names, not the whitespace.
    private static func render(_ kind: Packet.Kind, _ elements: [(String, String)]) -> String {
        var out = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<\(kind.rawValue)>\n"
        for (name, value) in elements {
            out += "\t<\(name)>\(escape(value))</\(name)>\n"
        }
        out += "</\(kind.rawValue)>"
        return out
    }
}
