import XCTest
@testable import QSOPartyLogger

/// The log's changes as datagrams to RUMlogNG — through a recording socket;
/// nothing here touches the network.
@MainActor
final class QSOBroadcasterTests: XCTestCase {

    /// Records datagrams; can refuse them the way the kernel does.
    final class RecordingUDP: UDPSending, @unchecked Sendable {
        let localPort: UInt16 = 51234
        let localDescription = "10.0.0.7:51234"
        private let lock = NSLock()
        private var stored: [Data] = []
        private var failures = 0
        private var closes = 0
        private var refusing = false
        var refuse: Bool {
            get { lock.withLock { refusing } }
            set { lock.withLock { refusing = newValue } }
        }
        var closed: Int { lock.withLock { closes } }
        var sendFailures: (count: Int, lastErrno: Int32?) {
            lock.withLock { (failures, failures > 0 ? EHOSTUNREACH : nil) }
        }
        var sent: [Data] { lock.withLock { stored } }
        var sentXML: [String] { sent.map { String(decoding: $0, as: UTF8.self) } }
        func send(_ data: Data) {
            lock.withLock {
                if refusing { failures += 1 } else { stored.append(data) }
            }
        }
        func close() { lock.withLock { closes += 1 } }
    }

    final class Factory {
        var made: [(host: String, port: UInt16)] = []
        var sockets: [RecordingUDP] = []
        var failWith: Error?
        func make(_ host: String, _ port: UInt16) throws -> any UDPSending {
            made.append((host, port))
            if let failWith { throw failWith }
            let socket = RecordingUDP()
            sockets.append(socket)
            return socket
        }
    }

    let t0 = Date(timeIntervalSince1970: 1_788_013_920)
    var ksqp: ContestDefinition { ContestCatalog.contest(id: "ksqp")! }

    func broadcaster(_ factory: Factory, enabled: Bool = true) -> QSOBroadcaster {
        let b = QSOBroadcaster()
        b.makeSender = factory.make
        b.stationName = "SHACK-MAC"
        b.pacing = .zero
        b.now = { self.t0 }
        b.configure(.init(enabled: enabled, host: "127.0.0.1", port: 12060))
        return b
    }

    func log(_ rows: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        log.qsos = rows
        return log
    }

    func row(_ call: String, at offset: TimeInterval = 0) -> QSO {
        QSO(timestampUTC: t0.addingTimeInterval(offset), call: call, band: .m20, modeClass: .cw, rawMode: "CW",
            freqKHz: 14042, rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "MRN")
    }

    let noScore: (QSO) -> N1MMContactBroadcast.RowScoring = { _ in .none }

    func calls(in xml: [String]) -> [String] {
        xml.compactMap { text in
            guard let start = text.range(of: "<call>")?.upperBound,
                  let end = text.range(of: "</call>")?.lowerBound else { return nil }
            return String(text[start..<end])
        }
    }

    // MARK: Off

    func testOffSendsNothingAndOpensNothing() async {
        let f = Factory()
        let b = broadcaster(f, enabled: false)
        b.handle(.added([row("W0BH")]), log: log([row("W0BH")]), contest: ksqp, scoring: noScore)
        b.sendWholeLog(log: log([row("W0BH")]), contest: ksqp, scoring: noScore)
        await b.flush()
        XCTAssertTrue(f.made.isEmpty)
        XCTAssertEqual(b.status, .off)
    }

    /// The scoring closure reads the engine's fold; a disabled broadcaster
    /// must not ask for it.
    func testOffNeverAsksForTheScore() async {
        let f = Factory()
        let b = broadcaster(f, enabled: false)
        var asked = 0
        b.handle(.added([row("W0BH")]), log: log([row("W0BH")]), contest: ksqp, scoring: { _ in asked += 1; return .none })
        await b.flush()
        XCTAssertEqual(asked, 0)
    }

    // MARK: On

    func testTheSocketOpensLazilyToTheConfiguredHostAndPort() async {
        let f = Factory()
        let b = broadcaster(f)
        XCTAssertTrue(f.made.isEmpty, "nothing opens until there is something to send")
        XCTAssertEqual(b.status, .ready(destination: "127.0.0.1:12060"))
        b.handle(.added([row("W0BH")]), log: log([row("W0BH")]), contest: ksqp, scoring: noScore)
        await b.flush()
        XCTAssertEqual(f.made.count, 1)
        XCTAssertEqual(f.made.first?.host, "127.0.0.1")
        XCTAssertEqual(f.made.first?.port, 12060)
    }

