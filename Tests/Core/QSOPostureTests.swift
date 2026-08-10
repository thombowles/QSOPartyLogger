import XCTest
@testable import QSOPartyLogger

/// `QSO.posture` — the one additive log field the advisor needs, and the
/// three proofs that it changes nothing else.
///
/// It records whether a contact was made running or searching, stamped from
/// the same Run/S&P flag that already picks the message set. Nothing scores on
/// it and no export carries it; it exists so the advisor can say what running
/// on 40 m has actually paid tonight from the operator's own log rather than
/// from a rule of thumb.
final class QSOPostureTests: XCTestCase {

    private func qso(
        call: String = "W0BH", band: Band = .m20, mode: ModeClass = .cw,
        their: String = "MRN", posture: OperatingMode? = nil
    ) -> QSO {
        QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_770_000_000),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : "CW",
            freqKHz: 14_040,
            rstSent: "599", rstRcvd: "599",
            myLoc: "TX", theirLoc: their, posture: posture
        )
    }

    private func log(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        log.qsos = qsos
        return log
    }

    // MARK: Additive

    /// A log written by any build before this field decodes with `nil` — the
    /// same promise `nameRcvd` and the POTA fields make.
    func testLogsWrittenBeforePostureSupportDecodeUnchanged() throws {
        let data = try log([qso(posture: .run)]).encoded()
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var qsos = try XCTUnwrap(json["qsos"] as? [[String: Any]])
        XCTAssertNotNil(qsos[0]["posture"], "today's encoding carries the key")
        qsos[0].removeValue(forKey: "posture")
        json["qsos"] = qsos
        let legacy = try JSONSerialization.data(withJSONObject: json)

        let decoded = try ContestLog.decode(from: legacy)
        XCTAssertNil(decoded.qsos[0].posture)
        // And nothing else moved.
        XCTAssertEqual(decoded.qsos[0].call, "W0BH")
        XCTAssertEqual(decoded.qsos[0].theirLoc, "MRN")
    }

    /// An unstamped row is absent from the encoding entirely, so a log made
    /// wholly of them is byte-identical to what an older build wrote.
    func testAnUnstampedRowWritesNoKeyAtAll() throws {
        let data = try log([qso()]).encoded()
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let qsos = try XCTUnwrap(json["qsos"] as? [[String: Any]])
        XCTAssertNil(qsos[0]["posture"])
    }

    func testAStampedRowRoundTripsThroughTheDocumentEncoding() throws {
        let original = log([qso(call: "W0BH", posture: .run),
                            qso(call: "K5TR", posture: .searchPounce),
                            qso(call: "N5NA", posture: nil)])
        let decoded = try ContestLog.decode(from: try original.encoded())
        XCTAssertEqual(decoded.qsos.map(\.posture), [.run, .searchPounce, nil])
    }

    /// A value the enum does not know must not take the whole log down with
    /// it — a hand-edited file or a future spelling has to stay openable.
    func testAnUnreadablePostureIsRefusedRatherThanTakingTheLogDown() throws {
        let data = try log([qso(posture: .run)]).encoded()
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var qsos = try XCTUnwrap(json["qsos"] as? [[String: Any]])
        qsos[0]["posture"] = "Mult-hunting"
        json["qsos"] = qsos
        let mangled = try JSONSerialization.data(withJSONObject: json)

        // Documented behaviour rather than an aspiration: the synthesized
        // decoder rejects an unknown raw value. If that is ever softened to a
        // silent nil, this test is where the decision gets made on purpose.
        XCTAssertThrowsError(try ContestLog.decode(from: mangled))
    }

    // MARK: Nothing reads it

    /// Scoring is a pure function of the rules and the rest of the row. If a
    /// posture could move a score, the field would be a rule rather than a
    /// note.
    func testScoringIsIdenticalWithAndWithoutTheStamp() throws {
        let party = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        let rows = [qso(call: "W0BH", their: "MRN"),
                    qso(call: "K0XX", band: .m40, their: "JOH"),
                    qso(call: "N0YY", band: .m40, mode: .phone, their: "SED")]
        let bare = ScoreEngine.score(log: log(rows), party: party)

        let stamped = rows.enumerated().map { index, row -> QSO in
            var copy = row
            copy.posture = index.isMultiple(of: 2) ? .run : .searchPounce
            return copy
        }
        XCTAssertEqual(ScoreEngine.score(log: log(stamped), party: party), bare)
    }

    /// Cabrillo and ADIF are what the sponsor and the world see. Neither may
    /// gain a byte because the operator was running.
    func testNeitherCabrilloNorAdifChangesByItsPresence() throws {
        let party = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        let rows = [qso(call: "W0BH", their: "MRN"),
                    qso(call: "K0XX", band: .m40, their: "JOH")]
        var bareLog = log(rows)
        bareLog.myLocation = .outOfState(location: "TX")

        var stampedLog = bareLog
        stampedLog.qsos = rows.map { row in
            var copy = row
            copy.posture = .run
            return copy
        }

        XCTAssertEqual(
            CabrilloExporter.export(log: stampedLog, party: party,
                                    score: ScoreEngine.score(log: stampedLog, party: party)),
            CabrilloExporter.export(log: bareLog, party: party,
                                    score: ScoreEngine.score(log: bareLog, party: party))
        )
        XCTAssertEqual(
            AdifExporter.export(log: stampedLog, party: party),
            AdifExporter.export(log: bareLog, party: party)
        )
        XCTAssertFalse(
            AdifExporter.export(log: stampedLog, party: party).uppercased().contains("POSTURE")
        )
    }

    // MARK: One contact, one posture

    /// A county-line contact is still one contact, made in one posture,
    /// however many rows it expands into — the same law the serial, the name
    /// and the park set already follow.
    func testEveryRowOfACountyLineContactCarriesTheSamePosture() {
        let rows = CountyLineExpander.expand(
            entry: .init(
                call: "W0BH", rstSent: "599", rstRcvd: "599",
                band: .m20, modeClass: .cw, rawMode: "CW", freqKHz: 14_040,
                timestampUTC: Date(timeIntervalSince1970: 1_770_000_000),
                posture: .searchPounce
            ),
            myLocs: ["TX"],
            theirLocs: ["MRN", "JOH"]
        )
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.map(\.posture)), [.searchPounce])
        XCTAssertEqual(Set(rows.map(\.groupID)).count, 1)
    }

    /// The expander's default keeps every existing caller — and every test
    /// that builds a contact without one — stamping nothing.
    func testTheExpanderStampsNothingUnlessAsked() {
        let rows = CountyLineExpander.expand(
            entry: .init(
                call: "W0BH", rstSent: "599", rstRcvd: "599",
                band: .m20, modeClass: .cw, rawMode: "CW", freqKHz: nil,
                timestampUTC: Date(timeIntervalSince1970: 1_770_000_000)
            ),
            myLocs: ["TX"], theirLocs: ["MRN"]
        )
        XCTAssertNil(rows[0].posture)
    }
}
