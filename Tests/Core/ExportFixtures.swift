// Tests/Core/ExportFixtures.swift
import Foundation
@testable import QSOPartyLogger

/// Deterministic logs, one per party shape, for the export byte-identity
/// fixtures (`Tests/Fixtures/Exports`). Every id, timestamp and token is
/// fixed, and every token comes from the party's own data.
enum ExportFixtures {
    struct Fixture {
        let name: String
        let party: PartyDefinition
        let log: ContestLog
    }

    /// 2026-08-29 14:32:00 UTC, then +90 s per row.
    static let t0 = Date(timeIntervalSince1970: 1_788_013_920)

    static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012X", n))!
    }

    static func station(_ configure: (inout StationProfile) -> Void = { _ in }) -> StationProfile {
        var s = StationProfile()
        s.callsign = "KE5CW"; s.name = "Tom Bowles"; s.city = "Amarillo"; s.stateProvince = "TX"
        s.categoryPower = .low
        configure(&s)
        return s
    }

    /// One row; `n` fixes its id (unique per row). Rows expanded from one
    /// on-air contact share a `group` — the same group id and the same time.
    static func row(_ n: Int, call: String, band: Band = .m20, mode: ModeClass = .cw,
                    freq: Int? = 14042, rstSent: String? = nil, rstRcvd: String? = nil,
                    serialSent: Int? = nil, serialRcvd: Int? = nil,
                    nameSent: String? = nil, nameRcvd: String? = nil,
                    memberSent: String? = nil, memberRcvd: String? = nil,
                    myPotaRefs: [String]? = nil, theirPotaRefs: [String]? = nil,
                    my: String, their: String, group: Int? = nil) -> QSO {
        let raw = mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY"
        let rst = mode == .phone ? "59" : "599"
        let contact = group ?? n
        return QSO(id: uuid(n), groupID: uuid(1000 + contact), timestampUTC: t0.addingTimeInterval(Double(contact) * 90),
                   call: call, band: band, modeClass: mode, rawMode: raw, freqKHz: freq,
                   rstSent: rstSent ?? rst, rstRcvd: rstRcvd ?? rst,
                   serialSent: serialSent, serialRcvd: serialRcvd, nameSent: nameSent, nameRcvd: nameRcvd,
                   memberSent: memberSent, memberRcvd: memberRcvd,
                   myPotaRefs: myPotaRefs, theirPotaRefs: theirPotaRefs, myLoc: my, theirLoc: their)
    }

    static func party(_ id: String) throws -> PartyDefinition {
        guard let p = PartyCatalog.party(id: id) else { throw NSError(domain: "ExportFixtures", code: 1, userInfo: [NSLocalizedDescriptionKey: "no bundled party \(id)"]) }
        return p
    }

    static func all() throws -> [Fixture] {
        var out: [Fixture] = []

        // 1. KSQP, inside on a county line, an activation, a park-to-park row, a dupe.
        do {
            let p = try party("ksqp"); let c = p.counties.map(\.abbr)
            var log = ContestLog(partyID: p.id, station: station { $0.categoryStation = .mobile }, myLocation: .inState(counties: [c[0], c[1]]))
            log.myPotaRefs = ["US-3315"]
            log.qsos = [
                row(1, call: "W0BH", my: c[0], their: c[5], group: 1),
                row(2, call: "W0BH", my: c[1], their: c[5], group: 1),
                row(3, call: "N0XYZ", band: .m40, mode: .cw, freq: 7040, my: c[0], their: c[7], group: 2),
                row(4, call: "N0XYZ", band: .m40, mode: .cw, freq: 7040, my: c[0], their: c[8], group: 2),
                row(5, call: "N0XYZ", band: .m40, mode: .cw, freq: 7040, my: c[1], their: c[7], group: 2),
                row(6, call: "N0XYZ", band: .m40, mode: .cw, freq: 7040, my: c[1], their: c[8], group: 2),
                row(7, call: "K5TR", mode: .phone, freq: 14250, my: c[0], their: "TX"),
                row(8, call: "VE3ABC", band: .m40, freq: nil, my: c[0], their: "ON"),
                row(9, call: "DL1AA", my: c[0], their: "DX"),
                row(10, call: "W0BH", my: c[0], their: c[5]),                                 // dupe
                row(11, call: "K0AA", myPotaRefs: ["US-3315"], theirPotaRefs: ["US-0088"], my: c[0], their: c[9]),
            ]
            out.append(Fixture(name: "ksqp-inside-county-line", party: p, log: log))
        }
        // 2. KSQP, outside (TX): counties, an out-of-scope state, a dupe.
        do {
            let p = try party("ksqp"); let c = p.counties.map(\.abbr)
            var log = ContestLog(partyID: p.id, station: station(), myLocation: .outOfState(location: "TX"))
            log.qsos = [row(1, call: "W0BH", my: "TX", their: c[5]), row(2, call: "N0XYZ", band: .m40, freq: 7040, my: "TX", their: c[7]),
                        row(3, call: "K5TR", my: "TX", their: "OK"), row(4, call: "W0BH", my: "TX", their: c[5])]
            out.append(Fixture(name: "ksqp-outside", party: p, log: log))
        }
        // 3. KSQP, an entrant outside the US and Canada who typed a prefix as their location.
        do {
            let p = try party("ksqp"); let c = p.counties.map(\.abbr)
            var log = ContestLog(partyID: p.id, station: station { $0.callsign = "DL1QPL"; $0.stateProvince = ""; $0.country = "GERMANY" },
                                 myLocation: .outOfState(location: "DL"))
            log.qsos = [row(1, call: "W0BH", my: "DL", their: c[5]), row(2, call: "K0AA", my: "DL", their: c[6])]
            out.append(Fixture(name: "ksqp-outside-dx", party: p, log: log))
        }
        // 4. CQP, inside: serial numbers, a county line received.
        do {
            let p = try party("cqp"); let c = p.counties.map(\.abbr)
            var log = ContestLog(partyID: p.id, station: station(), myLocation: .inState(counties: [c[0]]))
            log.qsos = [row(1, call: "W0BH", serialSent: 1, serialRcvd: 12, my: c[0], their: "KS"),
                        row(2, call: "N6XYZ", serialSent: 2, serialRcvd: 7, my: c[0], their: c[3], group: 2),
                        row(3, call: "N6XYZ", serialSent: 2, serialRcvd: 7, my: c[0], their: c[4], group: 2),
                        row(4, call: "VE7ABC", mode: .phone, freq: 14250, serialSent: 3, serialRcvd: 130, my: c[0], their: "BC")]
            out.append(Fixture(name: "cqp-inside-serials", party: p, log: log))
        }
        // 5. NAQP CW: a name, one side, the entrant's own token.
        do {
            let p = try party("naqpcw"); let c = p.counties.map(\.abbr)
            var log = ContestLog(partyID: p.id, station: station(), myLocation: .outOfState(location: "TX"), exchangeName: "TOM")
            log.qsos = [row(1, call: "W0BH", nameSent: "TOM", nameRcvd: "BOB", my: "TX", their: "CA"),
                        row(2, call: "VE3ABC", band: .m40, freq: 7040, nameSent: "TOM", nameRcvd: "MARY-ANN", my: "TX", their: "ON"),
                        row(3, call: "XE1AAA", nameSent: "TOM", nameRcvd: "JOSE", my: "TX", their: c[0])]
            out.append(Fixture(name: "naqpcw-name", party: p, log: log))
        }
        // 6. Skeeter Hunt: the member-or-power element, blank for a QRO station.
        do {
            let p = try party("skeeter")
            var log = ContestLog(partyID: p.id, station: station { $0.categoryStation = .portable }, myLocation: .outOfState(location: "TX"),
                                 exchangeMember: "13", entryClassID: p.entryClasses.first?.id ?? "")
            log.qsos = [row(1, call: "W2LJ", memberSent: "13", memberRcvd: "1", my: "TX", their: "NJ"),
                        row(2, call: "K3WWP", memberSent: "13", memberRcvd: "5W", my: "TX", their: "PA"),
                        row(3, call: "VE3ABC", memberSent: "13", memberRcvd: nil, my: "TX", their: "ON"),
                        row(4, call: "DL1AA", memberSent: "13", memberRcvd: "100W", my: "TX", their: "DL")]
            out.append(Fixture(name: "skeeter-member", party: p, log: log))
        }
        // 7. PAQP, inside: sections, serials, granted EPA/WPA, the DX token.
        do {
            let p = try party("paqp"); let c = p.counties.map(\.abbr); let s = p.sections.sorted()
            var log = ContestLog(partyID: p.id, station: station(), myLocation: .inState(counties: [c[0]]))
            log.qsos = [row(1, call: "W0BH", serialSent: 1, serialRcvd: 3, my: c[0], their: s[0]),
                        row(2, call: "K3LR", serialSent: 2, serialRcvd: 44, my: c[0], their: c[2]),
                        row(3, call: "DL1AA", serialSent: 3, serialRcvd: 9, my: c[0], their: "DX"),
                        row(4, call: "VE3ABC", serialSent: 4, serialRcvd: 21, my: c[0], their: s[1])]
            out.append(Fixture(name: "paqp-inside-sections", party: p, log: log))
        }
        // 8. 7QP, inside: eight member states, LOCATION headers the primary state.
        do {
            let p = try party("sevenqp"); let c = p.counties.map(\.abbr)
            let last = c[c.count - 1]
            var log = ContestLog(partyID: p.id, station: station(), myLocation: .inState(counties: [last]))
            log.qsos = [row(1, call: "W0BH", my: last, their: c[0]), row(2, call: "K7ABC", my: last, their: c[10]),
                        row(3, call: "K5TR", my: last, their: "TX"), row(4, call: "VE7ABC", my: last, their: "BC")]
            out.append(Fixture(name: "sevenqp-inside-multistate", party: p, log: log))
        }
        // 9. Salmon Run, inside: DX prefixes, the colliding tokens both ways, a province.
        do {
            let p = try party("warun"); let c = p.counties.map(\.abbr)
            var log = ContestLog(partyID: p.id, station: station(), myLocation: .inState(counties: [c[0]]))
            log.qsos = [row(1, call: "PA0AAA", my: c[0], their: "PA"), row(2, call: "W3XYZ", my: c[0], their: "PA"),
                        row(3, call: "DL1EEE", my: c[0], their: "DL"), row(4, call: "VE5ABC", my: c[0], their: "SK"),
                        row(5, call: "W7ABC", band: .m40, freq: 7040, my: c[0], their: c[3])]
            out.append(Fixture(name: "warun-inside-prefix-dx", party: p, log: log))
        }
        // 10. MDC, inside: no report in the exchange — the line still carries one today.
        do {
            let p = try party("mdc"); let c = p.counties.map(\.abbr)
            var log = ContestLog(partyID: p.id, station: station(), myLocation: .inState(counties: [c[0]]))
            log.qsos = [row(1, call: "W3XYZ", my: c[0], their: "PA"), row(2, call: "K3LR", my: c[0], their: c[1]),
                        row(3, call: "VE3ABC", mode: .phone, freq: 14250, my: c[0], their: "ON")]
            out.append(Fixture(name: "mdc-inside-no-rst", party: p, log: log))
        }
        return out
    }
}