    func testEachRowAddedIsOneContactInfoDatagram() async {
        let f = Factory()
        let b = broadcaster(f)
        let rows = [row("W0BH"), row("N0XYZ", at: 90)]
        b.handle(.added(rows), log: log(rows), contest: ksqp,
                 scoring: { $0.call == "W0BH" ? .init(points: 2, isNewMultiplier: true) : .none })
        await b.flush()
        let xml = f.sockets[0].sentXML
        XCTAssertEqual(xml.count, 2)
        XCTAssertTrue(xml[0].hasPrefix("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<contactinfo>"))
        XCTAssertTrue(xml[0].contains("<call>W0BH</call>"))
        XCTAssertTrue(xml[0].contains("<points>2</points>"))
        XCTAssertTrue(xml[1].contains("<call>N0XYZ</call>"))
        XCTAssertEqual(b.status, .sent(count: 2, lastCall: "N0XYZ", at: t0, destination: "127.0.0.1:12060"))
    }

    func testAnEditIsADeleteThenAReplaceAndADeleteIsADelete() async {
        let f = Factory()
        let b = broadcaster(f)
        let old = row("W0BH")
        var new = old
        new.theirLoc = "BOU"
        b.handle(.replaced([.init(old: old, new: new)]), log: log([new]), contest: ksqp, scoring: noScore)
        b.handle(.removed([new]), log: log([]), contest: ksqp, scoring: noScore)
        await b.flush()
        let xml = f.sockets[0].sentXML
        XCTAssertEqual(xml.count, 3)
        XCTAssertTrue(xml[0].contains("<contactdelete>"))
        XCTAssertTrue(xml[1].contains("<contactreplace>"))
        XCTAssertTrue(xml[1].contains("<exchange1>BOU</exchange1>"))
        XCTAssertTrue(xml[2].contains("<contactdelete>"))
    }

    func testTheStationNameIsThisMacs() async {
        let f = Factory()
        let b = broadcaster(f)
        b.handle(.added([row("W0BH")]), log: log([row("W0BH")]), contest: ksqp, scoring: noScore)
        await b.flush()
        XCTAssertTrue(f.sockets[0].sentXML[0].contains("<StationName>SHACK-MAC</StationName>"))
    }

    // MARK: The whole log

    func testTheWholeLogGoesOldestFirstAndTheStatusCountsIt() async {
        let f = Factory()
        let b = broadcaster(f)
        let rows = [row("W0BH", at: 90), row("N0XYZ", at: 0), row("K5TR", at: 180)]
        b.sendWholeLog(log: log(rows), contest: ksqp, scoring: noScore)
        XCTAssertEqual(b.status, .sending(done: 0, total: 3))
        XCTAssertTrue(b.isSendingWholeLog)
        await b.flush()
        XCTAssertEqual(calls(in: f.sockets[0].sentXML), ["N0XYZ", "W0BH", "K5TR"])
        XCTAssertFalse(b.isSendingWholeLog)
        XCTAssertEqual(b.status, .sent(count: 3, lastCall: "K5TR", at: t0, destination: "127.0.0.1:12060"))
    }

    func testASecondPressStopsAWholeLogSendAndKeepsLiveChanges() async {
        let f = Factory()
        let b = broadcaster(f)
        b.pacing = .seconds(10)   // the first packet goes, then the drain waits
        let rows = (1...5).map { row("K\($0)AA", at: Double($0)) }
        b.sendWholeLog(log: log(rows), contest: ksqp, scoring: noScore)
        b.handle(.added([row("W0BH")]), log: log(rows), contest: ksqp, scoring: noScore)
        b.sendWholeLog(log: log(rows), contest: ksqp, scoring: noScore)   // Stop
        XCTAssertFalse(b.isSendingWholeLog)
        b.pacing = .zero
        b.configure(.init(enabled: true, host: "127.0.0.1", port: 12061))  // reopens; the live packet is still queued
        await b.flush()
        let sent = calls(in: f.sockets.flatMap(\.sentXML))
        XCTAssertTrue(sent.contains("W0BH"), "the live change survives Stop: \(sent)")
        XCTAssertFalse(sent.contains("K5AA"), "the tail of the whole-log send was dropped: \(sent)")
    }

    func testAnEmptyLogSendsNothing() async {
        let f = Factory()
        let b = broadcaster(f)
        b.sendWholeLog(log: log([]), contest: ksqp, scoring: noScore)
        await b.flush()
        XCTAssertTrue(f.made.isEmpty)
        XCTAssertFalse(b.isSendingWholeLog)
    }

    // MARK: Configuration

    func testAChangedDestinationClosesTheSocketAndTheNextPacketReopens() async {
        let f = Factory()
        let b = broadcaster(f)
        b.handle(.added([row("W0BH")]), log: log([row("W0BH")]), contest: ksqp, scoring: noScore)
        await b.flush()
        b.configure(.init(enabled: true, host: "10.0.0.9", port: 12060))
        XCTAssertEqual(f.sockets[0].closed, 1)
        b.handle(.added([row("N0XYZ")]), log: log([row("N0XYZ")]), contest: ksqp, scoring: noScore)
        await b.flush()
        XCTAssertEqual(f.made.map(\.host), ["127.0.0.1", "10.0.0.9"])
        XCTAssertEqual(f.sockets[1].sentXML.count, 1)
    }

    func testTurningOffClosesTheSocketAndDropsTheQueue() async {
        let f = Factory()
        let b = broadcaster(f)
        b.handle(.added([row("K5TR")]), log: log([row("K5TR")]), contest: ksqp, scoring: noScore)
        await b.flush()
        b.pacing = .seconds(10)
        b.sendWholeLog(log: log([row("W0BH"), row("N0XYZ", at: 1)]), contest: ksqp, scoring: noScore)
        b.configure(.init(enabled: false, host: "127.0.0.1", port: 12060))
        await b.flush()
        XCTAssertEqual(b.status, .off)
        XCTAssertFalse(b.isSendingWholeLog)
        XCTAssertEqual(f.sockets[0].closed, 1)
        XCTAssertLessThanOrEqual(f.sockets[0].sent.count, 2, "the live packet, and at most one of the whole log")
        XCTAssertFalse(calls(in: f.sockets[0].sentXML).contains("N0XYZ"), "the tail never leaves after Off")
    }

    /// Off before the drain has run at all: nothing opens, nothing leaves.
    func testTurningOffBeforeAnythingLeftOpensNoSocket() async {
        let f = Factory()
        let b = broadcaster(f)
        b.sendWholeLog(log: log([row("W0BH"), row("N0XYZ", at: 1)]), contest: ksqp, scoring: noScore)
        b.configure(.init(enabled: false, host: "127.0.0.1", port: 12060))
        await b.flush()
        XCTAssertTrue(f.made.isEmpty)
        XCTAssertEqual(b.status, .off)
        XCTAssertFalse(b.isSendingWholeLog)
    }

    func testTheSameConfigurationChangesNothing() async {
        let f = Factory()
        let b = broadcaster(f)
        b.handle(.added([row("W0BH")]), log: log([row("W0BH")]), contest: ksqp, scoring: noScore)
        await b.flush()
        b.configure(.init(enabled: true, host: "127.0.0.1", port: 12060))
        XCTAssertEqual(f.sockets[0].closed, 0)
    }

    // MARK: Failure, inline

    func testAHostThatCannotBeOpenedIsReportedInItsOwnWordsAndTheQueueIsDropped() async {
        let f = Factory()
        f.failWith = UDPSender.UDPError.resolve("rumlog.local")
        let b = broadcaster(f)
        b.sendWholeLog(log: log([row("W0BH"), row("N0XYZ", at: 1)]), contest: ksqp, scoring: noScore)
        await b.flush()
        XCTAssertEqual(b.status, .failed("Could not resolve rumlog.local."))
        XCTAssertFalse(b.isSendingWholeLog)
        XCTAssertEqual(f.made.count, 1, "one attempt per burst, not one per packet")
    }

    func testARefusedDatagramIsReportedAndSendingGoesOn() async {
        let f = Factory()
        let b = broadcaster(f)
        b.handle(.added([row("W0BH")]), log: log([row("W0BH")]), contest: ksqp, scoring: noScore)
        await b.flush()
        f.sockets[0].refuse = true
        b.handle(.added([row("N0XYZ")]), log: log([row("N0XYZ")]), contest: ksqp, scoring: noScore)
        await b.flush()
        guard case .failed(let why) = b.status else { return XCTFail("\(b.status)") }
        XCTAssertTrue(why.hasPrefix("Send failed: "), why)
        f.sockets[0].refuse = false
        b.handle(.added([row("K5TR")]), log: log([row("K5TR")]), contest: ksqp, scoring: noScore)
        await b.flush()
        XCTAssertEqual(b.status, .sent(count: 2, lastCall: "K5TR", at: t0, destination: "127.0.0.1:12060"))
    }

    func testALogWithNoRulesInstalledIsReportedNotSent() async {
        let f = Factory()
        let b = broadcaster(f)
        b.handle(.added([row("W0BH")]), log: log([row("W0BH")]), contest: nil, scoring: noScore)
        await b.flush()
        XCTAssertTrue(f.made.isEmpty)
        XCTAssertEqual(b.status, .failed("No contest rules installed for ksqp — nothing sent."))
    }

    // MARK: The status line

    func testStatusText() {
        XCTAssertEqual(QSOBroadcaster.Status.off.text, "Off — nothing is sent.")
        XCTAssertEqual(QSOBroadcaster.Status.ready(destination: "127.0.0.1:12060").text,
                       "Ready — 127.0.0.1:12060. Nothing sent yet this session.")
        XCTAssertEqual(QSOBroadcaster.Status.sent(count: 12, lastCall: "W0BH", at: t0, destination: "127.0.0.1:12060").text,
                       "Sent W0BH at 14:32:00z to 127.0.0.1:12060 · 12 this session")
        XCTAssertEqual(QSOBroadcaster.Status.sending(done: 143, total: 2012).text, "Sending 143 of 2,012…")
        XCTAssertEqual(QSOBroadcaster.Status.failed("Could not resolve x.").text, "Could not resolve x.")
        XCTAssertTrue(QSOBroadcaster.Status.failed("x").isFailure)
        XCTAssertFalse(QSOBroadcaster.Status.off.isFailure)
    }
}
